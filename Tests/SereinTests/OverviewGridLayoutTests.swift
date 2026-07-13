import XCTest
@testable import Serein

final class OverviewGridLayoutTests: XCTestCase {
    func testSinglePageFillsViewportPreservingAspect() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 1,
                availableSize: CGSize(width: 800, height: 1000),
                pageAspect: 1.414,
                cellSpacing: 0,
                minCellWidth: 48,
                maxCellWidth: nil
            )
        )

        XCTAssertEqual(result.columns, 1)
        XCTAssertTrue(result.fitsWithoutScroll)
        // Height-limited: 1000 / 1.414 ≈ 707
        XCTAssertEqual(result.cellSize.width, 1000 / 1.414, accuracy: 1)
    }

    func testNinePagesUsesThreeByThreeWhenSquareViewport() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 9,
                availableSize: CGSize(width: 900, height: 1200),
                pageAspect: 1.414,
                cellSpacing: 0,
                minCellWidth: 48,
                maxCellWidth: nil
            )
        )

        XCTAssertEqual(result.columns, 3)
        XCTAssertTrue(result.fitsWithoutScroll)
        XCTAssertEqual(result.cellSize.width, 1200 / 3 / 1.414, accuracy: 1)
    }

    func testWideViewportPrefersMoreColumns() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 12,
                availableSize: CGSize(width: 1600, height: 500),
                pageAspect: 1.414,
                cellSpacing: 0,
                minCellWidth: 48,
                maxCellWidth: nil
            )
        )

        XCTAssertGreaterThanOrEqual(result.columns, 6)
        XCTAssertTrue(result.fitsWithoutScroll)
        XCTAssertGreaterThan(result.cellSize.width, 48)
    }

    func testTallViewportPrefersFewerColumns() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 12,
                availableSize: CGSize(width: 400, height: 1600),
                pageAspect: 1.414,
                cellSpacing: 0,
                minCellWidth: 48,
                maxCellWidth: nil
            )
        )

        XCTAssertLessThanOrEqual(result.columns, 4)
        XCTAssertTrue(result.fitsWithoutScroll)
    }

    func testTwentyEightPagesFillsCommonDesktopWindowWithoutArtificialCap() {
        let available = CGSize(width: 1400, height: 900)
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 28,
                availableSize: available,
                pageAspect: 1.414,
                cellSpacing: 10,
                minCellWidth: 56,
                maxCellWidth: nil
            )
        )

        XCTAssertTrue(result.fitsWithoutScroll)
        // Without the old 360 cap, cells should grow well past the previous default 140.
        XCTAssertGreaterThan(result.cellSize.width, 140)
        let usage = (result.contentSize.width * result.contentSize.height)
            / (available.width * available.height)
        XCTAssertGreaterThan(usage, 0.65)
    }

    func testTinyViewportClampsToMinWidthAndAllowsScroll() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 100,
                availableSize: CGSize(width: 200, height: 200),
                pageAspect: 1.414,
                cellSpacing: 8,
                minCellWidth: 48,
                maxCellWidth: nil
            )
        )

        XCTAssertEqual(result.cellSize.width, 48, accuracy: 0.5)
        XCTAssertFalse(result.fitsWithoutScroll)
    }

    func testManualColumnsRespectsAvailableWidth() {
        let columns = OverviewGridLayout.columnsForManualWidth(
            pageCount: 30,
            availableWidth: 800,
            cellWidth: 140,
            cellSpacing: 8
        )
        // floor((800+8)/(140+8)) = floor(808/148) = 5
        XCTAssertEqual(columns, 5)
    }

    func testManualColumnsNeverExceedPageCount() {
        let columns = OverviewGridLayout.columnsForManualWidth(
            pageCount: 2,
            availableWidth: 2000,
            cellWidth: 80,
            cellSpacing: 8
        )
        XCTAssertEqual(columns, 2)
    }

    func testZeroPageCountStillProducesValidLayout() {
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 0,
                availableSize: CGSize(width: 800, height: 600)
            )
        )
        XCTAssertEqual(result.columns, 1)
        XCTAssertGreaterThan(result.cellSize.width, 0)
    }
}
