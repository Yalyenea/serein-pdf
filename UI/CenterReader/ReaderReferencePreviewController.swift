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
        content.onNavigate = { [weak self, weak source] in
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

/// Keep preview interaction limited to reading, selection, and copying.
private final class ReferencePDFView: PDFView {
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let page = page(for: point, nearest: false),
           page.annotations.contains(where: {
               ($0.type == "Link" || $0.type == "Widget")
                   && $0.bounds.contains(convert(point, to: page))
           }) { return }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

@MainActor
final class ReferencePreviewViewController: NSViewController {
    var onNavigate: (() -> Void)?
    var onClose: (() -> Void)?
    let destination: PDFDestination
    private let previewDocument: PDFDocument
    private let previewPage: PDFPage
    private let pageTitle: String
    private let preview = ReferencePDFView()
    private let jump = NSButton()
    private var hasPositioned = false

    init?(destination: PDFDestination, document: PDFDocument) {
        guard let page = destination.page, page.document === document,
              let copy = page.copy() as? PDFPage else { return nil }
        self.destination = destination
        pageTitle = page.label ?? String(document.index(for: page) + 1)
        previewPage = copy
        previewDocument = PDFDocument()
        previewDocument.insert(copy, at: 0)
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
        super.init(nibName: nil, bundle: nil)
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
        preview.displayMode = .singlePage
        preview.displayBox = .cropBox
        preview.displaysPageBreaks = false
        preview.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        preview.autoScales = false
        preview.document = previewDocument
        preview.onCancel = { [weak self] in self?.onClose?() }
        for child in [preview, jump] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            jump.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            jump.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            jump.widthAnchor.constraint(equalToConstant: 24),
            jump.heightAnchor.constraint(equalToConstant: 24),
            preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        applyTheme()
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
        let viewport = scrollView.contentView.bounds.size
        preview.scaleFactor *= viewport.width / width
        preview.layoutDocumentView()

        // PDF null coordinates mean the page edge. Work in view coordinates so
        // the crop remains upright for rotated pages as well.
        let point = NSPoint(
            x: Self.coordinate(destination.point.x, lower: pageBounds.minX, upper: pageBounds.maxX, unspecified: pageBounds.minX),
            y: Self.coordinate(destination.point.y, lower: pageBounds.minY, upper: pageBounds.maxY, unspecified: pageBounds.maxY)
        )
        let target = preview.convert(point, from: page)
        let pageRect = preview.convert(pageBounds, from: page)
        let height = min(viewport.height, pageRect.height)
        let desiredY = preview.isFlipped ? target.y - 24 : target.y - height + 24
        let rect = NSRect(
            x: pageRect.minX,
            y: min(max(desiredY, pageRect.minY), pageRect.maxY - height),
            width: pageRect.width,
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
            jump.contentTintColor = NightModeStyle.secondaryTextColor
            jump.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.withAlphaComponent(0.92).cgColor
            preview.backgroundColor = NightModeStyle.readerBackdropColor
            preview.contentFilters = NightModeStyle.makePDFContentFilters(for: view.effectiveAppearance)
        }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
    @objc private func jumpToReference() { onNavigate?() }
}
