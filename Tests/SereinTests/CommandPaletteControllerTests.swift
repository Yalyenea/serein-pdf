import AppKit
import XCTest
@testable import Serein

@MainActor
final class CommandPaletteControllerTests: XCTestCase {
    func testPointerAndKeyboardShareOneHighlightAndExitClearsIt() throws {
        _ = NSApplication.shared
        var invoked: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invoked.append(command) }
        controller.show(commands: [.highlightSelection, .underlineSelection], bindings: [:], targetWindowID: nil, relativeTo: nil)
        defer { controller.dismiss() }
        let tiles = controller.testingTiles
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: try XCTUnwrap(controller.window).windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0
        ))
        func highlighted() -> [Int] {
            tiles.indices.filter { (tiles[$0].layer?.backgroundColor?.alpha ?? 0) > 0 }
        }
        XCTAssertEqual(highlighted(), [0])
        tiles[1].mouseEntered(with: event)
        XCTAssertEqual(highlighted(), [1])
        tiles[0].mouseEntered(with: event)
        tiles[1].mouseExited(with: event)
        XCTAssertEqual(highlighted(), [0])
        for _ in 0..<3 { tiles[0].updateTrackingAreas() }
        XCTAssertEqual(tiles[0].trackingAreas.count, 1)
        tiles[0].mouseExited(with: event)
        XCTAssertEqual(highlighted(), [])

        _ = controller.testingHandlePanelKeyEvent(makeKeyEvent(characters: "", keyCode: 124, window: controller.window))
        XCTAssertEqual(highlighted(), [0])
        _ = controller.testingHandlePanelKeyEvent(makeKeyEvent(characters: "", keyCode: 124, window: controller.window))
        XCTAssertEqual(highlighted(), [1])
        tiles[0].mouseExited(with: event)
        XCTAssertEqual(highlighted(), [1])
        tiles[0].mouseMoved(with: event)
        XCTAssertEqual(highlighted(), [0])
        _ = controller.testingHandlePanelKeyEvent(makeKeyEvent(characters: "", keyCode: 124, window: controller.window))
        tiles[1].mouseExited(with: event)
        XCTAssertEqual(highlighted(), [1])
        _ = controller.testingHandlePanelKeyEvent(makeReturnKeyEvent(in: try XCTUnwrap(controller.window)))
        XCTAssertEqual(invoked, [.underlineSelection])

        controller.show(commands: [.highlightSelection, .underlineSelection], bindings: [:], targetWindowID: nil, relativeTo: nil)
        let reopened = controller.testingTiles
        XCTAssertEqual(reopened.filter { ($0.layer?.backgroundColor?.alpha ?? 0) > 0 }.count, 1)
        reopened[1].mouseEntered(with: event)
        reopened[1].mouseExited(with: event)
        XCTAssertTrue(reopened.allSatisfy { ($0.layer?.backgroundColor?.alpha ?? 0) == 0 })
    }

    func testBuiltInChordSuffixInvokesCommandFromVisiblePalette() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        var invokedWindowIDs: [UUID?] = []
        let targetWindowID = UUID()
        let controller = CommandPaletteController { command, windowID in
            invokedCommands.append(command)
            invokedWindowIDs.append(windowID)
        }
        controller.show(
            commands: [.switchCurrentTheme, .openLibraryPDF],
            bindings: [:],
            targetWindowID: targetWindowID,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "o",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.openLibraryPDF])
        XCTAssertEqual(invokedWindowIDs, [targetWindowID])
    }

    func testCommandTSwitchesThemeInsteadOfCreatingABlankTab() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.switchCurrentTheme, .newBlankTab, .openLibraryPDF],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "t",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testCommandTChordIsConsumedEvenWhenThemeCommandIsHidden() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.newBlankTab],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "t",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testLocalMonitorSwallowsCommandTBeforeMenuDispatch() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.switchCurrentTheme, .newBlankTab],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        NSApp.sendEvent(
            makeKeyEvent(
                characters: "t",
                modifierFlags: [.command],
                window: controller.window
            )
        )

        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testTypingDoesNotFilterAndEnterInvokesHighlightedCommand() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.highlightSelection, .openLibraryPDF, .toggleReaderSplit],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        let commands = controller.testingCommands
        XCTAssertTrue(controller.testingHandlePanelKeyEvent(makeKeyEvent(characters: "x", modifierFlags: [], window: controller.window)))
        XCTAssertEqual(controller.testingCommands, commands)
        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeReturnKeyEvent(in: controller.window!)
            )
        )
        XCTAssertEqual(invokedCommands, [.highlightSelection])
    }

    func testCommandKClosesWithoutInvokingCommand() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "k",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testResigningKeyClosesWithoutRestoringParentWindow() {
        _ = NSApplication.shared
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = CommandPaletteController { _, _ in }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: parentWindow
        )
        XCTAssertTrue(controller.window?.delegate === controller)

        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: controller.window)
        )

        XCTAssertFalse(controller.window?.isVisible ?? true)
        XCTAssertFalse(parentWindow.isVisible)
    }

    func testClickingCommandTitleInvokesImmediately() throws {
        _ = NSApplication.shared
        var invoked: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invoked.append(command) }
        controller.show(commands: [.openLibraryPDF], bindings: [:], targetWindowID: nil, relativeTo: nil)
        defer { controller.dismiss() }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        func findTile(in view: NSView) -> NSView? {
            if view.identifier?.rawValue == "commandPalette.\(ShortcutCommand.openLibraryPDF.rawValue)" { return view }
            return view.subviews.lazy.compactMap { findTile(in: $0) }.first
        }
        let tile = try XCTUnwrap(findTile(in: content))
        let title = try XCTUnwrap(tile.subviews.first as? NSTextField)
        let point = NSPoint(x: title.bounds.midX, y: title.bounds.midY)
        let hit = content.hitTest(content.convert(point, from: title))
        XCTAssertTrue(hit === tile)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: title.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        hit?.mouseDown(with: event)
        XCTAssertEqual(invoked, [.openLibraryPDF])
        XCTAssertFalse(window.isVisible)
    }

    func testGridUsesTwoColumnsAndFitsShortContentWithoutSearch() throws {
        _ = NSApplication.shared
        let controller = CommandPaletteController { _, _ in }
        controller.show(commands: [.highlightSelection, .underlineSelection], bindings: [:], targetWindowID: nil, relativeTo: nil)
        defer { controller.dismiss() }
        let frames = controller.testingTileFrames
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
        XCTAssertGreaterThan(frames[1].minX, frames[0].maxX)
        XCTAssertLessThan(try XCTUnwrap(controller.window?.contentView?.frame.height), 100)
        func containsSearch(_ view: NSView) -> Bool {
            view is NSSearchField || view.subviews.contains(where: containsSearch)
        }
        XCTAssertFalse(containsSearch(try XCTUnwrap(controller.window?.contentView)))
    }

    func testAllCommandsReserveSpaceForScrollerAndUseSharedSymbols() throws {
        _ = NSApplication.shared
        let controller = CommandPaletteController { _, _ in }
        controller.show(commands: ShortcutCommand.allCases, bindings: AppConfiguration.default.shortcuts.bindings,
                        targetWindowID: nil, relativeTo: nil)
        defer { controller.dismiss() }
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: content))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
        let rightEdge = try XCTUnwrap(controller.testingTileFrames.map(\.maxX).max())
        XCTAssertGreaterThanOrEqual(document.bounds.maxX - rightEdge, 20)
        for tile in controller.testingTiles {
            let shortcuts = try XCTUnwrap(findDescendant(of: ShortcutSequenceView.self, in: tile))
            XCTAssertLessThanOrEqual(shortcuts.frame.maxX, tile.bounds.maxX - 8 + 0.01)
            func verifySymbols(_ view: NSView) {
                if let symbol = view as? NSImageView { XCTAssertNotNil(symbol.image) }
                view.subviews.forEach(verifySymbols)
            }
            verifySymbols(shortcuts)
        }
    }
}
