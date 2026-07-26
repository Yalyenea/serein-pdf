import AppKit
import QuartzCore
import XCTest
@testable import Serein

@MainActor
final class ReadingFocusOverlayViewTests: XCTestCase {
    func testFocusBandTracksCursorAndClipsToReaderBounds() {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )
        overlay.pageBoundsProvider = { _ in NSRect(x: 50, y: 0, width: 400, height: 300) }
        overlay.setFocusEnabled(true)

        overlay.updateFocus(at: NSPoint(x: 120, y: 150))
        XCTAssertEqual(
            overlay.focusBandRect,
            NSRect(
                x: 50,
                y: 102,
                width: 400,
                height: 96
            )
        )

        overlay.updateFocus(at: NSPoint(x: 120, y: 10))
        XCTAssertEqual(
            overlay.focusBandRect,
            NSRect(
                x: 50,
                y: 0,
                width: 400,
                height: 58
            )
        )
    }

    func testColumnModeSelectsTheColumnUnderThePointer() {
        let pageBounds = NSRect(x: 50, y: 20, width: 400, height: 500)
        let settings = ReadingFocusSettings(
            widthMode: .column,
            customWidthRatio: 0.72,
            height: 100
        )

        XCTAssertEqual(
            ReadingFocusOverlayView.focusRect(
                at: NSPoint(x: 140, y: 250),
                in: pageBounds,
                clippedTo: pageBounds,
                settings: settings
            ),
            NSRect(x: 50, y: 200, width: 200, height: 100)
        )
        XCTAssertEqual(
            ReadingFocusOverlayView.focusRect(
                at: NSPoint(x: 360, y: 250),
                in: pageBounds,
                clippedTo: pageBounds,
                settings: settings
            ),
            NSRect(x: 250, y: 200, width: 200, height: 100)
        )
    }

    func testCustomWidthTracksPointerAndClampsToPageEdges() {
        let pageBounds = NSRect(x: 50, y: 0, width: 400, height: 300)
        let settings = ReadingFocusSettings(
            widthMode: .custom,
            customWidthRatio: 0.5,
            height: 80
        )

        XCTAssertEqual(
            ReadingFocusOverlayView.focusRect(
                at: NSPoint(x: 70, y: 150),
                in: pageBounds,
                clippedTo: pageBounds,
                settings: settings
            ),
            NSRect(x: 50, y: 110, width: 200, height: 80)
        )
        XCTAssertEqual(
            ReadingFocusOverlayView.focusRect(
                at: NSPoint(x: 430, y: 150),
                in: pageBounds,
                clippedTo: pageBounds,
                settings: settings
            ),
            NSRect(x: 250, y: 110, width: 200, height: 80)
        )
    }

    func testShrinkingWidthUsesOneRoundedCutoutAndOneSubtleEdgeShadow() throws {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )
        overlay.pageBoundsProvider = { _ in NSRect(x: 0, y: 0, width: 500, height: 300) }
        overlay.setFocusEnabled(true)
        overlay.updateFocus(at: NSPoint(x: 250, y: 150))

        overlay.setSettings(
            ReadingFocusSettings(widthMode: .custom, customWidthRatio: 0.5, height: 80)
        )

        let sublayers = try XCTUnwrap(overlay.layer?.sublayers)
        XCTAssertTrue(sublayers.compactMap { $0 as? CAGradientLayer }.isEmpty)
        let shapeLayers = sublayers.compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(shapeLayers.count, 2)
        let shadeLayer = shapeLayers[0]
        let focusEdgeLayer = shapeLayers[1]
        let path = try XCTUnwrap(shadeLayer.path)

        XCTAssertEqual(shadeLayer.fillRule, .evenOdd)
        XCTAssertTrue(path.contains(NSPoint(x: 20, y: 150), using: .evenOdd))
        XCTAssertTrue(path.contains(NSPoint(x: 250, y: 250), using: .evenOdd))
        XCTAssertFalse(path.contains(NSPoint(x: 250, y: 150), using: .evenOdd))
        XCTAssertTrue(path.contains(NSPoint(x: 125, y: 110), using: .evenOdd))
        XCTAssertFalse(path.contains(NSPoint(x: 131, y: 116), using: .evenOdd))
        XCTAssertEqual(focusEdgeLayer.lineWidth, 1)
        XCTAssertEqual(focusEdgeLayer.shadowRadius, 6)
        XCTAssertGreaterThan(focusEdgeLayer.shadowOpacity, 0)
        XCTAssertNotNil(focusEdgeLayer.path)
    }

    func testOverlayNeverCapturesPDFInteraction() {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )

        XCTAssertNil(overlay.hitTest(NSPoint(x: 250, y: 150)))
        XCTAssertFalse(overlay.isAccessibilityElement())
    }

    func testDisablingFocusClearsTransientState() {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )
        overlay.pageBoundsProvider = { _ in NSRect(x: 0, y: 0, width: 500, height: 300) }
        overlay.setFocusEnabled(true)
        overlay.updateFocus(at: NSPoint(x: 250, y: 150))

        overlay.setFocusEnabled(false)

        XCTAssertNil(overlay.focusLocation)
        XCTAssertNil(overlay.focusBandRect)
        XCTAssertEqual(overlay.alphaValue, 0)
    }

    func testDraggingUpdatesFocusWithoutCapturingPDFEvents() {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )
        overlay.pageBoundsProvider = { _ in NSRect(x: 0, y: 0, width: 500, height: 300) }
        overlay.setFocusEnabled(true)

        overlay.handlePointerDrag(at: NSPoint(x: 200, y: 180))

        XCTAssertEqual(overlay.focusLocation, NSPoint(x: 200, y: 180))
        XCTAssertNil(overlay.hitTest(NSPoint(x: 200, y: 180)))

        overlay.handlePointerDrag(at: NSPoint(x: 200, y: 320))
        XCTAssertNil(overlay.focusLocation)
    }

    func testPinnedFocusSupportsLivePopoverAdjustment() {
        let overlay = ReadingFocusOverlayView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 300)
        )
        let window = NSWindow(
            contentRect: overlay.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlay
        overlay.pageBoundsProvider = { _ in NSRect(x: 0, y: 0, width: 500, height: 300) }
        overlay.setFocusEnabled(true)

        overlay.setFocusPinned(true, at: NSPoint(x: 250, y: 150))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        overlay.setSettings(
            ReadingFocusSettings(widthMode: .column, customWidthRatio: 0.72, height: 120)
        )

        XCTAssertEqual(overlay.focusBandRect, NSRect(x: 250, y: 90, width: 250, height: 120))

        overlay.setFocusPinned(false)
        XCTAssertNil(overlay.focusBandRect)
    }

    func testNightModeUsesStrongerSurroundingShade() {
        let overlay = ReadingFocusOverlayView()
        let lightAlpha = overlay.shadeAlpha
        let lightShadowOpacity = overlay.edgeShadowOpacity

        overlay.setNightModeEnabled(true)

        XCTAssertGreaterThan(overlay.shadeAlpha, lightAlpha)
        XCTAssertGreaterThan(overlay.edgeShadowOpacity, lightShadowOpacity)
    }

    func testPDFContainerKeepsFocusOverlayAboveContentAndSizedToBounds() {
        let container = PDFContainerView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        let content = NSView()
        container.embedPDFView(content)
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.subviews.last === container.readingFocusOverlay)
        XCTAssertEqual(container.readingFocusOverlay.frame, container.bounds)
        XCTAssertNil(
            container.readingFocusOverlay.hitTest(NSPoint(x: 320, y: 240))
        )
    }
}
