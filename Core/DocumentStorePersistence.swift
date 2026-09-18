import Foundation
import os

struct PersistedDocumentStoreState: Codable, Equatable, Sendable {
    struct SessionReference: Codable, Equatable, Sendable {
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

    struct SplitStateRecord: Codable, Equatable, Sendable {
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

    struct WindowRecord: Codable, Equatable, Sendable {
        var id: UUID
        var sessionIDs: [UUID]
        var sessionURLs: [URL]
        var continuousReadingSessionIDs: [UUID]
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
            continuousReadingSessionIDs: [UUID] = [],
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
            self.continuousReadingSessionIDs = continuousReadingSessionIDs
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
            case continuousReadingSessionIDs
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
            continuousReadingSessionIDs = try container.decodeIfPresent(
                [UUID].self,
                forKey: .continuousReadingSessionIDs
            ) ?? []
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
        let sessions = try container.decode([SessionReference].self, forKey: .sessions)

        if let windows = try container.decodeIfPresent([WindowRecord].self, forKey: .windows) {
            self.init(sessions: sessions, windows: windows)
            return
        }

        let activeSessionURL = try container.decodeIfPresent(URL.self, forKey: .activeSessionURL)
        let tabPresentationMode = try container.decodeIfPresent(TabPresentationMode.self, forKey: .tabPresentationMode)
            ?? .verticalSidebar
        let isLeftSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isLeftSidebarVisible) ?? true
        let isRightSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isRightSidebarVisible) ?? true

        self.init(
            sessions: sessions,
            activeSessionURL: activeSessionURL,
            tabPresentationMode: tabPresentationMode,
            isLeftSidebarVisible: isLeftSidebarVisible,
            isRightSidebarVisible: isRightSidebarVisible
        )
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
    func flush() throws
}

final class UserDefaultsDocumentStorePersistence: DocumentStorePersistence, @unchecked Sendable {
    static let stateKey = "Serein.DocumentStoreState"
    static let debounceInterval: TimeInterval = 0.25

    private static let logger = Logger(subsystem: "local.yfff.Serein", category: "DocumentStorePersistence")

    private let userDefaults: UserDefaults
    private let debounceInterval: TimeInterval
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "local.yfff.Serein.DocumentStorePersistence",
        qos: .utility
    )
    private let persistenceQueueKey = DispatchSpecificKey<UInt8>()
    private var lastPersistedState: PersistedDocumentStoreState?
    private var pendingState: PersistedDocumentStoreState?
    private var mutationGeneration: UInt64 = 0
    private var scheduleGeneration: UInt64 = 0
    private var flushWorkItem: DispatchWorkItem?

    init(
        userDefaults: UserDefaults = .standard,
        debounceInterval: TimeInterval = UserDefaultsDocumentStorePersistence.debounceInterval
    ) {
        self.userDefaults = userDefaults
        self.debounceInterval = max(0, debounceInterval)
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: 1)
    }

    deinit {
        lock.lock()
        flushWorkItem?.cancel()
        lock.unlock()
        try? flush()
    }

    func loadState() throws -> PersistedDocumentStoreState? {
        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            return try loadPersistedState()
        }
        return try persistenceQueue.sync { try loadPersistedState() }
    }

    private func loadPersistedState() throws -> PersistedDocumentStoreState? {
        try flush()
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return nil }
        let state = try JSONDecoder().decode(PersistedDocumentStoreState.self, from: data)
        lock.lock()
        lastPersistedState = state
        lock.unlock()
        return state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        lock.lock()
        guard pendingState != state,
              pendingState != nil || lastPersistedState != state else {
            lock.unlock()
            return
        }
        pendingState = state
        mutationGeneration &+= 1
        let flushImmediately = debounceInterval <= 0
        scheduleFlushLocked()
        lock.unlock()
        if flushImmediately {
            try flush()
        }
    }

    func flush() throws {
        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            try persistPendingState()
        } else {
            try persistenceQueue.sync { try persistPendingState() }
        }
    }

    private func persistPendingState() throws {
        // Snapshot and write share one queue; concurrent flushes preserve order.
        lock.lock()
        flushWorkItem?.cancel()
        flushWorkItem = nil
        scheduleGeneration &+= 1
        guard let snapshot = persistenceSnapshotLocked() else {
            lock.unlock()
            return
        }
        lock.unlock()

        try Self.write(snapshot.state, to: userDefaults)
        markPersisted(snapshot)
    }

    private func scheduleFlushLocked() {
        flushWorkItem?.cancel()
        guard debounceInterval > 0 else { return }
        scheduleGeneration &+= 1
        let scheduledGeneration = scheduleGeneration
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistScheduled(generation: scheduledGeneration)
        }
        flushWorkItem = workItem
        persistenceQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func persistScheduled(generation scheduledGeneration: UInt64) {
        lock.lock()
        guard scheduleGeneration == scheduledGeneration,
              let snapshot = persistenceSnapshotLocked() else {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            try Self.write(snapshot.state, to: userDefaults)
            markPersisted(snapshot)
        } catch {
            Self.logger.error("Failed to persist document store: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistenceSnapshotLocked() -> PersistenceSnapshot? {
        pendingState.map {
            PersistenceSnapshot(state: $0, generation: mutationGeneration)
        }
    }

    private func markPersisted(_ snapshot: PersistenceSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        lastPersistedState = snapshot.state
        if mutationGeneration == snapshot.generation,
           pendingState == snapshot.state {
            pendingState = nil
            flushWorkItem = nil
        }
    }

    private static func write(_ state: PersistedDocumentStoreState, to userDefaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(state)
        userDefaults.set(data, forKey: Self.stateKey)
    }

    private struct PersistenceSnapshot: Sendable {
        let state: PersistedDocumentStoreState
        let generation: UInt64
    }
}
