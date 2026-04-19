import AppKit
import PDFKit

private final class CollapsibleContainerView: NSView {
    override var fittingSize: NSSize {
        NSSize(width: 1, height: super.fittingSize.height)
    }
}

final class RightSidebarViewController: NSViewController {
    enum Mode: Int { case outline = 0, pages = 1 }

    let documentStore: DocumentStore
    let outlineViewController: OutlineViewController
    private let thumbnailView = PDFThumbnailView()
    private let modeSegmented = NSSegmentedControl()
    private var mode: Mode = .outline
    private var lastAppliedThumbnailWidth: CGFloat = 0
    private var lastAppliedThumbnailColumns: Int = 1
    private var outlineModeConstraints: [NSLayoutConstraint] = []
    private var pagesModeConstraints: [NSLayoutConstraint] = []
    private var thumbnailContentWidth: NSLayoutConstraint?

    private static let thumbnailCellSpacing: CGFloat = 4

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.outlineViewController = OutlineViewController(documentStore: documentStore)
        super.init(nibName: nil, bundle: nil)
        title = "Outline"
        addChild(outlineViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pdfView: PDFView) {
        thumbnailView.pdfView = pdfView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyMode()
    }

    override func loadView() {
        let container = CollapsibleContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        container.layer?.masksToBounds = true

        modeSegmented.segmentCount = 2
        modeSegmented.setImage(
            NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Outline"),
            forSegment: 0)
        modeSegmented.setImage(
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Pages"),
            forSegment: 1)
        modeSegmented.setWidth(26, forSegment: 0)
        modeSegmented.setWidth(26, forSegment: 1)
        modeSegmented.setToolTip("Outline", forSegment: 0)
        modeSegmented.setToolTip("Pages", forSegment: 1)
        modeSegmented.selectedSegment = 0
        modeSegmented.controlSize = .mini
        modeSegmented.segmentStyle = .rounded
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        modeSegmented.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modeSegmented.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        thumbnailView.thumbnailSize = NSSize(width: 96, height: 128)
        thumbnailView.maximumNumberOfColumns = 1
        thumbnailView.backgroundColor = .clear
        thumbnailView.wantsLayer = true
        thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        thumbnailView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let outlineView = outlineViewController.view
        outlineView.translatesAutoresizingMaskIntoConstraints = false

        for view in [modeSegmented, outlineView, thumbnailView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        let segmentedLeading = modeSegmented.leadingAnchor.constraint(
            greaterThanOrEqualTo: container.leadingAnchor, constant: 6)
        let segmentedTrailing = modeSegmented.trailingAnchor.constraint(
            lessThanOrEqualTo: container.trailingAnchor, constant: -6)
        segmentedLeading.priority = .defaultHigh
        segmentedTrailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            modeSegmented.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            segmentedLeading,
            segmentedTrailing,
            modeSegmented.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
        ])

        outlineModeConstraints = [
            outlineView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outlineView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outlineView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            outlineView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        outlineModeConstraints.forEach { $0.priority = .defaultHigh }

        let widthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 96)
        widthConstraint.priority = .defaultHigh
        thumbnailContentWidth = widthConstraint

        pagesModeConstraints = [
            thumbnailView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            thumbnailView.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            thumbnailView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            widthConstraint,
        ]

        NSLayoutConstraint.activate(outlineModeConstraints)

        view = container
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .outline
        applyMode()
    }

    private func applyMode() {
        let isOutline = mode == .outline

        if isOutline {
            NSLayoutConstraint.deactivate(pagesModeConstraints)
            NSLayoutConstraint.activate(outlineModeConstraints)
        } else {
            NSLayoutConstraint.deactivate(outlineModeConstraints)
            NSLayoutConstraint.activate(pagesModeConstraints)
        }

        outlineViewController.view.isHidden = !isOutline
        thumbnailView.isHidden = isOutline

        view.needsLayout = true
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        }
        outlineViewController.refreshChromeColors()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        adjustThumbnailSizeForWidth()
    }

    private func adjustThumbnailSizeForWidth() {
        let available = max(view.bounds.width - 8, 32)
        let visibleHeight = max(view.bounds.height - 56, 240)
        let rowSpacing: CGFloat = 6
        let maxRowHeight = max(visibleHeight / 5 - rowSpacing, 70)
        let widthFromHeight = maxRowHeight / 1.414

        let columns: Int
        if available >= 260 {
            columns = 3
        } else if available >= 160 {
            columns = 2
        } else {
            columns = 1
        }
        let spacing = Self.thumbnailCellSpacing
        let columnWidth = (available - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let targetWidth = max(40, min(columnWidth, widthFromHeight, 150))
        let contentWidth = CGFloat(columns) * targetWidth + CGFloat(max(columns - 1, 0)) * spacing

        thumbnailContentWidth?.constant = contentWidth

        guard abs(targetWidth - lastAppliedThumbnailWidth) > 0.5
            || columns != lastAppliedThumbnailColumns else { return }
        lastAppliedThumbnailWidth = targetWidth
        lastAppliedThumbnailColumns = columns
        thumbnailView.maximumNumberOfColumns = columns
        thumbnailView.thumbnailSize = NSSize(width: targetWidth, height: targetWidth * 1.414)
    }

    func toggleMode() {
        setMode(mode == .outline ? .pages : .outline)
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        modeSegmented.selectedSegment = newMode.rawValue
        applyMode()
    }
}
