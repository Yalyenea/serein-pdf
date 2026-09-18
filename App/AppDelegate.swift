import AppKit
import UniformTypeIdentifiers

private enum SharePayloadKind: Int, CaseIterable {
    case originalPDF
    case cleanPDFCopy
    case highlightsMarkdown

    var title: String {
        switch self {
        case .originalPDF:
            "Original PDF"
        case .cleanPDFCopy:
            "Clean PDF Copy"
        case .highlightsMarkdown:
            "Highlights Markdown"
        }
    }
}

private enum ShareDocumentError: Error, LocalizedError {
    case noHighlights
    case missingShareAnchor

    var errorDescription: String? {
        switch self {
        case .noHighlights:
            "The current PDF has no highlights to share."
        case .missingShareAnchor:
            "Unable to find a window for the share picker."
        }
    }
}

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
    private(set) var temporaryAppearanceMode: AppearanceMode?
    private var readerShortcutsController: ReaderShortcutsController?
    private var commandPaletteController: CommandPaletteController?
    private var recentFilesPaletteController: RecentFilesPaletteController?
    private var libraryPaletteController: PDFLibraryPaletteController?
    private var openTabsPaletteController: OpenTabsPaletteController?
    private var openTabsPaletteWindowID: UUID?
    private var sharingServicePicker: NSSharingServicePicker?
    private var temporaryShareDirectories: [URL] = []
    private let recentFilesMenu = NSMenu(title: "Open Recent")
    private var displayedRecentDocumentURLs: [URL]?
    private let windowMenu = NSMenu(title: "Window")
    private let moveCurrentPDFToWindowMenu = NSMenu(title: "Move Current PDF to Window")
    private let moveCurrentPDFToWindowItem = NSMenuItem(
        title: "Move Current PDF to Window",
        action: nil,
        keyEquivalent: ""
    )
    private let sendToCodexMenu = NSMenu(title: "Send to Codex")
    private let sendToCodexItem = NSMenuItem(title: "Send to Codex", action: nil, keyEquivalent: "")
    private let openWithMenu = NSMenu(title: "Open With")
    private let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
    private var autoSaveTimer: Timer?
    private var isAutoSaveRunning = false
    private var lastRecentFilesCleanupDate: Date?
    private var reportedAutoSaveFailureURLs: Set<URL> = []
    private var pendingOpenURLs: [URL] = []
    private let sereinOpenURLResolver = SereinOpenURLResolver()
    private let openDocumentSelectionResolver = OpenDocumentSelectionResolver()
    private let securityScopedAccessController = SecurityScopedAccessController()
    private let codexShareCoordinator = CodexShareCoordinator()
    private let externalApplicationService = ExternalApplicationService()
    private var cachedShortcutHandlerMap: [ShortcutCommand: ReaderShortcutsController.ShortcutHandler]?
    private struct CommandWindowContext {
        let windowID: UUID?
    }
    private var commandWindowContext: CommandWindowContext?
    private var appUpdateCoordinator: AppUpdateCoordinator?
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
        documentStore.noteRecentDocumentURL = { url in
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        try? documentStore.restorePersistedState()
        installMainMenu()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshThemeChromeIfFollowingSystem()
            }
        }
        observeMenuStateChanges()
        readerShortcutsController = ReaderShortcutsController(
            shortcutsProvider: { [weak self] in
                self?.appConfiguration.shortcuts.bindings ?? [:]
            },
            handlerProvider: { [weak self] in
                self?.shortcutHandlerMap() ?? [:]
            },
            isAnnotationModeEnabledProvider: { [weak self] window in
                guard let self else { return false }
                return self.mainWindowControllers.values.first {
                    $0.window === window
                }?.isAnnotationModeEnabled == true
            },
            bookPageTurnHandler: { [weak self] direction, window in
                guard let self,
                      let entry = self.mainWindowControllers.first(where: { $0.value.window === window }),
                      self.documentStore.activeSession(in: entry.key)?.displayMode.usesBookLayout == true else {
                    return false
                }
                if direction < 0 {
                    entry.value.goToPreviousPage()
                } else {
                    entry.value.goToNextPage()
                }
                return true
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

        appUpdateCoordinator = AppUpdateCoordinator(
            tokenProvider: { [weak self] in
                guard let self else { return nil }
                let configToken = self.appConfiguration.updates.githubToken
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if configToken.isEmpty == false {
                    return configToken
                }
                if let env = ProcessInfo.processInfo.environment["SEREIN_GITHUB_TOKEN"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   env.isEmpty == false {
                    return env
                }
                if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   env.isEmpty == false {
                    return env
                }
                return nil
            },
            autoCheckEnabledProvider: { [weak self] in
                self?.appConfiguration.updates.autoCheck ?? true
            }
        )
        appUpdateCoordinator?.scheduleLaunchCheck()
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
        runRecentFilesCleanupIfNeeded()
        guard isAutoSaveRunning == false else { return }
        let prepared = documentStore.prepareAutoSaveJobs()
        reportAutoSaveErrors(prepared.errors)
        guard prepared.jobs.isEmpty == false else { return }

        isAutoSaveRunning = true
        Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                DocumentStore.performAutoSaveJobs(prepared.jobs)
            }.value
            guard let self else { return }
            self.isAutoSaveRunning = false
            self.reportAutoSaveErrors(self.documentStore.completeAutoSave(results))
        }
    }

    private func reportAutoSaveErrors(_ errors: [URL: Error]) {
        if errors.isEmpty == false {
            let freshErrors = errors.filter { reportedAutoSaveFailureURLs.contains($0.key) == false }
            if freshErrors.isEmpty == false {
                reportedAutoSaveFailureURLs.formUnion(freshErrors.keys)
                presentAutoSaveErrors(freshErrors)
                NSLog("Serein auto-save failed for: %@", errors.keys.map(\.lastPathComponent).joined(separator: ", "))
            }
        }
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
        commandPaletteController?.dismiss(restoreParent: false)
        recentFilesPaletteController?.close()
        libraryPaletteController?.close()
        closeOpenTabsPalette()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowControllers.values.forEach { $0.flushPendingReadingPositions() }
        documentStore?.flushPersistence()
        cleanupTemporaryShareDirectories()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard (currentWindowController() ?? mainWindowControllers.values.first)?.prepareForApplicationTermination() != false else {
            return .terminateCancel
        }
        do {
            try appUpdateCoordinator?.installPendingUpdate()
            return .terminateNow
        } catch {
            sender.presentError(error)
            return .terminateCancel
        }
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
            let documentURLs = try sereinOpenURLResolver.resolve(urls)
            let frontWindowID = try openResolvedDocumentURLs(documentURLs, in: targetWindowID)
            bringWindowToFront(frontWindowID)
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
        guard notification.isLightweightStoreChange == false else { return }
        let change = notification.documentStoreChange
        if change.contains(.annotations) {
            let dirtyURLs = Set(documentStore.sessions.filter(\.isDirty).map(\.url))
            reportedAutoSaveFailureURLs.formIntersection(dirtyURLs)
        }
        if change.contains(.recentFiles) {
            updateRecentFilesMenu()
        }
        refreshManagedMenuState()
    }

    private func observeMenuStateChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange, object: documentStore
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReaderWindowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
    }

    @objc
    private func handleReaderWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              controller(for: window) != nil else { return }
        refreshManagedMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === windowMenu || menu === moveCurrentPDFToWindowMenu {
            rebuildMoveCurrentPDFToWindowMenu()
        }
        if menu === openWithMenu {
            rebuildOpenWithMenu()
        }
        openWithItem.isEnabled = currentPublicPDFSession() != nil
        refreshManagedMenuState(in: menu)
    }

    private func shortcutHandlerMap() -> [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] {
        if let cachedShortcutHandlerMap {
            return cachedShortcutHandlerMap
        }
        var map: [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] = [
            .addComment: { [weak self] in self?.addOrEditComment(nil) },
            .exitHighlightMode: { [weak self] in self?.exitHighlightMode(nil) },
            .toggleNightMode: { [weak self] in self?.toggleNightMode(nil) },
            .toggleReadingFocus: { [weak self] in self?.toggleReadingFocusModeAction(nil) },
            .adjustReadingFocus: { [weak self] in self?.showReadingFocusControlsAction(nil) },
            .toggleHorizontalPanLock: { [weak self] in self?.toggleHorizontalPanLockAction(nil) },
            .switchCurrentTheme: { [weak self] in self?.switchCurrentTheme(nil) },
            .openLibraryPDF: { [weak self] in self?.showLibraryPalette(nil) },
            .refreshLibraryIndex: { [weak self] in self?.refreshLibraryIndex(nil) },
            .openLibrarySettings: { [weak self] in self?.openLibrarySettings(nil) },
            .openShortcutSettings: { [weak self] in self?.openShortcutSettings(nil) },
            .saveAnnotations: { [weak self] in self?.saveAnnotations(nil) },
            .shareDocument: { [weak self] in self?.shareDocument(nil) },
            .exportCleanCopy: { [weak self] in self?.exportCleanCopy(nil) },
            .copyHighlightsMarkdown: { [weak self] in self?.copyHighlightsMarkdown(nil) },
            .copyCurrentPDFPath: { [weak self] in self?.copyCurrentPDFPath(nil) },
            .copyCurrentPageAsImage: { [weak self] in self?.copyCurrentPageAsImage(nil) },
            .sendContextToCodex: { [weak self] in self?.sendContextToCodex(nil) },
            .sendCurrentPDFToCodex: { [weak self] in self?.sendCurrentPDFToCodex(nil) },
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
            .fitTextWidth: { [weak self] in self?.fitReaderToTextWidth(nil) },
            .zoomIn: { [weak self] in self?.zoomInReader(nil) },
            .zoomOut: { [weak self] in self?.zoomOutReader(nil) },
            .singlePage: { [weak self] in self?.useSinglePage(nil) },
            .singlePageContinuous: { [weak self] in self?.useSinglePageContinuous(nil) },
            .twoUp: { [weak self] in self?.useTwoUp(nil) },
            .twoUpContinuous: { [weak self] in self?.useTwoUpContinuous(nil) },
            .book: { [weak self] in self?.useBook(nil) },
            .bookContinuous: { [weak self] in self?.useBookContinuous(nil) },
            .toggleDisplayModeContinuity: { [weak self] in self?.toggleDisplayModeContinuity(nil) },
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
        for command in ShortcutCommand.allCases where command.annotationMarkupType != nil {
            map[command] = { [weak self] in self?.applyAnnotationCommand(command) }
        }
        cachedShortcutHandlerMap = map
        return map
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
        controller.installReaderOpenURLsHandler { [weak self] urls, windowID in
            self?.openDroppedDocuments(urls, preferredWindowID: windowID)
        }
        controller.installCodexShareHandlers(
            selectionHandler: { [weak self] text, _ in
                self?.openTextInCodex(text)
            },
            pageImageHandler: { [weak self] image, pageNumber, windowID in
                self?.openPageImageInCodex(image, pageNumber: pageNumber, windowID: windowID)
            }
        )
        controller.installOpenWithMenuProvider { [weak self] sessionID, windowID in
            self?.makeOpenWithMenu(for: sessionID, in: windowID)
        }
        controller.installRevealInFinderHandler { [weak self] sessionID, windowID in
            self?.revealPDFInFinder(for: sessionID, in: windowID)
        }
        mainWindowControllers[windowID] = controller
        return controller
    }

    private func currentWindowController() -> MainWindowController? {
        if let commandWindowContext {
            return commandWindowContext.windowID.flatMap { mainWindowControllers[$0] }
        }
        if let keyWindow = NSApp.keyWindow,
           let controller = controller(for: keyWindow) {
            return controller
        }
        if let mainWindow = NSApp.mainWindow,
           let controller = controller(for: mainWindow) {
            return controller
        }
        return NSApp.orderedWindows.lazy.compactMap { self.controller(for: $0) }.first
    }

    private func withCommandWindowContext<Result>(
        _ windowID: UUID?,
        perform action: () -> Result
    ) -> Result {
        let previousContext = commandWindowContext
        commandWindowContext = CommandWindowContext(windowID: windowID)
        defer { commandWindowContext = previousContext }
        return action()
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

    private func bringWindowToFront(_ windowID: UUID?) {
        guard let windowID else { return }
        let controller = makeWindowController(windowID: windowID)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc
    func openDocument(_ sender: Any?) {
        mainWindowController?.hideFindBar()
        let targetWindowID = mainWindowController?.windowID ?? documentStore.defaultWindowID
        presentOpenPanel(preferredWindowID: targetWindowID)
    }

    private func presentOpenPanel(preferredWindowID targetWindowID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = "Open one or more PDF files or folders."

        guard panel.runModal() == .OK else { return }

        do {
            let frontWindowID = try openResolvedDocumentURLs(panel.urls, in: targetWindowID)
            bringWindowToFront(frontWindowID)
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
        let commandPaletteItem = NSMenuItem(
            title: "Command Palette…",
            action: #selector(showCommandPalette(_:)),
            keyEquivalent: ShortcutCommand.commandPaletteShortcut.menuKeyEquivalent
        )
        commandPaletteItem.keyEquivalentModifierMask = ShortcutCommand.commandPaletteShortcut.modifierMask
        commandPaletteItem.target = self
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
        appMenu.addItem(commandPaletteItem)
        appMenu.addItem(librarySettingsItem)
        appMenu.addItem(shortcutSettingsItem)
        appMenu.addItem(.separator())
        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        appMenu.addItem(checkUpdatesItem)
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
        let copyCurrentPageAsImageItem = makeConfiguredMenuItem(
            title: ShortcutCommand.copyCurrentPageAsImage.menuTitle,
            command: .copyCurrentPageAsImage,
            action: #selector(copyCurrentPageAsImage(_:))
        )
        openWithMenu.autoenablesItems = false
        openWithMenu.delegate = self
        openWithItem.submenu = openWithMenu
        let sendContextToCodexItem = makeConfiguredMenuItem(
            title: ShortcutCommand.sendContextToCodex.menuTitle,
            command: .sendContextToCodex,
            action: #selector(sendContextToCodex(_:))
        )
        let sendCurrentPDFToCodexItem = makeConfiguredMenuItem(
            title: ShortcutCommand.sendCurrentPDFToCodex.menuTitle,
            command: .sendCurrentPDFToCodex,
            action: #selector(sendCurrentPDFToCodex(_:))
        )
        sendToCodexMenu.autoenablesItems = false
        sendToCodexMenu.delegate = self
        sendToCodexMenu.items = [
            sendContextToCodexItem,
            sendCurrentPDFToCodexItem,
        ]
        sendToCodexItem.submenu = sendToCodexMenu
        sendToCodexItem.isHidden = appConfiguration.integrations.codexEnabled == false
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
        let shareDocumentItem = makeConfiguredMenuItem(
            title: ShortcutCommand.shareDocument.menuTitle,
            command: .shareDocument,
            action: #selector(shareDocument(_:))
        )
        let exportCleanCopyItem = makeConfiguredMenuItem(
            title: ShortcutCommand.exportCleanCopy.menuTitle,
            command: .exportCleanCopy,
            action: #selector(exportCleanCopy(_:))
        )
        let exportHighlightsItem = NSMenuItem(
            title: "Export Highlights…",
            action: #selector(exportHighlights(_:)),
            keyEquivalent: ""
        )
        exportHighlightsItem.target = self
        let exportAllOpenHighlightsItem = NSMenuItem(
            title: "Export All Open Highlights…",
            action: #selector(exportAllOpenHighlights(_:)),
            keyEquivalent: ""
        )
        exportAllOpenHighlightsItem.target = self
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
            openWithItem,
            copyCurrentPDFPathItem,
            copyCurrentPageAsImageItem,
            recentItem,
            reopenClosedItem,
            findItem,
            findAllOpenItem,
            findNextItem,
            findPreviousItem,
            saveAnnotationsItem,
            shareDocumentItem,
            sendToCodexItem,
            exportCleanCopyItem,
            exportHighlightsItem,
            exportAllOpenHighlightsItem,
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
        let markupItems = ShortcutCommand.allCases.compactMap { command in
            command.annotationMarkupType.map { _ in
                makeConfiguredMenuItem(
                    title: command.menuTitle,
                    command: command,
                    action: #selector(applyAnnotationCommand(_:))
                )
            }
        }

        annotateMenu.items = markupItems + [
            makeConfiguredMenuItem(
                title: ShortcutCommand.addComment.menuTitle,
                command: .addComment,
                action: #selector(addOrEditComment(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.exitHighlightMode.menuTitle,
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
        let sideBySideSplitItem = NSMenuItem(
            title: "Split Left & Right",
            action: #selector(useSideBySideReaderSplit(_:)),
            keyEquivalent: ""
        )
        sideBySideSplitItem.target = self
        let stackedSplitItem = NSMenuItem(
            title: "Split Top & Bottom",
            action: #selector(useStackedReaderSplit(_:)),
            keyEquivalent: ""
        )
        stackedSplitItem.target = self

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
                title: ShortcutCommand.toggleReadingFocus.menuTitle,
                command: .toggleReadingFocus,
                action: #selector(toggleReadingFocusModeAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.adjustReadingFocus.menuTitle,
                command: .adjustReadingFocus,
                action: #selector(showReadingFocusControlsAction(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleHorizontalPanLock.menuTitle,
                command: .toggleHorizontalPanLock,
                action: #selector(toggleHorizontalPanLockAction(_:))
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
                title: ShortcutCommand.fitTextWidth.menuTitle,
                command: .fitTextWidth,
                action: #selector(fitReaderToTextWidth(_:))
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
            .separator(),
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
                title: ReaderDisplayMode.book.menuTitle,
                command: .book,
                action: #selector(useBook(_:))
            ),
            makeConfiguredMenuItem(
                title: ReaderDisplayMode.bookContinuous.menuTitle,
                command: .bookContinuous,
                action: #selector(useBookContinuous(_:))
            ),
            makeConfiguredMenuItem(
                title: ShortcutCommand.toggleDisplayModeContinuity.menuTitle,
                command: .toggleDisplayModeContinuity,
                action: #selector(toggleDisplayModeContinuity(_:))
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
            sideBySideSplitItem,
            stackedSplitItem,
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
        windowMenu.delegate = self
        moveCurrentPDFToWindowMenu.autoenablesItems = false
        moveCurrentPDFToWindowMenu.delegate = self
        moveCurrentPDFToWindowItem.submenu = moveCurrentPDFToWindowMenu
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
            moveCurrentPDFToWindowItem,
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
        guard let builtInChordDisplay = command.builtInChordDisplay else { return title }
        return "\(title) (\(builtInChordDisplay))"
    }

    @objc
    private func closeCurrentTab(_ sender: Any?) {
        if commandWindowContext == nil,
           let keyWindow = NSApp.keyWindow,
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
        if let commandWindowContext {
            if let windowID = commandWindowContext.windowID {
                mainWindowControllers[windowID]?.window?.performClose(sender)
            } else {
                NSApp.keyWindow?.performClose(sender)
            }
            return
        }
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performClose(sender)
            return
        }
        mainWindowController?.window?.performClose(sender)
    }

    @objc
    private func activatePreviousTab(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
        documentStore.activatePreviousSession(in: controller.windowID)
    }

    @objc
    private func activateNextTab(_ sender: Any?) {
        guard let controller = mainWindowController else { return }
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
    private func moveCurrentPDFToExistingWindow(_ sender: NSMenuItem) {
        guard let destinationWindowIDString = sender.representedObject as? String,
              let destinationWindowID = UUID(uuidString: destinationWindowIDString),
              let sourceController = mainWindowController,
              let session = documentStore.activeSession(in: sourceController.windowID),
              session.isBlank == false,
              documentStore.moveSession(
                session.id,
                from: sourceController.windowID,
                to: destinationWindowID
              ) else { return }
        bringWindowToFront(destinationWindowID)
    }

    private func rebuildMoveCurrentPDFToWindowMenu() {
        moveCurrentPDFToWindowMenu.removeAllItems()
        guard let sourceController = mainWindowController,
              let activeSession = documentStore.activeSession(in: sourceController.windowID),
              activeSession.isBlank == false else {
            moveCurrentPDFToWindowItem.isEnabled = false
            addUnavailableWindowMoveItem(title: "No PDF to Move")
            return
        }

        let windowIDs = documentStore.windowIDs()
        let destinations = windowIDs.filter { $0 != sourceController.windowID }
        moveCurrentPDFToWindowItem.isEnabled = destinations.isEmpty == false
        guard destinations.isEmpty == false else {
            addUnavailableWindowMoveItem(title: "No Other Windows")
            return
        }

        for destinationWindowID in destinations {
            let windowNumber = (windowIDs.firstIndex(of: destinationWindowID) ?? 0) + 1
            let destinationTitle = documentStore.activeSession(in: destinationWindowID)
                .flatMap { $0.isBlank ? nil : $0.title }
                ?? "Empty Window"
            let item = NSMenuItem(
                title: "Window \(windowNumber): \(destinationTitle)",
                action: #selector(moveCurrentPDFToExistingWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = destinationWindowID.uuidString
            moveCurrentPDFToWindowMenu.addItem(item)
        }
    }

    private func addUnavailableWindowMoveItem(title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        moveCurrentPDFToWindowMenu.addItem(item)
    }

    @objc
    private func showCommandPalette(_ sender: Any?) {
        if commandPaletteController?.window?.isVisible == true {
            commandPaletteController?.dismiss(
                restoreParent: commandPaletteController?.window?.isKeyWindow == true
            )
            return
        }

        if commandPaletteController == nil {
            commandPaletteController = CommandPaletteController(
                onInvokeCommand: { [weak self] command, windowID in
                    guard let self else { return }
                    self.withCommandWindowContext(windowID) {
                        self.shortcutHandlerMap()[command]?()
                    }
                },
                onVisibilityChange: { [weak self] _ in
                    self?.refreshMenuShortcuts()
                }
            )
        }
        let targetWindowID = commandPaletteTargetWindowID()
        let availableCommands = availableCommandPaletteCommands(targetWindowID: targetWindowID)
        recentFilesPaletteController?.close()
        libraryPaletteController?.close()
        closeOpenTabsPalette()
        commandPaletteController?.show(
            commands: availableCommands.map(\.command),
            bindings: appConfiguration.shortcuts.bindings,
            titles: Dictionary(uniqueKeysWithValues: availableCommands.map { ($0.command, $0.title) }),
            targetWindowID: targetWindowID,
            relativeTo: NSApp.keyWindow ?? mainWindowController?.window
        )
    }

    private func commandPaletteTargetWindowID() -> UUID? {
        if let keyWindow = NSApp.keyWindow,
           let controller = controller(for: keyWindow) {
            return controller.windowID
        }
        if let mainWindow = NSApp.mainWindow,
           let controller = controller(for: mainWindow) {
            return controller.windowID
        }
        return NSApp.orderedWindows.lazy.compactMap { self.controller(for: $0)?.windowID }.first
    }

    private func availableCommandPaletteCommands(
        targetWindowID: UUID?
    ) -> [(command: ShortcutCommand, title: String)] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        return withCommandWindowContext(targetWindowID) {
            ShortcutCommand.allCases.compactMap { command in
                guard let item = configuredMenuItem(for: command, in: mainMenu),
                      validateMenuItem(item) else { return nil }
                let title = switch command {
                case .closeCurrentTab, .sendContextToCodex:
                    item.title
                default:
                    command.menuTitle
                }
                return (command, title)
            }
        }
    }

    private func configuredMenuItem(for command: ShortcutCommand, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? ShortcutCommand == command {
                return item
            }
            if let submenu = item.submenu,
               let match = configuredMenuItem(for: command, in: submenu) {
                return match
            }
        }
        return nil
    }

    @objc
    private func showRecentFilesPalette(_ sender: Any?) {
        commandPaletteController?.dismiss(restoreParent: false)
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
        commandPaletteController?.dismiss(restoreParent: false)
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
        commandPaletteController?.dismiss(restoreParent: false)
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
                guard alternatePane else {
                    self.documentStore.activateTab(sessionID: sessionID, in: windowID)
                    return
                }
                let focusedPane = self.documentStore.focusedPane(in: windowID)
                let targetPane = self.documentStore.isSplitEnabled(in: windowID)
                    ? focusedPane
                    : focusedPane.other
                self.documentStore.activateTab(
                    sessionID: sessionID,
                    in: windowID,
                    targetPane: targetPane
                )
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
    private func applyAnnotationCommand(_ sender: Any?) {
        let command = (sender as? NSMenuItem)?.representedObject as? ShortcutCommand
            ?? sender as? ShortcutCommand
        guard let type = command?.annotationMarkupType else { return }
        _ = mainWindowController?.triggerAnnotationShortcut(type)
    }

    @objc
    private func addOrEditComment(_ sender: Any?) {
        _ = mainWindowController?.addOrEditComment()
    }

    @objc
    private func exitHighlightMode(_ sender: Any?) {
        _ = mainWindowController?.exitTransientReaderState()
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
    private func toggleReadingFocusModeAction(_ sender: Any?) {
        mainWindowController?.toggleReadingFocusMode()
    }

    @objc
    private func toggleHorizontalPanLockAction(_ sender: Any?) {
        mainWindowController?.toggleHorizontalPanLock()
    }

    @objc
    private func showReadingFocusControlsAction(_ sender: Any?) {
        mainWindowController?.showReadingFocusControls()
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
    private func useSideBySideReaderSplit(_ sender: Any?) {
        showReaderSplit(layout: .sideBySide)
    }

    @objc
    private func useStackedReaderSplit(_ sender: Any?) {
        showReaderSplit(layout: .stacked)
    }

    private func showReaderSplit(layout: ReaderSplitLayout) {
        guard let controller = mainWindowController,
              documentStore.activeSession(in: controller.windowID)?.isBlank == false else { return }
        documentStore.setSplitLayout(layout, in: controller.windowID)
        documentStore.setSplitEnabled(true, in: controller.windowID)
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
    func toggleNightMode(_ sender: Any?) {
        let currentIsDark = (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        toggleTemporaryAppearanceMode(currentIsDark: currentIsDark)
        applyApplicationAppearance()
    }

    var persistentAppearanceMode: AppearanceMode {
        appConfiguration.appearance.mode
    }

    func toggleTemporaryAppearanceMode(currentIsDark: Bool) {
        temporaryAppearanceMode = temporaryAppearanceMode == nil
            ? appConfiguration.appearance.mode.toggled(currentIsDark: currentIsDark)
            : nil
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
    private func fitReaderToTextWidth(_ sender: Any?) {
        mainWindowController?.fitReaderToTextWidth()
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
    private func toggleDisplayModeContinuity(_ sender: Any?) {
        guard let controller = mainWindowController,
              let sessionID = documentStore.activeSessionID(in: controller.windowID) else { return }
        documentStore.toggleDisplayModeContinuity(for: sessionID)
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
    private func useBook(_ sender: Any?) {
        setActiveReaderDisplayMode(.book)
    }

    @objc
    private func useBookContinuous(_ sender: Any?) {
        setActiveReaderDisplayMode(.bookContinuous)
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
    private func shareDocument(_ sender: Any?) {
        guard let context = currentPDFShareContext() else { return }
        guard saveBeforeSharingIfNeeded(context.session) else { return }
        guard let refreshedContext = currentPDFShareContext() else { return }
        guard let payload = promptForSharePayload(
            hasHighlights: documentStore.hasHighlights(for: refreshedContext.session.id)
        ) else { return }

        do {
            let items = try shareItems(for: payload, session: refreshedContext.session)
            try presentSharingPicker(items: items, from: refreshedContext.controller)
        } catch {
            presentShareError(error)
        }
    }

    @objc
    private func exportCleanCopy(_ sender: Any?) {
        guard let context = currentPDFShareContext() else { return }
        guard saveBeforeSharingIfNeeded(context.session) else { return }
        guard let refreshedContext = currentPDFShareContext() else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = cleanCopyFilename(for: refreshedContext.session)
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try documentStore.writeCleanCopy(for: refreshedContext.session.id, to: url)
        } catch {
            presentShareError(error)
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
    private func exportAllOpenHighlights(_ sender: Any?) {
        guard let documents = currentAllOpenHighlightExportContext() else { return }
        guard let format = promptForHighlightExportFormat() else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = HighlightExporter.defaultAllOpenFilename(format: format)
        panel.allowedContentTypes = [contentType(for: format)]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try HighlightExporter.exportAllOpen(documents, format: format)
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

    @objc
    private func copyCurrentPageAsImage(_ sender: Any?) {
        guard let session = currentPageImageSession(),
              let image = try? documentStore.currentPageImage(for: session.id) else { return }
        PDFPageImageService.copyToPasteboard(image)
    }

    @objc
    private func sendContextToCodex(_ sender: Any?) {
        guard appConfiguration.integrations.codexEnabled else { return }
        if let text = mainWindowController?.selectedReaderText {
            openTextInCodex(text)
            return
        }
        sendCurrentPageToCodex()
    }

    private func sendCurrentPageToCodex() {
        guard let session = currentPageImageSession() else { return }

        do {
            let image = try documentStore.currentPageImage(for: session.id)
            openPageImageInCodex(
                image,
                pageNumber: session.currentPageIndex + 1,
                documentTitle: session.title
            )
        } catch {
            presentCodexShareError(error)
        }
    }

    @objc
    private func sendCurrentPDFToCodex(_ sender: Any?) {
        guard appConfiguration.integrations.codexEnabled,
              let session = currentPublicPDFSession(),
              saveBeforeSharingIfNeeded(session) else { return }
        openFilesInCodex([session.url])
    }

    private func openTextInCodex(_ text: String) {
        guard appConfiguration.integrations.codexEnabled else { return }
        do {
            try codexShareCoordinator.openText(text)
        } catch {
            presentCodexShareError(error)
        }
    }

    private func openPageImageInCodex(_ image: NSImage, pageNumber: Int, windowID: UUID) {
        guard appConfiguration.integrations.codexEnabled else { return }
        guard let session = focusedPDFSession(in: windowID) else { return }
        openPageImageInCodex(image, pageNumber: pageNumber, documentTitle: session.title)
    }

    private func openPageImageInCodex(_ image: NSImage, pageNumber: Int, documentTitle: String) {
        do {
            let url = try codexShareCoordinator.writePageImage(
                image,
                documentTitle: documentTitle,
                pageNumber: pageNumber
            )
            openFilesInCodex([url])
        } catch {
            presentCodexShareError(error)
        }
    }

    private func openFilesInCodex(_ urls: [URL]) {
        guard appConfiguration.integrations.codexEnabled else { return }
        do {
            try codexShareCoordinator.openFiles(urls) { [weak self] error in
                guard let error else { return }
                self?.presentCodexShareError(error)
            }
        } catch {
            presentCodexShareError(error)
        }
    }

    private func currentPageImageSession() -> DocumentSession? {
        guard let windowID = mainWindowController?.windowID ?? mainWindowControllers.values.first?.windowID else {
            return nil
        }
        return focusedPDFSession(in: windowID)
    }

    private func focusedPDFSession(in windowID: UUID) -> DocumentSession? {
        let pane = documentStore.isSplitEnabled(in: windowID)
            ? documentStore.focusedPane(in: windowID)
            : .primary
        guard let sessionID = documentStore.displayedSessionID(for: pane, in: windowID),
              let session = documentStore.session(for: sessionID),
              session.isBlank == false else {
            return nil
        }
        return session
    }

    private func currentPublicPDFSession() -> DocumentSession? {
        guard let windowID = mainWindowController?.windowID,
              let focusedSession = focusedPDFSession(in: windowID),
              let publicSessionID = documentStore.publicSessionID(
                forDisplayedSessionID: focusedSession.id,
                in: windowID
              ) else { return nil }
        return documentStore.session(for: publicSessionID)
    }

    private func makeOpenWithMenu(for sessionID: UUID, in windowID: UUID) -> NSMenu? {
        guard let publicSessionID = documentStore.publicSessionID(
            forDisplayedSessionID: sessionID,
            in: windowID
        ),
        let session = documentStore.session(for: publicSessionID),
        session.isBlank == false else { return nil }

        let menu = NSMenu(title: "Open With")
        menu.autoenablesItems = false
        populateOpenWithMenu(menu, session: session)
        return menu
    }

    private func revealPDFInFinder(for sessionID: UUID, in windowID: UUID) {
        guard let publicSessionID = documentStore.publicSessionID(
            forDisplayedSessionID: sessionID,
            in: windowID
        ),
        let session = documentStore.session(for: publicSessionID),
        session.isBlank == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting([session.url])
    }

    private func rebuildOpenWithMenu() {
        openWithMenu.removeAllItems()
        guard let session = currentPublicPDFSession() else {
            addUnavailableOpenWithItem(to: openWithMenu, title: "No PDF Open")
            return
        }
        populateOpenWithMenu(openWithMenu, session: session)
    }

    private func populateOpenWithMenu(_ menu: NSMenu, session: DocumentSession) {
        let applications = externalApplicationService.applications(for: session.url)
        guard applications.isEmpty == false else {
            addUnavailableOpenWithItem(to: menu, title: "No Compatible Applications")
            return
        }

        for application in applications {
            let item = NSMenuItem(
                title: application.name,
                action: #selector(openPDFWithApplication(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = application.icon
            item.representedObject = OpenWithRequest(
                sessionID: session.id,
                applicationURL: application.url
            )
            menu.addItem(item)
        }
    }

    private func addUnavailableOpenWithItem(to menu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc
    private func openPDFWithApplication(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? OpenWithRequest,
              let session = documentStore.session(for: request.sessionID),
              saveBeforeOpeningExternallyIfNeeded(session) else { return }

        externalApplicationService.open(
            documentURL: session.url,
            with: request.applicationURL
        ) { [weak self] error in
            guard let error else { return }
            self?.presentExternalApplicationError(error)
        }
    }

    private func currentPDFShareContext() -> (controller: MainWindowController, session: DocumentSession)? {
        guard let controller = mainWindowController,
              let session = documentStore.activeSession(in: controller.windowID),
              session.isBlank == false else { return nil }
        return (controller, session)
    }

    private func saveBeforeSharingIfNeeded(_ session: DocumentSession) -> Bool {
        saveAnnotationsIfNeeded(
            session,
            title: "Save Before Sharing",
            message: "This PDF has unsaved annotations. Save them before sharing or exporting a clean copy."
        )
    }

    private func saveBeforeOpeningExternallyIfNeeded(_ session: DocumentSession) -> Bool {
        saveAnnotationsIfNeeded(
            session,
            title: "Save Before Opening",
            message: "This PDF has unsaved annotations. Save them before opening it in another application."
        )
    }

    private func saveAnnotationsIfNeeded(
        _ session: DocumentSession,
        title: String,
        message: String
    ) -> Bool {
        guard session.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try documentStore.saveAnnotations(for: session.id)
            return true
        } catch {
            presentSaveError(error)
            return false
        }
    }

    private func promptForSharePayload(hasHighlights: Bool) -> SharePayloadKind? {
        let alert = NSAlert()
        alert.messageText = "Share"
        alert.informativeText = "Choose what to share."
        alert.addButton(withTitle: "Share")
        alert.addButton(withTitle: "Cancel")

        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        for payload in SharePayloadKind.allCases {
            popUp.addItem(withTitle: payload.title)
            guard let item = popUp.itemArray.last else { continue }
            item.tag = payload.rawValue
            if payload == .highlightsMarkdown && hasHighlights == false {
                item.isEnabled = false
            }
        }
        popUp.selectItem(at: 0)
        alert.accessoryView = popUp

        guard alert.runModal() == .alertFirstButtonReturn,
              let selectedItem = popUp.selectedItem else { return nil }
        return SharePayloadKind(rawValue: selectedItem.tag)
    }

    private func shareItems(for payload: SharePayloadKind, session: DocumentSession) throws -> [Any] {
        switch payload {
        case .originalPDF:
            return [session.url]
        case .cleanPDFCopy:
            let url = try temporaryCleanCopyURL(for: session)
            try documentStore.writeCleanCopy(for: session.id, to: url)
            return [url]
        case .highlightsMarkdown:
            let groups = documentStore.annotationGroups(for: session.id)
            guard groups.isEmpty == false else { throw ShareDocumentError.noHighlights }
            let data = try HighlightExporter.export(groups, format: .markdown)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return [markdown]
        }
    }

    private func temporaryCleanCopyURL(for session: DocumentSession) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SereinShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryShareDirectories.append(directory)
        return directory.appendingPathComponent(cleanCopyFilename(for: session))
    }

    private func cleanCopyFilename(for session: DocumentSession) -> String {
        let baseName = session.url.deletingPathExtension().lastPathComponent
        let sanitized = baseName.map { character in
            character == "/" || character == ":" ? "-" : character
        }
        let cleanBaseName = String(sanitized).isEmpty ? "Clean Copy" : String(sanitized)
        return "\(cleanBaseName)-clean.pdf"
    }

    private func presentSharingPicker(items: [Any], from controller: MainWindowController) throws {
        guard let view = controller.window?.contentView else {
            throw ShareDocumentError.missingShareAnchor
        }

        let picker = NSSharingServicePicker(items: items)
        sharingServicePicker = picker
        picker.show(
            relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY, width: 1, height: 1),
            of: view,
            preferredEdge: .maxY
        )
    }

    private func cleanupTemporaryShareDirectories() {
        for url in temporaryShareDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryShareDirectories.removeAll()
    }

    private func setActiveReaderDisplayMode(_ mode: ReaderDisplayMode) {
        guard let controller = mainWindowController,
              let sessionID = documentStore.activeSessionID(in: controller.windowID) else { return }
        documentStore.setDisplayMode(mode, for: sessionID)
    }

    private func updateRecentFilesMenu() {
        let recentDocumentURLs = documentStore.recentDocumentURLs
        guard displayedRecentDocumentURLs != recentDocumentURLs else { return }
        displayedRecentDocumentURLs = recentDocumentURLs
        recentFilesMenu.removeAllItems()

        if recentDocumentURLs.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentFilesMenu.addItem(emptyItem)
            return
        }

        for url in recentDocumentURLs {
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

    @discardableResult
    private func openResolvedDocumentURLs(_ urls: [URL], in targetWindowID: UUID) throws -> UUID? {
        let resolvedURLs = try openDocumentSelectionResolver.resolve(urls)
        return try openOrActivateDocumentURLs(resolvedURLs, in: targetWindowID)
    }

    @discardableResult
    private func openOrActivateDocumentURLs(_ urls: [URL], in targetWindowID: UUID) throws -> UUID? {
        var pendingOpenURLs: [URL] = []
        var seenPendingURLs: Set<URL> = []
        var frontWindowID: UUID?

        for url in urls {
            if let location = documentStore.activateOpenDocument(at: url) {
                frontWindowID = location.windowID
                continue
            }

            let normalizedURL = DocumentStore.normalizedDocumentURL(url)
            if seenPendingURLs.insert(normalizedURL).inserted {
                pendingOpenURLs.append(url)
            }
        }

        if pendingOpenURLs.isEmpty == false {
            _ = try documentStore.open(documentsAt: pendingOpenURLs, in: targetWindowID)
            frontWindowID = targetWindowID
        }

        return frontWindowID
    }

    private func openRecentDocuments(_ urls: [URL], preferredWindowID: UUID? = nil) {
        guard urls.isEmpty == false else { return }
        mainWindowController?.hideFindBar()
        let targetWindowID = preferredWindowID
            .flatMap { documentStore.windowWorkspace(for: $0)?.id }
            ?? mainWindowController?.windowID
            ?? documentStore.defaultWindowID

        do {
            let frontWindowID = try openOrActivateDocumentURLs(urls, in: targetWindowID)
            bringWindowToFront(frontWindowID)
        } catch {
            presentOpenError(error)
        }
    }

    private func openDroppedDocuments(_ urls: [URL], preferredWindowID: UUID? = nil) {
        guard urls.isEmpty == false else { return }
        mainWindowController?.hideFindBar()
        let targetWindowID = preferredWindowID
            .flatMap { documentStore.windowWorkspace(for: $0)?.id }
            ?? mainWindowController?.windowID
            ?? documentStore.defaultWindowID

        do {
            let frontWindowID = try openResolvedDocumentURLs(urls, in: targetWindowID)
            bringWindowToFront(frontWindowID)
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
            let frontWindowID = try openOrActivateDocumentURLs([url], in: controller.windowID)
            bringWindowToFront(frontWindowID)
        } catch {
            presentOpenError(error)
        }
    }

    @objc
    private func openSettingsWindow(_ sender: Any?) {
        openSettingsWindow(sender, selecting: nil)
    }

    @objc
    private func checkForUpdates(_ sender: Any?) {
        appUpdateCoordinator?.checkForUpdatesFromMenu(sender)
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
        let appearanceModeChanged = previousConfiguration.appearance.mode != newConfiguration.appearance.mode
        newConfiguration.access = securityScopedAccessController.sync(access: newConfiguration.access)

        if previousConfiguration.layout.sidebarsSwapped != newConfiguration.layout.sidebarsSwapped {
            swap(&newConfiguration.layout.leftSidebarWidth, &newConfiguration.layout.rightSidebarWidth)
            swap(&newConfiguration.layout.leftSidebarMinWidth, &newConfiguration.layout.rightSidebarMinWidth)
            swap(&newConfiguration.layout.leftSidebarMaxWidth, &newConfiguration.layout.rightSidebarMaxWidth)
        }

        do {
            try configStore.save(newConfiguration)
            appConfiguration = newConfiguration
            if appearanceModeChanged {
                temporaryAppearanceMode = nil
            }
            applyApplicationAppearance()
            refreshMenuShortcuts()
            documentStore.updateAppConfiguration(newConfiguration)
            settingsWindowController?.sync(configuration: newConfiguration)
            if libraryFoldersChanged {
                libraryPaletteController?.invalidateCatalogCache(
                    folderURLs: newConfiguration.library.folderURLs
                )
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
        ThemeManager.shared.apply(
            light: appConfiguration.appearance.lightTheme,
            dark: appConfiguration.appearance.darkTheme
        )
        let effectiveMode = temporaryAppearanceMode ?? appConfiguration.appearance.mode
        NSApp.appearance = effectiveMode.appAppearance
        mainWindowControllers.values.forEach { $0.refreshThemeAppearance() }
        settingsWindowController?.window?.appearance = effectiveMode.appAppearance
        settingsWindowController?.refreshChromeColors()
        commandPaletteController?.refreshChromeColors()
        recentFilesPaletteController?.refreshChromeColors()
        libraryPaletteController?.refreshChromeColors()
        openTabsPaletteController?.refreshChromeColors()
    }

    private func refreshThemeChromeIfFollowingSystem() {
        guard temporaryAppearanceMode == nil,
              appConfiguration.appearance.mode == .system else { return }
        mainWindowControllers.values.forEach { $0.refreshThemeAppearance() }
        settingsWindowController?.window?.appearance = nil
        settingsWindowController?.refreshChromeColors()
        commandPaletteController?.refreshChromeColors()
        recentFilesPaletteController?.refreshChromeColors()
        libraryPaletteController?.refreshChromeColors()
        openTabsPaletteController?.refreshChromeColors()
    }

    private func refreshMenuShortcuts() {
        sendToCodexItem.isHidden = appConfiguration.integrations.codexEnabled == false
        guard let menu = NSApp.mainMenu else { return }
        refreshMenuShortcuts(in: menu)
        refreshManagedMenuState(in: menu)
    }

    private func shouldExposeMenuKeyEquivalent(_ shortcut: KeyboardShortcut) -> Bool {
        guard commandPaletteController?.window?.isVisible == true else { return true }
        return ShortcutCommand.allCases.contains { command in
            command.builtInShortcutSequence?.strokes.last == shortcut
        } == false
    }

    private func refreshMenuShortcuts(in menu: NSMenu) {
        for item in menu.items {
            if let command = item.representedObject as? ShortcutCommand {
                item.title = menuTitle(command.menuTitle, for: command)
                if let shortcut = appConfiguration.shortcuts.bindings[command],
                   shouldExposeMenuKeyEquivalent(shortcut) {
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
        sendToCodexItem.isHidden = appConfiguration.integrations.codexEnabled == false
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

    private func presentCodexShareError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to send to Codex"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentExternalApplicationError(_ error: Error) {
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

    private func presentShareError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to share or export document"
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

    private func currentAllOpenHighlightExportContext() -> [HighlightExporter.DocumentGroups]? {
        guard let windowID = mainWindowController?.windowID else { return nil }
        let documents = documentStore.sessions(in: windowID).compactMap { session -> HighlightExporter.DocumentGroups? in
            guard session.isBlank == false else { return nil }
            let groups = documentStore.annotationGroups(for: session.id)
            guard groups.isEmpty == false else { return nil }
            return (documentTitle: session.title, groups: groups)
        }
        return documents.isEmpty ? nil : documents
    }

    /// Menu validation must remain metadata-only. An unloaded annotation cache is
    /// treated as potentially containing highlights; the explicit export action
    /// resolves the exact groups after the user chooses it.
    private func mayHaveHighlights(_ session: DocumentSession) -> Bool {
        guard session.isBlank == false else { return false }
        guard session.isAnnotationCacheLoaded else { return true }
        return session.annotationCache.groups.isEmpty == false
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
        case #selector(moveCurrentPDFToExistingWindow(_:)):
            guard let destinationWindowIDString = menuItem.representedObject as? String,
                  let destinationWindowID = UUID(uuidString: destinationWindowIDString),
                  let sourceWindowID = windowID else { return false }
            return activePDFSession != nil &&
                destinationWindowID != sourceWindowID &&
                documentStore.windowIDs().contains(destinationWindowID)
        case #selector(refreshLibraryIndex(_:)), #selector(showLibraryPalette(_:)):
            return appConfiguration.library.folderURLs.isEmpty == false
        case #selector(openLibrarySettings(_:)), #selector(openShortcutSettings(_:)):
            return true
        case #selector(applyAnnotationCommand(_:)), #selector(addOrEditComment(_:)):
            return activePDFSession != nil
        case #selector(exitHighlightMode(_:)):
            menuItem.state = controller?.isAnnotationModeEnabled == true ? .on : .off
            return controller?.isAnnotationModeEnabled == true
        case #selector(toggleNightMode(_:)):
            menuItem.state = controller?.isNightModeEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleReadingFocusModeAction(_:)):
            menuItem.state = controller?.isReadingFocusModeEnabled == true ? .on : .off
            return activePDFSession != nil
        case #selector(toggleHorizontalPanLockAction(_:)):
            menuItem.state = controller?.isHorizontalPanLocked == true ? .on : .off
            return activePDFSession.map { $0.displayMode.usesBookLayout == false } == true
        case #selector(showReadingFocusControlsAction(_:)):
            return activePDFSession != nil
        case #selector(saveAnnotations(_:)):
            return activePDFSession?.isDirty == true
        case #selector(shareDocument(_:)), #selector(exportCleanCopy(_:)):
            return activePDFSession != nil
        case #selector(exportHighlights(_:)), #selector(copyHighlightsMarkdown(_:)):
            return activePDFSession.map(mayHaveHighlights) == true
        case #selector(exportAllOpenHighlights(_:)):
            guard let windowID else { return false }
            return documentStore.sessions(in: windowID).contains(where: mayHaveHighlights)
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
            return controller != nil
        case #selector(setHighlightColorYellow(_:)):
            menuItem.state = controller?.currentHighlightColor == .yellow ? .on : .off
            return controller != nil
        case #selector(setHighlightColorGreen(_:)):
            menuItem.state = controller?.currentHighlightColor == .green ? .on : .off
            return controller != nil
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
        case #selector(copyCurrentPageAsImage(_:)):
            return currentPageImageSession() != nil
        case #selector(sendContextToCodex(_:)):
            let dynamicTitle = controller?.selectedReaderText == nil
                ? "Send Page Image to Codex"
                : "Send Selection to Codex"
            menuItem.title = menuTitle(dynamicTitle, for: .sendContextToCodex)
            return appConfiguration.integrations.codexEnabled && currentPageImageSession() != nil
        case #selector(sendCurrentPDFToCodex(_:)):
            return appConfiguration.integrations.codexEnabled && currentPublicPDFSession() != nil
        case #selector(findNextMatchAction(_:)), #selector(findPreviousMatchAction(_:)):
            return controller?.isFindBarVisible == true
        case #selector(useSidebarTabs(_:)):
            menuItem.state = windowID.map { documentStore.tabPresentationMode(in: $0) == .verticalSidebar } == true ? .on : .off
            return controller != nil
        case #selector(useTitlebarTabs(_:)):
            menuItem.state = windowID.map { documentStore.tabPresentationMode(in: $0) == .horizontalTitlebar } == true ? .on : .off
            return controller != nil
        case #selector(toggleLeftSidebar(_:)):
            menuItem.state = windowID.map { documentStore.isLeftSidebarVisible(in: $0) } == true ? .on : .off
            return controller != nil
        case #selector(toggleRightSidebar(_:)):
            menuItem.state = windowID.map { documentStore.isRightSidebarVisible(in: $0) } == true ? .on : .off
            return controller != nil
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
        case #selector(toggleDisplayModeContinuity(_:)):
            return activePDFSession != nil
        case #selector(zoomInReader(_:)), #selector(zoomOutReader(_:)), #selector(fitReaderToTextWidth(_:)):
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
        case #selector(useSideBySideReaderSplit(_:)):
            menuItem.state = windowID.map {
                documentStore.isSplitEnabled(in: $0) && documentStore.splitLayout(in: $0) == .sideBySide
            } == true ? .on : .off
            return activePDFSession != nil
        case #selector(useStackedReaderSplit(_:)):
            menuItem.state = windowID.map {
                documentStore.isSplitEnabled(in: $0) && documentStore.splitLayout(in: $0) == .stacked
            } == true ? .on : .off
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
        case #selector(useBook(_:)):
            menuItem.state = activePDFSession?.displayMode == .book ? .on : .off
            return activePDFSession != nil
        case #selector(useBookContinuous(_:)):
            menuItem.state = activePDFSession?.displayMode == .bookContinuous ? .on : .off
            return activePDFSession != nil
        default:
            return true
        }
    }
}

#if DEBUG
extension AppDelegate {
    func installMenuForTesting(documentStore: DocumentStore, controllers: [MainWindowController]) {
        self.documentStore = documentStore
        mainWindowControllers = Dictionary(uniqueKeysWithValues: controllers.map { ($0.windowID, $0) })
        installMainMenu()
        observeMenuStateChanges()
    }
}
#endif
