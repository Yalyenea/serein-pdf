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
    func everyPresetMapsPaperAndTextToItsDeclaredEndpoints() throws {
        defer { ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon) }
        for theme in LightTheme.allCases where theme != .normal {
            ThemeManager.shared.apply(light: theme, dark: .normal)
            let filter = try #require(NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .aqua)).first)
            let vectors = try matrixVectors(from: filter)
            assertLinearColor(apply(vectors, to: (1, 1, 1)), matches: resolve(NightModeStyle.pageBackgroundColor, in: .aqua))
            assertLinearColor(apply(vectors, to: (0, 0, 0)), matches: .black)
        }
        for theme in DarkTheme.allCases {
            ThemeManager.shared.apply(light: .normal, dark: theme)
            let filter = try #require(NightModeStyle.makePDFContentFilters(for: NSAppearance(named: .darkAqua)).first)
            let vectors = try matrixVectors(from: filter)
            assertLinearColor(apply(vectors, to: (1, 1, 1)), matches: resolve(NightModeStyle.pageBackgroundColor, in: .darkAqua))
            assertLinearColor(apply(vectors, to: (0, 0, 0)), matches: resolve(NightModeStyle.pageForegroundColor, in: .darkAqua))
        }
    }

    @Test
    @MainActor
    func customBackgroundsKeepReadableEndpointsInEitherAppearance() throws {
        defer { ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon) }
        for hex in ["#ffffff", "#000000", "#faeedd", "#102035", "#808080", "#ff00ff"] {
            let color = try #require(ThemeHexColor(hex: hex))
            let overrides = ThemeBackgroundOverrides(page: color, window: color)
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon, lightBackground: overrides, darkBackground: overrides)
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let filter = try #require(NightModeStyle.makePDFContentFilters(for: NSAppearance(named: name)).first)
                let vectors = try matrixVectors(from: filter)
                let background = resolve(NightModeStyle.pageBackgroundColor, in: name)
                let foreground = resolve(NightModeStyle.pageForegroundColor, in: name)
                assertLinearColor(apply(vectors, to: (1, 1, 1)), matches: background)
                assertLinearColor(apply(vectors, to: (0, 0, 0)), matches: foreground)
                #expect(ThemeHexColor(color: background) == color)
                #expect(ThemeHexColor(color: resolve(NightModeStyle.readerBackdropColor, in: name)) == color)
                let primary = try #require(ThemeHexColor(color: resolve(NightModeStyle.primaryTextColor, in: name))).components
                let contrast = (max(primary.luminance, color.components.luminance) + 0.05)
                    / (min(primary.luminance, color.components.luminance) + 0.05)
                #expect(contrast >= 4.5)
            }
        }
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
