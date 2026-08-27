import Foundation
import XCTest
@testable import Serein

final class ReadingStateStoreTests: XCTestCase {
    func testSaveAndLoadReadingStateByDocumentURL() throws {
        let suiteName = "SereinTests.ReadingStateStore.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        // Immediate write for deterministic unit tests.
        let store = UserDefaultsReadingStateStore(userDefaults: userDefaults, debounceInterval: 0)
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let state = PersistedReadingState(
            url: url,
            displayMode: .bookContinuous,
            scaleMode: .manual,
            scaleFactor: 1.6,
            readingPosition: ReadingPosition(pageIndex: 5, point: CGPoint(x: 18, y: 24))
        )

        try store.saveState(state)
        let loaded = try store.loadState(for: url)

        XCTAssertEqual(loaded, state)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testLRUEvictsOldestEntriesBeyondLimit() throws {
        let suiteName = "SereinTests.ReadingStateStore.LRU.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsReadingStateStore(
            userDefaults: userDefaults,
            maxEntries: 2,
            debounceInterval: 0
        )

        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")

        try store.saveState(makeState(url: first, page: 0))
        try store.saveState(makeState(url: second, page: 1))
        try store.saveState(makeState(url: third, page: 2))

        XCTAssertNil(try store.loadState(for: first))
        XCTAssertEqual(try store.loadState(for: second)?.readingPosition.pageIndex, 1)
        XCTAssertEqual(try store.loadState(for: third)?.readingPosition.pageIndex, 2)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testLRUOrderSurvivesStoreRecreation() throws {
        let suiteName = "SereinTests.ReadingStateStore.RestartLRU.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let first = URL(fileURLWithPath: "/tmp/restart-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/restart-second.pdf")
        let third = URL(fileURLWithPath: "/tmp/restart-third.pdf")
        let firstState = makeState(url: first, page: 1)
        let secondState = makeState(url: second, page: 2)
        let thirdState = makeState(url: third, page: 3)

        do {
            let store = UserDefaultsReadingStateStore(
                userDefaults: userDefaults,
                maxEntries: 2,
                debounceInterval: 60
            )
            try store.saveState(firstState)
            try store.saveState(secondState)
            try store.flush()
        }

        do {
            let store = UserDefaultsReadingStateStore(
                userDefaults: userDefaults,
                maxEntries: 2,
                debounceInterval: 60
            )
            XCTAssertEqual(try store.loadState(for: first), firstState)
            try store.flush()
        }

        do {
            let store = UserDefaultsReadingStateStore(
                userDefaults: userDefaults,
                maxEntries: 2,
                debounceInterval: 60
            )
            try store.saveState(thirdState)
            try store.flush()
        }

        let verifier = UserDefaultsReadingStateStore(
            userDefaults: userDefaults,
            maxEntries: 2,
            debounceInterval: 60
        )
        XCTAssertNil(try verifier.loadState(for: second))
        XCTAssertEqual(try verifier.loadState(for: first), firstState)
        XCTAssertEqual(try verifier.loadState(for: third), thirdState)
    }

    func testDictionaryOnlyStateMigratesLRUWithoutLosingReadingProgress() throws {
        let suiteName = "SereinTests.ReadingStateStore.LegacyMigration.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let first = URL(fileURLWithPath: "/tmp/migration-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/migration-second.pdf")
        let legacyStates = [
            first.absoluteString: makeState(url: first, page: 4),
            second.absoluteString: makeState(url: second, page: 8),
        ]
        userDefaults.set(
            try JSONEncoder().encode(legacyStates),
            forKey: UserDefaultsReadingStateStore.stateKey
        )

        let store = UserDefaultsReadingStateStore(userDefaults: userDefaults, debounceInterval: 0)

        XCTAssertEqual(try store.loadState(for: first)?.readingPosition.pageIndex, 4)
        XCTAssertEqual(try store.loadState(for: second)?.readingPosition.pageIndex, 8)
        let migratedStates = try JSONDecoder().decode(
            [String: PersistedReadingState].self,
            from: try XCTUnwrap(userDefaults.data(forKey: UserDefaultsReadingStateStore.stateKey))
        )
        let migratedOrder = try JSONDecoder().decode(
            [String].self,
            from: try XCTUnwrap(userDefaults.data(forKey: UserDefaultsReadingStateStore.lruKey))
        )
        XCTAssertEqual(migratedStates, legacyStates)
        XCTAssertEqual(Set(migratedOrder), Set(legacyStates.keys))
    }

    func testDebouncedWriteFlushesOnDemand() throws {
        let suiteName = "SereinTests.ReadingStateStore.Flush.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsReadingStateStore(
            userDefaults: userDefaults,
            debounceInterval: 60
        )
        let url = URL(fileURLWithPath: "/tmp/flush.pdf")
        let expectedState = PersistedReadingState(
            url: url,
            displayMode: .twoUpContinuous,
            scaleMode: .fitWidth,
            scaleFactor: 1.65,
            readingPosition: ReadingPosition(pageIndex: 3, point: CGPoint(x: 21, y: 34))
        )
        try store.saveState(expectedState)

        // In-memory load works before disk flush.
        XCTAssertEqual(try store.loadState(for: url), expectedState)
        XCTAssertNil(userDefaults.data(forKey: UserDefaultsReadingStateStore.stateKey))

        try store.flush()

        let peer = UserDefaultsReadingStateStore(userDefaults: userDefaults, debounceInterval: 0)
        XCTAssertEqual(try peer.loadState(for: url), expectedState)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeState(url: URL, page: Int) -> PersistedReadingState {
        PersistedReadingState(
            url: url,
            displayMode: .singlePageContinuous,
            scaleMode: .manual,
            scaleFactor: 1.0,
            readingPosition: ReadingPosition(pageIndex: page, point: .zero)
        )
    }
}
