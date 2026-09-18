import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class CommentIconOverlayTests: XCTestCase {
    func testDotDrawingCoordinatesMatchItsClickTargetAwayFromPageCenter() throws {
        let fixture = try makeReader(comments: [""])
        defer { fixture.window.close() }
        let reader = fixture.reader
        let page = try XCTUnwrap(reader.pdfView.document?.page(at: 0))
        let annotation = try XCTUnwrap(page.annotations.first)
        annotation.bounds.origin.y = 650
        let group = try XCTUnwrap(fixture.store.annotationGroup(containing: annotation, for: fixture.sessionID))
        XCTAssertTrue(fixture.store.updateComment("Visible dot", forHighlightGroup: group.groupID, in: fixture.sessionID))
        settle(reader)
        // PDFKit can append page views after the annotation overlay is installed.
        // A late opaque page sibling must never cover the dot on the next layout.
        let documentView = try XCTUnwrap(reader.pdfView.documentView)
        let latePageView = NSView(frame: documentView.bounds)
        latePageView.wantsLayer = true
        latePageView.layer?.backgroundColor = NSColor.white.cgColor
        documentView.addSubview(latePageView)
        // Enter the same layout-completion path as PDFKit page changes. Marking
        // a child dirty does not guarantee its parent lays it out on macOS 15.
        reader.pdfView.layoutDocumentView()
        let overlay = try overlay(in: reader)
        let refreshDeadline = Date().addingTimeInterval(1)
        while documentView.subviews.last !== overlay, Date() < refreshDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        reader.view.window?.displayIfNeeded()
        XCTAssertTrue(documentView.subviews.last === overlay,
                      "overlayIndex=\(String(describing: documentView.subviews.firstIndex { $0 === overlay })), siblings=\(documentView.subviews.count)")
        let frame = try XCTUnwrap(overlay.icons.first?.frame)
        let drawnFrame = overlay.convert(frame, to: reader.pdfView)
        let expectedFrame = reader.pdfView.convert(reader.pdfView.commentIcons.bounds(for: annotation), from: page)
        let bitmap = try XCTUnwrap(reader.pdfView.bitmapImageRepForCachingDisplay(in: reader.pdfView.bounds))
        reader.pdfView.cacheDisplay(in: reader.pdfView.bounds, to: bitmap)
        XCTAssertEqual(drawnFrame.midY, expectedFrame.midY, accuracy: 0.5)
        XCTAssertEqual(drawnFrame.midX, expectedFrame.midX, accuracy: 0.5)
        let pixelX = Int(expectedFrame.midX / reader.pdfView.bounds.width * CGFloat(bitmap.pixelsWide))
        let pixelY = Int((reader.pdfView.bounds.maxY - expectedFrame.midY) / reader.pdfView.bounds.height * CGFloat(bitmap.pixelsHigh))
        let pixel = try XCTUnwrap(bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(pixel.saturationComponent, 0.1,
                             "The dot must be visible at its click target; overlayIndex=\(String(describing: documentView.subviews.firstIndex { $0 === overlay })), siblings=\(documentView.subviews.count)")
    }

    func testCommentChangesRefreshDotsWithoutResizingReader() throws {
        for type in AnnotationMarkupType.allCases {
            let fixture = try makeReader(type: type, comments: [""])
            defer { fixture.window.close() }
            let page = try XCTUnwrap(fixture.reader.pdfView.document?.page(at: 0))
            let annotation = try XCTUnwrap(page.annotations.first)
            let group = try XCTUnwrap(fixture.store.annotationGroup(containing: annotation, for: fixture.sessionID))
            XCTAssertEqual(try overlay(in: fixture.reader).icons.count, 0)

            for comment in ["New comment", "Edited comment", "", "Restored comment"] {
                XCTAssertTrue(fixture.store.updateComment(comment, forHighlightGroup: group.groupID, in: fixture.sessionID))
                settle(fixture.reader)
                XCTAssertEqual(try overlay(in: fixture.reader).icons.count, comment.isEmpty ? 0 : 1, type.rawValue)
                let nativeIcons = findAllDescendants(of: NSImageView.self, in: fixture.reader.pdfView)
                    .filter { $0.image != nil }
                XCTAssertTrue(nativeIcons.allSatisfy(\.isHidden))
            }
            XCTAssertTrue(fixture.store.removeHighlightGroup(group, in: fixture.sessionID))
            settle(fixture.reader)
            XCTAssertEqual(try overlay(in: fixture.reader).icons.count, 0)
        }
    }

    func testSinglePageDotsFollowPageAndZoomWithoutOtherPages() throws {
        let fixture = try makeReader(comments: ["First page", "Second page"])
        defer { fixture.window.close() }
        let reader = fixture.reader
        let document = try XCTUnwrap(reader.pdfView.document)
        for index in [0, 1, 0] {
            let page = try XCTUnwrap(document.page(at: index))
            reader.pdfView.go(to: page)
            for scale in [0.7, 1.2] {
                fixture.store.setScaleMode(.manual, scaleFactor: scale, for: fixture.sessionID)
                settle(reader)
                XCTAssertEqual(reader.pdfView.visiblePages.map { document.index(for: $0) }, [index])
                XCTAssertEqual(try overlay(in: reader).icons.count, 1)
                try assertDotsMatchVisiblePages(reader)
            }
        }
    }

    func testContinuousScrollingRefreshesVisiblePageDots() throws {
        let fixture = try makeReader(comments: ["First", "Second", "Third"], mode: .singlePageContinuous)
        defer { fixture.window.close() }
        let reader = fixture.reader
        let document = try XCTUnwrap(reader.pdfView.document)
        let scrollView = try XCTUnwrap(reader.pdfView.documentView?.enclosingScrollView)
        for y: CGFloat in [0, 550, 1000, 0] {
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            settle(reader)
            let deadline = Date().addingTimeInterval(1)
            while reader.pdfView.visiblePages.isEmpty, Date() < deadline {
                reader.view.window?.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertFalse(reader.pdfView.visiblePages.isEmpty,
                           "clip=\(scrollView.contentView.bounds), document=\(String(describing: reader.pdfView.documentView?.frame))")
            try assertDotsMatchVisiblePages(reader)
        }
        XCTAssertEqual(document.pageCount, 3)
    }

    private func assertDotsMatchVisiblePages(_ reader: ReaderViewController) throws {
        // PDFKit updates its visible page views asynchronously after scrolling.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let frames = try visibleFrames(in: reader)
            if frames.actual == frames.expected { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let (actual, expected) = try visibleFrames(in: reader)
        XCTAssertEqual(actual.count, expected.count, "actual=\(actual), expected=\(expected)")
        for (actualFrame, expectedFrame) in zip(actual, expected) {
            XCTAssertEqual(actualFrame.minX, expectedFrame.minX, accuracy: 0.5)
            XCTAssertEqual(actualFrame.minY, expectedFrame.minY, accuracy: 0.5)
            XCTAssertEqual(actualFrame.width, expectedFrame.width, accuracy: 0.5)
            XCTAssertEqual(actualFrame.height, expectedFrame.height, accuracy: 0.5)
        }
    }

    private func visibleFrames(in reader: ReaderViewController) throws -> (actual: [NSRect], expected: [NSRect]) {
        let documentView = try XCTUnwrap(reader.pdfView.documentView)
        let viewport = documentView.convert(reader.pdfView.bounds, from: reader.pdfView)
        let expected = reader.pdfView.visiblePages.flatMap { page in
            reader.pdfView.commentIcons.frames(on: page).map { _, frame in
                documentView.convert(reader.pdfView.convert(frame, from: page), from: reader.pdfView)
            }
        }.filter { $0.intersects(viewport) }
        let overlay = try overlay(in: reader)
        let allFrames = overlay.icons.map { documentView.convert($0.frame, from: overlay) }
        let actual = allFrames.filter { $0.intersects(viewport) }
        return (actual, expected)
    }

    private func overlay(in reader: ReaderViewController) throws -> CommentIconOverlayView {
        try XCTUnwrap(findAllDescendants(of: CommentIconOverlayView.self, in: reader.pdfView).first)
    }

    private func settle(_ reader: ReaderViewController) {
        reader.view.layoutSubtreeIfNeeded()
        reader.view.window?.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private func makeReader(
        type: AnnotationMarkupType = .highlight,
        comments: [String],
        mode: ReaderDisplayMode = .singlePage
    ) throws -> (store: DocumentStore, sessionID: UUID, reader: ReaderViewController, window: NSWindow) {
        _ = NSApplication.shared
        let url = try TestPDFFixtures.makeBlankPDF(named: "comment-overlay", pageCount: comments.count, pageSize: NSSize(width: 600, height: 800))
        let source = try XCTUnwrap(PDFDocument(url: url))
        for (index, comment) in comments.enumerated() {
            let annotation = PDFAnnotation(
                bounds: NSRect(x: 100 + 100 * index, y: 400, width: 80, height: 20),
                forType: type.pdfSubtype, withProperties: nil
            )
            annotation.userName = UUID().uuidString
            annotation.contents = comment.isEmpty ? nil : comment
            try XCTUnwrap(source.page(at: index)).addAnnotation(annotation)
        }
        XCTAssertTrue(source.write(to: url))
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: url)
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1, for: session.id)
        let reader = ReaderViewController(documentStore: store)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.view.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = reader
        window.makeKeyAndOrderFront(nil)
        settle(reader)
        return (store, session.id, reader, window)
    }
}
