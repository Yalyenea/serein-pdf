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
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
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
