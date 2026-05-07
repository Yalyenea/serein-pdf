import Foundation

struct PersistedDocumentStoreState: Codable, Equatable {
    struct SessionReference: Codable, Equatable {
        var id: UUID
        var url: URL
        var title: String?

        init(id: UUID = UUID(), url: URL, title: String? = nil) {
            self.id = id
            self.url = url
            self.title = title
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case url
            case title
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            url = try container.decode(URL.self, forKey: .url)
            title = try container.decodeIfPresent(String.self, forKey: .title)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
        }
    }

    struct SplitStateRecord: Codable, Equatable {
        var isEnabled: Bool
        var primarySessionID: UUID?
        var secondarySessionID: UUID?
        var primarySessionURL: URL?
        var secondarySessionURL: URL?
        var focusedPane: ReaderPane

        init(
            isEnabled: Bool,
            primarySessionID: UUID? = nil,
            secondarySessionID: UUID? = nil,
            primarySessionURL: URL?,
            secondarySessionURL: URL?,
            focusedPane: ReaderPane
        ) {
            self.isEnabled = isEnabled
            self.primarySessionID = primarySessionID
            self.secondarySessionID = secondarySessionID
            self.primarySessionURL = primarySessionURL
            self.secondarySessionURL = secondarySessionURL
            self.focusedPane = focusedPane
        }
    }

    struct WindowRecord: Codable, Equatable {
        var id: UUID
        var sessionIDs: [UUID]
        var sessionURLs: [URL]
        var tabPresentationMode: TabPresentationMode
        var isLeftSidebarVisible: Bool
        var isRightSidebarVisible: Bool
        var rightSidebarMode: RightSidebarMode
        var searchQuery: String
        var searchScope: SearchScope
        var splitState: SplitStateRecord
        var recentlyClosedURLs: [URL]

        init(
            id: UUID,
            sessionIDs: [UUID] = [],
            sessionURLs: [URL] = [],
            tabPresentationMode: TabPresentationMode,
            isLeftSidebarVisible: Bool,
            isRightSidebarVisible: Bool,
            rightSidebarMode: RightSidebarMode,
            searchQuery: String,
            searchScope: SearchScope,
            splitState: SplitStateRecord,
            recentlyClosedURLs: [URL]
        ) {
            self.id = id
            self.sessionIDs = sessionIDs
            self.sessionURLs = sessionURLs
            self.tabPresentationMode = tabPresentationMode
            self.isLeftSidebarVisible = isLeftSidebarVisible
            self.isRightSidebarVisible = isRightSidebarVisible
            self.rightSidebarMode = rightSidebarMode
            self.searchQuery = searchQuery
            self.searchScope = searchScope
            self.splitState = splitState
            self.recentlyClosedURLs = recentlyClosedURLs
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case sessionIDs
            case sessionURLs
            case tabPresentationMode
            case isLeftSidebarVisible
            case isRightSidebarVisible
            case rightSidebarMode
            case searchQuery
            case searchScope
            case splitState
            case recentlyClosedURLs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            sessionIDs = try container.decodeIfPresent([UUID].self, forKey: .sessionIDs) ?? []
            sessionURLs = try container.decodeIfPresent([URL].self, forKey: .sessionURLs) ?? []
            tabPresentationMode = try container.decode(TabPresentationMode.self, forKey: .tabPresentationMode)
            isLeftSidebarVisible = try container.decode(Bool.self, forKey: .isLeftSidebarVisible)
            isRightSidebarVisible = try container.decode(Bool.self, forKey: .isRightSidebarVisible)
            rightSidebarMode = try container.decode(RightSidebarMode.self, forKey: .rightSidebarMode)
            searchQuery = try container.decode(String.self, forKey: .searchQuery)
            searchScope = try container.decode(SearchScope.self, forKey: .searchScope)
            splitState = try container.decode(SplitStateRecord.self, forKey: .splitState)
            recentlyClosedURLs = try container.decode([URL].self, forKey: .recentlyClosedURLs)
        }
    }

    var sessions: [SessionReference]
    var windows: [WindowRecord]

    init(sessions: [SessionReference], windows: [WindowRecord]) {
        self.sessions = sessions
        self.windows = windows
    }

    init(
        sessions: [SessionReference],
        activeSessionURL: URL?,
        tabPresentationMode: TabPresentationMode,
        isLeftSidebarVisible: Bool,
        isRightSidebarVisible: Bool
    ) {
        self.sessions = sessions
        self.windows = [
            WindowRecord(
                id: UUID(),
                sessionURLs: activeSessionURL.map { [$0] } ?? [],
                tabPresentationMode: tabPresentationMode,
                isLeftSidebarVisible: isLeftSidebarVisible,
                isRightSidebarVisible: isRightSidebarVisible,
                rightSidebarMode: .outline,
                searchQuery: "",
                searchScope: .currentDocument,
                splitState: SplitStateRecord(
                    isEnabled: false,
                    primarySessionID: nil,
                    secondarySessionID: nil,
                    primarySessionURL: activeSessionURL,
                    secondarySessionURL: nil,
                    focusedPane: .primary
                ),
                recentlyClosedURLs: []
            )
        ]
    }

    var activeSessionURL: URL? {
        windows.first?.splitState.primarySessionURL
    }

    var tabPresentationMode: TabPresentationMode {
        windows.first?.tabPresentationMode ?? .verticalSidebar
    }

    var isLeftSidebarVisible: Bool {
        windows.first?.isLeftSidebarVisible ?? true
    }

    var isRightSidebarVisible: Bool {
        windows.first?.isRightSidebarVisible ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case sessions
        case windows
        case activeSessionURL
        case tabPresentationMode
        case isLeftSidebarVisible
        case isRightSidebarVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decode([SessionReference].self, forKey: .sessions)

        if let windows = try container.decodeIfPresent([WindowRecord].self, forKey: .windows),
           windows.isEmpty == false {
            self.windows = windows
            return
        }

        let activeSessionURL = try container.decodeIfPresent(URL.self, forKey: .activeSessionURL)
        let tabPresentationMode = try container.decodeIfPresent(TabPresentationMode.self, forKey: .tabPresentationMode)
            ?? .verticalSidebar
        let isLeftSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isLeftSidebarVisible) ?? true
        let isRightSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isRightSidebarVisible) ?? true

        windows = [
            WindowRecord(
                id: UUID(),
                sessionURLs: activeSessionURL.map { [$0] } ?? [],
                tabPresentationMode: tabPresentationMode,
                isLeftSidebarVisible: isLeftSidebarVisible,
                isRightSidebarVisible: isRightSidebarVisible,
                rightSidebarMode: .outline,
                searchQuery: "",
                searchScope: .currentDocument,
                splitState: SplitStateRecord(
                    isEnabled: false,
                    primarySessionID: nil,
                    secondarySessionID: nil,
                    primarySessionURL: activeSessionURL,
                    secondarySessionURL: nil,
                    focusedPane: .primary
                ),
                recentlyClosedURLs: []
            )
        ]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(windows, forKey: .windows)
    }
}

protocol DocumentStorePersistence {
    func loadState() throws -> PersistedDocumentStoreState?
    func saveState(_ state: PersistedDocumentStoreState) throws
}

struct UserDefaultsDocumentStorePersistence: DocumentStorePersistence {
    private static let stateKey = "Serein.DocumentStoreState"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState() throws -> PersistedDocumentStoreState? {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return nil }
        return try JSONDecoder().decode(PersistedDocumentStoreState.self, from: data)
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        let data = try JSONEncoder().encode(state)
        userDefaults.set(data, forKey: Self.stateKey)
    }
}
