import Foundation
import XCTest
@testable import SlatePDF

final class RecentFilesStoreTests: XCTestCase {
    func testRecordOpenDeduplicatesAndMovesFileToFront() throws {
        let userDefaults = makeUserDefaults()
        let store = UserDefaultsRecentFilesStore(maxCount: 5, userDefaults: userDefaults)
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")

        _ = try store.recordOpen(for: first)
        _ = try store.recordOpen(for: second)
        let recentFiles = try store.recordOpen(for: first)

        XCTAssertEqual(recentFiles, [first, second])
        XCTAssertEqual(try store.loadRecentFiles(), [first, second])
    }

    func testRecordOpenKeepsNewestFilesWithinCapacity() throws {
        let userDefaults = makeUserDefaults()
        let store = UserDefaultsRecentFilesStore(maxCount: 2, userDefaults: userDefaults)
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        let third = URL(fileURLWithPath: "/tmp/third.pdf")

        _ = try store.recordOpen(for: first)
        _ = try store.recordOpen(for: second)
        let recentFiles = try store.recordOpen(for: third)

        XCTAssertEqual(recentFiles, [third, second])
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "SlatePDFTests.RecentFilesStore.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
