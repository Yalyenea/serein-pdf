import AppKit

enum HighlightColor: String, CaseIterable, Codable, Sendable {
    case pink
    case yellow
    case green

    static let `default`: HighlightColor = .pink

    var nsColor: NSColor {
        switch self {
        case .pink:
            NSColor(calibratedRed: 0.97, green: 0.79, blue: 0.86, alpha: 0.85)
        case .yellow:
            NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.62, alpha: 0.82)
        case .green:
            NSColor(calibratedRed: 0.74, green: 0.92, blue: 0.78, alpha: 0.82)
        }
    }

    var menuTitle: String {
        switch self {
        case .pink: "Pink"
        case .yellow: "Yellow"
        case .green: "Green"
        }
    }

    static func closest(to color: NSColor?) -> HighlightColor {
        guard let color else { return .default }
        let srgb = color.usingColorSpace(.sRGB) ?? color

        func distanceSquared(to candidate: HighlightColor) -> CGFloat {
            let target = candidate.nsColor.usingColorSpace(.sRGB) ?? candidate.nsColor
            let red = srgb.redComponent - target.redComponent
            let green = srgb.greenComponent - target.greenComponent
            let blue = srgb.blueComponent - target.blueComponent
            let alpha = srgb.alphaComponent - target.alphaComponent
            return red * red + green * green + blue * blue + alpha * alpha
        }

        return Self.allCases.min(by: { distanceSquared(to: $0) < distanceSquared(to: $1) }) ?? .default
    }
}
