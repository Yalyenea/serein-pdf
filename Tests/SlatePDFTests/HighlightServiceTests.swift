import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

@MainActor
final class HighlightServiceTests: XCTestCase {
    func testDefaultHighlightColorIsPink() {
        XCTAssertEqual(HighlightColor.default, .pink)
    }

    func testAllPaletteColorsAreAvailable() {
        XCTAssertEqual(Set(HighlightColor.allCases), [.pink, .yellow, .green])
    }

    func testHighlightColorHasDistinctMenuTitles() {
        let titles = HighlightColor.allCases.map(\.menuTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testSelectionContainsTextReturnsFalseForNilSelection() {
        XCTAssertFalse(HighlightService.selectionContainsText(nil))
    }

    func testDefaultColorMatchesPinkPalette() {
        XCTAssertEqual(
            HighlightService.defaultColor.cgColor.components,
            HighlightColor.pink.nsColor.cgColor.components
        )
    }
}
