import XCTest
@testable import SlatePDF

final class RecentFilesPaletteStateTests: XCTestCase {
    func testFilteringMatchesTitleAndPath() {
        let alpha = URL(fileURLWithPath: "/tmp/Reading/Alpha-Paper.pdf")
        let beta = URL(fileURLWithPath: "/tmp/Notes/BetaSummary.pdf")
        var state = RecentFilesPaletteState(recentURLs: [alpha, beta])

        state.appendToQuery("alpha")
        XCTAssertEqual(state.filteredItems.map(\.url), [alpha])

        state = RecentFilesPaletteState(recentURLs: [alpha, beta])
        state.appendToQuery("notes")
        XCTAssertEqual(state.filteredItems.map(\.url), [beta])
    }

    func testSpaceLikeToggleSelectionKeepsFilteredOrderForOpenTargets() {
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")
        var state = RecentFilesPaletteState(recentURLs: [first, second, third])

        state.toggleSelectionForHighlightedItem()
        state.moveHighlight(delta: 2)
        state.toggleSelectionForHighlightedItem()

        XCTAssertEqual(state.selectedURLs, [first, third])
        XCTAssertEqual(state.openTargets(), [first, third])
    }

    func testOpenTargetsFallsBackToHighlightedItemWhenNoMultiSelect() {
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        var state = RecentFilesPaletteState(recentURLs: [first, second])

        state.moveHighlight(delta: 1)

        XCTAssertEqual(state.openTargets(), [second])
    }

    func testToggleHelpFlipsVisibility() {
        var state = RecentFilesPaletteState(recentURLs: [])

        XCTAssertFalse(state.isHelpVisible)
        state.toggleHelp()
        XCTAssertTrue(state.isHelpVisible)
        state.toggleHelp()
        XCTAssertFalse(state.isHelpVisible)
    }

    func testFilteringDropsSelectionsThatAreNoLongerVisible() {
        let first = URL(fileURLWithPath: "/tmp/alpha.pdf")
        let second = URL(fileURLWithPath: "/tmp/beta.pdf")
        var state = RecentFilesPaletteState(recentURLs: [first, second])

        state.toggleSelectionForHighlightedItem()
        state.moveHighlight(delta: 1)
        state.toggleSelectionForHighlightedItem()
        state.query = "beta"

        XCTAssertEqual(state.filteredItems.map(\.url), [second])
        XCTAssertEqual(state.selectedURLs, [second])
    }

    func testEmptyStateHasNoHighlightOrOpenTargets() {
        let state = RecentFilesPaletteState(recentURLs: [])

        XCTAssertTrue(state.filteredItems.isEmpty)
        XCTAssertNil(state.highlightedIndex)
        XCTAssertEqual(state.openTargets(), [])
    }
}
