import Foundation

/// Keeps preview and editor attached to the same corner in screen coordinates.
struct AnnotationCommentPlacement {
    private enum Side {
        case right, left, above, below
    }

    private let reservedFrame: NSRect
    private let alignsRight: Bool
    private let alignsTop: Bool

    init(anchor: NSRect, available: NSRect, reservedSize: NSSize) {
        let gap: CGFloat = 8
        let size = NSSize(
            width: min(max(reservedSize.width, 1), available.width),
            height: min(max(reservedSize.height, 1), available.height)
        )
        let candidates: [(side: Side, clearance: CGFloat, required: CGFloat)] = [
            (.right, available.maxX - anchor.maxX - gap, size.width),
            (.left, anchor.minX - available.minX - gap, size.width),
            (.above, available.maxY - anchor.maxY - gap, size.height),
            (.below, anchor.minY - available.minY - gap, size.height),
        ]
        // When no side can fit the reserved card, overlap is unavoidable. Use
        // the side with the most room and keep the entire card on screen.
        let side = candidates.first(where: { $0.clearance >= $0.required })?.side
            ?? candidates.max(by: { $0.clearance / $0.required < $1.clearance / $1.required })!.side

        var right = anchor.midX > available.midX
        var top = anchor.midY >= available.midY
        var x = right ? anchor.maxX - size.width : anchor.minX
        var y = top ? anchor.maxY - size.height : anchor.minY
        switch side {
        case .right:
            right = false
            x = anchor.maxX + gap
        case .left:
            right = true
            x = anchor.minX - gap - size.width
        case .above:
            top = false
            y = anchor.maxY + gap
        case .below:
            top = true
            y = anchor.minY - gap - size.height
        }

        reservedFrame = NSRect(
            x: min(max(x, available.minX), available.maxX - size.width),
            y: min(max(y, available.minY), available.maxY - size.height),
            width: size.width,
            height: size.height
        )
        alignsRight = right
        alignsTop = top
    }

    /// `reservedSize` must include the largest preview or editor dimensions.
    func frame(for size: NSSize) -> NSRect {
        let width = min(max(size.width, 1), reservedFrame.width)
        let height = min(max(size.height, 1), reservedFrame.height)
        return NSRect(
            x: alignsRight ? reservedFrame.maxX - width : reservedFrame.minX,
            y: alignsTop ? reservedFrame.maxY - height : reservedFrame.minY,
            width: width,
            height: height
        )
    }
}
