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

    func testLongDocumentAtMinimumWidthFillsAvailableColumns() {
        let available = CGSize(width: 1430, height: 893)
        let result = OverviewGridLayout.computeFitAll(
            .init(
                pageCount: 268,
                availableSize: available,
                pageAspect: 1.414,
                cellSpacing: 10,
                minCellWidth: 56,
                maxCellWidth: nil
            )
        )

        // floor((1430 + 10) / (56 + 10)) = 21. The previous no-fit
        // tie-break preferred 4 columns because 268 is divisible by 4,
        // leaving a narrow strip centered in a wide window.
        XCTAssertEqual(result.columns, 21)
        XCTAssertEqual(result.cellSize.width, 56, accuracy: 0.5)
        XCTAssertGreaterThan(result.contentSize.width / available.width, 0.9)
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

    // MARK: - visibleCellIndices

    private let gridGeometry = (
        cellSize: CGSize(width: 120, height: 170),
        spacing: CGFloat(10),
        origin: CGPoint(x: 210, y: 10)
    )

    func testVisibleCellIndicesCoversTopRowsAtScrollTop() {
        let indices = OverviewGridLayout.visibleCellIndices(
            pageCount: 60,
            columns: 3,
            cellSize: gridGeometry.cellSize,
            spacing: gridGeometry.spacing,
            origin: gridGeometry.origin,
            viewport: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        // Viewport spans rows 0...3 (stride 180 from y = 10).
        XCTAssertEqual(indices, Array(0..<12))
    }

    func testVisibleCellIndicesTracksMidDocumentViewport() {
        let indices = OverviewGridLayout.visibleCellIndices(
            pageCount: 60,
            columns: 3,
            cellSize: gridGeometry.cellSize,
            spacing: gridGeometry.spacing,
            origin: gridGeometry.origin,
            viewport: CGRect(x: 0, y: 1810, width: 800, height: 600)
        )
        // Visible y ∈ [1810, 2410) → rows 10...13.
        XCTAssertEqual(indices, Array(30..<42))
    }

    func testVisibleCellIndicesClampsToPageCountOnLastRow() {
        let indices = OverviewGridLayout.visibleCellIndices(
            pageCount: 20,
            columns: 3,
            cellSize: gridGeometry.cellSize,
            spacing: gridGeometry.spacing,
            origin: gridGeometry.origin,
            viewport: CGRect(x: 0, y: 1000, width: 800, height: 600)
        )
        // Rows 5...6; the last row only holds 2 of 3 cells.
        XCTAssertEqual(indices, [15, 16, 17, 18, 19])
    }

    func testVisibleCellIndicesReturnsEmptyOutsideGrid() {
        let above = OverviewGridLayout.visibleCellIndices(
            pageCount: 60,
            columns: 3,
            cellSize: gridGeometry.cellSize,
            spacing: gridGeometry.spacing,
            origin: gridGeometry.origin,
            viewport: CGRect(x: 0, y: -600, width: 800, height: 500)
        )
        let below = OverviewGridLayout.visibleCellIndices(
            pageCount: 60,
            columns: 3,
            cellSize: gridGeometry.cellSize,
            spacing: gridGeometry.spacing,
            origin: gridGeometry.origin,
            viewport: CGRect(x: 0, y: 4000, width: 800, height: 500)
        )
        XCTAssertEqual(above, [])
        XCTAssertEqual(below, [])
    }
}
