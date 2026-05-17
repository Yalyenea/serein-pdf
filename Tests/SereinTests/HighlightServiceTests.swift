import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class HighlightServiceTests: XCTestCase {
    func testDefaultHighlightColorIsPink() {
        XCTAssertEqual(HighlightColor.default, .pink)
    }

    func testAllPaletteColorsAreAvailable() {
        XCTAssertEqual(Set(HighlightColor.allCases), [.pink, .yellow, .green])
    }

    func testHighlightColorHasDistinctMenuTitles() {
        let titles = HighlightColor.allCases.map(\.menuTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testSelectionContainsTextReturnsFalseForNilSelection() {
        XCTAssertFalse(HighlightService.selectionContainsText(nil))
    }

    func testDefaultColorMatchesPinkPalette() {
        XCTAssertEqual(
            HighlightService.defaultColor.cgColor.components,
            HighlightColor.pink.nsColor.cgColor.components
        )
    }

    func testHighlightAnnotationAtPointReturnsCoveringHighlight() throws {
        let document = try makeSearchableDocument(text: "alpha beta")
        let page = try XCTUnwrap(document.page(at: 0))
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        XCTAssertEqual(HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor).count, 1)
        XCTAssertEqual(HighlightService.applyHighlight(to: betaSelection, color: HighlightColor.green.nsColor).count, 1)

        let alphaBounds = alphaSelection.bounds(for: page)
        let alphaCenter = NSPoint(x: alphaBounds.midX, y: alphaBounds.midY)
        let outside = NSPoint(x: alphaBounds.maxX + 1000, y: alphaBounds.maxY + 1000)

        let hitAlpha = HighlightService.highlightAnnotation(at: alphaCenter, on: page)
        XCTAssertEqual(hitAlpha?.color.cgColor.components, HighlightColor.pink.nsColor.cgColor.components)
        XCTAssertNil(HighlightService.highlightAnnotation(at: outside, on: page))
    }

    func testTextSanitizerPreservesChineseAndRemovesHiddenUnicodeArtifacts() {
        let sanitized = PDFTextSanitizer.sanitize("中\u{0000}\u{200B}文\u{FEFF} 高\u{2060}亮")
        XCTAssertEqual(sanitized, "中文 高亮")
    }

    func testBuildHighlightGroupsPreservesChineseSnippet() throws {
        let document = try makeSearchableDocument(text: "海瑟矩阵可能非正定，导致牛顿方向其实并非下降方向。")
        let selection = try XCTUnwrap(document.findString("非正定", withOptions: []).first)
        _ = HighlightService.applyHighlight(to: selection)

        let groups = HighlightService.buildHighlightGroups(in: document)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.snippet, "非正定")
    }

    func testBuildHighlightGroupsFromRecordsOnlyUsesChangedRecords() throws {
        let document = try makeSearchableDocument(text: "alpha beta gamma")
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        _ = HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor)
        let betaRecords = HighlightService.applyHighlight(
            to: betaSelection,
            color: HighlightColor.green.nsColor,
            createdAt: Date(timeIntervalSince1970: 42)
        )
        XCTAssertTrue(HighlightService.updateComment("changed only", for: betaRecords))

        let groups = HighlightService.buildHighlightGroups(from: betaRecords)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.snippet, "beta")
        XCTAssertEqual(groups.first?.color, .green)
        XCTAssertEqual(groups.first?.comment, "changed only")
        XCTAssertEqual(groups.first?.createdAt, Date(timeIntervalSince1970: 42))
    }

    private func makeSearchableDocument(text: String) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("highlight-searchable.pdf")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 220)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create PDF context")
            throw NSError(domain: "HighlightServiceTests", code: 1)
        }

        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.white.setFill()
        NSBezierPath(rect: mediaBox).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        NSString(string: text).draw(at: NSPoint(x: 48, y: 112), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        data.write(to: url, atomically: true)

        return try XCTUnwrap(PDFDocument(url: url))
    }
}
