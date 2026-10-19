import Foundation

struct ReaderPane: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init() { rawValue = UUID().uuidString }
    static let primary = ReaderPane(rawValue: "primary")
    static let secondary = ReaderPane(rawValue: "secondary")

    /// Used by the two-pane command entry points, not by layout traversal.
    var other: ReaderPane { self == .primary ? .secondary : .primary }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ReaderSplitLayout: String, Equatable, Codable, Sendable {
    case sideBySide
    case stacked
}

indirect enum ReaderLayoutNode: Equatable, Codable, Sendable {
    case pane(ReaderPane)
    case split(id: UUID, layout: ReaderSplitLayout, ratio: Double, first: ReaderLayoutNode, second: ReaderLayoutNode)

    var paneIDs: [ReaderPane] {
        switch self {
        case let .pane(id): [id]
        case let .split(_, _, _, first, second): first.paneIDs + second.paneIDs
        }
    }

    func replacing(_ pane: ReaderPane, with replacement: ReaderLayoutNode) -> ReaderLayoutNode {
        switch self {
        case let .pane(id): id == pane ? replacement : self
        case let .split(id, layout, ratio, first, second):
            .split(id: id, layout: layout, ratio: ratio,
                   first: first.replacing(pane, with: replacement),
                   second: second.replacing(pane, with: replacement))
        }
    }

    func removing(_ pane: ReaderPane) -> ReaderLayoutNode? {
        switch self {
        case let .pane(id): return id == pane ? nil : self
        case let .split(id, layout, ratio, first, second):
            let left = first.removing(pane)
            let right = second.removing(pane)
            if let left, let right {
                return .split(id: id, layout: layout, ratio: ratio, first: left, second: right)
            }
            return left ?? right
        }
    }

    func updatingRatio(_ ratio: Double, splitID: UUID) -> ReaderLayoutNode {
        switch self {
        case .pane: self
        case let .split(id, layout, previousRatio, first, second):
            .split(id: id, layout: layout, ratio: id == splitID ? ratio : previousRatio,
                   first: first.updatingRatio(ratio, splitID: splitID),
                   second: second.updatingRatio(ratio, splitID: splitID))
        }
    }
}

struct ReaderPaneState: Equatable, Sendable {
    let id: ReaderPane
    let sessionID: UUID?
}

struct ReaderLayoutGroup: Equatable, Codable, Sendable {
    let id: UUID
    var root: ReaderLayoutNode
    var sessionIDsByPane: [ReaderPane: UUID]
    var focusedPane: ReaderPane
    var zoomedPane: ReaderPane?

    init(sessionID: UUID?, pane: ReaderPane = .primary) {
        id = UUID()
        root = .pane(pane)
        sessionIDsByPane = sessionID.map { [pane: $0] } ?? [:]
        focusedPane = pane
    }

    var sessionIDs: [UUID] { root.paneIDs.compactMap { sessionIDsByPane[$0] } }

    mutating func removePane(_ pane: ReaderPane) {
        guard let updated = root.removing(pane) else { return }
        root = updated
        sessionIDsByPane.removeValue(forKey: pane)
        if focusedPane == pane { focusedPane = root.paneIDs[0] }
        if zoomedPane == pane || root.paneIDs.count == 1 { zoomedPane = nil }
    }
}

/// A small, stable symbol palette keeps Space identity consistent across both tab styles.
enum SpaceIcon: String, CaseIterable, Codable, Sendable {
    case books = "books.vertical"
    case document = "doc.text"
    case bookmark = "bookmark"
    case study = "graduationcap"
    case work = "briefcase"
    case code = "chevron.left.forwardslash.chevron.right"
    case science = "flask"
    case leaf = "leaf"
    case globe = "globe"
    case star = "star"
    case heart = "heart"
    case moon = "moon"
    case coffee = "cup.and.saucer"
    case bolt = "bolt"
    case music = "headphones"
    case layers = "square.stack"

    var label: String {
        switch self {
        case .books: L10n.text("Books", "书籍")
        case .document: L10n.text("Document", "文档")
        case .bookmark: L10n.text("Bookmark", "书签")
        case .study: L10n.text("Study", "学习")
        case .work: L10n.text("Work", "工作")
        case .code: L10n.text("Code", "代码")
        case .science: L10n.text("Science", "科学")
        case .leaf: L10n.text("Leaf", "叶子")
        case .globe: L10n.text("Globe", "地球")
        case .star: L10n.text("Star", "星星")
        case .heart: L10n.text("Heart", "爱心")
        case .moon: L10n.text("Moon", "月亮")
        case .coffee: L10n.text("Coffee", "咖啡")
        case .bolt: L10n.text("Lightning", "闪电")
        case .music: L10n.text("Music", "音乐")
        case .layers: L10n.text("Layers", "图层")
        }
    }
}

struct NamedWorkspace: Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    // Optional so saved Spaces created before icon selection retain their identity.
    var icon: SpaceIcon?
    var sessionIDs: [UUID] = []
    var selectedSessionIDs: Set<UUID> = []
    var continuousReadingState = ContinuousReadingState()
    var groups: [ReaderLayoutGroup] = []
    var activeGroupID: UUID?
    var recentlyClosedURLs: [URL] = []
    var searchQuery = ""
    var searchScope: SearchScope = .currentDocument

    init(id: UUID = UUID(), name: String = L10n.text("Space", "空间")) {
        self.id = id
        self.name = name
    }

    var activeGroup: ReaderLayoutGroup? {
        get { groups.first { $0.id == activeGroupID } }
        set {
            guard let newValue else { activeGroupID = nil; return }
            if let index = groups.firstIndex(where: { $0.id == newValue.id }) {
                groups.remove(at: index)
            }
            groups.append(newValue)
            activeGroupID = newValue.id
        }
    }

    var referencedSessionIDs: Set<UUID> {
        Set(sessionIDs + groups.flatMap(\.sessionIDs))
    }
}

struct WorkspaceDocumentReference: Equatable, Codable, Sendable {
    let workspaceID: UUID
    let sessionID: UUID
}

struct WorkspaceDocumentEntry {
    let windowID: UUID
    let workspaceID: UUID
    let workspaceName: String
    let session: DocumentSession
}
