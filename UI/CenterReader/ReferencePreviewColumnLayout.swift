import Foundation

/// Detect a local gutter from text geometry in upright display coordinates.
enum ReferencePreviewColumnLayout {
    static func columnBounds(characterBounds: [CGRect], pageBounds: CGRect, target: CGPoint) -> CGRect? {
        let width = pageBounds.width
        guard width > 0, target.x.isFinite, target.y.isFinite else { return nil }
        let nearby = characterBounds.filter {
            !$0.isEmpty && !$0.isInfinite && !$0.isNull
                && pageBounds.contains(CGPoint(x: $0.midX, y: $0.midY))
                && abs($0.midY - target.y) < width * 0.16
        }.sorted { $0.midY < $1.midY }
        guard !nearby.isEmpty else { return nil }
        let heights = nearby.map(\.height).sorted()
        let rowTolerance = heights[heights.count / 2] * 1.2
        var rows: [[CGRect]] = []
        for rect in nearby {
            if let last = rows.last, let first = last.first,
               abs(first.midY - rect.midY) < rowTolerance {
                rows[rows.count - 1].append(rect)
            } else {
                rows.append([rect])
            }
        }
        guard rows.count >= 3 else { return nil }
        rows = rows.map { $0.sorted { $0.minX < $1.minX } }
        let minimumGap = width * 0.015
        // A gutter must lie near the center and separate substantial text on both sides.
        func gaps(in row: [CGRect]) -> [ClosedRange<CGFloat>] {
            guard !row.isEmpty else { return [] }
            var gaps: [ClosedRange<CGFloat>] = []
            var right = row[0].maxX
            for rect in row.dropFirst() {
                if rect.minX - right >= minimumGap,
                   right > pageBounds.minX + width * 0.3,
                   rect.minX < pageBounds.minX + width * 0.7,
                   right - row[0].minX > width * 0.18,
                   row.last!.maxX - rect.minX > width * 0.18 {
                    gaps.append(right...rect.minX)
                }
                right = max(right, rect.maxX)
            }
            return gaps
        }
        // Opposite columns need not share baselines. Project single-column rows
        // together so equations and staggered paragraphs can still expose a gutter.
        let unpaired = rows.filter { $0.last!.maxX - $0[0].minX < width * 0.6 }
            .flatMap { $0 }.sorted { $0.minX < $1.minX }
        let candidates = rows.flatMap { gaps(in: $0) } + gaps(in: unpaired)
        let nearest = rows.min { a, b in
            abs(a[0].midY - target.y) < abs(b[0].midY - target.y)
        }!
        guard abs(nearest[0].midY - target.y) < width * 0.055 else { return nil }
        var best: (gap: ClosedRange<CGFloat>, rows: [[CGRect]])?
        for gap in candidates {
            let center = (gap.lowerBound + gap.upperBound) / 2
            let strip = (center - minimumGap / 2)...(center + minimumGap / 2)
            func crosses(_ row: [CGRect]) -> Bool {
                row.contains { $0.maxX > strip.lowerBound && $0.minX < strip.upperBound }
            }
            // Titles or other text spanning the gutter at the destination need full width.
            guard !crosses(nearest) else { continue }
            func hasBody(_ row: [CGRect], onLeft: Bool) -> Bool {
                let side = row.filter { onLeft ? $0.maxX <= strip.lowerBound : $0.minX >= strip.upperBound }
                guard let first = side.first, let last = side.last else { return false }
                return last.maxX - first.minX > width * 0.18
            }
            // Sparse formula/superscript rows carry no vote. Require substantial
            // text on each side, without requiring it to line up across columns.
            let evidence = rows.filter { hasBody($0, onLeft: true) || hasBody($0, onLeft: false) }
            let supporting = evidence.filter { !crosses($0) }
            guard supporting.filter({ hasBody($0, onLeft: true) }).count >= 3,
                  supporting.filter({ hasBody($0, onLeft: false) }).count >= 3,
                  supporting.count * 2 >= evidence.count else { continue }
            if best == nil || supporting.count > best!.rows.count {
                best = (gap, supporting)
            }
        }
        guard let best else { return nil }
        let center = (best.gap.lowerBound + best.gap.upperBound) / 2
        let padding = width * 0.018
        // A destination inside the gutter does not identify either column.
        guard target.x <= best.gap.lowerBound + padding || target.x >= best.gap.upperBound - padding else { return nil }
        let isLeft = target.x < center
        // Include short equation rows and their numbers, not only the voting text.
        let column = rows.filter { row in
            !row.contains { $0.maxX > center - minimumGap / 2 && $0.minX < center + minimumGap / 2 }
        }.flatMap { $0 }.filter { isLeft ? $0.midX < center : $0.midX > center }
        guard let left = column.map(\.minX).min(), let right = column.map(\.maxX).max() else { return nil }
        let minX = max(pageBounds.minX, min(left, target.x) - padding)
        let maxX = min(pageBounds.maxX, max(right, target.x) + padding)
        return CGRect(x: minX, y: pageBounds.minY, width: maxX - minX, height: pageBounds.height)
    }
}
