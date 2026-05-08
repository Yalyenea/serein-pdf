import AppKit
import PDFKit

private final class ReaderPaneHostView: NSView {
    var isFocused: Bool = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            layer?.borderColor = isFocused ? SplitViewController.chromeStrokeColor.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isFocused ? 1 : 0
        }
    }
}

final class ReaderWorkspaceViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    let primaryReaderViewController: ReaderViewController
    let secondaryReaderViewController: ReaderViewController
    var onFocusedReaderDidChange: ((PDFView) -> Void)?

    private let splitView = NSSplitView()
    private let primaryHostView = ReaderPaneHostView()
    private let secondaryHostView = ReaderPaneHostView()
    private var appliedSplitEnabled: Bool?
    private var pendingSplitGeometryUpdate = false

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.primaryReaderViewController = ReaderViewController(
            documentStore: documentStore,
            windowID: windowID
        )
        self.secondaryReaderViewController = ReaderViewController(
            documentStore: documentStore,
            windowID: windowID
        )
        super.init(nibName: nil, bundle: nil)
        title = "Reader Workspace"
        addChild(primaryReaderViewController)
        addChild(secondaryReaderViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        primaryReaderViewController.onFocusRequested = { [weak self] in
            guard let self else { return }
            self.documentStore.setFocusedPane(.primary, in: self.windowID)
        }
        secondaryReaderViewController.onFocusRequested = { [weak self] in
            guard let self else { return }
            self.documentStore.setFocusedPane(.secondary, in: self.windowID)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        syncFromStore()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyPendingSplitGeometryUpdate()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        for host in [primaryHostView, secondaryHostView] {
            host.translatesAutoresizingMaskIntoConstraints = false
            splitView.addSubview(host)
        }

        embed(primaryReaderViewController, in: primaryHostView)
        embed(secondaryReaderViewController, in: secondaryHostView)

        container.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            primaryHostView.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            secondaryHostView.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])

        view = container
    }

    func activeReaderViewController() -> ReaderViewController {
        documentStore.focusedPane(in: windowID) == .secondary && documentStore.isSplitEnabled(in: windowID)
            ? secondaryReaderViewController
            : primaryReaderViewController
    }

    func toggleSplit() {
        documentStore.setSplitEnabled(!documentStore.isSplitEnabled(in: windowID), in: windowID)
    }

    func fitToWidth() {
        activeReaderViewController().fitToWidth()
    }

    func fitToHeight() {
        activeReaderViewController().fitToHeight()
    }

    func fitToPage() {
        activeReaderViewController().fitToPage()
    }

    func zoomIn() {
        activeReaderViewController().zoomIn()
    }

    func zoomOut() {
        activeReaderViewController().zoomOut()
    }

    func goToNextPage() {
        let reader = activeReaderViewController()
        guard reader.goToNextPage() == false else { return }
        goToContinuousReadingBoundary(direction: 1)
    }

    func goToPreviousPage() {
        let reader = activeReaderViewController()
        guard reader.goToPreviousPage() == false else { return }
        goToContinuousReadingBoundary(direction: -1)
    }

    func scrollHalfPageDown() {
        let reader = activeReaderViewController()
        guard reader.scrollHalfPageDown() == false else { return }
        goToContinuousReadingBoundary(direction: 1)
    }

    func scrollHalfPageUp() {
        let reader = activeReaderViewController()
        guard reader.scrollHalfPageUp() == false else { return }
        goToContinuousReadingBoundary(direction: -1)
    }

    func goToFirstPage() {
        activeReaderViewController().goToFirstPage()
    }

    func goToLastPage() {
        activeReaderViewController().goToLastPage()
    }

    func navigateBack() {
        activeReaderViewController().navigateBack()
    }

    func navigateForward() {
        activeReaderViewController().navigateForward()
    }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        activeReaderViewController().goToPage(pageIndex)
    }

    private func goToContinuousReadingBoundary(direction: Int) {
        let focusedPane = documentStore.focusedPane(in: windowID)
        guard let sessionID = documentStore.displayedSessionID(for: focusedPane, in: windowID),
              let target = documentStore.continuousReadingTarget(from: sessionID, direction: direction, in: windowID) else {
            return
        }
        documentStore.updateCurrentPage(index: target.pageIndex, for: target.sessionID)
        documentStore.activate(sessionID: target.sessionID, in: windowID, targetPane: focusedPane)
    }

    @discardableResult
    func triggerHighlightShortcut() -> Bool {
        activeReaderViewController().triggerHighlightShortcut()
    }

    func exitHighlightMode() {
        activeReaderViewController().exitHighlightMode()
    }

    func setHighlightColor(_ color: HighlightColor) {
        activeReaderViewController().setHighlightColor(color)
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        activeReaderViewController().removeHighlightUnderCursor()
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        activeReaderViewController().undoLastHighlight()
    }

    @discardableResult
    func redoLastHighlight() -> Bool {
        activeReaderViewController().redoLastHighlight()
    }

    func toggleNightMode() {
        activeReaderViewController().toggleNightMode()
    }

    func refreshThemeAppearance() {
        primaryReaderViewController.refreshThemeAppearance()
        secondaryReaderViewController.refreshThemeAppearance()
    }

    func saveAnnotations() throws {
        try activeReaderViewController().saveAnnotations()
    }

    func focus(on highlight: DocumentHighlightGroup) {
        activeReaderViewController().focus(on: highlight)
    }

    func showFindBar(scope: SearchScope? = nil) {
        activeReaderViewController().showFindBar(scope: scope)
    }

    func hideFindBar() {
        activeReaderViewController().hideFindBar()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        syncFromStore()
    }

    private func syncFromStore() {
        primaryReaderViewController.targetSessionID = documentStore.displayedSessionID(for: .primary, in: windowID)
        secondaryReaderViewController.targetSessionID = documentStore.displayedSessionID(for: .secondary, in: windowID)

        syncSearchHighlights(
            for: primaryReaderViewController,
            sessionID: documentStore.displayedSessionID(for: .primary, in: windowID)
        )
        syncSearchHighlights(
            for: secondaryReaderViewController,
            sessionID: documentStore.displayedSessionID(for: .secondary, in: windowID)
        )

        let splitEnabled = documentStore.isSplitEnabled(in: windowID)
        let splitStateChanged = appliedSplitEnabled != splitEnabled
        secondaryHostView.isHidden = !splitEnabled
        if splitEnabled, splitView.subviews.count > 1 {
            splitView.subviews[1].isHidden = false
        }
        if splitStateChanged {
            scheduleSplitGeometryUpdateIfNeeded()
        }

        let focusedPane = documentStore.focusedPane(in: windowID)
        primaryHostView.isFocused = focusedPane == .primary || splitEnabled == false
        secondaryHostView.isFocused = splitEnabled && focusedPane == .secondary
        onFocusedReaderDidChange?(activeReaderViewController().pdfView)
    }

    private func syncSearchHighlights(for reader: ReaderViewController, sessionID: UUID?) {
        let query = documentStore.searchQuery(in: windowID)
        guard let sessionID,
              let session = documentStore.session(for: sessionID),
              query.isEmpty == false,
              session.searchCache.query == query else {
            reader.clearSearchResults()
            return
        }

        reader.applySearchResults(session.searchCache.matches, selectedMatchIndex: nil)
    }

    private func embed(_ controller: NSViewController, in hostView: NSView) {
        let childView = controller.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            childView.topAnchor.constraint(equalTo: hostView.topAnchor),
            childView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
    }

    private func scheduleSplitGeometryUpdateIfNeeded() {
        guard pendingSplitGeometryUpdate == false else { return }
        pendingSplitGeometryUpdate = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingSplitGeometryUpdate()
        }
    }

    private func applyPendingSplitGeometryUpdate() {
        guard pendingSplitGeometryUpdate else { return }
        guard splitView.subviews.count > 1, splitView.bounds.width > 0 else { return }

        pendingSplitGeometryUpdate = false
        let splitEnabled = documentStore.isSplitEnabled(in: windowID)
        if splitEnabled {
            splitView.subviews[1].isHidden = false
            splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
        } else {
            splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
        }
        splitView.adjustSubviews()
        appliedSplitEnabled = splitEnabled
    }
}
