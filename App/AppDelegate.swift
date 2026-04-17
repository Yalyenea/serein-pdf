import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private let documentStore = DocumentStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let windowController = MainWindowController(documentStore: documentStore)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)

        mainWindowController = windowController
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

    private func presentOpenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Failed to open PDF"
        if let window = mainWindowController?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
