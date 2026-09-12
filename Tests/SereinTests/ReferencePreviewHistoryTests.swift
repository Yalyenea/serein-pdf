import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferencePreviewHistoryTests: XCTestCase {
    func testFollowingSourceLinksReusesPanelWithoutNavigatingReader() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let panel = try XCTUnwrap(content.view.window)
        let frame = panel.frame
        let originalPage = fixture.reader.currentPage
        let originalScale = fixture.reader.scaleFactor
        var navigationCount = 0
        fixture.controller.onNavigate = { _ in navigationCount += 1 }

        try fixture.clickLink(in: content, sourcePageIndex: 1, corruptCopiedAction: true)
        XCTAssertTrue(content.destination.page === fixture.pages[2])
        try fixture.clickLink(in: content, sourcePageIndex: 2, corruptCopiedAction: true)
        XCTAssertTrue(content.destination.page === fixture.pages[0])

        XCTAssertTrue(fixture.controller.content === content)
        XCTAssertTrue(content.view.window === panel)
        XCTAssertEqual(panel.frame, frame)
        XCTAssertTrue(fixture.reader.currentPage === originalPage)
        XCTAssertEqual(fixture.reader.scaleFactor, originalScale)
        XCTAssertEqual(navigationCount, 0)
        XCTAssertEqual(try fixture.pdfView(in: content).document?.pageCount, 1)
    }

    func testBackForwardButtonsRespectBoundariesAndDiscardAbandonedBranch() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let back = try fixture.button("referencePreviewBack", in: content)
        let forward = try fixture.button("referencePreviewForward", in: content)
        XCTAssertFalse(content.canGoBack)
        XCTAssertFalse(content.canGoForward)
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)
        content.goBack()
        content.goForward()
        XCTAssertTrue(content.destination.page === fixture.pages[1])

        XCTAssertTrue(content.navigate(to: fixture.destination(on: 2)))
        XCTAssertTrue(content.navigate(to: fixture.destination(on: 0)))
        back.performClick(nil)
        XCTAssertTrue(content.destination.page === fixture.pages[2])
        XCTAssertTrue(back.isEnabled)
        XCTAssertTrue(forward.isEnabled)
        forward.performClick(nil)
        XCTAssertTrue(content.destination.page === fixture.pages[0])
        XCTAssertFalse(forward.isEnabled)
        back.performClick(nil)

        let branch = fixture.destination(on: 1, point: NSPoint(x: 100, y: 220))
        XCTAssertTrue(content.navigate(to: branch))
        XCTAssertFalse(content.canGoForward)
        XCTAssertFalse(forward.isEnabled)
        content.goForward()
        XCTAssertEqual(content.destination.point, branch.point)
        content.goBack()
        XCTAssertTrue(content.destination.page === fixture.pages[2])
        content.goBack()
        XCTAssertTrue(content.destination.page === fixture.pages[1])
        XCTAssertEqual(content.destination.point, fixture.destination(on: 1).point)
        XCTAssertFalse(content.canGoBack)
        XCTAssertFalse(back.isEnabled)
    }

    func testDifferentDestinationsOnSamePageHaveSeparateHistoryEntries() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let initialPoint = content.destination.point
        let next = fixture.destination(on: 1, point: NSPoint(x: 180, y: 180))
        XCTAssertTrue(content.navigate(to: next))
        XCTAssertTrue(content.canGoBack)
        XCTAssertEqual(content.destination.point, next.point)
        content.goBack()
        XCTAssertTrue(content.destination.page === fixture.pages[1])
        XCTAssertEqual(content.destination.point, initialPoint)
        content.goForward()
        XCTAssertTrue(content.destination.page === fixture.pages[1])
        XCTAssertEqual(content.destination.point, next.point)
    }

    func testSourceLinkHitTestingSurvivesRotationAndOffsetCropBox() throws {
        for rotation in [0, 90, 180, 270] {
            let fixture = try PreviewHistoryFixture()
            defer { fixture.close() }
            fixture.pages[1].setBounds(NSRect(x: 36, y: 48, width: 528, height: 704), for: .cropBox)
            fixture.pages[1].rotation = rotation
            let content = try fixture.show()

            try fixture.clickLink(in: content, sourcePageIndex: 1, corruptCopiedAction: true)

            XCTAssertTrue(content.destination.page === fixture.pages[2], "Wrong source link at rotation \(rotation)")
            XCTAssertTrue(content.canGoBack)
        }
    }

    func testHistoryRestoresScrolledAndZoomedViewportInBothDirections() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let preview = try fixture.pdfView(in: content)
        let first = try fixture.moveViewport(in: preview, scale: 1.45, origin: NSPoint(x: 90, y: 210))
        XCTAssertTrue(content.navigate(to: fixture.destination(on: 2)))
        let second = try fixture.moveViewport(in: preview, scale: 1.2, origin: NSPoint(x: 60, y: 370))

        content.goBack()
        XCTAssertTrue(content.destination.page === fixture.pages[1])
        try assertViewport(preview, matches: first)
        content.goForward()
        XCTAssertTrue(content.destination.page === fixture.pages[2])
        try assertViewport(preview, matches: second)
    }

    func testJumpUsesCurrentHistoryDestinationAndCallsReaderExactlyOnce() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let target = fixture.destination(on: 2, point: NSPoint(x: 150, y: 330))
        var navigations: [PDFDestination] = []
        fixture.controller.onNavigate = { navigations.append($0) }
        XCTAssertTrue(content.navigate(to: target))
        XCTAssertTrue(content.navigate(to: fixture.destination(on: 0)))
        content.goBack()
        XCTAssertTrue(navigations.isEmpty)

        try fixture.button("referencePreviewJump", in: content).performClick(nil)

        XCTAssertEqual(navigations.count, 1)
        XCTAssertTrue(navigations.first?.page === fixture.pages[2])
        XCTAssertEqual(navigations.first?.point, target.point)
        XCTAssertNil(fixture.controller.content)
    }

    func testEachNavigationCopiesOnlyOnePageAndPreservesSourceAnnotations() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        var widgets: [PDFAnnotation] = []
        var markups: [PDFAnnotation] = []
        for (index, page) in fixture.pages.enumerated() {
            let widget = PDFAnnotation(bounds: NSRect(x: 100, y: 410, width: 100, height: 20), forType: .widget, withProperties: nil)
            widget.widgetFieldType = .text
            widget.fieldName = "field-\(index)"
            widget.widgetStringValue = "Source \(index)"
            widget.isReadOnly = false
            page.addAnnotation(widget)
            widgets.append(widget)
            let markup = PDFAnnotation(bounds: NSRect(x: 100, y: 450, width: 100, height: 20), forType: .underline, withProperties: nil)
            markup.contents = "Source comment \(index)"
            page.addAnnotation(markup)
            markups.append(markup)
        }
        let content = try fixture.show()
        for index in [1, 2, 0] {
            if index != 1 { XCTAssertTrue(content.navigate(to: fixture.destination(on: index))) }
            let preview = try fixture.pdfView(in: content)
            let copy = try XCTUnwrap(preview.currentPage)
            XCTAssertEqual(preview.document?.pageCount, 1)
            XCTAssertFalse(copy === fixture.pages[index])
            XCTAssertFalse(preview.canGoToNextPage)
            XCTAssertFalse(preview.canGoToPreviousPage)
            let widget = try XCTUnwrap(copy.annotations.first { $0.fieldName == "field-\(index)" })
            XCTAssertTrue(widget.isReadOnly)
            let markup = try XCTUnwrap(copy.annotations.first { $0.type == "Underline" })
            XCTAssertTrue(markup.contents?.isEmpty ?? true)
            XCTAssertFalse(widgets[index].isReadOnly)
            XCTAssertEqual(widgets[index].widgetStringValue, "Source \(index)")
            XCTAssertEqual(markups[index].contents, "Source comment \(index)")
            XCTAssertTrue(widgets[index].page === fixture.pages[index])
            XCTAssertTrue(fixture.pages[index].document === fixture.document)
        }
        XCTAssertEqual(fixture.document.pageCount, 3)
    }

    func testInvalidTargetLeavesHistoryIntactAndReopeningStartsFresh() throws {
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        let foreign = TestPDFFixtures.makeBlankDocument(pageCount: 1)
        let foreignPage = try XCTUnwrap(foreign.page(at: 0))
        XCTAssertFalse(content.navigate(to: PDFDestination(page: foreignPage, at: .zero)))
        XCTAssertTrue(content.destination.page === fixture.pages[1])
        XCTAssertFalse(content.canGoBack)
        XCTAssertTrue(content.navigate(to: fixture.destination(on: 2)))
        fixture.controller.close()

        let reopened = try fixture.show()
        XCTAssertFalse(reopened === content)
        XCTAssertFalse(reopened.canGoBack)
        XCTAssertFalse(reopened.canGoForward)
        XCTAssertTrue(reopened.destination.page === fixture.pages[1])
    }

    func testRenderHistoryControlsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["SEREIN_REFERENCE_SNAPSHOTS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try PreviewHistoryFixture()
        defer { fixture.close() }
        let content = try fixture.show()
        for state in ["initial", "back", "both"] {
            if state == "back" { XCTAssertTrue(content.navigate(to: fixture.destination(on: 2))) }
            if state == "both" {
                XCTAssertTrue(content.navigate(to: fixture.destination(on: 0)))
                content.goBack()
            }
            content.view.layoutSubtreeIfNeeded()
            content.view.displayIfNeeded()
            let bitmap = try XCTUnwrap(content.view.bitmapImageRepForCachingDisplay(in: content.view.bounds))
            content.view.cacheDisplay(in: content.view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("reference-history-\(state).png"))
        }
    }

    func testRealPDFLinkChainWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["SEREIN_REFERENCE_PDF"] else { return }
        let document = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path)))
        func destinations(on page: PDFPage) -> [PDFDestination] {
            page.annotations.compactMap { ($0.action as? PDFActionGoTo)?.destination ?? $0.destination }
                .filter { $0.page?.document === document }
        }
        let first = try XCTUnwrap((0..<document.pageCount).compactMap { document.page(at: $0) }
            .flatMap { destinations(on: $0) }.first { destinations(on: $0.page!).isEmpty == false })
        let next = try XCTUnwrap(destinations(on: first.page!).first)
        let content = try XCTUnwrap(ReferencePreviewViewController(destination: first, document: document))
        content.preferredContentSize = NSSize(width: 580, height: 360)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: content.preferredContentSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = content
        defer { window.close() }
        content.positionReference()
        XCTAssertTrue(content.navigate(to: next))
        content.goBack()
        XCTAssertTrue(content.destination.page === first.page)
        content.goForward()
        XCTAssertTrue(content.destination.page === next.page)
        content.view.layoutSubtreeIfNeeded()

        if let output = ProcessInfo.processInfo.environment["SEREIN_REFERENCE_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(content.view.bitmapImageRepForCachingDisplay(in: content.view.bounds))
            content.view.cacheDisplay(in: content.view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("reference-history-real-pdf.png"))
        }
    }

    private func assertViewport(_ preview: PDFView, matches expected: PreviewViewport, file: StaticString = #filePath, line: UInt = #line) throws {
        let page = try XCTUnwrap(preview.currentPage)
        preview.layoutDocumentView()
        let visible = preview.convert(preview.bounds, to: page)
        XCTAssertEqual(preview.scaleFactor, expected.scale, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(visible.minX, expected.rect.minX, accuracy: 1.5, file: file, line: line)
        XCTAssertEqual(visible.minY, expected.rect.minY, accuracy: 1.5, file: file, line: line)
        XCTAssertEqual(visible.width, expected.rect.width, accuracy: 1.5, file: file, line: line)
        XCTAssertEqual(visible.height, expected.rect.height, accuracy: 1.5, file: file, line: line)
    }
}

private struct PreviewViewport {
    let scale: CGFloat
    let rect: NSRect
}

@MainActor
private final class PreviewHistoryFixture {
    let document: PDFDocument
    let pages: [PDFPage]
    let links: [PDFAnnotation]
    let reader = ReaderPDFView()
    let window: NSWindow
    let controller = ReaderReferencePreviewController()

    init() throws {
        _ = NSApplication.shared
        let sourceDocument = TestPDFFixtures.makeBlankDocument(pageCount: 3, pageSize: NSSize(width: 600, height: 800))
        let sourcePages = try (0..<3).map { try XCTUnwrap(sourceDocument.page(at: $0)) }
        document = sourceDocument
        pages = sourcePages
        links = sourcePages.indices.map { _ in
            PDFAnnotation(bounds: NSRect(x: 100, y: 520, width: 160, height: 24), forType: .link, withProperties: nil)
        }
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 820, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        for index in pages.indices {
            let target = PDFDestination(page: pages[(index + 1) % pages.count], at: NSPoint(x: 100, y: 560))
            if index == 2 { links[index].destination = target }
            else { links[index].action = PDFActionGoTo(destination: target) }
            pages[index].addAnnotation(links[index])
        }
        window.isReleasedWhenClosed = false
        reader.frame = NSRect(x: 0, y: 0, width: 820, height: 700)
        window.contentView = reader
        reader.displayMode = .singlePage
        reader.document = document
        reader.scaleFactor = 0.7
        reader.go(to: pages[0])
        reader.layoutDocumentView()
    }

    func close() {
        controller.close()
        window.close()
    }

    func destination(on index: Int, point: NSPoint = NSPoint(x: 100, y: 560)) -> PDFDestination {
        PDFDestination(page: pages[index], at: point)
    }

    func show() throws -> ReferencePreviewViewController {
        let anchor = reader.convert(links[0].bounds, from: pages[0])
        XCTAssertTrue(controller.show(destination: destination(on: 1), anchor: anchor, in: reader))
        let content = try XCTUnwrap(controller.content)
        content.view.layoutSubtreeIfNeeded()
        content.positionReference()
        return content
    }

    func pdfView(in content: ReferencePreviewViewController) throws -> PDFView {
        try XCTUnwrap(content.view.subviews.compactMap { $0 as? PDFView }.first)
    }

    func button(_ identifier: String, in content: ReferencePreviewViewController) throws -> NSButton {
        try XCTUnwrap(content.view.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == identifier })
    }

    func moveViewport(in preview: PDFView, scale: CGFloat, origin: NSPoint) throws -> PreviewViewport {
        let page = try XCTUnwrap(preview.currentPage)
        preview.scaleFactor = scale
        preview.layoutDocumentView()
        let viewport = preview.convert(preview.bounds, to: page).size
        preview.go(to: NSRect(origin: origin, size: viewport), on: page)
        preview.layoutDocumentView()
        return PreviewViewport(scale: preview.scaleFactor, rect: preview.convert(preview.bounds, to: page))
    }

    func clickLink(in content: ReferencePreviewViewController, sourcePageIndex: Int, corruptCopiedAction: Bool = false) throws {
        let preview = try pdfView(in: content)
        let page = try XCTUnwrap(preview.currentPage)
        if corruptCopiedAction {
            let copy = try XCTUnwrap(page.annotations.first { $0.type == "Link" })
            copy.destination = nil
            copy.action = PDFActionURL(url: URL(string: "https://example.com/copied-link-must-not-be-used")!)
        }
        let bounds = links[sourcePageIndex].bounds
        let point = preview.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
        XCTAssertTrue(preview.visibleRect.contains(point), "Test link must be visible before clicking")
        let location = preview.convert(point, to: nil)
        let targetWindow = try XCTUnwrap(preview.window)
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: targetWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.01, windowNumber: targetWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        NSApp.postEvent(mouseUp, atStart: true)
        defer {
            if NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: false) === mouseUp {
                _ = NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: true)
            }
        }
        preview.mouseDown(with: mouseDown)
    }
}
