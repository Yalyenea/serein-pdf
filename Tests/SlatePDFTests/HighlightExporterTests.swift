import Foundation
import XCTest
@testable import SlatePDF

final class HighlightExporterTests: XCTestCase {
    func testMarkdownExportIncludesCommentAndPageHeaders() throws {
        let markdown = try XCTUnwrap(
            String(
                data: try HighlightExporter.export(sampleGroups(), format: .markdown),
                encoding: .utf8
            )
        )

        XCTAssertTrue(markdown.contains("# Highlights"))
        XCTAssertTrue(markdown.contains("## Page 1"))
        XCTAssertTrue(markdown.contains("Color: Pink"))
        XCTAssertTrue(markdown.contains("Comment: Key idea"))
    }

    func testPlainTextExportIncludesSnippetAndComment() throws {
        let text = try XCTUnwrap(
            String(
                data: try HighlightExporter.export(sampleGroups(), format: .plainText),
                encoding: .utf8
            )
        )

        XCTAssertTrue(text.contains("Page 1 | Pink"))
        XCTAssertTrue(text.contains("Snippet: alpha beta"))
        XCTAssertTrue(text.contains("Comment: Key idea"))
    }

    func testJSONExportIncludesCommentAndCreatedAt() throws {
        let data = try HighlightExporter.export(sampleGroups(), format: .json)
        let exported = try JSONDecoder().decode([ExportedHighlight].self, from: data)

        XCTAssertEqual(exported.count, 2)
        XCTAssertEqual(exported.first?.page, 1)
        XCTAssertEqual(exported.first?.color, "pink")
        XCTAssertEqual(exported.first?.comment, "Key idea")
        XCTAssertNotNil(exported.first?.createdAt)
        XCTAssertNil(exported.last?.comment)
    }

    private func sampleGroups() -> [DocumentHighlightGroup] {
        [
            DocumentHighlightGroup(
                groupID: "a",
                pageIndex: 0,
                snippet: "alpha beta",
                color: .pink,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                comment: "Key idea",
                primarySelection: nil,
                records: []
            ),
            DocumentHighlightGroup(
                groupID: "b",
                pageIndex: 1,
                snippet: "gamma delta",
                color: .green,
                createdAt: nil,
                comment: "",
                primarySelection: nil,
                records: []
            ),
        ]
    }
}
