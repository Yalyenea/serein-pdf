import AppKit

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var selection = ThemeSelection.default

    private init() {}

    func apply(light: LightTheme, dark: DarkTheme) {
        selection = ThemeSelection(light: light, dark: dark)
    }

    var snapshot: ThemeSnapshot {
        ThemeRegistry.snapshot(for: selection)
    }
}
