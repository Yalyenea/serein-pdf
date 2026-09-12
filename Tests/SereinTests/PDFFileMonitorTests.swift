import Foundation
import XCTest
@testable import Serein

@MainActor
final class PDFFileMonitorTests: XCTestCase {
    func testDirectoryMonitorReportsOnlyChangedPDF() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let changed = expectation(description: "changed PDF reported")
        let monitor = PDFFileMonitor(debounceInterval: 0)
        var changedURLs: [URL] = []
        monitor.onChange = { url in
            changedURLs.append(url)
            changed.fulfill()
        }
        monitor.replaceMonitoredURLs(with: [first, second])
        try await Task.sleep(for: .milliseconds(200))

        try appendInPlace(to: first)
        await fulfillment(of: [changed], timeout: 2)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(changedURLs, [first.standardizedFileURL])
    }

    func testIdleMonitorDoesNotPollFileMetadata() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try (0..<20).map { index in
            let url = directory.appendingPathComponent("\(index).pdf")
            try Data("PDF \(index)".utf8).write(to: url)
            return url
        }
        let recorder = SnapshotRecorder()
        let monitor = PDFFileMonitor(debounceInterval: 0, snapshotProvider: recorder.capture)
        monitor.replaceMonitoredURLs(with: Set(urls))
        try await Task.sleep(for: .milliseconds(200))
        let baseline = recorder.count
        XCTAssertEqual(baseline, urls.count)

        try await Task.sleep(for: .milliseconds(1_200))

        XCTAssertEqual(recorder.count, baseline)
        monitor.replaceMonitoredURLs(with: [])
    }

    func testInPlaceChangeScansOnlyAffectedFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let recorder = SnapshotRecorder()
        let monitor = PDFFileMonitor(debounceInterval: 0.02, snapshotProvider: recorder.capture)
        monitor.replaceMonitoredURLs(with: [first, second])
        try await Task.sleep(for: .milliseconds(200))
        recorder.reset()
        let changed = expectation(description: "in-place write reported")
        monitor.onChange = { _ in changed.fulfill() }

        try appendInPlace(to: first)
        await fulfillment(of: [changed], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(Set(recorder.urls), [first.standardizedFileURL])
    }

    func testAtomicReplacementRearmsFileMonitorForLaterInPlaceWrites() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("replaced.pdf")
        try Data("original".utf8).write(to: url)
        let monitor = PDFFileMonitor(debounceInterval: 0.02)
        monitor.replaceMonitoredURLs(with: [url])
        try await Task.sleep(for: .milliseconds(200))
        let replaced = expectation(description: "atomic replacement reported")
        monitor.onChange = { changedURL in
            XCTAssertEqual(changedURL, url.standardizedFileURL)
            replaced.fulfill()
        }

        try Data("replacement".utf8).write(to: url, options: .atomic)
        await fulfillment(of: [replaced], timeout: 2)
        let written = expectation(description: "replacement vnode write reported")
        monitor.onChange = { _ in written.fulfill() }
        try appendInPlace(to: url)
        await fulfillment(of: [written], timeout: 2)
    }

    func testDeletedPDFCanBeRecreatedAndMonitoredAgain() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recreated.pdf")
        try Data("original".utf8).write(to: url)
        let monitor = PDFFileMonitor(debounceInterval: 0.02)
        monitor.replaceMonitoredURLs(with: [url])
        try await Task.sleep(for: .milliseconds(200))
        let deleted = expectation(description: "deletion reported")
        monitor.onChange = { _ in deleted.fulfill() }
        try FileManager.default.removeItem(at: url)
        await fulfillment(of: [deleted], timeout: 2)

        let recreated = expectation(description: "recreation reported")
        monitor.onChange = { _ in recreated.fulfill() }
        try Data("recreated".utf8).write(to: url)
        await fulfillment(of: [recreated], timeout: 2)

        let written = expectation(description: "recreated vnode write reported")
        monitor.onChange = { _ in written.fulfill() }
        try appendInPlace(to: url)
        await fulfillment(of: [written], timeout: 2)
    }

    func testRemovingURLStopsItsFileEvents() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let recorder = SnapshotRecorder()
        let monitor = PDFFileMonitor(debounceInterval: 0.02, snapshotProvider: recorder.capture)
        monitor.replaceMonitoredURLs(with: [first, second])
        try await Task.sleep(for: .milliseconds(200))
        monitor.replaceMonitoredURLs(with: [first])
        try await Task.sleep(for: .milliseconds(100))
        recorder.reset()
        let changed = expectation(description: "removed PDF is ignored")
        changed.isInverted = true
        monitor.onChange = { _ in changed.fulfill() }

        try appendInPlace(to: second)
        await fulfillment(of: [changed], timeout: 0.2)

        XCTAssertTrue(recorder.urls.isEmpty)
        monitor.replaceMonitoredURLs(with: [])
    }

    func testDeletedParentDirectoryRebindsThroughExistingAncestor() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ancestor = root.appendingPathComponent("ancestor")
        let directory = ancestor.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recreated.pdf")
        try Data("original".utf8).write(to: url)
        let monitor = PDFFileMonitor(debounceInterval: 0.02)
        monitor.replaceMonitoredURLs(with: [url])
        try await Task.sleep(for: .milliseconds(200))
        let deleted = expectation(description: "parent removal reported")
        monitor.onChange = { _ in deleted.fulfill() }

        try FileManager.default.removeItem(at: ancestor)
        await fulfillment(of: [deleted], timeout: 2)
        let recreated = expectation(description: "rebuilt parent reported")
        monitor.onChange = { _ in recreated.fulfill() }
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("recreated".utf8).write(to: url)
        await fulfillment(of: [recreated], timeout: 2)

        let written = expectation(description: "rebuilt parent file vnode write reported")
        monitor.onChange = { _ in written.fulfill() }
        try appendInPlace(to: url)
        await fulfillment(of: [written], timeout: 2)
    }

    func testRenamedParentDirectoryRebindsToReplacement() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("replaced.pdf")
        try Data("original".utf8).write(to: url)
        let monitor = PDFFileMonitor(debounceInterval: 0.02)
        monitor.replaceMonitoredURLs(with: [url])
        try await Task.sleep(for: .milliseconds(200))
        let moved = expectation(description: "parent rename reported")
        monitor.onChange = { _ in moved.fulfill() }

        try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("old-documents"))
        await fulfillment(of: [moved], timeout: 2)
        let replaced = expectation(description: "replacement parent reported")
        monitor.onChange = { _ in replaced.fulfill() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: url)
        await fulfillment(of: [replaced], timeout: 2)

        let written = expectation(description: "replacement parent file vnode write reported")
        monitor.onChange = { _ in written.fulfill() }
        try appendInPlace(to: url)
        await fulfillment(of: [written], timeout: 2)
    }

    private func makeDirectory() throws -> URL {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = project.appendingPathComponent(".tmp/PDFFileMonitorTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appendInPlace(to url: URL) throws {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: Data(" changed".utf8))
    }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedURLs: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return capturedURLs
    }

    var count: Int { urls.count }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        capturedURLs.removeAll()
    }

    func capture(_ url: URL) -> PDFFileSnapshot? {
        lock.lock()
        capturedURLs.append(url)
        lock.unlock()
        return PDFFileSnapshot(url: url)
    }
}
