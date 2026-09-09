import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewTests: XCTestCase {
    func testInternalLinkClickPreviewsWithoutChangingReaderPosition() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        let originalPage = fixture.view.currentPage
        let originalScale = fixture.view.scaleFactor
        var previewCount = 0
        var navigationCount = 0
        fixture.view.onInternalLinkPreviewRequested = { destination, anchor in
            previewCount += 1
            XCTAssertTrue(destination.page === fixture.targetPage)
            XCTAssertEqual(destination.point, fixture.destination.point)
            let expected = fixture.view.convert(fixture.link.bounds, from: fixture.sourcePage)
            XCTAssertEqual(anchor.minX, expected.minX, accuracy: 0.01)
            XCTAssertEqual(anchor.minY, expected.minY, accuracy: 0.01)
            XCTAssertEqual(anchor.width, expected.width, accuracy: 0.01)
            XCTAssertEqual(anchor.height, expected.height, accuracy: 0.01)
            return true
        }
        fixture.view.onInternalLinkNavigationRequested = { _ in
            navigationCount += 1
            return true
        }

        fixture.sendClick()

        XCTAssertEqual(previewCount, 1)
        XCTAssertEqual(navigationCount, 0)
        XCTAssertTrue(fixture.view.currentPage === originalPage)
        XCTAssertEqual(fixture.view.scaleFactor, originalScale)
    }

    func testOptionClickNavigatesWithoutPreviewing() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        var previewCount = 0
        var navigationCount = 0
        fixture.view.onInternalLinkPreviewRequested = { _, _ in
            previewCount += 1
            return true
        }
        fixture.view.onInternalLinkNavigationRequested = { destination in
            navigationCount += 1
            XCTAssertTrue(destination.page === fixture.targetPage)
            XCTAssertEqual(destination.point, fixture.destination.point)
            return true
        }

        fixture.sendClick(modifiers: [.option])

        XCTAssertEqual(previewCount, 0)
        XCTAssertEqual(navigationCount, 1)
    }

    func testDeclinedPreviewContinuesThroughNavigation() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        var callbacks: [String] = []
        fixture.view.onInternalLinkPreviewRequested = { _, _ in
            callbacks.append("preview")
            return false
        }
        fixture.view.onInternalLinkNavigationRequested = { _ in
            callbacks.append("navigation")
            return true
        }

        fixture.sendClick()

        XCTAssertEqual(callbacks, ["preview", "navigation"])
    }

    func testLinkWithDestinationPropertyCanBePreviewed() throws {
        let fixture = try makeFixture(useDestinationProperty: true)
        defer { fixture.window.close() }
        var previewCount = 0
        fixture.view.onInternalLinkPreviewRequested = { destination, _ in
            previewCount += 1
            XCTAssertTrue(destination.page === fixture.targetPage)
            XCTAssertEqual(destination.point, fixture.destination.point)
            return true
        }

        fixture.sendClick()

        XCTAssertEqual(previewCount, 1)
    }

    func testExternalURLDoesNotEnterInternalLinkCallbacks() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        fixture.link.action = PDFActionURL(url: URL(string: "https://example.com/reference")!)
        var previewCount = 0
        var navigationCount = 0
        var annotationActivationCount = 0
        fixture.view.onInternalLinkPreviewRequested = { _, _ in
            previewCount += 1
            return true
        }
        fixture.view.onInternalLinkNavigationRequested = { _ in
            navigationCount += 1
            return true
        }
        // Stop before PDFKit opens a browser after confirming internal routing was skipped.
        fixture.view.onAnnotationActivationRequested = { _ in
            annotationActivationCount += 1
            return true
        }

        fixture.sendClick(clickCount: 2)

        XCTAssertEqual(previewCount, 0)
        XCTAssertEqual(navigationCount, 0)
        XCTAssertEqual(annotationActivationCount, 1)
    }

    func testPreviewCopiesOnlyTargetPageAndKeepsSourceWidgetUnchanged() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        let document = try XCTUnwrap(fixture.view.document)
        let sourceWidget = PDFAnnotation(
            bounds: NSRect(x: 320, y: 440, width: 150, height: 24),
            forType: .widget,
            withProperties: nil
        )
        sourceWidget.widgetFieldType = .text
        sourceWidget.fieldName = "reference-field"
        sourceWidget.widgetStringValue = "Original value"
        sourceWidget.isReadOnly = false
        fixture.targetPage.addAnnotation(sourceWidget)
        let preview = try makePreview(destination: fixture.destination, document: document)
        defer { preview.window.close() }

        let previewDocument = try XCTUnwrap(preview.pdfView.document)
        let previewPage = try XCTUnwrap(preview.pdfView.currentPage)
        XCTAssertFalse(previewDocument === document)
        XCTAssertEqual(previewDocument.pageCount, 1)
        XCTAssertTrue(previewPage === previewDocument.page(at: 0))
        XCTAssertFalse(previewPage === fixture.targetPage)
        XCTAssertEqual(document.index(for: fixture.targetPage), 1)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertFalse(preview.pdfView.canGoToNextPage)
        XCTAssertFalse(preview.pdfView.canGoToPreviousPage)
        let copiedWidget = try XCTUnwrap(previewPage.annotations.first { $0.fieldName == "reference-field" })
        XCTAssertFalse(copiedWidget === sourceWidget)
        XCTAssertTrue(copiedWidget.isReadOnly)
        XCTAssertEqual(copiedWidget.widgetStringValue, "Original value")
        XCTAssertFalse(sourceWidget.isReadOnly)

        copiedWidget.widgetStringValue = "Preview-only change"

        XCTAssertEqual(sourceWidget.widgetStringValue, "Original value")
        XCTAssertFalse(sourceWidget.isReadOnly)
        XCTAssertTrue(sourceWidget.page === fixture.targetPage)
    }

    func testTargetIsVisibleWithRotatedAndOffsetCropBoxes() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        let document = try XCTUnwrap(fixture.view.document)
        let cropBox = NSRect(x: 36, y: 48, width: 528, height: 704)
        fixture.targetPage.setBounds(cropBox, for: .cropBox)
        let point = NSPoint(x: cropBox.maxX - 72, y: cropBox.minY + 90)

        for rotation in [0, 90, 180, 270] {
            fixture.targetPage.rotation = rotation
            let destination = PDFDestination(page: fixture.targetPage, at: point)
            let preview = try makePreview(destination: destination, document: document)
            defer { preview.window.close() }
            let page = try XCTUnwrap(preview.pdfView.currentPage)
            let targetInPreview = preview.pdfView.convert(point, from: page)

            XCTAssertEqual(page.rotation, rotation)
            XCTAssertEqual(page.bounds(for: .cropBox), cropBox)
            XCTAssertTrue(
                preview.pdfView.visibleRect.insetBy(dx: -1, dy: -1).contains(targetInPreview),
                "Target \(targetInPreview) is outside \(preview.pdfView.visibleRect) at rotation \(rotation)"
            )
            XCTAssertTrue(preview.pdfView.scaleFactor.isFinite)
            XCTAssertGreaterThan(preview.pdfView.scaleFactor, 0)
        }
    }

    func testUnspecifiedDestinationCoordinatesShowPageTop() throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        let document = try XCTUnwrap(fixture.view.document)
        let cropBox = NSRect(x: 36, y: 48, width: 528, height: 704)
        fixture.targetPage.setBounds(cropBox, for: .cropBox)
        let destination = PDFDestination(
            page: fixture.targetPage,
            at: NSPoint(x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue)
        )
        let preview = try makePreview(destination: destination, document: document)
        defer { preview.window.close() }
        let page = try XCTUnwrap(preview.pdfView.currentPage)
        let pageTop = preview.pdfView.convert(NSPoint(x: cropBox.minX, y: cropBox.maxY), from: page)

        XCTAssertTrue(preview.pdfView.visibleRect.insetBy(dx: -1, dy: -1).contains(pageTop))
        XCTAssertTrue(pageTop.x.isFinite)
        XCTAssertTrue(pageTop.y.isFinite)
        XCTAssertTrue(preview.pdfView.scaleFactor.isFinite)
    }

    private func makePreview(
        destination: PDFDestination,
        document: PDFDocument
    ) throws -> (window: NSWindow, pdfView: PDFView) {
        let content = try XCTUnwrap(ReferencePreviewViewController(destination: destination, document: document))
        let size = NSSize(width: 580, height: 360)
        content.preferredContentSize = size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = content
        content.view.frame = NSRect(origin: .zero, size: size)
        content.view.layoutSubtreeIfNeeded()
        content.positionReference()
        let pdfView = try XCTUnwrap(content.view.subviews.compactMap { $0 as? PDFView }.first)
        pdfView.layoutDocumentView()
        return (window, pdfView)
    }

    private func makeFixture(useDestinationProperty: Bool = false) throws -> LinkFixture {
        _ = NSApplication.shared
        let document = TestPDFFixtures.makeBlankDocument(
            pageCount: 2,
            pageSize: NSSize(width: 600, height: 800)
        )
        let sourcePage = try XCTUnwrap(document.page(at: 0))
        let targetPage = try XCTUnwrap(document.page(at: 1))
        let destination = PDFDestination(page: targetPage, at: NSPoint(x: 320, y: 480))
        let link = PDFAnnotation(
            bounds: NSRect(x: 100, y: 500, width: 90, height: 24),
            forType: .link,
            withProperties: nil
        )
        if useDestinationProperty {
            link.destination = destination
        } else {
            link.action = PDFActionGoTo(destination: destination)
        }
        sourcePage.addAnnotation(link)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 700))
        let view = ReaderPDFView(frame: NSRect(x: 37, y: 29, width: 730, height: 620))
        window.contentView = host
        host.addSubview(view)
        view.displayMode = .singlePage
        view.document = document
        view.scaleFactor = 0.65
        view.go(to: sourcePage)
        host.layoutSubtreeIfNeeded()
        view.layoutDocumentView()
        return LinkFixture(
            window: window,
            view: view,
            sourcePage: sourcePage,
            targetPage: targetPage,
            link: link,
            destination: destination
        )
    }
}

@MainActor
private struct LinkFixture {
    let window: NSWindow
    let view: ReaderPDFView
    let sourcePage: PDFPage
    let targetPage: PDFPage
    let link: PDFAnnotation
    let destination: PDFDestination

    func sendClick(modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        let point = NSPoint(x: link.bounds.midX, y: link.bounds.midY)
        let pointInView = view.convert(point, from: sourcePage)
        let pointInWindow = view.convert(pointInView, to: nil)
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: pointInWindow,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
        let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: pointInWindow,
            modifierFlags: modifiers,
            timestamp: 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 0
        )!
        // A routing regression must fail assertions instead of leaving PDFKit's
        // native selection loop waiting indefinitely for a physical mouse release.
        NSApp.postEvent(mouseUp, atStart: true)
        defer {
            if NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: false) === mouseUp {
                _ = NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: true)
            }
        }
        view.mouseDown(with: mouseDown)
    }
}
