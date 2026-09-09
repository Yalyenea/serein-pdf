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
        XCTAssertEqual(grid.testingLiveItemViewCount, 21)
        XCTAssertTrue(grid.testingPendingRenderIndices.isEmpty)
    }

    func testOverviewRendersAllPagesWhenWholeGridFits() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 6)

        grid.testingFlushRenders()

        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0..<6))
    }

    func testClipViewScrollingRendersNewNeighborhoodReleasesFarPagesAndRestoresFromCache() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(0...20))

        // Viewport y ∈ [1810, 2410): visible rows 10...13, buffered rows 6...16.
        XCTAssertTrue(grid.testingClipViewScroll(to: CGPoint(x: 0, y: 1810)))
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, Set(18...50))
        XCTAssertEqual(grid.testingLiveItemViewCount, 33)

        // Back to the top: cached pages reappear synchronously, no rasterization.
        XCTAssertTrue(grid.testingClipViewScroll(to: .zero))
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

    func testRapidClipViewScrollingCancelsStaleRenderNeighborhoods() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 600)

        // Move several screens without waiting for the prior neighborhood to
        // rasterize, matching a fast scrollbar drag through a long document.
        XCTAssertTrue(grid.testingClipViewScroll(to: CGPoint(x: 0, y: 6_000)))
        XCTAssertTrue(grid.testingClipViewScroll(to: CGPoint(x: 0, y: 12_000)))
        XCTAssertTrue(grid.testingClipViewScroll(to: CGPoint(x: 0, y: 24_000)))

        let finalViewport = CGRect(x: 0, y: 24_000, width: 800, height: 600)
        let expected = Set(
            OverviewGridLayout.visibleCellIndices(
                pageCount: 600,
                columns: 3,
                cellSize: CGSize(width: 120, height: 170),
                spacing: 10,
                origin: CGPoint(x: 210, y: 10),
                viewport: finalViewport.insetBy(dx: -800, dy: -600)
            )
        )

        XCTAssertTrue(grid.testingPendingRenderIndices.isSubset(of: expected))
        grid.testingFlushRenders()
        XCTAssertEqual(grid.testingThumbnailImageIndices, expected)
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

    func testHiddenGridLifecycleNeverRendersUntilShownAndReleasesOnHide() {
        _ = NSApplication.shared
        let grid = OverviewGridView(frame: NSRect(origin: .zero, size: viewportSize))
        grid.isHidden = true

        // configure/applyLayout run while hidden (the real entry sequence
        // configures before unhiding) — nothing may rasterize.
        grid.configure(document: TestPDFFixtures.makeBlankDocument(pageCount: 60))
        grid.applyLayout(columns: 3, cellSize: CGSize(width: 120, height: 170))
        grid.layoutSubtreeIfNeeded()
        grid.testingFlushRenders()
        XCTAssertTrue(grid.testingThumbnailImageIndices.isEmpty)

        // Showing renders; hiding releases everything; showing re-renders.
        grid.isHidden = false
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

    func testReleaseDocumentDropsCellsAndPreventsFurtherRendering() {
        _ = NSApplication.shared
        let grid = makeLaidOutGrid(pageCount: 60)
        grid.testingFlushRenders()
        XCTAssertTrue(grid.testingHasDocument)
        XCTAssertFalse(grid.testingThumbnailImageIndices.isEmpty)

        grid.releaseDocument()

        XCTAssertFalse(grid.testingHasDocument)
        XCTAssertEqual(grid.testingLiveItemViewCount, 0)
        XCTAssertTrue(grid.testingThumbnailImageIndices.isEmpty)
        XCTAssertTrue(grid.testingPendingRenderIndices.isEmpty)
        grid.testingScroll(to: CGRect(origin: CGPoint(x: 0, y: 1_800), size: viewportSize))
        grid.testingFlushRenders()
        XCTAssertTrue(grid.testingThumbnailImageIndices.isEmpty)
    }

    private func makeLaidOutGrid(pageCount: Int) -> OverviewGridView {
        let grid = OverviewGridView(frame: NSRect(origin: .zero, size: viewportSize))
        grid.configure(document: TestPDFFixtures.makeBlankDocument(pageCount: pageCount))
        grid.applyLayout(columns: 3, cellSize: CGSize(width: 120, height: 170))
        grid.layoutSubtreeIfNeeded()
        return grid
    }
}
