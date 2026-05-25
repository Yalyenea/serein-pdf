import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private static let recentFilesCleanupInterval: TimeInterval = 60 * 60 * 24
    private static let recentFilesCleanupDateKey = "Serein.RecentFilesCleanup.lastDate"
    private var mainWindowControllers: [UUID: MainWindowController] = [:]
    private var settingsWindowController: SettingsWindowController?
    private var documentStore: DocumentStore!
    private var appConfiguration: AppConfiguration = .default
    private var configStore: AppConfigurationStore?
    private var appearanceObservation: NSKeyValueObservation?
    private var readerShortcutsController: ReaderShortcutsController?
    private var recentFilesPaletteController: RecentFilesPaletteController?
    private var libraryPaletteController: PDFLibraryPaletteController?
    private var openTabsPaletteController: OpenTabsPaletteController?
    private var openTabsPaletteWindowID: UUID?
    private let recentFilesMenu = NSMenu(title: "Open Recent")
    private let windowMenu = NSMenu(title: "Window")
    private var autoSaveTimer: Timer?
    private var lastRecentFilesCleanupDate: Date?
    private var reportedAutoSaveFailureURLs: Set<URL> = []
    private var pendingOpenURLs: [URL] = []
    private let openDocumentSelectionResolver = OpenDocumentSelectionResolver()
    private let securityScopedAccessController = SecurityScopedAccessController()
    private var mainWindowController: MainWindowController? {
        currentWindowController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        do {
            let configStore = try AppConfigurationStore()
            self.configStore = configStore
            appConfiguration = try configStore.load()
            let access = securityScopedAccessController.sync(access: appConfiguration.access)
            if access != appConfiguration.access {
                appConfiguration.access = access
                try configStore.save(appConfiguration)
            }
        } catch {
            presentConfigurationError(error)
            NSApp.terminate(nil)
            return
        }

        applyApplicationAppearance()
        documentStore = DocumentStore(appConfiguration: appConfiguration)
        try? documentStore.restorePersistedState()
        installMainMenu()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshThemeChromeIfFollowingSystem()
            }
        }
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
            },
            supplementalHandlerProvider: { [weak self] in
                self?.supplementalShortcutHandlerMap() ?? [:]
            }
        )

        for windowID in documentStore.windowIDs() {
            let controller = makeWindowController(windowID: windowID)
            controller.showWindow(nil)
            controller.window?.orderFront(nil)
        }
        currentWindowController()?.window?.makeKeyAndOrderFront(nil)
        runRecentFilesCleanupIfNeeded()
        updateRecentFilesMenu()
        startAutoSaveTimer()
        NSApp.activate(ignoringOtherApps: true)
        requestDefaultUsersAccessIfNeeded()

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
        if errors.isEmpty == false {
            let freshErrors = errors.filter { reportedAutoSaveFailureURLs.contains($0.key) == false }
            if freshErrors.isEmpty == false {
                reportedAutoSaveFailureURLs.formUnion(freshErrors.keys)
                presentAutoSaveErrors(freshErrors)
                NSLog("Serein auto-save failed for: %@", errors.keys.map(\.lastPathComponent).joined(separator: ", "))
            }
        }
        runRecentFilesCleanupIfNeeded()
    }

    private func runRecentFilesCleanupIfNeeded() {
        let now = Date()
        let lastCleanupDate = lastRecentFilesCleanupDate
            ?? UserDefaults.standard.object(forKey: Self.recentFilesCleanupDateKey) as? Date
        if let lastCleanupDate,
           now.timeIntervalSince(lastCleanupDate) < Self.recentFilesCleanupInterval {
            self.lastRecentFilesCleanupDate = lastCleanupDate
            return
        }
        lastRecentFilesCleanupDate = now
        UserDefaults.standard.set(now, forKey: Self.recentFilesCleanupDateKey)
        documentStore.refreshRecentDocumentURLsFromStore()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationDidResignActive(_ notification: Notification) {
        closeOpenTabsPalette()
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
            try openResolvedDocumentURLs(urls, in: targetWindowID)
        } catch {
            presentOpenError(error)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestDefaultUsersAccessIfNeeded() {
        guard let configStore,
              let usersURL = appConfiguration.access.rootURLs.first(where: { $0.standardizedFileURL.path == "/Users" }),
              appConfiguration.access.rootBookmarkData[usersURL.standardizedFileURL.path] == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = usersURL
        panel.message = "/Users is already selected. Allow access once so Serein can keep reading PDFs under user folders after reinstalling."
        panel.prompt = "Allow /Users"

        guard panel.runModal() == .OK,
              let selectedURL = panel.urls.first?.standardizedFileURL else { return }

        guard selectedURL.path == usersURL.standardizedFileURL.path else {
            presentUsersAccessSelectionError(expectedURL: usersURL, selectedURL: selectedURL)
            return
        }

        guard let bookmarkData = SecurityScopedAccessController.makeBookmarkData(for: selectedURL) else {
            presentUsersAccessBookmarkError(for: selectedURL)
            return
        }

        var updatedConfiguration = appConfiguration
        updatedConfiguration.access.rootBookmarkData[selectedURL.path] = bookmarkData
        updatedConfiguration.access = securityScopedAccessController.sync(access: updatedConfiguration.access)
        do {
            try configStore.save(updatedConfiguration)
            appConfiguration = updatedConfiguration
        } catch {
            presentConfigurationError(error)
        }
    }

    private func presentUsersAccessSelectionError(expectedURL: URL, selectedURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Choose /Users to keep broad file access"
        alert.informativeText = "Selected \(selectedURL.path), but Serein needs \(expectedURL.path)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentUsersAccessBookmarkError(for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to keep access to /Users"
        alert.informativeText = "Serein could not create persistent access for \(url.path)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        let dirtyURLs = Set(documentStore.sessions.filter(\.isDirty).map(\.url))
        reportedAutoSaveFailureURLs.formIntersection(dirtyURLs)
        updateRecentFilesMenu()
        refreshManagedMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshManagedMenuState(in: menu)
    }

    private func shortcutHandlerMap() -> [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] {
        [
            .highlightSelection: { [weak self] in self?.highlightSelection(nil) },
            .exitHighlightMode: { [weak self] in self?.exitHighlightMode(nil) },
            .toggleNightMode: { [weak self] in self?.toggleNightMode(nil) },
            .switchCurrentTheme: { [weak self] in self?.switchCurrentTheme(nil) },
            .openLibraryPDF: { [weak self] in self?.showLibraryPalette(nil) },
            .refreshLibraryIndex: { [weak self] in self?.refreshLibraryIndex(nil) },
            .openLibrarySettings: { [weak self] in self?.openLibrarySettings(nil) },
            .openShortcutSettings: { [weak self] in self?.openShortcutSettings(nil) },
            .saveAnnotations: { [weak self] in self?.saveAnnotations(nil) },
            .copyHighlightsMarkdown: { [weak self] in self?.copyHighlightsMarkdown(nil) },
            .copyCurrentPDFPath: { [weak self] in self?.copyCurrentPDFPath(nil) },
            .removeHighlight: { [weak self] in self?.removeHighlightUnderCursorAction(nil) },
            .highlightColorPink: { [weak self] in self?.setHighlightColorPink(nil) },
            .highlightColorYellow: { [weak self] in self?.setHighlightColorYellow(nil) },
            .highlightColorGreen: { [weak self] in self?.setHighlightColorGreen(nil) },
            .toggleLeftSidebar: { [weak self] in self?.toggleLeftSidebar(nil) },
            .toggleRightSidebar: { [weak self] in self?.toggleRightSidebar(nil) },
            .useSidebarTabs: { [weak self] in self?.useSidebarTabs(nil) },
            .useTitlebarTabs: { [weak self] in self?.useTitlebarTabs(nil) },
            .closeCurrentTab: { [weak self] in self?.closeCurrentTab(nil) },
            .closeCurrentWindow: { [weak self] in self?.closeCurrentWindow(nil) },
            .previousTab: { [weak self] in self?.activatePreviousTab(nil) },
            .nextTab: { [weak self] in self?.activateNextTab(nil) },
            .showAllTabs: { [weak self] in self?.showAllTabs(nil) },
            .toggleContinuousReading: { [weak self] in self?.toggleContinuousReading(nil) },
            .fitHeight: { [weak self] in self?.fitReaderToHeight(nil) },
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
            .findAllOpen: { [weak self] in self?.findInAllOpenDocuments(nil) },
            .findNextMatch: { [weak self] in self?.findNextMatchAction(nil) },
            .findPreviousMatch: { [weak self] in self?.findPreviousMatchAction(nil) },
            .gotoPage: { [weak self] in self?.showGotoPageDialog(nil) },
            .showRecentFilesPalette: { [weak self] in self?.showRecentFilesPalette(nil) },
            .openContainingFolder: { [weak self] in self?.openContainingFolder(nil) },
            .reopenLastClosed: { [weak self] in self?.reopenLastClosed(nil) },
            .newBlankTab: { [weak self] in self?.newBlankTab(nil) },
            .newWindow: { [weak self] in self?.newWindow(nil) },
            .mergeAllWindows: { [weak self] in self?.mergeAllWindows(nil) },
            .moveCurrentPDFToNewWindow: { [weak self] in self?.moveCurrentPDFToNewWindow(nil) },
            .toggleAllPagesOverview: { [weak self] in self?.toggleAllPagesOverview(nil) },
            .toggleDemoMode: { [weak self] in self?.toggleDemoModeAction(nil) },
            .toggleImmersiveMode: { [weak self] in self?.toggleImmersiveModeAction(nil) },
            .toggleReaderSplit: { [weak self] in self?.toggleReaderSplitAction(nil) },
            .toggleRightSidebarMode: { [weak self] in self?.toggleRightSidebarModeAction(nil) },
            .swapSidebars: { [weak self] in self?.swapSidebarsAction(nil) },
            .undoLastHighlight: { [weak self] in self?.undoLastHighlightAction(nil) },
            .redoLastHighlight: { [weak self] in self?.redoLastHighlightAction(nil) },
        ]
    }

    private func supplementalShortcutHandlerMap() -> [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] {
        [
            .singlePageContinuous: { [weak self] in self?.toggleSinglePageContinuous(nil) },
        ]
    }

    private func makeWindowController(windowID: UUID) -> MainWindowController {
        if let existing = mainWindowControllers[windowID] {
            return existing
        }

        let controller = MainWindowController(documentStore: documentStore, windowID: windowID)
        controller.refreshThemeAppearance()
        controller.shouldCloseHandler = { [weak self] controller in
            self?.handleWindowShouldClose(controller) ?? true
        }
        controller.didCloseHandler = { [weak self] controller in
            self?.handleWindowDidClose(controller)
        }
        controller.installPlainShortcutHandler { [weak self] event, window in
            guard let self,
                  let readerShortcutsController = self.readerShortcutsController else { return false }
            return readerShortcutsController.handleShortcutEvent(for: event, in: window)
        }
        controller.installSidebarRecentOpenHandler { [weak self] url, windowID in
            self?.openRecentDocuments([url], preferredWindowID: windowID)
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
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = "Open one or more PDF files or folders."

        guard panel.runModal() == .OK else { return }

        do {
            try openResolvedDocumentURLs(panel.urls, in: targetWindowID)
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
        let appMenuItem = NSMenuItem(title: "Serein", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsWindow(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        let librarySettingsItem = makeConfiguredMenuItem(
            title: ShortcutCommand.openLibrarySettings.menuTitle,
            command: .openLibrarySettings,
            action: #selector(openLibrarySettings(_:))
        )
        let shortcutSettingsItem = makeConfiguredMenuItem(
            title: ShortcutCommand.openShortcutSettings.menuTitle,
            command: .openShortcutSettings,
            action: #selector(openShortcutSettings(_:))
        )
        appMenu.addItem(settingsItem)
        appMenu.addItem(librarySettingsItem)
        appMenu.addItem(shortcutSettingsItem)
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: "Hide Serein",
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
            withTitle: "Quit Serein",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func buildFileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = managedMenu(title: "File")
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsWindow(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        let newWindowItem = makeConfiguredMenuItem(
            title: ShortcutCommand.newWindow.menuTitle,
            command: .newWindow,
            action: #selector(newWindow(_:))
        )
        let newBlankTabItem = makeConfiguredMenuItem(
            title: ShortcutCommand.newBlankTab.menuTitle,
            command: .newBlankTab,
            action: #selector(newBlankTab(_:))
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
        let openLibraryItem = makeConfiguredMenuItem(
            title: ShortcutCommand.openLibraryPDF.menuTitle,
            command: .openLibraryPDF,
            action: #selector(showLibraryPalette(_:))
        )
        let refreshLibraryItem = makeConfiguredMenuItem(
            title: ShortcutCommand.refreshLibraryIndex.menuTitle,
            command: .refreshLibraryIndex,
            action: #selector(refreshLibraryIndex(_:))
        )
        let openContainingFolderItem = makeConfiguredMenuItem(
            title: ShortcutCommand.openContainingFolder.menuTitle,
            command: .openContainingFolder,
            action: #selector(openContainingFolder(_:))
        )
        let copyCurrentPDFPathItem = makeConfiguredMenuItem(
            title: ShortcutCommand.copyCurrentPDFPath.menuTitle,
            command: .copyCurrentPDFPath,
            action: #selector(copyCurrentPDFPath(_:))
        )
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(findInCurrentDocument(_:)),
            keyEquivalent: "f"
        )
        let findAllOpenItem = makeConfiguredMenuItem(
            title: ShortcutCommand.findAllOpen.menuTitle,
            command: .findAllOpen,
            action: #selector(findInAllOpenDocuments(_:))
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
        let closeWindowItem = makeConfiguredMenuItem(
            title: ShortcutCommand.closeCurrentWindow.menuTitle,
            command: .closeCurrentWindow,
            action: #selector(closeCurrentWindow(_:))
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
            newBlankTabItem,
            newWindowItem,
            openItem,
            quickOpenRecentItem,
            openLibraryItem,
            refreshLibraryItem,
            openContainingFolderItem,
            copyCurrentPDFPathItem,
            recentItem,
            reopenClosedItem,
            findItem,
            findAllOpenItem,
            findNextItem,
            findPreviousItem,
            saveAnnotationsItem,
            exportHighlightsItem,
            copyHighlightsMarkdownItem,
            .separator(),
            closeItem,
            closeWindowItem,
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
        let tabsMenu = managedMenu(title: "Tabs")

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
            makeConfiguredMenuItem(
                title: ShortcutCommand.showAllTabs.menuTitle,
                command: .showAllTabs,
                action: #selector(showAllTabs(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleContinuousReading.menuTitle,
                command: .toggleContinuousReading,
                action: #selector(toggleContinuousReading(_:))
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
        let annotateMenu = managedMenu(title: "Annotate")

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
        let viewMenu = managedMenu(title: "View")

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
            makeConfiguredMenuItem(
                title: ShortcutCommand.switchCurrentTheme.menuTitle,
                command: .switchCurrentTheme,
                action: #selector(switchCurrentTheme(_:))
            ),
            .separator(),
            makeConfiguredMenuItem(
                title: "Fit Width",
                command: .fitWidth,
                action: #selector(fitReaderToWidth(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.fitHeight.menuTitle,
                command: .fitHeight,
                action: #selector(fitReaderToHeight(_:))
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
                title: ShortcutCommand.toggleDemoMode.menuTitle,
                command: .toggleDemoMode,
                action: #selector(toggleDemoModeAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleImmersiveMode.menuTitle,
                command: .toggleImmersiveMode,
                action: #selector(toggleImmersiveModeAction(_:))
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
        let navigateMenu = managedMenu(title: "Navigate")

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
        let mergeAllWindowsItem = makeConfiguredMenuItem(
            title: ShortcutCommand.mergeAllWindows.menuTitle,
            command: .mergeAllWindows,
            action: #selector(mergeAllWindows(_:))
        )
        let moveCurrentPDFItem = makeConfiguredMenuItem(
            title: ShortcutCommand.moveCurrentPDFToNewWindow.menuTitle,
            command: .moveCurrentPDFToNewWindow,
            action: #selector(moveCurrentPDFToNewWindow(_:))
        )

        windowMenu.items = [
            minimizeItem,
            zoomItem,
            .separator(),
            mergeAllWindowsItem,
            moveCurrentPDFItem,
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
        let item = NSMenuItem(title: menuTitle(title, for: command), action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = command

        if let shortcut = appConfiguration.shortcuts.bindings[command] {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
    }

    private func managedMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    private func menuTitle(_ title: String, for command: ShortcutCommand) -> String {
        guard appConfiguration.shortcuts.bindings[command] == nil,
              let builtInChordDisplay = command.builtInChordDisplay else { return title }
        return "\(title) (\(builtInChordDisplay))"
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
    private func closeCurrentWindow(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performClose(sender)
            return
        }
        mainWindowController?.window?.performClose(sender)
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
    private func newBlankTab(_ sender: Any?) {
        let controller: MainWindowController
        if let currentController = mainWindowController {
            controller = currentController
        } else {
            let windowID = documentStore.defaultWindowID
            controller = makeWindowController(windowID: windowID)
            controller.showWindow(sender)
        }

        controller.hideFindBar()
        documentStore.newBlankTab(in: controller.windowID)
        controller.window?.makeKeyAndOrderFront(sender)
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
    private func mergeAllWindows(_ sender: Any?) {
        guard let targetController = mainWindowController else { return }
        let closingControllers = mainWindowControllers.values.filter { $0.windowID != targetController.windowID }
        guard closingControllers.isEmpty == false else { return }

        documentStore.mergeAllWindows(into: targetController.windowID)
        for controller in closingControllers {
            controller.window?.performClose(sender)
        }
        targetController.window?.makeKeyAndOrderFront(sender)
    }

    @objc
    private func moveCurrentPDFToNewWindow(_ sender: Any?) {
        guard let sourceController = mainWindowController,
              let windowID = documentStore.moveActiveSessionToNewWindow(from: sourceController.windowID) else { return }
        let controller = makeWindowController(windowID: windowID)
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }

    @objc
    private func showRecentFilesPalette(_ sender: Any?) {
        runRecentFilesCleanupIfNeeded()
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
    private func showLibraryPalette(_ sender: Any?) {
        guard appConfiguration.library.folderURLs.isEmpty == false else {
            presentLibraryMessage(
                title: "No PDF library folders",
                message: "Add folders in Settings > Library, then use Cmd+K, Cmd+O again."
            )
            return
        }

        if libraryPaletteController == nil {
            libraryPaletteController = PDFLibraryPaletteController { [weak self] url in
                self?.openRecentDocuments([url])
            }
        }
        libraryPaletteController?.show(
            folderURLs: appConfiguration.library.folderURLs,
            relativeTo: mainWindowController?.window
        )
    }

    @objc
    private func refreshLibraryIndex(_ sender: Any?) {
        libraryPaletteController?.invalidateCatalogCache()
        showLibraryPalette(sender)
    }

    @objc
    private func showAllTabs(_ sender: Any?) {
        if openTabsPaletteController?.window?.isVisible == true {
            closeOpenTabsPalette()
            return
        }
        guard let controller = mainWindowController else { return }
        let sessions = documentStore.sessions(in: controller.windowID)
        guard sessions.isEmpty == false else { return }
        openTabsPaletteWindowID = controller.windowID

        if openTabsPaletteController == nil {
            openTabsPaletteController = OpenTabsPaletteController { [weak self] sessionID, alternatePane in
                guard let self,
                      let windowID = self.openTabsPaletteWindowID else { return }
                self.documentStore.clearSearch(in: windowID)
                let focusedPane = self.documentStore.focusedPane(in: windowID)
                let targetPane = alternatePane
                    ? (self.documentStore.isSplitEnabled(in: windowID) ? focusedPane : focusedPane.other)
                    : nil
                self.documentStore.activate(sessionID: sessionID, in: windowID, targetPane: targetPane)
            }
        }
        openTabsPaletteController?.show(
            with: sessions,
            activeSessionID: documentStore.activeSessionID(in: controller.windowID),
            primarySessionID: documentStore.displayedSessionID(for: .primary, in: controller.windowID),
            secondarySessionID: documentStore.displayedSessionID(for: .secondary, in: controller.windowID),
            focusedPane: documentStore.focusedPane(in: controller.windowID),
            relativeTo: controller.window
        )
    }

    private func closeOpenTabsPalette() {
        openTabsPaletteController?.close()
        openTabsPaletteWindowID = nil
    }

    @objc
    private func toggleContinuousReading(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        _ = documentStore.toggleContinuousReadingFromSelection(in: controller.windowID)
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
    private func toggleDemoModeAction(_ sender: Any?) {
        mainWindowController?.toggleDemoMode()
    }

    @objc
    private func toggleImmersiveModeAction(_ sender: Any?) {
        mainWindowController?.toggleImmersiveMode()
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
        let currentIsDark = (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        var updatedConfiguration = appConfiguration
        updatedConfiguration.appearance.mode = appConfiguration.appearance.mode.toggled(currentIsDark: currentIsDark)
        applyUpdatedConfiguration(updatedConfiguration)
    }

    @objc
    private func switchCurrentTheme(_ sender: Any?) {
        let currentIsDark = (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        var updatedConfiguration = appConfiguration
        if currentIsDark {
            updatedConfiguration.appearance.darkTheme = appConfiguration.appearance.darkTheme.toggled
        } else {
            updatedConfiguration.appearance.lightTheme = appConfiguration.appearance.lightTheme.toggled
        }
        applyUpdatedConfiguration(updatedConfiguration)
    }

    @objc
    private func fitReaderToWidth(_ sender: Any?) {
        mainWindowController?.fitReaderToWidth()
    }

    @objc
    private func fitReaderToHeight(_ sender: Any?) {
        mainWindowController?.fitReaderToHeight()
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
        alert.window.initialFirstResponder = field
        field.target = alert.buttons.first
        field.action = #selector(NSButton.performClick(_:))
        field.selectText(nil)

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
    private func toggleSinglePageContinuous(_ sender: Any?) {
        guard let controller = mainWindowController,
              let sessionID = documentStore.activeSessionID(in: controller.windowID) else { return }
        documentStore.toggleSinglePageContinuous(for: sessionID)
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

    @objc
    private func copyCurrentPDFPath(_ sender: Any?) {
        guard let windowID = mainWindowController?.windowID ?? mainWindowControllers.values.first?.windowID,
              let activeSession = documentStore.activeSession(in: windowID),
              activeSession.isBlank == false else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(activeSession.url.path, forType: .string)
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
        mainWindowController?.showFindBar(scope: .currentDocument)
    }

    @objc
    private func findInAllOpenDocuments(_ sender: Any?) {
        guard let controller = mainWindowController,
              documentStore.activeSession(in: controller.windowID) != nil else { return }
        mainWindowController?.showFindBar(scope: .allOpen)
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

    @objc
    private func openContainingFolder(_ sender: Any?) {
        guard let windowID = mainWindowController?.windowID ?? mainWindowControllers.values.first?.windowID,
              let activeSession = documentStore.activeSession(in: windowID),
              activeSession.isBlank == false else { return }
        let activeURL = activeSession.url
        NSWorkspace.shared.activateFileViewerSelecting([activeURL])
    }

    private func openResolvedDocumentURLs(_ urls: [URL], in targetWindowID: UUID) throws {
        let resolvedURLs = try openDocumentSelectionResolver.resolve(urls)
        _ = try documentStore.open(documentsAt: resolvedURLs, in: targetWindowID)
    }

    private func openRecentDocuments(_ urls: [URL], preferredWindowID: UUID? = nil) {
        guard urls.isEmpty == false else { return }
        mainWindowController?.hideFindBar()
        let targetWindowID = preferredWindowID
            .flatMap { documentStore.windowWorkspace(for: $0)?.id }
            ?? mainWindowController?.windowID
            ?? documentStore.defaultWindowID

        do {
            _ = try documentStore.open(documentsAt: urls, in: targetWindowID)
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
    private func openSettingsWindow(_ sender: Any?) {
        openSettingsWindow(sender, selecting: nil)
    }

    @objc
    private func openLibrarySettings(_ sender: Any?) {
        openSettingsWindow(sender, selecting: .library)
    }

    @objc
    private func openShortcutSettings(_ sender: Any?) {
        openSettingsWindow(sender, selecting: .shortcuts)
    }

    private func openSettingsWindow(_ sender: Any?, selecting page: SettingsPage?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configuration: appConfiguration,
                onConfigurationChanged: { [weak self] configuration in
                    self?.applyUpdatedConfiguration(configuration)
                }
            )
        }

        settingsWindowController?.sync(configuration: appConfiguration)
        if let page {
            settingsWindowController?.selectPage(page)
        }
        settingsWindowController?.window?.appearance = appConfiguration.appearance.mode.appAppearance
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyUpdatedConfiguration(_ configuration: AppConfiguration) {
        guard let configStore else { return }
        let previousConfiguration = appConfiguration
        var newConfiguration = configuration
        let libraryFoldersChanged = previousConfiguration.library.folderURLs != newConfiguration.library.folderURLs
        newConfiguration.access = securityScopedAccessController.sync(access: newConfiguration.access)

        if previousConfiguration.layout.sidebarsSwapped != newConfiguration.layout.sidebarsSwapped {
            swap(&newConfiguration.layout.leftSidebarWidth, &newConfiguration.layout.rightSidebarWidth)
            swap(&newConfiguration.layout.leftSidebarMinWidth, &newConfiguration.layout.rightSidebarMinWidth)
            swap(&newConfiguration.layout.leftSidebarMaxWidth, &newConfiguration.layout.rightSidebarMaxWidth)
        }

        do {
            try configStore.save(newConfiguration)
            appConfiguration = newConfiguration
            applyApplicationAppearance()
            refreshMenuShortcuts()
            documentStore.updateAppConfiguration(newConfiguration)
            if libraryFoldersChanged {
                libraryPaletteController?.invalidateCatalogCache()
            }
        } catch {
            appConfiguration = previousConfiguration
            applyApplicationAppearance()
            refreshMenuShortcuts()
            documentStore.updateAppConfiguration(previousConfiguration)
            settingsWindowController?.sync(configuration: previousConfiguration)
            presentConfigurationSaveError(error)
        }
    }

    private func applyApplicationAppearance() {
        NightModeStyle.applyThemeSelections(
            light: appConfiguration.appearance.lightTheme,
            dark: appConfiguration.appearance.darkTheme
        )
        NSApp.appearance = appConfiguration.appearance.mode.appAppearance
        mainWindowControllers.values.forEach { $0.refreshThemeAppearance() }
        settingsWindowController?.window?.appearance = appConfiguration.appearance.mode.appAppearance
    }

    private func refreshThemeChromeIfFollowingSystem() {
        guard appConfiguration.appearance.mode == .system else { return }
        mainWindowControllers.values.forEach { $0.refreshThemeAppearance() }
        settingsWindowController?.window?.appearance = nil
    }

    private func refreshMenuShortcuts() {
        guard let menu = NSApp.mainMenu else { return }
        refreshMenuShortcuts(in: menu)
        refreshManagedMenuState(in: menu)
    }

    private func refreshMenuShortcuts(in menu: NSMenu) {
        for item in menu.items {
            if let command = item.representedObject as? ShortcutCommand {
                item.title = menuTitle(command.menuTitle, for: command)
                if let shortcut = appConfiguration.shortcuts.bindings[command] {
                    item.keyEquivalent = shortcut.menuKeyEquivalent
                    item.keyEquivalentModifierMask = shortcut.modifierMask
                } else {
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                }
            }

            if let submenu = item.submenu {
                refreshMenuShortcuts(in: submenu)
            }
        }
    }

    private func refreshManagedMenuState() {
        guard let menu = NSApp.mainMenu else { return }
        refreshManagedMenuState(in: menu)
    }

    private func refreshManagedMenuState(in menu: NSMenu) {
        for item in menu.items {
            if let target = item.target, target === self {
                item.isEnabled = validateMenuItem(item)
            }

            if let submenu = item.submenu {
                refreshManagedMenuState(in: submenu)
            }
        }
    }

    private func presentOpenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to open documents"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentConfigurationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Failed to load Serein config"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func presentConfigurationSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to save Serein settings"
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

    private func presentLibraryMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
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
        let activePDFSession = activeSession?.isBlank == false ? activeSession : nil

        switch menuItem.action {
        case #selector(newBlankTab(_:)):
            return true
        case #selector(newWindow(_:)):
            return true
        case #selector(mergeAllWindows(_:)):
            return mainWindowControllers.count > 1
        case #selector(moveCurrentPDFToNewWindow(_:)):
            return activePDFSession != nil
        case #selector(refreshLibraryIndex(_:)), #selector(showLibraryPalette(_:)):
            return appConfiguration.library.folderURLs.isEmpty == false
        case #selector(openLibrarySettings(_:)), #selector(openShortcutSettings(_:)):
            return true
        case #selector(highlightSelection(_:)):
            return activePDFSession != nil
        case #selector(exitHighlightMode(_:)):
            menuItem.state = controller?.isHighlightModeEnabled == true ? .on : .off
            return controller?.isHighlightModeEnabled == true
        case #selector(toggleNightMode(_:)):
            menuItem.state = controller?.isNightModeEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(saveAnnotations(_:)):
            return activePDFSession?.isDirty == true
        case #selector(exportHighlights(_:)), #selector(copyHighlightsMarkdown(_:)):
            return activePDFSession.map { documentStore.hasHighlights(for: $0.id) } == true
        case #selector(removeHighlightUnderCursorAction(_:)):
            return activePDFSession != nil
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
        case #selector(findInCurrentDocument(_:)), #selector(findInAllOpenDocuments(_:)):
            return activePDFSession != nil
        case #selector(showRecentFilesPalette(_:)):
            return documentStore.recentDocumentURLs.isEmpty == false
        case #selector(showAllTabs(_:)):
            return windowID.map { documentStore.sessions(in: $0).isEmpty == false } == true
        case #selector(toggleContinuousReading(_:)):
            if let windowID {
                menuItem.state = documentStore.isContinuousReadingEnabled(in: windowID) ? .on : .off
                return documentStore.isContinuousReadingEnabled(in: windowID)
                    || documentStore.selectedSessionIDs(in: windowID).count > 1
            }
            return false
        case #selector(openContainingFolder(_:)), #selector(copyCurrentPDFPath(_:)):
            return activePDFSession != nil
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
            if let windowID,
               documentStore.selectedSessionIDs(in: windowID).count > 1 {
                menuItem.title = menuTitle("Close Selected Tabs", for: .closeCurrentTab)
            } else {
                menuItem.title = menuTitle("Close Current Tab", for: .closeCurrentTab)
            }
            return controller != nil
        case #selector(closeCurrentWindow(_:)):
            return NSApp.keyWindow != nil || controller != nil
        case #selector(activatePreviousTab(_:)), #selector(activateNextTab(_:)):
            return windowID.map { documentStore.sessionCount(in: $0) > 1 } == true
        case #selector(fitReaderToWidth(_:)):
            menuItem.state = activePDFSession?.scaleMode == .fitWidth ? .on : .off
            return activePDFSession != nil
        case #selector(fitReaderToHeight(_:)):
            menuItem.state = activePDFSession?.scaleMode == .fitHeight ? .on : .off
            return activePDFSession != nil
        case #selector(zoomInReader(_:)), #selector(zoomOutReader(_:)):
            return activePDFSession != nil
        case #selector(goToNextPageAction(_:)),
             #selector(goToPreviousPageAction(_:)),
             #selector(scrollHalfPageDownAction(_:)),
             #selector(scrollHalfPageUpAction(_:)):
            return activePDFSession != nil
        case #selector(goToFirstPageAction(_:)), #selector(goToLastPageAction(_:)):
            return activePDFSession != nil && (controller?.currentPageCount ?? 0) > 0
        case #selector(navigateBackAction(_:)):
            return controller?.canGoBack == true
        case #selector(navigateForwardAction(_:)):
            return controller?.canGoForward == true
        case #selector(showGotoPageDialog(_:)):
            return activePDFSession != nil && (controller?.currentPageCount ?? 0) > 0
        case #selector(reopenLastClosed(_:)):
            return windowID.map { documentStore.recentlyClosedURLs(in: $0).isEmpty == false } == true
        case #selector(toggleAllPagesOverview(_:)):
            menuItem.state = controller?.isAllPagesOverviewActive == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleDemoModeAction(_:)):
            menuItem.state = controller?.isDemoModeEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleImmersiveModeAction(_:)):
            menuItem.state = controller?.isImmersiveModeEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleReaderSplitAction(_:)):
            menuItem.state = controller?.isReaderSplitEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleRightSidebarModeAction(_:)):
            return windowID.map { documentStore.isRightSidebarVisible(in: $0) } == true
        case #selector(swapSidebarsAction(_:)):
            return true
        case #selector(useSinglePage(_:)):
            menuItem.state = activePDFSession?.displayMode == .singlePage ? .on : .off
            return activePDFSession != nil
        case #selector(useSinglePageContinuous(_:)):
            menuItem.state = activePDFSession?.displayMode == .singlePageContinuous ? .on : .off
            return activePDFSession != nil
        case #selector(useTwoUp(_:)):
            menuItem.state = activePDFSession?.displayMode == .twoUp ? .on : .off
            return activePDFSession != nil
        case #selector(useTwoUpContinuous(_:)):
            menuItem.state = activePDFSession?.displayMode == .twoUpContinuous ? .on : .off
            return activePDFSession != nil
        default:
            return true
        }
    }
}
