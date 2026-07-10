import AppKit
import PDFKit
import XCTest
@testable import Serein

/// Fails first if macOS renames PDFKit private views used by night-mode chrome.
@MainActor
final class PDFKitPrivateViewSentinelTests: XCTestCase {
    func testPDFKitExposesContentBackgroundAndPageViews() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)

        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = document

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

        XCTAssertFalse(
            viewsMatching("ContentBackgroundView", in: pdfView).isEmpty,
            "PDFKit ContentBackgroundView missing — night-mode margin paint will fail silently"
        )
        XCTAssertFalse(
            viewsMatching("PDFPageView", in: pdfView).isEmpty,
            "PDFKit PDFPageView missing — night-mode page chrome will fail silently"
        )
        window.orderOut(nil)
    }

    private func viewsMatching(_ substring: String, in root: NSView) -> [NSView] {
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
