import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewScrollingTests: XCTestCase {
    func testLoadingAnAdjacentPagePreservesVisiblePageCoordinates() throws {
        let fixture = try ScrollingPreviewFixture()
        defer { fixture.close() }
        XCTAssertEqual(fixture.preview.document?.pageCount, 1)
        let page = try XCTUnwrap(fixture.preview.document?.page(at: 0))
        fixture.moveToBottom(of: page)
        let before = fixture.preview.convert(fixture.preview.bounds, to: page)

        fixture.content.prepareForScroll(forward: true)

        XCTAssertEqual(fixture.preview.document?.pageCount, 2)
        let after = fixture.preview.convert(fixture.preview.bounds, to: page)
        XCTAssertEqual(before.minX, after.minX, accuracy: 1.5)
        XCTAssertEqual(before.minY, after.minY, accuracy: 1.5)
        XCTAssertEqual(before.width, after.width, accuracy: 1.5)
        XCTAssertEqual(before.height, after.height, accuracy: 1.5)
    }

    func testHistoryRestoresAnAdjacentPageAfterTheOriginalCopyWasEvicted() throws {
        let fixture = try ScrollingPreviewFixture()
        defer { fixture.close() }
        for _ in 0..<4 {
            let document = try XCTUnwrap(fixture.preview.document)
            let page = try XCTUnwrap(document.page(at: document.pageCount - 1))
            fixture.moveToBottom(of: page)
            fixture.content.prepareForScroll(forward: true)
            XCTAssertLessThanOrEqual(document.pageCount, 3)
        }
        let before = try XCTUnwrap(fixture.content.currentSourceDestination)
        XCTAssertGreaterThan(fixture.document.index(for: try XCTUnwrap(before.page)), 3)
        let scale = fixture.preview.scaleFactor
        XCTAssertTrue(fixture.content.navigate(to: PDFDestination(page: fixture.document.page(at: 10)!, at: NSPoint(x: 0, y: 600))))
        XCTAssertEqual(fixture.preview.document?.pageCount, 1)

        fixture.content.goBack()

        let after = try XCTUnwrap(fixture.content.currentSourceDestination)
        XCTAssertTrue(before.page === after.page)
        XCTAssertEqual(before.point.x, after.point.x, accuracy: 1.5)
        XCTAssertEqual(before.point.y, after.point.y, accuracy: 1.5)
        XCTAssertEqual(fixture.preview.scaleFactor, scale, accuracy: 0.001)
        XCTAssertLessThanOrEqual(fixture.preview.document?.pageCount ?? 0, 3)
    }

    func testSplitKeysUseVisibleSourcePositionAndPinSurvivesResignKey() throws {
        let fixture = try ScrollingPreviewFixture()
        defer { fixture.close() }
        let page = try XCTUnwrap(fixture.preview.document?.page(at: 0))
        fixture.moveToBottom(of: page)
        let expected = try XCTUnwrap(fixture.content.currentSourceDestination)
        var splits: [(PDFDestination, ReaderSplitLayout)] = []
        fixture.controller.onSplit = { splits.append(($0, $1)); return true }
        let pin = try XCTUnwrap(fixture.content.view.subviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "referencePreviewPin"
        })
        pin.performClick(nil)
        XCTAssertTrue(fixture.content.isPinned)
        fixture.controller.dismissUnlessPinned()
        XCTAssertNotNil(fixture.controller.content)
        XCTAssertTrue(fixture.content.view.window?.styleMask.contains(.resizable) == true)
        for modifiers: NSEvent.ModifierFlags in [[], [.shift]] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                      modifierFlags: modifiers, timestamp: 0,
                                                      windowNumber: fixture.content.view.window!.windowNumber,
                                                      context: nil, characters: "b", charactersIgnoringModifiers: "b",
                                                      isARepeat: false, keyCode: 11))
            fixture.preview.keyDown(with: event)
        }
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.map(\.1), [.sideBySide, .stacked])
        for (destination, _) in splits {
            XCTAssertTrue(destination.page === expected.page)
            XCTAssertEqual(destination.point.x, expected.point.x, accuracy: 1.5)
            XCTAssertEqual(destination.point.y, expected.point.y, accuracy: 1.5)
        }
        pin.performClick(nil)
        fixture.controller.dismissUnlessPinned()
        XCTAssertNil(fixture.controller.content)
    }

    func testDeclinedSplitKeepsPreviewOpen() throws {
        let fixture = try ScrollingPreviewFixture()
        defer { fixture.close() }
        fixture.controller.onSplit = { _, _ in false }
        let button = try XCTUnwrap(fixture.content.view.subviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "referencePreviewSplit"
        })

        button.performClick(nil)

        XCTAssertNotNil(fixture.controller.content)
    }
}

@MainActor
private final class ScrollingPreviewFixture {
    let document: PDFDocument
    let window: NSWindow
    let controller = ReaderReferencePreviewController()
    let content: ReferencePreviewViewController
    let preview: PDFView

    init() throws {
        _ = NSApplication.shared
        document = TestPDFFixtures.makeBlankDocument(pageCount: 12, pageSize: NSSize(width: 600, height: 800))
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 820, height: 700),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let reader = PDFView(frame: NSRect(x: 0, y: 0, width: 820, height: 700))
        reader.document = document
        reader.scaleFactor = 0.7
        window.contentView = reader
        reader.layoutDocumentView()
        let destination = PDFDestination(page: document.page(at: 3)!, at: NSPoint(x: 0, y: 500))
        XCTAssertTrue(controller.show(destination: destination, anchor: NSRect(x: 100, y: 100, width: 50, height: 20), in: reader))
        content = try XCTUnwrap(controller.content)
        content.positionReference()
        preview = try XCTUnwrap(content.view.subviews.compactMap { $0 as? PDFView }.first)
    }

    func moveToBottom(of page: PDFPage) {
        content.stopObservingScroll()
        let size = preview.convert(preview.bounds, to: page).size
        preview.go(to: NSRect(x: 0, y: 0, width: size.width, height: size.height), on: page)
        preview.layoutDocumentView()
    }

    func close() {
        controller.close()
        window.close()
    }
}
