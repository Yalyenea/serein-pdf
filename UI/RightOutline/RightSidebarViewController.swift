import AppKit
import PDFKit

private final class CollapsibleContainerView: NSView {
    override var fittingSize: NSSize {
        NSSize(width: 1, height: super.fittingSize.height)
    }
}

final class RightSidebarViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    let outlineViewController: OutlineViewController
    let searchResultsViewController: SearchResultsViewController
    let annotationsViewController: AnnotationsViewController
    var onActivateSearchMatch: ((SearchSidebarMatch) -> Void)?
    var onSearchSelectionDidChange: ((Int?, Int) -> Void)?
    var onActivateAnnotation: ((DocumentHighlightGroup) -> Void)?
    private let thumbnailView = PDFThumbnailView()
    private let modeSegmented = NSSegmentedControl()
    private var lastAppliedThumbnailWidth: CGFloat = 0
    private var lastAppliedThumbnailColumns: Int = 1
    private var outlineModeConstraints: [NSLayoutConstraint] = []
    private var pagesModeConstraints: [NSLayoutConstraint] = []
    private var searchModeConstraints: [NSLayoutConstraint] = []
    private var annotationsModeConstraints: [NSLayoutConstraint] = []
    private var thumbnailContentWidth: NSLayoutConstraint?

    private static let thumbnailCellSpacing: CGFloat = 4

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.outlineViewController = OutlineViewController(documentStore: documentStore, windowID: windowID)
        self.searchResultsViewController = SearchResultsViewController(documentStore: documentStore, windowID: windowID)
        self.annotationsViewController = AnnotationsViewController(documentStore: documentStore, windowID: windowID)
        super.init(nibName: nil, bundle: nil)
        title = "Outline"
        addChild(outlineViewController)
        addChild(searchResultsViewController)
        addChild(annotationsViewController)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        searchResultsViewController.onActivateMatch = { [weak self] match in
            self?.onActivateSearchMatch?(match)
        }
        searchResultsViewController.onSelectionChanged = { [weak self] selectedIndex, total in
            self?.onSearchSelectionDidChange?(selectedIndex, total)
        }
        annotationsViewController.onActivateHighlight = { [weak self] group in
            self?.onActivateAnnotation?(group)
        }
        applyMode()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = CollapsibleContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        container.layer?.masksToBounds = true

        modeSegmented.segmentCount = 4
        modeSegmented.setImage(
            NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Outline"),
            forSegment: 0)
        modeSegmented.setImage(
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Pages"),
            forSegment: 1)
        modeSegmented.setImage(
            NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search"),
            forSegment: 2)
        modeSegmented.setImage(
            NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Annotations"),
            forSegment: 3)
        modeSegmented.setWidth(26, forSegment: 0)
        modeSegmented.setWidth(26, forSegment: 1)
        modeSegmented.setWidth(26, forSegment: 2)
        modeSegmented.setWidth(26, forSegment: 3)
        modeSegmented.setToolTip("Outline", forSegment: 0)
        modeSegmented.setToolTip("Pages", forSegment: 1)
        modeSegmented.setToolTip("Search", forSegment: 2)
        modeSegmented.setToolTip("Annotations", forSegment: 3)
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
        let searchView = searchResultsViewController.view
        searchView.translatesAutoresizingMaskIntoConstraints = false
        let annotationsView = annotationsViewController.view
        annotationsView.translatesAutoresizingMaskIntoConstraints = false

        for view in [modeSegmented, outlineView, thumbnailView, searchView, annotationsView] {
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

        searchModeConstraints = [
            searchView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            searchView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        annotationsModeConstraints = [
            annotationsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            annotationsView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            annotationsView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            annotationsView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        NSLayoutConstraint.activate(outlineModeConstraints)

        view = container
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        setMode(RightSidebarMode(rawValue: sender.selectedSegment) ?? .outline)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        applyStateFromStore()
        let summary = searchResultsViewController.selectionSummary()
        onSearchSelectionDidChange?(summary.selectedIndex, summary.totalMatches)
    }

    private func applyMode() {
        switch documentStore.rightSidebarMode(in: windowID) {
        case .outline:
            NSLayoutConstraint.deactivate(pagesModeConstraints)
            NSLayoutConstraint.deactivate(searchModeConstraints)
            NSLayoutConstraint.deactivate(annotationsModeConstraints)
            NSLayoutConstraint.activate(outlineModeConstraints)
        case .pages:
            NSLayoutConstraint.deactivate(outlineModeConstraints)
            NSLayoutConstraint.deactivate(searchModeConstraints)
            NSLayoutConstraint.deactivate(annotationsModeConstraints)
            NSLayoutConstraint.activate(pagesModeConstraints)
        case .search:
            NSLayoutConstraint.deactivate(outlineModeConstraints)
            NSLayoutConstraint.deactivate(pagesModeConstraints)
            NSLayoutConstraint.deactivate(annotationsModeConstraints)
            NSLayoutConstraint.activate(searchModeConstraints)
        case .annotations:
            NSLayoutConstraint.deactivate(outlineModeConstraints)
            NSLayoutConstraint.deactivate(pagesModeConstraints)
            NSLayoutConstraint.deactivate(searchModeConstraints)
            NSLayoutConstraint.activate(annotationsModeConstraints)
        }

        let mode = documentStore.rightSidebarMode(in: windowID)
        outlineViewController.view.isHidden = mode != .outline
        thumbnailView.isHidden = mode != .pages
        searchResultsViewController.view.isHidden = mode != .search
        annotationsViewController.view.isHidden = mode != .annotations

        view.needsLayout = true
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        }
        outlineViewController.refreshChromeColors()
        searchResultsViewController.refreshChromeColors()
        annotationsViewController.refreshChromeColors()
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
        documentStore.toggleRightSidebarMode(in: windowID)
    }

    func setMode(_ newMode: RightSidebarMode) {
        documentStore.setRightSidebarMode(newMode, in: windowID)
    }

    func applyStateFromStore() {
        let mode = documentStore.rightSidebarMode(in: windowID)
        modeSegmented.selectedSegment = mode.rawValue
        applyMode()
    }

    func selectNextSearchMatch(activate: Bool) -> SearchSidebarMatch? {
        let match = searchResultsViewController.selectNextMatch()
        if activate, let selected = match {
            onActivateSearchMatch?(selected)
        }
        return match
    }

    func selectPreviousSearchMatch(activate: Bool) -> SearchSidebarMatch? {
        let match = searchResultsViewController.selectPreviousMatch()
        if activate, let selected = match {
            onActivateSearchMatch?(selected)
        }
        return match
    }

    func activateSelectedSearchMatch() -> SearchSidebarMatch? {
        searchResultsViewController.activateSelectedMatch()
    }
}
