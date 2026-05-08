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
            "Find in document"
        case .allOpen:
            "Find in all open PDFs"
        }
    }
}

enum ReaderPane: String, CaseIterable, Codable, Sendable {
    case primary
    case secondary

    var other: ReaderPane {
        switch self {
        case .primary:
            .secondary
        case .secondary:
            .primary
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
    var pageIndex: Int
}

struct WindowWorkspace: Equatable, Sendable {
    let id: UUID
    var sessionIDs: [UUID]
    var selectedSessionIDs: Set<UUID>
    var continuousReadingState: ContinuousReadingState
    var tabPresentationMode: TabPresentationMode
    var isLeftSidebarVisible: Bool
    var isRightSidebarVisible: Bool
    var rightSidebarMode: RightSidebarMode
    var searchQuery: String
    var searchScope: SearchScope
    var isSplitEnabled: Bool
    var primarySessionID: UUID?
    var secondarySessionID: UUID?
    var focusedPane: ReaderPane
    var recentlyClosedURLs: [URL]

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
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary,
        recentlyClosedURLs: [URL] = []
    ) {
        self.id = id
        self.sessionIDs = sessionIDs
        self.selectedSessionIDs = selectedSessionIDs
        self.continuousReadingState = continuousReadingState
        self.tabPresentationMode = tabPresentationMode
        self.isLeftSidebarVisible = isLeftSidebarVisible
        self.isRightSidebarVisible = isRightSidebarVisible
        self.rightSidebarMode = rightSidebarMode
        self.searchQuery = searchQuery
        self.searchScope = searchScope
        self.isSplitEnabled = isSplitEnabled
        self.primarySessionID = primarySessionID
        self.secondarySessionID = secondarySessionID
        self.focusedPane = focusedPane
        self.recentlyClosedURLs = recentlyClosedURLs
    }

    var activeSessionID: UUID? {
        switch focusedPane {
        case .primary:
            primarySessionID ?? secondarySessionID
        case .secondary:
            secondarySessionID ?? primarySessionID
        }
    }

    mutating func setSession(_ sessionID: UUID?, for pane: ReaderPane) {
        switch pane {
        case .primary:
            primarySessionID = sessionID
        case .secondary:
            secondarySessionID = sessionID
        }
    }
}
