import AppKit

enum HighlightPalette: CaseIterable, Sendable {
    case normal
    case rosePineDawn
    case rosePineMoon

    func color(for color: HighlightColor) -> NSColor {
        switch (self, color) {
        case (.normal, .pink):
            NSColor(srgbRed: 241.0 / 255.0, green: 171.0 / 255.0, blue: 192.0 / 255.0, alpha: 0.70)
        case (.normal, .yellow):
            NSColor(srgbRed: 239.0 / 255.0, green: 213.0 / 255.0, blue: 110.0 / 255.0, alpha: 0.63)
        case (.normal, .green):
            NSColor(srgbRed: 169.0 / 255.0, green: 217.0 / 255.0, blue: 180.0 / 255.0, alpha: 0.66)
        case (.rosePineDawn, .pink):
            NSColor(srgbRed: 233.0 / 255.0, green: 168.0 / 255.0, blue: 186.0 / 255.0, alpha: 0.68)
        case (.rosePineDawn, .yellow):
            NSColor(srgbRed: 228.0 / 255.0, green: 201.0 / 255.0, blue: 103.0 / 255.0, alpha: 0.62)
        case (.rosePineDawn, .green):
            NSColor(srgbRed: 159.0 / 255.0, green: 204.0 / 255.0, blue: 167.0 / 255.0, alpha: 0.64)
        case (.rosePineMoon, .pink):
            NSColor(srgbRed: 232.0 / 255.0, green: 140.0 / 255.0, blue: 171.0 / 255.0, alpha: 0.48)
        case (.rosePineMoon, .yellow):
            NSColor(srgbRed: 232.0 / 255.0, green: 196.0 / 255.0, blue: 110.0 / 255.0, alpha: 0.42)
        case (.rosePineMoon, .green):
            NSColor(srgbRed: 143.0 / 255.0, green: 207.0 / 255.0, blue: 167.0 / 255.0, alpha: 0.44)
        }
    }
}

enum HighlightColor: String, CaseIterable, Codable, Sendable {
    case pink
    case yellow
    case green

    static let `default`: HighlightColor = .pink

    var nsColor: NSColor {
        nsColor(in: .normal)
    }

    func nsColor(in palette: HighlightPalette) -> NSColor {
        palette.color(for: self)
    }

    var menuTitle: String {
        switch self {
        case .pink:
            "Pink"
        case .yellow:
            "Yellow"
        case .green:
            "Green"
        }
    }

    static func closest(to color: NSColor?) -> HighlightColor {
        guard let color else { return .default }
        let srgb = color.usingColorSpace(.sRGB) ?? color

        func distanceSquared(to candidate: HighlightColor) -> CGFloat {
            HighlightPalette.allCases.map { palette in
                let candidateColor = candidate.nsColor(in: palette)
                let target = candidateColor.usingColorSpace(.sRGB) ?? candidateColor
                let red = srgb.redComponent - target.redComponent
                let green = srgb.greenComponent - target.greenComponent
                let blue = srgb.blueComponent - target.blueComponent
                let alpha = srgb.alphaComponent - target.alphaComponent
                return red * red + green * green + blue * blue + alpha * alpha
            }.min() ?? .greatestFiniteMagnitude
        }

        return Self.allCases.min(by: { distanceSquared(to: $0) < distanceSquared(to: $1) }) ?? .default
    }
}
