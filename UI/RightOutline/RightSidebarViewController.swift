import AppKit
import PDFKit

private final class CollapsibleContainerView: SidebarMaterialView {
    override var fittingSize: NSSize {
        NSSize(width: 1, height: super.fittingSize.height)
    }
}

/// Captures the reader origin before PDFKit handles a Pages-sidebar click.
/// PDFThumbnailView otherwise changes the PDFView directly, leaving no reliable
/// way to distinguish the click from ordinary scrolling after the fact.
final class NavigationTrackingPDFThumbnailView: PDFThumbnailView {
    var onWillNavigate: (() -> Void)?
    var onDidNavigate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        notifyWillNavigate()
        super.mouseDown(with: event)
        notifyDidNavigate()
    }

    func notifyWillNavigate() {
        onWillNavigate?()
    }

    func notifyDidNavigate() {
        onDidNavigate?()
    }

}

final class RightSidebarViewController: NSViewController {
    private static let contentInset: CGFloat = 8
    let documentStore: DocumentStore
    let windowID: UUID
    let outlineViewController: OutlineViewController
    let searchResultsViewController: SearchResultsViewController
    let annotationsViewController: AnnotationsViewController
    var onActivateSearchMatch: ((SearchSidebarMatch) -> Void)?
    var onSearchSelectionDidChange: ((Int?, Int) -> Void)?
    var onActivateAnnotation: ((DocumentHighlightGroup) -> Void)?
    var onDeleteAnnotation: ((DocumentHighlightGroup) -> Void)?
    var onChangeAnnotationColor: ((DocumentHighlightGroup, HighlightColor) -> Void)?
    var onWillNavigateFromPages: (() -> Void)?
    var onDidNavigateFromPages: (() -> Void)?
    private let thumbnailView = NavigationTrackingPDFThumbnailView()
    private weak var configuredPDFView: PDFView?
    private let modeSegmented = NSSegmentedControl()
    private let emptyStateView = EmptyStateView(
        title: "No Document Open",
        detail: "Open a PDF to see its outline and notes."
    )
    private var lastAppliedDocumentPresence: Bool?
    private var lastAppliedThumbnailWidth: CGFloat = 0
    private var lastAppliedThumbnailColumns: Int = 1
    private var outlineModeConstraints: [NSLayoutConstraint] = []
    private var pagesModeConstraints: [NSLayoutConstraint] = []
    private var searchModeConstraints: [NSLayoutConstraint] = []
    private var annotationsModeConstraints: [NSLayoutConstraint] = []
    private var thumbnailContentWidth: NSLayoutConstraint?
    private var appliedMode: RightSidebarMode?
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
        configuredPDFView = pdfView
        updateThumbnailBinding()
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
        annotationsViewController.onDeleteHighlight = { [weak self] group in
            self?.onDeleteAnnotation?(group)
        }
        annotationsViewController.onChangeHighlightColor = { [weak self] group, color in
            self?.onChangeAnnotationColor?(group, color)
        }
        thumbnailView.onWillNavigate = { [weak self] in
            self?.onWillNavigateFromPages?()
        }
        thumbnailView.onDidNavigate = { [weak self] in
            self?.onDidNavigateFromPages?()
        }
        applyMode()
        applyDocumentPresence()
        updateThumbnailBinding()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = CollapsibleContainerView()
        container.applySurface()
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

        // The empty state defaults to visible: an empty window should show it
        // even if no store notification arrived before loadView. Keep whatever
        // applyDocumentPresence already set when it ran earlier.
        emptyStateView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [modeSegmented, outlineView, thumbnailView, searchView, emptyStateView] {
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

        // M12-014: the no-document state centers its copy instead of leaving a
        // titlebar-anchored dead zone.
        NSLayoutConstraint.activate([
            emptyStateView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: 16),
            emptyStateView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -16),
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
                greaterThanOrEqualTo: container.leadingAnchor, constant: Self.contentInset),
            thumbnailView.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -Self.contentInset),
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

        NSLayoutConstraint.activate(outlineModeConstraints)

        view = container
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        setMode(RightSidebarMode(rawValue: sender.selectedSegment) ?? .outline)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        // Outline/search/annotations controllers observe the store themselves for content.
        guard notification.isOnlyReadingPositionChange == false else { return }
        let change = notification.documentStoreChange
        if change.intersection([.content, .tabs, .rightSidebarMode, .sidebarVisibility, .appearance]).isEmpty == false {
            applyStateFromStore()
        }
        if change.intersection([.content, .tabs, .search]).isEmpty == false {
            let summary = searchResultsViewController.selectionSummary()
            onSearchSelectionDidChange?(summary.selectedIndex, summary.totalMatches)
        }
    }

    /// M12-011: without a PDF document (no active session, or a blank tab) the
    /// segmented chrome and mode panes are noise — hide them and show one shared
    /// centered empty state instead. Mode machinery stays intact underneath so
    /// pane lazy-loading and mode memory survive the transition.
    private func applyDocumentPresence() {
        let hasDocument = activeDocument() != nil
        guard hasDocument != lastAppliedDocumentPresence else { return }
        lastAppliedDocumentPresence = hasDocument

        modeSegmented.isHidden = !hasDocument
        emptyStateView.isHidden = hasDocument
        setModeContentHidden(!hasDocument)
        view.needsLayout = true
    }

    private func setModeContentHidden(_ hidden: Bool) {
        outlineViewController.view.isHidden = hidden || appliedMode != .outline
        thumbnailView.isHidden = hidden || appliedMode != .pages
        searchResultsViewController.view.isHidden = hidden || appliedMode != .search
        if annotationsViewController.isViewLoaded {
            annotationsViewController.view.isHidden = hidden || appliedMode != .annotations
        }
    }

    private func activeDocument() -> DocumentSession? {
        guard let session = documentStore.activeSession(in: windowID) else { return nil }
        return session.isBlank ? nil : session
    }

    private func applyMode() {
        let mode = documentStore.rightSidebarMode(in: windowID)
        guard appliedMode != mode else { return }

        switch mode {
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
            ensureAnnotationsViewLoaded()
            NSLayoutConstraint.activate(annotationsModeConstraints)
        }

        appliedMode = mode
        setModeContentHidden(emptyStateView.isHidden == false)

        view.needsLayout = true
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            (view as? SidebarMaterialView)?.applySurface()
        }
        emptyStateView.refreshChromeColors()
        outlineViewController.refreshChromeColors()
        searchResultsViewController.refreshChromeColors()
        if annotationsViewController.isViewLoaded {
            annotationsViewController.refreshChromeColors()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard thumbnailView.pdfView != nil else { return }
        adjustThumbnailSizeForWidth()
    }

    private func updateThumbnailBinding() {
        guard isViewLoaded else { return }
        let sidebarVisible = documentStore.appConfiguration.layout.sidebarsSwapped
            ? documentStore.isLeftSidebarVisible(in: windowID)
            : documentStore.isRightSidebarVisible(in: windowID)
        let showsPages = sidebarVisible && appliedMode == .pages && activeDocument() != nil
        let pdfView = showsPages ? configuredPDFView : nil
        guard thumbnailView.pdfView !== pdfView else { return }
        if pdfView != nil {
            adjustThumbnailSizeForWidth()
        }
        // PDFThumbnailView observes and rasterizes its PDFView even while hidden.
        // Keep the reader weakly until the Pages pane is actually visible.
        thumbnailView.pdfView = pdfView
    }

    private func adjustThumbnailSizeForWidth() {
        let available = max(view.bounds.width - Self.contentInset * 2, 32)
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

    var selectedAnnotationGroupID: String? {
        annotationsViewController.isViewLoaded ? annotationsViewController.selectedGroupID : nil
    }

    func applyStateFromStore() {
        let mode = documentStore.rightSidebarMode(in: windowID)
        modeSegmented.selectedSegment = mode.rawValue
        applyMode()
        applyDocumentPresence()
        updateThumbnailBinding()
    }

    private func ensureAnnotationsViewLoaded() {
        guard annotationsModeConstraints.isEmpty else { return }
        let annotationsView = annotationsViewController.view
        annotationsView.translatesAutoresizingMaskIntoConstraints = false
        annotationsView.isHidden = false
        view.addSubview(annotationsView)

        annotationsModeConstraints = [
            annotationsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            annotationsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            annotationsView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            annotationsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
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

#if DEBUG
extension RightSidebarViewController {
    var testingEmptyStateVisible: Bool {
        emptyStateView.isHidden == false
    }

    var testingSegmentedHidden: Bool {
        modeSegmented.isHidden
    }
}
#endif
