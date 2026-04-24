import AppKit
import CoreImage

enum NightModeStyle {
    private struct RGBComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(red: lhs.red + rhs.red, green: lhs.green + rhs.green, blue: lhs.blue + rhs.blue)
        }

        static func - (lhs: Self, rhs: Self) -> Self {
            Self(red: lhs.red - rhs.red, green: lhs.green - rhs.green, blue: lhs.blue - rhs.blue)
        }

        static func * (lhs: CGFloat, rhs: Self) -> Self {
            Self(red: lhs * rhs.red, green: lhs * rhs.green, blue: lhs * rhs.blue)
        }

        func clamped() -> Self {
            Self(
                red: min(max(red, 0), 1),
                green: min(max(green, 0), 1),
                blue: min(max(blue, 0), 1)
            )
        }
    }

    private struct MatrixRow {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private enum PDFStyle {
        case none
        case classicInvert
        case remap(background: RGBComponents, foreground: RGBComponents, accentPreservation: CGFloat)
    }

    private struct ThemeDescriptor {
        let pageBackground: NSColor
        let pageForeground: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        let readerBackdrop: NSColor
        let splitBackground: NSColor
        let paneBackground: NSColor
        let chromeDivider: NSColor
        let selectedChromeBackground: NSColor
        let chromeStroke: NSColor
        let pdfStyle: PDFStyle
    }

    private static let luminanceWeights = RGBComponents(red: 0.2126, green: 0.7152, blue: 0.0722)

    private static let moonBase = RGBComponents(red: 35.0 / 255.0, green: 33.0 / 255.0, blue: 54.0 / 255.0)
    private static let moonSurface = RGBComponents(red: 42.0 / 255.0, green: 39.0 / 255.0, blue: 63.0 / 255.0)
    private static let moonOverlay = RGBComponents(red: 57.0 / 255.0, green: 53.0 / 255.0, blue: 82.0 / 255.0)
    private static let moonMuted = RGBComponents(red: 110.0 / 255.0, green: 106.0 / 255.0, blue: 134.0 / 255.0)
    private static let moonText = RGBComponents(red: 224.0 / 255.0, green: 222.0 / 255.0, blue: 244.0 / 255.0)

    private static let dawnBase = RGBComponents(red: 250.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0)
    private static let dawnSurface = RGBComponents(red: 255.0 / 255.0, green: 250.0 / 255.0, blue: 243.0 / 255.0)
    private static let dawnOverlay = RGBComponents(red: 242.0 / 255.0, green: 233.0 / 255.0, blue: 222.0 / 255.0)
    private static let dawnMuted = RGBComponents(red: 152.0 / 255.0, green: 147.0 / 255.0, blue: 165.0 / 255.0)
    private static let dawnText = RGBComponents(red: 87.0 / 255.0, green: 82.0 / 255.0, blue: 121.0 / 255.0)

    nonisolated(unsafe) private static var currentLightTheme: LightTheme = .normal
    nonisolated(unsafe) private static var currentDarkTheme: DarkTheme = .rosePineMoon

    static func applyThemeSelections(light: LightTheme, dark: DarkTheme) {
        currentLightTheme = light
        currentDarkTheme = dark
    }

    static let pageBackgroundColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).pageBackground
    }
    static let pageForegroundColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).pageForeground
    }
    static let primaryTextColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).primaryText
    }
    static let secondaryTextColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).secondaryText
    }
    static let readerBackdropColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).readerBackdrop
    }
    static let splitBackgroundColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).splitBackground
    }
    static let paneBackgroundColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).paneBackground
    }
    static let chromeDividerColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).chromeDivider
    }
    static let selectedChromeBackgroundColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).selectedChromeBackground
    }
    static let chromeStrokeColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).chromeStroke
    }

    static func makePDFContentFilters(for appearance: NSAppearance? = nil) -> [CIFilter] {
        switch activeDescriptor(for: appearance).pdfStyle {
        case .none:
            return []
        case .classicInvert:
            guard let filter = CIFilter(name: "CIColorMatrix") else { return [] }
            let scale: CGFloat = -1.0
            let bias: CGFloat = 0.95
            filter.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            filter.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
            return [filter]
        case let .remap(background, foreground, accentPreservation):
            guard let filter = CIFilter(name: "CIColorMatrix") else { return [] }
            let rows = colorMatrixRows(background: background, foreground: foreground, accentPreservation: accentPreservation)
            filter.setValue(CIVector(x: rows.red.red, y: rows.red.green, z: rows.red.blue, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: rows.green.red, y: rows.green.green, z: rows.green.blue, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: rows.blue.red, y: rows.blue.green, z: rows.blue.blue, w: 0), forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            filter.setValue(
                CIVector(x: foreground.red, y: foreground.green, z: foreground.blue, w: 0),
                forKey: "inputBiasVector"
            )
            return [filter]
        }
    }

    static func transformedColor(
        for color: NSColor,
        background: NSColor = color(from: moonBase),
        foreground: NSColor = color(from: moonText),
        accentPreservation: CGFloat = 0.14
    ) -> NSColor {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let input = RGBComponents(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
        let targetBackground = RGBComponents(
            red: (background.usingColorSpace(.sRGB) ?? background).redComponent,
            green: (background.usingColorSpace(.sRGB) ?? background).greenComponent,
            blue: (background.usingColorSpace(.sRGB) ?? background).blueComponent
        )
        let targetForeground = RGBComponents(
            red: (foreground.usingColorSpace(.sRGB) ?? foreground).redComponent,
            green: (foreground.usingColorSpace(.sRGB) ?? foreground).greenComponent,
            blue: (foreground.usingColorSpace(.sRGB) ?? foreground).blueComponent
        )
        let output = remap(input: input, background: targetBackground, foreground: targetForeground, accentPreservation: accentPreservation)
        return NSColor(calibratedRed: output.red, green: output.green, blue: output.blue, alpha: srgb.alphaComponent)
    }

    private static func activeDescriptor(for appearance: NSAppearance? = nil) -> ThemeDescriptor {
        let resolvedAppearance = appearance ?? NSAppearance(named: .aqua)!
        return isDarkAppearance(resolvedAppearance)
            ? darkDescriptor(for: currentDarkTheme)
            : lightDescriptor(for: currentLightTheme)
    }

    private static func lightDescriptor(for theme: LightTheme) -> ThemeDescriptor {
        switch theme {
        case .normal:
            return ThemeDescriptor(
                pageBackground: .white,
                pageForeground: .black,
                primaryText: .labelColor,
                secondaryText: .secondaryLabelColor,
                readerBackdrop: .white,
                splitBackground: NSColor(calibratedWhite: 0.96, alpha: 1.0),
                paneBackground: NSColor(calibratedWhite: 0.955, alpha: 1.0),
                chromeDivider: NSColor(calibratedWhite: 0.88, alpha: 1.0),
                selectedChromeBackground: NSColor(calibratedWhite: 0.915, alpha: 1.0),
                chromeStroke: NSColor(calibratedWhite: 0.82, alpha: 1.0),
                pdfStyle: .none
            )
        case .rosePineDawn:
            return ThemeDescriptor(
                pageBackground: color(from: dawnBase),
                pageForeground: color(from: dawnText),
                primaryText: color(from: dawnText),
                secondaryText: color(from: dawnMuted),
                readerBackdrop: color(from: dawnBase),
                splitBackground: color(from: dawnSurface),
                paneBackground: color(from: dawnSurface),
                chromeDivider: color(from: dawnOverlay),
                selectedChromeBackground: color(from: dawnOverlay),
                chromeStroke: color(from: dawnMuted),
                pdfStyle: .remap(background: dawnBase, foreground: dawnText, accentPreservation: 0.06)
            )
        }
    }

    private static func darkDescriptor(for theme: DarkTheme) -> ThemeDescriptor {
        switch theme {
        case .normal:
            return ThemeDescriptor(
                pageBackground: NSColor(calibratedWhite: 0.05, alpha: 1.0),
                pageForeground: NSColor(calibratedWhite: 0.95, alpha: 1.0),
                primaryText: .labelColor,
                secondaryText: .secondaryLabelColor,
                readerBackdrop: NSColor(calibratedWhite: 0.07, alpha: 1.0),
                splitBackground: NSColor(calibratedWhite: 0.10, alpha: 1.0),
                paneBackground: NSColor(calibratedWhite: 0.09, alpha: 1.0),
                chromeDivider: NSColor(calibratedWhite: 0.12, alpha: 1.0),
                selectedChromeBackground: NSColor(calibratedWhite: 0.19, alpha: 1.0),
                chromeStroke: NSColor(calibratedWhite: 0.28, alpha: 1.0),
                pdfStyle: .classicInvert
            )
        case .rosePineMoon:
            return ThemeDescriptor(
                pageBackground: color(from: moonBase),
                pageForeground: color(from: moonText),
                primaryText: color(from: moonText),
                secondaryText: color(from: moonMuted),
                readerBackdrop: color(from: moonBase),
                splitBackground: color(from: moonSurface),
                paneBackground: color(from: moonSurface),
                chromeDivider: color(from: moonOverlay),
                selectedChromeBackground: color(from: moonOverlay),
                chromeStroke: color(from: moonMuted),
                pdfStyle: .remap(background: moonBase, foreground: moonText, accentPreservation: 0.14)
            )
        }
    }

    private static func colorMatrixRows(
        background: RGBComponents,
        foreground: RGBComponents,
        accentPreservation: CGFloat
    ) -> (red: MatrixRow, green: MatrixRow, blue: MatrixRow) {
        (
            red: matrixRow(
                foreground: foreground.red,
                background: background.red,
                preserving: accentPreservation,
                diagonal: .red
            ),
            green: matrixRow(
                foreground: foreground.green,
                background: background.green,
                preserving: accentPreservation,
                diagonal: .green
            ),
            blue: matrixRow(
                foreground: foreground.blue,
                background: background.blue,
                preserving: accentPreservation,
                diagonal: .blue
            )
        )
    }

    private enum DiagonalChannel {
        case red
        case green
        case blue
    }

    private static func matrixRow(
        foreground: CGFloat,
        background: CGFloat,
        preserving: CGFloat,
        diagonal: DiagonalChannel
    ) -> MatrixRow {
        let delta = (foreground - background) + preserving
        return MatrixRow(
            red: (diagonal == .red ? preserving : 0) - delta * luminanceWeights.red,
            green: (diagonal == .green ? preserving : 0) - delta * luminanceWeights.green,
            blue: (diagonal == .blue ? preserving : 0) - delta * luminanceWeights.blue
        )
    }

    private static func remap(
        input: RGBComponents,
        background: RGBComponents,
        foreground: RGBComponents,
        accentPreservation: CGFloat
    ) -> RGBComponents {
        let luminance =
            input.red * luminanceWeights.red +
            input.green * luminanceWeights.green +
            input.blue * luminanceWeights.blue
        let inverted = foreground - luminance * (foreground - background)
        let huePreserved = accentPreservation * RGBComponents(
            red: input.red - luminance,
            green: input.green - luminance,
            blue: input.blue - luminance
        )
        return (inverted + huePreserved).clamped()
    }

    private static func color(from components: RGBComponents, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(calibratedRed: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }

    private static func dynamicColor(_ provider: @escaping (NSAppearance) -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            provider(appearance)
        }
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
