import AppKit
import XCTest
@testable import Serein

@MainActor
final class RecentFilesPaletteControllerTests: XCTestCase {
    func testMarkedQueryTextRetainsEnterAndEscapeForInputMethod() throws {
        _ = NSApplication.shared
        let controller = RecentFilesPaletteController { _ in XCTFail("Composing text must not open a PDF") }
        defer { controller.close() }
        controller.show(with: [URL(fileURLWithPath: "/tmp/recent.pdf")], relativeTo: nil)
        let editor = try XCTUnwrap(controller.window?.firstResponder as? NSTextView)
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        for (characters, keyCode) in [("\r", UInt16(36)), ("\u{1b}", UInt16(53))] {
            XCTAssertFalse(controller.testingHandlePanelKeyEvent(
                makeKeyEvent(characters: characters, keyCode: keyCode, window: controller.window)
            ))
        }
        XCTAssertFalse(controller.testingHandleQueryCommand(#selector(NSResponder.insertNewline(_:))))
        XCTAssertFalse(controller.testingHandleQueryCommand(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(controller.window?.isVisible == true)
    }

    func testReturningToQueryAppendsAfterEntireUnicodeText() {
        _ = NSApplication.shared
        let controller = RecentFilesPaletteController { _ in }
        defer { controller.close() }
        controller.show(with: [URL(fileURLWithPath: "/tmp/😀a.pdf")], relativeTo: nil)
        controller.testingSetQuery("😀")
        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.testingHandleResultsKeyEvent(
            makeKeyEvent(characters: "a", keyCode: 0, window: controller.window)
        ))
        XCTAssertEqual(controller.testingQuery, "😀a")
    }

    func testEscapeFromReaderClosesUnfocusedRecentPanelAndThenReturnsToReader() throws {
        _ = NSApplication.shared
        let reader = ReaderShortcutWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                          styleMask: [.titled], backing: .buffered, defer: false)
        var readerKeys: [UInt16] = []
        reader.plainShortcutHandler = { event, _ in readerKeys.append(event.keyCode); return true }
        let controller = RecentFilesPaletteController { _ in XCTFail("Escape must not open a PDF") }
        defer { controller.close(); reader.orderOut(nil) }
        for _ in 0..<2 {
            controller.show(with: [], relativeTo: reader)
            controller.window?.resignKey()
            reader.makeKeyAndOrderFront(nil)
            XCTAssertFalse(try XCTUnwrap(controller.window).isKeyWindow)
            XCTAssertTrue(controller.window?.isVisible == true)

            NSApp.sendEvent(makeKeyEvent(characters: "x", keyCode: 7, window: reader))
            XCTAssertEqual(readerKeys.last, 7)
            XCTAssertTrue(controller.window?.isVisible == true)

            let before = readerKeys.count
            NSApp.sendEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: reader))
            XCTAssertFalse(controller.window?.isVisible == true)
            XCTAssertEqual(readerKeys.count, before)

            NSApp.sendEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: reader))
            XCTAssertEqual(readerKeys.count, before + 1)
            XCTAssertEqual(readerKeys.last, 53)
        }
    }

    func testEscapeClosesPanelThroughKeyEquivalentWithEitherFocus() throws {
        _ = NSApplication.shared
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        defer { controller.close() }
        for focusList in [false, true] {
            controller.show(with: [URL(fileURLWithPath: "/tmp/recent-escape.pdf")], relativeTo: nil)
            if focusList {
                XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
                XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
                _ = controller.testingHandleResultsKeyEvent(makeKeyEvent(characters: " ", keyCode: 49, window: controller.window))
            }
            let window = try XCTUnwrap(controller.window)
            XCTAssertTrue(window.performKeyEquivalent(with: makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: window)))
            XCTAssertFalse(window.isVisible)
            XCTAssertTrue(openedURLs.isEmpty)
        }
        controller.show(with: [], relativeTo: nil)
        let window = try XCTUnwrap(controller.window)
        window.makeFirstResponder(window.contentView)
        window.cancelOperation(nil)
        XCTAssertFalse(window.isVisible)
    }

    func testThemeRefreshPreservesQueryAndMarkedFilesAcrossPanelReuse() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        let previousTheme = ThemeManager.shared.selection
        defer {
            app.appearance = previousAppearance
            ThemeManager.shared.apply(light: previousTheme.light, dark: previousTheme.dark)
        }
        app.appearance = NSAppearance(named: .aqua)
        ThemeManager.shared.apply(light: .normal, dark: .normal)
        let first = URL(fileURLWithPath: "/tmp/alpha-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/alpha-second.pdf")
        let controller = RecentFilesPaletteController { _ in }
        defer { controller.close() }
        controller.show(with: [first, second], relativeTo: nil)
        controller.testingSetQuery("alpha")
        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.testingHandleResultsKeyEvent(
            makeKeyEvent(characters: " ", keyCode: 49, window: controller.window)
        ))
        let content = try XCTUnwrap(controller.window?.contentView)
        let originalBackground = try XCTUnwrap(content.layer?.backgroundColor)

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        controller.refreshChromeColors()

        XCTAssertNotEqual(content.layer?.backgroundColor, originalBackground)
        XCTAssertEqual(controller.testingQuery, "alpha")
        XCTAssertEqual(controller.testingSelectedURLs, [first])
        XCTAssertEqual(controller.testingHighlightedIndex, 0)
        let table = try XCTUnwrap(findDescendant(of: NSTableView.self, in: content))
        XCTAssertTrue(table.rowView(atRow: 0, makeIfNecessary: true) is ThemedTableRowView)

        controller.close()
        controller.show(with: [second], relativeTo: nil)
        XCTAssertEqual(controller.testingQuery, "")
        XCTAssertTrue(controller.testingSelectedURLs.isEmpty)
        XCTAssertEqual(table.numberOfRows, 1)
    }

    func testEnterFromPanelOpensHighlightedURL() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        controller.show(with: [first, second], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)
            )
        )
        XCTAssertEqual(openedURLs, [first])
    }

    func testKeypadEnterFromPanelOpensHighlightedURL() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        controller.show(with: [first], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(characters: "\r", keyCode: 76, window: controller.window)
            )
        )
        XCTAssertEqual(openedURLs, [first])
    }

    func testEnterFromPanelOpensSelectedURLsInFilteredOrder() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/alpha-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/alpha-second.pdf")
        let third = URL(fileURLWithPath: "/tmp/beta.pdf")
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }
        controller.testingSetQuery("alpha")

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(
            controller.testingHandleResultsKeyEvent(
                makeKeyEvent(characters: " ", keyCode: 49, window: controller.window)
            )
        )
        XCTAssertTrue(
            controller.testingHandleResultsKeyEvent(
                makeKeyEvent(characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, window: controller.window)
            )
        )
        XCTAssertTrue(
            controller.testingHandleResultsKeyEvent(
                makeKeyEvent(characters: " ", keyCode: 49, window: controller.window)
            )
        )

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)
            )
        )
        XCTAssertEqual(openedURLs, [first, second])
    }

    func testEnterFromPanelWithEmptyResultsDoesNotOpen() {
        _ = NSApplication.shared
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        controller.show(with: [], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)
            )
        )
        XCTAssertEqual(openedURLs, [])
    }

    func testFirstDownArrowFromRecentHistoryOnlyEntersNavigationMode() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(controller.testingInteractionMode, .navigatingResults)
        XCTAssertEqual(controller.testingHighlightedIndex, 0)
        XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
    }

    func testFirstDownArrowAfterSearchOnlyEntersNavigationMode() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/alpha-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/alpha-second.pdf")
        let third = URL(fileURLWithPath: "/tmp/beta.pdf")
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }
        controller.testingSetQuery("alpha")

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(controller.testingInteractionMode, .navigatingResults)
        XCTAssertEqual(controller.testingHighlightedIndex, 0)
        XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
    }

    func testSecondDownArrowInNavigationMovesToNextRow() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")
        var openedURLs: [URL] = []
        let controller = RecentFilesPaletteController { openedURLs = $0 }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }

        let downEvent = makeKeyEvent(characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, window: controller.window)

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.testingHandleResultsKeyEvent(downEvent))
        XCTAssertEqual(controller.testingInteractionMode, .navigatingResults)
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertTrue(controller.window?.isVisible == true)
    }

    func testSpaceKeepsCurrentHighlightAndDoesNotReturnToQuery() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(
            controller.testingHandleResultsKeyEvent(
                makeKeyEvent(characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, window: controller.window)
            )
        )
        let spaceEvent = makeKeyEvent(characters: " ", keyCode: 49, window: controller.window)

        XCTAssertTrue(controller.testingHandleResultsKeyEvent(spaceEvent))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertEqual(controller.testingSelectedURLs, [second])
        XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
        XCTAssertEqual(controller.testingQuery, "")

        XCTAssertTrue(controller.testingHandleResultsKeyEvent(spaceEvent))
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
        XCTAssertEqual(controller.testingSelectedURLs, [])
        XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
        XCTAssertEqual(controller.testingQuery, "")
    }

    func testEnteringNavigationMovesFocusToResultsTable() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.testingResultsTableIsFirstResponder)
        XCTAssertFalse(controller.testingQueryFieldIsFirstResponder)
    }

    func testPrintableKeyFromNavigationReturnsToQueryEditingAndAppendsQuery() {
        _ = NSApplication.shared
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second], relativeTo: nil)
        defer { controller.close() }

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        let textEvent = makeKeyEvent(characters: "a", keyCode: 0, window: controller.window)

        XCTAssertTrue(controller.testingHandleResultsKeyEvent(textEvent))
        XCTAssertEqual(controller.testingInteractionMode, .editingQuery)
        XCTAssertEqual(controller.testingQuery, "a")
        XCTAssertTrue(controller.testingQueryFieldIsFirstResponder)
    }

}
