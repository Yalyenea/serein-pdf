import AppKit
import XCTest
@testable import Serein

@MainActor
final class RecentFilesPaletteControllerTests: XCTestCase {
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
        let controller = RecentFilesPaletteController { _ in }
        controller.show(with: [first, second, third], relativeTo: nil)
        defer { controller.close() }

        let downEvent = makeKeyEvent(characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, window: controller.window)

        XCTAssertTrue(controller.testingHandleQueryCommand(#selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.testingHandleResultsKeyEvent(downEvent))
        XCTAssertEqual(controller.testingInteractionMode, .navigatingResults)
        XCTAssertEqual(controller.testingHighlightedIndex, 1)
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
