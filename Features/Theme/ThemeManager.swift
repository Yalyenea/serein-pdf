import AppKit

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var selection = ThemeSelection.default

    private init() {}

    func apply(
        light: LightTheme,
        dark: DarkTheme,
        lightBackground: ThemeBackgroundOverrides = .init(),
        darkBackground: ThemeBackgroundOverrides = .init()
    ) {
        selection = ThemeSelection(light: light, dark: dark, lightBackground: lightBackground, darkBackground: darkBackground)
        snapshot = ThemeRegistry.snapshot(for: selection)
    }

    private(set) var snapshot = ThemeRegistry.snapshot(for: .default)
}
