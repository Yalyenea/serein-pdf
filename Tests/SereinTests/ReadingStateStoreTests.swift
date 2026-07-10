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
            displayMode: .twoUpContinuous,
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

    func testDebouncedWriteFlushesOnDemand() throws {
        let suiteName = "SereinTests.ReadingStateStore.Flush.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsReadingStateStore(
            userDefaults: userDefaults,
            debounceInterval: 60
        )
        let url = URL(fileURLWithPath: "/tmp/flush.pdf")
        try store.saveState(makeState(url: url, page: 3))

        // In-memory load works before disk flush.
        XCTAssertEqual(try store.loadState(for: url)?.readingPosition.pageIndex, 3)
        XCTAssertNil(userDefaults.data(forKey: "Serein.ReadingState"))

        try store.flush()
        XCTAssertNotNil(userDefaults.data(forKey: "Serein.ReadingState"))

        // Fresh instance reads flushed disk state.
        let peer = UserDefaultsReadingStateStore(userDefaults: userDefaults, debounceInterval: 0)
        XCTAssertEqual(try peer.loadState(for: url)?.readingPosition.pageIndex, 3)

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
