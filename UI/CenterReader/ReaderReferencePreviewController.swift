import AppKit
import PDFKit

/// A pane-local preview. Only the explicit jump enters the reader's history.
@MainActor
final class ReaderReferencePreviewController: NSObject, NSWindowDelegate {
    var onNavigate: ((PDFDestination) -> Void)?
    private(set) var content: ReferencePreviewViewController?
    private var panel: ReferencePreviewPanel?

    @discardableResult
    func show(destination: PDFDestination, anchor: NSRect, in source: PDFView) -> Bool {
        guard let document = source.document, let page = destination.page,
              page.document === document, source.window != nil,
              !anchor.intersection(source.visibleRect).isEmpty else { return false }
        guard let content = ReferencePreviewViewController(destination: destination, document: document) else { return false }
        close()
        content.onClose = { [weak self] in self?.close() }
        content.onNavigate = { [weak self, weak source] destination in
            guard let self else { return }
            self.close()
            guard source?.document === document else { return }
            self.onNavigate?(destination)
        }
        let available = source.window?.screen?.visibleFrame.size ?? source.bounds.size
        content.preferredContentSize = NSSize(
            width: min(580, max(280, available.width - 80)),
            height: min(360, max(200, available.height - 120))
        )
        guard let owner = source.window else { return false }
        let panel = ReferencePreviewPanel(
            contentRect: NSRect(origin: .zero, size: content.preferredContentSize),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = .fullScreenAuxiliary
        panel.appearance = source.effectiveAppearance
        panel.contentViewController = content
        panel.delegate = self
        let screenFrame = (owner.screen?.visibleFrame ?? owner.frame).insetBy(dx: 8, dy: 8)
        let anchorFrame = owner.convertToScreen(source.convert(anchor.intersection(source.visibleRect), to: nil))
        let size = content.preferredContentSize
        let y = anchorFrame.maxY + 6 + size.height <= screenFrame.maxY
            ? anchorFrame.maxY + 6 : anchorFrame.minY - 6 - size.height
        panel.setFrameOrigin(NSPoint(
            x: min(max(anchorFrame.midX - size.width / 2, screenFrame.minX), screenFrame.maxX - size.width),
            y: min(max(y, screenFrame.minY), screenFrame.maxY - size.height)
        ))
        self.content = content
        self.panel = panel
        owner.addChildWindow(panel, ordered: .above)
        NotificationCenter.default.addObserver(self, selector: #selector(dismissPreview), name: NSWindow.willCloseNotification, object: owner)
        NotificationCenter.default.addObserver(self, selector: #selector(dismissPreview), name: NSApplication.didResignActiveNotification, object: NSApp)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        content = nil
        NotificationCenter.default.removeObserver(self)
        let owner = panel.parent
        let restoreFocus = panel.isKeyWindow
        panel.delegate = nil
        owner?.removeChildWindow(panel)
        panel.close()
        if restoreFocus, owner?.isVisible == true { owner?.makeKey() }
    }

    func windowDidResignKey(_ notification: Notification) { close() }
    @objc private func dismissPreview(_ notification: Notification) { close() }

    func applyTheme() {
        panel?.appearance = panel?.parent?.effectiveAppearance
        content?.applyTheme()
    }
}

private final class ReferencePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Resolve links against the source page; the displayed document contains only a copy.
private final class ReferencePDFView: PDFView {
    var onCancel: (() -> Void)?
    var onInternalLink: ((PDFDestination) -> Void)?
    weak var sourcePage: PDFPage?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let page = page(for: point, nearest: false), let sourcePage,
           let annotation = sourcePage.annotations.first(where: {
               ($0.type == "Link" || $0.type == "Widget")
                   && $0.bounds.contains(convert(point, to: page))
           }) {
            if event.clickCount == 1, annotation.type == "Link",
               let destination = (annotation.action as? PDFActionGoTo)?.destination ?? annotation.destination,
               destination.page?.document === sourcePage.document {
                onInternalLink?(destination)
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

@MainActor
final class ReferencePreviewViewController: NSViewController {
    private struct Viewport {
        let bounds: NSRect
        let scaleFactor: CGFloat
    }

    private struct Visit {
        let destination: PDFDestination
        var viewport: Viewport?
    }

    var onNavigate: ((PDFDestination) -> Void)?
    var onClose: (() -> Void)?
    private(set) var destination: PDFDestination
    private let sourceDocument: PDFDocument
    private var previewDocument: PDFDocument
    private var previewPage: PDFPage
    private let preview = ReferencePDFView()
    private let jump = NSButton()
    private let back = NSButton()
    private let forward = NSButton()
    private var hasPositioned = false
    private var visits: [Visit]
    private var visitIndex = 0

    var canGoBack: Bool { visitIndex > 0 }
    var canGoForward: Bool { visitIndex + 1 < visits.count }

    private var pageTitle: String {
        guard let page = destination.page else { return "" }
        return page.label ?? String(sourceDocument.index(for: page) + 1)
    }

    init?(destination: PDFDestination, document: PDFDocument) {
        guard let copy = Self.copyPage(for: destination, in: document) else { return nil }
        self.destination = destination
        sourceDocument = document
        visits = [Visit(destination: destination)]
        previewPage = copy
        previewDocument = PDFDocument()
        previewDocument.insert(copy, at: 0)
        super.init(nibName: nil, bundle: nil)
    }

    private static func copyPage(for destination: PDFDestination, in document: PDFDocument) -> PDFPage? {
        guard let page = destination.page, page.document === document,
              let copy = page.copy() as? PDFPage else { return nil }
        for annotation in copy.annotations {
            if annotation.type == "Widget" {
                annotation.isReadOnly = true
            } else if HighlightService.isMarkupAnnotation(annotation) {
                annotation.contents = nil
                if let popup = annotation.popup {
                    copy.removeAnnotation(popup)
                    annotation.popup = nil
                }
            }
        }
        return copy
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        view.setAccessibilityLabel("Reference · Page \(pageTitle)")
        jump.title = ""
        jump.identifier = NSUserInterfaceItemIdentifier("referencePreviewJump")
        jump.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Jump to reference")
        jump.setAccessibilityLabel("Jump to reference · Page \(pageTitle)")
        jump.imagePosition = .imageOnly
        jump.isBordered = false
        jump.target = self
        jump.action = #selector(jumpToReference)
        jump.toolTip = "Jump to reference · Page \(pageTitle) (Option-click a link to jump directly)"
        jump.wantsLayer = true
        jump.layer?.cornerRadius = 4
        jump.focusRingType = .none
        configureHistoryButton(back, identifier: "referencePreviewBack", symbol: "chevron.left",
                               label: "Back", action: #selector(goBack))
        configureHistoryButton(forward, identifier: "referencePreviewForward", symbol: "chevron.right",
                               label: "Forward", action: #selector(goForward))
        preview.displayMode = .singlePage
        preview.displayBox = .cropBox
        preview.displaysPageBreaks = false
        preview.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        preview.autoScales = false
        preview.document = previewDocument
        preview.sourcePage = destination.page
        preview.onCancel = { [weak self] in self?.onClose?() }
        preview.onInternalLink = { [weak self] destination in self?.navigate(to: destination) }
        for child in [preview, back, forward, jump] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            back.widthAnchor.constraint(equalToConstant: 24),
            back.heightAnchor.constraint(equalToConstant: 24),
            forward.topAnchor.constraint(equalTo: back.topAnchor),
            forward.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 2),
            forward.widthAnchor.constraint(equalToConstant: 24),
            forward.heightAnchor.constraint(equalToConstant: 24),
            jump.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            jump.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            jump.widthAnchor.constraint(equalToConstant: 24),
            jump.heightAnchor.constraint(equalToConstant: 24),
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        refreshNavigationControls()
        applyTheme()
    }

    private func configureHistoryButton(_ button: NSButton, identifier: String, symbol: String,
                                        label: String, action: Selector) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.focusRingType = .none
    }

    @discardableResult
    func navigate(to destination: PDFDestination) -> Bool {
        guard let copy = Self.copyPage(for: destination, in: sourceDocument) else { return false }
        captureViewport()
        visits.removeSubrange((visitIndex + 1)..<visits.count)
        visits.append(Visit(destination: destination))
        visitIndex = visits.count - 1
        display(destination: destination, copy: copy)
        return true
    }

    @objc func goBack() { moveInHistory(to: visitIndex - 1) }
    @objc func goForward() { moveInHistory(to: visitIndex + 1) }

    private func moveInHistory(to index: Int) {
        guard visits.indices.contains(index), index != visitIndex,
              let copy = Self.copyPage(for: visits[index].destination, in: sourceDocument) else { return }
        captureViewport()
        visitIndex = index
        display(destination: visits[index].destination, copy: copy)
    }

    private func captureViewport() {
        guard isViewLoaded, hasPositioned else { return }
        visits[visitIndex].viewport = Viewport(bounds: preview.convert(preview.bounds, to: previewPage),
                                             scaleFactor: preview.scaleFactor)
    }

    private func display(destination: PDFDestination, copy: PDFPage) {
        self.destination = destination
        previewPage = copy
        let document = PDFDocument()
        document.insert(copy, at: 0)
        preview.sourcePage = destination.page
        preview.document = document
        previewDocument = document
        hasPositioned = false
        guard isViewLoaded else { return }
        refreshNavigationControls()
        positionReference()
        view.window?.makeFirstResponder(preview)
    }

    private func refreshNavigationControls() {
        view.setAccessibilityLabel("Reference · Page \(pageTitle)")
        jump.setAccessibilityLabel("Jump to reference · Page \(pageTitle)")
        jump.toolTip = "Jump to reference · Page \(pageTitle)"
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        positionReference()
        view.window?.makeFirstResponder(preview)
    }

    func positionReference() {
        guard !hasPositioned else { return }
        let page = previewPage
        view.layoutSubtreeIfNeeded()
        guard preview.bounds.width > 24, preview.bounds.height > 24 else { return }
        preview.go(to: page)
        preview.layoutDocumentView()
        guard let scrollView = preview.documentView?.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.tile()
        let pageBounds = page.bounds(for: .cropBox)
        let width = preview.convert(pageBounds, from: page).width
        guard width > 0 else { return }
        hasPositioned = true
        // PDFKit's clip bounds can use scaled document units after navigation.
        let viewport = preview.convert(scrollView.contentView.bounds, from: scrollView.contentView).size
        preview.scaleFactor *= viewport.width / width
        preview.layoutDocumentView()

        if let viewport = visits[visitIndex].viewport {
            preview.scaleFactor = viewport.scaleFactor
            preview.layoutDocumentView()
            preview.go(to: viewport.bounds, on: page)
            return
        }

        // PDF null coordinates mean the page edge. Work in view coordinates so
        // the crop remains upright for rotated pages as well.
        let point = NSPoint(
            x: Self.coordinate(destination.point.x, lower: pageBounds.minX, upper: pageBounds.maxX, unspecified: pageBounds.minX),
            y: Self.coordinate(destination.point.y, lower: pageBounds.minY, upper: pageBounds.maxY, unspecified: pageBounds.maxY)
        )
        var contentBounds = pageBounds
        if destination.point.x.isFinite, destination.point.x != kPDFDestinationUnspecifiedValue,
           destination.point.y.isFinite, destination.point.y != kPDFDestinationUnspecifiedValue,
           let text = page.string {
            let characters = Array(text.utf16)
            let characterBounds = (0..<min(characters.count, page.numberOfCharacters)).compactMap { index -> NSRect? in
                if let scalar = UnicodeScalar(characters[index]), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    return nil
                }
                return preview.convert(page.characterBounds(at: index), from: page)
            }
            if let column = ReferencePreviewColumnLayout.columnBounds(
                characterBounds: characterBounds,
                pageBounds: preview.convert(pageBounds, from: page),
                target: preview.convert(point, from: page)
            ) {
                contentBounds = preview.convert(column, to: page)
                preview.scaleFactor *= viewport.width / column.width
                preview.layoutDocumentView()
            }
        }
        let target = preview.convert(point, from: page)
        let pageRect = preview.convert(pageBounds, from: page)
        let contentRect = preview.convert(contentBounds, from: page)
        let height = min(viewport.height, pageRect.height)
        let desiredY = preview.isFlipped ? target.y - 24 : target.y - height + 24
        let rect = NSRect(
            x: contentRect.minX,
            y: min(max(desiredY, pageRect.minY), pageRect.maxY - height),
            width: contentRect.width,
            height: height
        )
        preview.go(to: preview.convert(rect, to: page), on: page)
    }

    private static func coordinate(_ value: CGFloat, lower: CGFloat, upper: CGFloat, unspecified: CGFloat) -> CGFloat {
        guard value.isFinite, value != kPDFDestinationUnspecifiedValue else { return unspecified }
        return min(max(value, lower), upper)
    }

    func applyTheme() {
        guard isViewLoaded else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NightModeStyle.readerBackdropColor.cgColor
            for button in [back, forward, jump] {
                button.contentTintColor = NightModeStyle.secondaryTextColor
                button.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.withAlphaComponent(0.92).cgColor
            }
            preview.backgroundColor = NightModeStyle.readerBackdropColor
            preview.contentFilters = NightModeStyle.makePDFContentFilters(for: view.effectiveAppearance)
        }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
    @objc private func jumpToReference() { onNavigate?(destination) }
}
