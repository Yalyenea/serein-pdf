struct OutlineNode: Hashable, Sendable {
    var title: String
    var pageIndex: Int?
    var children: [OutlineNode]

    static let empty: [OutlineNode] = []
}
