import Foundation

enum RightSidebarMode: Int, CaseIterable, Codable, Sendable {
    case outline = 0
    case pages = 1
    case search = 2
    case annotations = 3

    func toggledPreviewMode() -> RightSidebarMode {
        switch self {
        case .outline:
            .pages
        case .pages:
            .outline
        case .search:
            .pages
        case .annotations:
            .pages
        }
    }
}

enum SearchScope: String, CaseIterable, Codable, Sendable {
    case currentDocument = "current_document"
    case allOpen = "all_open"

    var placeholder: String {
        switch self {
        case .currentDocument:
            L10n.text("Find in document", "在当前文档中查找")
        case .allOpen:
            L10n.text("Find in all open PDFs", "在所有打开的 PDF 中查找")
        }
    }
}

struct ContinuousReadingState: Equatable, Codable, Sendable {
    var orderedSessionIDs: [UUID]

    init(orderedSessionIDs: [UUID] = []) {
        self.orderedSessionIDs = orderedSessionIDs
    }

    var isEnabled: Bool {
        orderedSessionIDs.count > 1
    }
}

struct ContinuousReadingTarget: Equatable, Sendable {
    var sessionID: UUID
    var readingPosition: ReadingPosition

    var pageIndex: Int {
        readingPosition.pageIndex
    }
}

struct ReaderSplitPair: Equatable, Sendable {
    var primarySessionID: UUID
    var secondarySessionID: UUID

    func pane(containing sessionID: UUID) -> ReaderPane? {
        if primarySessionID == sessionID {
            return .primary
        }
        if secondarySessionID == sessionID {
            return .secondary
        }
        return nil
    }
}

struct WindowWorkspace: Equatable, Codable, Sendable {
    let id: UUID
    var workspaces: [NamedWorkspace]
    var activeWorkspaceID: UUID
    var isClosed = false
    var documentMRU: [WorkspaceDocumentReference] = []
    var tabPresentationMode: TabPresentationMode
    var isLeftSidebarVisible: Bool
    var isRightSidebarVisible: Bool
    var rightSidebarMode: RightSidebarMode
    var leftSidebarWidth: CGFloat?
    var rightSidebarWidth: CGFloat?
    /// An explicit outline visibility choice stays in effect across empty workspaces.
    var outlineVisibilityWhileEmpty: Bool?

    init(
        id: UUID = UUID(),
        sessionIDs: [UUID] = [],
        selectedSessionIDs: Set<UUID> = [],
        continuousReadingState: ContinuousReadingState = ContinuousReadingState(),
        tabPresentationMode: TabPresentationMode = .verticalSidebar,
        isLeftSidebarVisible: Bool = true,
        isRightSidebarVisible: Bool = true,
        rightSidebarMode: RightSidebarMode = .outline,
        searchQuery: String = "",
        searchScope: SearchScope = .currentDocument,
        isSplitEnabled: Bool = false,
        splitLayout: ReaderSplitLayout = .sideBySide,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary,
        recentlyClosedURLs: [URL] = [],
        leftSidebarWidth: CGFloat? = nil,
        rightSidebarWidth: CGFloat? = nil
    ) {
        self.id = id
        var workspace = NamedWorkspace()
        workspace.sessionIDs = sessionIDs
        workspace.selectedSessionIDs = selectedSessionIDs
        workspace.continuousReadingState = continuousReadingState
        workspace.searchQuery = searchQuery
        workspace.searchScope = searchScope
        workspace.recentlyClosedURLs = recentlyClosedURLs
        if let primarySessionID {
            var group = ReaderLayoutGroup(sessionID: primarySessionID)
            if isSplitEnabled {
                group.root = .split(id: UUID(), layout: splitLayout, ratio: 0.5,
                                    first: .pane(.primary), second: .pane(.secondary))
                group.sessionIDsByPane[.secondary] = secondarySessionID
                group.focusedPane = focusedPane
            }
            workspace.activeGroup = group
        }
        workspaces = [workspace]
        activeWorkspaceID = workspace.id
        self.tabPresentationMode = tabPresentationMode
        self.isLeftSidebarVisible = isLeftSidebarVisible
        self.isRightSidebarVisible = isRightSidebarVisible
        self.rightSidebarMode = rightSidebarMode
        self.leftSidebarWidth = leftSidebarWidth
        self.rightSidebarWidth = rightSidebarWidth
    }

    var activeWorkspace: NamedWorkspace {
        get { workspaces[workspaces.firstIndex { $0.id == activeWorkspaceID }!] }
        set { workspaces[workspaces.firstIndex { $0.id == activeWorkspaceID }!] = newValue }
    }

    var sessionIDs: [UUID] {
        get { activeWorkspace.sessionIDs }
        set { activeWorkspace.sessionIDs = newValue }
    }
    var selectedSessionIDs: Set<UUID> {
        get { activeWorkspace.selectedSessionIDs }
        set { activeWorkspace.selectedSessionIDs = newValue }
    }
    var continuousReadingState: ContinuousReadingState {
        get { activeWorkspace.continuousReadingState }
        set { activeWorkspace.continuousReadingState = newValue }
    }
    var searchQuery: String {
        get { activeWorkspace.searchQuery }
        set { activeWorkspace.searchQuery = newValue }
    }
    var searchScope: SearchScope {
        get { activeWorkspace.searchScope }
        set { activeWorkspace.searchScope = newValue }
    }
    var recentlyClosedURLs: [URL] {
        get { activeWorkspace.recentlyClosedURLs }
        set { activeWorkspace.recentlyClosedURLs = newValue }
    }
    var readerLayout: ReaderLayoutNode? { activeWorkspace.activeGroup?.root }
    var paneIDs: [ReaderPane] { readerLayout?.paneIDs ?? [] }
    var activeSessionID: UUID? { activeWorkspace.activeGroup?.sessionIDsByPane[focusedPane] }
    var focusedPane: ReaderPane {
        get { activeWorkspace.activeGroup?.focusedPane ?? .primary }
        set { activeWorkspace.activeGroup?.focusedPane = newValue }
    }
    var isSplitEnabled: Bool {
        get { paneIDs.count > 1 }
        set {
            guard newValue != isSplitEnabled else { return }
            guard var group = activeWorkspace.activeGroup else { return }
            if newValue {
                let addedPane: ReaderPane = group.root.paneIDs.contains(.secondary) ? ReaderPane() : .secondary
                group.root = .split(id: UUID(), layout: .sideBySide, ratio: 0.5,
                                    first: group.root, second: .pane(addedPane))
            } else {
                let retained = group.sessionIDsByPane[group.focusedPane]
                group.root = .pane(.primary)
                group.sessionIDsByPane = retained.map { [.primary: $0] } ?? [:]
                group.focusedPane = .primary
                group.zoomedPane = nil
            }
            activeWorkspace.activeGroup = group
        }
    }
    var splitLayout: ReaderSplitLayout {
        get {
            if case let .split(_, layout, _, _, _) = readerLayout { return layout }
            return .sideBySide
        }
        set {
            guard var group = activeWorkspace.activeGroup,
                  case let .split(id, _, ratio, first, second) = group.root else { return }
            group.root = .split(id: id, layout: newValue, ratio: ratio, first: first, second: second)
            activeWorkspace.activeGroup = group
        }
    }
    var primarySessionID: UUID? {
        get { paneIDs.first.flatMap { activeWorkspace.activeGroup?.sessionIDsByPane[$0] } }
        set {
            if activeWorkspace.activeGroup == nil, let newValue {
                activeWorkspace.activeGroup = ReaderLayoutGroup(sessionID: newValue)
            } else if let first = paneIDs.first {
                activeWorkspace.activeGroup?.sessionIDsByPane[first] = newValue
            }
        }
    }
    var secondarySessionID: UUID? {
        get {
            guard paneIDs.count > 1 else { return nil }
            return activeWorkspace.activeGroup?.sessionIDsByPane[paneIDs[1]]
        }
        set {
            guard paneIDs.count > 1 else { return }
            let second = paneIDs[1]
            activeWorkspace.activeGroup?.sessionIDsByPane[second] = newValue
        }
    }
    var splitPair: ReaderSplitPair? {
        get {
            guard let group = activeWorkspace.groups.first(where: { $0.root.paneIDs.count > 1 }),
                  group.sessionIDs.count >= 2 else { return nil }
            return ReaderSplitPair(primarySessionID: group.sessionIDs[0], secondarySessionID: group.sessionIDs[1])
        }
    }

    mutating func setSession(_ sessionID: UUID?, for pane: ReaderPane) {
        guard paneIDs.contains(pane) else { return }
        activeWorkspace.activeGroup?.sessionIDsByPane[pane] = sessionID
    }
}
