import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderShiftClickSelectionTests: XCTestCase {
    func testShiftClickSelectsForwardBackwardAcrossPagesAndKeepsAnchor() throws {
        _ = NSApplication.shared
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for text in ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ"] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (text as NSString).draw(at: NSPoint(x: 40, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        var document = try XCTUnwrap(PDFDocument(data: data as Data))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ReaderPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.setReaderDocument(document)
        view.displayMode = .singlePageContinuous
        view.scaleFactor = 1
        window.makeKeyAndOrderFront(nil)
        view.layoutDocumentView()
        view.layoutSubtreeIfNeeded()

        func click(_ pageIndex: Int, _ index: Int, shift: Bool = false, clickCount: Int = 1, edge: CGFloat = 0.5, offsetX: CGFloat = 0) throws {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let rect = page.characterBounds(at: index)
            let point = view.convert(NSPoint(x: rect.minX + rect.width * edge + offsetX, y: rect.midY), from: page)
            let location = view.convert(point, to: nil)
            let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: flags, timestamp: 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: clickCount, pressure: 0))
            NSApp.postEvent(up, atStart: true)
            defer {
                if NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: false) === up {
                    _ = NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: true)
                }
            }
            // Match the app event loop so hitTest observes the dispatched event.
            NSApp.postEvent(down, atStart: true)
            let dispatched = try XCTUnwrap(NSApp.nextEvent(matching: .leftMouseDown, until: .now, inMode: .default, dequeue: true))
            NSApp.sendEvent(dispatched)
        }

        try click(0, 2, edge: 0, offsetX: -0.1)
        try click(0, 6, shift: true, edge: 1, offsetX: 0.1)
        XCTAssertEqual(view.currentSelection?.string, "CDEFG")
        try click(0, 4, shift: true, edge: 1, offsetX: 0.1)
        XCTAssertEqual(view.currentSelection?.string, "CDE")
        try click(0, 0, shift: true, edge: 0, offsetX: -0.1)
        XCTAssertEqual(view.currentSelection?.string, "AB")
        try click(1, 2, shift: true, edge: 1, offsetX: 0.1)
        XCTAssertEqual(view.currentSelection?.pages.count, 2)
        XCTAssertEqual(view.currentSelection?.string?.replacingOccurrences(of: "\n", with: ""), "CDEFGHIJKLMNOP")
        try click(1, 4, edge: 1, offsetX: 0.1)
        try click(0, 11, shift: true, edge: 0, offsetX: -0.1)
        XCTAssertEqual(view.currentSelection?.string?.replacingOccurrences(of: "\n", with: ""), "LMNOPQR")
        // Readers click before or after text, not only in the center of a glyph.
        try click(0, 0, offsetX: -15)
        try click(0, 6, shift: true, edge: 1, offsetX: 0.1)
        XCTAssertEqual(view.currentSelection?.string, "ABCDEFG")
        try click(0, 12, shift: true, offsetX: 15)
        XCTAssertEqual(view.currentSelection?.string, "ABCDEFGHIJKLM")
        view.setReaderDocument(nil)
        document = try XCTUnwrap(PDFDocument(data: data as Data))
        view.setReaderDocument(document)
        view.layoutDocumentView()
        try click(0, 4, shift: true)
        XCTAssertNotEqual(view.currentSelection?.pages.count, 2)
        try click(0, 4, clickCount: 2)
        XCTAssertEqual(view.currentSelection?.string, "ABCDEFGHIJKLM")
    }
}
