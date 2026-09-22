import AppKit

// Color tokens from Rosewash's src/content/core.js PRESETS.
// Reuses Serein's paper tint and color-preserving dark remap.
enum ThemePresets {
    static let light: [LightTheme: ThemeDescriptor] = [
        .absolutely: make(base: 0xf9f9f7, surface: 0xf4f4f2, overlay: 0xebebe8, muted: 0x939391, text: 0x2d2d2b, isDark: false),
        .catppuccin: make(base: 0xeff1f5, surface: 0xe6e9ef, overlay: 0xccd0da, muted: 0x9ca0b0, text: 0x4c4f69, isDark: false),
        .codex: make(base: 0xf7f7f7, surface: 0xffffff, overlay: 0xececec, muted: 0x666666, text: 0x0d0d0d, isDark: false),
        .everforest: make(base: 0xfdf6e3, surface: 0xf4f0d9, overlay: 0xefebd4, muted: 0x939f91, text: 0x5c6a72, isDark: false),
        .github: make(base: 0xffffff, surface: 0xf6f8fa, overlay: 0xeaeef2, muted: 0x656d76, text: 0x1f2328, isDark: false),
        .gruvbox: make(base: 0xfbf1c7, surface: 0xf2e5bc, overlay: 0xebdbb2, muted: 0x928374, text: 0x3c3836, isDark: false),
        .linear: make(base: 0xf7f8fa, surface: 0xffffff, overlay: 0xeef0f4, muted: 0x8a93a6, text: 0x2a3140, isDark: false),
        .notion: make(base: 0xffffff, surface: 0xf7f6f3, overlay: 0xf1efe8, muted: 0x787774, text: 0x37352f, isDark: false),
        .one: make(base: 0xfafafa, surface: 0xf0f0f1, overlay: 0xe5e5e6, muted: 0xa0a1a7, text: 0x383a42, isDark: false),
        .proof: make(base: 0xf5f3ed, surface: 0xefede6, overlay: 0xe5e2d8, muted: 0x8b877c, text: 0x2f312d, isDark: false),
        .raycast: make(base: 0xffffff, surface: 0xf4f4f5, overlay: 0xe4e4e7, muted: 0x71717a, text: 0x18181b, isDark: false),
        .solarized: make(base: 0xfdf6e3, surface: 0xeee8d5, overlay: 0xe4dcc8, muted: 0x93a1a1, text: 0x657b83, isDark: false),
        .vercel: make(base: 0xfafafa, surface: 0xffffff, overlay: 0xeaeaea, muted: 0x666666, text: 0x171717, isDark: false),
        .vscodePlus: make(base: 0xffffff, surface: 0xf3f3f3, overlay: 0xe7e7e7, muted: 0x6a6a6a, text: 0x000000, isDark: false),
        .xcode: make(base: 0xffffff, surface: 0xf5f5f7, overlay: 0xe8e8ed, muted: 0x5d6c79, text: 0x1d1d1f, isDark: false),
    ]

    static let dark: [DarkTheme: ThemeDescriptor] = [
        .absolutely: make(base: 0x2d2d2b, surface: 0x373735, overlay: 0x424240, muted: 0xb2b2b0, text: 0xf9f9f7, isDark: true),
        .ayu: make(base: 0x0b0e14, surface: 0x0d1017, overlay: 0x11151c, muted: 0x6c7380, text: 0xbfbdb6, isDark: true),
        .catppuccin: make(base: 0x1e1e2e, surface: 0x313244, overlay: 0x45475a, muted: 0x6c7086, text: 0xcdd6f4, isDark: true),
        .codex: make(base: 0x111111, surface: 0x1a1a1a, overlay: 0x262626, muted: 0x8f8f8f, text: 0xfcfcfc, isDark: true),
        .dracula: make(base: 0x282a36, surface: 0x21222c, overlay: 0x44475a, muted: 0x6272a4, text: 0xf8f8f2, isDark: true),
        .everforest: make(base: 0x2d353b, surface: 0x343f44, overlay: 0x3d484d, muted: 0x859289, text: 0xd3c6aa, isDark: true),
        .github: make(base: 0x0d1117, surface: 0x161b22, overlay: 0x21262d, muted: 0x8b949e, text: 0xe6edf3, isDark: true),
        .gruvbox: make(base: 0x282828, surface: 0x3c3836, overlay: 0x504945, muted: 0x928374, text: 0xebdbb2, isDark: true),
        .linear: make(base: 0x0f0f11, surface: 0x17181d, overlay: 0x1c1e26, muted: 0x636b7b, text: 0xe6e9ef, isDark: true),
        .lobster: make(base: 0x111827, surface: 0x1a1d25, overlay: 0x1f2937, muted: 0x71717a, text: 0xe4e4e7, isDark: true),
        .material: make(base: 0x212121, surface: 0x2a2a2a, overlay: 0x353535, muted: 0x545454, text: 0xeeffff, isDark: true),
        .matrix: make(base: 0x040805, surface: 0x0a140c, overlay: 0x102016, muted: 0x3f8f52, text: 0xb8ffca, isDark: true),
        .monokai: make(base: 0x272822, surface: 0x1e1f1c, overlay: 0x3e3d32, muted: 0x75715e, text: 0xf8f8f2, isDark: true),
        .nightOwl: make(base: 0x011627, surface: 0x0b2942, overlay: 0x1d3b53, muted: 0x637777, text: 0xd6deeb, isDark: true),
        .nord: make(base: 0x2e3440, surface: 0x3b4252, overlay: 0x434c5e, muted: 0x4c566a, text: 0xeceff4, isDark: true),
        .notion: make(base: 0x191919, surface: 0x202020, overlay: 0x2c2c2c, muted: 0x9b9b9b, text: 0xd4d4d4, isDark: true),
        .one: make(base: 0x282c34, surface: 0x21252b, overlay: 0x3e4452, muted: 0x5c6370, text: 0xabb2bf, isDark: true),
        .oscurange: make(base: 0x0b0b0f, surface: 0x141419, overlay: 0x1c1c22, muted: 0x46474f, text: 0xe6e6e6, isDark: true),
        .raycast: make(base: 0x141414, surface: 0x1c1c1c, overlay: 0x272727, muted: 0xa1a1aa, text: 0xfafafa, isDark: true),
        .sentry: make(base: 0x2d2935, surface: 0x26222d, overlay: 0x3a3545, muted: 0x8d849f, text: 0xe6dff9, isDark: true),
        .solarized: make(base: 0x002b36, surface: 0x073642, overlay: 0x0a4450, muted: 0x586e75, text: 0x839496, isDark: true),
        .temple: make(base: 0x02120c, surface: 0x0c1f14, overlay: 0x1d2d0f, muted: 0x394d46, text: 0xc7e6da, isDark: true),
        .tokyoNight: make(base: 0x1a1b26, surface: 0x16161e, overlay: 0x24283b, muted: 0x565f89, text: 0xa9b1d6, isDark: true),
        .vercel: make(base: 0x000000, surface: 0x0a0a0a, overlay: 0x171717, muted: 0x888888, text: 0xededed, isDark: true),
        .vscodePlus: make(base: 0x1e1e1e, surface: 0x252526, overlay: 0x2d2d2d, muted: 0x858585, text: 0xd4d4d4, isDark: true),
        .xcode: make(base: 0x1f1f24, surface: 0x282830, overlay: 0x32323c, muted: 0x6c7986, text: 0xffffff, isDark: true),
    ]

    private static func make(
        base: UInt32, surface: UInt32, overlay: UInt32, muted: UInt32, text: UInt32,
        isDark: Bool
    ) -> ThemeDescriptor {
        let base = ThemeRGBComponents(hex: base)
        let surface = ThemeRGBComponents(hex: surface)
        let overlay = ThemeRGBComponents(hex: overlay)
        let muted = ThemeRGBComponents(hex: muted)
        let text = ThemeRGBComponents(hex: text)
        return ThemeDescriptor(
            pageBackground: .srgb(surface),
            pageForeground: .srgb(text),
            primaryText: .srgb(text),
            secondaryText: .srgb(muted.mixed(with: text, fraction: 0.5)),
            tertiaryText: .srgb(muted),
            readerBackdrop: .srgb(base),
            splitBackground: .srgb(base),
            paneBackground: .srgb(base),
            chromeDivider: .srgb(overlay),
            selectedChromeBackground: .srgb(overlay),
            chromeStroke: .srgb(muted),
            prefersFlatPDFChrome: true,
            highlightPalette: isDark ? .rosePineMoon : .normal,
            pdfStyle: isDark
                ? .darkPaper(background: surface, foreground: text, accentPreservation: 0.85)
                : .paper(background: surface)
        )
    }
}
