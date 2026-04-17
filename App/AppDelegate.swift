import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var mainWindowController: MainWindowController?
    private let documentStore = DocumentStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
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

        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenuItem.submenu = fileMenu

        return fileMenuItem
    }

    private func buildViewMenuItem() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let sidebarTabsItem = NSMenuItem(
            title: "Use Sidebar Tabs",
            action: #selector(useSidebarTabs(_:)),
            keyEquivalent: ""
        )
        sidebarTabsItem.target = self

        let titlebarTabsItem = NSMenuItem(
            title: "Use Titlebar Tabs",
            action: #selector(useTitlebarTabs(_:)),
            keyEquivalent: ""
        )
        titlebarTabsItem.target = self

        let toggleLeftSidebarItem = NSMenuItem(
            title: "Toggle Left Sidebar",
            action: #selector(toggleLeftSidebar(_:)),
            keyEquivalent: ""
        )
        toggleLeftSidebarItem.target = self

        let toggleRightSidebarItem = NSMenuItem(
            title: "Toggle Right Sidebar",
            action: #selector(toggleRightSidebar(_:)),
            keyEquivalent: ""
        )
        toggleRightSidebarItem.target = self

        viewMenu.items = [
            sidebarTabsItem,
            titlebarTabsItem,
            .separator(),
            toggleLeftSidebarItem,
            toggleRightSidebarItem,
        ]
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
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

    private func presentOpenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to open PDF"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(useSidebarTabs(_:)):
            menuItem.state = documentStore.tabPresentationMode == .verticalSidebar ? .on : .off
        case #selector(useTitlebarTabs(_:)):
            menuItem.state = documentStore.tabPresentationMode == .horizontalTitlebar ? .on : .off
        case #selector(toggleLeftSidebar(_:)):
            menuItem.state = documentStore.isLeftSidebarVisible ? .on : .off
        case #selector(toggleRightSidebar(_:)):
            menuItem.state = documentStore.isRightSidebarVisible ? .on : .off
        default:
            break
        }

        return true
    }
}
