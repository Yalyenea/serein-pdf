import Foundation
import XCTest
@testable import Serein

final class RecentFilesStoreTests: XCTestCase {
    func testRecordOpenDeduplicatesAndMovesFileToFront() throws {
        let userDefaults = makeUserDefaults()
        let store = UserDefaultsRecentFilesStore(maxCount: 5, userDefaults: userDefaults)
        let first = try makeTemporaryFile(named: "first.pdf")
        let second = try makeTemporaryFile(named: "second.pdf")

        _ = try store.recordOpen(for: first)
        _ = try store.recordOpen(for: second)
        let recentFiles = try store.recordOpen(for: first)

        XCTAssertEqual(recentFiles, [first, second])
        XCTAssertEqual(try store.loadRecentFiles(), [first, second])
    }

    func testRecordOpenKeepsNewestFilesWithinCapacity() throws {
        let userDefaults = makeUserDefaults()
        let store = UserDefaultsRecentFilesStore(maxCount: 2, userDefaults: userDefaults)
        let first = try makeTemporaryFile(named: "first.pdf")
        let second = try makeTemporaryFile(named: "second.pdf")
        let third = try makeTemporaryFile(named: "third.pdf")

        _ = try store.recordOpen(for: first)
        _ = try store.recordOpen(for: second)
        let recentFiles = try store.recordOpen(for: third)

        XCTAssertEqual(recentFiles, [third, second])
    }

    func testDefaultCapacityKeepsTwoHundredNewestFiles() throws {
        let userDefaults = makeUserDefaults()
        let store = UserDefaultsRecentFilesStore(userDefaults: userDefaults)
        var urls: [URL] = []
        for index in 0..<220 {
            let url = try makeTemporaryFile(named: "item-\(index).pdf")
            urls.append(url)
            _ = try store.recordOpen(for: url)
        }

        let recentFiles = try store.loadRecentFiles()
        XCTAssertEqual(recentFiles.count, 200)
        XCTAssertEqual(recentFiles.first, urls[219])
        XCTAssertEqual(recentFiles.last, urls[20])
    }

    func testLoadRecentFilesPrunesMissingLinksAndPersistsPrunedList() throws {
        let userDefaults = makeUserDefaults()
        let existing = try makeTemporaryFile(named: "existing.pdf")
        let missing = existing.deletingLastPathComponent().appendingPathComponent("missing.pdf")
        let seededData = try JSONEncoder().encode([missing, existing, existing])
        userDefaults.set(seededData, forKey: "Serein.RecentFiles")
        let store = UserDefaultsRecentFilesStore(userDefaults: userDefaults)

        let loaded = try store.loadRecentFiles()

        XCTAssertEqual(loaded, [existing])
        XCTAssertEqual(try store.loadRecentFiles(), [existing])
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "SereinTests.RecentFilesStore.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func makeTemporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SereinTests.RecentFiles.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: fileURL)
        return fileURL
    }
}
