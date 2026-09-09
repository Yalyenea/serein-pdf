import Foundation
@testable import Serein

/// Shared in-memory doubles so tests never touch real UserDefaults / workspace files.
final class TestInMemoryDocumentStorePersistence: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?

    func loadState() throws -> PersistedDocumentStoreState? {
        state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        self.state = state
    }

    func flush() throws {}
}

final class TestInMemoryReadingStateStore: ReadingStateStore {
    var states: [URL: PersistedReadingState] = [:]
    private(set) var savedStates: [PersistedReadingState] = []

    func loadState(for url: URL) throws -> PersistedReadingState? {
        states[url]
    }

    func saveState(_ state: PersistedReadingState) throws {
        states[state.url] = state
        savedStates.append(state)
    }
}

final class TestInMemoryRecentFilesStore: RecentFilesStore {
    var recentFiles: [URL] = []

    func loadRecentFiles() throws -> [URL] {
        recentFiles
    }

    func recordOpen(for url: URL) throws -> [URL] {
        try recordOpen(for: [url])
    }

    func recordOpen(for urls: [URL]) throws -> [URL] {
        for url in urls {
            recentFiles.removeAll { $0 == url }
            recentFiles.insert(url, at: 0)
        }
        return recentFiles
    }

    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL] {
        if let index = recentFiles.firstIndex(of: oldURL) {
            recentFiles[index] = newURL
        }
        return recentFiles
    }
}

@MainActor
func makeIsolatedDocumentStore(
    appConfiguration: AppConfiguration = .default,
    persistence: DocumentStorePersistence = TestInMemoryDocumentStorePersistence(),
    readingStateStore: ReadingStateStore = TestInMemoryReadingStateStore(),
    recentFilesStore: RecentFilesStore = TestInMemoryRecentFilesStore()
) -> DocumentStore {
    DocumentStore(
        persistence: persistence,
        readingStateStore: readingStateStore,
        recentFilesStore: recentFilesStore,
        appConfiguration: appConfiguration
    )
}

@MainActor
func waitForDocumentSearch(
    in store: DocumentStore,
    windowID: UUID? = nil,
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let targetWindowID = windowID ?? store.defaultWindowID
    let deadline = Date(timeIntervalSinceNow: timeout)
    while store.searchSnapshot(in: targetWindowID).isSearching, Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    precondition(
        store.searchSnapshot(in: targetWindowID).isSearching == false,
        "Search did not complete before timeout at \(file):\(line)"
    )
}
