import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct WorkspaceWorkflowTests {
    @Test(arguments: [NSSize(width: 800, height: 600), NSSize(width: 1480, height: 940)])
    func menuCommandsBuildFourPanesAndRestoreWorkspace(contentSize: NSSize) async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        // Let AppKit finish activation so menu validation uses a real key window.
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSApp.stop(nil)
                NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    subtype: 0, data1: 0, data2: 0)!, atStart: false)
            }
        }
        NSApp.run()
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        let window = try #require(controller.window)
        let previousMenu = NSApp.mainMenu
        defer {
            controller.close()
            NSApp.mainMenu = previousMenu
        }
        let fixturePath = ProcessInfo.processInfo.environment["SEREIN_WORKSPACE_QA_PDF"]
        let url = try fixturePath.map { URL(fileURLWithPath: $0) }
            ?? TestPDFFixtures.makeLabeledPDF(named: "workspace-workflow", pageSizes: Array(repeating: NSSize(width: 612, height: 792), count: 6))
        let source = try store.open(documentAt: url)
        let workspaceID = try #require(store.activeWorkspaceID(in: controller.windowID))
        // AppKit can shrink this window to the current screen. Reserve its width
        // for the four readers instead of relying on a large desktop plus sidebars.
        store.setLeftSidebarVisible(false, in: controller.windowID)
        store.setRightSidebarVisible(false, in: controller.windowID)
        window.setContentSize(contentSize)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let app = AppDelegate()
        app.installMenuForTesting(documentStore: store, controllers: [controller])
        settle(window)
        let split = try #require(window.contentViewController as? SplitViewController)
        let readers = split.readerWorkspaceViewController
        try #require(readers.canSplitPane(layout: .sideBySide))
        try #require(readers.canSplitPane(layout: .stacked))

        try invoke(.splitCurrentPDFRight, app: app)
        settle(window)
        try #require(store.readerPanes(in: controller.windowID).count == 2)
        try #require(store.focusedPane(in: controller.windowID) == .secondary)
        try invoke(.splitCurrentPDFDown, app: app)
        settle(window)
        try #require(store.readerPanes(in: controller.windowID).count == 3)
        try invoke(.focusPaneLeft, app: app)
        try #require(store.focusedPane(in: controller.windowID) == .primary)
        try invoke(.splitCurrentPDFDown, app: app)
        settle(window)
        let panes = store.readerPanes(in: controller.windowID)
        #expect(panes.count == 4)
        #expect(Set(panes.compactMap(\.sessionID)).count == 4)
        #expect(store.sessions(in: controller.windowID).map(\.id) == [source.id])
        for (index, pane) in panes.enumerated() {
            let reader = try #require(readers.readerViewController(for: pane.id))
            reader.goToPage(index)
        }
        settle(window)
        controller.flushPendingReadingPositions()
        let positions = try Dictionary(uniqueKeysWithValues: panes.map { pane in
            let reader = try #require(readers.readerViewController(for: pane.id))
            return (pane.id, try #require(reader.currentPosition))
        })
        let savedLayout = store.readerLayout(in: controller.windowID)
        let focusedPane = store.focusedPane(in: controller.windowID)
        try invoke(.togglePaneZoom, app: app)
        #expect(store.zoomedPane(in: controller.windowID) == focusedPane)
        try invoke(.togglePaneZoom, app: app)
        #expect(store.zoomedPane(in: controller.windowID) == nil)
        #expect(store.readerLayout(in: controller.windowID) == savedLayout)

        let otherWorkspace = try #require(store.createWorkspace(name: "Notes", in: controller.windowID))
        store.activateWorkspace(otherWorkspace, in: controller.windowID)
        #expect(store.sessions(in: controller.windowID).isEmpty)
        let other = try store.open(documentAt: url, in: controller.windowID)
        #expect(other.id != source.id)
        #expect(try store.pdfDocument(for: other.id) === store.pdfDocument(for: source.id))
        store.activateWorkspace(workspaceID, in: controller.windowID)
        settle(window)
        #expect(store.readerLayout(in: controller.windowID) == savedLayout)
        #expect(store.focusedPane(in: controller.windowID) == focusedPane)
        for pane in panes {
            let reader = try #require(readers.readerViewController(for: pane.id))
            let before = try #require(positions[pane.id])
            let after = try #require(reader.currentPosition)
            #expect(after.pageIndex == before.pageIndex)
            #expect(abs(after.point.y - before.point.y) < 2)
            #expect(!reader.pdfView.visiblePages.isEmpty)
            let page = try #require(reader.pdfView.document?.page(at: after.pageIndex))
            let visibleBounds = reader.pdfView.convert(reader.pdfView.bounds, to: page)
            #expect(!visibleBounds.intersection(page.bounds(for: .cropBox)).isEmpty)
        }

        if fixturePath != nil {
            try await capture(window)
        }
        try invoke(.closeCurrentTab, app: app)
        settle(window)
        #expect(store.readerPanes(in: controller.windowID).count == 3)
        #expect(store.sessions(in: controller.windowID).map(\.id) == [source.id])
        #expect(window.firstResponder === split.readerViewController.pdfView)
    }

    private func invoke(_ command: ShortcutCommand, app: AppDelegate) throws {
        let menu = try #require(NSApp.mainMenu)
        let item = try #require(find(command, in: menu))
        #expect(app.validateMenuItem(item))
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func find(_ command: ShortcutCommand, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? ShortcutCommand == command { return item }
            if let submenu = item.submenu, let match = find(command, in: submenu) { return match }
        }
        return nil
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
        window.layoutIfNeeded()
    }

    private func capture(_ window: NSWindow, name: String = "workspace-four-panes") async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/\(name).png")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settle(window)
        try await Task.sleep(for: .seconds(1))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), output.path]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}
