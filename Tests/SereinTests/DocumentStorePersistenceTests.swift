import Foundation
import XCTest
@testable import Serein

final class DocumentStorePersistenceTests: XCTestCase {
    func testDebouncedSavesCoalesceAndFlushLatestState() throws {
        let suiteName = "SereinTests.DocumentStorePersistence.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsDocumentStorePersistence(
            userDefaults: userDefaults,
            debounceInterval: 60
        )
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let first = PersistedDocumentStoreState(
            sessions: [.init(url: firstURL)],
            activeSessionURL: firstURL,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: true,
            isRightSidebarVisible: true
        )
        let secondURL = URL(fileURLWithPath: "/tmp/second.pdf")
        let second = PersistedDocumentStoreState(
            sessions: [.init(url: secondURL)],
            activeSessionURL: secondURL,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: true,
            isRightSidebarVisible: true
        )

        try persistence.saveState(first)
        try persistence.saveState(second)
        XCTAssertNil(userDefaults.data(forKey: UserDefaultsDocumentStorePersistence.stateKey))

        try persistence.flush()

        let stored = try JSONDecoder().decode(
            PersistedDocumentStoreState.self,
            from: try XCTUnwrap(userDefaults.data(forKey: UserDefaultsDocumentStorePersistence.stateKey))
        )
        XCTAssertEqual(stored, second)
    }

    func testLoadTracksPersistedStateSoUnchangedSaveDoesNotBecomePending() throws {
        let suiteName = "SereinTests.DocumentStorePersistence.Unchanged.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let state = PersistedDocumentStoreState(
            sessions: [],
            activeSessionURL: nil,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: true,
            isRightSidebarVisible: true
        )
        userDefaults.set(
            try JSONEncoder().encode(state),
            forKey: UserDefaultsDocumentStorePersistence.stateKey
        )
        let persistence = UserDefaultsDocumentStorePersistence(
            userDefaults: userDefaults,
            debounceInterval: 60
        )

        let loadedState = try XCTUnwrap(persistence.loadState())
        XCTAssertEqual(loadedState, state)
        try persistence.saveState(loadedState)
        userDefaults.removeObject(forKey: UserDefaultsDocumentStorePersistence.stateKey)
        try persistence.flush()

        XCTAssertNil(userDefaults.data(forKey: UserDefaultsDocumentStorePersistence.stateKey))
    }
}
