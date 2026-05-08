import Foundation

struct OutlineNode: Hashable, Sendable {
    var title: String
    var pageIndex: Int?
    var children: [OutlineNode]
    var sourceSessionID: UUID?
    var isDocumentRoot: Bool

    static let empty: [OutlineNode] = []

    init(
        title: String,
        pageIndex: Int?,
        children: [OutlineNode],
        sourceSessionID: UUID? = nil,
        isDocumentRoot: Bool = false
    ) {
        self.title = title
        self.pageIndex = pageIndex
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
                children: node.children.withSourceSessionID(sessionID),
                sourceSessionID: sessionID,
                isDocumentRoot: node.isDocumentRoot
            )
        }
    }
}
