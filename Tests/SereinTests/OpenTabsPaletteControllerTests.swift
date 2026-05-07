import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class OpenTabsPaletteControllerTests: XCTestCase {
    func testPanelStartsWithCollectionFocused() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let controller = OpenTabsPaletteController { _, _ in }
        controller.show(
            with: [first],
            activeSessionID: first.id,
            primarySessionID: first.id,
            secondarySessionID: nil,
            focusedPane: .primary,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingCollectionViewIsFirstResponder)
        XCTAssertEqual(controller.testingHighlightedIndex, 0)
    }

    func testVimKeysMoveSelectionAcrossGrid() throws {
        _ = NSApplication.shared
        let sessions = try (0..<6).map { index in
            try makeSession(title: "PDF \(index)", path: "/tmp/\(index).pdf")
        }
        let controller = OpenTabsPaletteController { _, _ in }
        controller.show(
            with: sessions,
            activeSessionID: sessions[0].id,
            primarySessionID: sessions[0].id,
            secondarySessionID: nil,
            focusedPane: .primary,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "l", keyCode: 37, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertEqual(controller.testingSelectedItemCount, 1)

        let columnCount = controller.testingCurrentColumnCount
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "j", keyCode: 38, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, min(sessions.count - 1, 1 + columnCount))
        XCTAssertEqual(controller.testingSelectedItemCount, 1)

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "h", keyCode: 4, window: controller.window)))
        XCTAssertEqual(controller.testingHighlightedIndex, max((controller.testingHighlightedIndex ?? 0) / columnCount * columnCount, min(sessions.count - 1, columnCount)))
        XCTAssertEqual(controller.testingSelectedItemCount, 1)
    }

    func testEnterActivatesHighlightedSession() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: Bool?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            with: [first, second],
            activeSessionID: first.id,
            primarySessionID: first.id,
            secondarySessionID: nil,
            focusedPane: .primary,
            relativeTo: nil
        )
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "l", keyCode: 37, window: controller.window)))
        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))

        XCTAssertEqual(activatedSessionID, second.id)
        XCTAssertEqual(activatedAlternatePane, false)
    }

    func testOptionEnterActivatesHighlightedSessionInAlternatePane() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: Bool?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            with: [first, second],
            activeSessionID: first.id,
            primarySessionID: first.id,
            secondarySessionID: nil,
            focusedPane: .primary,
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
        XCTAssertEqual(activatedAlternatePane, true)
    }

    func testClickActivatesItem() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")
        var activatedSessionID: UUID?
        var activatedAlternatePane: Bool?
        let controller = OpenTabsPaletteController { sessionID, alternatePane in
            activatedSessionID = sessionID
            activatedAlternatePane = alternatePane
        }
        controller.show(
            with: [first, second],
            activeSessionID: first.id,
            primarySessionID: first.id,
            secondarySessionID: nil,
            focusedPane: .primary,
            relativeTo: nil
        )
        defer { controller.close() }

        controller.testingClickItem(at: 1)

        XCTAssertEqual(activatedSessionID, second.id)
        XCTAssertEqual(activatedAlternatePane, false)
    }

    func testEscapeClosesPanelWithoutActivating() throws {
        _ = NSApplication.shared
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        var activatedSessionID: UUID?
        let controller = OpenTabsPaletteController { sessionID, _ in
            activatedSessionID = sessionID
        }
        controller.show(
            with: [first],
            activeSessionID: first.id,
            primarySessionID: first.id,
            secondarySessionID: nil,
            focusedPane: .primary,
            relativeTo: nil
        )

        XCTAssertTrue(controller.testingHandlePaletteKeyEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: controller.window)))

        XCTAssertNil(activatedSessionID)
        XCTAssertFalse(controller.testingWindowIsVisible)
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

    private func makeKeyEvent(
        characters: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        window: NSWindow?
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
