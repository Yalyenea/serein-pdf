import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderCommentInteractionTests: XCTestCase {
    func testNativeCommentIconClicksReachCustomHandlerAtDifferentScalesAndRotations() throws {
        _ = NSApplication.shared
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 600, height: 800))
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = PDFAnnotation(bounds: NSRect(x: 100, y: 400, width: 180, height: 20), forType: .highlight, withProperties: nil)
        annotation.contents = "One comment"
        page.addAnnotation(annotation)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let pdfView = ReaderPDFView(frame: NSRect(x: 0, y: 0, width: 900, height: 900))
        window.contentView = pdfView
        pdfView.displayMode = .singlePage
        pdfView.document = document
        var activations = 0
        pdfView.onAnnotationActivationRequested = { _ in
            activations += 1
            return true
        }

        for rotation in [0, 90, 180, 270] {
            pdfView.document = nil
            page.rotation = rotation
            pdfView.document = document
            for scale in [0.7, 1.2] {
                pdfView.scaleFactor = scale
                pdfView.layoutDocumentView()
                pdfView.annotationsChanged(on: page)
                pdfView.layoutSubtreeIfNeeded()
                let icon = try XCTUnwrap(imageViews(in: try XCTUnwrap(pdfView.documentView)).first { $0.image != nil })
                let center = NSPoint(x: icon.bounds.midX, y: icon.bounds.midY)
                let point = icon.convert(center, to: pdfView)
                XCTAssertTrue(pdfView.hitTest(pdfView.convert(point, to: pdfView.superview)) === pdfView)
                let pagePoint = pdfView.convert(point, to: page)
                XCTAssertTrue(HighlightService.commentAnnotation(at: pagePoint, on: page) === annotation,
                              "Icon at \(pagePoint), rotation \(rotation), scale \(scale)")
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                    location: pdfView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                pdfView.mouseDown(with: event)
            }
        }
        XCTAssertEqual(activations, 8)
    }

    private func imageViews(in view: NSView) -> [NSImageView] {
        ((view as? NSImageView).map { [$0] } ?? [])
            + view.subviews.flatMap { imageViews(in: $0) }
    }
}
