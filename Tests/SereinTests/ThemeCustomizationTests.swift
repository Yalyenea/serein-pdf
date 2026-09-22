import AppKit
import Foundation
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ThemeCustomizationTests {
    @Test
    func hexColorsRequireSixASCIIHexDigitsAndNormalizeCase() throws {
        let color = try #require(ThemeHexColor(hex: "#A1b2C3"))
        #expect(color.hexString == "#a1b2c3")
        #expect(color.components == ThemeRGBComponents(hex: 0xa1b2c3))
        #expect(ThemeHexColor(hex: "#000000")?.components == ThemeRGBComponents(hex: 0x000000))
        #expect(ThemeHexColor(hex: "#FFFFFF")?.hexString == "#ffffff")

        for invalid in ["", "a1b2c3", "#fff", "#12345678", "#gg0000", " #123456", "#123456 ", "#１２３４５６"] {
            #expect(ThemeHexColor(hex: invalid) == nil, "Accepted invalid color: \(invalid)")
        }
    }

    @Test
    func everyThemeRoundTripsThroughTOMLAndParticipatesInTheCycle() throws {
        #expect(LightTheme.allCases.count == 17)
        #expect(DarkTheme.allCases.count == 28)
        #expect(Set(ThemeRegistry.lightThemes.keys) == Set(LightTheme.allCases))
        #expect(Set(ThemeRegistry.darkThemes.keys) == Set(DarkTheme.allCases))

        var configuration = AppConfiguration.default
        var nextLight = LightTheme.allCases[0]
        for theme in LightTheme.allCases {
            #expect(nextLight == theme)
            nextLight = nextLight.toggled
            configuration.appearance.lightTheme = theme
            let restored = try AppConfigurationParser().parse(AppConfigurationFile.render(configuration))
            #expect(restored == configuration)
        }
        #expect(nextLight == LightTheme.allCases[0])

        var nextDark = DarkTheme.allCases[0]
        for theme in DarkTheme.allCases {
            #expect(nextDark == theme)
            nextDark = nextDark.toggled
            configuration.appearance.darkTheme = theme
            let restored = try AppConfigurationParser().parse(AppConfigurationFile.render(configuration))
            #expect(restored == configuration)
        }
        #expect(nextDark == DarkTheme.allCases[0])
    }

    @Test
    func customBackgroundsPersistIndependentlyAndCanBeCleared() throws {
        let root = try TestPDFFixtures.makeRootDirectory(prefix: "theme-background-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)
        var configuration = AppConfiguration.default
        configuration.appearance.lightTheme = .everforest
        configuration.appearance.darkTheme = .catppuccin
        configuration.appearance.lightBackground = ThemeBackgroundOverrides(
            page: ThemeHexColor(hex: "#FAEEDD"),
            window: ThemeHexColor(hex: "#DDDDEE")
        )
        configuration.appearance.darkBackground = ThemeBackgroundOverrides(
            page: ThemeHexColor(hex: "#121827"),
            window: ThemeHexColor(hex: "#242131")
        )
        try store.save(configuration)

        #expect(try AppConfigurationStore(fileURL: fileURL).load() == configuration)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("light_page_background = \"#faeedd\""))
        #expect(content.contains("light_window_background = \"#ddddee\""))
        #expect(content.contains("dark_page_background = \"#121827\""))
        #expect(content.contains("dark_window_background = \"#242131\""))

        configuration.appearance.lightBackground = .init()
        try store.save(configuration)
        let cleared = try AppConfigurationStore(fileURL: fileURL).load()
        #expect(cleared == configuration)
        #expect(cleared.appearance.lightBackground == ThemeBackgroundOverrides())
        #expect(cleared.appearance.darkBackground.page?.hexString == "#121827")
        #expect(cleared.appearance.darkBackground.window?.hexString == "#242131")
        let clearedContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(clearedContent.contains("light_page_background = \"\""))
        #expect(clearedContent.contains("light_window_background = \"\""))
    }

    @Test
    func existingThemeConfigurationGainsEmptyOverridesWithoutChangingSelections() throws {
        let root = try TestPDFFixtures.makeRootDirectory(prefix: "theme-background-migration")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("config.toml")
        try """
        [appearance]
        mode = "dark"
        light_theme = "rose_pine_dawn"
        dark_theme = "normal"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try AppConfigurationStore(fileURL: fileURL).load()
        #expect(loaded.appearance.mode == .dark)
        #expect(loaded.appearance.lightTheme == .rosePineDawn)
        #expect(loaded.appearance.darkTheme == .normal)
        #expect(loaded.appearance.lightBackground == ThemeBackgroundOverrides())
        #expect(loaded.appearance.darkBackground == ThemeBackgroundOverrides())
        let rewritten = try String(contentsOf: fileURL, encoding: .utf8)
        for key in backgroundKeys {
            #expect(rewritten.contains("\(key) = \"\""))
        }
        #expect(try AppConfigurationStore(fileURL: fileURL).load() == loaded)
    }

    @Test
    func invalidBackgroundValuesAreRejectedForEveryConfigurationKey() throws {
        for key in backgroundKeys {
            for value in ["#fff", "123456", "#12345g", "#12345678", " #123456"] {
                #expect(throws: (any Error).self) {
                    try AppConfigurationParser().parse("[appearance]\n\(key) = \"\(value)\"")
                }
            }
            let cleared = try AppConfigurationParser().parse("[appearance]\n\(key) = \"\"")
            #expect(cleared.appearance.lightBackground == ThemeBackgroundOverrides())
            #expect(cleared.appearance.darkBackground == ThemeBackgroundOverrides())
        }
    }

    @Test
    func invalidPersistedColorIsReportedWithoutRewritingTheFile() throws {
        let root = try TestPDFFixtures.makeRootDirectory(prefix: "theme-background-invalid")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("config.toml")
        let invalid = "[appearance]\nlight_page_background = \"#notrgb\"\n"
        try invalid.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try AppConfigurationStore(fileURL: fileURL).load()
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == invalid)
    }

    @Test
    func settingsMenusExposeAllThemeVariantsWithTheirStableIDs() throws {
        _ = NSApplication.shared
        let controller = SettingsWindowController(configuration: .default) { _ in }
        defer { controller.close() }
        let content = try #require(controller.window?.contentView)
        let light: NSPopUpButton = try control("lightThemePopUp", in: content)
        let dark: NSPopUpButton = try control("darkThemePopUp", in: content)

        #expect(light.itemArray.compactMap { $0.representedObject as? String } == LightTheme.allCases.map(\.rawValue))
        #expect(dark.itemArray.compactMap { $0.representedObject as? String } == DarkTheme.allCases.map(\.rawValue))
        #expect(light.selectedItem?.representedObject as? String == LightTheme.normal.rawValue)
        #expect(dark.selectedItem?.representedObject as? String == DarkTheme.rosePineMoon.rawValue)

        controller.showWindow(nil)
        light.selectItem(withTitle: try #require(LightTheme.allCases.map(\.menuTitle).max { $0.count < $1.count }))
        dark.selectItem(withTitle: try #require(DarkTheme.allCases.map(\.menuTitle).max { $0.count < $1.count }))
        let window = try #require(controller.window)
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        #expect(abs(content.bounds.width - 680) < 1)
        for identifier in [
            "lightThemePopUp", "darkThemePopUp", "lightPageBackground", "lightWindowBackground",
            "darkPageBackground", "darkWindowBackground", "resetLightBackground", "resetDarkBackground",
        ] {
            let view: NSControl = try control(identifier, in: content)
            let frame = view.convert(view.bounds, to: content)
            #expect(frame.width > 0, "Control has no width: \(identifier)")
            #expect(frame.minX >= 0, "Control crosses the leading edge: \(identifier)")
            #expect(frame.maxX <= content.bounds.maxX, "Control crosses the trailing edge: \(identifier)")
        }
    }

    @Test
    func settingsActionsKeepBackgroundsAcrossThemeChangesAndResetEachAppearance() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        var publications = 0
        var controller: SettingsWindowController!
        controller = SettingsWindowController(configuration: configuration) { updated in
            configuration = updated
            publications += 1
            controller.sync(configuration: updated)
        }
        defer {
            controller.close()
            controller = nil
        }
        let content = try #require(controller.window?.contentView)
        let lightPage: NSColorWell = try control("lightPageBackground", in: content)
        let lightWindow: NSColorWell = try control("lightWindowBackground", in: content)
        let darkPage: NSColorWell = try control("darkPageBackground", in: content)
        let darkWindow: NSColorWell = try control("darkWindowBackground", in: content)
        let resetLight: NSButton = try control("resetLightBackground", in: content)
        let resetDark: NSButton = try control("resetDarkBackground", in: content)
        #expect(resetLight.isEnabled == false)
        #expect(resetDark.isEnabled == false)

        lightPage.color = NSColor(srgbRed: 1, green: 0.8, blue: 0.6, alpha: 1)
        try sendAction(lightPage)
        #expect(configuration.appearance.lightBackground.page?.hexString == "#ffcc99")
        #expect(configuration.appearance.lightBackground.window == nil)
        #expect(configuration.appearance.darkBackground == ThemeBackgroundOverrides())
        #expect(resetLight.isEnabled)
        #expect(resetDark.isEnabled == false)

        lightWindow.color = NSColor(srgbRed: 0.8, green: 0.8, blue: 1, alpha: 1)
        try sendAction(lightWindow)
        darkPage.color = NSColor(srgbRed: 0.2, green: 0.2, blue: 0.4, alpha: 1)
        try sendAction(darkPage)
        darkWindow.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.2, alpha: 1)
        try sendAction(darkWindow)
        #expect(configuration.appearance.lightBackground.window?.hexString == "#ccccff")
        #expect(configuration.appearance.darkBackground.page?.hexString == "#333366")
        #expect(configuration.appearance.darkBackground.window?.hexString == "#336633")
        let lightBackground = configuration.appearance.lightBackground
        let darkBackground = configuration.appearance.darkBackground

        let lightThemes: NSPopUpButton = try control("lightThemePopUp", in: content)
        try select(LightTheme.everforest.rawValue, in: lightThemes)
        let darkThemes: NSPopUpButton = try control("darkThemePopUp", in: content)
        try select(DarkTheme.catppuccin.rawValue, in: darkThemes)
        #expect(configuration.appearance.lightTheme == .everforest)
        #expect(configuration.appearance.darkTheme == .catppuccin)
        #expect(configuration.appearance.lightBackground == lightBackground)
        #expect(configuration.appearance.darkBackground == darkBackground)
        #expect(ThemeHexColor(color: lightPage.color) == lightBackground.page)
        #expect(ThemeHexColor(color: darkWindow.color) == darkBackground.window)

        let defaults = ThemeRegistry.snapshot(for: ThemeSelection(light: .everforest, dark: .catppuccin))
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))

        try sendAction(resetLight)
        #expect(configuration.appearance.lightBackground == ThemeBackgroundOverrides())
        #expect(configuration.appearance.darkBackground == darkBackground)
        #expect(configuration.appearance.lightTheme == .everforest)
        #expect(resetLight.isEnabled == false)
        #expect(resetDark.isEnabled)
        #expect(ThemeHexColor(color: lightPage.color) == ThemeHexColor(
            color: defaults.light.color(for: .pageBackground, appearance: lightAppearance)
        ))
        #expect(ThemeHexColor(color: lightWindow.color) == ThemeHexColor(
            color: defaults.light.color(for: .readerBackdrop, appearance: lightAppearance)
        ))
        #expect(ThemeHexColor(color: darkPage.color) == darkBackground.page)
        #expect(ThemeHexColor(color: darkWindow.color) == darkBackground.window)

        try sendAction(resetDark)
        #expect(configuration.appearance.darkBackground == ThemeBackgroundOverrides())
        #expect(configuration.appearance.darkTheme == .catppuccin)
        #expect(resetDark.isEnabled == false)
        #expect(ThemeHexColor(color: darkPage.color) == ThemeHexColor(
            color: defaults.dark.color(for: .pageBackground, appearance: darkAppearance)
        ))
        #expect(ThemeHexColor(color: darkWindow.color) == ThemeHexColor(
            color: defaults.dark.color(for: .readerBackdrop, appearance: darkAppearance)
        ))
        #expect(publications == 8)
    }

    private var backgroundKeys: [String] {
        ["light_page_background", "light_window_background", "dark_page_background", "dark_window_background"]
    }

    private func control<T: NSControl>(_ identifier: String, in root: NSView) throws -> T {
        var pending = [root]
        while let view = pending.popLast() {
            if view.identifier?.rawValue == identifier, let control = view as? T {
                return control
            }
            pending.append(contentsOf: view.subviews)
        }
        throw CocoaError(.coderValueNotFound)
    }

    private func sendAction(_ control: NSControl) throws {
        let action = try #require(control.action)
        let target = try #require(control.target)
        #expect(control.sendAction(action, to: target))
    }

    private func select(_ rawValue: String, in popUp: NSPopUpButton) throws {
        let item = try #require(popUp.itemArray.first { ($0.representedObject as? String) == rawValue })
        popUp.select(item)
        try sendAction(popUp)
    }
}
