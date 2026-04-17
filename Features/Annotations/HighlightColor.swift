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
}
