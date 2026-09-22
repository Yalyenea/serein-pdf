import AppKit
import XCTest
@testable import Serein

@MainActor
final class RecentWindowsPaletteControllerTests: XCTestCase {
    func testFilteringPreservesProvidedOrderAndEnterActivatesSelectedWindow() {
        _ = NSApplication.shared
        let first = RecentWindowsPaletteItem(windowID: UUID(), title: "Reading", documentSummary: "Alpha.pdf")
        let second = RecentWindowsPaletteItem(windowID: UUID(), title: "Notes", documentSummary: "Beta.pdf")
        var activated: UUID?
        let controller = RecentWindowsPaletteController(onActivateWindow: { activated = $0 }, onSplitWindow: { _, _ in XCTFail() })
        defer { controller.close() }
        controller.show(with: [first, second], relativeTo: nil)
        XCTAssertEqual(controller.testingHighlightedWindowID, first.windowID)
        controller.testingSetQuery("Beta")
        XCTAssertEqual(controller.testingHighlightedWindowID, second.windowID)
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))
        XCTAssertEqual(activated, second.windowID)
        XCTAssertFalse(controller.window?.isVisible == true)
    }

    func testSplitForwardsSourceWindowAndDirectionWithoutActivatingIt() {
        _ = NSApplication.shared
        let item = RecentWindowsPaletteItem(windowID: UUID(), title: "Reference", documentSummary: "Paper.pdf")
        var splits: [(UUID, ReaderSplitLayout)] = []
        let controller = RecentWindowsPaletteController(onActivateWindow: { _ in XCTFail() }, onSplitWindow: { splits.append(($0, $1)) })
        defer { controller.close() }
        let cases: [(NSEvent.ModifierFlags, ReaderSplitLayout)] = [([.option], .sideBySide), ([.option, .shift], .stacked)]
        for (flags, expected) in cases {
            controller.show(with: [item], relativeTo: nil)
            XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(
                characters: "\r", keyCode: 36, modifierFlags: flags, window: controller.window
            )))
            XCTAssertEqual(splits.last?.0, item.windowID)
            XCTAssertEqual(splits.last?.1, expected)
        }
    }

    func testWindowWithoutPDFRejectsSplitAndRemainsSelectable() {
        _ = NSApplication.shared
        let item = RecentWindowsPaletteItem(windowID: UUID(), title: "Empty", documentSummary: "No PDF", canSplit: false)
        var activated: UUID?
        let controller = RecentWindowsPaletteController(onActivateWindow: { activated = $0 }, onSplitWindow: { _, _ in XCTFail() })
        defer { controller.close() }
        controller.show(with: [item], relativeTo: nil)
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(
            characters: "\r", keyCode: 36, modifierFlags: [.option], window: controller.window
        )))
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.testingFooter.contains("no PDF"))
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))
        XCTAssertEqual(activated, item.windowID)
    }
}
