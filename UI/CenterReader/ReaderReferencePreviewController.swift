import AppKit
import PDFKit

/// A pane-local preview. Only the explicit jump enters the reader's history.
@MainActor
final class ReaderReferencePreviewController: NSObject, NSPopoverDelegate {
    var onNavigate: ((PDFDestination) -> Void)?
    private(set) var content: ReferencePreviewViewController?
    private var popover: NSPopover?

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
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = content
        self.content = content
        self.popover = popover
        popover.show(relativeTo: anchor.intersection(source.visibleRect), of: source, preferredEdge: .minY)
        return true
    }

    func close() {
        popover?.close()
        popover = nil
        content = nil
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        content = nil
    }

    func applyTheme() {
        content?.applyTheme()
    }
}

/// Keep preview interaction limited to reading, selection, and copying.
private final class ReferencePDFView: PDFView {
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
    private let pageLabel = NSTextField(labelWithString: "")
    private var hasPositioned = false

    init?(destination: PDFDestination, document: PDFDocument) {
        guard let page = destination.page, page.document === document,
              let copy = page.copy() as? PDFPage else { return nil }
        self.destination = destination
        pageTitle = page.label ?? String(document.index(for: page) + 1)
        previewPage = copy
        previewDocument = PDFDocument()
        previewDocument.insert(copy, at: 0)
        for annotation in copy.annotations where annotation.type == "Widget" {
            annotation.isReadOnly = true
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
        pageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pageLabel.stringValue = "Reference · Page \(pageTitle)"
        let jump = NSButton(title: "Jump to Reference", target: self, action: #selector(jumpToReference))
        jump.bezelStyle = .inline
        jump.font = .systemFont(ofSize: 11)
        jump.toolTip = "Option-click a reference to jump directly"
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close preview")!, target: self, action: #selector(closePreview))
        close.isBordered = false
        close.keyEquivalent = "\u{1b}"
        close.keyEquivalentModifierMask = []
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [pageLabel, spacer, jump, close])
        header.spacing = 10
        header.alignment = .centerY
        preview.displayMode = .singlePage
        preview.displayBox = .cropBox
        preview.displaysPageBreaks = false
        preview.autoScales = false
        preview.document = previewDocument
        for child in [header, preview] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            header.heightAnchor.constraint(equalToConstant: 22),
            close.widthAnchor.constraint(equalToConstant: 18),
            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        applyTheme()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        positionReference()
    }

    func positionReference() {
        guard !hasPositioned else { return }
        let page = previewPage
        view.layoutSubtreeIfNeeded()
        guard preview.bounds.width > 24, preview.bounds.height > 24 else { return }
        hasPositioned = true
        preview.go(to: page)
        preview.layoutDocumentView()
        let pageBounds = page.bounds(for: .cropBox)
        let width = preview.convert(pageBounds, from: page).width
        guard width > 0 else { return }
        preview.scaleFactor *= (preview.bounds.width - 24) / width
        preview.layoutDocumentView()

        // PDF null coordinates mean the page edge. Work in view coordinates so
        // the crop remains upright for rotated pages as well.
        let point = NSPoint(
            x: Self.coordinate(destination.point.x, lower: pageBounds.minX, upper: pageBounds.maxX, unspecified: pageBounds.minX),
            y: Self.coordinate(destination.point.y, lower: pageBounds.minY, upper: pageBounds.maxY, unspecified: pageBounds.maxY)
        )
        let target = preview.convert(point, from: page)
        let pageRect = preview.convert(pageBounds, from: page)
        let height = min(preview.bounds.height - 16, pageRect.height)
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
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NightModeStyle.readerBackdropColor.cgColor
            pageLabel.textColor = NightModeStyle.secondaryTextColor
            preview.backgroundColor = NightModeStyle.readerBackdropColor
            preview.contentFilters = NightModeStyle.makePDFContentFilters(for: NSApp.effectiveAppearance)
        }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
    @objc private func jumpToReference() { onNavigate?() }
    @objc private func closePreview() { onClose?() }
}
