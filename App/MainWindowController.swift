import AppKit

extension NSToolbarItem.Identifier {
    static let titlebarTabs = NSToolbarItem.Identifier("local.yfff.SlatePDF.titlebarTabs")
}

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    let documentStore: DocumentStore
    private let splitViewController: SplitViewController
    private let toolbar = NSToolbar(identifier: "MainToolbar")
    private let titlebarTabsItem = NSToolbarItem(itemIdentifier: .titlebarTabs)
    private var isTitlebarTabsItemAttached = false

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

        toolbar.delegate = self
        shouldCascadeWindows = true
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
        titlebarTabsItem.label = "Open Documents"
        titlebarTabsItem.paletteLabel = "Open Documents"
        titlebarTabsItem.view = tabsView
        titlebarTabsItem.visibilityPriority = .high
    }

    private func applyWindowChromeState() {
        let shouldShowTitlebarTabs =
            documentStore.tabPresentationMode == .horizontalTitlebar &&
            !documentStore.isLeftSidebarVisible

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

        if window.toolbar === toolbar {
            window.toolbar = nil
        }
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

    func installPlainShortcutHandler(_ handler: @escaping (NSEvent, NSWindow) -> Bool) {
        guard let window = window as? ReaderShortcutWindow else { return }
        window.plainShortcutHandler = handler
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
    func removeHighlightInSelection() -> Bool {
        splitViewController.readerViewController.removeHighlightInSelection()
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

    var isHighlightModeEnabled: Bool {
        splitViewController.readerViewController.isHighlightModeEnabled
    }

    var isNightModeEnabled: Bool {
        splitViewController.readerViewController.isNightModeEnabled
    }
}
