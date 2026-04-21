import AppKit
import XCTest
@testable import SlatePDF

@MainActor
final class RecentFilesPaletteControllerTests: XCTestCase {
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

    private func makeKeyEvent(characters: String, keyCode: UInt16, window: NSWindow?) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
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
