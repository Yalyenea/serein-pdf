import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
struct NightModeStyleTests {
    /// Reset global theme so other suites do not inherit Dawn/Moon selections.
    @MainActor
    private func withThemeSelections(
        light: LightTheme,
        dark: DarkTheme,
        _ body: () throws -> Void
    ) rethrows {
        ThemeManager.shared.apply(light: light, dark: dark)
        defer { ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon) }
        try body()
    }

    @Test
    @MainActor
    func registryCoversEveryConfiguredTheme() {
        #expect(Set(ThemeRegistry.lightThemes.keys) == Set(LightTheme.allCases))
        #expect(Set(ThemeRegistry.darkThemes.keys) == Set(DarkTheme.allCases))
        #expect(ThemeSelection.default == ThemeSelection(light: .normal, dark: .rosePineMoon))
    }

    @Test
    @MainActor
    func dynamicColorsCaptureImmutableThemeSnapshot() {
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        let normalColor = NightModeStyle.pageBackgroundColor

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        defer { ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon) }
        let dawnColor = NightModeStyle.pageBackgroundColor

        assertColor(resolve(normalColor, in: .aqua), matches: .white)
        assertColor(
            resolve(dawnColor, in: .aqua),
            matches: NSColor(
                srgbRed: 1,
                green: 250.0 / 255.0,
                blue: 243.0 / 255.0,
                alpha: 1
            )
        )
    }

    @Test
    @MainActor
    func rosePineMoonFilterMapsWhiteAndBlackToThemeEndpoints() throws {
        try withThemeSelections(light: .normal, dark: .rosePineMoon) {
            let background = resolve(NightModeStyle.pageBackgroundColor, in: .darkAqua)
            let foreground = resolve(NightModeStyle.pageForegroundColor, in: .darkAqua)
            let filter = try #require(
                NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .darkAqua)).first
            )
            let vectors = try matrixVectors(from: filter)
            let transformedWhite = apply(vectors, to: (red: 1, green: 1, blue: 1))
            let transformedBlack = apply(vectors, to: (red: 0, green: 0, blue: 0))

            assertLinearColor(transformedWhite, matches: background)
            assertLinearColor(transformedBlack, matches: foreground)
        }
    }

    @Test
    @MainActor
    func rosePineMoonFilterPreservesWarmAndCoolAccentDirection() throws {
        try withThemeSelections(light: .normal, dark: .rosePineMoon) {
            let filter = try #require(
                NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .darkAqua)).first
            )
            let vectors = try matrixVectors(from: filter)
            let warm = apply(
                vectors,
                to: linearized(red: 0.76, green: 0.48, blue: 0.09)
            )
            let cool = apply(
                vectors,
                to: linearized(red: 0.40, green: 0.52, blue: 0.63)
            )

            #expect(warm.red > warm.green)
            #expect(warm.green > warm.blue)
            #expect(cool.blue > cool.green)
            #expect(cool.green > cool.red)
        }
    }

    @Test
    @MainActor
    func rosePineSidebarChromeUsesNearbySurfaceSteps() {
        withThemeSelections(light: .normal, dark: .rosePineMoon) {
            let page = resolve(NightModeStyle.pageBackgroundColor, in: .darkAqua)
            let primary = resolve(NightModeStyle.primaryTextColor, in: .darkAqua)
            let secondary = resolve(NightModeStyle.secondaryTextColor, in: .darkAqua)
            let tertiary = resolve(NightModeStyle.tertiaryTextColor, in: .darkAqua)
            let split = resolve(SplitViewController.splitBackgroundColor, in: .darkAqua)
            let pane = resolve(PlaceholderViewController.paneBackgroundColor, in: .darkAqua)
            let divider = resolve(SplitViewController.dividerBackgroundColor, in: .darkAqua)
            let selected = resolve(SplitViewController.selectedChromeBackgroundColor, in: .darkAqua)
            let stroke = resolve(SplitViewController.chromeStrokeColor, in: .darkAqua)

            assertColor(page, matches: NSColor(srgbRed: 42.0 / 255.0, green: 39.0 / 255.0, blue: 63.0 / 255.0, alpha: 1.0))
            assertColor(split, matches: NSColor(srgbRed: 35.0 / 255.0, green: 33.0 / 255.0, blue: 54.0 / 255.0, alpha: 1.0))
            assertColor(pane, matches: split)
            assertColor(primary, matches: NSColor(srgbRed: 224.0 / 255.0, green: 222.0 / 255.0, blue: 244.0 / 255.0, alpha: 1.0))
            assertColor(secondary, matches: NSColor(srgbRed: 144.0 / 255.0, green: 140.0 / 255.0, blue: 170.0 / 255.0, alpha: 1.0))
            assertColor(tertiary, matches: NSColor(srgbRed: 110.0 / 255.0, green: 106.0 / 255.0, blue: 134.0 / 255.0, alpha: 1.0))
            assertColor(divider, matches: NSColor(srgbRed: 57.0 / 255.0, green: 53.0 / 255.0, blue: 82.0 / 255.0, alpha: 1.0))
            assertColor(selected, matches: divider)
            assertColor(stroke, matches: NSColor(srgbRed: 110.0 / 255.0, green: 106.0 / 255.0, blue: 134.0 / 255.0, alpha: 1.0))
            #expect(NightModeStyle.usesOpaqueSidebar(for: NSAppearance(named: .darkAqua)))
        }
    }

    @Test
    @MainActor
    func rosePineDawnChromeUsesWarmLightPalette() throws {
        try withThemeSelections(light: .rosePineDawn, dark: .normal) {
            let backdrop = resolve(NightModeStyle.readerBackdropColor, in: .aqua)
            let page = resolve(NightModeStyle.pageBackgroundColor, in: .aqua)
            let foreground = resolve(NightModeStyle.pageForegroundColor, in: .aqua)
            let primary = resolve(NightModeStyle.primaryTextColor, in: .aqua)
            let secondary = resolve(NightModeStyle.secondaryTextColor, in: .aqua)
            let tertiary = resolve(NightModeStyle.tertiaryTextColor, in: .aqua)
            let split = resolve(SplitViewController.splitBackgroundColor, in: .aqua)
            let pane = resolve(PlaceholderViewController.paneBackgroundColor, in: .aqua)
            let divider = resolve(SplitViewController.dividerBackgroundColor, in: .aqua)
            let selected = resolve(SplitViewController.selectedChromeBackgroundColor, in: .aqua)
            let stroke = resolve(SplitViewController.chromeStrokeColor, in: .aqua)
            let filters = NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .aqua))
            let filter = try #require(filters.first)
            let redVector = try #require(filter.value(forKey: "inputRVector") as? CIVector)
            let greenVector = try #require(filter.value(forKey: "inputGVector") as? CIVector)
            let blueVector = try #require(filter.value(forKey: "inputBVector") as? CIVector)
            let biasVector = try #require(filter.value(forKey: "inputBiasVector") as? CIVector)

            assertColor(backdrop, matches: NSColor(srgbRed: 250.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0, alpha: 1.0))
            assertColor(page, matches: NSColor(srgbRed: 1.0, green: 250.0 / 255.0, blue: 243.0 / 255.0, alpha: 1.0))
            assertColor(split, matches: backdrop)
            assertColor(pane, matches: backdrop)
            assertColor(foreground, matches: primary)
            assertColor(primary, matches: NSColor(srgbRed: 87.0 / 255.0, green: 82.0 / 255.0, blue: 121.0 / 255.0, alpha: 1.0))
            assertColor(secondary, matches: NSColor(srgbRed: 121.0 / 255.0, green: 117.0 / 255.0, blue: 147.0 / 255.0, alpha: 1.0))
            assertColor(tertiary, matches: NSColor(srgbRed: 152.0 / 255.0, green: 147.0 / 255.0, blue: 165.0 / 255.0, alpha: 1.0))
            assertColor(divider, matches: NSColor(srgbRed: 234.0 / 255.0, green: 227.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0))
            assertColor(selected, matches: NSColor(srgbRed: 233.0 / 255.0, green: 223.0 / 255.0, blue: 218.0 / 255.0, alpha: 0.5))
            assertColor(stroke, matches: NSColor(srgbRed: 206.0 / 255.0, green: 202.0 / 255.0, blue: 205.0 / 255.0, alpha: 1.0))
            #expect(filters.map(\.name) == ["CIColorMatrix"])
            #expect(abs(redVector.x - 1.0) < 0.0005)
            #expect(abs(greenVector.y - 0.956) < 0.0005)
            #expect(abs(blueVector.z - 0.896) < 0.0005)
            #expect(redVector.y == 0 && redVector.z == 0)
            #expect(greenVector.x == 0 && greenVector.z == 0)
            #expect(blueVector.x == 0 && blueVector.y == 0)
            #expect(biasVector.x == 0 && biasVector.y == 0 && biasVector.z == 0)
            #expect(NightModeStyle.usesOpaqueSidebar(for: NSAppearance(named: .aqua)))
            #expect(NightModeStyle.prefersFlatPDFChrome(for: NSAppearance(named: .aqua)))
        }
    }

    @Test
    @MainActor
    func normalLightThemeKeepsUnfilteredWhitePage() {
        withThemeSelections(light: .normal, dark: .rosePineMoon) {
            let page = resolve(NightModeStyle.pageBackgroundColor, in: .aqua)
            let filters = NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .aqua))

            assertColor(page, matches: .white)
            #expect(filters.isEmpty)
        }
    }

    private typealias RGB = (red: CGFloat, green: CGFloat, blue: CGFloat)
    private typealias MatrixVectors = (
        red: CIVector,
        green: CIVector,
        blue: CIVector,
        bias: CIVector
    )

    private func matrixVectors(from filter: CIFilter) throws -> MatrixVectors {
        #expect(filter.name == "CIColorMatrix")
        return try (
            red: #require(filter.value(forKey: "inputRVector") as? CIVector),
            green: #require(filter.value(forKey: "inputGVector") as? CIVector),
            blue: #require(filter.value(forKey: "inputBVector") as? CIVector),
            bias: #require(filter.value(forKey: "inputBiasVector") as? CIVector)
        )
    }

    private func apply(_ vectors: MatrixVectors, to input: RGB) -> RGB {
        (
            red: vectors.red.x * input.red + vectors.red.y * input.green
                + vectors.red.z * input.blue + vectors.bias.x,
            green: vectors.green.x * input.red + vectors.green.y * input.green
                + vectors.green.z * input.blue + vectors.bias.y,
            blue: vectors.blue.x * input.red + vectors.blue.y * input.green
                + vectors.blue.z * input.blue + vectors.bias.z
        )
    }

    private func assertLinearColor(
        _ color: RGB,
        matches expectedColor: NSColor,
        tolerance: CGFloat = 0.001
    ) {
        let expected = expectedColor.usingColorSpace(.sRGB) ?? expectedColor
        let linearExpected = linearized(
            red: expected.redComponent,
            green: expected.greenComponent,
            blue: expected.blueComponent
        )

        #expect(abs(color.red - linearExpected.red) < tolerance)
        #expect(abs(color.green - linearExpected.green) < tolerance)
        #expect(abs(color.blue - linearExpected.blue) < tolerance)
    }

    private func linearized(red: CGFloat, green: CGFloat, blue: CGFloat) -> RGB {
        (
            red: linearize(red),
            green: linearize(green),
            blue: linearize(blue)
        )
    }

    private func linearize(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
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
