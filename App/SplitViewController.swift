import AppKit

final class SplitViewController: NSSplitViewController {
    private static let legacyAutosaveNames = [
        "MainSplitView",
        "SereinSplit.v2",
        "SereinSplit.v3",
    ]
    let documentStore: DocumentStore
    let windowID: UUID
    let verticalTabsViewController: VerticalTabsViewController
    let readerWorkspaceViewController: ReaderWorkspaceViewController
    let rightSidebarViewController: RightSidebarViewController
    let titlebarTabsController: TitlebarTabsController
    private var tabsSidebarItem: NSSplitViewItem!
    private var outlineSidebarItem: NSSplitViewItem!
    private var centerItem: NSSplitViewItem!
    private var appliedSwapped: Bool?
    private var hasAppliedSidebarWidths = false
    private var isApplyingSidebarWidths = false
    private var pendingSidebarWidthApply = false

    var readerViewController: ReaderViewController {
        readerWorkspaceViewController.activeReaderViewController()
    }

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        verticalTabsViewController = VerticalTabsViewController(documentStore: documentStore, windowID: windowID)
        readerWorkspaceViewController = ReaderWorkspaceViewController(
            documentStore: documentStore,
            windowID: windowID
        )
        rightSidebarViewController = RightSidebarViewController(documentStore: documentStore, windowID: windowID)
        titlebarTabsController = TitlebarTabsController(documentStore: documentStore, windowID: windowID)
        super.init(nibName: nil, bundle: nil)
        wireInteractions()
        rightSidebarViewController.configure(pdfView: readerWorkspaceViewController.activeReaderViewController().pdfView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init(documentStore: DocumentStore) {
        self.init(documentStore: documentStore, windowID: documentStore.defaultWindowID)
    }

    static let splitBackgroundColor: NSColor = NightModeStyle.splitBackgroundColor

    static let dividerBackgroundColor: NSColor = NightModeStyle.chromeDividerColor

    static let selectedChromeBackgroundColor: NSColor = NightModeStyle.selectedChromeBackgroundColor

    static let chromeStrokeColor: NSColor = NightModeStyle.chromeStrokeColor

    override func viewDidLoad() {
        super.viewDidLoad()

        purgeLegacyAutosaveKeys()
        view.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = nil
        splitView.wantsLayer = true
        applyChromeColors()

        let sidebarHoldingPriority = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 10
        )

        tabsSidebarItem = NSSplitViewItem(viewController: verticalTabsViewController)
        tabsSidebarItem.canCollapse = true
        tabsSidebarItem.holdingPriority = sidebarHoldingPriority

        centerItem = NSSplitViewItem(viewController: readerWorkspaceViewController)
        centerItem.minimumThickness = 320
        centerItem.holdingPriority = .defaultLow

        outlineSidebarItem = NSSplitViewItem(viewController: rightSidebarViewController)
        outlineSidebarItem.canCollapse = true
        outlineSidebarItem.holdingPriority = sidebarHoldingPriority

        rebuildSplitItems()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        applyStoreState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyStoreState()
        applySidebarWidthsForWindow()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scheduleSidebarWidthApply()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        syncSidebarVisibilityFromSplitView()
        guard isApplyingSidebarWidths == false,
              hasAppliedSidebarWidths else { return }

        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        let leftItem = swapped ? outlineSidebarItem : tabsSidebarItem
        let rightItem = swapped ? tabsSidebarItem : outlineSidebarItem
        let storedWidths = documentStore.sidebarWidths(in: windowID)
        let leftWidth = leftItem?.isCollapsed == true
            ? storedWidths.left
            : splitView.arrangedSubviews[safe: 0]?.frame.width ?? storedWidths.left
        let rightWidth = rightItem?.isCollapsed == true
            ? storedWidths.right
            : splitView.arrangedSubviews[safe: 2]?.frame.width ?? storedWidths.right
        guard sidebarWidthChangedMeaningfully(current: leftWidth, stored: storedWidths.left) ||
                sidebarWidthChangedMeaningfully(current: rightWidth, stored: storedWidths.right) else { return }

        documentStore.updateSidebarWidths(
            left: leftWidth,
            right: rightWidth,
            in: windowID
        )
    }

    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let padding: CGFloat = 10
        if splitView.isVertical {
            return NSRect(
                x: drawnRect.minX - padding,
                y: 0,
                width: drawnRect.width + padding * 2,
                height: splitView.bounds.height
            )
        }
        return NSRect(
            x: 0,
            y: drawnRect.minY - padding,
            width: splitView.bounds.width,
            height: drawnRect.height + padding * 2
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildSplitItemsIfSwapChanged()
        applyStoreState()
        applySidebarWidthsForWindow()
    }

    private func rebuildSplitItemsIfSwapChanged() {
        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        guard appliedSwapped != swapped else { return }
        rebuildSplitItems()
    }

    private func rebuildSplitItems() {
        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        let layout = documentStore.appConfiguration.layout

        for item in splitViewItems {
            removeSplitViewItem(item)
        }

        let leftItem: NSSplitViewItem = swapped ? outlineSidebarItem : tabsSidebarItem
        let rightItem: NSSplitViewItem = swapped ? tabsSidebarItem : outlineSidebarItem

        leftItem.minimumThickness = layout.leftSidebarMinWidth
        leftItem.maximumThickness = layout.leftSidebarMaxWidth
        rightItem.minimumThickness = layout.rightSidebarMinWidth
        rightItem.maximumThickness = layout.rightSidebarMaxWidth

        addSplitViewItem(leftItem)
        addSplitViewItem(centerItem)
        addSplitViewItem(rightItem)

        appliedSwapped = swapped
        hasAppliedSidebarWidths = false
    }

    private func applyStoreState() {
        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        let physicalLeft: NSSplitViewItem = swapped ? outlineSidebarItem : tabsSidebarItem
        let physicalRight: NSSplitViewItem = swapped ? tabsSidebarItem : outlineSidebarItem

        let leftShouldCollapse = !documentStore.isLeftSidebarVisible(in: windowID)
        if physicalLeft.isCollapsed != leftShouldCollapse {
            physicalLeft.isCollapsed = leftShouldCollapse
        }
        let rightShouldCollapse = !documentStore.isRightSidebarVisible(in: windowID)
        if physicalRight.isCollapsed != rightShouldCollapse {
            physicalRight.isCollapsed = rightShouldCollapse
        }

        rightSidebarViewController.applyStateFromStore()
    }

    private func scheduleSidebarWidthApply() {
        guard pendingSidebarWidthApply == false else { return }
        pendingSidebarWidthApply = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingSidebarWidthApply = false
            self.applySidebarWidthsForWindow()
        }
    }

    private func applySidebarWidthsForWindow() {
        guard splitView.bounds.width > 0,
              splitView.arrangedSubviews.count >= 3 else { return }

        let layout = documentStore.appConfiguration.layout
        let leftIsVisible = documentStore.isLeftSidebarVisible(in: windowID)
        let rightIsVisible = documentStore.isRightSidebarVisible(in: windowID)
        let preferredWidths = documentStore.sidebarWidths(in: windowID)

        let targetLeft = leftIsVisible
            ? min(max(preferredWidths.left, layout.leftSidebarMinWidth), layout.leftSidebarMaxWidth)
            : nil
        let targetRight = rightIsVisible
            ? min(max(preferredWidths.right, layout.rightSidebarMinWidth), layout.rightSidebarMaxWidth)
            : nil
        let total = splitView.bounds.width
        let requiredWidth = (targetLeft ?? 0) + (targetRight ?? 0) + centerItem.minimumThickness
        guard total >= requiredWidth else {
            hasAppliedSidebarWidths = false
            return
        }

        let currentWidths = currentSidebarWidths()
        let alreadyApplied =
            hasAppliedSidebarWidths &&
            widthsMatch(currentWidths.left, targetWidth: targetLeft) &&
            widthsMatch(currentWidths.right, targetWidth: targetRight)
        if alreadyApplied {
            return
        }

        isApplyingSidebarWidths = true
        defer { isApplyingSidebarWidths = false }

        if let targetLeft {
            splitView.setPosition(targetLeft, ofDividerAt: 0)
        }
        if let targetRight {
            splitView.setPosition(total - targetRight, ofDividerAt: 1)
        }

        hasAppliedSidebarWidths = true
    }

    private func currentSidebarWidths() -> (left: CGFloat?, right: CGFloat?) {
        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        let leftItem = swapped ? outlineSidebarItem : tabsSidebarItem
        let rightItem = swapped ? tabsSidebarItem : outlineSidebarItem
        let leftWidth = leftItem?.isCollapsed == true ? nil : splitView.arrangedSubviews[safe: 0]?.frame.width
        let rightWidth = rightItem?.isCollapsed == true ? nil : splitView.arrangedSubviews[safe: 2]?.frame.width
        return (leftWidth, rightWidth)
    }

    private func widthsMatch(_ currentWidth: CGFloat?, targetWidth: CGFloat?) -> Bool {
        switch (currentWidth, targetWidth) {
        case (nil, nil):
            true
        case let (currentWidth?, targetWidth?):
            abs(currentWidth - targetWidth) <= 1
        default:
            false
        }
    }

    private func sidebarWidthChangedMeaningfully(current: CGFloat?, stored: CGFloat?) -> Bool {
        switch (current, stored) {
        case (nil, nil):
            false
        case let (current?, stored?):
            abs(current - stored) > 4
        default:
            true
        }
    }

    private func syncSidebarVisibilityFromSplitView() {
        let swapped = documentStore.appConfiguration.layout.sidebarsSwapped
        let leftItem = swapped ? outlineSidebarItem : tabsSidebarItem
        let rightItem = swapped ? tabsSidebarItem : outlineSidebarItem
        let leftIsVisible = leftItem?.isCollapsed != true
        let rightIsVisible = rightItem?.isCollapsed != true

        if documentStore.isLeftSidebarVisible(in: windowID) != leftIsVisible {
            documentStore.setLeftSidebarVisible(leftIsVisible, in: windowID)
        }
        if documentStore.isRightSidebarVisible(in: windowID) != rightIsVisible {
            documentStore.setRightSidebarVisible(rightIsVisible, in: windowID)
        }
    }

    private func purgeLegacyAutosaveKeys() {
        Self.legacyAutosaveNames.forEach { name in
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name)")
        }
        UserDefaults.standard.removeObject(forKey: "Serein.Layout.lastConfigLeftWidth")
        UserDefaults.standard.removeObject(forKey: "Serein.Layout.lastConfigRightWidth")
    }

    func refreshChromeColors() {
        applyChromeColors()
        verticalTabsViewController.refreshChromeColors()
        readerWorkspaceViewController.refreshThemeAppearance()
        rightSidebarViewController.refreshChromeColors()
        titlebarTabsController.refreshChromeColors()
    }

    func fitToWidth() {
        readerWorkspaceViewController.fitToWidth()
    }

    func fitToHeight() {
        readerWorkspaceViewController.fitToHeight()
    }

    func fitToPage() {
        readerWorkspaceViewController.fitToPage()
    }

    func zoomIn() {
        readerWorkspaceViewController.zoomIn()
    }

    func zoomOut() {
        readerWorkspaceViewController.zoomOut()
    }

    func goToNextPage() {
        readerWorkspaceViewController.goToNextPage()
    }

    func goToPreviousPage() {
        readerWorkspaceViewController.goToPreviousPage()
    }

    func scrollHalfPageDown() {
        readerWorkspaceViewController.scrollHalfPageDown()
    }

    func scrollHalfPageUp() {
        readerWorkspaceViewController.scrollHalfPageUp()
    }

    func goToFirstPage() {
        readerWorkspaceViewController.goToFirstPage()
    }

    func goToLastPage() {
        readerWorkspaceViewController.goToLastPage()
    }

    func navigateBack() {
        readerWorkspaceViewController.navigateBack()
    }

    func navigateForward() {
        readerWorkspaceViewController.navigateForward()
    }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        readerWorkspaceViewController.goToPage(pageIndex)
    }

    @discardableResult
    func triggerHighlightShortcut() -> Bool {
        readerWorkspaceViewController.triggerHighlightShortcut()
    }

    func exitHighlightMode() {
        readerWorkspaceViewController.exitHighlightMode()
    }

    func setHighlightColor(_ color: HighlightColor) {
        readerWorkspaceViewController.setHighlightColor(color)
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        readerWorkspaceViewController.removeHighlightUnderCursor()
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        readerWorkspaceViewController.undoLastHighlight()
    }

    @discardableResult
    func redoLastHighlight() -> Bool {
        readerWorkspaceViewController.redoLastHighlight()
    }

    func toggleNightMode() {
        readerWorkspaceViewController.toggleNightMode()
    }

    func saveAnnotations() throws {
        try readerWorkspaceViewController.saveAnnotations()
    }

    func showFindBar(scope: SearchScope? = nil) {
        readerWorkspaceViewController.showFindBar(scope: scope)
        syncFindStatus()
    }

    func hideFindBar() {
        readerWorkspaceViewController.hideFindBar()
    }

    @discardableResult
    func findNextMatch() -> Bool {
        guard documentStore.totalSearchMatches(in: windowID) > 0 else { return false }
        _ = rightSidebarViewController.selectNextSearchMatch(activate: true)
        syncFindStatus()
        return true
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        guard documentStore.totalSearchMatches(in: windowID) > 0 else { return false }
        _ = rightSidebarViewController.selectPreviousSearchMatch(activate: true)
        syncFindStatus()
        return true
    }

    private func applyChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = Self.splitBackgroundColor.cgColor
            splitView.layer?.backgroundColor = Self.dividerBackgroundColor.cgColor
        }
    }

    private func wireInteractions() {
        let alternateActivation: (UUID) -> Void = { [weak self] sessionID in
            guard let self else { return }
            let focusedPane = self.documentStore.focusedPane(in: self.windowID)
            let targetPane = self.documentStore.isSplitEnabled(in: self.windowID)
                ? focusedPane
                : focusedPane.other
            self.documentStore.activate(sessionID: sessionID, in: self.windowID, targetPane: targetPane)
        }
        verticalTabsViewController.onAlternateSessionActivationRequested = alternateActivation
        titlebarTabsController.onAlternateSessionActivationRequested = alternateActivation

        readerWorkspaceViewController.onFocusedReaderDidChange = { [weak self] pdfView in
            self?.rightSidebarViewController.configure(pdfView: pdfView)
            self?.syncFindStatus()
        }

        for reader in [
            readerWorkspaceViewController.primaryReaderViewController,
            readerWorkspaceViewController.secondaryReaderViewController,
        ] {
            reader.onFindActionRequested = { [weak self] action in
                self?.handleFindAction(action)
            }
        }

        rightSidebarViewController.onActivateSearchMatch = { [weak self] match in
            self?.activateSearchMatch(match)
        }
        rightSidebarViewController.onActivateAnnotation = { [weak self] group in
            self?.activateAnnotation(group)
        }
        rightSidebarViewController.onSearchSelectionDidChange = { [weak self] _, _ in
            self?.syncFindStatus()
        }
    }

    private func handleFindAction(_ action: FindNavigationAction) {
        switch action {
        case .selectNext:
            _ = rightSidebarViewController.selectNextSearchMatch(activate: false)
        case .selectPrevious:
            _ = rightSidebarViewController.selectPreviousSearchMatch(activate: false)
        case .activateSelected:
            _ = rightSidebarViewController.activateSelectedSearchMatch()
        case .activateNext:
            _ = rightSidebarViewController.selectNextSearchMatch(activate: true)
        case .activatePrevious:
            _ = rightSidebarViewController.selectPreviousSearchMatch(activate: true)
        }
        syncFindStatus()
    }

    private func activateSearchMatch(_ match: SearchSidebarMatch) {
        let targetPane = documentStore.isSplitEnabled(in: windowID)
            ? documentStore.focusedPane(in: windowID)
            : nil
        documentStore.activate(sessionID: match.sessionID, in: windowID, targetPane: targetPane)
        readerWorkspaceViewController.activeReaderViewController().go(to: match.selection)
        syncFindStatus()
    }

    private func activateAnnotation(_ group: DocumentHighlightGroup) {
        readerWorkspaceViewController.focus(on: group)
    }

    private func syncFindStatus() {
        let summary = rightSidebarViewController.searchResultsViewController.selectionSummary()
        readerWorkspaceViewController.activeReaderViewController().updateFindStatus(
            matchIndex: summary.selectedIndex,
            totalMatches: summary.totalMatches
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
