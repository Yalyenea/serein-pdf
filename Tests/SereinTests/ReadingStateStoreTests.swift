import Foundation
import XCTest
@testable import Serein

final class ReadingStateStoreTests: XCTestCase {
    func testSaveAndLoadReadingStateByDocumentURL() throws {
        let suiteName = "SereinTests.ReadingStateStore.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsReadingStateStore(userDefaults: userDefaults)
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
}
