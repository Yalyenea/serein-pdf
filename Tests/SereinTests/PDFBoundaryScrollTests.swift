import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct PDFBoundaryScrollTests {
    @Test(arguments: [ReaderDisplayMode.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous])
    func documentEdgesRejectTinyOffsetsAndWheelOverscroll(mode: ReaderDisplayMode) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let url: URL
        if let path = ProcessInfo.processInfo.environment["SEREIN_BOUNDARY_TEST_PDF"] {
            url = URL(fileURLWithPath: path)
        } else {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".tmp/pdf-boundary-tests/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            url = root.appendingPathComponent("boundary.pdf")
            let document = TestPDFFixtures.makeBlankDocument(
                pageCount: 3, pageSize: NSSize(width: 720, height: 1800)
            )
            #expect(document.write(to: url))
        }
        let session = try store.open(documentAt: url)
        store.setDisplayMode(mode, for: session.id)
        settle(controller.window)
        let split = try #require(controller.window?.contentViewController as? SplitViewController)
        let reader = split.readerViewController
        let scroll = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first)
        let clip = scroll.contentView
        let document = try #require(clip.documentView)
        // Real PDFs may fit completely, especially in two-up mode. Enlarge
        // them so reversing at an edge exercises actual in-page scrolling.
        while document.frame.height <= clip.bounds.height + 20,
              reader.pdfView.scaleFactor < reader.pdfView.maxScaleFactor {
            reader.zoomIn()
            settle(controller.window)
        }
        try #require(document.frame.height > clip.bounds.height + 20)

        for atEnd in [false, true] {
            if atEnd { reader.goToLastPage() } else { reader.goToFirstPage() }
            settle(controller.window)
            let proposed = NSRect(
                x: clip.bounds.minX, y: atEnd ? 1_000_000 : -1_000_000,
                width: clip.bounds.width, height: clip.bounds.height
            )
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
            settle(controller.window)
            let edge = clip.bounds.origin
            let outward: CGFloat = atEnd ? 1 : -1
            // NSScrollView applies wheel deltas in its document coordinate system.
            // PDFKit's document orientation differs between macOS releases.
            let outwardWheelDirection: Int32 = (atEnd ? -1 : 1) * (clip.isFlipped ? 1 : -1)
            print("Boundary start: mode=\(mode), end=\(atEnd), clipFlipped=\(clip.isFlipped), documentFlipped=\(document.isFlipped), edge=\(edge), clip=\(clip.bounds), document=\(document.frame), scale=\(reader.pdfView.scaleFactor), scaleMode=\(session.scaleMode), page=\(session.currentPageIndex), windowVisible=\(controller.window?.isVisible == true)")
            let samples = BoundarySamples()
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: nil
            ) { _ in
                MainActor.assumeIsolated { samples.origins.append(clip.bounds.origin) }
            }

            for delta: CGFloat in [0.1, 0.25, 0.6, 2, 8] {
                clip.scroll(to: NSPoint(x: edge.x, y: edge.y + outward * delta))
                #expect(abs(clip.bounds.origin.y - edge.y) < 0.01)
            }
            #expect(samples.origins.isEmpty)
            for _ in 0..<4 {
                let cg = try #require(CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: outwardWheelDirection * 2, wheel2: 0, wheel3: 0
                ))
                let event = try #require(NSEvent(cgEvent: cg))
                scroll.scrollWheel(with: event)
                settle(controller.window)
                if abs(clip.bounds.origin.y - edge.y) >= 0.01 {
                    print("Boundary changed: mode=\(mode), end=\(atEnd), deltaY=\(event.scrollingDeltaY), clipFlipped=\(clip.isFlipped), documentFlipped=\(document.isFlipped), origin=\(clip.bounds.origin), document=\(document.frame), scale=\(reader.pdfView.scaleFactor), scaleMode=\(session.scaleMode), page=\(session.currentPageIndex), windowVisible=\(controller.window?.isVisible == true), constrainedEdge=\(clip.constrainBoundsRect(proposed))")
                }
                #expect(abs(clip.bounds.origin.y - edge.y) < 0.01)
            }
            NotificationCenter.default.removeObserver(observer)
            #expect(samples.origins.allSatisfy { abs($0.y - edge.y) < 0.01 })

            clip.scroll(to: NSPoint(x: edge.x, y: edge.y - outward * 12))
            scroll.reflectScrolledClipView(clip)
            settle(controller.window)
            #expect(abs(clip.bounds.origin.y - (edge.y - outward * 12)) < 0.5)

            clip.scroll(to: edge)
            scroll.reflectScrolledClipView(clip)
            let pdf = try #require(reader.pdfView.document)
            let pageBefore = pdf.index(for: try #require(reader.pdfView.currentPage))
            for _ in 0..<3 {
                let cg = try #require(CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: -outwardWheelDirection * 12, wheel2: 0, wheel3: 0
                ))
                scroll.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
                settle(controller.window)
            }
            let pageAfter = pdf.index(for: try #require(reader.pdfView.currentPage))
            let turnedInward = atEnd ? pageAfter < pageBefore : pageAfter > pageBefore
            #expect((clip.bounds.origin.y - edge.y) * outward < -0.5 || turnedInward)
        }
    }

    private func settle(_ window: NSWindow?) {
        window?.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        window?.layoutIfNeeded()
    }
}

@MainActor
private final class BoundarySamples {
    var origins: [NSPoint] = []
}
