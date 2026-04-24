import AppKit
import Testing
@testable import SlatePDF

struct NightModeStyleTests {
    @Test
    func rosePineNightModeMapsBlackAndWhiteToThemeEndpoints() {
        let transformedWhite = NightModeStyle.transformedColor(for: .white)
        let transformedBlack = NightModeStyle.transformedColor(for: .black)

        assertColor(transformedWhite, matches: NightModeStyle.pageBackgroundColor)
        assertColor(transformedBlack, matches: NightModeStyle.pageForegroundColor)
    }

    @Test
    func rosePineNightModeTurnsSystemBlueIntoSoftIris() {
        let transformed = NightModeStyle.transformedColor(
            for: NSColor(calibratedRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        )
        let srgb = transformed.usingColorSpace(.sRGB) ?? transformed

        #expect(srgb.redComponent > 0.48)
        #expect(srgb.redComponent < 0.55)
        #expect(srgb.greenComponent > 0.53)
        #expect(srgb.greenComponent < 0.64)
        #expect(srgb.blueComponent > 0.70)
        #expect(srgb.blueComponent < 0.78)
        #expect(srgb.blueComponent > srgb.greenComponent)
        #expect(srgb.greenComponent > srgb.redComponent)
    }

    @Test
    @MainActor
    func rosePineSidebarChromeUsesNearbySurfaceSteps() {
        let page = resolve(NightModeStyle.pageBackgroundColor, in: .darkAqua)
        let split = resolve(SplitViewController.splitBackgroundColor, in: .darkAqua)
        let pane = resolve(PlaceholderViewController.paneBackgroundColor, in: .darkAqua)
        let divider = resolve(SplitViewController.dividerBackgroundColor, in: .darkAqua)
        let selected = resolve(SplitViewController.selectedChromeBackgroundColor, in: .darkAqua)
        let stroke = resolve(SplitViewController.chromeStrokeColor, in: .darkAqua)

        assertColor(split, matches: NSColor(calibratedRed: 42.0 / 255.0, green: 39.0 / 255.0, blue: 63.0 / 255.0, alpha: 1.0))
        assertColor(pane, matches: split)
        assertColor(divider, matches: NSColor(calibratedRed: 57.0 / 255.0, green: 53.0 / 255.0, blue: 82.0 / 255.0, alpha: 1.0))
        assertColor(selected, matches: divider)
        assertColor(stroke, matches: NSColor(calibratedRed: 110.0 / 255.0, green: 106.0 / 255.0, blue: 134.0 / 255.0, alpha: 1.0))

        #expect(split.redComponent > page.redComponent)
        #expect(split.greenComponent > page.greenComponent)
        #expect(split.blueComponent > page.blueComponent)
        #expect(split.redComponent - page.redComponent < 0.045)
        #expect(split.greenComponent - page.greenComponent < 0.045)
        #expect(split.blueComponent - page.blueComponent < 0.045)
    }

    private func assertColor(_ lhs: NSColor, matches rhs: NSColor, tolerance: CGFloat = 0.002) {
        let left = lhs.usingColorSpace(.sRGB) ?? lhs
        let right = rhs.usingColorSpace(.sRGB) ?? rhs

        #expect(abs(left.redComponent - right.redComponent) < tolerance)
        #expect(abs(left.greenComponent - right.greenComponent) < tolerance)
        #expect(abs(left.blueComponent - right.blueComponent) < tolerance)
        #expect(abs(left.alphaComponent - right.alphaComponent) < tolerance)
    }

    private func resolve(_ color: NSColor, in appearanceName: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: appearanceName) ?? NSAppearance(named: .aqua)!
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}
