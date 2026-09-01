import AppKit
import PDFKit
import XCTest
@testable import Serein

/// Lazy thumbnail pipeline for the all-pages overview: only the viewport
/// neighborhood rasterizes, offscreen bitmaps are released, and leaving the
/// overview drops everything.
@MainActor
final class OverviewGridViewTests: XCTestCase {
    private let viewportSize = CGSize(width: 800, height: 600)

    func testOverviewRendersOnlyViewportNeighborhoodInsteadOfWholeDocument() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)

        grid.testingFlushRenders()

        // 3 columns × stride 180: viewport rows 0...3, one-screen prefetch
        // extends to row 6 → indices 0...20 out of 60 pages.
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...20))
        XCTAssertTrue(grid.testingPendingRenderIndices.isEmpty)
    }

    func testOverviewRendersAllPagesWhenWholeGridFits() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 6)

        grid.testingFlushRenders()

        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0..<6))
    }

    func testScrollingRendersNewNeighborhoodAndReleasesFarPages() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...20))

        // Viewport y ∈ [1810, 2410): visible rows 10...13, buffered rows 6...16.
        grid.testingScroll(to: CGRect(origin: CGPoint(x: 0, y: 1810), size: viewportSize))
        grid.testingFlushRenders()

        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(18...50))
    }

    func testScrollingBackRestoresPagesFromCacheWithoutRerendering() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        grid.testingScroll(to: CGRect(origin: CGPoint(x: 0, y: 1810), size: viewportSize))
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(18...50))

        // Back to the top: cached pages reappear synchronously, no rasterization.
        grid.testingScroll(to: CGRect(origin: .zero, size: viewportSize))
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...20))
        XCTAssertTrue(grid.testingPendingRenderIndices.isEmpty)
    }

    func testScrollingEntireGridKeepsLiveThumbnailsBounded() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()

        // Walk the viewport through every row of the grid. At no point may
        // more than the viewport neighborhood hold a bitmap, no matter how
        // many pages have been visited.
        let stride: CGFloat = 180
        var maxLive = 0
        var y: CGFloat = 0
        let maxY = CGFloat(20) * stride + 20
        while y <= maxY {
            grid.testingScroll(to: CGRect(origin: CGPoint(x: 0, y: y), size: viewportSize))
            grid.testingFlushRenders()
            maxLive = max(maxLive, grid.testingThumbnailImageIndices.count)
            y += viewportSize.height
        }

        // 800x600 viewport, 3 columns: visible 4 rows plus a one-screen buffer
        // on each side ≈ 11 rows × 3 = 33 cells — far below the 60-page total.
        XCTAssertLessThanOrEqual(maxLive, 36)
        XCTAssertFalse(grid.testingThumbnailImageIndices.isEmpty)
    }

    func testZoomingReRendersOnlyVisibleCellsAtNewSize() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...20))

        grid.applyLayout(columns: 2, cellSize: CGSize(width: 240, height: 340))
        grid.testingFlushRenders()

        // 2 columns × stride 350: buffered rows 0...3 → indices 0...7.
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...7))
        for index in 0...7 {
            XCTAssertEqual(
                grid.testingThumbnailPointSize(at: index),
                CGSize(width: 240, height: 340)
            )
        }
    }

    func testLeavingOverviewReleasesAllThumbnailsAndReentryRendersAgain() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        XCTAssertFalse(grid.testingThumbnailImageIndices.isEmpty)

        grid.isHidden = true
        XCTAssertTrue(grid.testingThumbnailImageIndices.isEmpty)
        XCTAssertTrue(grid.testingPendingRenderIndices.isEmpty)

        grid.isHidden = false
        grid.testingFlushRenders()
        XCTAssertFalse(grid.testingThumbnailImageIndices.isEmpty)
    }

    func testConfiguringAnotherDocumentRebuildsItems() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()

        grid.configure(document: TestPDFFixtures.makeBlankDocument(pageCount: 4))
        grid.applyLayout(columns: 2, cellSize: CGSize(width: 240, height: 340))
        grid.testingFlushRenders()

        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0..<4))
    }

    func testHiddenGridDoesNotRasterizeUntilShown() {
        _ = NSApplication.shared
        let grid = OverviewGridView(frame: NSRect(origin: .zero, size: viewportSize))
        grid.isHidden = true
        grid.configure(document: TestPDFFixtures.makeBlankDocument(pageCount: 60))
        grid.applyLayout(columns: 3, cellSize: CGSize(width: 120, height: 170))
        grid.layoutSubtreeIfNeeded()
        grid.testingFlushRenders()

        XCTAssertTrue(grid.testingThumbnailImageIndices.isEmpty)

        grid.isHidden = false
        grid.testingFlushRenders()
        XCTAssertFalse(grid.testingThumbnailImageIndices.isEmpty)
    }

    private func makeLaidOutGrid(pageCount: Int) -> OverviewGridView {
        let grid = OverviewGridView(frame: NSRect(origin: .zero, size: viewportSize))
        grid.configure(document: TestPDFFixtures.makeBlankDocument(pageCount: pageCount))
        grid.applyLayout(columns: 3, cellSize: CGSize(width: 120, height: 170))
        grid.layoutSubtreeIfNeeded()
        return grid
    }
}
