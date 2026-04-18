import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

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

    func testRemoveHighlightsOnlyDeletesTheMatchedAnnotation() throws {
        let document = try makeSearchableDocument(text: "alpha beta")
        let page = try XCTUnwrap(document.page(at: 0))
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)

        XCTAssertEqual(HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor), 1)
        XCTAssertEqual(HighlightService.applyHighlight(to: betaSelection, color: HighlightColor.green.nsColor), 1)
        XCTAssertEqual(page.annotations.count, 2)

        let removedCount = HighlightService.removeHighlights(in: alphaSelection)

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertEqual(page.annotations.first?.color.cgColor.components, HighlightColor.green.nsColor.cgColor.components)
    }

    func testHighlightAnnotationAtPointReturnsCoveringHighlight() throws {
        let document = try makeSearchableDocument(text: "alpha beta")
        let page = try XCTUnwrap(document.page(at: 0))
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        XCTAssertEqual(HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor), 1)
        XCTAssertEqual(HighlightService.applyHighlight(to: betaSelection, color: HighlightColor.green.nsColor), 1)

        let alphaBounds = alphaSelection.bounds(for: page)
        let alphaCenter = NSPoint(x: alphaBounds.midX, y: alphaBounds.midY)
        let outside = NSPoint(x: alphaBounds.maxX + 1000, y: alphaBounds.maxY + 1000)

        let hitAlpha = HighlightService.highlightAnnotation(at: alphaCenter, on: page)
        XCTAssertEqual(hitAlpha?.color.cgColor.components, HighlightColor.pink.nsColor.cgColor.components)
        XCTAssertNil(HighlightService.highlightAnnotation(at: outside, on: page))
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
