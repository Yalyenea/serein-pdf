import AppKit
import XCTest
@testable import Serein

@MainActor
final class ReaderMenuKeyboardTests: XCTestCase {
    func testPrintMenuTracksCurrentPDFAndBlankTab() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        let previousWindowsMenu = app.windowsMenu
        let store = makeIsolatedDocumentStore()
        let reader = MainWindowController(documentStore: store)
        let delegate = AppDelegate()
        let window = try XCTUnwrap(reader.window)
        delegate.installMenuForTesting(documentStore: store, controllers: [reader])
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        defer {
            NotificationCenter.default.removeObserver(delegate)
            reader.close()
            app.mainMenu = previousMenu
            app.windowsMenu = previousWindowsMenu
        }
        let item = try XCTUnwrap(find(.printDocument, in: XCTUnwrap(app.mainMenu)))
        XCTAssertFalse(delegate.validateMenuItem(item))

        let url = try TestPDFFixtures.makeLabeledPDF(named: "print-menu", pageSizes: [NSSize(width: 612, height: 792)])
        let session = try store.open(documentAt: url, in: reader.windowID)
        _ = try store.pdfDocument(for: session.id)
        XCTAssertTrue(delegate.validateMenuItem(item))
        XCTAssertEqual(item.keyEquivalent, "p")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
        store.setDirty(true, for: session.id)
        XCTAssertTrue(delegate.validateMenuItem(item))
        store.setDirty(false, for: session.id)

        _ = store.newBlankTab(in: reader.windowID)
        XCTAssertFalse(delegate.validateMenuItem(item))
    }

    func testAuxiliaryEditorsKeepControlBindingsWithSplitReaderOpen() throws {
        guard ProcessInfo.processInfo.environment["SEREIN_KEYBOARD_TEST_CHILD"] == "1" else {
            try runInIsolatedApplication()
            return
        }
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        var failure: Error?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            do { try self.exerciseAuxiliaryEditors() }
            catch { failure = error }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
        // SwiftPM has no application event loop; key-window transitions require one.
        NSApp.run()
        if let failure { throw failure }
    }

    func testWorkspaceMenuShortcutsSwitchEmptyWorkspacesInBothTabModes() throws {
        guard ProcessInfo.processInfo.environment["SEREIN_KEYBOARD_TEST_CHILD"] == "1" else {
            try runInIsolatedApplication(testName: "testWorkspaceMenuShortcutsSwitchEmptyWorkspacesInBothTabModes")
            return
        }
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        var failure: Error?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            do { try self.exerciseWorkspaceKeyboardNavigation() }
            catch { failure = error }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
        NSApp.run()
        if let failure { throw failure }
    }

    private func runInIsolatedApplication(testName: String = "testAuxiliaryEditorsKeepControlBindingsWithSplitReaderOpen") throws {
        // NSApplication's launch and activation lifecycle cannot be reset between tests.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctest", "-XCTest",
            "SereinTests.ReaderMenuKeyboardTests/\(testName)",
            Bundle(for: Self.self).bundleURL.path]
        let environmentKeys: Set<String> = ["PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "DEVELOPER_DIR", "SDKROOT"]
        process.environment = ProcessInfo.processInfo.environment.filter { environmentKeys.contains($0.key) }
        process.environment?["SEREIN_KEYBOARD_TEST_CHILD"] = "1"
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, result)
        XCTAssertTrue(result.contains("Executed 1 test"), result)
    }

    private func exerciseWorkspaceKeyboardNavigation() throws {
        let previousMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        let window = try XCTUnwrap(controller.window)
        let delegate = AppDelegate()
        defer {
            NotificationCenter.default.removeObserver(delegate)
            controller.close()
            NSApp.mainMenu = previousMenu
            NSApp.windowsMenu = previousWindowsMenu
        }
        window.setContentSize(NSSize(width: 1300, height: 800))
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settle(window)
        delegate.installMenuForTesting(documentStore: store, controllers: [controller])
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let previousItem = try XCTUnwrap(find(.previousWorkspace, in: menu))
        let nextItem = try XCTUnwrap(find(.nextWorkspace, in: menu))
        let ninthItem = try XCTUnwrap(find(.workspace9, in: menu))
        XCTAssertFalse(delegate.validateMenuItem(previousItem))
        XCTAssertFalse(delegate.validateMenuItem(nextItem))
        XCTAssertFalse(delegate.validateMenuItem(ninthItem))

        let url = try TestPDFFixtures.makeLabeledPDF(named: "workspace-menu-keys",
            pageSizes: Array(repeating: NSSize(width: 612, height: 792), count: 8))
        _ = try store.open(documentAt: url, in: controller.windowID)
        XCTAssertTrue(controller.splitCurrentPDF(layout: .sideBySide))
        settle(window)
        let originalID = try XCTUnwrap(store.activeWorkspaceID(in: controller.windowID))
        let cloneID = try XCTUnwrap(store.activeSessionID(in: controller.windowID))
        let clonePane = store.focusedPane(in: controller.windowID)
        let layout = try XCTUnwrap(store.readerLayout(in: controller.windowID))
        var workspaceIDs = [originalID]
        for number in 2...9 {
            workspaceIDs.append(try XCTUnwrap(store.createWorkspace(name: "Space \(number)", in: controller.windowID)))
        }

        for presentation in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            store.setTabPresentationMode(presentation, in: controller.windowID)
            store.activateWorkspace(originalID, in: controller.windowID)
            settle(window)
            XCTAssertTrue(delegate.validateMenuItem(previousItem))
            XCTAssertTrue(delegate.validateMenuItem(nextItem))
            XCTAssertTrue(delegate.validateMenuItem(ninthItem))
            XCTAssertEqual(ninthItem.title, "9. Space 9")
            XCTAssertEqual(nextItem.keyEquivalent, "\u{F703}")
            XCTAssertEqual(nextItem.keyEquivalentModifierMask, [.command, .option])
            XCTAssertEqual(ninthItem.keyEquivalent, "9")
            let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
            let reader = try XCTUnwrap(split.readerWorkspaceViewController.readerViewController(for: clonePane))
            let pendingPosition = ReadingPosition(pageIndex: 5, point: NSPoint(x: 29, y: 105))
            reader.testingScheduleReadingPositionWriteback(pendingPosition, for: cloneID)
            XCTAssertTrue(reader.testingHasPendingReadingPositionWriteback)

            NSApp.sendEvent(makeKeyEvent(characters: "\u{F703}", keyCode: 124,
                                        modifierFlags: [.command, .option], window: window))
            XCTAssertEqual(store.activeWorkspaceID(in: controller.windowID), workspaceIDs[1])
            XCTAssertTrue(store.sessions(in: controller.windowID).isEmpty)
            XCTAssertEqual(store.session(for: cloneID)?.lastReadPosition, pendingPosition)
            NSApp.sendEvent(makeKeyEvent(characters: "9", keyCode: 25,
                                        modifierFlags: [.command, .option], window: window))
            XCTAssertEqual(store.activeWorkspaceID(in: controller.windowID), workspaceIDs[8])
            XCTAssertTrue(delegate.validateMenuItem(ninthItem))
            XCTAssertEqual(ninthItem.state, .on)
            NSApp.sendEvent(makeKeyEvent(characters: "\u{F703}", keyCode: 124,
                                        modifierFlags: [.command, .option], window: window))
            XCTAssertEqual(store.activeWorkspaceID(in: controller.windowID), originalID)
            XCTAssertEqual(store.readerLayout(in: controller.windowID), layout)
            XCTAssertEqual(store.focusedPane(in: controller.windowID), clonePane)
            NSApp.sendEvent(makeKeyEvent(characters: "\u{F702}", keyCode: 123,
                                        modifierFlags: [.command, .option], window: window))
            XCTAssertEqual(store.activeWorkspaceID(in: controller.windowID), workspaceIDs[8])
            NSApp.sendEvent(makeKeyEvent(characters: "1", keyCode: 18,
                                        modifierFlags: [.command, .option], window: window))
            XCTAssertEqual(store.activeWorkspaceID(in: controller.windowID), originalID)
        }
    }

    private func exerciseAuxiliaryEditors() throws {
        let previousMenu = NSApp.mainMenu
        let store = makeIsolatedDocumentStore()
        let reader = MainWindowController(documentStore: store)
        let readerWindow = try XCTUnwrap(reader.window)
        let delegate = AppDelegate()
        let palette = RecentFilesPaletteController { _ in }
        let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                                styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        defer {
            if sheet.sheetParent != nil { readerWindow.endSheet(sheet) }
            sheet.orderOut(nil)
            settings.orderOut(nil)
            palette.close()
            reader.close()
            NSApp.mainMenu = previousMenu
        }
        let url = try TestPDFFixtures.makeLabeledPDF(named: "menu-editor", pageSizes: [NSSize(width: 612, height: 792)])
        _ = try store.open(documentAt: url)
        readerWindow.setContentSize(NSSize(width: 1400, height: 900))
        reader.showWindow(nil)
        readerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settle(readerWindow)
        XCTAssertTrue(reader.splitCurrentPDF(layout: .sideBySide))
        settle(readerWindow)
        delegate.installMenuForTesting(documentStore: store, controllers: [reader])
        let focus = store.focusedPane(in: reader.windowID)
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let focusItems = try [ShortcutCommand.focusPaneLeft, .focusPaneDown, .focusPaneUp, .focusPaneRight].map {
            try XCTUnwrap(find($0, in: menu))
        }
        XCTAssertTrue(focusItems.allSatisfy(\.isEnabled))

        palette.show(with: [url], relativeTo: readerWindow)
        let paletteWindow = try XCTUnwrap(palette.window)
        let queryEditor = try XCTUnwrap(paletteWindow.firstResponder as? NSTextView)
        try assertNativeControlEditing(queryEditor, in: paletteWindow, focusItems: focusItems)
        XCTAssertEqual(store.focusedPane(in: reader.windowID), focus)
        palette.close()

        let settingsEditor = NSTextView(frame: settings.contentView!.bounds)
        settings.contentView = settingsEditor
        settings.makeKeyAndOrderFront(nil)
        XCTAssertTrue(settings.makeFirstResponder(settingsEditor))
        try assertNativeControlEditing(settingsEditor, in: settings, focusItems: focusItems)
        XCTAssertEqual(store.focusedPane(in: reader.windowID), focus)
        settings.orderOut(nil)

        readerWindow.makeKeyAndOrderFront(nil)
        XCTAssertTrue(focusItems.allSatisfy(\.isEnabled))
        let sheetEditor = NSTextView(frame: sheet.contentView!.bounds)
        sheet.contentView = sheetEditor
        readerWindow.beginSheet(sheet)
        sheet.makeKey()
        XCTAssertTrue(sheet.makeFirstResponder(sheetEditor))
        try assertNativeControlEditing(sheetEditor, in: sheet, focusItems: focusItems)
        XCTAssertEqual(store.focusedPane(in: reader.windowID), focus)
        readerWindow.endSheet(sheet)
        sheet.orderOut(nil)
        readerWindow.makeKeyAndOrderFront(nil)
        XCTAssertTrue(focusItems.allSatisfy(\.isEnabled))
    }

    private func assertNativeControlEditing(_ editor: NSTextView, in window: NSWindow,
                                           focusItems: [NSMenuItem]) throws {
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(focusItems.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(focusItems.allSatisfy { $0.keyEquivalent.isEmpty })
        editor.string = "abc def"
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        NSApp.sendEvent(makeKeyEvent(characters: "\u{08}", keyCode: 4,
                                    charactersIgnoringModifiers: "h", modifierFlags: [.control], window: window))
        XCTAssertEqual(editor.string, "ab def")
        NSApp.sendEvent(makeKeyEvent(characters: "\u{0B}", keyCode: 40,
                                    charactersIgnoringModifiers: "k", modifierFlags: [.control], window: window))
        XCTAssertEqual(editor.string, "ab")
    }

    private func find(_ command: ShortcutCommand, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? ShortcutCommand == command { return item }
            if let submenu = item.submenu, let found = find(command, in: submenu) { return found }
        }
        return nil
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        window.layoutIfNeeded()
    }
}
