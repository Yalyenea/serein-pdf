import Foundation
import XCTest
@testable import Serein

@MainActor
final class PDFFileMonitorTests: XCTestCase {
    func testDirectoryMonitorReportsOnlyChangedPDF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SereinTests.PDFFileMonitor.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let changed = expectation(description: "changed PDF reported")
        let monitor = PDFFileMonitor(debounceInterval: 0, pollingInterval: 0.1)
        var changedURLs: [URL] = []
        monitor.onChange = { url in
            changedURLs.append(url)
            changed.fulfill()
        }
        monitor.replaceMonitoredURLs(with: [first, second])
        try await Task.sleep(for: .milliseconds(200))

        try Data("first changed".utf8).write(to: first)
        await fulfillment(of: [changed], timeout: 2)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(changedURLs, [first.standardizedFileURL])
    }
}
