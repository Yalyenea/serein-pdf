import Foundation
import XCTest
@testable import Serein

final class DocumentStorePersistenceTests: XCTestCase {
    func testLegacyJSONWithoutWindowsPreservesReaderStateAndSuppliesDefaults() throws {
        let legacyJSON = """
        {
            "sessions": [{ "url": "file:///tmp/legacy.pdf" }],
            "activeSessionURL": "file:///tmp/legacy.pdf",
            "tabPresentationMode": "horizontalTitlebar",
            "isLeftSidebarVisible": false,
            "isRightSidebarVisible": false
        }
        """
        let state = try JSONDecoder().decode(
            PersistedDocumentStoreState.self,
            from: Data(legacyJSON.utf8)
        )
        let url = URL(fileURLWithPath: "/tmp/legacy.pdf")
        XCTAssertEqual(state.sessions.map(\.url), [url])
        XCTAssertNil(state.sessions.first?.title)
        XCTAssertEqual(state.activeSessionURL, url)
        XCTAssertEqual(state.tabPresentationMode, .horizontalTitlebar)
        XCTAssertFalse(state.isLeftSidebarVisible)
        XCTAssertFalse(state.isRightSidebarVisible)
        XCTAssertEqual(state.windows.count, 1)
        let window = try XCTUnwrap(state.windows.first)
        XCTAssertEqual(window.sessionURLs, [url])
        XCTAssertTrue(window.sessionIDs.isEmpty)
        XCTAssertTrue(window.continuousReadingSessionIDs.isEmpty)
        XCTAssertEqual(window.rightSidebarMode, .outline)
        XCTAssertEqual(window.searchQuery, "")
        XCTAssertEqual(window.searchScope, .currentDocument)
        XCTAssertTrue(window.recentlyClosedURLs.isEmpty)
        XCTAssertFalse(window.splitState.isEnabled)
        XCTAssertEqual(window.splitState.primarySessionURL, url)
        XCTAssertNil(window.splitState.primarySessionID)
        XCTAssertNil(window.splitState.secondarySessionID)
        XCTAssertNil(window.splitState.secondarySessionURL)
        XCTAssertEqual(window.splitState.focusedPane, .primary)

        let minimal = try JSONDecoder().decode(
            PersistedDocumentStoreState.self,
            from: Data(#"{"sessions": []}"#.utf8)
        )
        XCTAssertTrue(minimal.sessions.isEmpty)
        XCTAssertEqual(minimal.windows.count, 1)
        XCTAssertNil(minimal.activeSessionURL)
        XCTAssertEqual(minimal.tabPresentationMode, .verticalSidebar)
        XCTAssertTrue(minimal.isLeftSidebarVisible)
        XCTAssertTrue(minimal.isRightSidebarVisible)
        XCTAssertEqual(minimal.windows.first?.sessionURLs, [])
    }

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
