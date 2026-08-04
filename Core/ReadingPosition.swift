import CoreGraphics

struct ReadingPosition: Codable, Equatable, Sendable {
    var pageIndex: Int
    var pointX: CGFloat
    var pointY: CGFloat

    init(pageIndex: Int, point: CGPoint) {
        self.pageIndex = pageIndex
        pointX = point.x
        pointY = point.y
    }

    var point: CGPoint {
        CGPoint(x: pointX, y: pointY)
    }

    static func pageTop(pageIndex: Int, pageBounds: CGRect) -> ReadingPosition {
        ReadingPosition(pageIndex: pageIndex, point: CGPoint(x: pageBounds.minX, y: pageBounds.maxY))
    }

    static func pageBottom(pageIndex: Int, pageBounds: CGRect) -> ReadingPosition {
        ReadingPosition(pageIndex: pageIndex, point: CGPoint(x: pageBounds.minX, y: pageBounds.minY))
    }

    static let zero = ReadingPosition(pageIndex: 0, point: .zero)
}
