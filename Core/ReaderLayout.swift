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

struct NamedWorkspace: Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    var sessionIDs: [UUID] = []
    var selectedSessionIDs: Set<UUID> = []
    var continuousReadingState = ContinuousReadingState()
    var groups: [ReaderLayoutGroup] = []
    var activeGroupID: UUID?
    var recentlyClosedURLs: [URL] = []
    var searchQuery = ""
    var searchScope: SearchScope = .currentDocument

    init(id: UUID = UUID(), name: String = L10n.text("Workspace", "工作区")) {
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
