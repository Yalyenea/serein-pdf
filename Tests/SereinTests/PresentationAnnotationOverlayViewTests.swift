import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class PresentationAnnotationOverlayViewTests: XCTestCase {
    func testPointerPassesThroughWhileToolbarAndPenRemainInteractive() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        let point = try fixture.point(on: 0)
        let parentPoint = overlay.convert(point, to: overlay.superview)

        XCTAssertNil(overlay.hitTest(parentPoint))
        overlay.setPresentationEnabled(true)
        XCTAssertNil(overlay.hitTest(parentPoint))
        overlay.selectTool(.pen)
        XCTAssertTrue(overlay.hitTest(parentPoint) === overlay)
        XCTAssertNil(overlay.hitTest(NSPoint(x: -20, y: -20)))

        let toolbar = try XCTUnwrap(overlay.subviews.first)
        let pen = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.tag == 1 })
        let buttonPoint = pen.convert(NSPoint(x: pen.bounds.midX, y: pen.bounds.midY), to: overlay.superview)
        XCTAssertTrue(overlay.hitTest(buttonPoint) === pen)
        overlay.setPresentationEnabled(false)
        XCTAssertNil(overlay.hitTest(buttonPoint))
    }

    func testMouseStrokeUsesPageCoordinatesAndLeavesExistingAnnotationsUntouched() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        let page = try XCTUnwrap(fixture.pdfView.document?.page(at: 0))
        let existing = PDFAnnotation(bounds: NSRect(x: 80, y: 80, width: 40, height: 20),
                                     forType: .highlight, withProperties: nil)
        page.addAnnotation(existing)
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.pen)
        let start = try XCTUnwrap(overlay.overlayPoint(NSPoint(x: 120, y: 160), on: page))
        let end = try XCTUnwrap(overlay.overlayPoint(NSPoint(x: 200, y: 220), on: page))
        var interactions = 0
        overlay.onInteraction = { interactions += 1 }

        overlay.mouseDown(with: fixture.mouseEvent(.leftMouseDown, at: start))
        overlay.mouseDragged(with: fixture.mouseEvent(.leftMouseDragged, at: end))
        overlay.mouseUp(with: fixture.mouseEvent(.leftMouseUp, at: end))

        XCTAssertEqual(interactions, 1)
        XCTAssertTrue(fixture.window.firstResponder === fixture.pdfView)
        let stroke = try XCTUnwrap(overlay.strokes.first)
        XCTAssertTrue(stroke.page === page)
        XCTAssertEqual(stroke.segments.count, 1)
        XCTAssertEqual(stroke.segments[0].first!.x, 120, accuracy: 0.01)
        XCTAssertEqual(stroke.segments[0].first!.y, 160, accuracy: 0.01)
        XCTAssertEqual(stroke.segments[0].last!.x, 200, accuracy: 0.01)
        XCTAssertEqual(stroke.segments[0].last!.y, 220, accuracy: 0.01)
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertTrue(page.annotations[0] === existing)
        overlay.clearCurrentPage()
        XCTAssertTrue(page.annotations[0] === existing)
    }

    func testLeavingPageSplitsStrokeAndUndoRemovesWholeGesture() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.pen)
        let point = try fixture.point(on: 0)
        overlay.beginStroke(at: point)
        overlay.continueStroke(at: NSPoint(x: point.x + 20, y: point.y))
        overlay.continueStroke(at: NSPoint(x: -100, y: -100))
        overlay.continueStroke(at: NSPoint(x: point.x, y: point.y + 30))
        overlay.endStroke()

        XCTAssertEqual(overlay.strokes.count, 1)
        XCTAssertEqual(overlay.strokes[0].segments.count, 2)
        XCTAssertEqual(overlay.strokes[0].segments[0].count, 2)
        XCTAssertEqual(overlay.strokes[0].segments[1].count, 1)
        overlay.undoCurrentPage()
        XCTAssertTrue(overlay.strokes.isEmpty)
    }

    func testPageNavigationRetainsMarksAndClearUndoOnlyAffectCurrentPage() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.pen)
        overlay.beginStroke(at: try fixture.point(on: 0))
        overlay.endStroke()
        fixture.go(to: 1)
        overlay.beginStroke(at: try fixture.point(on: 1))
        overlay.endStroke()
        overlay.beginStroke(at: try fixture.point(on: 1))
        overlay.endStroke()

        XCTAssertEqual(overlay.strokes.count, 3)
        overlay.undoCurrentPage()
        XCTAssertEqual(overlay.strokes.count, 2)
        overlay.clearCurrentPage()
        XCTAssertEqual(overlay.strokes.count, 1)
        XCTAssertTrue(overlay.strokes[0].page === fixture.pdfView.document?.page(at: 0))
        fixture.go(to: 0)
        XCTAssertEqual(overlay.strokes.count, 1)
        overlay.setPresentationEnabled(false)
        XCTAssertTrue(overlay.strokes.isEmpty)
        XCTAssertEqual(overlay.tool, .pointer)
    }

    func testPageCoordinateRoundTripSurvivesCropRotationAndZoom() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let page = try XCTUnwrap(fixture.pdfView.document?.page(at: 0))
        page.setBounds(NSRect(x: 40, y: 60, width: 300, height: 360), for: .cropBox)
        fixture.pdfView.displayBox = .cropBox
        fixture.overlay.setPresentationEnabled(true)
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            for scale in [CGFloat(0.8), 1.2] {
                fixture.pdfView.scaleFactor = scale
                fixture.settle()
                let pagePoint = NSPoint(x: 160, y: 240)
                let viewPoint = try XCTUnwrap(fixture.overlay.overlayPoint(pagePoint, on: page))
                let location = try XCTUnwrap(fixture.overlay.pageLocation(at: viewPoint))
                XCTAssertTrue(location.page === page)
                XCTAssertEqual(location.point.x, pagePoint.x, accuracy: 0.01)
                XCTAssertEqual(location.point.y, pagePoint.y, accuracy: 0.01)
            }
        }
    }

    func testLaserExpiresWithoutFurtherMovementAndStopsTimerOnLifecycleChanges() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.laser)
        let point = try fixture.point(on: 0)
        let now = ProcessInfo.processInfo.systemUptime
        overlay.updateLaser(at: point, time: now)
        overlay.updateLaser(at: NSPoint(x: point.x + 30, y: point.y), time: now + 0.1)
        XCTAssertEqual(overlay.laserSamples.count, 2)
        XCTAssertTrue(overlay.isLaserTimerRunning)
        overlay.expireLaser(at: now + 0.5)
        XCTAssertEqual(overlay.laserSamples.count, 1)
        overlay.expireLaser(at: now + 0.6)
        XCTAssertTrue(overlay.laserSamples.isEmpty)
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertEqual(overlay.laserLocation, NSPoint(x: point.x + 30, y: point.y))

        overlay.updateLaser(at: point)
        overlay.resetDocument()
        XCTAssertTrue(overlay.laserSamples.isEmpty)
        XCTAssertNil(overlay.laserLocation)
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertEqual(overlay.tool, .pointer)
        overlay.selectTool(.laser)
        overlay.updateLaser(at: point)
        fixture.go(to: 1)
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertNil(overlay.laserLocation)
        overlay.updateLaser(at: try fixture.point(on: 1))
        overlay.setPresentationEnabled(false)
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertNil(overlay.laserLocation)
    }

    func testLaserStopsWhenDetachedOrAncestorHidden() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.laser)
        overlay.updateLaser(at: try fixture.point(on: 0))
        fixture.window.contentView?.isHidden = true
        overlay.refreshGeometry()
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertNil(overlay.laserLocation)
        fixture.window.contentView?.isHidden = false
        overlay.updateLaser(at: try fixture.point(on: 0))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertNil(overlay.laserLocation)
        overlay.updateLaser(at: try fixture.point(on: 0))
        XCTAssertTrue(overlay.isLaserTimerRunning)
        overlay.removeFromSuperview()
        XCTAssertFalse(overlay.isLaserTimerRunning)
        XCTAssertNil(overlay.laserLocation)
    }

    func testShortcutsArePresentationScopedAndEscapeFirstReleasesTool() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        XCTAssertFalse(overlay.handleKeyEvent(makeKeyEvent(characters: "p")))
        overlay.setPresentationEnabled(true)
        XCTAssertTrue(overlay.handleKeyEvent(makeKeyEvent(characters: "p")))
        XCTAssertEqual(overlay.tool, .pen)
        XCTAssertFalse(overlay.handleKeyEvent(makeKeyEvent(characters: "p", modifierFlags: .command)))
        XCTAssertTrue(overlay.handleKeyEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53)))
        XCTAssertEqual(overlay.tool, .pointer)
        XCTAssertFalse(overlay.handleKeyEvent(makeKeyEvent(characters: "\u{1b}", keyCode: 53)))
        XCTAssertTrue(overlay.handleKeyEvent(makeKeyEvent(characters: "r")))
        XCTAssertEqual(overlay.tool, .laser)
        XCTAssertTrue(overlay.handleKeyEvent(makeKeyEvent(characters: "r")))
        XCTAssertEqual(overlay.tool, .pointer)
        XCTAssertTrue(overlay.handleKeyEvent(makeKeyEvent(characters: "z", modifierFlags: .command)))
        fixture.pdfView.document = nil
        overlay.resetDocument()
        XCTAssertFalse(overlay.handleKeyEvent(makeKeyEvent(characters: "p")))
        XCTAssertTrue(overlay.subviews.first!.isHidden)
        XCTAssertNil(overlay.hitTest(NSPoint(x: 200, y: 200)))
    }

    func testToolbarPinChoiceSurvivesPresentationAndDocumentChanges() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        XCTAssertTrue(overlay.isToolbarPinned)
        XCTAssertFalse(overlay.isToolbarVisible)
        overlay.setPresentationEnabled(true)
        overlay.updateToolbarVisibility(at: nil)
        XCTAssertTrue(overlay.isToolbarVisible)

        overlay.setToolbarPinned(false)
        overlay.updateToolbarVisibility(at: nil)
        XCTAssertFalse(overlay.isToolbarVisible)
        fixture.go(to: 1)
        XCTAssertFalse(overlay.isToolbarVisible)
        overlay.resetDocument()
        XCTAssertFalse(overlay.isToolbarPinned)
        XCTAssertFalse(overlay.isToolbarVisible)
        overlay.setPresentationEnabled(false)
        overlay.setPresentationEnabled(true)
        XCTAssertFalse(overlay.isToolbarPinned)
        XCTAssertFalse(overlay.isToolbarVisible)

        overlay.setToolbarPinned(true)
        XCTAssertTrue(overlay.isToolbarVisible)
        fixture.pdfView.document = nil
        overlay.resetDocument()
        XCTAssertFalse(overlay.isToolbarVisible)
        XCTAssertTrue(overlay.subviews.allSatisfy(\.isHidden))
    }

    func testAutomaticToolbarShowsOnHoverAndHidesOnMouseExit() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.setToolbarPinned(false)
        overlay.updateToolbarVisibility(at: nil)
        let toolbar = try XCTUnwrap(overlay.subviews.first)
        let reveal = try XCTUnwrap(overlay.subviews.first { $0.identifier?.rawValue == "presentation-toolbar-reveal" })
        let revealPoint = NSPoint(x: reveal.frame.midX, y: reveal.frame.midY)
        let toolbarPoint = NSPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)

        overlay.mouseMoved(with: fixture.mouseEvent(.mouseMoved, at: revealPoint))
        XCTAssertTrue(overlay.isToolbarVisible)
        overlay.mouseMoved(with: fixture.mouseEvent(.mouseMoved, at: toolbarPoint))
        XCTAssertTrue(overlay.isToolbarVisible)
        overlay.refreshGeometry()
        XCTAssertTrue(overlay.isToolbarVisible)
        overlay.mouseMoved(with: fixture.mouseEvent(.mouseMoved, at: try fixture.point(on: 0)))
        XCTAssertFalse(overlay.isToolbarVisible)
        overlay.mouseMoved(with: fixture.mouseEvent(.mouseMoved, at: revealPoint))
        XCTAssertTrue(overlay.isToolbarVisible)
        overlay.mouseExited(with: fixture.mouseEvent(.mouseExited, at: toolbarPoint))
        XCTAssertFalse(overlay.isToolbarVisible)
    }

    func testHiddenToolbarDoesNotBlockPageInputAndDragDoesNotRevealIt() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.pdfView.scaleFactor = 1.2
        fixture.settle()
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        overlay.selectTool(.pen)
        let toolbar = try XCTUnwrap(overlay.subviews.first)
        let coveredPoint = NSPoint(x: toolbar.frame.minX + 20, y: toolbar.frame.midY)
        XCTAssertNil(overlay.pageLocation(at: coveredPoint))
        overlay.setToolbarPinned(false)
        overlay.updateToolbarVisibility(at: nil)
        XCTAssertNotNil(overlay.pageLocation(at: coveredPoint))
        XCTAssertTrue(overlay.hitTest(overlay.convert(coveredPoint, to: overlay.superview)) === overlay)

        let start = try fixture.point(on: 0)
        overlay.mouseDown(with: fixture.mouseEvent(.leftMouseDown, at: start))
        overlay.mouseDragged(with: fixture.mouseEvent(.leftMouseDragged, at: coveredPoint))
        overlay.updateToolbarVisibility(at: NSPoint(x: overlay.bounds.midX, y: 16))
        XCTAssertFalse(overlay.isToolbarVisible)
        overlay.mouseUp(with: fixture.mouseEvent(.leftMouseUp, at: coveredPoint))
        let stroke = try XCTUnwrap(overlay.strokes.first)
        XCTAssertEqual(stroke.segments.count, 1)
        XCTAssertEqual(stroke.segments[0].count, 2)
        let expected = try XCTUnwrap(overlay.pageLocation(at: coveredPoint))
        XCTAssertEqual(stroke.segments[0].last!.x, expected.point.x, accuracy: 0.01)
        XCTAssertEqual(stroke.segments[0].last!.y, expected.point.y, accuracy: 0.01)
    }

    func testToolbarButtonsRevealPinAndSelectToolWithoutTakingKeyboardFocus() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let overlay = fixture.overlay
        overlay.setPresentationEnabled(true)
        let toolbar = try XCTUnwrap(overlay.subviews.first)
        let pin = try XCTUnwrap(toolbar.subviews.first {
            $0.identifier?.rawValue == "presentation-toolbar-pin"
        } as? NSButton)
        let reveal = try XCTUnwrap(overlay.subviews.first {
            $0.identifier?.rawValue == "presentation-toolbar-reveal"
        } as? NSButton)
        let pen = try XCTUnwrap(toolbar.subviews.first {
            $0.identifier?.rawValue == "presentation-1"
        } as? NSButton)
        let shortcutButtons = toolbar.subviews.compactMap { $0 as? NSButton }.filter {
            $0.identifier?.rawValue != "presentation-toolbar-pin"
        }
        XCTAssertTrue(shortcutButtons.allSatisfy { $0.title.isEmpty })
        XCTAssertTrue(shortcutButtons.allSatisfy { button in
            button.subviews.contains { $0 is ShortcutSequenceView }
        })

        pin.performClick(nil)
        XCTAssertFalse(overlay.isToolbarPinned)
        XCTAssertFalse(overlay.isToolbarVisible)
        XCTAssertFalse(reveal.isHidden)
        let revealPoint = reveal.convert(NSPoint(x: reveal.bounds.midX, y: reveal.bounds.midY),
                                         to: overlay.superview)
        XCTAssertTrue(overlay.hitTest(revealPoint) === reveal)
        reveal.performClick(nil)
        XCTAssertTrue(overlay.isToolbarVisible)
        XCTAssertTrue(reveal.isHidden)
        XCTAssertFalse(overlay.isToolbarPinned)
        pen.performClick(nil)
        XCTAssertEqual(overlay.tool, .pen)
        XCTAssertTrue(fixture.window.firstResponder === fixture.pdfView)
        pin.performClick(nil)
        overlay.updateToolbarVisibility(at: nil)
        XCTAssertTrue(overlay.isToolbarPinned)
        XCTAssertTrue(overlay.isToolbarVisible)
        XCTAssertEqual(overlay.tool, .pen)
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let pdfView: PDFView
        let overlay: PresentationAnnotationOverlayView

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 650))
            window.contentView = root
            let frame = NSRect(x: 30, y: 20, width: 740, height: 600)
            pdfView = PDFView(frame: frame)
            pdfView.displayMode = .singlePage
            pdfView.document = TestPDFFixtures.makeBlankDocument(
                pageCount: 2, pageSize: NSSize(width: 400, height: 500)
            )
            pdfView.scaleFactor = 1
            overlay = PresentationAnnotationOverlayView(frame: frame)
            overlay.pdfView = pdfView
            root.addSubview(pdfView)
            root.addSubview(overlay)
            settle()
        }

        func settle() {
            window.contentView?.layoutSubtreeIfNeeded()
            pdfView.layoutDocumentView()
            overlay.layoutSubtreeIfNeeded()
            overlay.refreshGeometry()
        }

        func go(to index: Int) {
            pdfView.go(to: pdfView.document!.page(at: index)!)
            settle()
        }

        func point(on index: Int) throws -> NSPoint {
            let page = try XCTUnwrap(pdfView.document?.page(at: index))
            return try XCTUnwrap(overlay.overlayPoint(NSPoint(x: 200, y: 250), on: page))
        }

        func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            let location = overlay.convert(point, to: nil)
            if type == .mouseEntered || type == .mouseExited {
                return NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [],
                                              timestamp: 0, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            }
            return NSEvent.mouseEvent(with: type, location: location,
                                     modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }
}
