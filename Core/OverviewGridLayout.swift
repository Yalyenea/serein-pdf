import Foundation

/// Viewport-driven layout for the all-pages overview grid.
enum OverviewGridLayout {
    static let defaultPageAspect: CGFloat = 1.414
    static let defaultCellSpacing: CGFloat = 10
    static let defaultMinCellWidth: CGFloat = 56
    /// Soft upper bound only for manual zoom; fit-all uses available space.
    static let defaultMaxCellWidth: CGFloat = 480
    static let defaultEdgeInset: CGFloat = 10

    struct Input: Equatable {
        var pageCount: Int
        var availableSize: CGSize
        var pageAspect: CGFloat = OverviewGridLayout.defaultPageAspect
        var cellSpacing: CGFloat = OverviewGridLayout.defaultCellSpacing
        var minCellWidth: CGFloat = OverviewGridLayout.defaultMinCellWidth
        /// When `nil`, fit-all may grow up to the viewport.
        var maxCellWidth: CGFloat? = nil
    }

    struct Result: Equatable {
        var columns: Int
        var cellSize: CGSize
        var contentSize: CGSize
        var fitsWithoutScroll: Bool
    }

    /// Maximize page cell size so the full grid fills the viewport when possible.
    static func computeFitAll(_ input: Input) -> Result {
        let pageCount = max(input.pageCount, 1)
        let aspect = max(input.pageAspect, 0.1)
        let spacing = max(input.cellSpacing, 0)
        let minW = max(input.minCellWidth, 1)
        let maxW = max(input.maxCellWidth ?? .greatestFiniteMagnitude, minW)

        let availW = max(input.availableSize.width, 1)
        let availH = max(input.availableSize.height, 1)

        var best: Result?

        for columns in 1...pageCount {
            let rows = Int(ceil(Double(pageCount) / Double(columns)))
            let maxCellW = (availW - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let maxCellH = (availH - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            guard maxCellW > 0, maxCellH > 0 else { continue }

            let widthFromHeight = maxCellH / aspect
            let rawW = min(maxCellW, widthFromHeight, maxW)
            guard rawW.isFinite, rawW > 0 else { continue }

            // Candidates below the readable thumbnail floor cannot satisfy
            // fit-all. Handle that case after the search with a width-filled,
            // vertically scrollable grid.
            guard rawW >= minW else { continue }
            let usedW = rawW

            let usedH = usedW * aspect
            let contentW = CGFloat(columns) * usedW + CGFloat(max(columns - 1, 0)) * spacing
            let contentH = CGFloat(rows) * usedH + CGFloat(max(rows - 1, 0)) * spacing

            let candidate = Result(
                columns: columns,
                cellSize: CGSize(width: usedW, height: usedH),
                contentSize: CGSize(width: contentW, height: contentH),
                fitsWithoutScroll: contentW <= availW + 0.5 && contentH <= availH + 0.5
            )

            if shouldPrefer(candidate, over: best, pageCount: pageCount) {
                best = candidate
            }
        }

        if let best {
            return best
        }

        // Too many pages to fit at the readable minimum. Fill every column
        // the viewport can hold so the grid uses the window width and scrolls
        // only vertically; choosing by last-row slack can collapse a long
        // document to just a few centered columns.
        let width = minW
        let columns = columnsForManualWidth(
            pageCount: pageCount,
            availableWidth: availW,
            cellWidth: width,
            cellSpacing: spacing
        )
        let rows = Int(ceil(Double(pageCount) / Double(columns)))
        let height = width * aspect
        return Result(
            columns: columns,
            cellSize: CGSize(width: width, height: height),
            contentSize: CGSize(
                width: CGFloat(columns) * width + CGFloat(max(columns - 1, 0)) * spacing,
                height: CGFloat(rows) * height + CGFloat(max(rows - 1, 0)) * spacing
            ),
            fitsWithoutScroll: false
        )
    }

    /// Indices of grid cells whose frames intersect `viewport`.
    ///
    /// Coordinates live in the flipped overview container space: (0,0) is the
    /// content's top-left and the grid's first cell sits at `origin`.
    static func visibleCellIndices(
        pageCount: Int,
        columns: Int,
        cellSize: CGSize,
        spacing: CGFloat,
        origin: CGPoint,
        viewport: CGRect
    ) -> [Int] {
        let pages = max(pageCount, 0)
        guard pages > 0, cellSize.width > 0, cellSize.height > 0 else { return [] }
        let cols = max(columns, 1)
        let rows = Int(ceil(Double(pages) / Double(cols)))

        let strideX = cellSize.width + spacing
        let strideY = cellSize.height + spacing
        guard strideX > 0, strideY > 0 else { return [] }

        // Row r spans y in [origin.y + r * strideY, origin.y + r * strideY + cellSize.height).
        let firstRow = max(0, Int(floor((viewport.minY - origin.y - cellSize.height) / strideY)) + 1)
        let lastRow = min(rows - 1, Int(floor((viewport.maxY - origin.y) / strideY)))
        let firstCol = max(0, Int(floor((viewport.minX - origin.x - cellSize.width) / strideX)) + 1)
        let lastCol = min(cols - 1, Int(floor((viewport.maxX - origin.x) / strideX)))
        guard firstRow <= lastRow, firstCol <= lastCol else { return [] }

        var indices: [Int] = []
        indices.reserveCapacity((lastRow - firstRow + 1) * (lastCol - firstCol + 1))
        for row in firstRow...lastRow {
            for col in firstCol...lastCol {
                let index = row * cols + col
                if index < pages {
                    indices.append(index)
                }
            }
        }
        return indices
    }

    /// Columns that fit a fixed manual cell width.
    static func columnsForManualWidth(
        pageCount: Int,
        availableWidth: CGFloat,
        cellWidth: CGFloat,
        cellSpacing: CGFloat = defaultCellSpacing
    ) -> Int {
        let pages = max(pageCount, 1)
        let spacing = max(cellSpacing, 0)
        let width = max(cellWidth, 1)
        let avail = max(availableWidth, 1)
        let columns = Int(floor((avail + spacing) / (width + spacing)))
        return min(pages, max(1, columns))
    }

    private static func shouldPrefer(_ candidate: Result, over current: Result?, pageCount: Int) -> Bool {
        guard let current else { return true }

        if candidate.fitsWithoutScroll != current.fitsWithoutScroll {
            return candidate.fitsWithoutScroll
        }

        let candidateArea = candidate.cellSize.width * candidate.cellSize.height
        let currentArea = current.cellSize.width * current.cellSize.height
        if abs(candidateArea - currentArea) > 1 {
            return candidateArea > currentArea
        }

        // Prefer denser packing (less unused last-row slots), then squarer grid.
        let candidateSlack = unusedSlots(pageCount: pageCount, columns: candidate.columns)
        let currentSlack = unusedSlots(pageCount: pageCount, columns: current.columns)
        if candidateSlack != currentSlack {
            return candidateSlack < currentSlack
        }

        let ideal = Int(ceil(sqrt(Double(pageCount))))
        let candidateDist = abs(candidate.columns - ideal)
        let currentDist = abs(current.columns - ideal)
        if candidateDist != currentDist {
            return candidateDist < currentDist
        }

        return candidate.columns < current.columns
    }

    private static func unusedSlots(pageCount: Int, columns: Int) -> Int {
        let rows = Int(ceil(Double(pageCount) / Double(columns)))
        return rows * columns - pageCount
    }
}
