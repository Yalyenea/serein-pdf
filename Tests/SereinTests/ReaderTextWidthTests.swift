import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderTextWidthTests {
    @Test
    func fitsAsymmetricTextMarginsAndPersistsManualZoom() throws {
        try withReader { controller, reader, store, sessionID in
            let page = try #require(reader.pdfView.document?.page(at: 0))
            let cropBox = page.bounds(for: .cropBox)
            let originalData = try Data(contentsOf: try #require(store.session(for: sessionID)?.url))
            let pageWidthScale = reader.pdfView.scaleFactor

            reader.fitToTextWidth()
            settle(controller)

            try expectTextFillsViewport([page], in: reader.pdfView)
            #expect(reader.pdfView.scaleFactor > pageWidthScale * 1.2)
            let session = try #require(store.session(for: sessionID))
            #expect(session.scaleMode == .manual)
            #expect(abs(session.zoomScale - reader.pdfView.scaleFactor) < 0.001)
            #expect(page.bounds(for: .cropBox) == cropBox)
            #expect(try Data(contentsOf: session.url) == originalData)
        }
    }

    @Test
    func preservesReadingHeightAndRepeatedFitIsStable() throws {
        try withReader { controller, reader, _, _ in
            let page = try #require(reader.pdfView.document?.page(at: 0))
            controller.scrollHalfPageDown()
            controller.scrollHalfPageDown()
            settle(controller)
            let before = try viewportCenter(on: page, in: reader.pdfView)

            reader.fitToTextWidth()
            settle(controller)

            let after = try viewportCenter(on: page, in: reader.pdfView)
            #expect(abs(after.y - before.y) < 3)
            let scale = reader.pdfView.scaleFactor
            for _ in 0..<3 {
                reader.fitToTextWidth()
                settle(controller)
            }
            let repeated = try viewportCenter(on: page, in: reader.pdfView)
            #expect(abs(reader.pdfView.scaleFactor - scale) < 0.001)
            #expect(abs(repeated.x - after.x) < 1)
            #expect(abs(repeated.y - after.y) < 1)
            try expectTextFillsViewport([page], in: reader.pdfView)
        }
    }

    @Test
    func blankPDFDoesNotChangeScaleOrReadingPosition() throws {
        let url = try TestPDFFixtures.makeBlankPDF(
            named: "text-width-blank", pageSize: NSSize(width: 720, height: 2000)
        )
        try withReader(url: url) { controller, reader, store, sessionID in
            controller.scrollHalfPageDown()
            settle(controller)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
            let before = try #require(store.session(for: sessionID))
            let scale = reader.pdfView.scaleFactor
            let origin = try clipView(in: reader.pdfView).bounds.origin

            reader.fitToTextWidth()
            settle(controller)

            let after = try #require(store.session(for: sessionID))
            #expect(reader.pdfView.scaleFactor == scale)
            #expect(try clipView(in: reader.pdfView).bounds.origin == origin)
            #expect(after.scaleMode == before.scaleMode)
            #expect(after.lastReadPosition == before.lastReadPosition)
        }
    }

    @Test
    func horizontalPanLockAllowsTextWidthFitAndLocksResultingPosition() throws {
        try withReader { controller, reader, store, sessionID in
            #expect(controller.toggleHorizontalPanLock())
            settle(controller)
            let scale = reader.pdfView.scaleFactor
            let page = try #require(reader.pdfView.currentPage)

            reader.fitToTextWidth()
            settle(controller)

            #expect(reader.pdfView.scaleFactor > scale * 1.2)
            try expectTextFillsViewport([page], in: reader.pdfView)
            #expect(store.session(for: sessionID)?.scaleMode == .manual)
            #expect(store.session(for: sessionID)?.isHorizontalPanLocked == true)
            let clip = try clipView(in: reader.pdfView)
            let lockedX = clip.bounds.origin.x
            #expect(lockedX > 0)
            clip.setBoundsOrigin(NSPoint(x: lockedX + 55, y: clip.bounds.origin.y))
            settle(controller)
            #expect(abs(clip.bounds.origin.x - lockedX) < 0.1)
            reader.fitToTextWidth()
            settle(controller)
            try expectTextFillsViewport([page], in: reader.pdfView)
        }
    }

    @Test(arguments: [false, true])
    func explicitZoomCommandsPreserveAnchorsWithHorizontalPanLock(_ continuous: Bool) throws {
        var unlockedResults: [(scale: CGFloat, center: NSPoint)] = []
        for locked in [false, true] {
            try withReader(mode: continuous ? .singlePageContinuous : .singlePage) { controller, reader, store, sessionID in
                let page = try #require(reader.pdfView.currentPage)
                if locked { #expect(controller.toggleHorizontalPanLock()) }
                let commands: [() -> Void] = [
                    { reader.zoomIn() }, { reader.zoomOut() },
                    { reader.pdfView.zoomIn(nil) }, { reader.pdfView.zoomOut(nil) },
                    { reader.fitToWidth() }, { reader.fitToHeight() }, { reader.fitToPage() },
                ]
                for (index, command) in commands.enumerated() {
                    reader.fitToTextWidth()
                    controller.scrollHalfPageDown()
                    settle(controller)
                    command()
                    settle(controller)
                    let scale = reader.pdfView.scaleFactor
                    let center = try viewportCenter(on: page, in: reader.pdfView)
                    if !locked {
                        unlockedResults.append((scale, center))
                        continue
                    }
                    let expected = unlockedResults[index]
                    #expect(abs(scale - expected.scale) < 0.001)
                    #expect(abs(center.x - expected.center.x) < 1)
                    #expect(abs(center.y - expected.center.y) < 1)
                    #expect(store.session(for: sessionID)?.isHorizontalPanLocked == true)
                    #expect(reader.testingPanLockIndicatorIsVisible)
                    let clip = try clipView(in: reader.pdfView)
                    let lockedX = clip.bounds.origin.x
                    clip.setBoundsOrigin(NSPoint(x: lockedX + 55, y: clip.bounds.origin.y))
                    settle(controller)
                    #expect(abs(clip.bounds.origin.x - lockedX) < 0.1)
                }
            }
        }
    }

    @Test
    func horizontalPanLockStillBlocksMagnificationGestures() throws {
        try withReader { controller, reader, _, _ in
            #expect(controller.toggleHorizontalPanLock())
            let scale = reader.pdfView.scaleFactor
            var magnificationRequests = 0
            reader.pdfView.onUserMagnificationRequested = { magnificationRequests += 1 }
            let event = try #require(NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
            ))
            // A locked reader must reject the gesture before PDFKit handles its payload.
            reader.pdfView.magnify(with: event)
            reader.pdfView.smartMagnify(with: event)
            settle(controller)
            #expect(magnificationRequests == 0)
            #expect(reader.pdfView.scaleFactor == scale)
        }
    }

    @Test(arguments: [false, true])
    func overviewAndPresentationBlockTextWidthFit(_ presentation: Bool) throws {
        try withReader { controller, reader, store, sessionID in
            if presentation {
                reader.setPresentationEnabled(true)
            } else {
                reader.setAllPagesOverviewActive(true)
            }
            settle(controller)
            let scale = reader.pdfView.scaleFactor
            let mode = store.session(for: sessionID)?.scaleMode

            reader.fitToTextWidth()
            settle(controller)

            #expect(reader.pdfView.scaleFactor == scale)
            #expect(store.session(for: sessionID)?.scaleMode == mode)
        }
    }

    @Test(arguments: [ReaderDisplayMode.twoUp, .twoUpContinuous])
    func fitsBothPagesOfSpread(_ mode: ReaderDisplayMode) throws {
        let url = try makeTextPDF(pageCount: 2)
        try withReader(url: url, mode: mode) { controller, reader, _, _ in
            let document = try #require(reader.pdfView.document)
            let first = try #require(document.page(at: 0))
            let second = try #require(document.page(at: 1))

            reader.fitToTextWidth()
            settle(controller)

            try expectTextFillsViewport([first, second], in: reader.pdfView)
        }
    }

    @Test(arguments: [0, 90, 270], [NSScroller.Style.overlay, .legacy])
    func respectsCropBoxAndRotation(_ rotation: Int, scrollerStyle: NSScroller.Style) throws {
        let url = try makeTextPDF()
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        page.setBounds(NSRect(x: 30, y: 30, width: 660, height: 1940), for: .cropBox)
        page.rotation = rotation
        #expect(document.write(to: url))

        try withReader(url: url) { controller, reader, _, _ in
            let scroll = try #require(reader.pdfView.documentView?.enclosingScrollView)
            scroll.scrollerStyle = scrollerStyle
            settle(controller)
            let livePage = try #require(reader.pdfView.document?.page(at: 0))
            reader.fitToTextWidth()
            settle(controller)
            try expectTextFillsViewport([livePage], in: reader.pdfView)
            #expect(livePage.rotation == rotation)
            #expect(livePage.bounds(for: .cropBox) == page.bounds(for: .cropBox))
        }
    }
}

@MainActor
private func withReader(
    url: URL? = nil,
    mode: ReaderDisplayMode = .singlePage,
    body: (MainWindowController, ReaderViewController, DocumentStore, UUID) throws -> Void
) throws {
    _ = NSApplication.shared
    let store = makeIsolatedDocumentStore()
    let controller = MainWindowController(documentStore: store)
    defer { controller.close() }
    let session = try store.open(documentAt: try url ?? makeTextPDF())
    store.setDisplayMode(mode, for: session.id)
    let window = try #require(controller.window)
    window.setContentSize(MainWindowController.defaultContentSize)
    window.setFrameOrigin(NSPoint(x: 80, y: 80))
    controller.showWindow(nil)
    settle(controller)
    let split = try #require(window.contentViewController as? SplitViewController)
    let reader = split.readerViewController
    reader.fitToWidth()
    settle(controller)
    try body(controller, reader, store, session.id)
}

@MainActor
private func settle(_ controller: MainWindowController) {
    controller.window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
    controller.window?.layoutIfNeeded()
}

@MainActor
private func clipView(in pdfView: PDFView) throws -> NSClipView {
    try #require(pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView)
}

@MainActor
private func viewportCenter(on page: PDFPage, in pdfView: PDFView) throws -> NSPoint {
    let clip = try clipView(in: pdfView)
    let point = pdfView.convert(NSPoint(x: clip.bounds.midX, y: clip.bounds.midY), from: clip)
    return pdfView.convert(point, to: page)
}

@MainActor
private func expectTextFillsViewport(_ pages: [PDFPage], in pdfView: PDFView) throws {
    let clip = try clipView(in: pdfView)
    var textBounds = CGRect.null
    for page in pages {
        #expect(page.numberOfCharacters > 0)
        var pageText = CGRect.null
        for index in 0..<page.numberOfCharacters {
            let bounds = page.characterBounds(at: index)
            if !bounds.isEmpty { pageText = pageText.union(bounds) }
        }
        textBounds = textBounds.union(pdfView.convert(pageText, from: page))
    }
    let viewport = pdfView.convert(clip.bounds, from: clip)
    #expect(abs(textBounds.width - (viewport.width - 24)) < 3)
    #expect(abs(textBounds.midX - viewport.midX) < 2)
}

@MainActor
private func makeTextPDF(pageCount: Int = 1) throws -> URL {
    let root = try TestPDFFixtures.makeRootDirectory(prefix: "text-width")
    let url = root.appendingPathComponent("asymmetric-text.pdf")
    var box = CGRect(x: 0, y: 0, width: 720, height: 2000)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for row in 0..<45 {
            NSString(string: "Readable content with asymmetric margins").draw(
                at: NSPoint(x: 90, y: 100 + row * 40),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: NSColor.black,
                ]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    return url
}
