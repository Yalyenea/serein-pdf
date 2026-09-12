import AppKit
import PDFKit

/// Owns reader-local annotation UI while leaving navigation and highlight creation to the reader.
@MainActor
final class ReaderAnnotationInteractionController: NSObject {
    var activeSessionID: UUID?
    var onFocusRequested: (() -> Void)?
    var onRevealRequested: ((DocumentHighlightGroup) -> Void)?
    var onCreateMarkupRequested: ((AnnotationMarkupType) -> DocumentHighlightGroup?)?
    var onNavigateRequested: ((DocumentHighlightGroup) -> Void)?
    var onSendSelectionToCodexRequested: ((String) -> Void)?
    var onSendPageImageToCodexRequested: ((NSImage, Int) -> Void)?
    var shouldSuppressPreview: ((String) -> Bool)?

    private let documentStore: DocumentStore
    private let pdfView: ReaderPDFView
    private weak var hostView: NSView?
    private let focusPulseView = AnnotationFocusPulseView()

    private var pendingFocusToken = 0
    private weak var hoveredAnnotation: PDFAnnotation?
    private var hoveredGroup: DocumentHighlightGroup?
    private var lastHoveredGroup: DocumentHighlightGroup?
    private var lastHoveredAt: Date?
    private var contextGroup: DocumentHighlightGroup?
    private var previewShowWorkItem: DispatchWorkItem?
    private var previewHideWorkItem: DispatchWorkItem?
    private var isPointerOverCard = false
    private var focusHideWorkItem: DispatchWorkItem?
    private var commentEditorPanel: AnnotationCommentPanel?
    private var presentedGroup: DocumentHighlightGroup?

    init(documentStore: DocumentStore, pdfView: ReaderPDFView) {
        self.documentStore = documentStore
        self.pdfView = pdfView
        super.init()
        focusPulseView.isHidden = true
    }

    func install(in hostView: NSView) {
        self.hostView = hostView
        hostView.addSubview(focusPulseView)
    }

    func layoutOverlay() {
        if let presentedGroup {
            commentEditorPanel?.updateAnchor(commentAnchorRect(for: presentedGroup))
        }
    }

    func refreshThemeAppearance() {
        commentEditorPanel?.refreshThemeAppearance()
    }

    func handlePointerMoved(_ event: NSEvent?) {
        guard commentEditorPanel?.editor.isEditing != true else { return }
        guard let event, let hit = annotationHit(at: event.locationInWindow) else {
            if let hoveredGroup {
                lastHoveredGroup = hoveredGroup
                lastHoveredAt = Date()
            }
            schedulePreviewHide()
            return
        }

        cancelPendingHide()

        lastHoveredGroup = hit.group
        lastHoveredAt = Date()

        let annotationChanged = hoveredAnnotation !== hit.annotation
        let contentChanged = hoveredGroup?.comment != hit.group.comment
            || hoveredGroup?.snippet != hit.group.snippet
        guard annotationChanged || contentChanged || (commentEditorPanel == nil && previewShowWorkItem == nil) else { return }

        hoveredAnnotation = hit.annotation
        hoveredGroup = hit.group

        guard hit.group.normalizedComment.isEmpty == false else {
            cancelPendingPreview()
            dismissCommentEditor()
            return
        }

        if shouldSuppressPreview?(hit.group.groupID) == true {
            cancelPendingPreview()
            dismissCommentEditor()
            return
        }

        cancelPendingPreview()
        if presentedGroup?.groupID == hit.group.groupID && contentChanged == false { return }
        dismissCommentEditor()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.hoveredAnnotation === hit.annotation,
                      self.hoveredGroup?.groupID == hit.group.groupID else { return }
                self.previewShowWorkItem = nil
                self.showCommentCard(for: hit.group, editing: false)
            }
        }
        previewShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    func makeContextMenu(for event: NSEvent) -> NSMenu? {
        guard let session = activeSession(), session.isBlank == false else { return nil }

        onFocusRequested?()
        let hit = annotationHit(at: event.locationInWindow)
        contextGroup = hit?.group
        let selectedText = pdfView.currentSelection?.string
            .map(PDFTextSanitizer.sanitize)
            .flatMap { $0.isEmpty ? nil : $0 }
        let hasSelection = selectedText != nil

        let menu = NSMenu(title: "Reader")
        menu.autoenablesItems = false

        if hit != nil {
            let copyItem = NSMenuItem(
                title: "Copy Annotation Snippet",
                action: #selector(copyContext(_:)),
                keyEquivalent: "c"
            )
            copyItem.target = self
            copyItem.keyEquivalentModifierMask = [.command]
            menu.addItem(copyItem)
            menu.addItem(.separator())
        }

        for command in ShortcutCommand.allCases {
            guard let type = command.annotationMarkupType else { continue }
            menu.addItem(
                contextMenuItem(
                    title: "\(type.modeTitle) Selection",
                    command: command,
                    action: #selector(markupContext(_:)),
                    isEnabled: hasSelection
                )
            )
        }
        menu.addItem(
            contextMenuItem(
                title: hit == nil ? "Add Comment" : "Edit Comment",
                command: .addComment,
                action: #selector(editContextComment(_:)),
                isEnabled: hasSelection || hit != nil
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            contextMenuItem(
                title: ShortcutCommand.removeHighlight.menuTitle,
                command: .removeHighlight,
                action: #selector(removeContextHighlight(_:)),
                isEnabled: hit != nil
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            contextMenuItem(
                title: ShortcutCommand.copyCurrentPageAsImage.menuTitle,
                command: .copyCurrentPageAsImage,
                action: #selector(copyCurrentPageAsImage(_:)),
                isEnabled: pdfView.currentPage != nil
            )
        )
        if documentStore.appConfiguration.integrations.codexEnabled {
            let sendItem = contextMenuItem(
                title: hasSelection ? "Send Selection to Codex" : "Send Page Image to Codex",
                command: .sendContextToCodex,
                action: #selector(sendContextToCodex(_:)),
                isEnabled: hasSelection || pdfView.currentPage != nil
            )
            sendItem.representedObject = selectedText
            menu.addItem(sendItem)
        }
        return menu
    }

    func activateAnnotation(at event: NSEvent) -> Bool {
        guard let hit = annotationHit(at: event.locationInWindow),
              event.clickCount == 2 || hit.isCommentIcon else { return false }
        onFocusRequested?()
        presentCommentEditor(for: hit.group, navigate: false)
        return true
    }

    @discardableResult
    func addOrEditComment() -> Bool {
        if let createdGroup = onCreateMarkupRequested?(.highlight) {
            presentCommentEditor(for: createdGroup, navigate: false)
            return true
        }
        if let pointInWindow = hostView?.window?.mouseLocationOutsideOfEventStream,
           let group = annotationHit(at: pointInWindow)?.group {
            presentCommentEditor(for: group, navigate: false)
            return true
        }
        if let hoveredGroup {
            presentCommentEditor(for: hoveredGroup, navigate: false)
            return true
        }
        if let lastHoveredGroup,
           let lastHoveredAt,
           Date().timeIntervalSince(lastHoveredAt) < 0.45 {
            presentCommentEditor(for: lastHoveredGroup, navigate: false)
            return true
        }
        return false
    }

    func presentCommentEditor(for group: DocumentHighlightGroup, navigate: Bool = true) {
        if let panel = commentEditorPanel, presentedGroup?.groupID == group.groupID {
            cancelPendingPreview()
            cancelPendingHide()
            panel.beginEditing()
            return
        }
        clearPreview()
        dismissCommentEditor()

        if navigate {
            onNavigateRequested?(group)
            showFocusPulse(for: group)
        }
        showCommentCard(for: group, editing: true)
    }

    private func showCommentCard(for group: DocumentHighlightGroup, editing: Bool) {
        guard let session = activeSession(), let hostView else { return }

        let editor = AnnotationCommentEditorViewController(group: group)
        editor.onSave = { [weak self] comment in
            guard let self else { return }
            _ = self.documentStore.updateComment(
                comment,
                forHighlightGroup: group.groupID,
                in: session.id
            )
            self.dismissCommentEditor()
        }
        editor.onCancel = { [weak self] in
            self?.dismissCommentEditor()
        }

        let panel = AnnotationCommentPanel(editor: editor)
        panel.onHoverChanged = { [weak self] hovered in
            guard let self else { return }
            self.isPointerOverCard = hovered
            if hovered {
                self.cancelPendingHide()
            } else {
                self.schedulePreviewHide()
            }
        }
        panel.onBeginEditing = { [weak self] in
            self?.cancelPendingPreview()
            self?.cancelPendingHide()
            self?.onFocusRequested?()
        }
        panel.onClose = { [weak self] in
            self?.commentEditorPanel = nil
            self?.presentedGroup = nil
            self?.isPointerOverCard = false
        }
        commentEditorPanel = panel
        presentedGroup = group
        panel.show(relativeTo: commentAnchorRect(for: group), of: hostView, editing: editing)
    }

    func dismissCommentEditor() {
        let panel = commentEditorPanel
        commentEditorPanel = nil
        presentedGroup = nil
        isPointerOverCard = false
        panel?.close()
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        guard let session = activeSession(),
              let window = pdfView.window,
              let group = annotationHit(at: window.mouseLocationOutsideOfEventStream)?.group,
              documentStore.removeHighlightGroup(group, in: session.id) else { return false }
        clearPreview()
        pdfView.needsDisplay = true
        return true
    }

    func showFocusPulse(for group: DocumentHighlightGroup) {
        focusHideWorkItem?.cancel()
        pendingFocusToken += 1
        let token = pendingFocusToken
        let anchor = anchorRect(for: group)

        guard anchor.isNull == false, anchor.isEmpty == false else {
            focusPulseView.isHidden = true
            return
        }

        focusPulseView.fillColor = group.color.nsColor.withAlphaComponent(0.28)
        focusPulseView.frame = anchor.insetBy(dx: -2, dy: -1)
        focusPulseView.alphaValue = 1
        focusPulseView.isHidden = false

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingFocusToken == token else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    self.focusPulseView.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        guard self.pendingFocusToken == token else { return }
                        self.focusPulseView.isHidden = true
                        self.focusPulseView.alphaValue = 1
                    }
                }
            }
        }
        focusHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
    }

    func clearPreview() {
        cancelPendingPreview()
        cancelPendingHide()
        hidePreviewKeepingHoverMemory()
    }

    func sessionDidChange() {
        clearPreview()
        dismissCommentEditor()
        contextGroup = nil
        lastHoveredGroup = nil
        lastHoveredAt = nil
    }

    private func activeSession() -> DocumentSession? {
        guard let activeSessionID,
              let session = documentStore.session(for: activeSessionID) else { return nil }
        return session
    }

    private func annotationHit(at pointInWindow: NSPoint) -> HighlightAnnotationHit? {
        guard let session = activeSession(),
              session.isBlank == false,
              let document = pdfView.document else { return nil }

        let pointInPDF = pdfView.convert(pointInWindow, from: nil)
        guard pdfView.bounds.contains(pointInPDF),
              let page = pdfView.page(for: pointInPDF, nearest: false),
              page.document === document else { return nil }

        let pointOnPage = pdfView.convert(pointInPDF, to: page)
        let commentAnnotation = HighlightService.commentAnnotation(at: pointOnPage, on: page)
        guard let annotation = commentAnnotation ?? HighlightService.highlightAnnotation(at: pointOnPage, on: page),
              let group = documentStore.annotationGroup(containing: annotation, for: session.id) else {
            return nil
        }
        return HighlightAnnotationHit(annotation: annotation, page: page, group: group, isCommentIcon: commentAnnotation != nil)
    }

    private func commentAnchorRect(for group: DocumentHighlightGroup) -> NSRect {
        let owner = group.records.first { ($0.annotation.contents ?? "").isEmpty == false }
            ?? group.records.first
        guard let hostView, let annotation = owner?.annotation, let page = annotation.page else {
            return anchorRect(for: group)
        }
        let bounds = pdfView.convert(HighlightService.commentIconBounds(for: annotation), from: page)
        return hostView.convert(bounds, from: pdfView)
    }

    private func anchorRect(for group: DocumentHighlightGroup) -> NSRect {
        guard let hostView else { return .zero }
        if let selection = group.primarySelection,
           let page = selection.pages.first {
            let boundsInPDF = pdfView.convert(selection.bounds(for: page), from: page)
            return hostView.convert(boundsInPDF, from: pdfView)
        }
        if let record = group.records.first,
           let page = record.annotation.page {
            let boundsInPDF = pdfView.convert(record.annotation.bounds, from: page)
            return hostView.convert(boundsInPDF, from: pdfView)
        }
        return NSRect(x: hostView.bounds.midX, y: hostView.bounds.midY, width: 1, height: 1)
    }

    private func contextMenuItem(
        title: String,
        command: ShortcutCommand,
        action: Selector,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = command
        item.isEnabled = isEnabled
        if let shortcut = documentStore.appConfiguration.shortcuts.bindings[command] {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }
        return item
    }

    @objc
    private func copyContext(_ sender: Any?) {
        let selectedText = pdfView.currentSelection?.string.map(PDFTextSanitizer.sanitize)
        let text = contextGroup?.snippet ?? selectedText.flatMap { $0.isEmpty ? nil : $0 }
        guard let text, text.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc
    private func markupContext(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? ShortcutCommand,
              let type = command.annotationMarkupType else { return }
        _ = onCreateMarkupRequested?(type)
    }

    @objc
    private func editContextComment(_ sender: Any?) {
        if let contextGroup {
            presentCommentEditor(for: contextGroup, navigate: false)
            return
        }
        if let createdGroup = onCreateMarkupRequested?(.highlight) {
            presentCommentEditor(for: createdGroup, navigate: false)
        }
    }

    @objc
    private func copyCurrentPageAsImage(_ sender: Any?) {
        guard let page = pdfView.currentPage else { return }
        PDFPageImageService.copyToPasteboard(PDFPageImageService.image(from: page))
    }

    @objc
    private func sendContextToCodex(_ sender: Any?) {
        if let text = (sender as? NSMenuItem)?.representedObject as? String {
            onSendSelectionToCodexRequested?(text)
            return
        }
        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return }
        onSendPageImageToCodexRequested?(PDFPageImageService.image(from: page), pageIndex + 1)
    }

    @objc
    private func removeContextHighlight(_ sender: Any?) {
        guard let session = activeSession(),
              let contextGroup,
              documentStore.removeHighlightGroup(contextGroup, in: session.id) else { return }
        clearPreview()
        dismissCommentEditor()
        pdfView.needsDisplay = true
    }

    private func cancelPendingPreview() {
        previewShowWorkItem?.cancel()
        previewShowWorkItem = nil
    }

    private func cancelPendingHide() {
        previewHideWorkItem?.cancel()
        previewHideWorkItem = nil
    }

    private func schedulePreviewHide() {
        guard commentEditorPanel?.editor.isEditing != true, isPointerOverCard == false else { return }
        cancelPendingPreview()
        guard previewHideWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.previewHideWorkItem = nil
                guard self.isPointerOverCard == false, self.commentEditorPanel?.editor.isEditing != true else { return }
                self.hidePreviewKeepingHoverMemory()
            }
        }
        previewHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func hidePreviewKeepingHoverMemory() {
        hoveredAnnotation = nil
        hoveredGroup = nil
        if commentEditorPanel?.editor.isEditing == false { dismissCommentEditor() }
    }

    var testingCommentPanel: AnnotationCommentPanel? { commentEditorPanel }
}

private struct HighlightAnnotationHit {
    let annotation: PDFAnnotation
    let page: PDFPage
    let group: DocumentHighlightGroup
    let isCommentIcon: Bool
}

private final class AnnotationFocusPulseView: NSView {
    var fillColor: NSColor = HighlightColor.default.nsColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
    }
}
