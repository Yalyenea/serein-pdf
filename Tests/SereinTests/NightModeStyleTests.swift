import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
struct NightModeStyleTests {
    @Test
    @MainActor
    func rosePineNightModeMapsPDFKitPageGrayAndBlackToThemeEndpoints() {
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
        let background = resolve(NightModeStyle.pageBackgroundColor, in: .darkAqua)
        let foreground = resolve(NightModeStyle.pageForegroundColor, in: .darkAqua)
        let transformedPageGray = NightModeStyle.transformedColor(
            for: NSColor(calibratedWhite: 0.84, alpha: 1.0),
            background: background,
            foreground: foreground,
            backgroundLuminance: 0.84
        )
        let transformedBlack = NightModeStyle.transformedColor(for: .black, background: background, foreground: foreground)

        assertColor(transformedPageGray, matches: background, tolerance: 0.08)
        assertColor(transformedBlack, matches: foreground, tolerance: 0.03)
    }

    @Test
    func rosePineNightModeTurnsSystemBlueIntoSoftIris() {
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
        let transformed = NightModeStyle.transformedColor(
            for: NSColor(calibratedRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        )
        let srgb = transformed.usingColorSpace(.sRGB) ?? transformed

        #expect(srgb.redComponent > 0.48)
        #expect(srgb.redComponent < 0.58)
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
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
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

        assertColor(page, matches: split)
    }

    @Test
    @MainActor
    func rosePineDawnChromeUsesWarmLightPalette() {
        NightModeStyle.applyThemeSelections(light: .rosePineDawn, dark: .normal)
        let backdrop = resolve(NightModeStyle.readerBackdropColor, in: .aqua)
        let page = resolve(NightModeStyle.pageBackgroundColor, in: .aqua)
        let foreground = resolve(NightModeStyle.pageForegroundColor, in: .aqua)
        let split = resolve(SplitViewController.splitBackgroundColor, in: .aqua)
        let pane = resolve(PlaceholderViewController.paneBackgroundColor, in: .aqua)
        let divider = resolve(SplitViewController.dividerBackgroundColor, in: .aqua)
        let stroke = resolve(SplitViewController.chromeStrokeColor, in: .aqua)
        let transformedWhite = NightModeStyle.transformedColor(for: .white, background: page, foreground: foreground, accentPreservation: 0.06)
        let filters = NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .aqua))

        assertColor(backdrop, matches: NSColor(calibratedRed: 250.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0, alpha: 1.0))
        assertColor(page, matches: backdrop)
        assertColor(split, matches: NSColor(calibratedRed: 1.0, green: 250.0 / 255.0, blue: 243.0 / 255.0, alpha: 1.0))
        assertColor(pane, matches: split)
        assertColor(divider, matches: NSColor(calibratedRed: 242.0 / 255.0, green: 233.0 / 255.0, blue: 222.0 / 255.0, alpha: 1.0))
        assertColor(stroke, matches: NSColor(calibratedRed: 152.0 / 255.0, green: 147.0 / 255.0, blue: 165.0 / 255.0, alpha: 1.0))
        assertColor(transformedWhite, matches: page, tolerance: 0.08)
        #expect(filters.isEmpty == false)

        #expect(abs(split.redComponent - 1.0) < 0.001)
        #expect(split.greenComponent < 0.99)
        #expect(split.blueComponent < 0.965)
    }

    @Test
    @MainActor
    func normalLightThemeKeepsUnfilteredWhitePage() {
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)

        let page = resolve(NightModeStyle.pageBackgroundColor, in: .aqua)
        let filters = NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .aqua))

        assertColor(page, matches: .white)
        #expect(filters.isEmpty)
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
