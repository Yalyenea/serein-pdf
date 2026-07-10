import AppKit
import PDFKit
import XCTest
@testable import Serein

/// Guards night-mode plumbing that walks PDFKit private view class names.
/// If macOS renames these, this fails first so we can update ReaderViewController.
@MainActor
final class PDFKitPrivateViewSentinelTests: XCTestCase {
    func testPDFKitExposesContentBackgroundAndPageViews() throws {
        let document = PDFDocument()
        let page = PDFPage()
        document.insert(page, at: 0)

        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        pdfView.layoutDocumentView()

        // Host briefly so PDFKit builds its internal scroll/page hierarchy.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = pdfView
        window.orderFront(nil)
        pdfView.layoutSubtreeIfNeeded()
        pdfView.layoutDocumentView()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let backgroundViews = viewsMatching(substring: "ContentBackgroundView", in: pdfView)
        let pageViews = viewsMatching(substring: "PDFPageView", in: pdfView)

        XCTAssertFalse(
            backgroundViews.isEmpty,
            "PDFKit ContentBackgroundView missing — night-mode margin paint will fail silently"
        )
        XCTAssertFalse(
            pageViews.isEmpty,
            "PDFKit PDFPageView missing — night-mode page chrome will fail silently"
        )

        window.orderOut(nil)
    }

    private func viewsMatching(substring: String, in root: NSView) -> [NSView] {
        var matches: [NSView] = []
        var pending = [root]
        while let view = pending.popLast() {
            if String(describing: type(of: view)).contains(substring) {
                matches.append(view)
            }
            pending.append(contentsOf: view.subviews)
        }
        return matches
    }
}
