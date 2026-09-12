import AppKit

struct ThemeRGBComponents: Equatable, Sendable {
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

enum ThemeColorRecipe: Equatable, Sendable {
    enum Semantic: Sendable {
        case white
        case black
        case label
        case secondaryLabel
        case tertiaryLabel
    }

    case semantic(Semantic)
    case calibratedWhite(CGFloat, alpha: CGFloat = 1)
    case srgb(ThemeRGBComponents, alpha: CGFloat = 1)

    func resolve(for appearance: NSAppearance) -> NSColor {
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = switch self {
            case .semantic(.white):
                .white
            case .semantic(.black):
                .black
            case .semantic(.label):
                .labelColor
            case .semantic(.secondaryLabel):
                .secondaryLabelColor
            case .semantic(.tertiaryLabel):
                .tertiaryLabelColor
            case let .calibratedWhite(white, alpha):
                NSColor(calibratedWhite: white, alpha: alpha)
            case let .srgb(components, alpha):
                NSColor(
                    srgbRed: components.red,
                    green: components.green,
                    blue: components.blue,
                    alpha: alpha
                )
            }
        }
        return resolvedColor!
    }
}

enum ThemePDFStyle: Equatable, Sendable {
    case none
    case paper(background: ThemeRGBComponents)
    case darkPaper(
        background: ThemeRGBComponents,
        foreground: ThemeRGBComponents,
        accentPreservation: CGFloat
    )
}

enum ThemeColorRole: Sendable {
    case pageBackground
    case pageForeground
    case primaryText
    case secondaryText
    case tertiaryText
    case readerBackdrop
    case splitBackground
    case paneBackground
    case chromeDivider
    case selectedChromeBackground
    case chromeStroke
}

struct ThemeDescriptor: Equatable, Sendable {
    let pageBackground: ThemeColorRecipe
    let pageForeground: ThemeColorRecipe
    let primaryText: ThemeColorRecipe
    let secondaryText: ThemeColorRecipe
    let tertiaryText: ThemeColorRecipe
    let readerBackdrop: ThemeColorRecipe
    let splitBackground: ThemeColorRecipe
    let paneBackground: ThemeColorRecipe
    let chromeDivider: ThemeColorRecipe
    let selectedChromeBackground: ThemeColorRecipe
    let chromeStroke: ThemeColorRecipe
    let prefersFlatPDFChrome: Bool
    let highlightPalette: HighlightPalette
    let pdfStyle: ThemePDFStyle

    func color(for role: ThemeColorRole, appearance: NSAppearance) -> NSColor {
        let recipe = switch role {
        case .pageBackground: pageBackground
        case .pageForeground: pageForeground
        case .primaryText: primaryText
        case .secondaryText: secondaryText
        case .tertiaryText: tertiaryText
        case .readerBackdrop: readerBackdrop
        case .splitBackground: splitBackground
        case .paneBackground: paneBackground
        case .chromeDivider: chromeDivider
        case .selectedChromeBackground: selectedChromeBackground
        case .chromeStroke: chromeStroke
        }
        return recipe.resolve(for: appearance)
    }
}

struct ThemeSelection: Equatable, Sendable {
    var light: LightTheme
    var dark: DarkTheme

    static let `default` = ThemeSelection(light: .normal, dark: .rosePineMoon)
}

struct ThemeSnapshot: Equatable, Sendable {
    let light: ThemeDescriptor
    let dark: ThemeDescriptor

    func descriptor(for appearance: NSAppearance?) -> ThemeDescriptor {
        let resolvedAppearance = appearance ?? NSAppearance(named: .aqua)!
        return Self.isDarkAppearance(resolvedAppearance) ? dark : light
    }

    func dynamicColor(for role: ThemeColorRole) -> NSColor {
        NSColor(name: nil) { appearance in
            descriptor(for: appearance).color(for: role, appearance: appearance)
        }
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

enum ThemeRegistry {
    private static let moonBase = rgb(35, 33, 54)
    private static let moonSurface = rgb(42, 39, 63)
    private static let moonOverlay = rgb(57, 53, 82)
    private static let moonMuted = rgb(110, 106, 134)
    private static let moonSubtle = rgb(144, 140, 170)
    private static let moonText = rgb(224, 222, 244)

    private static let normalDarkPaper = rgb(37, 37, 37)
    private static let normalDarkText = rgb(222, 222, 222)
    private static let normalDarkDivider = rgb(54, 54, 54)
    private static let normalDarkSelected = rgb(68, 68, 68)
    private static let normalDarkStroke = rgb(90, 90, 90)

    private static let dawnBase = rgb(250, 244, 237)
    private static let dawnSurface = rgb(255, 250, 243)
    private static let dawnHighlight = rgb(233, 223, 218)
    private static let dawnUI = rgb(234, 227, 225)
    private static let dawnStrongUI = rgb(206, 202, 205)
    private static let dawnMuted = rgb(152, 147, 165)
    private static let dawnSubtle = rgb(121, 117, 147)
    private static let dawnText = rgb(87, 82, 121)

    static let lightThemes: [LightTheme: ThemeDescriptor] = [
        .normal: ThemeDescriptor(
            pageBackground: .semantic(.white),
            pageForeground: .semantic(.black),
            primaryText: .semantic(.label),
            secondaryText: .semantic(.secondaryLabel),
            tertiaryText: .semantic(.tertiaryLabel),
            readerBackdrop: .semantic(.white),
            splitBackground: .semantic(.white),
            paneBackground: .semantic(.white),
            chromeDivider: .calibratedWhite(0.88),
            selectedChromeBackground: .calibratedWhite(0.915),
            chromeStroke: .calibratedWhite(0.82),
            prefersFlatPDFChrome: false,
            highlightPalette: .normal,
            pdfStyle: .none
        ),
        .rosePineDawn: ThemeDescriptor(
            pageBackground: .srgb(dawnSurface),
            pageForeground: .srgb(dawnText),
            primaryText: .srgb(dawnText),
            secondaryText: .srgb(dawnSubtle),
            tertiaryText: .srgb(dawnMuted),
            readerBackdrop: .srgb(dawnBase),
            splitBackground: .srgb(dawnBase),
            paneBackground: .srgb(dawnBase),
            chromeDivider: .srgb(dawnUI),
            selectedChromeBackground: .srgb(dawnHighlight, alpha: 0.5),
            chromeStroke: .srgb(dawnStrongUI),
            prefersFlatPDFChrome: true,
            highlightPalette: .rosePineDawn,
            pdfStyle: .paper(background: dawnSurface)
        ),
    ]

    static let darkThemes: [DarkTheme: ThemeDescriptor] = [
        .normal: ThemeDescriptor(
            pageBackground: .srgb(normalDarkPaper),
            pageForeground: .srgb(normalDarkText),
            primaryText: .semantic(.label),
            secondaryText: .semantic(.secondaryLabel),
            tertiaryText: .semantic(.tertiaryLabel),
            readerBackdrop: .srgb(normalDarkPaper),
            splitBackground: .srgb(normalDarkPaper),
            paneBackground: .srgb(normalDarkPaper),
            chromeDivider: .srgb(normalDarkDivider),
            selectedChromeBackground: .srgb(normalDarkSelected),
            chromeStroke: .srgb(normalDarkStroke),
            prefersFlatPDFChrome: true,
            highlightPalette: .normal,
            pdfStyle: .darkPaper(
                background: normalDarkPaper,
                foreground: normalDarkText,
                accentPreservation: 0.08
            )
        ),
        .rosePineMoon: ThemeDescriptor(
            pageBackground: .srgb(moonSurface),
            pageForeground: .srgb(moonText),
            primaryText: .srgb(moonText),
            secondaryText: .srgb(moonSubtle),
            tertiaryText: .srgb(moonMuted),
            readerBackdrop: .srgb(moonBase),
            splitBackground: .srgb(moonBase),
            paneBackground: .srgb(moonBase),
            chromeDivider: .srgb(moonOverlay),
            selectedChromeBackground: .srgb(moonOverlay),
            chromeStroke: .srgb(moonMuted),
            prefersFlatPDFChrome: true,
            highlightPalette: .rosePineMoon,
            pdfStyle: .darkPaper(
                background: moonSurface,
                foreground: moonText,
                accentPreservation: 0.85
            )
        ),
    ]

    static func snapshot(for selection: ThemeSelection) -> ThemeSnapshot {
        ThemeSnapshot(
            light: lightThemes[selection.light]!,
            dark: darkThemes[selection.dark]!
        )
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> ThemeRGBComponents {
        ThemeRGBComponents(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
