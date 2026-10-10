import AppKit
import PDFKit
import XCTest
@testable import Serein

final class OutlineExtractorTests: XCTestCase {
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

    func testExtractResolvesUnspecifiedAxesAgainstCropBoxWithoutRoundingExplicitCoordinates() throws {
        let document = makeDocument(pageCount: 2)
        let page = try XCTUnwrap(document.page(at: 1))
        let cropBox = CGRect(x: 11.25, y: 17.5, width: 120.5, height: 190.75)
        page.setBounds(cropBox, for: .cropBox)
        let unspecified = kPDFDestinationUnspecifiedValue
        let cases: [(point: CGPoint, expected: CGPoint)] = [
            (CGPoint(x: unspecified, y: unspecified), CGPoint(x: cropBox.minX, y: cropBox.maxY)),
            (CGPoint(x: unspecified, y: 120.625), CGPoint(x: cropBox.minX, y: 120.625)),
            (CGPoint(x: 36.875, y: unspecified), CGPoint(x: 36.875, y: cropBox.maxY)),
            (CGPoint(x: 36.875, y: 120.625), CGPoint(x: 36.875, y: 120.625)),
        ]
        let root = PDFOutline()
        for (index, testCase) in cases.enumerated() {
            let item = PDFOutline()
            item.label = "Destination \(index)"
            item.destination = PDFDestination(page: page, at: testCase.point)
            root.insertChild(item, at: index)
        }
        document.outlineRoot = root

        let extracted = OutlineExtractor.extract(from: document)

        XCTAssertEqual(extracted.count, cases.count)
        for (node, testCase) in zip(extracted, cases) {
            XCTAssertEqual(node.pageIndex, 1)
            XCTAssertEqual(node.destinationPoint, testCase.expected)
        }
    }

    func testExtractResolvesUnspecifiedGoToActionDestinationAxes() throws {
        let document = makeDocument(pageCount: 2)
        let page = try XCTUnwrap(document.page(at: 1))
        let root = PDFOutline()
        let item = PDFOutline()
        item.label = "Unspecified action destination"
        item.action = PDFActionGoTo(destination: PDFDestination(
            page: page,
            at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue)
        ))
        root.insertChild(item, at: 0)
        document.outlineRoot = root

        let extracted = try XCTUnwrap(OutlineExtractor.extract(from: document).first)

        XCTAssertEqual(extracted.pageIndex, 1)
        XCTAssertEqual(extracted.destinationPoint, CGPoint(
            x: page.bounds(for: .cropBox).minX,
            y: page.bounds(for: .cropBox).maxY
        ))
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

    func testExtractIgnoresDestinationOutsideDocument() throws {
        let document = makeDocument(pageCount: 1)
        let otherDocument = makeDocument(pageCount: 1)
        let root = PDFOutline()
        let item = PDFOutline()
        item.label = "Invalid destination"
        item.destination = PDFDestination(page: try XCTUnwrap(otherDocument.page(at: 0)), at: .zero)
        root.insertChild(item, at: 0)
        document.outlineRoot = root

        let extracted = try XCTUnwrap(OutlineExtractor.extract(from: document).first)

        XCTAssertEqual(extracted.title, "Invalid destination")
        XCTAssertNil(extracted.pageIndex)
        XCTAssertNil(extracted.destinationPoint)
    }
}
