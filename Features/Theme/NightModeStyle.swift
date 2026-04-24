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

    private static let background = RGBComponents(
        red: 35.0 / 255.0,
        green: 33.0 / 255.0,
        blue: 54.0 / 255.0
    )
    private static let surface = RGBComponents(
        red: 42.0 / 255.0,
        green: 39.0 / 255.0,
        blue: 63.0 / 255.0
    )
    private static let overlay = RGBComponents(
        red: 57.0 / 255.0,
        green: 53.0 / 255.0,
        blue: 82.0 / 255.0
    )
    private static let muted = RGBComponents(
        red: 110.0 / 255.0,
        green: 106.0 / 255.0,
        blue: 134.0 / 255.0
    )
    private static let foreground = RGBComponents(
        red: 224.0 / 255.0,
        green: 222.0 / 255.0,
        blue: 244.0 / 255.0
    )
    private static let accentPreservation: CGFloat = 0.14
    private static let luminanceWeights = RGBComponents(red: 0.2126, green: 0.7152, blue: 0.0722)

    static let pageBackgroundColor = NSColor(
        calibratedRed: background.red,
        green: background.green,
        blue: background.blue,
        alpha: 1.0
    )
    static let pageForegroundColor = NSColor(
        calibratedRed: foreground.red,
        green: foreground.green,
        blue: foreground.blue,
        alpha: 1.0
    )
    static let splitBackgroundColor = dynamicColor(
        dark: surface,
        light: NSColor(calibratedWhite: 0.96, alpha: 1.0)
    )
    static let paneBackgroundColor = dynamicColor(
        dark: surface,
        light: NSColor(calibratedWhite: 0.955, alpha: 1.0)
    )
    static let chromeDividerColor = dynamicColor(
        dark: overlay,
        light: NSColor(calibratedWhite: 0.88, alpha: 1.0)
    )
    static let selectedChromeBackgroundColor = dynamicColor(
        dark: overlay,
        light: NSColor(calibratedWhite: 0.915, alpha: 1.0)
    )
    static let chromeStrokeColor = dynamicColor(
        dark: muted,
        light: NSColor(calibratedWhite: 0.82, alpha: 1.0)
    )

    static func makePDFContentFilters() -> [CIFilter] {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return [] }
        let rows = colorMatrixRows()
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

    static func transformedColor(for color: NSColor) -> NSColor {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let input = RGBComponents(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
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
        let output = (inverted + huePreserved).clamped()
        return NSColor(calibratedRed: output.red, green: output.green, blue: output.blue, alpha: srgb.alphaComponent)
    }

    private static func colorMatrixRows() -> (red: MatrixRow, green: MatrixRow, blue: MatrixRow) {
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

    private static func color(from components: RGBComponents, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(calibratedRed: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }

    private static func dynamicColor(dark: RGBComponents, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? color(from: dark) : light
        }
    }
}
