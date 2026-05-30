import AppKit

extension NSToolbarItem.Identifier {
    static let titlebarTabs = NSToolbarItem.Identifier("local.yfff.Serein.titlebarTabs")
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    static let defaultContentSize = NSSize(width: 1480, height: 960)
    static let minimumWindowSize = NSSize(width: 560, height: 360)

    let documentStore: DocumentStore
    let windowID: UUID
    private let splitViewController: SplitViewController
    private let toolbar = NSToolbar(identifier: "MainToolbar")
    private let titlebarTabsItem = NSToolbarItem(itemIdentifier: .titlebarTabs)
    private var allowsTerminationWithoutPrompt = false
    private var demoModeSnapshot: DemoModeSnapshot?
    private var immersiveModeSnapshot: ImmersiveModeSnapshot?
    var shouldCloseHandler: ((MainWindowController) -> Bool)?
    var didCloseHandler: ((MainWindowController) -> Void)?

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        splitViewController = SplitViewController(documentStore: documentStore, windowID: windowID)
        let window = ReaderShortcutWindow(contentViewController: splitViewController)

        window.title = "Serein"
        window.setContentSize(Self.defaultContentSize)
        window.minSize = Self.minimumWindowSize
        window.contentMinSize = Self.minimumWindowSize
        window.minFullScreenContentSize = Self.minimumWindowSize
        window.center()
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenAllowsTiling)
        window.tabbingMode = .disallowed
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        toolbar.centeredItemIdentifier = nil
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SplitViewController.splitBackgroundColor
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        super.init(window: window)

        window.delegate = self
        toolbar.delegate = self
        shouldCascadeWindows = true
        splitViewController.verticalTabsViewController.onCloseSessionRequested = { [weak self] sessionID in
            self?.requestCloseSession(sessionID)
        }
        splitViewController.titlebarTabsController.onCloseSessionRequested = { [weak self] sessionID in
            self?.requestCloseSession(sessionID)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        refreshThemeAppearance()
        applyWindowChromeState()
        refreshWindowTitle()
    }

    convenience init(documentStore: DocumentStore) {
        self.init(documentStore: documentStore, windowID: documentStore.defaultWindowID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshThemeAppearance()
        applyWindowChromeState()
        refreshWindowTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        refreshThemeAppearance()
        applyWindowChromeState()
        refreshWindowTitle()
    }

    private func configureTitlebarTabsItemIfNeeded() {
        let tabsView = splitViewController.titlebarTabsController.view
        titlebarTabsItem.label = ""
        titlebarTabsItem.paletteLabel = ""
        titlebarTabsItem.view = tabsView
        titlebarTabsItem.visibilityPriority = .high
    }

    private func applyWindowChromeState() {
        let tabsOnRight = documentStore.appConfiguration.layout.sidebarsSwapped
        let tabsPaneVisible = tabsOnRight
            ? documentStore.isRightSidebarVisible(in: windowID)
            : documentStore.isLeftSidebarVisible(in: windowID)
        let shouldShowTitlebarTabs =
            documentStore.tabPresentationMode(in: windowID) == .horizontalTitlebar &&
            !tabsPaneVisible &&
            !isImmersiveModeEnabled

        splitViewController.titlebarTabsController.setTabsStripVisible(shouldShowTitlebarTabs)
        synchronizeWindowToolbar(isVisible: shouldShowTitlebarTabs)
        synchronizeTitlebarTabsItem(isVisible: shouldShowTitlebarTabs)
    }

    private func synchronizeWindowToolbar(isVisible: Bool) {
        guard let window else { return }

        if isVisible {
            if window.toolbar !== toolbar {
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unifiedCompact
            return
        }

        window.toolbar = nil
    }

    private func synchronizeTitlebarTabsItem(isVisible: Bool) {
        let itemIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == .titlebarTabs })

        if isVisible {
            configureTitlebarTabsItemIfNeeded()
            if itemIndex == nil {
                toolbar.insertItem(withItemIdentifier: .titlebarTabs, at: 0)
            }
            toolbar.centeredItemIdentifier = .titlebarTabs
            return
        }

        toolbar.centeredItemIdentifier = nil
        if let itemIndex {
            toolbar.removeItem(at: itemIndex)
        }
    }

    private func refreshWindowTitle() {
        guard let window else { return }
        guard let session = documentStore.activeSession(in: windowID),
              session.isBlank == false else {
            window.title = "Serein"
            window.representedURL = nil
            window.representedFilename = ""
            return
        }

        window.title = session.title
        window.representedURL = session.url
        window.representedFilename = session.url.path
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.titlebarTabs]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .titlebarTabs else { return nil }
        configureTitlebarTabsItemIfNeeded()
        return titlebarTabsItem
    }

    func fitReaderToWidth() {
        splitViewController.fitToWidth()
    }

    func fitReaderToHeight() {
        splitViewController.fitToHeight()
    }

    func fitReaderToPage() {
        splitViewController.fitToPage()
    }

    func zoomIn() {
        splitViewController.zoomIn()
    }

    func zoomOut() {
        splitViewController.zoomOut()
    }

    func goToNextPage() {
        splitViewController.goToNextPage()
    }

    func goToPreviousPage() {
        splitViewController.goToPreviousPage()
    }

    func scrollHalfPageDown() {
        splitViewController.scrollHalfPageDown()
    }

    func scrollHalfPageUp() {
        splitViewController.scrollHalfPageUp()
    }

    func goToFirstPage() {
        splitViewController.goToFirstPage()
    }

    func goToLastPage() {
        splitViewController.goToLastPage()
    }

    func navigateBack() {
        splitViewController.navigateBack()
    }

    func navigateForward() {
        splitViewController.navigateForward()
    }

    var canGoBack: Bool { splitViewController.readerViewController.canGoBack }
    var canGoForward: Bool { splitViewController.readerViewController.canGoForward }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        splitViewController.goToPage(pageIndex)
    }

    var currentPageCount: Int { splitViewController.readerViewController.currentPageCount }

    var isAllPagesOverviewActive: Bool {
        splitViewController.readerViewController.isAllPagesOverviewActive
    }

    func setAllPagesOverviewActive(_ active: Bool) {
        splitViewController.readerViewController.setAllPagesOverviewActive(active)
    }

    @discardableResult
    func toggleAllPagesOverview() -> Bool {
        splitViewController.readerViewController.toggleAllPagesOverview()
    }

    func toggleRightSidebarMode() {
        splitViewController.rightSidebarViewController.toggleMode()
    }

    func toggleReaderSplit() {
        splitViewController.readerWorkspaceViewController.toggleSplit()
    }

    var isReaderSplitEnabled: Bool {
        documentStore.isSplitEnabled(in: windowID)
    }

    var isDemoModeEnabled: Bool {
        demoModeSnapshot != nil
    }

    var isImmersiveModeEnabled: Bool {
        documentStore.isLeftSidebarVisible(in: windowID) == false &&
            documentStore.isRightSidebarVisible(in: windowID) == false
    }

    func toggleDemoMode() {
        guard documentStore.activeSession(in: windowID) != nil else { return }

        if let snapshot = demoModeSnapshot {
            demoModeSnapshot = nil
            restoreDemoMode(from: snapshot)
            return
        }

        enterDemoMode()
    }

    func toggleImmersiveMode() {
        guard documentStore.activeSession(in: windowID) != nil else { return }

        immersiveModeSnapshot = nil
        let shouldOpenBothSidebars =
            documentStore.isLeftSidebarVisible(in: windowID) == false &&
            documentStore.isRightSidebarVisible(in: windowID) == false
        documentStore.setLeftSidebarVisible(shouldOpenBothSidebars, in: windowID)
        documentStore.setRightSidebarVisible(shouldOpenBothSidebars, in: windowID)
        applyWindowChromeState()
    }

    private func enterDemoMode() {
        demoModeSnapshot = DemoModeSnapshot(
            wasFullScreen: window?.styleMask.contains(.fullScreen) == true,
            wasImmersiveModeEnabled: isImmersiveModeEnabled,
            readerState: currentDemoReaderState()
        )
        if isImmersiveModeEnabled == false {
            enterImmersiveMode()
        }
        applyDemoReaderState()
        if window?.isVisible == true,
           window?.styleMask.contains(.fullScreen) != true {
            window?.toggleFullScreen(nil)
        }
        scheduleDemoFitToPage()
    }

    private func restoreDemoMode(from snapshot: DemoModeSnapshot) {
        restoreDemoReaderState(snapshot.readerState)
        if snapshot.wasImmersiveModeEnabled == false, let immersiveModeSnapshot {
            self.immersiveModeSnapshot = nil
            restoreImmersiveMode(from: immersiveModeSnapshot)
        }
        if snapshot.wasFullScreen == false,
           window?.isVisible == true,
           window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        }
    }

    private func enterImmersiveMode() {
        immersiveModeSnapshot = ImmersiveModeSnapshot(
            isLeftSidebarVisible: documentStore.isLeftSidebarVisible(in: windowID),
            isRightSidebarVisible: documentStore.isRightSidebarVisible(in: windowID)
        )
        documentStore.setLeftSidebarVisible(false, in: windowID)
        documentStore.setRightSidebarVisible(false, in: windowID)
        applyWindowChromeState()
    }

    private func restoreImmersiveMode(from snapshot: ImmersiveModeSnapshot) {
        documentStore.setLeftSidebarVisible(snapshot.isLeftSidebarVisible, in: windowID)
        documentStore.setRightSidebarVisible(snapshot.isRightSidebarVisible, in: windowID)
        applyWindowChromeState()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let snapshot = demoModeSnapshot,
              snapshot.wasFullScreen == false else { return }
        demoModeSnapshot = nil
        restoreDemoMode(from: snapshot)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard demoModeSnapshot != nil else { return }
        scheduleDemoFitToPage()
    }

    func installPlainShortcutHandler(_ handler: @escaping (NSEvent, NSWindow) -> Bool) {
        guard let window = window as? ReaderShortcutWindow else { return }
        window.plainShortcutHandler = handler
    }

    func installSidebarRecentOpenHandler(_ handler: @escaping (URL, UUID) -> Void) {
        splitViewController.verticalTabsViewController.onOpenRecentURLRequested = { [weak self] url in
            guard let self else { return }
            handler(url, self.windowID)
        }
    }

    func requestCloseActiveSession() {
        let selectedSessionIDs = documentStore.selectedSessionIDsInWindowOrder(in: windowID)
        if selectedSessionIDs.count > 1 {
            requestCloseSessions(selectedSessionIDs)
            return
        }

        if documentStore.isSplitEnabled(in: windowID) {
            let focusedPane = documentStore.focusedPane(in: windowID)
            let focusedSessionID = documentStore.displayedSessionID(for: focusedPane, in: windowID)
            let otherSessionID = documentStore.displayedSessionID(for: focusedPane.other, in: windowID)

            guard let focusedSessionID else {
                documentStore.setSplitEnabled(false, in: windowID)
                return
            }

            guard let otherSessionID, otherSessionID != focusedSessionID else {
                documentStore.setSplitEnabled(false, in: windowID)
                return
            }

            requestCloseSession(focusedSessionID, collapseSplitKeeping: focusedPane.other)
            return
        }

        guard let sessionID = documentStore.activeSessionID(in: windowID) else { return }
        requestCloseSession(sessionID)
    }

    private func requestCloseSessions(_ sessionIDs: [UUID]) {
        for sessionID in sessionIDs {
            guard requestCloseSession(sessionID) else { return }
        }
        if documentStore.isSplitEnabled(in: windowID),
           documentStore.sessionCount(in: windowID) < 2 {
            documentStore.setSplitEnabled(false, in: windowID)
        }
    }

    @discardableResult
    func requestCloseSession(_ sessionID: UUID, collapseSplitKeeping survivorPane: ReaderPane? = nil) -> Bool {
        guard let session = documentStore.session(for: sessionID) else { return true }
        guard session.isDirty else {
            closeSession(sessionID, collapseSplitKeeping: survivorPane)
            return true
        }

        switch presentUnsavedChangesAlert(
            title: "Save changes to “\(session.title)” before closing?",
            detail: "Your highlights are only in memory until you save them."
        ) {
        case .save:
            do {
                try documentStore.saveAnnotations(for: sessionID)
                closeSession(sessionID, collapseSplitKeeping: survivorPane)
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            closeSession(sessionID, collapseSplitKeeping: survivorPane)
            return true
        case .cancel:
            return false
        }
    }

    private func closeSession(_ sessionID: UUID, collapseSplitKeeping survivorPane: ReaderPane?) {
        documentStore.close(sessionID: sessionID, from: windowID)

        guard let survivorPane,
              documentStore.isSplitEnabled(in: windowID) else { return }

        documentStore.setFocusedPane(survivorPane, in: windowID)
        documentStore.setSplitEnabled(false, in: windowID)
    }

    func prepareForApplicationTermination() -> Bool {
        if allowsTerminationWithoutPrompt {
            allowsTerminationWithoutPrompt = false
            return true
        }

        let dirtySessions = documentStore.sessions.filter(\.isDirty)
        guard dirtySessions.isEmpty == false else { return true }

        let detail: String
        if dirtySessions.count == 1, let session = dirtySessions.first {
            detail = "“\(session.title)” still has unsaved highlights."
        } else {
            let titles = dirtySessions.prefix(3).map(\.title).joined(separator: "\n")
            let suffix = dirtySessions.count > 3 ? "\n…" : ""
            detail = "These documents still have unsaved highlights:\n\(titles)\(suffix)"
        }

        switch presentUnsavedChangesAlert(
            title: "Save changes before quitting Serein?",
            detail: detail
        ) {
        case .save:
            do {
                try dirtySessions.forEach { try documentStore.saveAnnotations(for: $0.id) }
                allowsTerminationWithoutPrompt = true
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            allowsTerminationWithoutPrompt = true
            return true
        case .cancel:
            return false
        }
    }

    func prepareForWindowClosure() -> Bool {
        let dirtySessions = documentStore.exclusiveDirtySessions(in: windowID)
        guard dirtySessions.isEmpty == false else { return true }

        let detail: String
        if dirtySessions.count == 1, let session = dirtySessions.first {
            detail = "“\(session.title)” 只在当前窗口打开，关闭窗口会丢失未保存高亮。"
        } else {
            let titles = dirtySessions.prefix(3).map(\.title).joined(separator: "\n")
            let suffix = dirtySessions.count > 3 ? "\n…" : ""
            detail = "这些文档只在当前窗口打开，关闭窗口会丢失未保存高亮:\n\(titles)\(suffix)"
        }

        switch presentUnsavedChangesAlert(
            title: "Save changes before closing this window?",
            detail: detail
        ) {
        case .save:
            do {
                try dirtySessions.forEach { try documentStore.saveAnnotations(for: $0.id) }
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldCloseHandler?(self) ?? true
    }

    func windowWillClose(_ notification: Notification) {
        didCloseHandler?(self)
    }

    @discardableResult
    func triggerHighlightShortcut() -> Bool {
        splitViewController.triggerHighlightShortcut()
    }

    func exitHighlightMode() {
        splitViewController.exitHighlightMode()
    }

    func setHighlightColor(_ color: HighlightColor) {
        splitViewController.setHighlightColor(color)
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        splitViewController.removeHighlightUnderCursor()
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        splitViewController.undoLastHighlight()
    }

    var hasUndoableHighlight: Bool {
        splitViewController.readerViewController.hasUndoableHighlight
    }

    var hasRedoableHighlight: Bool {
        splitViewController.readerViewController.hasRedoableHighlight
    }

    func redoLastHighlight() -> Bool {
        splitViewController.redoLastHighlight()
    }

    var currentHighlightColor: HighlightColor {
        splitViewController.readerViewController.currentHighlightColor
    }

    func refreshThemeAppearance() {
        window?.backgroundColor = SplitViewController.splitBackgroundColor
        splitViewController.refreshChromeColors()
    }

    func saveAnnotations() throws {
        try splitViewController.saveAnnotations()
    }

    @discardableResult
    func searchCurrentDocument(for query: String) -> Bool {
        splitViewController.readerViewController.search(for: query)
    }

    func showFindBar(scope: SearchScope? = nil) {
        splitViewController.showFindBar(scope: scope)
    }

    func hideFindBar() {
        splitViewController.hideFindBar()
    }

    var isFindBarVisible: Bool {
        splitViewController.readerViewController.isFindBarVisible
    }

    @discardableResult
    func findNextMatch() -> Bool {
        splitViewController.findNextMatch()
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        splitViewController.findPreviousMatch()
    }

    var isHighlightModeEnabled: Bool {
        splitViewController.readerViewController.isHighlightModeEnabled
    }

    var isNightModeEnabled: Bool {
        (window?.effectiveAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

    private func presentUnsavedChangesAlert(title: String, detail: String) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to save annotations"
        alert.runModal()
    }

    private func currentDemoReaderState() -> DemoReaderState? {
        guard let session = documentStore.activeSession(in: windowID) else { return nil }
        return DemoReaderState(
            sessionID: session.id,
            displayMode: session.displayMode,
            scaleMode: session.scaleMode,
            zoomScale: session.zoomScale
        )
    }

    private func applyDemoReaderState() {
        guard let sessionID = demoModeSnapshot?.readerState?.sessionID,
              documentStore.session(for: sessionID) != nil else { return }
        documentStore.setDisplayMode(.singlePage, for: sessionID)
        fitReaderToPage()
    }

    private func restoreDemoReaderState(_ state: DemoReaderState?) {
        guard let state,
              documentStore.session(for: state.sessionID) != nil else { return }
        documentStore.setDisplayMode(state.displayMode, for: state.sessionID)
        documentStore.setScaleMode(state.scaleMode, scaleFactor: state.zoomScale, for: state.sessionID)
    }

    private func scheduleDemoFitToPage() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.demoModeSnapshot != nil else { return }
            self.fitReaderToPage()
        }
    }

    private struct DemoModeSnapshot {
        let wasFullScreen: Bool
        let wasImmersiveModeEnabled: Bool
        let readerState: DemoReaderState?
    }

    private struct ImmersiveModeSnapshot {
        let isLeftSidebarVisible: Bool
        let isRightSidebarVisible: Bool
    }

    private struct DemoReaderState {
        let sessionID: UUID
        let displayMode: ReaderDisplayMode
        let scaleMode: ReaderScaleMode
        let zoomScale: CGFloat
    }
}
