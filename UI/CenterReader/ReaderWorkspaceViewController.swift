import AppKit
import PDFKit

private final class ReaderPaneHostView: NSView {
    var isFocused: Bool = false {
        didSet {
            guard oldValue != isFocused else { return }
            updateAppearance()
        }
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

final class ReaderWorkspaceViewController: NSViewController, NSPopoverDelegate {
    private static let sideBySideMinimumPaneWidth: CGFloat = 320
    private static let stackedMinimumPaneHeight: CGFloat = 160

    let documentStore: DocumentStore
    let windowID: UUID
    let primaryReaderViewController: ReaderViewController
    let secondaryReaderViewController: ReaderViewController
    let floatingOutlineViewController: FloatingOutlineViewController
    var onFocusedReaderDidChange: ((PDFView) -> Void)?
    private(set) var isReadingFocusModeEnabled = false
    private(set) var isPresentationEnabled = false
    private(set) var readingFocusSettingsOverride: ReadingFocusSettings?
    private var readingFocusControlsPopover: NSPopover?
    private weak var readingFocusControlsReader: ReaderViewController?

    var readingFocusSettings: ReadingFocusSettings {
        readingFocusSettingsOverride ?? documentStore.appConfiguration.reader.readingFocus
    }

    private let splitView = NSSplitView()
    private let primaryHostView = ReaderPaneHostView()
    private let secondaryHostView = ReaderPaneHostView()
    private let splitCandidateBackdrop = NSView()
    private let splitCandidateLabel = NSTextField(labelWithString: "Second pane")
    private let splitCandidatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var sideBySideMinimumConstraints: [NSLayoutConstraint] = []
    private var stackedMinimumConstraints: [NSLayoutConstraint] = []
    private var appliedSplitEnabled: Bool?
    private var appliedSplitLayout: ReaderSplitLayout?
    private var appliedSecondarySessionID: UUID?
    private var displayedPrimarySessionID: UUID?
    private var displayedSecondarySessionID: UUID?
    private var appliedFocusedPane: ReaderPane?
    private var appliedReadingFocusSettings: ReadingFocusSettings?
    private var appliedSearchSource: SearchSnapshotSource?
    private var pendingSplitGeometryUpdate = false
    private var splitGeometryUpdateScheduled = false
    private var floatingOutlineWidthConstraint: NSLayoutConstraint!
    private var floatingOutlineHeightConstraint: NSLayoutConstraint!

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
        self.floatingOutlineViewController = FloatingOutlineViewController(
            documentStore: documentStore,
            windowID: windowID
        )
        super.init(nibName: nil, bundle: nil)
        secondaryReaderViewController.setLocalEventMonitoringEnabled(false)
        title = "Reader Workspace"
        addChild(primaryReaderViewController)
        addChild(secondaryReaderViewController)
        addChild(floatingOutlineViewController)
        floatingOutlineViewController.preferredSizeDidChange = { [weak self] _ in
            self?.applyFloatingOutlineSize()
        }
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
        primaryReaderViewController.onBookPageBoundaryRequested = { [weak self] direction in
            self?.turnBookPageAcrossBoundary(direction: direction, in: .primary) ?? false
        }
        secondaryReaderViewController.onBookPageBoundaryRequested = { [weak self] direction in
            self?.turnBookPageAcrossBoundary(direction: direction, in: .secondary) ?? false
        }
        primaryReaderViewController.onHistorySessionNavigationRequested = { [weak self] sessionID in
            guard let self else { return nil }
            return self.activateHistorySession(sessionID, in: .primary)
        }
        secondaryReaderViewController.onHistorySessionNavigationRequested = { [weak self] sessionID in
            guard let self else { return nil }
            return self.activateHistorySession(sessionID, in: .secondary)
        }
        floatingOutlineViewController.onNavigationRequested = { [weak self] request in
            _ = self?.navigate(to: request)
        }
        primaryReaderViewController.onOverviewPresentationDidChange = { [weak self] active in
            guard let self else { return }
            self.floatingOutlineViewController.setSuppressed(
                self.isPresentationEnabled || active || self.secondaryReaderViewController.isAllPagesOverviewActive
            )
        }
        secondaryReaderViewController.onOverviewPresentationDidChange = { [weak self] active in
            guard let self else { return }
            self.floatingOutlineViewController.setSuppressed(
                self.isPresentationEnabled || active || self.primaryReaderViewController.isAllPagesOverviewActive
            )
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
        requestSplitGeometryUpdate()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyFloatingOutlineSize()
        let splitLayout = documentStore.splitLayout(in: windowID)
        if pendingSplitGeometryUpdate, splitLength(for: splitLayout) > 0 {
            requestSplitGeometryUpdate()
        }
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
        installSplitCandidateView()

        container.addSubview(splitView)
        let floatingOutlineView = floatingOutlineViewController.view
        floatingOutlineView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(floatingOutlineView)
        floatingOutlineWidthConstraint = floatingOutlineView.widthAnchor.constraint(equalToConstant: 28)
        floatingOutlineHeightConstraint = floatingOutlineView.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            floatingOutlineView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            floatingOutlineView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            floatingOutlineWidthConstraint,
            floatingOutlineHeightConstraint,
        ])
        sideBySideMinimumConstraints = [
            primaryHostView.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Self.sideBySideMinimumPaneWidth
            ),
            secondaryHostView.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Self.sideBySideMinimumPaneWidth
            ),
        ]
        stackedMinimumConstraints = [
            primaryHostView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.stackedMinimumPaneHeight
            ),
            secondaryHostView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.stackedMinimumPaneHeight
            ),
        ]
        (sideBySideMinimumConstraints + stackedMinimumConstraints).forEach {
            $0.priority = .defaultLow
        }

        view = container
        applyFloatingOutlineSize()
    }

    func activeReaderViewController() -> ReaderViewController {
        documentStore.focusedPane(in: windowID) == .secondary && documentStore.isSplitEnabled(in: windowID)
            ? secondaryReaderViewController
            : primaryReaderViewController
    }

    func setPresentationEnabled(_ enabled: Bool) {
        isPresentationEnabled = enabled
        primaryReaderViewController.setPresentationEnabled(enabled)
        secondaryReaderViewController.setPresentationEnabled(enabled)
        floatingOutlineViewController.setSuppressed(
            enabled || primaryReaderViewController.isAllPagesOverviewActive
                || secondaryReaderViewController.isAllPagesOverviewActive
        )
    }

    var testingSplitView: NSSplitView {
        splitView
    }

    var testingActiveSplitMinimumConstraintCount: Int {
        (sideBySideMinimumConstraints + stackedMinimumConstraints).filter(\.isActive).count
    }

    var testingPrimaryPaneBorderWidth: CGFloat {
        primaryHostView.layer?.borderWidth ?? 0
    }

    var testingSecondaryPaneBorderWidth: CGFloat {
        secondaryHostView.layer?.borderWidth ?? 0
    }

    func toggleSplit() {
        documentStore.setSplitEnabled(!documentStore.isSplitEnabled(in: windowID), in: windowID)
    }

    func fitToWidth() {
        activeReaderViewController().fitToWidth()
    }

    /// After left/right chrome collapse or width pin, force readers to match the
    /// new center size (fit-width / fit-height reflow + recenter).
    func reflowReadersForChromeLayoutChange() {
        primaryReaderViewController.reflowForContainerSizeChange()
        secondaryReaderViewController.reflowForContainerSizeChange()
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
        _ = turnActivePage(direction: 1)
    }

    func goToPreviousPage() {
        _ = turnActivePage(direction: -1)
    }

    func scrollHalfPageDown() {
        let reader = activeReaderViewController()
        guard reader.scrollHalfPageDown() == false else { return }
        if reader.usesContinuousScrolling == false {
            guard reader.goToNextPage() == false else { return }
        }
        goToContinuousReadingBoundary(direction: 1)
    }

    func scrollHalfPageUp() {
        let reader = activeReaderViewController()
        guard reader.scrollHalfPageUp() == false else { return }
        if reader.usesContinuousScrolling == false {
            guard reader.goToPreviousPageBottom() == false else { return }
        }
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

    /// Shared exact destination route for right/floating Outline and future
    /// cross-document navigation sources.
    @discardableResult
    func navigate(to request: OutlineNavigationRequest) -> Bool {
        navigate(to: request.position, in: request.sessionID)
    }

    @discardableResult
    func navigate(to position: ReadingPosition, in sessionID: UUID) -> Bool {
        guard documentStore.session(for: sessionID) != nil else { return false }
        let reader = activeReaderViewController()
        let sameSession = reader.displayedSessionID == sessionID
        if sameSession == false {
            reader.recordCurrentPositionForNavigation()
            let focusedPane = documentStore.focusedPane(in: windowID)
            let targetPane = documentStore.isSplitEnabled(in: windowID) ? focusedPane : nil
            documentStore.activate(sessionID: sessionID, in: windowID, targetPane: targetPane)
            guard reader.displayedSessionID == sessionID else { return false }
        }
        return reader.go(to: position, recordHistory: sameSession)
    }

    @discardableResult
    private func turnBookPageAcrossBoundary(direction: Int, in pane: ReaderPane) -> Bool {
        documentStore.setFocusedPane(pane, in: windowID)
        return goToContinuousReadingBoundary(direction: direction, usesBookPageTurn: true)
    }

    @discardableResult
    private func turnActivePage(direction: Int) -> Bool {
        let reader = activeReaderViewController()
        let didTurn = direction > 0 ? reader.goToNextPage() : reader.goToPreviousPage()
        return didTurn || goToContinuousReadingBoundary(
            direction: direction,
            usesBookPageTurn: reader.usesBookLayout
        )
    }

    @discardableResult
    private func goToContinuousReadingBoundary(
        direction: Int,
        usesBookPageTurn: Bool = false
    ) -> Bool {
        let focusedPane = documentStore.focusedPane(in: windowID)
        guard let displayedSessionID = documentStore.displayedSessionID(for: focusedPane, in: windowID),
              let sourceSessionID = documentStore.publicSessionID(
                forDisplayedSessionID: displayedSessionID,
                in: windowID
              ),
              var target = documentStore.continuousReadingTarget(
                from: sourceSessionID,
                direction: direction,
                in: windowID
              ) else {
            return false
        }

        if usesBookPageTurn, direction < 0,
           documentStore.session(for: target.sessionID)?.displayMode.usesBookLayout == true,
           let document = try? documentStore.pdfDocument(for: target.sessionID),
           document.pageCount > 0,
           let page = document.page(at: document.pageCount - 1) {
            let lastPageIndex = document.pageCount - 1
            let bounds = page.bounds(for: .cropBox)
            target.readingPosition = ReadingPosition(
                pageIndex: lastPageIndex,
                point: NSPoint(x: bounds.maxX, y: bounds.maxY)
            )
        }
        let targetPane = documentStore.isSplitEnabled(in: windowID) ? focusedPane : nil
        return documentStore.activateContinuousReadingTarget(
            target,
            in: windowID,
            targetPane: targetPane
        ) != nil
    }

    private func activateHistorySession(_ sessionID: UUID, in pane: ReaderPane) -> UUID? {
        guard let requestedSession = documentStore.session(for: sessionID),
              let workspace = documentStore.windowWorkspace(for: windowID),
              workspace.sessionIDs.contains(sessionID)
                || workspace.primarySessionID == sessionID
                || workspace.secondarySessionID == sessionID else { return nil }
        let targetPane = documentStore.isSplitEnabled(in: windowID) ? pane : nil
        documentStore.activate(sessionID: sessionID, in: windowID, targetPane: targetPane)
        let resolvedPane: ReaderPane = documentStore.isSplitEnabled(in: windowID) ? pane : .primary
        guard let resolvedSessionID = documentStore.displayedSessionID(for: resolvedPane, in: windowID),
              documentStore.session(for: resolvedSessionID)?.url == requestedSession.url else { return nil }
        return resolvedSessionID
    }

    @discardableResult
    func triggerAnnotationShortcut(_ type: AnnotationMarkupType) -> Bool {
        activeReaderViewController().triggerAnnotationShortcut(type)
    }

    @discardableResult
    func addOrEditComment() -> Bool {
        activeReaderViewController().addOrEditComment()
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

    @discardableResult
    func toggleReadingFocusMode() -> Bool {
        isReadingFocusModeEnabled.toggle()
        primaryReaderViewController.setReadingFocusModeEnabled(isReadingFocusModeEnabled)
        secondaryReaderViewController.setReadingFocusModeEnabled(isReadingFocusModeEnabled)
        return isReadingFocusModeEnabled
    }

    var isHorizontalPanLocked: Bool {
        activeReaderViewController().isHorizontalPanLocked
    }

    @discardableResult
    func toggleHorizontalPanLock() -> Bool {
        activeReaderViewController().toggleHorizontalPanLock()
    }

    func setReadingFocusSettings(_ settings: ReadingFocusSettings) {
        readingFocusSettingsOverride = settings
        applyReadingFocusSettings()
    }

    func resetReadingFocusSettings() {
        readingFocusSettingsOverride = nil
        applyReadingFocusSettings()
    }

    func showReadingFocusControls() {
        guard documentStore.activeSession(in: windowID)?.isBlank == false else { return }
        if readingFocusControlsPopover?.isShown == true {
            readingFocusControlsPopover?.close()
            return
        }

        if isReadingFocusModeEnabled == false {
            _ = toggleReadingFocusMode()
        }

        let controls = ReadingFocusControlsViewController(
            settings: readingFocusSettings,
            defaultSettings: documentStore.appConfiguration.reader.readingFocus
        )
        controls.onSettingsChanged = { [weak self] settings in
            self?.setReadingFocusSettings(settings)
        }
        controls.onResetToDefaults = { [weak self, weak controls] in
            guard let self else { return }
            self.resetReadingFocusSettings()
            controls?.apply(
                settings: self.readingFocusSettings,
                defaultSettings: self.documentStore.appConfiguration.reader.readingFocus
            )
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controls
        readingFocusControlsPopover = popover

        let reader = activeReaderViewController()
        let readerView = reader.view
        let pointInView: NSPoint
        if let window = readerView.window {
            pointInView = readerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        } else {
            pointInView = NSPoint(x: readerView.bounds.midX, y: readerView.bounds.midY)
        }
        let anchorPoint = NSPoint(
            x: min(max(pointInView.x, readerView.bounds.minX + 8), readerView.bounds.maxX - 8),
            y: min(max(pointInView.y, readerView.bounds.minY + 8), readerView.bounds.maxY - 8)
        )
        readingFocusControlsReader = reader
        reader.setReadingFocusControlsPresented(true, anchorPointInView: anchorPoint)
        popover.show(
            relativeTo: NSRect(origin: anchorPoint, size: NSSize(width: 1, height: 1)),
            of: readerView,
            preferredEdge: .maxY
        )
    }

    func popoverDidClose(_ notification: Notification) {
        readingFocusControlsReader?.setReadingFocusControlsPresented(false)
        readingFocusControlsReader = nil
        readingFocusControlsPopover = nil
    }

    func refreshThemeAppearance() {
        primaryReaderViewController.refreshThemeAppearance()
        secondaryReaderViewController.refreshThemeAppearance()
        floatingOutlineViewController.refreshChromeColors()
        syncSplitCandidateView()
    }

    func saveAnnotations() throws {
        try activeReaderViewController().saveAnnotations()
    }

    func flushPendingReadingPositions() {
        primaryReaderViewController.flushPendingReadingPosition()
        secondaryReaderViewController.flushPendingReadingPosition()
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
        guard notification.affects(windowID: windowID) else { return }
        guard notification.isOnlySidebarChromeChange == false else { return }
        // Page/zoom writeback does not change pane layout or search highlight session targets.
        guard notification.isOnlyReadingPositionChange == false else { return }
        let change = notification.documentStoreChange
        guard change.intersection([.content, .tabs, .search, .appearance]).isEmpty == false else {
            return
        }
        syncFromStore(forceSearchRefresh: change.containsOnly(.search))
    }

    private func syncFromStore(forceSearchRefresh: Bool = true) {
        applyReadingFocusSettings()
        let primarySessionID = documentStore.displayedSessionID(for: .primary, in: windowID)
        let secondarySessionID = documentStore.displayedSessionID(for: .secondary, in: windowID)
        let primarySessionChanged = displayedPrimarySessionID != primarySessionID
        let secondaryTargetChanged = displayedSecondarySessionID != secondarySessionID
        if primarySessionChanged {
            displayedPrimarySessionID = primarySessionID
            primaryReaderViewController.targetSessionID = primarySessionID
        }
        if secondaryTargetChanged {
            displayedSecondarySessionID = secondarySessionID
            secondaryReaderViewController.targetSessionID = secondarySessionID
        }

        documentStore.rebuildSearchIfNeeded(in: windowID)
        let searchSource = documentStore.searchSnapshot(in: windowID).source
        if forceSearchRefresh || appliedSearchSource != searchSource || primarySessionChanged || secondaryTargetChanged {
            appliedSearchSource = searchSource
            syncSearchHighlights(for: primaryReaderViewController, sessionID: primarySessionID)
            syncSearchHighlights(for: secondaryReaderViewController, sessionID: secondarySessionID)
        }

        let splitEnabled = documentStore.isSplitEnabled(in: windowID)
        let splitLayout = documentStore.splitLayout(in: windowID)
        let splitStateChanged = appliedSplitEnabled != splitEnabled
        let splitLayoutChanged = appliedSplitLayout != splitLayout
        let secondarySessionChanged = appliedSecondarySessionID != secondarySessionID
        if splitStateChanged || splitLayoutChanged {
            applySplitLayout(splitLayout, splitEnabled: splitEnabled)
        }
        let secondaryShouldBeHidden = !splitEnabled
        if secondaryHostView.isHidden != secondaryShouldBeHidden {
            secondaryHostView.isHidden = secondaryShouldBeHidden
        }
        primaryReaderViewController.setLocalEventMonitoringEnabled(true)
        secondaryReaderViewController.setLocalEventMonitoringEnabled(splitEnabled)
        if splitStateChanged || splitLayoutChanged || (splitEnabled && secondarySessionChanged) {
            requestSplitGeometryUpdate()
        }

        let focusedPane = documentStore.focusedPane(in: windowID)
        let focusedPaneChanged = appliedFocusedPane != focusedPane
        appliedFocusedPane = focusedPane
        primaryHostView.isFocused = splitEnabled && focusedPane == .primary
        secondaryHostView.isFocused = splitEnabled && focusedPane == .secondary
        if splitStateChanged || primarySessionChanged || secondaryTargetChanged {
            syncSplitCandidateView()
        }
        if focusedPaneChanged || splitStateChanged || primarySessionChanged || secondaryTargetChanged {
            onFocusedReaderDidChange?(activeReaderViewController().pdfView)
        }
    }

    private func applyReadingFocusSettings() {
        let settings = readingFocusSettings
        guard appliedReadingFocusSettings != settings else { return }
        appliedReadingFocusSettings = settings
        primaryReaderViewController.setReadingFocusSettings(settings)
        secondaryReaderViewController.setReadingFocusSettings(settings)
    }

    private func installSplitCandidateView() {
        splitCandidateBackdrop.translatesAutoresizingMaskIntoConstraints = false
        splitCandidateBackdrop.wantsLayer = true
        splitCandidateBackdrop.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        splitCandidateBackdrop.isHidden = true

        splitCandidateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        splitCandidateLabel.textColor = NightModeStyle.secondaryTextColor
        splitCandidateLabel.alignment = .center
        splitCandidateLabel.translatesAutoresizingMaskIntoConstraints = false

        splitCandidatePopup.controlSize = .small
        splitCandidatePopup.font = .systemFont(ofSize: 12)
        splitCandidatePopup.target = self
        splitCandidatePopup.action = #selector(chooseSplitCandidate(_:))
        splitCandidatePopup.translatesAutoresizingMaskIntoConstraints = false
        splitCandidatePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let stack = NSStackView(views: [splitCandidateLabel, splitCandidatePopup])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        splitCandidateBackdrop.addSubview(stack)
        secondaryHostView.addSubview(splitCandidateBackdrop)
        NSLayoutConstraint.activate([
            splitCandidateBackdrop.leadingAnchor.constraint(equalTo: secondaryHostView.leadingAnchor),
            splitCandidateBackdrop.trailingAnchor.constraint(equalTo: secondaryHostView.trailingAnchor),
            splitCandidateBackdrop.topAnchor.constraint(equalTo: secondaryHostView.topAnchor),
            splitCandidateBackdrop.bottomAnchor.constraint(equalTo: secondaryHostView.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: splitCandidateBackdrop.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: splitCandidateBackdrop.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: splitCandidateBackdrop.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: splitCandidateBackdrop.trailingAnchor, constant: -24),
        ])
    }

    private func syncSplitCandidateView() {
        splitCandidateBackdrop.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        splitCandidateLabel.textColor = NightModeStyle.secondaryTextColor
        let candidates = documentStore.splitCandidateSessions(in: windowID)
        let shouldShow = documentStore.isSplitEnabled(in: windowID) &&
            documentStore.displayedSessionID(for: .secondary, in: windowID) == nil &&
            candidates.isEmpty == false
        splitCandidateBackdrop.isHidden = !shouldShow
        guard shouldShow else { return }

        splitCandidatePopup.removeAllItems()
        let primarySessionID = documentStore.displayedSessionID(for: .primary, in: windowID)
        for candidate in candidates {
            let title = candidate.id == primarySessionID ? "Same PDF - \(candidate.title)" : candidate.title
            splitCandidatePopup.addItem(withTitle: title)
            splitCandidatePopup.lastItem?.representedObject = candidate.id.uuidString
        }
    }

    @objc
    private func chooseSplitCandidate(_ sender: NSPopUpButton) {
        guard let uuidString = sender.selectedItem?.representedObject as? String,
              let sessionID = UUID(uuidString: uuidString) else { return }
        documentStore.activate(sessionID: sessionID, in: windowID, targetPane: .secondary)
    }

    private func syncSearchHighlights(for reader: ReaderViewController, sessionID: UUID?) {
        let snapshot = documentStore.searchSnapshot(in: windowID)
        guard let sessionID,
              snapshot.query.isEmpty == false else {
            reader.clearSearchResults()
            return
        }

        reader.applySearchResults(
            documentStore.searchSelections(for: sessionID, in: windowID),
            selectedMatchIndex: nil
        )
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

    private func applyFloatingOutlineSize() {
        guard isViewLoaded,
              floatingOutlineWidthConstraint != nil,
              floatingOutlineHeightConstraint != nil else { return }
        let maximumWidth = max(view.bounds.width - 28, 28)
        let maximumHeight = max(view.bounds.height - 48, 0)
        floatingOutlineViewController.setMaximumAvailableHeight(maximumHeight)
        let preferredSize = floatingOutlineViewController.preferredSize
        let width = min(preferredSize.width, maximumWidth)
        let height = min(preferredSize.height, maximumHeight)
        if abs(floatingOutlineWidthConstraint.constant - width) > 0.5 {
            floatingOutlineWidthConstraint.constant = width
        }
        if abs(floatingOutlineHeightConstraint.constant - height) > 0.5 {
            floatingOutlineHeightConstraint.constant = height
        }
    }

    private func requestSplitGeometryUpdate() {
        pendingSplitGeometryUpdate = true
        applyPendingSplitGeometryUpdate()
        guard pendingSplitGeometryUpdate else { return }
        guard splitGeometryUpdateScheduled == false else { return }
        splitGeometryUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.splitGeometryUpdateScheduled = false
            self?.applyPendingSplitGeometryUpdate()
        }
    }

    private func applySplitLayout(_ layout: ReaderSplitLayout, splitEnabled: Bool) {
        let allMinimumConstraints = sideBySideMinimumConstraints + stackedMinimumConstraints
        let activeMinimumConstraints: [NSLayoutConstraint]
        if splitEnabled {
            activeMinimumConstraints = switch layout {
            case .sideBySide:
                sideBySideMinimumConstraints
            case .stacked:
                stackedMinimumConstraints
            }
        } else {
            activeMinimumConstraints = []
        }
        for constraint in allMinimumConstraints {
            constraint.isActive = activeMinimumConstraints.contains { $0 === constraint }
        }

        if appliedSplitLayout != layout {
            splitView.isVertical = layout == .sideBySide
            appliedSplitLayout = layout
            splitView.needsLayout = true
        }
    }

    private func splitLength(for layout: ReaderSplitLayout) -> CGFloat {
        switch layout {
        case .sideBySide:
            splitView.bounds.width
        case .stacked:
            splitView.bounds.height
        }
    }

    private func applyPendingSplitGeometryUpdate() {
        guard pendingSplitGeometryUpdate else { return }
        let splitLayout = documentStore.splitLayout(in: windowID)
        let splitEnabled = documentStore.isSplitEnabled(in: windowID)
        applySplitLayout(splitLayout, splitEnabled: splitEnabled)
        let length = splitLength(for: splitLayout)
        guard splitView.subviews.count > 1, length > 0 else { return }

        pendingSplitGeometryUpdate = false
        let secondarySessionID = documentStore.displayedSessionID(for: .secondary, in: windowID)
        let shouldFitReadersToWidth = splitEnabled && (
            appliedSplitEnabled != splitEnabled || appliedSecondarySessionID != secondarySessionID
        )
        if splitEnabled {
            splitView.subviews[1].isHidden = false
            splitView.setPosition(length / 2, ofDividerAt: 0)
        } else {
            splitView.setPosition(length, ofDividerAt: 0)
            splitView.subviews[1].isHidden = true
        }
        splitView.adjustSubviews()
        if splitEnabled == false {
            splitView.subviews[1].isHidden = true
        }
        splitView.layoutSubtreeIfNeeded()
        appliedSplitEnabled = splitEnabled
        appliedSecondarySessionID = secondarySessionID
        fitReadersToWidthAfterSplitIfNeeded(shouldFitReadersToWidth)
    }

    private func fitReadersToWidthAfterSplitIfNeeded(_ shouldFit: Bool) {
        guard shouldFit else { return }
        view.layoutSubtreeIfNeeded()
        primaryReaderViewController.view.layoutSubtreeIfNeeded()
        secondaryReaderViewController.view.layoutSubtreeIfNeeded()
        primaryReaderViewController.fitToWidth()
        secondaryReaderViewController.fitToWidth()
    }
}
