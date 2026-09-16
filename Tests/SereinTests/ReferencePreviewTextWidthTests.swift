import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewTextWidthTests: XCTestCase {
    func testOpeningSingleColumnFitsTextWithSmallMarginsWithoutCroppingSource() throws {
        let document = try makeDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        let cropBox = page.bounds(for: .cropBox)
        let preview = try makePreview(document: document, point: CGPoint(x: 140, y: 620))
        defer { preview.window.close() }

        try assertTextFits(in: preview.pdfView)
        XCTAssertGreaterThan(preview.pdfView.scaleFactor, preview.pdfView.bounds.width / cropBox.width * 1.3)
        XCTAssertEqual(page.bounds(for: .cropBox), cropBox)
        XCTAssertEqual(preview.pdfView.currentPage?.bounds(for: .cropBox), cropBox)
        XCTAssertFalse(preview.pdfView.currentPage === page)
    }

    func testPageEdgeAndUnspecifiedDestinationsStillFitTextWidth() throws {
        let document = try makeDocument()
        for point in [
            CGPoint(x: 0, y: 620),
            CGPoint(x: kPDFDestinationUnspecifiedValue, y: 620),
            CGPoint(x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue),
        ] {
            let preview = try makePreview(document: document, point: point)
            defer { preview.window.close() }
            try assertTextFits(in: preview.pdfView)
            XCTAssertTrue(preview.pdfView.scaleFactor.isFinite)
        }
    }

    func testFollowingLinkFitsNewPageAndHistoryPreservesUserZoom() throws {
        let document = try makeDocument()
        let preview = try makePreview(document: document, point: CGPoint(x: 140, y: 620))
        defer { preview.window.close() }
        let firstScale = preview.pdfView.scaleFactor
        let customScale = firstScale * 1.25
        preview.pdfView.scaleFactor = customScale
        preview.pdfView.layoutDocumentView()
        let firstPage = try XCTUnwrap(preview.pdfView.currentPage)
        let firstViewport = preview.pdfView.convert(preview.pdfView.bounds, to: firstPage)
        let secondPage = try XCTUnwrap(document.page(at: 1))

        XCTAssertTrue(preview.content.navigate(to: PDFDestination(
            page: secondPage, at: CGPoint(x: 90, y: 620)
        )))
        try assertTextFits(in: preview.pdfView)
        let secondScale = preview.pdfView.scaleFactor
        XCTAssertLessThan(secondScale, firstScale * 0.8)

        preview.content.goBack()
        preview.pdfView.layoutDocumentView()
        XCTAssertEqual(preview.pdfView.scaleFactor, customScale, accuracy: 0.001)
        let restoredPage = try XCTUnwrap(preview.pdfView.currentPage)
        let restoredViewport = preview.pdfView.convert(preview.pdfView.bounds, to: restoredPage)
        XCTAssertEqual(restoredViewport.minX, firstViewport.minX, accuracy: 1.5)
        XCTAssertEqual(restoredViewport.minY, firstViewport.minY, accuracy: 1.5)

        preview.content.goForward()
        XCTAssertEqual(preview.pdfView.scaleFactor, secondScale, accuracy: 0.001)
        try assertTextFits(in: preview.pdfView)
    }

    func testTextWidthFitRespectsRotationAndOffsetCropBox() throws {
        for rotation in [0, 90, 180, 270] {
            let document = try makeDocument()
            let page = try XCTUnwrap(document.page(at: 0))
            let cropBox = CGRect(x: 36, y: 48, width: 648, height: 704)
            page.setBounds(cropBox, for: .cropBox)
            page.rotation = rotation
            let preview = try makePreview(document: document, point: CGPoint(x: 140, y: 620))
            defer { preview.window.close() }

            try assertTextFits(in: preview.pdfView)
            XCTAssertEqual(page.bounds(for: .cropBox), cropBox)
            XCTAssertEqual(page.rotation, rotation)
            XCTAssertEqual(preview.pdfView.currentPage?.rotation, rotation)
            XCTAssertEqual(preview.pdfView.currentPage?.bounds(for: .cropBox), cropBox)
        }
    }

    private func assertTextFits(
        in pdfView: PDFView, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        pdfView.layoutDocumentView()
        let page = try XCTUnwrap(pdfView.currentPage, file: file, line: line)
        let text = try XCTUnwrap(page.string, file: file, line: line) as NSString
        var bounds = CGRect.null
        for index in 0..<min(page.numberOfCharacters, text.length) {
            let character = text.substring(with: NSRange(location: index, length: 1))
            guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let glyph = page.characterBounds(at: index)
            if !glyph.isEmpty { bounds = bounds.union(glyph) }
        }
        XCTAssertFalse(bounds.isNull, file: file, line: line)
        let visibleText = pdfView.convert(bounds, from: page)
        XCTAssertEqual(visibleText.minX, pdfView.bounds.minX + 12, accuracy: 2, file: file, line: line)
        XCTAssertEqual(visibleText.maxX, pdfView.bounds.maxX - 12, accuracy: 2, file: file, line: line)
    }

    private func makePreview(
        document: PDFDocument, point: CGPoint
    ) throws -> (window: NSWindow, content: ReferencePreviewViewController, pdfView: PDFView) {
        _ = NSApplication.shared
        let page = try XCTUnwrap(document.page(at: 0))
        let content = try XCTUnwrap(ReferencePreviewViewController(
            destination: PDFDestination(page: page, at: point), document: document
        ))
        let size = NSSize(width: 580, height: 360)
        content.preferredContentSize = size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = content
        content.view.frame = NSRect(origin: .zero, size: size)
        content.view.layoutSubtreeIfNeeded()
        content.positionReference()
        let pdfView = try XCTUnwrap(content.view.subviews.compactMap { $0 as? PDFView }.first)
        pdfView.layoutDocumentView()
        return (window, content, pdfView)
    }

    private func makeDocument() throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 720, height: 800)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for (x, text) in [
            (CGFloat(140), "Single column conference paper content."),
            (CGFloat(90), "A wider paragraph with substantially longer lines of text."),
        ] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for row in 0..<25 {
                NSString(string: text).draw(
                    at: CGPoint(x: x, y: 650 - CGFloat(row) * 20),
                    withAttributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.black,
                    ]
                )
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }
}
