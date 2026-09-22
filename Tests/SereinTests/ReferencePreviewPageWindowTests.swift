import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewPageWindowTests: XCTestCase {
    func testStartsWithOneCopyAndKeepsOnlyThreeWhileReadingForwardAndBackward() throws {
        let source = TestPDFFixtures.makeBlankDocument(pageCount: 100)
        let window = try XCTUnwrap(ReferencePreviewPageWindow(document: source, pageIndex: 40))
        XCTAssertEqual(window.sourceIndices, [40])
        XCTAssertEqual(window.document.pageCount, 1)
        weak var firstCopy = window.document.page(at: 0)
        for index in 41...70 {
            XCTAssertTrue(window.extend(forward: true, keeping: index - 1))
            XCTAssertEqual(window.sourceIndices.last, index)
            XCTAssertLessThanOrEqual(window.document.pageCount, 3)
        }
        XCTAssertNil(firstCopy)
        XCTAssertEqual(window.sourceIndices, [68, 69, 70])
        for index in stride(from: 67, through: 40, by: -1) {
            XCTAssertTrue(window.extend(forward: false, keeping: index + 1))
            XCTAssertEqual(window.sourceIndices.first, index)
            XCTAssertLessThanOrEqual(window.document.pageCount, 3)
        }
        XCTAssertEqual(window.sourceIndices, [40, 41, 42])
        XCTAssertEqual(source.pageCount, 100)
        for (local, sourceIndex) in window.sourceIndices.enumerated() {
            let copy = try XCTUnwrap(window.document.page(at: local))
            XCTAssertEqual(window.sourceIndex(for: copy), sourceIndex)
            XCTAssertFalse(copy === source.page(at: sourceIndex))
        }
    }

    func testDocumentEdgesAndAnchorAreNotEvicted() throws {
        let source = TestPDFFixtures.makeBlankDocument(pageCount: 5)
        let window = try XCTUnwrap(ReferencePreviewPageWindow(document: source, pageIndex: 0))
        XCTAssertFalse(window.extend(forward: false, keeping: 0))
        XCTAssertTrue(window.extend(forward: true, keeping: 0))
        XCTAssertTrue(window.extend(forward: true, keeping: 0))
        XCTAssertFalse(window.extend(forward: true, keeping: 0))
        XCTAssertEqual(window.sourceIndices, [0, 1, 2])
        XCTAssertTrue(window.extend(forward: true, keeping: 2))
        XCTAssertTrue(window.extend(forward: true, keeping: 3))
        XCTAssertFalse(window.extend(forward: true, keeping: 4))
        XCTAssertEqual(window.sourceIndices, [2, 3, 4])
    }

    func testLazyAdjacentCopiesPreserveSourceAnnotations() throws {
        let source = TestPDFFixtures.makeBlankDocument(pageCount: 4)
        let page = try XCTUnwrap(source.page(at: 2))
        let widget = PDFAnnotation(bounds: NSRect(x: 20, y: 20, width: 80, height: 20), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text
        widget.widgetStringValue = "Original"
        widget.isReadOnly = false
        let markup = PDFAnnotation(bounds: NSRect(x: 20, y: 60, width: 80, height: 20), forType: .highlight, withProperties: nil)
        let popup = PDFAnnotation(bounds: NSRect(x: 20, y: 90, width: 80, height: 60), forType: .popup, withProperties: nil)
        markup.contents = "Source comment"
        markup.popup = popup
        page.addAnnotation(widget)
        page.addAnnotation(markup)
        page.addAnnotation(popup)
        let window = try XCTUnwrap(ReferencePreviewPageWindow(document: source, pageIndex: 1))

        XCTAssertTrue(window.extend(forward: true, keeping: 1))

        let copy = try XCTUnwrap(window.page(atSourceIndex: 2))
        let copiedWidget = try XCTUnwrap(copy.annotations.first { $0.type == "Widget" })
        XCTAssertTrue(copiedWidget.isReadOnly)
        copiedWidget.widgetStringValue = "Copy"
        XCTAssertFalse(widget.isReadOnly)
        XCTAssertEqual(widget.widgetStringValue, "Original")
        XCTAssertEqual(markup.contents, "Source comment")
        XCTAssertTrue(markup.popup === popup)
        XCTAssertTrue(popup.page === page)
        XCTAssertTrue(copy.annotations.first { $0.type == "Highlight" }?.contents?.isEmpty ?? true)
        XCTAssertFalse(copy.annotations.contains { $0.type == "Popup" })
    }
}
