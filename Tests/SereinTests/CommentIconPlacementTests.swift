import PDFKit
import XCTest
@testable import Serein

final class CommentIconPlacementTests: XCTestCase {
    func testBlankPagePlacesIconToTheRightOfTheHighlight() throws {
        let placement = CommentIconPlacement()
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 600, height: 800))
        let page = try XCTUnwrap(document.page(at: 0))
        let highlight = NSRect(x: 100, y: 400, width: 180, height: 20)
        let annotation = PDFAnnotation(bounds: highlight, forType: .highlight, withProperties: nil)
        annotation.contents = "note"
        page.addAnnotation(annotation)

        let icon = placement.bounds(for: annotation)
        XCTAssertEqual(icon.width, CommentIconPlacement.size.width, accuracy: 0.01)
        XCTAssertEqual(icon.minX, highlight.maxX + CommentIconPlacement.gap, accuracy: 0.5)
        XCTAssertEqual(icon.midY, highlight.midY, accuracy: 0.5)
        XCTAssertFalse(icon.intersects(highlight))
    }

    func testIconDoesNotCoverFollowingWordsOnATextLine() throws {
        let placement = CommentIconPlacement()
        let document = try TestPDFFixtures.makeSearchableDocument(text: "alpha beta gamma delta epsilon")
        let page = try XCTUnwrap(document.page(at: 0))
        let beta = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        let highlight = beta.bounds(for: page)
        let annotation = PDFAnnotation(bounds: highlight, forType: .highlight, withProperties: nil)
        annotation.contents = "comment"
        page.addAnnotation(annotation)

        let icon = placement.bounds(for: annotation)
        let covered = page.selection(for: icon)?.string.map(PDFTextSanitizer.sanitize) ?? ""
        XCTAssertTrue(covered.isEmpty, "icon \(icon) covers '\(covered)'")
        XCTAssertFalse(icon.intersects(highlight))
        XCTAssertGreaterThanOrEqual(icon.minX, highlight.maxX)
    }

    func testTwoCommentsOnOneLineDoNotOverlap() throws {
        let placement = CommentIconPlacement()
        let document = try TestPDFFixtures.makeSearchableDocument(text: "first word then second word")
        let page = try XCTUnwrap(document.page(at: 0))
        let first = try XCTUnwrap(document.findString("first", withOptions: []).first)
        let second = try XCTUnwrap(document.findString("second", withOptions: []).first)

        let left = PDFAnnotation(bounds: first.bounds(for: page), forType: .highlight, withProperties: nil)
        left.contents = "one"
        page.addAnnotation(left)
        let right = PDFAnnotation(bounds: second.bounds(for: page), forType: .highlight, withProperties: nil)
        right.contents = "two"
        page.addAnnotation(right)

        let leftIcon = placement.bounds(for: left)
        let rightIcon = placement.bounds(for: right)
        XCTAssertFalse(leftIcon.intersects(rightIcon))
        XCTAssertTrue(placement.annotation(at: NSPoint(x: leftIcon.midX, y: leftIcon.midY), on: page) === left)
        XCTAssertTrue(placement.annotation(at: NSPoint(x: rightIcon.midX, y: rightIcon.midY), on: page) === right)
    }

    func testRightEdgeHighlightStaysOnThePage() throws {
        let placement = CommentIconPlacement()
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 200, height: 260))
        let page = try XCTUnwrap(document.page(at: 0))
        let highlight = NSRect(x: 168, y: 80, width: 24, height: 14)
        let annotation = PDFAnnotation(bounds: highlight, forType: .highlight, withProperties: nil)
        annotation.contents = "edge"
        page.addAnnotation(annotation)

        let icon = placement.bounds(for: annotation)
        let pageBounds = page.bounds(for: .mediaBox).insetBy(dx: 4, dy: 4)
        XCTAssertTrue(pageBounds.contains(icon), "\(icon) outside \(pageBounds)")
        XCTAssertFalse(icon.intersects(highlight))
    }
}
