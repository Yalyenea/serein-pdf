import AppKit
import PDFKit

private final class ReaderPaneHostView: NSView {
    var isFocused = false { didSet { if oldValue != isFocused { refreshAppearance() } } }
    var onSessionChosen: ((UUID) -> Void)?
    private let candidateBackdrop = NSView()
    private let candidatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let candidateLabel = NSTextField(labelWithString: "Choose a PDF")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func installCandidateView() {
        candidateBackdrop.translatesAutoresizingMaskIntoConstraints = false
        candidateBackdrop.wantsLayer = true
        candidateBackdrop.isHidden = true
        candidateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        candidateLabel.alignment = .center
        candidatePopup.controlSize = .small
        candidatePopup.font = .systemFont(ofSize: 12)
        candidatePopup.target = self
        candidatePopup.action = #selector(chooseCandidate(_:))
        let stack = NSStackView(views: [candidateLabel, candidatePopup])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        candidateBackdrop.addSubview(stack)
        addSubview(candidateBackdrop)
        NSLayoutConstraint.activate([
            candidateBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBackdrop.topAnchor.constraint(equalTo: topAnchor),
            candidateBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
        refreshAppearance()
    }

    func setCandidates(_ candidates: [DocumentSession], isVisible: Bool) {
        candidateBackdrop.isHidden = !isVisible || candidates.isEmpty
        guard isVisible else { return }
        candidatePopup.removeAllItems()
        candidatePopup.addItem(withTitle: "Choose a PDF…")
        for candidate in candidates {
            candidatePopup.addItem(withTitle: candidate.title)
            candidatePopup.lastItem?.representedObject = candidate.id
        }
    }

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = isFocused ? SplitViewController.chromeStrokeColor.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isFocused ? 1 : 0
            candidateBackdrop.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
            candidateLabel.textColor = NightModeStyle.secondaryTextColor
        }
    }

    @objc private func chooseCandidate(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? UUID else { return }
        onSessionChosen?(id)
    }
}

private final class ReaderWorkspaceContainerView: NSView {
    override var isFlipped: Bool { true }
}

final class ReaderWorkspaceViewController: NSViewController, NSPopoverDelegate {
    let documentStore: DocumentStore
    let windowID: UUID
    let floatingOutlineViewController: FloatingOutlineViewController
    var onFocusedReaderDidChange: ((PDFView) -> Void)?
    var readersDidChange: (() -> Void)?
    private(set) var isReadingFocusModeEnabled = false
    private(set) var isPresentationEnabled = false
    private(set) var readingFocusSettingsOverride: ReadingFocusSettings?

    var readingFocusSettings: ReadingFocusSettings {
        readingFocusSettingsOverride ?? documentStore.appConfiguration.reader.readingFocus
    }

    var allReaderViewControllers: [ReaderViewController] {
        orderedPaneIDs.compactMap { readers[$0] }
    }

    // These accessors retain their ordered-pane meaning for existing integrations.
    // Pane identity and layout are exclusively owned by DocumentStore.
    var primaryReaderViewController: ReaderViewController {
        loadViewIfNeeded()
        return readers[orderedPaneIDs[0]]!
    }

    var secondaryReaderViewController: ReaderViewController {
        loadViewIfNeeded()
        return readers[orderedPaneIDs.count > 1 ? orderedPaneIDs[1] : orderedPaneIDs[0]]!
    }

    private var readers: [ReaderPane: ReaderViewController] = [:]
    private var hosts: [ReaderPane: ReaderPaneHostView] = [:]
    private var splitHosts: [UUID: ReaderSplitHostView] = [:]
    private var orderedPaneIDs: [ReaderPane] = []
    private var recentFocus: [ReaderPane] = []
    private let contentContainer = ReaderWorkspaceContainerView()
    private let zoomContainer = ReaderWorkspaceContainerView()
    private var renderedRoot: NSView?
    private var rootConstraints: [NSLayoutConstraint] = []
    private var zoomConstraints: [NSLayoutConstraint] = []
    private var appliedLayout: ReaderLayoutNode?
    private var appliedGroupID: UUID?
    private var appliedZoomedPane: ReaderPane?
    private var appliedFocusedPane: ReaderPane?
    private var appliedSearchSource: SearchSnapshotSource?
    private var appliedReadingFocusSettings: ReadingFocusSettings?
    private var isSynchronizingFromStore = false
    private var dividerReadingPositions: [ReaderPane: ReadingPosition] = [:]
    private var overviewPaneIDs: Set<ReaderPane> = []
    private var readingFocusControlsPopover: NSPopover?
    private weak var readingFocusControlsReader: ReaderViewController?
    private var floatingOutlineWidthConstraint: NSLayoutConstraint!
    private var floatingOutlineHeightConstraint: NSLayoutConstraint!

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.floatingOutlineViewController = FloatingOutlineViewController(documentStore: documentStore, windowID: windowID)
        super.init(nibName: nil, bundle: nil)
        title = "Reader Workspace"
        addChild(floatingOutlineViewController)
        floatingOutlineViewController.preferredSizeDidChange = { [weak self] _ in self?.applyFloatingOutlineSize() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = ReaderWorkspaceContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        for child in [contentContainer, zoomContainer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                child.topAnchor.constraint(equalTo: container.topAnchor),
                child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        zoomContainer.isHidden = true
        let outline = floatingOutlineViewController.view
        outline.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(outline)
        floatingOutlineWidthConstraint = outline.widthAnchor.constraint(equalToConstant: 28)
        floatingOutlineHeightConstraint = outline.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            outline.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            outline.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            floatingOutlineWidthConstraint, floatingOutlineHeightConstraint,
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        floatingOutlineViewController.onNavigationRequested = { [weak self] request in _ = self?.navigate(to: request) }
        floatingOutlineViewController.onQuickNavigationEnded = { [weak self] in self?.focusActiveReader() }
        NotificationCenter.default.addObserver(self, selector: #selector(handleDocumentStoreDidChange),
                                               name: .documentStoreDidChange, object: documentStore)
        syncFromStore()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        renderedRoot?.frame = contentContainer.bounds
        if let pane = appliedZoomedPane { hosts[pane]?.frame = zoomContainer.bounds }
        applyFloatingOutlineSize()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func activeReaderViewController() -> ReaderViewController {
        loadViewIfNeeded()
        return readers[documentStore.focusedPane(in: windowID)] ?? primaryReaderViewController
    }

    func readerViewController(for pane: ReaderPane) -> ReaderViewController? { readers[pane] }

    func setPresentationEnabled(_ enabled: Bool) {
        isPresentationEnabled = enabled
        allReaderViewControllers.forEach { $0.setPresentationEnabled(enabled) }
        updateFloatingOutlineSuppression()
    }

    func focusActiveReader() {
        view.window?.makeFirstResponder(activeReaderViewController().pdfView)
    }

    @discardableResult
    func focusPane(direction: ReaderPaneDirection) -> Bool {
        guard let layout = documentStore.readerLayout(in: windowID),
              let target = ReaderPaneGeometry.neighbour(
                from: documentStore.focusedPane(in: windowID), direction: direction,
                frames: ReaderPaneGeometry.frames(for: layout, in: contentContainer.bounds), recentFocus: recentFocus
              ) else { return false }
        if documentStore.zoomedPane(in: windowID) != nil { documentStore.togglePaneZoom(in: windowID) }
        documentStore.setFocusedPane(target, in: windowID)
        focusActiveReader()
        return true
    }

    func togglePaneZoom() {
        flushPendingReadingPositions()
        documentStore.togglePaneZoom(in: windowID)
        focusActiveReader()
    }

    @discardableResult
    func closeFocusedPane() -> Bool {
        flushPendingReadingPositions()
        let closed = documentStore.closePane(documentStore.focusedPane(in: windowID), in: windowID)
        if closed { focusActiveReader() }
        return closed
    }

    func toggleSplit() {
        if documentStore.isSplitEnabled(in: windowID) == false,
           canSplitPane(documentStore.focusedPane(in: windowID), layout: documentStore.splitLayout(in: windowID)) == false {
            NSSound.beep()
            return
        }
        flushPendingReadingPositions()
        documentStore.setSplitEnabled(!documentStore.isSplitEnabled(in: windowID), in: windowID)
    }

    func canSplitPane(_ pane: ReaderPane? = nil, layout: ReaderSplitLayout) -> Bool {
        loadViewIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let tree = documentStore.readerLayout(in: windowID),
              let frame = ReaderPaneGeometry.frames(for: tree, in: contentContainer.bounds)[pane ?? documentStore.focusedPane(in: windowID)] else { return false }
        return ReaderPaneGeometry.canSplit(frame.size, layout: layout)
    }

    @discardableResult
    func splitActivePane(
        layout: ReaderSplitLayout, sessionID: UUID? = nil, readingPosition: ReadingPosition? = nil
    ) -> Bool {
        splitPane(from: documentStore.focusedPane(in: windowID), layout: layout,
                  sessionID: sessionID, readingPosition: readingPosition)
    }

    @discardableResult
    func splitPane(
        from pane: ReaderPane, layout: ReaderSplitLayout,
        sessionID: UUID? = nil, readingPosition: ReadingPosition? = nil
    ) -> Bool {
        guard canSplitPane(pane, layout: layout), let reader = readers[pane] else {
            NSSound.beep()
            return false
        }
        reader.flushPendingReadingPosition()
        let position = readingPosition ?? (sessionID == nil || sessionID == reader.displayedSessionID ? reader.currentPosition : nil)
        guard documentStore.splitPane(from: pane, layout: layout, sessionID: sessionID,
                                      readingPosition: position, in: windowID) != nil else { return false }
        focusActiveReader()
        return true
    }

    var testingSplitView: NSSplitView? { renderedRoot as? NSSplitView }
    var testingActiveSplitMinimumConstraintCount: Int { splitHosts.count * 2 }
    var testingPrimaryPaneBorderWidth: CGFloat { hosts[orderedPaneIDs.first ?? .primary]?.layer?.borderWidth ?? 0 }
    var testingSecondaryPaneBorderWidth: CGFloat { orderedPaneIDs.count > 1 ? hosts[orderedPaneIDs[1]]?.layer?.borderWidth ?? 0 : 0 }
    var testingPaneFrames: [ReaderPane: NSRect] {
        guard let tree = appliedLayout else { return [:] }
        return ReaderPaneGeometry.frames(for: tree, in: contentContainer.bounds)
    }
    func fitToWidth() {
        activeReaderViewController().fitToWidth()
    }

    func fitToTextWidth() {
        activeReaderViewController().fitToTextWidth()
    }

    /// After left/right chrome collapse or width pin, force readers to match the
    /// new center size (fit-width / fit-height reflow + recenter).
    func prepareReadersForChromeLayoutChange() {
        allReaderViewControllers.forEach { $0.prepareForChromeSizeChange() }
    }

    func reflowReadersForChromeLayoutChange() {
        allReaderViewControllers.forEach { $0.reflowForContainerSizeChange() }
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
        let sameDocument = isSameDocument(reader.displayedSessionID, sessionID)
        if sameDocument == false {
            reader.recordCurrentPositionForNavigation()
            let focusedPane = documentStore.focusedPane(in: windowID)
            let targetPane = documentStore.isSplitEnabled(in: windowID) ? focusedPane : nil
            documentStore.activate(sessionID: sessionID, in: windowID, targetPane: targetPane)
        }
        let destinationReader = activeReaderViewController()
        guard isSameDocument(destinationReader.displayedSessionID, sessionID) else { return false }
        return destinationReader.go(to: position, recordHistory: sameDocument)
    }

    @discardableResult
    private func turnPageAcrossBoundary(direction: Int, in pane: ReaderPane) -> Bool {
        documentStore.setFocusedPane(pane, in: windowID)
        return goToContinuousReadingBoundary(direction: direction, usesBookPageTurn: activeReaderViewController().usesBookLayout)
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
                || documentStore.readerPanes(in: windowID).contains(where: { $0.sessionID == sessionID }) else { return nil }
        let targetPane = documentStore.isSplitEnabled(in: windowID) ? pane : nil
        documentStore.activate(sessionID: sessionID, in: windowID, targetPane: targetPane)
        let resolvedPane = documentStore.focusedPane(in: windowID)
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
        allReaderViewControllers.forEach { $0.setReadingFocusModeEnabled(isReadingFocusModeEnabled) }
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
        allReaderViewControllers.forEach { $0.refreshThemeAppearance() }
        floatingOutlineViewController.refreshChromeColors()
        hosts.values.forEach { $0.refreshAppearance() }
        splitHosts.values.forEach { $0.needsDisplay = true }
    }

    func saveAnnotations() throws {
        try activeReaderViewController().saveAnnotations()
    }

    func flushPendingReadingPositions() {
        allReaderViewControllers.forEach { $0.flushPendingReadingPosition() }
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


    func showQuickOutline() {
        _ = floatingOutlineViewController.showQuickNavigation()
    }

    func canSplitActivePane(layout: ReaderSplitLayout) -> Bool {
        canSplitPane(layout: layout)
    }

    @discardableResult
    func splitActivePane(documentAt url: URL, layout: ReaderSplitLayout) throws -> Bool {
        let pane = documentStore.focusedPane(in: windowID)
        guard canSplitPane(pane, layout: layout) else {
            NSSound.beep()
            return false
        }
        readers[pane]?.flushPendingReadingPosition()
        guard try documentStore.splitPane(from: pane, layout: layout, documentAt: url, in: windowID) != nil else { return false }
        focusActiveReader()
        return true
    }

    @objc private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID), !notification.isOnlySidebarChromeChange,
              !notification.isOnlyReadingPositionChange else { return }
        let change = notification.documentStoreChange
        guard !change.intersection([.content, .tabs, .search, .appearance]).isEmpty else { return }
        syncFromStore(forceSearchRefresh: change.containsOnly(.search))
    }

    private func syncFromStore(forceSearchRefresh: Bool = true) {
        guard !isSynchronizingFromStore else { return }
        isSynchronizingFromStore = true
        defer { isSynchronizingFromStore = false }
        let layout = documentStore.readerLayout(in: windowID) ?? .pane(.primary)
        let groupID = documentStore.windowWorkspace(for: windowID)?.activeWorkspace.activeGroup?.id
        let paneIDs = layout.paneIDs
        let zoomedPane = documentStore.zoomedPane(in: windowID)
        let oldIDs = Set(orderedPaneIDs)
        let addedIDs = Set(paneIDs).subtracting(oldIDs)
        let layoutChanged = appliedLayout != layout || appliedZoomedPane != zoomedPane
        let paneCollectionChanged = orderedPaneIDs != paneIDs
        var anchors: [ReaderPane: ReadingPosition] = [:]
        var resizedIDs: Set<ReaderPane> = []
        if layoutChanged {
            let desiredFrames = ReaderPaneGeometry.frames(for: layout, in: contentContainer.bounds)
            for pane in paneIDs {
                guard let reader = readers[pane], let host = hosts[pane] else { continue }
                let desiredSize = pane == zoomedPane ? contentContainer.bounds.size : desiredFrames[pane]?.size ?? .zero
                if abs(host.bounds.width - desiredSize.width) > 0.5 || abs(host.bounds.height - desiredSize.height) > 0.5 {
                    resizedIDs.insert(pane)
                    anchors[pane] = reader.currentPosition
                    reader.prepareForChromeSizeChange()
                }
            }
        }
        for pane in oldIDs.subtracting(paneIDs) {
            overviewPaneIDs.remove(pane)
            guard let reader = readers.removeValue(forKey: pane) else { continue }
            reader.flushPendingReadingPosition()
            reader.setLocalEventMonitoringEnabled(false)
            reader.targetSessionID = nil
            hosts.removeValue(forKey: pane)?.removeFromSuperview()
            reader.removeFromParent()
        }
        for pane in paneIDs where readers[pane] == nil { createReader(for: pane) }
        orderedPaneIDs = paneIDs
        var changedSessionIDs: Set<ReaderPane> = []
        var filledEmptyPaneIDs: Set<ReaderPane> = []
        var pendingSessionIDs: [ReaderPane: UUID] = [:]
        for pane in paneIDs {
            let sessionID = documentStore.displayedSessionID(for: pane, in: windowID)
            if readers[pane]?.targetSessionID != sessionID {
                if appliedGroupID == groupID, paneIDs.count > 1, oldIDs.contains(pane), readers[pane]?.targetSessionID == nil {
                    filledEmptyPaneIDs.insert(pane)
                }
                pendingSessionIDs[pane] = sessionID
                changedSessionIDs.insert(pane)
                anchors[pane] = sessionID.flatMap { documentStore.session(for: $0)?.lastReadPosition }
            }
        }
        applyReadingFocusSettings()
        if layoutChanged || paneCollectionChanged {
            // Detach old documents before resizing their hosts. Ordinary tab
            // switches retain the previous binding so the reader can announce
            // the new file name.
            for pane in changedSessionIDs where readers[pane]?.targetSessionID != nil {
                readers[pane]?.targetSessionID = nil
            }
        }
        let isNewSplit = appliedGroupID == groupID && appliedLayout != nil && !addedIDs.isEmpty && oldIDs.isSubset(of: Set(paneIDs))
        if layoutChanged || paneCollectionChanged {
            NSLayoutConstraint.deactivate(zoomConstraints)
            zoomConstraints = []
            NSLayoutConstraint.deactivate(rootConstraints)
            rootConstraints = []
            zoomContainer.subviews.forEach { $0.removeFromSuperview() }
            let root = render(layout)
            if renderedRoot !== root {
                if renderedRoot?.superview === contentContainer { renderedRoot?.removeFromSuperview() }
                contentContainer.addSubview(root)
                renderedRoot = root
            }
            rootConstraints = edgeConstraints(for: root, in: contentContainer)
            NSLayoutConstraint.activate(rootConstraints)
            root.frame = contentContainer.bounds
            root.layoutSubtreeIfNeeded()
            let liveSplitIDs = splitIDs(in: layout)
            for id in Set(splitHosts.keys).subtracting(liveSplitIDs) {
                splitHosts.removeValue(forKey: id)?.removeFromSuperview()
            }
            contentContainer.isHidden = zoomedPane != nil
            zoomContainer.isHidden = zoomedPane == nil
            if let pane = zoomedPane, let host = hosts[pane] {
                host.removeFromSuperview()
                zoomContainer.addSubview(host)
                host.frame = zoomContainer.bounds
                zoomConstraints = edgeConstraints(for: host, in: zoomContainer)
                NSLayoutConstraint.activate(zoomConstraints)
            }
            appliedLayout = layout
            appliedZoomedPane = zoomedPane
            view.layoutSubtreeIfNeeded()
        }
        // PDFKit restores its viewport while binding a document. New readers
        // must already occupy their final pane bounds before that restoration.
        for pane in changedSessionIDs {
            readers[pane]?.targetSessionID = pendingSessionIDs[pane]
        }
        if layoutChanged || paneCollectionChanged {
            for pane in resizedIDs.union(addedIDs) {
                guard let reader = readers[pane] else { continue }
                reader.reflowForContainerSizeChange()
                if isNewSplit { reader.fitToWidth() }
                if let anchor = anchors[pane] ?? reader.targetSessionID.flatMap({ documentStore.session(for: $0)?.lastReadPosition }) {
                    _ = reader.go(to: anchor, recordHistory: false)
                }
            }
        }
        for pane in filledEmptyPaneIDs {
            guard let reader = readers[pane] else { continue }
            reader.reflowForContainerSizeChange()
            reader.fitToWidth()
            if let anchor = anchors[pane] { _ = reader.go(to: anchor, recordHistory: false) }
        }
        appliedGroupID = groupID
        let candidates = documentStore.splitCandidateSessions(in: windowID)
        let focusedPane = documentStore.focusedPane(in: windowID)
        for pane in paneIDs {
            readers[pane]?.setLocalEventMonitoringEnabled(zoomedPane == nil || zoomedPane == pane)
            hosts[pane]?.isFocused = paneIDs.count > 1 && focusedPane == pane
            hosts[pane]?.setCandidates(candidates, isVisible: paneIDs.count > 1 && readers[pane]?.targetSessionID == nil)
        }
        documentStore.rebuildSearchIfNeeded(in: windowID)
        let searchSource = documentStore.searchSnapshot(in: windowID).source
        if forceSearchRefresh || appliedSearchSource != searchSource || !changedSessionIDs.isEmpty {
            appliedSearchSource = searchSource
            for reader in allReaderViewControllers { syncSearchHighlights(for: reader, sessionID: reader.targetSessionID) }
        }
        if paneCollectionChanged { readersDidChange?() }
        if appliedFocusedPane != focusedPane || layoutChanged || !changedSessionIDs.isEmpty {
            appliedFocusedPane = focusedPane
            recentFocus.removeAll { $0 == focusedPane || !paneIDs.contains($0) }
            recentFocus.insert(focusedPane, at: 0)
            floatingOutlineViewController.bind(to: activeReaderViewController().pdfView)
            onFocusedReaderDidChange?(activeReaderViewController().pdfView)
            activeReaderViewController().publishViewportPosition(force: true)
        }
        updateFloatingOutlineSuppression()
    }

    private func createReader(for pane: ReaderPane) {
        let reader = ReaderViewController(documentStore: documentStore, windowID: windowID)
        let host = ReaderPaneHostView()
        readers[pane] = reader
        hosts[pane] = host
        addChild(reader)
        reader.onFocusRequested = { [weak self] in
            guard let self else { return }
            self.documentStore.setFocusedPane(pane, in: self.windowID)
        }
        reader.onPageBoundaryRequested = { [weak self] direction in
            self?.turnPageAcrossBoundary(direction: direction, in: pane) ?? false
        }
        reader.onHistorySessionNavigationRequested = { [weak self] id in self?.activateHistorySession(id, in: pane) }
        reader.onOverviewPresentationDidChange = { [weak self] active in
            guard let self else { return }
            if active { self.overviewPaneIDs.insert(pane) }
            else { self.overviewPaneIDs.remove(pane) }
            self.updateFloatingOutlineSuppression()
        }
        reader.onSplitRequested = { [weak self] sessionID, position, layout in
            self?.splitPane(from: pane, layout: layout, sessionID: sessionID, readingPosition: position) ?? false
        }
        host.onSessionChosen = { [weak self] id in
            guard let self else { return }
            self.documentStore.activate(sessionID: id, in: self.windowID, targetPane: pane)
        }
        embed(reader, in: host)
        host.installCandidateView()
        reader.setReadingFocusModeEnabled(isReadingFocusModeEnabled)
        reader.setReadingFocusSettings(readingFocusSettings)
        reader.setPresentationEnabled(isPresentationEnabled)
    }

    private func render(_ node: ReaderLayoutNode) -> NSView {
        switch node {
        case let .pane(pane):
            return hosts[pane]!
        case let .split(id, layout, ratio, first, second):
            let host: ReaderSplitHostView
            if let existing = splitHosts[id] { host = existing }
            else {
                host = ReaderSplitHostView(id: id, layout: layout, ratio: ratio)
                splitHosts[id] = host
                host.onWillResize = { [weak self] panes in self?.prepareForDividerResize(panes) }
                host.onDidResize = { [weak self] panes in self?.completeDividerResize(panes) }
                host.onRatioChanged = { [weak self] id, ratio in
                    guard let self else { return }
                    self.documentStore.updateSplitRatio(ratio, splitID: id, in: self.windowID)
                }
            }
            host.isVertical = layout == .sideBySide
            host.ratio = ratio
            host.paneIDs = node.paneIDs
            host.firstMinimumSize = ReaderPaneGeometry.minimumSize(for: first)
            host.secondMinimumSize = ReaderPaneGeometry.minimumSize(for: second)
            host.install(first: render(first), second: render(second))
            host.resizeSubviews(withOldSize: host.bounds.size)
            return host
        }
    }

    private func splitIDs(in node: ReaderLayoutNode) -> Set<UUID> {
        switch node {
        case .pane: return []
        case let .split(id, _, _, first, second): return Set([id]).union(splitIDs(in: first)).union(splitIDs(in: second))
        }
    }

    private func prepareForDividerResize(_ panes: [ReaderPane]) {
        dividerReadingPositions = [:]
        for pane in panes {
            dividerReadingPositions[pane] = readers[pane]?.currentPosition
            readers[pane]?.prepareForChromeSizeChange()
        }
    }

    private func completeDividerResize(_ panes: [ReaderPane]) {
        for pane in panes {
            readers[pane]?.reflowForContainerSizeChange()
            if let anchor = dividerReadingPositions[pane] { _ = readers[pane]?.go(to: anchor, recordHistory: false) }
        }
        dividerReadingPositions = [:]
    }

    private func isSameDocument(_ displayedID: UUID?, _ requestedID: UUID) -> Bool {
        guard let displayedID else { return false }
        if displayedID == requestedID { return true }
        let current = documentStore.publicSessionID(forDisplayedSessionID: displayedID, in: windowID)
        let requested = documentStore.publicSessionID(forDisplayedSessionID: requestedID, in: windowID)
        return current != nil && current == requested
    }

    private func updateFloatingOutlineSuppression() {
        floatingOutlineViewController.setSuppressed(isPresentationEnabled || !overviewPaneIDs.isEmpty)
    }

    private func applyReadingFocusSettings() {
        let settings = readingFocusSettings
        guard appliedReadingFocusSettings != settings else { return }
        appliedReadingFocusSettings = settings
        allReaderViewControllers.forEach { $0.setReadingFocusSettings(settings) }
    }

    private func syncSearchHighlights(for reader: ReaderViewController, sessionID: UUID?) {
        guard let sessionID, !documentStore.searchSnapshot(in: windowID).query.isEmpty else {
            reader.clearSearchResults()
            return
        }
        reader.applySearchResults(documentStore.searchSelections(for: sessionID, in: windowID), selectedMatchIndex: nil)
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

    private func edgeConstraints(for child: NSView, in host: NSView) -> [NSLayoutConstraint] {
        child.translatesAutoresizingMaskIntoConstraints = false
        return [
            child.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            child.topAnchor.constraint(equalTo: host.topAnchor),
            child.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ]
    }

    private func applyFloatingOutlineSize() {
        guard isViewLoaded, floatingOutlineWidthConstraint != nil, floatingOutlineHeightConstraint != nil else { return }
        let maximumWidth = max(view.bounds.width - 28, 28)
        let maximumHeight = max(view.bounds.height - 48, 0)
        floatingOutlineViewController.setMaximumAvailableHeight(maximumHeight)
        let size = floatingOutlineViewController.preferredSize
        let width = min(size.width, maximumWidth)
        let height = min(size.height, maximumHeight)
        if abs(floatingOutlineWidthConstraint.constant - width) > 0.5 { floatingOutlineWidthConstraint.constant = width }
        if abs(floatingOutlineHeightConstraint.constant - height) > 0.5 { floatingOutlineHeightConstraint.constant = height }
    }
}
