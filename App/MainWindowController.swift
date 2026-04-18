import AppKit

extension NSToolbarItem.Identifier {
    static let titlebarTabs = NSToolbarItem.Identifier("local.yfff.SlatePDF.titlebarTabs")
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    let documentStore: DocumentStore
    private let splitViewController: SplitViewController
    private let toolbar = NSToolbar(identifier: "MainToolbar")
    private let titlebarTabsItem = NSToolbarItem(itemIdentifier: .titlebarTabs)
    private var isTitlebarTabsItemAttached = false
    private var allowsTerminationWithoutPrompt = false

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        splitViewController = SplitViewController(documentStore: documentStore)
        let window = ReaderShortcutWindow(contentViewController: splitViewController)

        window.title = "SlatePDF"
        window.setContentSize(NSSize(width: 1360, height: 900))
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        window.styleMask.insert(.fullSizeContentView)
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
        applyWindowChromeState()
        refreshWindowTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        applyWindowChromeState()
        refreshWindowTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        applyWindowChromeState()
        refreshWindowTitle()
    }

    private func configureTitlebarTabsItemIfNeeded() {
        let tabsView = splitViewController.titlebarTabsController.view
        tabsView.frame = NSRect(x: 0, y: 0, width: 760, height: 28)
        titlebarTabsItem.label = ""
        titlebarTabsItem.paletteLabel = ""
        titlebarTabsItem.view = tabsView
        titlebarTabsItem.visibilityPriority = .high
    }

    private func applyWindowChromeState() {
        let shouldShowTitlebarTabs =
            documentStore.tabPresentationMode == .horizontalTitlebar &&
            !documentStore.isLeftSidebarVisible

        splitViewController.titlebarTabsController.setTabsStripVisible(shouldShowTitlebarTabs)
        synchronizeTitlebarTabsItem(isVisible: shouldShowTitlebarTabs)
        synchronizeWindowToolbar(isVisible: shouldShowTitlebarTabs)
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
        if isVisible {
            configureTitlebarTabsItemIfNeeded()
            if isTitlebarTabsItemAttached == false {
                toolbar.insertItem(withItemIdentifier: .titlebarTabs, at: 0)
                isTitlebarTabsItemAttached = true
            }
            toolbar.centeredItemIdentifier = .titlebarTabs
            return
        }

        toolbar.centeredItemIdentifier = nil
        if let itemIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == .titlebarTabs }) {
            toolbar.removeItem(at: itemIndex)
        }
        isTitlebarTabsItemAttached = false
    }

    private func refreshWindowTitle() {
        window?.title = documentStore.activeSession?.title ?? "SlatePDF"
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
        splitViewController.readerViewController.fitToWidth()
    }

    func zoomIn() {
        splitViewController.readerViewController.zoomIn()
    }

    func zoomOut() {
        splitViewController.readerViewController.zoomOut()
    }

    func goToNextPage() {
        splitViewController.readerViewController.goToNextPage()
    }

    func goToPreviousPage() {
        splitViewController.readerViewController.goToPreviousPage()
    }

    func navigateBack() {
        splitViewController.readerViewController.navigateBack()
    }

    func navigateForward() {
        splitViewController.readerViewController.navigateForward()
    }

    var canGoBack: Bool { splitViewController.readerViewController.canGoBack }
    var canGoForward: Bool { splitViewController.readerViewController.canGoForward }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        splitViewController.readerViewController.goToPage(pageIndex)
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

    func installPlainShortcutHandler(_ handler: @escaping (NSEvent, NSWindow) -> Bool) {
        guard let window = window as? ReaderShortcutWindow else { return }
        window.plainShortcutHandler = handler
    }

    func requestCloseActiveSession() {
        guard let sessionID = documentStore.activeSessionID else { return }
        requestCloseSession(sessionID)
    }

    func requestCloseSession(_ sessionID: UUID) {
        guard let session = documentStore.session(for: sessionID) else { return }
        guard session.isDirty else {
            documentStore.close(sessionID: sessionID)
            return
        }

        switch presentUnsavedChangesAlert(
            title: "Save changes to “\(session.title)” before closing?",
            detail: "Your highlights are only in memory until you save them."
        ) {
        case .save:
            do {
                try documentStore.saveAnnotations(for: sessionID)
                documentStore.close(sessionID: sessionID)
            } catch {
                presentSaveError(error)
            }
        case .discard:
            documentStore.close(sessionID: sessionID)
        case .cancel:
            return
        }
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
            title: "Save changes before quitting SlatePDF?",
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        prepareForApplicationTermination()
    }

    @discardableResult
    func triggerHighlightShortcut() -> Bool {
        splitViewController.readerViewController.triggerHighlightShortcut()
    }

    func exitHighlightMode() {
        splitViewController.readerViewController.exitHighlightMode()
    }

    func setHighlightColor(_ color: HighlightColor) {
        splitViewController.readerViewController.setHighlightColor(color)
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        splitViewController.readerViewController.removeHighlightUnderCursor()
    }

    var currentHighlightColor: HighlightColor {
        splitViewController.readerViewController.currentHighlightColor
    }

    func toggleNightMode() {
        splitViewController.readerViewController.toggleNightMode()
        applyNightAppearance()
    }

    private func applyNightAppearance() {
        let isNight = splitViewController.readerViewController.isNightModeEnabled
        window?.appearance = NSAppearance(named: isNight ? .darkAqua : .aqua)
        splitViewController.refreshChromeColors()
    }

    func saveAnnotations() throws {
        try splitViewController.readerViewController.saveAnnotations()
    }

    @discardableResult
    func searchCurrentDocument(for query: String) -> Bool {
        splitViewController.readerViewController.search(for: query)
    }

    func showFindBar() {
        splitViewController.readerViewController.showFindBar()
    }

    func hideFindBar() {
        splitViewController.readerViewController.hideFindBar()
    }

    var isFindBarVisible: Bool {
        splitViewController.readerViewController.isFindBarVisible
    }

    @discardableResult
    func findNextMatch() -> Bool {
        splitViewController.readerViewController.findNextMatch()
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        splitViewController.readerViewController.findPreviousMatch()
    }

    var isHighlightModeEnabled: Bool {
        splitViewController.readerViewController.isHighlightModeEnabled
    }

    var isNightModeEnabled: Bool {
        splitViewController.readerViewController.isNightModeEnabled
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
}
