import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var mainWindowControllers: [UUID: MainWindowController] = [:]
    private var settingsWindowController: SettingsWindowController?
    private var documentStore: DocumentStore!
    private var appConfiguration: AppConfiguration = .default
    private var configStore: AppConfigurationStore?
    private var readerShortcutsController: ReaderShortcutsController?
    private var recentFilesPaletteController: RecentFilesPaletteController?
    private let recentFilesMenu = NSMenu(title: "Open Recent")
    private let windowMenu = NSMenu(title: "Window")
    private var autoSaveTimer: Timer?
    private var reportedAutoSaveFailureURLs: Set<URL> = []
    private var pendingOpenURLs: [URL] = []
    private var mainWindowController: MainWindowController? {
        currentWindowController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        do {
            let configStore = try AppConfigurationStore()
            self.configStore = configStore
            appConfiguration = try configStore.load()
        } catch {
            presentConfigurationError(error)
            NSApp.terminate(nil)
            return
        }

        documentStore = DocumentStore(appConfiguration: appConfiguration)
        try? documentStore.restorePersistedState()
        installMainMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        readerShortcutsController = ReaderShortcutsController(
            shortcutsProvider: { [weak self] in
                self?.appConfiguration.shortcuts.bindings ?? [:]
            },
            handlerProvider: { [weak self] in
                self?.shortcutHandlerMap() ?? [:]
            }
        )

        for windowID in documentStore.windowIDs() {
            let controller = makeWindowController(windowID: windowID)
            controller.showWindow(nil)
            controller.window?.orderFront(nil)
        }
        currentWindowController()?.window?.makeKeyAndOrderFront(nil)
        updateRecentFilesMenu()
        startAutoSaveTimer()
        NSApp.activate(ignoringOtherApps: true)

        if pendingOpenURLs.isEmpty == false {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            openExternalURLs(urls)
        }
    }

    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runAutoSave()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoSaveTimer = timer
    }

    private func runAutoSave() {
        let errors = documentStore.autoSaveDirtySessions()
        guard errors.isEmpty == false else { return }
        let freshErrors = errors.filter { reportedAutoSaveFailureURLs.contains($0.key) == false }
        guard freshErrors.isEmpty == false else { return }
        reportedAutoSaveFailureURLs.formUnion(freshErrors.keys)
        presentAutoSaveErrors(freshErrors)
        NSLog("SlatePDF auto-save failed for: %@", errors.keys.map(\.lastPathComponent).joined(separator: ", "))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (currentWindowController() ?? mainWindowControllers.values.first)?.prepareForApplicationTermination() == false
            ? .terminateCancel
            : .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.isEmpty == false else { return }
        guard documentStore != nil else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        openExternalURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard documentStore != nil else {
            pendingOpenURLs.append(url)
            return true
        }
        openExternalURLs([url])
        return true
    }

    private func openExternalURLs(_ urls: [URL]) {
        mainWindowController?.hideFindBar()
        let targetWindowID = mainWindowController?.windowID ?? documentStore.defaultWindowID
        do {
            for url in urls {
                _ = try documentStore.open(documentAt: url, in: targetWindowID)
            }
        } catch {
            presentOpenError(error)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        let dirtyURLs = Set(documentStore.sessions.filter(\.isDirty).map(\.url))
        reportedAutoSaveFailureURLs.formIntersection(dirtyURLs)
        updateRecentFilesMenu()
    }

    private func shortcutHandlerMap() -> [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] {
        [
            .highlightSelection: { [weak self] in self?.highlightSelection(nil) },
            .exitHighlightMode: { [weak self] in self?.exitHighlightMode(nil) },
            .toggleNightMode: { [weak self] in self?.toggleNightMode(nil) },
            .saveAnnotations: { [weak self] in self?.saveAnnotations(nil) },
            .copyHighlightsMarkdown: { [weak self] in self?.copyHighlightsMarkdown(nil) },
            .removeHighlight: { [weak self] in self?.removeHighlightUnderCursorAction(nil) },
            .highlightColorPink: { [weak self] in self?.setHighlightColorPink(nil) },
            .highlightColorYellow: { [weak self] in self?.setHighlightColorYellow(nil) },
            .highlightColorGreen: { [weak self] in self?.setHighlightColorGreen(nil) },
            .toggleLeftSidebar: { [weak self] in self?.toggleLeftSidebar(nil) },
            .toggleRightSidebar: { [weak self] in self?.toggleRightSidebar(nil) },
            .useSidebarTabs: { [weak self] in self?.useSidebarTabs(nil) },
            .useTitlebarTabs: { [weak self] in self?.useTitlebarTabs(nil) },
            .closeCurrentTab: { [weak self] in self?.closeCurrentTab(nil) },
            .previousTab: { [weak self] in self?.activatePreviousTab(nil) },
            .nextTab: { [weak self] in self?.activateNextTab(nil) },
            .fitWidth: { [weak self] in self?.fitReaderToWidth(nil) },
            .zoomIn: { [weak self] in self?.zoomInReader(nil) },
            .zoomOut: { [weak self] in self?.zoomOutReader(nil) },
            .singlePage: { [weak self] in self?.useSinglePage(nil) },
            .singlePageContinuous: { [weak self] in self?.useSinglePageContinuous(nil) },
            .twoUp: { [weak self] in self?.useTwoUp(nil) },
            .twoUpContinuous: { [weak self] in self?.useTwoUpContinuous(nil) },
            .pageDown: { [weak self] in self?.goToNextPageAction(nil) },
            .pageUp: { [weak self] in self?.goToPreviousPageAction(nil) },
            .halfPageDown: { [weak self] in self?.scrollHalfPageDownAction(nil) },
            .halfPageUp: { [weak self] in self?.scrollHalfPageUpAction(nil) },
            .goToFirstPage: { [weak self] in self?.goToFirstPageAction(nil) },
            .goToLastPage: { [weak self] in self?.goToLastPageAction(nil) },
            .navigateBack: { [weak self] in self?.navigateBackAction(nil) },
            .navigateForward: { [weak self] in self?.navigateForwardAction(nil) },
            .findNextMatch: { [weak self] in self?.findNextMatchAction(nil) },
            .findPreviousMatch: { [weak self] in self?.findPreviousMatchAction(nil) },
            .gotoPage: { [weak self] in self?.showGotoPageDialog(nil) },
            .showRecentFilesPalette: { [weak self] in self?.showRecentFilesPalette(nil) },
            .reopenLastClosed: { [weak self] in self?.reopenLastClosed(nil) },
            .newWindow: { [weak self] in self?.newWindow(nil) },
            .toggleAllPagesOverview: { [weak self] in self?.toggleAllPagesOverview(nil) },
            .toggleReaderSplit: { [weak self] in self?.toggleReaderSplitAction(nil) },
            .toggleRightSidebarMode: { [weak self] in self?.toggleRightSidebarModeAction(nil) },
            .swapSidebars: { [weak self] in self?.swapSidebarsAction(nil) },
            .undoLastHighlight: { [weak self] in self?.undoLastHighlightAction(nil) },
            .redoLastHighlight: { [weak self] in self?.redoLastHighlightAction(nil) },
        ]
    }

    private func makeWindowController(windowID: UUID) -> MainWindowController {
        if let existing = mainWindowControllers[windowID] {
            return existing
        }

        let controller = MainWindowController(documentStore: documentStore, windowID: windowID)
        controller.shouldCloseHandler = { [weak self] controller in
            self?.handleWindowShouldClose(controller) ?? true
        }
        controller.didCloseHandler = { [weak self] controller in
            self?.handleWindowDidClose(controller)
        }
        controller.installPlainShortcutHandler { [weak self] event, window in
            guard let self,
                  let readerShortcutsController = self.readerShortcutsController else { return false }
            return readerShortcutsController.handlePlainShortcut(for: event, in: window)
        }
        mainWindowControllers[windowID] = controller
        return controller
    }

    private func currentWindowController() -> MainWindowController? {
        if let keyWindow = NSApp.keyWindow,
           let controller = controller(for: keyWindow) {
            return controller
        }
        if let mainWindow = NSApp.mainWindow,
           let controller = controller(for: mainWindow) {
            return controller
        }
        return mainWindowControllers.values.first
    }

    private func controller(for window: NSWindow?) -> MainWindowController? {
        guard let window else { return nil }
        return mainWindowControllers.values.first { $0.window === window }
    }

    private func handleWindowShouldClose(_ controller: MainWindowController) -> Bool {
        let isLastWindow = mainWindowControllers.count <= 1
        if isLastWindow {
            return controller.prepareForApplicationTermination()
        }
        guard controller.prepareForWindowClosure() else { return false }
        documentStore.closeWindow(id: controller.windowID)
        return true
    }

    private func handleWindowDidClose(_ controller: MainWindowController) {
        mainWindowControllers.removeValue(forKey: controller.windowID)
    }

    @objc
    func openDocument(_ sender: Any?) {
        mainWindowController?.hideFindBar()
        let targetWindowID = mainWindowController?.windowID ?? documentStore.defaultWindowID
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.message = "Open one or more PDF files."

        guard panel.runModal() == .OK else { return }

        do {
            for url in panel.urls {
                _ = try documentStore.open(documentAt: url, in: targetWindowID)
            }
        } catch {
            presentOpenError(error)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(buildApplicationMenuItem())
        mainMenu.addItem(buildFileMenuItem())
        mainMenu.addItem(buildEditMenuItem())
        mainMenu.addItem(buildTabsMenuItem())
        mainMenu.addItem(buildAnnotateMenuItem())
        mainMenu.addItem(buildViewMenuItem())
        mainMenu.addItem(buildNavigateMenuItem())
        mainMenu.addItem(buildWindowMenuItem())
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func buildApplicationMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem(title: "SlatePDF", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        appMenu.addItem(
            settingsItem
        )
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: "Hide SlatePDF",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.keyEquivalentModifierMask = [.command]
        hideItem.target = NSApp
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(hideItem)
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: "Quit SlatePDF",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func buildFileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        let newWindowItem = makeConfiguredMenuItem(
            title: ShortcutCommand.newWindow.menuTitle,
            command: .newWindow,
            action: #selector(newWindow(_:))
        )
        let openItem = NSMenuItem(
            title: "Open…",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        let quickOpenRecentItem = makeConfiguredMenuItem(
            title: ShortcutCommand.showRecentFilesPalette.menuTitle,
            command: .showRecentFilesPalette,
            action: #selector(showRecentFilesPalette(_:))
        )
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(findInCurrentDocument(_:)),
            keyEquivalent: "f"
        )
        let findNextItem = makeConfiguredMenuItem(
            title: ShortcutCommand.findNextMatch.menuTitle,
            command: .findNextMatch,
            action: #selector(findNextMatchAction(_:))
        )
        let findPreviousItem = makeConfiguredMenuItem(
            title: ShortcutCommand.findPreviousMatch.menuTitle,
            command: .findPreviousMatch,
            action: #selector(findPreviousMatchAction(_:))
        )
        let closeItem = makeConfiguredMenuItem(
            title: "Close Current Tab",
            command: .closeCurrentTab,
            action: #selector(closeCurrentTab(_:))
        )
        let saveAnnotationsItem = makeConfiguredMenuItem(
            title: "Save Annotations",
            command: .saveAnnotations,
            action: #selector(saveAnnotations(_:))
        )
        let exportHighlightsItem = NSMenuItem(
            title: "Export Highlights…",
            action: #selector(exportHighlights(_:)),
            keyEquivalent: ""
        )
        exportHighlightsItem.target = self
        let copyHighlightsMarkdownItem = makeConfiguredMenuItem(
            title: ShortcutCommand.copyHighlightsMarkdown.menuTitle,
            command: .copyHighlightsMarkdown,
            action: #selector(copyHighlightsMarkdown(_:))
        )
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentFilesMenu
        let reopenClosedItem = makeConfiguredMenuItem(
            title: "Reopen Closed Tab",
            command: .reopenLastClosed,
            action: #selector(reopenLastClosed(_:))
        )

        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        findItem.keyEquivalentModifierMask = [.command]
        findItem.target = self
        fileMenu.items = [
            settingsItem,
            .separator(),
            newWindowItem,
            openItem,
            quickOpenRecentItem,
            recentItem,
            reopenClosedItem,
            findItem,
            findNextItem,
            findPreviousItem,
            saveAnnotationsItem,
            exportHighlightsItem,
            copyHighlightsMarkdownItem,
            .separator(),
            closeItem,
        ]
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func buildEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.autoenablesItems = true

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "")
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")

        for item in [cutItem, copyItem, pasteItem, selectAllItem] {
            item.keyEquivalentModifierMask = [.command]
            item.target = nil
        }

        editMenu.items = [
            undoItem,
            redoItem,
            .separator(),
            cutItem,
            copyItem,
            pasteItem,
            .separator(),
            selectAllItem,
        ]
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func buildTabsMenuItem() -> NSMenuItem {
        let tabsMenuItem = NSMenuItem(title: "Tabs", action: nil, keyEquivalent: "")
        let tabsMenu = NSMenu(title: "Tabs")

        tabsMenu.items = [
            makeConfiguredMenuItem(
                title: "Previous Tab",
                command: .previousTab,
                action: #selector(activatePreviousTab(_:))
            ),
            makeConfiguredMenuItem(
                title: "Next Tab",
                command: .nextTab,
                action: #selector(activateNextTab(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: "Use Sidebar Tabs",
                command: .useSidebarTabs,
                action: #selector(useSidebarTabs(_:))
            ),
            makeConfiguredMenuItem(
                title: "Use Titlebar Tabs",
                command: .useTitlebarTabs,
                action: #selector(useTitlebarTabs(_:))
            ),
        ]
        tabsMenuItem.submenu = tabsMenu
        return tabsMenuItem
    }

    private func buildAnnotateMenuItem() -> NSMenuItem {
        let annotateMenuItem = NSMenuItem(title: "Annotate", action: nil, keyEquivalent: "")
        let annotateMenu = NSMenu(title: "Annotate")

        annotateMenu.items = [
            makeConfiguredMenuItem(
                title: "Highlight Selection or Enter Highlight Mode",
                command: .highlightSelection,
                action: #selector(highlightSelection(_:))
            ),
            makeConfiguredMenuItem(
                title: "Exit Highlight Mode",
                command: .exitHighlightMode,
                action: #selector(exitHighlightMode(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: ShortcutCommand.highlightColorPink.menuTitle,
                command: .highlightColorPink,
                action: #selector(setHighlightColorPink(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.highlightColorYellow.menuTitle,
                command: .highlightColorYellow,
                action: #selector(setHighlightColorYellow(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.highlightColorGreen.menuTitle,
                command: .highlightColorGreen,
                action: #selector(setHighlightColorGreen(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: ShortcutCommand.removeHighlight.menuTitle,
                command: .removeHighlight,
                action: #selector(removeHighlightUnderCursorAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.undoLastHighlight.menuTitle,
                command: .undoLastHighlight,
                action: #selector(undoLastHighlightAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.redoLastHighlight.menuTitle,
                command: .redoLastHighlight,
                action: #selector(redoLastHighlightAction(_:))
            ),
        ]

        annotateMenuItem.submenu = annotateMenu
        return annotateMenuItem
    }

    private func buildViewMenuItem() -> NSMenuItem {
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")

        viewMenu.items = [
            makeConfiguredMenuItem(
                title: "Toggle Left Sidebar",
                command: .toggleLeftSidebar,
                action: #selector(toggleLeftSidebar(_:))
            ),
            makeConfiguredMenuItem(
                title: "Toggle Right Sidebar",
                command: .toggleRightSidebar,
                action: #selector(toggleRightSidebar(_:))
            ),
            makeConfiguredMenuItem(
                title: "Toggle Night Mode",
                command: .toggleNightMode,
                action: #selector(toggleNightMode(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: "Fit Width",
                command: .fitWidth,
                action: #selector(fitReaderToWidth(_:))
            ),
            makeConfiguredMenuItem(
                title: "Zoom In",
                command: .zoomIn,
                action: #selector(zoomInReader(_:))
            ),
            makeConfiguredMenuItem(
                title: "Zoom Out",
                command: .zoomOut,
                action: #selector(zoomOutReader(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: ReaderDisplayMode.singlePage.menuTitle,
                command: .singlePage,
                action: #selector(useSinglePage(_:))
            ),
            makeConfiguredMenuItem(
                title: ReaderDisplayMode.singlePageContinuous.menuTitle,
                command: .singlePageContinuous,
                action: #selector(useSinglePageContinuous(_:))
            ),
            makeConfiguredMenuItem(
                title: ReaderDisplayMode.twoUp.menuTitle,
                command: .twoUp,
                action: #selector(useTwoUp(_:))
            ),
            makeConfiguredMenuItem(
                title: ReaderDisplayMode.twoUpContinuous.menuTitle,
                command: .twoUpContinuous,
                action: #selector(useTwoUpContinuous(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: "All Pages Overview",
                command: .toggleAllPagesOverview,
                action: #selector(toggleAllPagesOverview(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleReaderSplit.menuTitle,
                command: .toggleReaderSplit,
                action: #selector(toggleReaderSplitAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleRightSidebarMode.menuTitle,
                command: .toggleRightSidebarMode,
                action: #selector(toggleRightSidebarModeAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.swapSidebars.menuTitle,
                command: .swapSidebars,
                action: #selector(swapSidebarsAction(_:))
            ),
        ]
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    private func buildNavigateMenuItem() -> NSMenuItem {
        let navigateMenuItem = NSMenuItem(title: "Navigate", action: nil, keyEquivalent: "")
        let navigateMenu = NSMenu(title: "Navigate")

        navigateMenu.items = [
            makeConfiguredMenuItem(
                title: "Next Page",
                command: .pageDown,
                action: #selector(goToNextPageAction(_:))
            ),
            makeConfiguredMenuItem(
                title: "Previous Page",
                command: .pageUp,
                action: #selector(goToPreviousPageAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.halfPageDown.menuTitle,
                command: .halfPageDown,
                action: #selector(scrollHalfPageDownAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.halfPageUp.menuTitle,
                command: .halfPageUp,
                action: #selector(scrollHalfPageUpAction(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: ShortcutCommand.goToFirstPage.menuTitle,
                command: .goToFirstPage,
                action: #selector(goToFirstPageAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.goToLastPage.menuTitle,
                command: .goToLastPage,
                action: #selector(goToLastPageAction(_:))
            ),
            makeConfiguredMenuItem(
                title: "Go to Page…",
                command: .gotoPage,
                action: #selector(showGotoPageDialog(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: "Back",
                command: .navigateBack,
                action: #selector(navigateBackAction(_:))
            ),
            makeConfiguredMenuItem(
                title: "Forward",
                command: .navigateForward,
                action: #selector(navigateForwardAction(_:))
            ),
        ]

        navigateMenuItem.submenu = navigateMenu
        return navigateMenuItem
    }

    private func buildWindowMenuItem() -> NSMenuItem {
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let minimizeItem = NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        minimizeItem.keyEquivalentModifierMask = [.command]
        minimizeItem.target = nil

        let zoomItem = NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        zoomItem.target = nil

        let bringAllToFrontItem = NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        bringAllToFrontItem.target = NSApp

        windowMenu.items = [
            minimizeItem,
            zoomItem,
            .separator(),
            bringAllToFrontItem,
        ]
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    private func makeConfiguredMenuItem(
        title: String,
        command: ShortcutCommand,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = command

        if let shortcut = appConfiguration.shortcuts.bindings[command] {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
    }

    @objc
    private func closeCurrentTab(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow,
           controller(for: keyWindow) == nil {
            keyWindow.performClose(sender)
            return
        }
        guard let controller = mainWindowController else { return }
        if documentStore.activeSession(in: controller.windowID) == nil {
            controller.window?.performClose(sender)
            return
        }
        controller.requestCloseActiveSession()
    }

    @objc
    private func activatePreviousTab(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        documentStore.clearSearch(in: controller.windowID)
        documentStore.activatePreviousSession(in: controller.windowID)
    }

    @objc
    private func activateNextTab(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        documentStore.clearSearch(in: controller.windowID)
        documentStore.activateNextSession(in: controller.windowID)
    }

    @objc
    private func useSidebarTabs(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        documentStore.setTabPresentationMode(.verticalSidebar, in: controller.windowID)
    }

    @objc
    private func useTitlebarTabs(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        documentStore.setTabPresentationMode(.horizontalTitlebar, in: controller.windowID)
    }

    @objc
    private func newWindow(_ sender: Any?) {
        let sourceWindowID = mainWindowController?.windowID
        let windowID = documentStore.createWindow(copyingFrom: sourceWindowID)
        let controller = makeWindowController(windowID: windowID)
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }

    @objc
    private func showRecentFilesPalette(_ sender: Any?) {
        if recentFilesPaletteController == nil {
            recentFilesPaletteController = RecentFilesPaletteController { [weak self] urls in
                self?.openRecentDocuments(urls)
            }
        }
        recentFilesPaletteController?.show(
            with: documentStore.recentDocumentURLs,
            relativeTo: mainWindowController?.window
        )
    }

    @objc
    private func highlightSelection(_ sender: Any?) {
        _ = mainWindowController?.triggerHighlightShortcut()
    }

    @objc
    private func exitHighlightMode(_ sender: Any?) {
        if mainWindowController?.isFindBarVisible == true {
            mainWindowController?.hideFindBar()
            return
        }
        if mainWindowController?.isAllPagesOverviewActive == true {
            mainWindowController?.setAllPagesOverviewActive(false)
            return
        }
        mainWindowController?.exitHighlightMode()
    }

    @objc
    private func toggleAllPagesOverview(_ sender: Any?) {
        _ = mainWindowController?.toggleAllPagesOverview()
    }

    @objc
    private func toggleRightSidebarModeAction(_ sender: Any?) {
        mainWindowController?.toggleRightSidebarMode()
    }

    @objc
    private func toggleReaderSplitAction(_ sender: Any?) {
        mainWindowController?.toggleReaderSplit()
    }

    @objc
    private func swapSidebarsAction(_ sender: Any?) {
        var newConfiguration = appConfiguration
        newConfiguration.layout.sidebarsSwapped.toggle()
        applyUpdatedConfiguration(newConfiguration)
    }

    @objc
    private func setHighlightColorPink(_ sender: Any?) {
        mainWindowController?.setHighlightColor(.pink)
    }

    @objc
    private func setHighlightColorYellow(_ sender: Any?) {
        mainWindowController?.setHighlightColor(.yellow)
    }

    @objc
    private func setHighlightColorGreen(_ sender: Any?) {
        mainWindowController?.setHighlightColor(.green)
    }

    @objc
    private func removeHighlightUnderCursorAction(_ sender: Any?) {
        _ = mainWindowController?.removeHighlightUnderCursor()
    }

    @objc
    private func undoLastHighlightAction(_ sender: Any?) {
        _ = mainWindowController?.undoLastHighlight()
    }

    @objc
    private func redoLastHighlightAction(_ sender: Any?) {
        _ = mainWindowController?.redoLastHighlight()
    }

    @objc
    private func toggleLeftSidebar(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        let isVisible = documentStore.isLeftSidebarVisible(in: controller.windowID)
        documentStore.setLeftSidebarVisible(!isVisible, in: controller.windowID)
    }

    @objc
    private func toggleRightSidebar(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        let isVisible = documentStore.isRightSidebarVisible(in: controller.windowID)
        documentStore.setRightSidebarVisible(!isVisible, in: controller.windowID)
    }

    @objc
    private func toggleNightMode(_ sender: Any?) {
        mainWindowController?.toggleNightMode()
    }

    @objc
    private func fitReaderToWidth(_ sender: Any?) {
        mainWindowController?.fitReaderToWidth()
    }

    @objc
    private func zoomInReader(_ sender: Any?) {
        mainWindowController?.zoomIn()
    }

    @objc
    private func zoomOutReader(_ sender: Any?) {
        mainWindowController?.zoomOut()
    }

    @objc
    private func goToNextPageAction(_ sender: Any?) {
        mainWindowController?.goToNextPage()
    }

    @objc
    private func goToPreviousPageAction(_ sender: Any?) {
        mainWindowController?.goToPreviousPage()
    }

    @objc
    private func scrollHalfPageDownAction(_ sender: Any?) {
        mainWindowController?.scrollHalfPageDown()
    }

    @objc
    private func scrollHalfPageUpAction(_ sender: Any?) {
        mainWindowController?.scrollHalfPageUp()
    }

    @objc
    private func goToFirstPageAction(_ sender: Any?) {
        mainWindowController?.goToFirstPage()
    }

    @objc
    private func goToLastPageAction(_ sender: Any?) {
        mainWindowController?.goToLastPage()
    }

    @objc
    private func navigateBackAction(_ sender: Any?) {
        mainWindowController?.navigateBack()
    }

    @objc
    private func navigateForwardAction(_ sender: Any?) {
        mainWindowController?.navigateForward()
    }

    @objc
    private func showGotoPageDialog(_ sender: Any?) {
        guard let mainWindowController,
              documentStore.activeSession(in: mainWindowController.windowID) != nil else { return }

        let pageCount = mainWindowController.currentPageCount
        guard pageCount > 0 else { return }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "1–\(pageCount)"

        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page number between 1 and \(pageCount)."
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn,
              let pageNumber = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }

        let index = pageNumber - 1
        guard mainWindowController.goToPage(index) else {
            let warn = NSAlert()
            warn.alertStyle = .warning
            warn.messageText = "Page Out of Range"
            warn.informativeText = "Enter a page number between 1 and \(pageCount)."
            warn.runModal()
            return
        }
    }

    @objc
    private func useSinglePage(_ sender: Any?) {
        setActiveReaderDisplayMode(.singlePage)
    }

    @objc
    private func useSinglePageContinuous(_ sender: Any?) {
        setActiveReaderDisplayMode(.singlePageContinuous)
    }

    @objc
    private func useTwoUp(_ sender: Any?) {
        setActiveReaderDisplayMode(.twoUp)
    }

    @objc
    private func useTwoUpContinuous(_ sender: Any?) {
        setActiveReaderDisplayMode(.twoUpContinuous)
    }

    @objc
    private func saveAnnotations(_ sender: Any?) {
        do {
            try mainWindowController?.saveAnnotations()
        } catch {
            presentSaveError(error)
        }
    }

    @objc
    private func exportHighlights(_ sender: Any?) {
        guard let context = currentHighlightExportContext() else { return }
        guard let format = promptForHighlightExportFormat() else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = HighlightExporter.defaultFilename(
            for: context.documentTitle,
            format: format
        )
        panel.allowedContentTypes = [contentType(for: format)]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try HighlightExporter.export(context.groups, format: format)
            try data.write(to: url)
        } catch {
            presentExportError(error)
        }
    }

    @objc
    private func copyHighlightsMarkdown(_ sender: Any?) {
        guard let context = currentHighlightExportContext() else { return }

        do {
            let data = try HighlightExporter.export(context.groups, format: .markdown)
            guard let string = String(data: data, encoding: .utf8) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        } catch {
            presentExportError(error)
        }
    }

    private func setActiveReaderDisplayMode(_ mode: ReaderDisplayMode) {
        guard let controller = mainWindowController,
              let sessionID = documentStore.activeSessionID(in: controller.windowID) else { return }
        documentStore.setDisplayMode(mode, for: sessionID)
    }

    private func updateRecentFilesMenu() {
        recentFilesMenu.removeAllItems()

        if documentStore.recentDocumentURLs.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentFilesMenu.addItem(emptyItem)
            return
        }

        for url in documentStore.recentDocumentURLs {
            let item = NSMenuItem(
                title: url.deletingPathExtension().lastPathComponent,
                action: #selector(openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = url.path
            item.representedObject = url
            recentFilesMenu.addItem(item)
        }
    }

    @objc
    private func findInCurrentDocument(_ sender: Any?) {
        guard let controller = mainWindowController,
              documentStore.activeSession(in: controller.windowID) != nil else { return }
        mainWindowController?.showFindBar()
    }

    @objc
    private func findNextMatchAction(_ sender: Any?) {
        _ = mainWindowController?.findNextMatch()
    }

    @objc
    private func findPreviousMatchAction(_ sender: Any?) {
        _ = mainWindowController?.findPreviousMatch()
    }

    @objc
    private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openRecentDocuments([url])
    }

    private func openRecentDocuments(_ urls: [URL]) {
        guard urls.isEmpty == false else { return }
        mainWindowController?.hideFindBar()
        let targetWindowID = mainWindowController?.windowID ?? documentStore.defaultWindowID

        do {
            for url in urls {
                _ = try documentStore.open(documentAt: url, in: targetWindowID)
            }
        } catch {
            presentOpenError(error)
        }
    }

    @objc
    private func reopenLastClosed(_ sender: Any?) {
        guard let controller = mainWindowController,
              let url = documentStore.popRecentlyClosed(in: controller.windowID) else { return }
        controller.hideFindBar()
        do {
            _ = try documentStore.open(documentAt: url, in: controller.windowID)
        } catch {
            presentOpenError(error)
        }
    }

    @objc
    private func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configuration: appConfiguration,
                onConfigurationChanged: { [weak self] configuration in
                    self?.applyUpdatedConfiguration(configuration)
                }
            )
        }

        settingsWindowController?.sync(configuration: appConfiguration)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyUpdatedConfiguration(_ configuration: AppConfiguration) {
        guard let configStore else { return }
        let previousConfiguration = appConfiguration
        var newConfiguration = configuration

        if previousConfiguration.layout.sidebarsSwapped != newConfiguration.layout.sidebarsSwapped {
            swap(&newConfiguration.layout.leftSidebarWidth, &newConfiguration.layout.rightSidebarWidth)
            swap(&newConfiguration.layout.leftSidebarMinWidth, &newConfiguration.layout.rightSidebarMinWidth)
            swap(&newConfiguration.layout.leftSidebarMaxWidth, &newConfiguration.layout.rightSidebarMaxWidth)
        }

        do {
            try configStore.save(newConfiguration)
            appConfiguration = newConfiguration
            refreshMenuShortcuts()
            documentStore.updateAppConfiguration(newConfiguration)
        } catch {
            appConfiguration = previousConfiguration
            refreshMenuShortcuts()
            documentStore.updateAppConfiguration(previousConfiguration)
            settingsWindowController?.sync(configuration: previousConfiguration)
            presentConfigurationSaveError(error)
        }
    }

    private func refreshMenuShortcuts() {
        guard let menu = NSApp.mainMenu else { return }
        refreshMenuShortcuts(in: menu)
    }

    private func refreshMenuShortcuts(in menu: NSMenu) {
        for item in menu.items {
            if let command = item.representedObject as? ShortcutCommand,
               let shortcut = appConfiguration.shortcuts.bindings[command] {
                item.keyEquivalent = shortcut.menuKeyEquivalent
                item.keyEquivalentModifierMask = shortcut.modifierMask
            } else if item.representedObject is ShortcutCommand {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }

            if let submenu = item.submenu {
                refreshMenuShortcuts(in: submenu)
            }
        }
    }

    private func presentOpenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to open PDF"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentConfigurationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Failed to load SlatePDF config"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func presentConfigurationSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to save SlatePDF settings"
        if let window = settingsWindowController?.window ?? mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to save annotations"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentExportError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to export highlights"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func currentHighlightExportContext() -> (documentTitle: String, groups: [DocumentHighlightGroup])? {
        guard let windowID = mainWindowController?.windowID,
              let session = documentStore.activeSession(in: windowID) else { return nil }
        let groups = documentStore.annotationGroups(for: session.id)
        guard groups.isEmpty == false else { return nil }
        return (session.title, groups)
    }

    private func promptForHighlightExportFormat() -> HighlightExportFormat? {
        let alert = NSAlert()
        alert.messageText = "Export Highlights"
        alert.informativeText = "Choose the output format."
        let buttons: [(String, HighlightExportFormat)] = [
            ("Markdown", .markdown),
            ("Plain Text", .plainText),
            ("JSON", .json),
        ]
        buttons.forEach { alert.addButton(withTitle: $0.0) }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let index = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        guard buttons.indices.contains(index) else { return nil }
        return buttons[index].1
    }

    private func contentType(for format: HighlightExportFormat) -> UTType {
        switch format {
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        case .plainText:
            return .plainText
        case .json:
            return .json
        }
    }

    private func presentAutoSaveErrors(_ errors: [URL: Error]) {
        let sortedFiles = errors.keys.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let fileList = sortedFiles.map(\.lastPathComponent).joined(separator: "\n")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Auto-save failed"
        alert.informativeText = "These PDFs still have unsaved highlights:\n\(fileList)"
        alert.addButton(withTitle: "OK")

        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func activeEditableTextResponder() -> NSTextView? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        guard let textView = window?.firstResponder as? NSTextView,
              textView.isEditable else { return nil }
        return textView
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let controller = mainWindowController
        let windowID = controller?.windowID
        let activeSession = windowID.flatMap { documentStore.activeSession(in: $0) }

        switch menuItem.action {
        case #selector(newWindow(_:)):
            return true
        case #selector(highlightSelection(_:)):
            return activeSession != nil
        case #selector(exitHighlightMode(_:)):
            menuItem.state = controller?.isHighlightModeEnabled == true ? .on : .off
            return controller?.isHighlightModeEnabled == true
        case #selector(toggleNightMode(_:)):
            menuItem.state = controller?.isNightModeEnabled == true ? .on : .off
            return activeSession != nil
        case #selector(saveAnnotations(_:)):
            return activeSession?.isDirty == true
        case #selector(exportHighlights(_:)), #selector(copyHighlightsMarkdown(_:)):
            return currentHighlightExportContext() != nil
        case #selector(removeHighlightUnderCursorAction(_:)):
            return activeSession != nil
        case #selector(undoLastHighlightAction(_:)):
            guard activeEditableTextResponder() == nil else { return false }
            return controller?.hasUndoableHighlight == true
        case #selector(redoLastHighlightAction(_:)):
            guard activeEditableTextResponder() == nil else { return false }
            return controller?.hasRedoableHighlight == true
        case #selector(setHighlightColorPink(_:)):
            menuItem.state = controller?.currentHighlightColor == .pink ? .on : .off
            return true
        case #selector(setHighlightColorYellow(_:)):
            menuItem.state = controller?.currentHighlightColor == .yellow ? .on : .off
            return true
        case #selector(setHighlightColorGreen(_:)):
            menuItem.state = controller?.currentHighlightColor == .green ? .on : .off
            return true
        case #selector(findInCurrentDocument(_:)):
            return activeSession != nil
        case #selector(showRecentFilesPalette(_:)):
            return documentStore.recentDocumentURLs.isEmpty == false
        case #selector(findNextMatchAction(_:)), #selector(findPreviousMatchAction(_:)):
            return controller?.isFindBarVisible == true
        case #selector(useSidebarTabs(_:)):
            menuItem.state = windowID.map { documentStore.tabPresentationMode(in: $0) == .verticalSidebar } == true ? .on : .off
            return true
        case #selector(useTitlebarTabs(_:)):
            menuItem.state = windowID.map { documentStore.tabPresentationMode(in: $0) == .horizontalTitlebar } == true ? .on : .off
            return true
        case #selector(toggleLeftSidebar(_:)):
            menuItem.state = windowID.map { documentStore.isLeftSidebarVisible(in: $0) } == true ? .on : .off
            return true
        case #selector(toggleRightSidebar(_:)):
            menuItem.state = windowID.map { documentStore.isRightSidebarVisible(in: $0) } == true ? .on : .off
            return true
        case #selector(closeCurrentTab(_:)):
            return controller != nil
        case #selector(activatePreviousTab(_:)), #selector(activateNextTab(_:)):
            return windowID.map { documentStore.sessionCount(in: $0) > 1 } == true
        case #selector(fitReaderToWidth(_:)):
            menuItem.state = activeSession?.scaleMode == .fitWidth ? .on : .off
            return activeSession != nil
        case #selector(zoomInReader(_:)), #selector(zoomOutReader(_:)):
            return activeSession != nil
        case #selector(goToNextPageAction(_:)),
             #selector(goToPreviousPageAction(_:)),
             #selector(scrollHalfPageDownAction(_:)),
             #selector(scrollHalfPageUpAction(_:)):
            return activeSession != nil
        case #selector(goToFirstPageAction(_:)), #selector(goToLastPageAction(_:)):
            return activeSession != nil && (controller?.currentPageCount ?? 0) > 0
        case #selector(navigateBackAction(_:)):
            return controller?.canGoBack == true
        case #selector(navigateForwardAction(_:)):
            return controller?.canGoForward == true
        case #selector(showGotoPageDialog(_:)):
            return activeSession != nil && (controller?.currentPageCount ?? 0) > 0
        case #selector(reopenLastClosed(_:)):
            return windowID.map { documentStore.recentlyClosedURLs(in: $0).isEmpty == false } == true
        case #selector(toggleAllPagesOverview(_:)):
            menuItem.state = controller?.isAllPagesOverviewActive == true ? .on : .off
            return activeSession != nil
        case #selector(toggleReaderSplitAction(_:)):
            menuItem.state = controller?.isReaderSplitEnabled == true ? .on : .off
            return activeSession != nil
        case #selector(toggleRightSidebarModeAction(_:)):
            return windowID.map { documentStore.isRightSidebarVisible(in: $0) } == true
        case #selector(swapSidebarsAction(_:)):
            return true
        case #selector(useSinglePage(_:)):
            menuItem.state = activeSession?.displayMode == .singlePage ? .on : .off
            return activeSession != nil
        case #selector(useSinglePageContinuous(_:)):
            menuItem.state = activeSession?.displayMode == .singlePageContinuous ? .on : .off
            return activeSession != nil
        case #selector(useTwoUp(_:)):
            menuItem.state = activeSession?.displayMode == .twoUp ? .on : .off
            return activeSession != nil
        case #selector(useTwoUpContinuous(_:)):
            menuItem.state = activeSession?.displayMode == .twoUpContinuous ? .on : .off
            return activeSession != nil
        default:
            return true
        }
    }
}
