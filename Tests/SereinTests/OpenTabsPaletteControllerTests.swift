import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class OpenTabsPaletteControllerTests: XCTestCase {
    func testPanelStartsWithListFocused() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let controller = OpenTabsPaletteController { _, _ in }
        controller.show(
            items: [OpenTabsPaletteItem(session: first, isActive: true)],
            activationMode: .explicitSelection,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingTableIsFirstResponder)
        XCTAssertEqual(controller.testingHighlightedIndex, 0)
    }

    func testVimKeysMoveSelectionThroughList() throws {
        _ = NSApplication.shared
        let sessions = try (0..<6).map { index in
            try makeSession(title: "PDF \(index)", path: "/tmp/\(index).pdf")
        }
        let controller = OpenTabsPaletteController { _, _ in }
        controller.show(
            items: sessions.map { OpenTabsPaletteItem(session: $0, isActive: $0.id == sessions[0].id) },
            activationMode: .explicitSelection,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "l", keyCode: 37, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertEqual(controller.testingSelectedItemCount, 1)

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "j", keyCode: 38, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, 2)
        XCTAssertEqual(controller.testingSelectedItemCount, 1)

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "h", keyCode: 4, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertEqual(controller.testingSelectedItemCount, 1)
    }

    func testEnterActivatesHighlightedSession() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: ReaderSplitLayout?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            items: [first, second].map { OpenTabsPaletteItem(session: $0, isActive: $0.id == first.id) },
            activationMode: .explicitSelection,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "l", keyCode: 37, window: controller.window)))
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))

        XCTAssertEqual(activatedSessionID, second.id)
        XCTAssertNil(activatedAlternatePane)
    }

    func testOptionEnterActivatesHighlightedSessionInAlternatePane() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: ReaderSplitLayout?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            items: [first, second].map { OpenTabsPaletteItem(session: $0, isActive: $0.id == first.id) },
            activationMode: .explicitSelection,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "l", keyCode: 37, window: controller.window)))
        XCTAssertTrue(
            controller.testingHandlePaletteKeyEvent(
                makeKeyEvent(characters: "\r", keyCode: 36, modifierFlags: [.option], window: controller.window)
            )
        )

        XCTAssertEqual(activatedSessionID, second.id)
        XCTAssertEqual(activatedAlternatePane, .sideBySide)
    }

    func testClickActivatesItem() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: ReaderSplitLayout?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            items: [first, second].map { OpenTabsPaletteItem(session: $0, isActive: $0.id == first.id) },
            activationMode: .explicitSelection,
            relativeTo: nil
        )
        defer { controller.close() }

        controller.testingClickItem(at: 1)

        XCTAssertEqual(activatedSessionID, second.id)
        XCTAssertNil(activatedAlternatePane)
    }

    func testEscapeClosesPanelWithoutActivating() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        var activatedSessionID: UUID?
        let controller = OpenTabsPaletteController { sessionID, _ in
            activatedSessionID = sessionID
        }
        controller.show(
            items: [OpenTabsPaletteItem(session: first, isActive: true)],
            activationMode: .explicitSelection,
            relativeTo: nil
        )

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: controller.window)))

        XCTAssertNil(activatedSessionID)
        XCTAssertFalse(controller.testingWindowIsVisible)
    }

    func testHeldControlCyclesFrozenMRUAndCommitsOnlyOnRelease() throws {
        _ = NSApplication.shared
        let sessions = try (0..<3).map { try makeSession(title: "PDF \($0)", path: "/tmp/\($0).pdf") }
        let items = sessions.enumerated().map {
            OpenTabsPaletteItem(session: $0.element, isActive: $0.offset == 0, workspaceName: "Workspace \($0.offset)")
        }
        var activatedIDs: [UUID] = []
        let controller = OpenTabsPaletteController(modifierFlags: { [.control] }) { sessionID, _ in activatedIDs.append(sessionID) }
        controller.show(items: items, activationMode: .heldControl(reverse: false), relativeTo: nil)
        defer { controller.close() }
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertTrue(activatedIDs.isEmpty)

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(
            characters: "\t", keyCode: 48, modifierFlags: [.control], window: controller.window
        )))
        XCTAssertEqual(controller.testingHighlightedIndex, 2)
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(
            characters: "\t", keyCode: 48, modifierFlags: [.control, .shift], window: controller.window
        )))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(
            characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125,
            modifierFlags: [.control], window: controller.window
        )))
        XCTAssertEqual(controller.testingHighlightedIndex, 2)
        XCTAssertEqual(controller.testingItems, items)
        XCTAssertTrue(activatedIDs.isEmpty)

        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [.control], window: controller.window))
        XCTAssertTrue(activatedIDs.isEmpty)
        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [], window: controller.window))
        XCTAssertEqual(activatedIDs, [sessions[2].id])
        XCTAssertFalse(controller.testingWindowIsVisible)
        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [], window: controller.window))
        XCTAssertEqual(activatedIDs.count, 1)
    }

    func testEscapeCancelsHeldControlAndExplicitModeIgnoresRelease() throws {
        _ = NSApplication.shared
        let session = try makeSession(title: "PDF", path: "/tmp/cancel.pdf")
        let items = [OpenTabsPaletteItem(session: session, isActive: true)]
        let controller = OpenTabsPaletteController(modifierFlags: { [.control] }) { _, _ in XCTFail("Must not activate") }
        defer { controller.close() }
        controller.show(items: items, activationMode: .heldControl(reverse: false), relativeTo: nil)
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(
            characters: "\u{1b}", keyCode: 53, modifierFlags: [.control], window: controller.window
        )))
        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [], window: controller.window))
        XCTAssertFalse(controller.testingWindowIsVisible)

        controller.show(items: items, activationMode: .explicitSelection, relativeTo: nil)
        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [], window: controller.window))
        XCTAssertTrue(controller.testingWindowIsVisible)
    }

    func testHeldControlAlreadyReleasedWhenPanelAppearsActivatesImmediately() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "Current", path: "/tmp/current.pdf")
        let previous = try makeSession(title: "Previous", path: "/tmp/previous.pdf")
        let items = [first, previous].map { OpenTabsPaletteItem(session: $0, isActive: $0.id == first.id) }
        var activatedIDs: [UUID] = []
        let controller = OpenTabsPaletteController(modifierFlags: { [] }) { sessionID, _ in activatedIDs.append(sessionID) }
        defer { controller.close() }

        controller.show(items: items, activationMode: .heldControl(reverse: false), relativeTo: nil)

        XCTAssertEqual(activatedIDs, [previous.id])
        XCTAssertFalse(controller.testingWindowIsVisible)
        controller.testingHandleFlagsChanged(makeFlagsEvent(modifiers: [], window: controller.window))
        XCTAssertEqual(activatedIDs, [previous.id])
    }

    func testConfiguredSplitHintsFitPanelInBothActivationModes() throws {
        _ = NSApplication.shared
        let session = try makeSession(title: "Paper", path: "/tmp/footer.pdf")
        let controller = OpenTabsPaletteController(modifierFlags: { [.control] }) { _, _ in }
        defer { controller.close() }
        let right = KeyboardShortcut(key: "return", modifiers: [.command, .control, .option])
        let down = KeyboardShortcut(key: "return", modifiers: [.command, .control, .option, .shift])
        let shortcuts: [(KeyboardShortcut?, KeyboardShortcut?)] = [
            (KeyboardShortcut(key: "return", modifiers: [.option]), KeyboardShortcut(key: "return", modifiers: [.option, .shift])),
            (right, down),
            (nil, nil),
        ]
        for (right, down) in shortcuts {
            controller.configureSplitShortcuts(right: right, down: down)
            for mode: OpenTabsPaletteActivationMode in [.explicitSelection, .heldControl(reverse: false)] {
                controller.show(items: [OpenTabsPaletteItem(session: session, isActive: true)], activationMode: mode, relativeTo: nil)
                let content = try XCTUnwrap(controller.window?.contentView)
                content.layoutSubtreeIfNeeded()
                let footer = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.contains("Esc  Cancel") })
                XCTAssertEqual(footer.stringValue.contains("Split right"), right != nil)
                XCTAssertEqual(footer.stringValue.contains("Split below"), down != nil)
                if let right { XCTAssertTrue(footer.stringValue.contains(right.displayString)) }
                if let down { XCTAssertTrue(footer.stringValue.contains(down.displayString)) }
                XCTAssertLessThanOrEqual(footer.fittingSize.width, content.bounds.width - 40)
                XCTAssertLessThanOrEqual(footer.frame.maxX, content.bounds.maxX - 20)
                controller.close()
            }
        }
    }

    private func makeFlagsEvent(modifiers: NSEvent.ModifierFlags, window: NSWindow?) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
                        timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
                        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59)!
    }

    private func makeSession(title: String, path: String) throws -> DocumentSession {
        DocumentSession(
            url: URL(fileURLWithPath: path),
            title: title,
            pdfDocument: try makePDFDocument(),
            currentPageIndex: 0
        )
    }

    private func makePDFDocument() throws -> PDFDocument {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 260))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        document.insert(page, at: 0)
        return document
    }

}
