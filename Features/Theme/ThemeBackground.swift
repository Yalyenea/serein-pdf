import AppKit

extension ThemeDescriptor {
    func applying(_ overrides: ThemeBackgroundOverrides, appearance: NSAppearance.Name) -> Self {
        guard overrides != ThemeBackgroundOverrides() else { return self }
        let resolvedAppearance = NSAppearance(named: appearance)!
        func components(_ recipe: ThemeColorRecipe) -> ThemeRGBComponents {
            let color = recipe.resolve(for: resolvedAppearance).usingColorSpace(.sRGB)!
            return ThemeRGBComponents(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
        }

        var pageBackground = self.pageBackground
        var pageForeground = self.pageForeground
        var pdfStyle = self.pdfStyle
        if let page = overrides.page?.components {
            pageBackground = .srgb(page)
            if page.luminance > 0.179 {
                pageForeground = .semantic(.black)
                pdfStyle = .paper(background: page)
            } else {
                let text = page.contrastingText(preferred: components(self.pageForeground))
                pageForeground = .srgb(text)
                pdfStyle = .darkPaper(background: page, foreground: text, accentPreservation: 0.85)
            }
        }

        let window = overrides.window?.components
        let text = window?.contrastingText(preferred: components(primaryText)) ?? components(primaryText)
        return Self(
            pageBackground: pageBackground,
            pageForeground: pageForeground,
            primaryText: window.map { _ in .srgb(text) } ?? primaryText,
            secondaryText: window.map { .srgb($0.mixed(with: text, fraction: 0.78)) } ?? secondaryText,
            tertiaryText: window.map { .srgb($0.mixed(with: text, fraction: 0.6)) } ?? tertiaryText,
            readerBackdrop: window.map { .srgb($0) } ?? readerBackdrop,
            splitBackground: window.map { .srgb($0) } ?? splitBackground,
            paneBackground: window.map { .srgb($0) } ?? paneBackground,
            chromeDivider: window.map { .srgb($0.mixed(with: text, fraction: 0.12)) } ?? chromeDivider,
            selectedChromeBackground: window.map { .srgb($0.mixed(with: text, fraction: 0.12)) } ?? selectedChromeBackground,
            chromeStroke: window.map { .srgb($0.mixed(with: text, fraction: 0.25)) } ?? chromeStroke,
            prefersFlatPDFChrome: true,
            highlightPalette: highlightPalette,
            pdfStyle: pdfStyle
        )
    }
}
