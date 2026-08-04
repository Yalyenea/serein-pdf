import AppKit
import PDFKit
import XCTest
@testable import Serein

final class OutlineExtractorTests: XCTestCase {
    func testOutlineNodeSupportsHashingForOutlineViewIdentity() {
        let child = OutlineNode(title: "Section 1.1", pageIndex: 2, children: [])
        let first = OutlineNode(title: "Chapter 1", pageIndex: 0, children: [child])
        let second = OutlineNode(title: "Chapter 1", pageIndex: 0, children: [child])

        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testExtractReturnsEmptyForDocumentWithoutOutline() {
        let document = makeDocument(pageCount: 1)

        XCTAssertEqual(OutlineExtractor.extract(from: document), [])
    }

    func testExtractPreservesHierarchyAndPageIndices() {
        let document = makeDocument(pageCount: 3)
        let root = PDFOutline()
        let chapterPoint = CGPoint(x: 24, y: 180)
        let sectionPoint = CGPoint(x: 36, y: 120)

        let chapter = PDFOutline()
        chapter.label = "Chapter 1"
        chapter.destination = PDFDestination(page: document.page(at: 0)!, at: chapterPoint)

        let section = PDFOutline()
        section.label = "Section 1.1"
        section.destination = PDFDestination(page: document.page(at: 2)!, at: sectionPoint)

        chapter.insertChild(section, at: 0)
        root.insertChild(chapter, at: 0)
        document.outlineRoot = root

        let extracted = OutlineExtractor.extract(from: document)

        XCTAssertEqual(extracted.count, 1)
        XCTAssertEqual(extracted[0].title, "Chapter 1")
        XCTAssertEqual(extracted[0].pageIndex, 0)
        XCTAssertEqual(extracted[0].destinationPoint, chapterPoint)
        XCTAssertEqual(extracted[0].children.count, 1)
        XCTAssertEqual(extracted[0].children[0].title, "Section 1.1")
        XCTAssertEqual(extracted[0].children[0].pageIndex, 2)
        XCTAssertEqual(extracted[0].children[0].destinationPoint, sectionPoint)
    }

    func testExtractPreservesGoToActionDestinationPoint() throws {
        let document = makeDocument(pageCount: 2)
        let root = PDFOutline()
        let item = PDFOutline()
        let point = CGPoint(x: 48, y: 96)
        item.label = "Action destination"
        item.action = PDFActionGoTo(
            destination: PDFDestination(page: try XCTUnwrap(document.page(at: 1)), at: point)
        )
        root.insertChild(item, at: 0)
        document.outlineRoot = root

        let extracted = try XCTUnwrap(OutlineExtractor.extract(from: document).first)

        XCTAssertEqual(extracted.pageIndex, 1)
        XCTAssertEqual(extracted.destinationPoint, point)
    }

    private func makeDocument(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()

        for _ in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 160, height: 240))
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 240)).fill()
            image.unlockFocus()
            document.insert(PDFPage(image: image)!, at: document.pageCount)
        }

        return document
    }
}
