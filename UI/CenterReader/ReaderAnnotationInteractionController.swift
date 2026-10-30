import AppKit
import PDFKit

/// Owns reader-local annotation UI while leaving navigation and highlight creation to the reader.
@MainActor
final class ReaderAnnotationInteractionController: NSObject {
    var activeSessionID: UUID?
    var onFocusRequested: (() -> Void)?
    var onCreateMarkupRequested: ((AnnotationMarkupType) -> DocumentHighlightGroup?)?
    var onSendSelectionToCodexRequested: ((String) -> Void)?
    var onSendPageImageToCodexRequested: ((NSImage, Int) -> Void)?
    var onTranslateSelectionRequested: ((PDFSelection) -> Void)?
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var shouldSuppressPreview: ((String) -> Bool)?

    private let documentStore: DocumentStore
    private let pdfView: ReaderPDFView
    private weak var hostView: NSView?
    private let focusPulseView = AnnotationFocusPulseView()
    private let commentIconOverlay = CommentIconOverlayView(frame: .zero)
    private var isOverlayRefreshScheduled = false

    private var pendingFocusToken = 0
    private weak var hoveredAnnotation: PDFAnnotation?
    private var hoveredGroup: DocumentHighlightGroup?
    private var lastHoveredGroup: DocumentHighlightGroup?
    private var lastHoveredAt: Date?
    private struct MenuContext {
        let sessionID: UUID
        let document: PDFDocument
        let page: PDFPage?
        var selection: PDFSelection?
        var group: DocumentHighlightGroup?
    }
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

    func scheduleOverlayRefresh() {
        guard isOverlayRefreshScheduled == false else { return }
        isOverlayRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayRefreshScheduled = false
            if let group = self.presentedGroup {
                self.commentEditorPanel?.updateAnchor(self.commentAnchorRect(for: group))
            }
            self.refreshCommentIcons()
        }
    }

    func refreshThemeAppearance() {
        commentEditorPanel?.refreshThemeAppearance()
        scheduleOverlayRefresh()
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
        guard let session = activeSession(), !session.isBlank, let document = pdfView.document else { return nil }
        onFocusRequested?()
        let point = pdfView.convert(event.locationInWindow, from: nil)
        let page = pdfView.page(for: point, nearest: false)
        let pagePoint = page.map { pdfView.convert(point, to: $0) }
        let hit = annotationHit(at: event.locationInWindow)
        var context = MenuContext(sessionID: session.id, document: document, page: page, group: hit?.group)
        let menu = NSMenu(title: L10n.text("Reader", "阅读器"))
        menu.autoenablesItems = false
        // Keep contextual Services and Writing Tools from appending unrelated actions.
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) { menu.automaticallyInsertsWritingToolsItems = false }
        var isPageContext = false
        var showsCodex = false

        if let group = hit?.group {
            if document.allowsCopying {
                menu.addItem(contextMenuItem(title: L10n.text("Copy Snippet", "复制摘录"),
                    action: #selector(copyContext(_:)), payload: context))
            }
            if document.allowsCommenting {
                menu.addItem(contextMenuItem(title: L10n.text("Edit Comment", "编辑批注"), command: .addComment,
                    action: #selector(editContextComment(_:)), payload: context))
                let colors = NSMenu(title: L10n.text("Color", "颜色"))
                colors.autoenablesItems = false
                for color in HighlightColor.allCases {
                    let item = contextMenuItem(title: color.menuTitle, action: #selector(changeContextColor(_:)),
                                               payload: (context, color))
                    item.state = color == group.color ? .on : .off
                    colors.addItem(item)
                }
                let item = NSMenuItem(title: colors.title, action: nil, keyEquivalent: "")
                item.submenu = colors
                menu.addItem(item)
                menu.addItem(.separator())
                menu.addItem(contextMenuItem(title: L10n.text("Delete Annotation", "删除批注"), command: .removeHighlight,
                    action: #selector(removeContextHighlight(_:)), payload: context))
            }
        } else if let page, let pagePoint, let link = page.annotations.last(where: {
            $0.type == "Link" && $0.bounds.contains(pagePoint)
        }), let url = (link.action as? PDFActionURL)?.url ?? link.url {
            let isWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            menu.addItem(contextMenuItem(title: isWeb ? L10n.text("Open in Browser", "在浏览器中打开") : L10n.text("Open Link", "打开链接"),
                action: #selector(openContextURL(_:)), payload: url))
            if document.allowsCopying {
                menu.addItem(contextMenuItem(title: L10n.text("Copy Link", "复制链接"), action: #selector(copyLink(_:)), payload: url))
            }
        } else if let page, let pagePoint, let link = page.annotations.last(where: {
            $0.type == "Link" && $0.bounds.contains(pagePoint)
        }), let destination = ReferenceLinkDestination.resolve(link), destination.page?.document === document {
            menu.addItem(contextMenuItem(title: L10n.text("Open Link", "打开链接"),
                action: #selector(openInternalLink(_:)), payload: (context, destination)))
        } else {
            // Keep an explicit text selection ahead of an underlying scan image. Outside that selection,
            // an image wins over nearby text; a stale selection must never determine the clicked menu.
            if let page, let pagePoint {
                context.selection = selectedText(at: pagePoint, on: page)
            }
            let image = context.selection == nil ? page.flatMap { page in
                pagePoint.flatMap { PDFEmbeddedImageService.region(at: $0, on: page) }
            } : nil
            if let image {
                menu.addItem(contextMenuItem(title: L10n.text("Copy Image", "复制图片"),
                    action: #selector(copyImage(_:)), payload: image))
            } else {
                if context.selection == nil, let page, let pagePoint {
                    let index = page.characterIndex(at: pagePoint)
                    if index >= 0, page.characterBounds(at: index).contains(pagePoint) {
                        context.selection = page.selectionForWord(at: pagePoint)?.copy() as? PDFSelection
                    }
                }
                if let selection = context.selection, !HighlightService.selectionContainsText(selection) {
                    context.selection = nil
                }
                if let selection = context.selection, HighlightService.selectionContainsText(selection) {
                    pdfView.currentSelection = selection
                    if document.allowsCopying {
                        menu.addItem(contextMenuItem(title: L10n.text("Copy", "复制"),
                            action: #selector(copyContext(_:)), payload: context))
                        menu.addItem(contextMenuItem(title: L10n.text("Translate…", "翻译…"), command: .translateSelection,
                            action: #selector(translateContext(_:)), payload: context))
                    }
                    if document.allowsCommenting {
                        let markup = NSMenu(title: L10n.text("Mark Up", "标记"))
                        markup.autoenablesItems = false
                        for command in ShortcutCommand.allCases {
                            guard let type = command.annotationMarkupType else { continue }
                            markup.addItem(contextMenuItem(title: type.modeTitle, command: command,
                                action: #selector(markupContext(_:)), payload: (context, type)))
                        }
                        let item = NSMenuItem(title: markup.title, action: nil, keyEquivalent: "")
                        item.submenu = markup
                        menu.addItem(item)
                        menu.addItem(contextMenuItem(title: L10n.text("Add Comment", "添加批注"), command: .addComment,
                            action: #selector(editContextComment(_:)), payload: context))
                    }
                }
                isPageContext = context.selection == nil
            }
            showsCodex = image == nil && (context.selection != nil || page != nil)
        }
        if document.allowsCopying {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(contextMenuItem(title: L10n.text("Copy Area…", "框选复制…"),
                action: #selector(copyArea(_:)), payload: context))
            if isPageContext, page != nil {
                menu.addItem(contextMenuItem(title: ShortcutCommand.copyCurrentPageAsImage.menuTitle,
                    command: .copyCurrentPageAsImage, action: #selector(copyCurrentPageAsImage(_:)), payload: context))
            }
        }
        if showsCodex, document.allowsCopying, documentStore.appConfiguration.integrations.codexEnabled {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(contextMenuItem(title: context.selection == nil ? L10n.text("Send Page Image to Codex", "发送页面图像到 Codex") : L10n.text("Send Selection to Codex", "发送所选文本到 Codex"),
                command: .sendContextToCodex, action: #selector(sendContextToCodex(_:)), payload: context))
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func selectedText(at point: CGPoint, on page: PDFPage) -> PDFSelection? {
        guard let selection = pdfView.currentSelection, selection.pages.contains(where: { $0 === page }),
              selection.selectionsByLine().contains(where: {
                  $0.pages.contains(where: { $0 === page }) && $0.bounds(for: page).insetBy(dx: -2, dy: -2).contains(point)
              }) else { return nil }
        return selection.copy() as? PDFSelection
    }

    private func isCurrent(_ context: MenuContext) -> Bool {
        activeSessionID == context.sessionID && pdfView.document === context.document
    }

    func activateAnnotation(at event: NSEvent) -> Bool {
        guard let hit = annotationHit(at: event.locationInWindow),
              event.clickCount == 2 || hit.isCommentIcon else { return false }
        onFocusRequested?()
        presentCommentEditor(for: hit.group)
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

    private func presentCommentEditor(for group: DocumentHighlightGroup) {
        if let panel = commentEditorPanel, presentedGroup?.groupID == group.groupID {
            cancelPendingPreview()
            cancelPendingHide()
            panel.beginEditing()
            return
        }
        clearPreview()
        dismissCommentEditor()

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
        lastHoveredGroup = nil
        lastHoveredAt = nil
        commentIconOverlay.icons = []
        commentIconOverlay.removeFromSuperview()
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
        let commentAnnotation = pdfView.commentIcons.annotation(at: pointOnPage, on: page)
        guard let annotation = commentAnnotation ?? HighlightService.highlightAnnotation(at: pointOnPage, on: page),
              let group = documentStore.annotationGroup(containing: annotation, for: session.id) else {
            return nil
        }
        return HighlightAnnotationHit(annotation: annotation, group: group, isCommentIcon: commentAnnotation != nil)
    }

    private func refreshCommentIcons() {
        guard let documentView = pdfView.documentView else {
            commentIconOverlay.removeFromSuperview()
            return
        }
        if commentIconOverlay.superview !== documentView {
            commentIconOverlay.removeFromSuperview()
            // autoresizingMask keeps the frame in sync with documentView afterwards.
            commentIconOverlay.frame = documentView.bounds
            documentView.addSubview(commentIconOverlay)
        }
        // PDFKit may append page views after installing the overlay. Keep dots
        // above those pages when asynchronous layout finishes.
        if documentView.subviews.last !== commentIconOverlay {
            documentView.addSubview(commentIconOverlay, positioned: .above, relativeTo: nil)
        }
        Self.hideNativeCommentIcons(in: documentView)

        let appearance = pdfView.effectiveAppearance
        let pages = commentIconPages()
        pdfView.commentIcons.retainPages(pages)
        commentIconOverlay.icons = pages.flatMap { page in
            pdfView.commentIcons.frames(on: page).map { annotation, pageRect in
                let inPDF = pdfView.convert(pageRect, from: page)
                let inOverlay = commentIconOverlay.convert(inPDF, from: pdfView)
                let color = NightModeStyle.highlightColor(
                    for: HighlightColor.closest(to: annotation.color),
                    appearance: appearance
                )
                return (inOverlay, color)
            }
        }
    }

    private func commentIconPages() -> [PDFPage] {
        guard let document = pdfView.document else { return [] }
        guard pdfView.displayMode == .singlePageContinuous || pdfView.displayMode == .twoUpContinuous else {
            return pdfView.visiblePages
        }
        // During a scroll, visiblePages can still describe the previous page views.
        // Resolve the viewport edges against PDFKit's document geometry instead.
        let bounds = pdfView.bounds
        let indices = [
            NSPoint(x: bounds.minX, y: bounds.minY),
            NSPoint(x: bounds.maxX, y: bounds.minY),
            NSPoint(x: bounds.minX, y: bounds.maxY),
            NSPoint(x: bounds.maxX, y: bounds.maxY),
        ].compactMap { pdfView.page(for: $0, nearest: true) }.map { document.index(for: $0) }
        guard let first = indices.min(), let last = indices.max() else { return [] }
        return (first...last).compactMap { document.page(at: $0) }
    }

    /// PDFKit's native comment badges are the only image-bearing image views under documentView.
    private static func hideNativeCommentIcons(in root: NSView) {
        var pending = [root]
        while let view = pending.popLast() {
            if let imageView = view as? NSImageView, imageView.image != nil, imageView.isHidden == false {
                imageView.isHidden = true
            }
            pending.append(contentsOf: view.subviews)
        }
    }

    private func commentAnchorRect(for group: DocumentHighlightGroup) -> NSRect {
        let owner = group.records.first { CommentIconPlacement.isCommentOwner($0.annotation) }
            ?? group.records.first
        guard let hostView, let annotation = owner?.annotation, let page = annotation.page else {
            return anchorRect(for: group)
        }
        let bounds = pdfView.convert(pdfView.commentIcons.bounds(for: annotation), from: page)
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

    private func contextMenuItem(title: String, command: ShortcutCommand? = nil,
                                 action: Selector, payload: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        if action == #selector(copyContext(_:)) {
            item.keyEquivalent = "c"
            item.keyEquivalentModifierMask = [.command]
        }
        if let command, let shortcut = documentStore.appConfiguration.shortcuts.bindings[command] {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }
        return item
    }

    @objc
    private func copyContext(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext, context.document.allowsCopying else { return }
        if let group = context.group {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(group.snippet, forType: .string)
        } else if isCurrent(context), let selection = context.selection {
            // Preserve PDFKit's text and rich-text clipboard formats while copying the captured selection.
            let previous = pdfView.currentSelection
            pdfView.currentSelection = selection
            pdfView.copy(sender)
            pdfView.currentSelection = previous
        }
    }

    @objc
    private func markupContext(_ sender: NSMenuItem) {
        guard let (context, type) = sender.representedObject as? (MenuContext, AnnotationMarkupType),
              isCurrent(context), context.document.allowsCommenting, let selection = context.selection else { return }
        pdfView.currentSelection = selection
        _ = onCreateMarkupRequested?(type)
    }

    @objc
    private func editContextComment(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext,
              isCurrent(context), context.document.allowsCommenting else { return }
        if let group = context.group {
            presentCommentEditor(for: group)
        } else if let selection = context.selection {
            pdfView.currentSelection = selection
            if let group = onCreateMarkupRequested?(.highlight) { presentCommentEditor(for: group) }
        }
    }

    @objc
    private func changeContextColor(_ sender: NSMenuItem) {
        guard let (context, color) = sender.representedObject as? (MenuContext, HighlightColor),
              isCurrent(context), context.document.allowsCommenting, let group = context.group else { return }
        documentStore.updateHighlightColor(color, forHighlightGroup: group.groupID, in: context.sessionID)
    }

    @objc
    private func translateContext(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext,
              isCurrent(context), context.document.allowsCopying, let selection = context.selection else { return }
        onTranslateSelectionRequested?(selection)
    }

    @objc
    private func openContextURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if !openURL(url) { NSSound.beep() }
    }

    @objc
    private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc
    private func openInternalLink(_ sender: NSMenuItem) {
        guard let (context, destination) = sender.representedObject as? (MenuContext, PDFDestination),
              isCurrent(context) else { return }
        _ = pdfView.onInternalLinkNavigationRequested?(destination)
    }

    @objc
    private func copyArea(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext,
              isCurrent(context), context.document.allowsCopying else { return }
        clearPreview()
        dismissCommentEditor()
        pdfView.areaSelectionOverlay?.begin(in: pdfView)
    }

    @objc
    private func copyImage(_ sender: NSMenuItem) {
        guard let region = sender.representedObject as? PDFEmbeddedImageService.Region,
              region.page.document?.allowsCopying != false, let image = region.image() else {
            NSSound.beep()
            return
        }
        if PDFPageImageService.copyToPasteboard(image) == false { NSSound.beep() }
    }

    @objc
    private func copyCurrentPageAsImage(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext, context.document.allowsCopying,
              let page = context.page else { return }
        PDFPageImageService.copyToPasteboard(PDFPageImageService.image(from: page))
    }

    @objc
    private func sendContextToCodex(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext, isCurrent(context), context.document.allowsCopying,
              documentStore.appConfiguration.integrations.codexEnabled else { return }
        if let text = context.selection?.string.map(PDFTextSanitizer.sanitize), !text.isEmpty {
            onSendSelectionToCodexRequested?(text)
        } else if let page = context.page {
            let index = context.document.index(for: page)
            guard index != NSNotFound else { return }
            onSendPageImageToCodexRequested?(PDFPageImageService.image(from: page), index + 1)
        }
    }

    @objc
    private func removeContextHighlight(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuContext, isCurrent(context),
              context.document.allowsCommenting, let group = context.group,
              documentStore.removeHighlightGroup(group, in: context.sessionID) else { return }
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

final class CommentIconOverlayView: NSView {
    var icons: [(frame: NSRect, color: NSColor)] = [] {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    // Frames are converted into this view, independently of PDFKit's orientation.
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for icon in icons where icon.frame.intersects(dirtyRect) {
            let rect = icon.frame.insetBy(dx: 0.4, dy: 0.4)
            icon.color.setFill()
            NSColor.white.withAlphaComponent(0.92).setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 1
            path.fill()
            path.stroke()
        }
    }
}

private struct HighlightAnnotationHit {
    let annotation: PDFAnnotation
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
