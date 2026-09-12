import AppKit
import CoreImage

@MainActor
enum NightModeStyle {
    private struct MatrixRow {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private static let luminanceWeights = ThemeRGBComponents(
        red: 0.2126,
        green: 0.7152,
        blue: 0.0722
    )

    static var pageBackgroundColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .pageBackground)
    }

    static var pageForegroundColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .pageForeground)
    }

    static var primaryTextColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .primaryText)
    }

    static var secondaryTextColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .secondaryText)
    }

    static var tertiaryTextColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .tertiaryText)
    }

    static var readerBackdropColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .readerBackdrop)
    }

    static var splitBackgroundColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .splitBackground)
    }

    static var paneBackgroundColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .paneBackground)
    }

    static var chromeDividerColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .chromeDivider)
    }

    static var selectedChromeBackgroundColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .selectedChromeBackground)
    }

    static var chromeStrokeColor: NSColor {
        ThemeManager.shared.snapshot.dynamicColor(for: .chromeStroke)
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
                    accentPreservation: accentPreservation
                )
            else {
                return []
            }
            return [filter]
        }
    }

    private static func activeDescriptor(for appearance: NSAppearance?) -> ThemeDescriptor {
        ThemeManager.shared.snapshot.descriptor(for: appearance)
    }

    private static func makeRemapFilter(
        background: ThemeRGBComponents,
        foreground: ThemeRGBComponents,
        accentPreservation: CGFloat
    ) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        let rows = colorMatrixRows(
            background: background,
            foreground: foreground,
            accentPreservation: accentPreservation
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
        background: ThemeRGBComponents,
        foreground: ThemeRGBComponents,
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
}
