import Foundation
import XCTest
@testable import Serein

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
        XCTAssertTrue(markdown.contains("- alpha beta"))
        XCTAssertTrue(markdown.contains("  - Key idea"))
        XCTAssertFalse(markdown.contains("Color:"))
        XCTAssertFalse(markdown.contains("Comment:"))
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
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(exported.count, 2)
        XCTAssertEqual(exported.first?.page, 1)
        XCTAssertEqual(exported.first?.color, "pink")
        XCTAssertEqual(exported.first?.comment, "Key idea")
        XCTAssertNotNil(exported.first?.createdAt)
        XCTAssertNil(exported.last?.comment)
        XCTAssertNil(object.first?["document"])
    }

    func testAllOpenMarkdownAndPlainTextPreserveDocumentThenPageHierarchy() throws {
        let markdown = try XCTUnwrap(
            String(
                data: try HighlightExporter.exportAllOpen(sampleDocuments(), format: .markdown),
                encoding: .utf8
            )
        )
        let plainText = try XCTUnwrap(
            String(
                data: try HighlightExporter.exportAllOpen(sampleDocuments(), format: .plainText),
                encoding: .utf8
            )
        )

        assertOrdered(
            ["## Second PDF", "### Page 2", "## First PDF", "### Page 1"],
            in: markdown
        )
        assertOrdered(
            ["Document: Second PDF", "Page 2", "Document: First PDF", "Page 1"],
            in: plainText
        )
        XCTAssertFalse(markdown.contains("Empty PDF"))
        XCTAssertFalse(plainText.contains("Empty PDF"))
    }

    func testAllOpenJSONUsesAggregateSchemaWithDocumentPerHighlight() throws {
        let data = try HighlightExporter.exportAllOpen(sampleDocuments(), format: .json)
        let exported = try JSONDecoder().decode([AggregateExportedHighlight].self, from: data)

        XCTAssertEqual(exported.map(\.document), ["Second PDF", "First PDF"])
        XCTAssertEqual(exported.map(\.page), [2, 1])
        XCTAssertEqual(exported.map(\.snippet), ["gamma delta", "alpha beta"])
    }

    func testAllOpenDefaultFilenameUsesRequestedFormat() {
        XCTAssertEqual(
            HighlightExporter.defaultAllOpenFilename(format: .markdown),
            "All-Open-highlights.md"
        )
        XCTAssertEqual(
            HighlightExporter.defaultAllOpenFilename(format: .plainText),
            "All-Open-highlights.txt"
        )
        XCTAssertEqual(
            HighlightExporter.defaultAllOpenFilename(format: .json),
            "All-Open-highlights.json"
        )
    }

    func testMarkdownExportPreservesChineseSnippetAndComment() throws {
        let markdown = try XCTUnwrap(
            String(
                data: try HighlightExporter.export(
                    [
                        DocumentHighlightGroup(
                            groupID: "cn",
                            pageIndex: 0,
                            snippet: "中文高亮",
                            color: .pink,
                            createdAt: nil,
                            comment: "关键想法",
                            primarySelection: nil,
                            records: []
                        ),
                    ],
                    format: .markdown
                ),
                encoding: .utf8
            )
        )

        XCTAssertTrue(markdown.contains("- 中文高亮"))
        XCTAssertTrue(markdown.contains("  - 关键想法"))
        XCTAssertFalse(markdown.contains("Color:"))
        XCTAssertFalse(markdown.contains("Comment:"))
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

    private func sampleDocuments() -> [HighlightExporter.DocumentGroups] {
        let groups = sampleGroups()
        return [
            (documentTitle: "Second PDF", groups: [groups[1]]),
            (documentTitle: "Empty PDF", groups: []),
            (documentTitle: "First PDF", groups: [groups[0]]),
        ]
    }

    private func assertOrdered(_ values: [String], in output: String) {
        var start = output.startIndex
        for value in values {
            guard let range = output.range(of: value, range: start..<output.endIndex) else {
                XCTFail("Missing or out-of-order value: \(value)")
                return
            }
            start = range.upperBound
        }
    }
}
