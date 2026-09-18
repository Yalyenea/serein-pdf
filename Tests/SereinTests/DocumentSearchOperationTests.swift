import Foundation
import XCTest
@testable import Serein

@MainActor
final class DocumentSearchOperationTests: XCTestCase {
    func testWholeWordPreviewUsesAcceptedSelectionLocation() async throws {
        let url = try TestPDFFixtures.makeSearchablePDF(
            named: "whole-word-preview",
            pages: ["needles decoy " + String(repeating: "padding ", count: 10) + "needle target"]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sessionID = UUID()
        let source = SearchSnapshotSource(
            query: "needle",
            scope: .currentDocument,
            options: SearchOptions(matchesWholeWords: true),
            targets: [SearchSnapshotSource.Target(
                sessionID: sessionID,
                sessionTitle: "Preview",
                url: url,
                fileSnapshot: PDFFileSnapshot(url: url)
            )]
        )
        let operation = DocumentSearchOperation(source: source)
        let completed = expectation(description: "Search completed")
        var matches: [DocumentSearchMatch] = []
        operation.onUpdate = { results, isSearching in
            guard !isSearching else { return }
            matches = results[sessionID, default: []]
            completed.fulfill()
        }
        operation.start()
        await fulfillment(of: [completed], timeout: 3)
        operation.cancel()

        XCTAssertEqual(matches.count, 1)
        let match = try XCTUnwrap(matches.first)
        XCTAssertTrue(match.previewText.contains("needle target"), match.previewText)
        XCTAssertFalse(match.previewText.contains("decoy"), match.previewText)
    }
}
