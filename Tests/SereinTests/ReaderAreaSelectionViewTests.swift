import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderAreaSelectionViewTests: XCTestCase {
    func testReverseDragCopiesVectorContentAndReturnsFocus() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        var copied: NSImage?
        fixture.overlay.copyImage = { copied = $0; return true }
        XCTAssertTrue(fixture.overlay.begin(in: fixture.pdfView))
        XCTAssertFalse(ReaderShortcutsController.shouldHandlePlainShortcut(for: fixture.window.firstResponder))
        let hit = fixture.overlay.convert(try fixture.point(100, 100), to: fixture.overlay.superview)
        XCTAssertTrue(fixture.window.contentView?.hitTest(hit) === fixture.overlay)
        fixture.overlay.mouseDown(with: try fixture.event(.leftMouseDown, x: 110, y: 100))
        fixture.overlay.mouseDragged(with: try fixture.event(.leftMouseDragged, x: 50, y: 60))
        XCTAssertEqual(fixture.overlay.selectionRect?.width, 60)
        fixture.overlay.mouseUp(with: try fixture.event(.leftMouseUp, x: 50, y: 60))
        XCTAssertEqual(try XCTUnwrap(copied).size, NSSize(width: 120, height: 80))
        XCTAssertFalse(fixture.overlay.isSelecting)
        XCTAssertNil(fixture.overlay.selectionRect)
        XCTAssertTrue(fixture.window.firstResponder === fixture.pdfView)
        XCTAssertNil(fixture.overlay.hitTest(hit))
    }

    func testEscapePrecedesPresentationShortcutsAndNeverCopies() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        var copies = 0
        var presentationKeys = 0
        fixture.overlay.copyImage = { _ in copies += 1; return true }
        fixture.window.presentationShortcutHandler = { _ in presentationKeys += 1; return true }
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.mouseDown(with: try fixture.event(.leftMouseDown, x: 50, y: 60))
        fixture.overlay.mouseDragged(with: try fixture.event(.leftMouseDragged, x: 110, y: 100))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        fixture.window.sendEvent(escape)
        fixture.overlay.mouseUp(with: try fixture.event(.leftMouseUp, x: 110, y: 100))
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(presentationKeys, 0)
        XCTAssertFalse(fixture.overlay.isSelecting)
    }

    func testClickAndRightClickDoNotWriteClipboard() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        var copies = 0
        fixture.overlay.copyImage = { _ in copies += 1; return true }
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.mouseDown(with: try fixture.event(.leftMouseDown, x: 50, y: 60))
        fixture.overlay.mouseUp(with: try fixture.event(.leftMouseUp, x: 50, y: 60))
        XCTAssertFalse(fixture.overlay.isSelecting)
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.rightMouseDown(with: try fixture.event(.rightMouseDown, x: 50, y: 60))
        XCTAssertFalse(fixture.overlay.isSelecting)
        XCTAssertEqual(copies, 0)
    }

    func testDragIsClippedToItsStartingPage() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        var copied: NSImage?
        fixture.overlay.copyImage = { copied = $0; return true }
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.mouseDown(with: try fixture.event(.leftMouseDown, x: 350, y: 450))
        fixture.overlay.mouseUp(with: try fixture.event(.leftMouseUp, x: 450, y: 550))
        XCTAssertEqual(try XCTUnwrap(copied).size, NSSize(width: 100, height: 100))
    }

    func testDocumentChangeResizeAndWindowDeactivationCancel() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        fixture.overlay.begin(in: fixture.pdfView)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        XCTAssertFalse(fixture.overlay.isSelecting)
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.setFrameSize(NSSize(width: 700, height: 600))
        XCTAssertFalse(fixture.overlay.isSelecting)
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.pdfView.setReaderDocument(nil)
        XCTAssertFalse(fixture.overlay.isSelecting)
    }

    func testThemeSwitchingDuringDragKeepsSelectionAndUsesEveryPreset() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let original = ThemeManager.shared.selection
        defer {
            ThemeManager.shared.apply(light: original.light, dark: original.dark,
                lightBackground: original.lightBackground, darkBackground: original.darkBackground)
        }
        fixture.overlay.begin(in: fixture.pdfView)
        fixture.overlay.mouseDown(with: try fixture.event(.leftMouseDown, x: 50, y: 60))
        fixture.overlay.mouseDragged(with: try fixture.event(.leftMouseDragged, x: 110, y: 100))
        let rect = fixture.overlay.selectionRect
        let overrides = ThemeBackgroundOverrides(page: ThemeHexColor(hex: "#dfe7ed"), window: ThemeHexColor(hex: "#18242d"))
        for light in LightTheme.allCases {
            ThemeManager.shared.apply(light: light, dark: .normal, lightBackground: overrides)
            fixture.overlay.appearance = NSAppearance(named: .aqua)
            fixture.overlay.refreshThemeAppearance()
            XCTAssertEqual(fixture.overlay.selectionRect, rect)
            XCTAssertTrue(fixture.overlay.isSelecting)
        }
        for dark in DarkTheme.allCases {
            ThemeManager.shared.apply(light: .normal, dark: dark, darkBackground: overrides)
            fixture.overlay.appearance = NSAppearance(named: .darkAqua)
            fixture.overlay.refreshThemeAppearance()
            XCTAssertEqual(fixture.overlay.selectionRect, rect)
            XCTAssertTrue(fixture.overlay.isSelecting)
        }
    }

    @MainActor
    private struct Fixture {
        let window: ReaderShortcutWindow
        let pdfView: ReaderPDFView
        let overlay: ReaderAreaSelectionView

        init() throws {
            _ = NSApplication.shared
            window = ReaderShortcutWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 650))
            window.contentView = root
            let frame = NSRect(x: 30, y: 20, width: 740, height: 600)
            pdfView = ReaderPDFView(frame: frame)
            pdfView.displayMode = .singlePage
            pdfView.document = try EmbeddedImagePDFFixture.document(content: "1 0 0 rg 10 20 200 200 re f")
            pdfView.scaleFactor = 1
            overlay = ReaderAreaSelectionView(frame: frame)
            pdfView.areaSelectionOverlay = overlay
            root.addSubview(pdfView)
            root.addSubview(overlay)
            root.layoutSubtreeIfNeeded()
            pdfView.layoutDocumentView()
        }

        func point(_ x: CGFloat, _ y: CGFloat) throws -> CGPoint {
            let page = try XCTUnwrap(pdfView.document?.page(at: 0))
            return overlay.convert(pdfView.convert(CGPoint(x: x, y: y), from: page), from: pdfView)
        }

        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: overlay.convert(try point(x, y), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
    }
}
