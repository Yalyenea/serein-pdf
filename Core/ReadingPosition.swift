import CoreGraphics

struct ReadingPosition: Equatable, Sendable {
    var pageIndex: Int
    var point: CGPoint

    static let zero = ReadingPosition(pageIndex: 0, point: .zero)
}
