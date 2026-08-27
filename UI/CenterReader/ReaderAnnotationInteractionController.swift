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
    private let previewView = AnnotationPreviewView()
    private let focusPulseView = AnnotationFocusPulseView()

    private var pendingFocusToken = 0
    private weak var hoveredAnnotation: PDFAnnotation?
    private var hoveredGroup: DocumentHighlightGroup?
    private var lastHoveredGroup: DocumentHighlightGroup?
    private var lastHoveredAt: Date?
    private var contextGroup: DocumentHighlightGroup?
    private var previewAnchor: NSRect?
    private var previewShowWorkItem: DispatchWorkItem?
    private var focusHideWorkItem: DispatchWorkItem?
    private var commentEditorPopover: NSPopover?

    init(documentStore: DocumentStore, pdfView: ReaderPDFView) {
        self.documentStore = documentStore
        self.pdfView = pdfView
        super.init()
        previewView.isHidden = true
        focusPulseView.isHidden = true
    }

    func install(in hostView: NSView) {
        self.hostView = hostView
        hostView.addSubview(previewView)
        hostView.addSubview(focusPulseView)
    }

    func layoutOverlay() {
        positionPreviewIfNeeded()
    }

    func handlePointerMoved(_ event: NSEvent?) {
        guard let event, let hit = annotationHit(at: event.locationInWindow) else {
            if let hoveredGroup {
                lastHoveredGroup = hoveredGroup
                lastHoveredAt = Date()
            }
            cancelPendingPreview()
            hidePreviewKeepingHoverMemory()
            return
        }

        lastHoveredGroup = hit.group
        lastHoveredAt = Date()

        let annotationChanged = hoveredAnnotation !== hit.annotation
        let contentChanged = hoveredGroup?.comment != hit.group.comment
            || hoveredGroup?.snippet != hit.group.snippet
        guard annotationChanged || contentChanged else { return }

        hoveredAnnotation = hit.annotation
        hoveredGroup = hit.group

        guard hit.group.normalizedComment.isEmpty == false else {
            cancelPendingPreview()
            previewView.isHidden = true
            previewAnchor = nil
            return
        }

        if shouldSuppressPreview?(hit.group.groupID) == true {
            cancelPendingPreview()
            previewView.isHidden = true
            previewAnchor = nil
            return
        }

        guard let hostView else { return }
        let boundsInPDF = pdfView.convert(hit.annotation.bounds, from: hit.page)
        previewAnchor = hostView.convert(boundsInPDF, from: pdfView)

        cancelPendingPreview()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.hoveredAnnotation === hit.annotation,
                      self.hoveredGroup?.groupID == hit.group.groupID else { return }
                guard self.previewView.configure(with: hit.group) else {
                    self.previewView.isHidden = true
                    return
                }
                self.previewView.isHidden = false
                self.positionPreviewIfNeeded()
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
        let hasSelection = HighlightService.selectionContainsText(pdfView.currentSelection)

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
            menu.addItem(
                contextMenuItem(
                    title: hasSelection ? "Send Selection to Codex" : "Send Page Image to Codex",
                    command: .sendContextToCodex,
                    action: #selector(sendContextToCodex(_:)),
                    isEnabled: hasSelection || pdfView.currentPage != nil
                )
            )
        }
        return menu
    }

    func activateAnnotation(at event: NSEvent) -> Bool {
        guard let group = annotationHit(at: event.locationInWindow)?.group else { return false }
        onRevealRequested?(group)
        return true
    }

    @discardableResult
    func addOrEditComment() -> Bool {
        if let createdGroup = onCreateMarkupRequested?(.highlight) {
            presentCommentEditor(for: createdGroup)
            return true
        }
        if let pointInWindow = hostView?.window?.mouseLocationOutsideOfEventStream,
           let group = annotationHit(at: pointInWindow)?.group {
            presentCommentEditor(for: group)
            return true
        }
        if let hoveredGroup {
            presentCommentEditor(for: hoveredGroup)
            return true
        }
        if let lastHoveredGroup,
           let lastHoveredAt,
           Date().timeIntervalSince(lastHoveredAt) < 0.45 {
            presentCommentEditor(for: lastHoveredGroup)
            return true
        }
        return false
    }

    func presentCommentEditor(for group: DocumentHighlightGroup) {
        clearPreview()
        dismissCommentEditor()

        guard let session = activeSession() else { return }
        onNavigateRequested?(group)
        showFocusPulse(for: group)

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

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentViewController = editor
        commentEditorPopover = popover

        guard let hostView else { return }
        popover.show(relativeTo: anchorRect(for: group), of: hostView, preferredEdge: .maxY)
    }

    func dismissCommentEditor() {
        commentEditorPopover?.close()
        commentEditorPopover = nil
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
        hidePreviewKeepingHoverMemory()
    }

    func sessionDidChange() {
        clearPreview()
        contextGroup = nil
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
        guard let annotation = HighlightService.highlightAnnotation(at: pointOnPage, on: page),
              let group = documentStore.annotationGroup(containing: annotation, for: session.id) else {
            return nil
        }
        return HighlightAnnotationHit(annotation: annotation, page: page, group: group)
    }

    private func positionPreviewIfNeeded() {
        guard previewView.isHidden == false,
              let anchor = previewAnchor,
              let hostView,
              hostView.bounds.width > 40,
              hostView.bounds.height > 40 else { return }

        let size = previewView.preferredSize(maxWidth: hostView.bounds.width - 24)
        guard size.width + 16 <= hostView.bounds.width,
              size.height + 16 <= hostView.bounds.height else {
            previewView.isHidden = true
            return
        }

        let spaceRight = hostView.bounds.maxX - anchor.maxX
        let spaceLeft = anchor.minX - hostView.bounds.minX
        var x: CGFloat
        if spaceRight >= size.width + 16 || spaceRight >= spaceLeft {
            x = anchor.maxX + 8
            if x + size.width > hostView.bounds.maxX - 8 {
                x = anchor.minX - size.width - 8
            }
        } else {
            x = anchor.minX - size.width - 8
            if x < hostView.bounds.minX + 8 {
                x = anchor.maxX + 8
            }
        }
        x = min(max(x, hostView.bounds.minX + 8), hostView.bounds.maxX - size.width - 8)

        var y = anchor.maxY + 8
        if y + size.height > hostView.bounds.maxY - 8 {
            y = anchor.minY - size.height - 8
        }
        y = min(max(y, hostView.bounds.minY + 8), hostView.bounds.maxY - size.height - 8)
        previewView.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        previewView.needsLayout = true
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
            presentCommentEditor(for: contextGroup)
            return
        }
        if let createdGroup = onCreateMarkupRequested?(.highlight) {
            presentCommentEditor(for: createdGroup)
        }
    }

    @objc
    private func copyCurrentPageAsImage(_ sender: Any?) {
        guard let page = pdfView.currentPage else { return }
        PDFPageImageService.copyToPasteboard(PDFPageImageService.image(from: page))
    }

    @objc
    private func sendContextToCodex(_ sender: Any?) {
        if let text = pdfView.currentSelection?.string.map(PDFTextSanitizer.sanitize),
           text.isEmpty == false {
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

    private func hidePreviewKeepingHoverMemory() {
        hoveredAnnotation = nil
        hoveredGroup = nil
        previewAnchor = nil
        previewView.isHidden = true
    }
}

private struct HighlightAnnotationHit {
    let annotation: PDFAnnotation
    let page: PDFPage
    let group: DocumentHighlightGroup
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
