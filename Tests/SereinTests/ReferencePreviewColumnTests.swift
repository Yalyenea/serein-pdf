import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewColumnTests: XCTestCase {
    private let pageBounds = CGRect(x: 0, y: 0, width: 600, height: 800)

    func testSingleColumnKeepsPageWidth() {
        XCTAssertNil(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: textBlock(x: 50, top: 700, columns: 83),
            pageBounds: pageBounds,
            target: CGPoint(x: 50, y: 708)
        ))
    }

    func testTwoColumnsSelectTargetSideIncludingDestinationAboveFirstLine() throws {
        let characters = twoColumns()
        for x: CGFloat in [50, 330] {
            let bounds = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
                characterBounds: characters,
                pageBounds: pageBounds,
                target: CGPoint(x: x, y: 714)
            ))
            XCTAssertLessThan(bounds.width, pageBounds.width * 0.65)
            XCTAssertGreaterThan(bounds.width, 200)
            XCTAssertEqual(bounds.minY, pageBounds.minY)
            XCTAssertEqual(bounds.height, pageBounds.height)
            XCTAssertTrue(bounds.contains(CGPoint(x: x + 100, y: 680)))
            XCTAssertFalse(bounds.contains(CGPoint(x: x == 50 ? 430 : 150, y: 680)))
        }
    }

    func testSpanningHeadingKeepsPageWidth() {
        let heading = textBlock(x: 50, top: 750, columns: 83, rows: 2)
        XCTAssertNil(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: heading + twoColumns(),
            pageBounds: pageBounds,
            target: CGPoint(x: 50, y: 764)
        ))
    }

    func testBodyBelowSpanningHeadingStillSelectsColumn() throws {
        let heading = textBlock(x: 50, top: 750, columns: 83, rows: 2)
        let bounds = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: heading + twoColumns(),
            pageBounds: pageBounds,
            target: CGPoint(x: 330, y: 500)
        ))
        XCTAssertLessThan(bounds.width, pageBounds.width * 0.65)
        XCTAssertTrue(bounds.contains(CGPoint(x: 430, y: 500)))
        XCTAssertFalse(bounds.contains(CGPoint(x: 150, y: 500)))
    }

    func testEmptyTextKeepsPageWidth() {
        XCTAssertNil(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: [], pageBounds: pageBounds, target: CGPoint(x: 330, y: 700)
        ))
    }

    func testNarrowGutterWithMixedGlyphHeightsAndDestinationBeforeRightText() throws {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let glyphs = [
            CGRect(x: 0, y: 0, width: 5, height: 4),
            CGRect(x: 0, y: 0, width: 5, height: 10),
            CGRect(x: 0, y: -2, width: 5, height: 6),
        ]
        var characters: [CGRect] = []
        for x: CGFloat in [50, 307] {
            for row in 0..<24 {
                for column in 0..<41 {
                    characters.append(glyphs[column % glyphs.count].offsetBy(
                        dx: x + CGFloat(column) * 6, dy: 700 - CGFloat(row) * 16
                    ))
                }
            }
        }
        // Left text ends at 295; the right destination precedes its first glyph by 0.2 pt.
        let column = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: characters,
            pageBounds: bounds,
            target: CGPoint(x: 306.8, y: 712)
        ))
        XCTAssertLessThan(column.width, bounds.width * 0.65)
        XCTAssertTrue(column.contains(CGPoint(x: 307, y: 700)))
        XCTAssertTrue(column.contains(CGPoint(x: 547, y: 700)))
        XCTAssertFalse(column.contains(CGPoint(x: 150, y: 700)))
    }

    func testOffsetPageBoxPreservesColumnCoordinates() throws {
        let offset = CGPoint(x: 36, y: 48)
        let bounds = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
            characterBounds: twoColumns().map { $0.offsetBy(dx: offset.x, dy: offset.y) },
            pageBounds: pageBounds.offsetBy(dx: offset.x, dy: offset.y),
            target: CGPoint(x: 330 + offset.x, y: 714 + offset.y)
        ))
        XCTAssertEqual(bounds.minY, offset.y)
        XCTAssertEqual(bounds.height, pageBounds.height)
        XCTAssertTrue(bounds.contains(CGPoint(x: 430 + offset.x, y: 680 + offset.y)))
        XCTAssertFalse(bounds.contains(CGPoint(x: 150 + offset.x, y: 680 + offset.y)))
    }

    func testPDFPreviewEnlargesTargetColumnAndKeepsDestinationVisible() throws {
        _ = NSApplication.shared
        let document = try makeTwoColumnDocument()
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertGreaterThan(page.numberOfCharacters, 500)

        for x: CGFloat in [50, 330] {
            let target = CGPoint(x: x, y: 708)
            let controller = try XCTUnwrap(ReferencePreviewViewController(
                destination: PDFDestination(page: page, at: target), document: document
            ))
            let size = NSSize(width: 580, height: 360)
            controller.preferredContentSize = size
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentViewController = controller
            controller.view.frame = NSRect(origin: .zero, size: size)
            controller.view.layoutSubtreeIfNeeded()
            controller.positionReference()
            let pdfView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? PDFView }.first)
            pdfView.layoutDocumentView()
            let previewPage = try XCTUnwrap(pdfView.currentPage)
            let fullPage = pdfView.convert(pageBounds, from: previewPage)
            XCTAssertGreaterThan(fullPage.width, pdfView.bounds.width * 1.5)
            let destination = pdfView.convert(target, from: previewPage)
            XCTAssertTrue(pdfView.visibleRect.insetBy(dx: -1, dy: -1).contains(destination))
            XCTAssertEqual(page.bounds(for: .cropBox), pageBounds)

            let initialScale = pdfView.scaleFactor
            let otherTarget = CGPoint(x: x == 50 ? 330 : 50, y: 708)
            XCTAssertTrue(controller.navigate(to: PDFDestination(page: page, at: otherTarget)))
            let otherScale = pdfView.scaleFactor
            XCTAssertGreaterThan(otherScale, pdfView.bounds.width / pageBounds.width * 1.5)
            try assertTargetVisible(otherTarget, in: pdfView)

            controller.goBack()
            XCTAssertEqual(controller.destination.point, target)
            XCTAssertEqual(pdfView.scaleFactor, initialScale, accuracy: 0.001)
            try assertTargetVisible(target, in: pdfView)

            controller.goForward()
            XCTAssertEqual(controller.destination.point, otherTarget)
            XCTAssertEqual(pdfView.scaleFactor, otherScale, accuracy: 0.001)
            try assertTargetVisible(otherTarget, in: pdfView)
        }
    }

    private func assertTargetVisible(
        _ target: CGPoint, in pdfView: PDFView, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        pdfView.layoutDocumentView()
        let page = try XCTUnwrap(pdfView.currentPage, file: file, line: line)
        let point = pdfView.convert(target, from: page)
        XCTAssertTrue(
            pdfView.visibleRect.insetBy(dx: -1, dy: -1).contains(point),
            "Target \(point) is outside \(pdfView.visibleRect)", file: file, line: line
        )
    }

    private func twoColumns() -> [CGRect] {
        textBlock(x: 50, top: 700, columns: 36) + textBlock(x: 330, top: 700, columns: 36)
    }

    private func textBlock(x: CGFloat, top: CGFloat, columns: Int, rows: Int = 24) -> [CGRect] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGRect(x: x + CGFloat(column) * 6, y: top - CGFloat(row) * 16, width: 5, height: 10)
            }
        }
    }

    private func makeTwoColumnDocument() throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = pageBounds
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        for x: CGFloat in [50, 330] {
            for row in 0..<28 {
                NSString(string: "Reference text in a research paper.").draw(
                    at: CGPoint(x: x, y: 690 - CGFloat(row) * 16), withAttributes: attributes
                )
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }
}
