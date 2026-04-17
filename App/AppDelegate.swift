import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var mainWindowController: MainWindowController?
    private var documentStore: DocumentStore!
    private var appConfiguration: AppConfiguration = .default
    private var configStore: AppConfigurationStore?

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
        installMainMenu()

        let windowController = MainWindowController(documentStore: documentStore)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)

        mainWindowController = windowController
        try? documentStore.restorePersistedState()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc
    func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.message = "Open one or more PDF files."

        guard panel.runModal() == .OK else { return }

        do {
            for url in panel.urls {
                _ = try documentStore.open(documentAt: url)
            }
        } catch {
            presentOpenError(error)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(buildApplicationMenuItem())
        mainMenu.addItem(buildFileMenuItem())
        mainMenu.addItem(buildTabsMenuItem())
        mainMenu.addItem(buildViewMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func buildApplicationMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit SlatePDF",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func buildFileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(
            title: "Open…",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        let closeItem = makeConfiguredMenuItem(
            title: "Close Current Tab",
            command: .closeCurrentTab,
            action: #selector(closeCurrentTab(_:))
        )

        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        fileMenu.items = [openItem, closeItem]
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func buildTabsMenuItem() -> NSMenuItem {
        let tabsMenuItem = NSMenuItem()
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

    private func buildViewMenuItem() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
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
            .separator(),
            makeConfiguredMenuItem(
                title: "Fit Width",
                command: .fitWidth,
                action: #selector(fitReaderToWidth(_:))
            ),
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
        ]
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
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
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
    }

    @objc
    private func closeCurrentTab(_ sender: Any?) {
        documentStore.closeActiveSession()
    }

    @objc
    private func activatePreviousTab(_ sender: Any?) {
        documentStore.activatePreviousSession()
    }

    @objc
    private func activateNextTab(_ sender: Any?) {
        documentStore.activateNextSession()
    }

    @objc
    private func useSidebarTabs(_ sender: Any?) {
        documentStore.setTabPresentationMode(.verticalSidebar)
    }

    @objc
    private func useTitlebarTabs(_ sender: Any?) {
        documentStore.setTabPresentationMode(.horizontalTitlebar)
    }

    @objc
    private func toggleLeftSidebar(_ sender: Any?) {
        documentStore.setLeftSidebarVisible(!documentStore.isLeftSidebarVisible)
    }

    @objc
    private func toggleRightSidebar(_ sender: Any?) {
        documentStore.setRightSidebarVisible(!documentStore.isRightSidebarVisible)
    }

    @objc
    private func fitReaderToWidth(_ sender: Any?) {
        mainWindowController?.fitReaderToWidth()
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

    private func setActiveReaderDisplayMode(_ mode: ReaderDisplayMode) {
        guard let sessionID = documentStore.activeSessionID else { return }
        documentStore.setDisplayMode(mode, for: sessionID)
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(useSidebarTabs(_:)):
            menuItem.state = documentStore.tabPresentationMode == .verticalSidebar ? .on : .off
            return true
        case #selector(useTitlebarTabs(_:)):
            menuItem.state = documentStore.tabPresentationMode == .horizontalTitlebar ? .on : .off
            return true
        case #selector(toggleLeftSidebar(_:)):
            menuItem.state = documentStore.isLeftSidebarVisible ? .on : .off
            return true
        case #selector(toggleRightSidebar(_:)):
            menuItem.state = documentStore.isRightSidebarVisible ? .on : .off
            return true
        case #selector(closeCurrentTab(_:)):
            return documentStore.activeSession != nil
        case #selector(activatePreviousTab(_:)), #selector(activateNextTab(_:)):
            return documentStore.sessions.count > 1
        case #selector(fitReaderToWidth(_:)):
            menuItem.state = documentStore.activeSession?.scaleMode == .fitWidth ? .on : .off
            return documentStore.activeSession != nil
        case #selector(useSinglePage(_:)):
            menuItem.state = documentStore.activeSession?.displayMode == .singlePage ? .on : .off
            return documentStore.activeSession != nil
        case #selector(useSinglePageContinuous(_:)):
            menuItem.state = documentStore.activeSession?.displayMode == .singlePageContinuous ? .on : .off
            return documentStore.activeSession != nil
        case #selector(useTwoUp(_:)):
            menuItem.state = documentStore.activeSession?.displayMode == .twoUp ? .on : .off
            return documentStore.activeSession != nil
        case #selector(useTwoUpContinuous(_:)):
            menuItem.state = documentStore.activeSession?.displayMode == .twoUpContinuous ? .on : .off
            return documentStore.activeSession != nil
        default:
            return true
        }
    }
}
