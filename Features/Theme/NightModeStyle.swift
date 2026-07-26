import AppKit
import CoreImage

enum NightModeStyle {
    private struct RGBComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        var linearized: Self {
            Self(
                red: Self.linearize(red),
                green: Self.linearize(green),
                blue: Self.linearize(blue)
            )
        }

        private static func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
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
        case paper(background: RGBComponents)
        case darkPaper(
            background: RGBComponents,
            foreground: RGBComponents,
            accentPreservation: CGFloat
        )
        case remap(
            background: RGBComponents,
            foreground: RGBComponents,
            accentPreservation: CGFloat,
            backgroundLuminance: CGFloat
        )
    }

    private struct ThemeDescriptor {
        let pageBackground: NSColor
        let pageForeground: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        let tertiaryText: NSColor
        let readerBackdrop: NSColor
        let splitBackground: NSColor
        let paneBackground: NSColor
        let chromeDivider: NSColor
        let selectedChromeBackground: NSColor
        let chromeStroke: NSColor
        let usesOpaqueSidebar: Bool
        let prefersFlatPDFChrome: Bool
        let highlightPalette: HighlightPalette
        let pdfStyle: PDFStyle
    }

    private static let luminanceWeights = RGBComponents(red: 0.2126, green: 0.7152, blue: 0.0722)

    private static let moonBase = RGBComponents(
        red: 35.0 / 255.0, green: 33.0 / 255.0, blue: 54.0 / 255.0)
    private static let moonSurface = RGBComponents(
        red: 42.0 / 255.0, green: 39.0 / 255.0, blue: 63.0 / 255.0)
    private static let moonOverlay = RGBComponents(
        red: 57.0 / 255.0, green: 53.0 / 255.0, blue: 82.0 / 255.0)
    private static let moonMuted = RGBComponents(
        red: 110.0 / 255.0, green: 106.0 / 255.0, blue: 134.0 / 255.0)
    private static let moonSubtle = RGBComponents(
        red: 144.0 / 255.0, green: 140.0 / 255.0, blue: 170.0 / 255.0)
    private static let moonText = RGBComponents(
        red: 224.0 / 255.0, green: 222.0 / 255.0, blue: 244.0 / 255.0)

    private static let dawnBase = RGBComponents(
        red: 250.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0)
    private static let dawnSurface = RGBComponents(
        red: 255.0 / 255.0, green: 250.0 / 255.0, blue: 243.0 / 255.0)
    private static let dawnHighlight = RGBComponents(
        red: 233.0 / 255.0, green: 223.0 / 255.0, blue: 218.0 / 255.0)
    private static let dawnUI = RGBComponents(
        red: 234.0 / 255.0, green: 227.0 / 255.0, blue: 225.0 / 255.0)
    private static let dawnStrongUI = RGBComponents(
        red: 206.0 / 255.0, green: 202.0 / 255.0, blue: 205.0 / 255.0)
    private static let dawnMuted = RGBComponents(
        red: 152.0 / 255.0, green: 147.0 / 255.0, blue: 165.0 / 255.0)
    private static let dawnSubtle = RGBComponents(
        red: 121.0 / 255.0, green: 117.0 / 255.0, blue: 147.0 / 255.0)
    private static let dawnText = RGBComponents(
        red: 87.0 / 255.0, green: 82.0 / 255.0, blue: 121.0 / 255.0)

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
    static let tertiaryTextColor = dynamicColor { appearance in
        activeDescriptor(for: appearance).tertiaryText
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

    static func usesOpaqueSidebar(for appearance: NSAppearance? = nil) -> Bool {
        activeDescriptor(for: appearance).usesOpaqueSidebar
    }

    static func prefersFlatPDFChrome(for appearance: NSAppearance? = nil) -> Bool {
        activeDescriptor(for: appearance).prefersFlatPDFChrome
    }

    static func highlightColor(for color: HighlightColor, appearance: NSAppearance? = nil) -> NSColor {
        color.nsColor(in: activeDescriptor(for: appearance).highlightPalette)
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
        case .paper(let background):
            guard let filter = CIFilter(name: "CIColorMatrix") else { return [] }
            let linearBackground = background.linearized
            filter.setValue(
                CIVector(x: linearBackground.red, y: 0, z: 0, w: 0),
                forKey: "inputRVector")
            filter.setValue(
                CIVector(x: 0, y: linearBackground.green, z: 0, w: 0),
                forKey: "inputGVector")
            filter.setValue(
                CIVector(x: 0, y: 0, z: linearBackground.blue, w: 0),
                forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            return [filter]
        case .darkPaper(let background, let foreground, let accentPreservation):
            guard
                let filter = makeRemapFilter(
                    background: background.linearized,
                    foreground: foreground.linearized,
                    accentPreservation: accentPreservation,
                    backgroundLuminance: 1.0
                )
            else {
                return []
            }
            return [filter]
        case .remap(
            let background,
            let foreground,
            let accentPreservation,
            let backgroundLuminance
        ):
            guard
                let filter = makeRemapFilter(
                    background: background,
                    foreground: foreground,
                    accentPreservation: accentPreservation,
                    backgroundLuminance: backgroundLuminance
                )
            else {
                return []
            }
            return [filter]
        }
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
                tertiaryText: .tertiaryLabelColor,
                readerBackdrop: .white,
                splitBackground: NSColor(calibratedWhite: 0.96, alpha: 1.0),
                paneBackground: NSColor(calibratedWhite: 0.955, alpha: 1.0),
                chromeDivider: NSColor(calibratedWhite: 0.88, alpha: 1.0),
                selectedChromeBackground: NSColor(calibratedWhite: 0.915, alpha: 1.0),
                chromeStroke: NSColor(calibratedWhite: 0.82, alpha: 1.0),
                usesOpaqueSidebar: false,
                prefersFlatPDFChrome: false,
                highlightPalette: .normal,
                pdfStyle: .none
            )
        case .rosePineDawn:
            return ThemeDescriptor(
                pageBackground: color(from: dawnSurface),
                pageForeground: color(from: dawnText),
                primaryText: color(from: dawnText),
                secondaryText: color(from: dawnSubtle),
                tertiaryText: color(from: dawnMuted),
                readerBackdrop: color(from: dawnBase),
                splitBackground: color(from: dawnBase),
                paneBackground: color(from: dawnBase),
                chromeDivider: color(from: dawnUI),
                selectedChromeBackground: color(from: dawnHighlight, alpha: 0.5),
                chromeStroke: color(from: dawnStrongUI),
                usesOpaqueSidebar: true,
                prefersFlatPDFChrome: true,
                highlightPalette: .rosePineDawn,
                pdfStyle: .paper(background: dawnSurface)
            )
        }
    }

    private static func darkDescriptor(for theme: DarkTheme) -> ThemeDescriptor {
        switch theme {
        case .normal:
            let pageBackground = RGBComponents(red: 0.09, green: 0.09, blue: 0.09)
            let pageForeground = RGBComponents(red: 0.95, green: 0.95, blue: 0.95)
            return ThemeDescriptor(
                pageBackground: NSColor(calibratedWhite: 0.09, alpha: 1.0),
                pageForeground: NSColor(calibratedWhite: 0.95, alpha: 1.0),
                primaryText: .labelColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                readerBackdrop: NSColor(calibratedWhite: 0.09, alpha: 1.0),
                splitBackground: NSColor(calibratedWhite: 0.10, alpha: 1.0),
                paneBackground: NSColor(calibratedWhite: 0.09, alpha: 1.0),
                chromeDivider: NSColor(calibratedWhite: 0.12, alpha: 1.0),
                selectedChromeBackground: NSColor(calibratedWhite: 0.19, alpha: 1.0),
                chromeStroke: NSColor(calibratedWhite: 0.28, alpha: 1.0),
                usesOpaqueSidebar: false,
                prefersFlatPDFChrome: true,
                highlightPalette: .normal,
                pdfStyle: .remap(
                    background: pageBackground, foreground: pageForeground,
                    accentPreservation: 0.08, backgroundLuminance: 0.84)
            )
        case .rosePineMoon:
            return ThemeDescriptor(
                pageBackground: color(from: moonSurface),
                pageForeground: color(from: moonText),
                primaryText: color(from: moonText),
                secondaryText: color(from: moonSubtle),
                tertiaryText: color(from: moonMuted),
                readerBackdrop: color(from: moonBase),
                splitBackground: color(from: moonBase),
                paneBackground: color(from: moonBase),
                chromeDivider: color(from: moonOverlay),
                selectedChromeBackground: color(from: moonOverlay),
                chromeStroke: color(from: moonMuted),
                usesOpaqueSidebar: true,
                prefersFlatPDFChrome: true,
                highlightPalette: .rosePineMoon,
                pdfStyle: .darkPaper(
                    background: moonSurface, foreground: moonText, accentPreservation: 0.85)
            )
        }
    }

    private static func makeRemapFilter(
        background: RGBComponents,
        foreground: RGBComponents,
        accentPreservation: CGFloat,
        backgroundLuminance: CGFloat
    ) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        let rows = colorMatrixRows(
            background: background,
            foreground: foreground,
            accentPreservation: accentPreservation,
            backgroundLuminance: backgroundLuminance
        )
        filter.setValue(
            CIVector(x: rows.red.red, y: rows.red.green, z: rows.red.blue, w: 0),
            forKey: "inputRVector")
        filter.setValue(
            CIVector(x: rows.green.red, y: rows.green.green, z: rows.green.blue, w: 0),
            forKey: "inputGVector")
        filter.setValue(
            CIVector(x: rows.blue.red, y: rows.blue.green, z: rows.blue.blue, w: 0),
            forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(
            CIVector(x: foreground.red, y: foreground.green, z: foreground.blue, w: 0),
            forKey: "inputBiasVector"
        )
        return filter
    }

    private static func colorMatrixRows(
        background: RGBComponents,
        foreground: RGBComponents,
        accentPreservation: CGFloat,
        backgroundLuminance: CGFloat
    ) -> (red: MatrixRow, green: MatrixRow, blue: MatrixRow) {
        (
            red: matrixRow(
                foreground: foreground.red,
                background: background.red,
                preserving: accentPreservation,
                backgroundLuminance: backgroundLuminance,
                diagonal: .red
            ),
            green: matrixRow(
                foreground: foreground.green,
                background: background.green,
                preserving: accentPreservation,
                backgroundLuminance: backgroundLuminance,
                diagonal: .green
            ),
            blue: matrixRow(
                foreground: foreground.blue,
                background: background.blue,
                preserving: accentPreservation,
                backgroundLuminance: backgroundLuminance,
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
        backgroundLuminance: CGFloat,
        diagonal: DiagonalChannel
    ) -> MatrixRow {
        let luminance = max(backgroundLuminance, 0.001)
        let delta = ((foreground - background) / luminance) + preserving
        return MatrixRow(
            red: (diagonal == .red ? preserving : 0) - delta * luminanceWeights.red,
            green: (diagonal == .green ? preserving : 0) - delta * luminanceWeights.green,
            blue: (diagonal == .blue ? preserving : 0) - delta * luminanceWeights.blue
        )
    }

    private static func color(from components: RGBComponents, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(
            srgbRed: components.red, green: components.green, blue: components.blue,
            alpha: alpha)
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
