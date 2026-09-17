import AppKit
import PDFKit
import XCTest
import ObjectiveC.runtime
@testable import Serein

@MainActor
final class CommentIconReuseTests: XCTestCase {
    func testDocumentGetterRemainsPDFKitImplementation() async throws {
        let selector = #selector(getter: PDFView.document)
        let readerMethod = try XCTUnwrap(class_getInstanceMethod(ReaderPDFView.self, selector))
        let nativeMethod = try XCTUnwrap(class_getInstanceMethod(PDFView.self, selector))
        XCTAssertEqual(
            unsafeBitCast(method_getImplementation(readerMethod), to: UInt.self),
            unsafeBitCast(method_getImplementation(nativeMethod), to: UInt.self),
            "PDFKit reads document on its form-filling queue; keep its native getter."
        )
        _ = NSApplication.shared
        let view = ReaderPDFView()
        let document = PDFDocument()
        view.setReaderDocument(document)
        nonisolated(unsafe) let object: NSObject = view
        let expectedID = ObjectIdentifier(document)
        let completed = expectation(description: "PDFKit background document read")
        DispatchQueue(label: "test.pdf-form-filling").async {
            XCTAssertFalse(Thread.isMainThread)
            let result = object.perform(NSSelectorFromString("document"))?.takeUnretainedValue()
            XCTAssertEqual(result.map(ObjectIdentifier.init), expectedID)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
    }

    func testDrawingHitTestingAndAnchoringReuseTextScan() throws {
        _ = NSApplication.shared
        let view = ReaderPDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        let document = PDFDocument()
        let page = CountingPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 800), for: .mediaBox)
        let annotation = comment(on: page)
        document.insert(page, at: 0)
        view.setReaderDocument(document)
        let placement = view.commentIcons
        let frame = try XCTUnwrap(placement.frames(on: page).first?.frame)
        let scans = page.textScans
        XCTAssertGreaterThan(scans, 0)
        XCTAssertEqual(placement.bounds(for: annotation), frame)
        XCTAssertTrue(placement.annotation(at: NSPoint(x: frame.midX, y: frame.midY), on: page) === annotation)
        view.scaleFactor = 1.2
        annotation.color = .green
        annotation.contents = "Edited text"
        XCTAssertEqual(placement.frames(on: page).first?.frame, frame)
        XCTAssertEqual(page.textScans, scans, "Geometry-independent changes must reuse the text scan")
    }

    func testAnnotationAndPageChangesRecomputePlacement() throws {
        let placement = CommentIconPlacement()
        let page = CountingPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 600, height: 800), for: .mediaBox)
        let annotation = comment(on: page)
        let original = placement.bounds(for: annotation)
        var scans = page.textScans
        annotation.bounds.origin.x += 20
        XCTAssertNotEqual(placement.bounds(for: annotation), original)
        XCTAssertGreaterThan(page.textScans, scans)
        annotation.contents = " \n "
        XCTAssertTrue(placement.frames(on: page).isEmpty)
        annotation.contents = "Restored"
        scans = page.textScans
        _ = placement.frames(on: page)
        XCTAssertGreaterThan(page.textScans, scans)
        let second = comment(on: page)
        let frames = placement.frames(on: page)
        XCTAssertEqual(frames.count, 2)
        XCTAssertFalse(frames[0].frame.intersects(frames[1].frame))
        page.removeAnnotation(second)
        XCTAssertEqual(placement.frames(on: page).count, 1)
        for rotation in [90, 180] {
            scans = page.textScans
            page.rotation = rotation
            _ = placement.frames(on: page)
            XCTAssertGreaterThan(page.textScans, scans)
        }
        scans = page.textScans
        page.setBounds(NSRect(x: 0, y: 0, width: 300, height: 500), for: .cropBox)
        _ = placement.frames(on: page)
        XCTAssertGreaterThan(page.textScans, scans)
    }

    func testLeavingPagesAndReplacingDocumentDiscardCachedLayouts() {
        _ = NSApplication.shared
        let placement = CommentIconPlacement()
        weak var releasedPage: PDFPage?
        autoreleasepool {
            let page = CountingPage()
            releasedPage = page
            _ = comment(on: page)
            _ = placement.frames(on: page)
        }
        XCTAssertNotNil(releasedPage)
        placement.retainPages([])
        XCTAssertNil(releasedPage)

        let view = ReaderPDFView()
        let document = PDFDocument()
        let page = CountingPage()
        _ = comment(on: page)
        document.insert(page, at: 0)
        view.setReaderDocument(document)
        _ = view.commentIcons.frames(on: page)
        let scans = page.textScans
        view.setReaderDocument(PDFDocument())
        _ = view.commentIcons.frames(on: page)
        XCTAssertGreaterThan(page.textScans, scans)
    }

    private func comment(on page: PDFPage) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: NSRect(x: 100, y: 400, width: 80, height: 20), forType: .highlight, withProperties: nil)
        annotation.contents = "Comment"
        page.addAnnotation(annotation)
        return annotation
    }
}

private final class CountingPage: PDFPage {
    var textScans = 0
    override func selection(for rect: CGRect) -> PDFSelection? {
        textScans += 1
        return nil
    }
}
