import AppKit
import PDFKit
import XCTest
@testable import Serein

final class CleanPDFServiceTests: XCTestCase {
    func testCleanCopyRemovesVisibleAnnotationsAndPreservesLinksAndWidgets() throws {
        let document = makeAnnotatedDocument()

        let cleanData = try CleanPDFService.cleanCopyData(from: document)
        let cleanDocument = try XCTUnwrap(PDFDocument(data: cleanData))
        let cleanAnnotations = try XCTUnwrap(cleanDocument.page(at: 0)?.annotations)
        let cleanTypes = cleanAnnotations.compactMap(\.type).sorted()

        XCTAssertEqual(cleanTypes, ["Link", "Widget"])
        let originalTypes = try XCTUnwrap(document.page(at: 0)?.annotations.compactMap(\.type))
        XCTAssertTrue(originalTypes.contains("Highlight"))
        XCTAssertTrue(originalTypes.contains("Underline"))
        XCTAssertTrue(originalTypes.contains("Text"))
        XCTAssertTrue(originalTypes.contains("Square"))
        XCTAssertTrue(originalTypes.contains("Link"))
        XCTAssertTrue(originalTypes.contains("Widget"))
    }

    func testWriteCleanCopyWritesFilteredPDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("clean.pdf")

        try CleanPDFService.writeCleanCopy(from: makeAnnotatedDocument(), to: outputURL)

        let cleanDocument = try XCTUnwrap(PDFDocument(url: outputURL))
        let cleanTypes = try XCTUnwrap(cleanDocument.page(at: 0)?.annotations.compactMap(\.type).sorted())
        XCTAssertEqual(cleanTypes, ["Link", "Widget"])
    }

    private func makeAnnotatedDocument() -> PDFDocument {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 260))

        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
        image.unlockFocus()

        let page = PDFPage(image: image)!
        document.insert(page, at: 0)

        [
            PDFAnnotation(bounds: NSRect(x: 20, y: 210, width: 80, height: 16), forType: .highlight, withProperties: nil),
            PDFAnnotation(bounds: NSRect(x: 20, y: 180, width: 80, height: 16), forType: .underline, withProperties: nil),
            PDFAnnotation(bounds: NSRect(x: 20, y: 145, width: 24, height: 24), forType: .text, withProperties: nil),
            PDFAnnotation(bounds: NSRect(x: 20, y: 105, width: 48, height: 28), forType: .square, withProperties: nil),
            PDFAnnotation(bounds: NSRect(x: 20, y: 65, width: 80, height: 18), forType: .link, withProperties: nil),
            PDFAnnotation(bounds: NSRect(x: 20, y: 25, width: 80, height: 18), forType: .widget, withProperties: nil),
        ].forEach { page.addAnnotation($0) }

        return document
    }
}
