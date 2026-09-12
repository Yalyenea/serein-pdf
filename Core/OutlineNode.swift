import Foundation

struct OutlineNavigationRequest: Equatable, Sendable {
    let sessionID: UUID
    let position: ReadingPosition
}

struct OutlineNode: Hashable, Sendable {
    var title: String
    var pageIndex: Int?
    var destinationPoint: CGPoint?
    var children: [OutlineNode]
    var sourceSessionID: UUID?
    var isDocumentRoot: Bool

    init(
        title: String,
        pageIndex: Int?,
        destinationPoint: CGPoint? = nil,
        children: [OutlineNode],
        sourceSessionID: UUID? = nil,
        isDocumentRoot: Bool = false
    ) {
        self.title = title
        self.pageIndex = pageIndex
        self.destinationPoint = destinationPoint
        self.children = children
        self.sourceSessionID = sourceSessionID
        self.isDocumentRoot = isDocumentRoot
    }
}

extension Array where Element == OutlineNode {
    func withSourceSessionID(_ sessionID: UUID) -> [OutlineNode] {
        map { node in
            OutlineNode(
                title: node.title,
                pageIndex: node.pageIndex,
                destinationPoint: node.destinationPoint,
                children: node.children.withSourceSessionID(sessionID),
                sourceSessionID: sessionID,
                isDocumentRoot: node.isDocumentRoot
            )
        }
    }
}
