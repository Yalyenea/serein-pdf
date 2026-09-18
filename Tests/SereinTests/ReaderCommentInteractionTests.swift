import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderCommentInteractionTests: XCTestCase {
    func testNativeCommentIconClicksReachCustomHandlerAtDifferentScalesAndRotations() throws {
        for type in AnnotationMarkupType.allCases {
            try assertNativeCommentIconClicks(type: type)
        }
    }

    private func assertNativeCommentIconClicks(type: AnnotationMarkupType) throws {
        _ = NSApplication.shared
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 600, height: 800))
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = PDFAnnotation(bounds: NSRect(x: 100, y: 400, width: 180, height: 20), forType: type.pdfSubtype, withProperties: nil)
        annotation.contents = "One comment"
        page.addAnnotation(annotation)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let pdfView = ReaderPDFView(frame: NSRect(x: 0, y: 0, width: 900, height: 900))
        window.contentView = pdfView
        pdfView.displayMode = .singlePage
        pdfView.document = document
        window.makeKeyAndOrderFront(nil)
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
                let iconBounds = pdfView.commentIcons.bounds(for: annotation)
                let pagePoint = NSPoint(x: iconBounds.midX, y: iconBounds.midY)
                XCTAssertTrue(pdfView.commentIcons.annotation(at: pagePoint, on: page) === annotation,
                              "Icon at \(pagePoint), rotation \(rotation), scale \(scale)")
                let point = pdfView.convert(pagePoint, from: page)
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                    location: pdfView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                let previousActivations = activations
                // Dispatch through AppKit so hitTest sees this click as currentEvent
                // and the assertion covers delivery through PDFKit's native subviews.
                NSApp.sendEvent(event)
                XCTAssertEqual(activations, previousActivations + 1,
                               "Icon click, rotation \(rotation), scale \(scale)")
                let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp,
                    location: event.locationInWindow, modifierFlags: [], timestamp: 0.01,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
                NSApp.sendEvent(mouseUp)
            }
        }
        XCTAssertEqual(activations, 8)
    }

    func testCommentIconsRefreshForEveryMarkupTypeWithoutChangingAnnotationOrder() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let pdfView = ReaderPDFView(frame: window.contentView!.bounds)
        window.contentView = pdfView
        pdfView.displayMode = .singlePage

        for type in AnnotationMarkupType.allCases {
            let document = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 600, height: 800))
            let page = try XCTUnwrap(document.page(at: 0))
            let groupID = UUID().uuidString
            let records = [400, 370].map { y in
                let annotation = PDFAnnotation(bounds: NSRect(x: 100, y: CGFloat(y), width: 180, height: 20), forType: type.pdfSubtype, withProperties: nil)
                annotation.userName = groupID
                page.addAnnotation(annotation)
                return HighlightAnnotationRecord(pageIndex: 0, annotation: annotation)
            }
            let overlapping = PDFAnnotation(bounds: records[0].annotation.bounds, forType: .highlight, withProperties: nil)
            page.addAnnotation(overlapping)
            let originalAnnotations = page.annotations
            pdfView.document = document
            pdfView.scaleFactor = 1
            pdfView.layoutDocumentView()
            XCTAssertEqual(commentIcons(in: pdfView).count, 0)

            for comment in ["First line\nSecond line", "Edited comment", "", "Restored comment"] {
                XCTAssertTrue(HighlightService.updateComment(comment, for: records), type.rawValue)
                pdfView.annotationsChanged(on: page)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                pdfView.layoutSubtreeIfNeeded()

                let icons = commentIcons(in: pdfView)
                XCTAssertEqual(icons.count, comment.isEmpty ? 0 : 1, "\(type.rawValue): \(comment)")
                XCTAssertEqual(page.annotations.map(ObjectIdentifier.init), originalAnnotations.map(ObjectIdentifier.init))
                XCTAssertEqual(records.compactMap(\.annotation.contents), comment.isEmpty ? [] : [comment])
                XCTAssertTrue(records.allSatisfy { $0.annotation.popup == nil })
                if comment.isEmpty == false {
                    let iconBounds = pdfView.commentIcons.bounds(for: records[0].annotation)
                    XCTAssertTrue(
                        pdfView.commentIcons.annotation(
                            at: NSPoint(x: iconBounds.midX, y: iconBounds.midY),
                            on: page
                        ) === records[0].annotation
                    )
                }
            }

            let saved = try XCTUnwrap(document.dataRepresentation())
            let reopened = try XCTUnwrap(PDFDocument(data: saved))
            pdfView.document = reopened
            pdfView.layoutDocumentView()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            pdfView.layoutSubtreeIfNeeded()
            XCTAssertEqual(commentIcons(in: pdfView).count, 1, type.rawValue)
            XCTAssertEqual(reopened.page(at: 0)?.annotations.count, originalAnnotations.count)
        }
    }

    private func commentIcons(in pdfView: PDFView) -> [NSImageView] {
        findAllDescendants(of: NSImageView.self, in: pdfView).filter { $0.image != nil }
    }

}
