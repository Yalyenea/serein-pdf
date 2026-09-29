import AppKit
import XCTest
@testable import Serein

@MainActor
final class LocalizationTests: XCTestCase {
    func testAutomaticLanguageUsesSystemPreferenceAndExplicitChoiceWins() {
        XCTAssertEqual(AppLanguage.automatic.resolved(preferredLanguages: ["zh-Hans-CN", "en"]), .chinese)
        XCTAssertEqual(AppLanguage.automatic.resolved(preferredLanguages: ["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.automatic.resolved(preferredLanguages: ["en-US", "zh"]), .english)
        XCTAssertEqual(AppLanguage.automatic.resolved(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.automatic.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh"]), .english)
        XCTAssertEqual(AppLanguage.chinese.resolved(preferredLanguages: ["en"]), .chinese)
    }

    func testLanguageConfigurationRoundTripAndInvalidValue() throws {
        for language in AppLanguage.allCases {
            var configuration = AppConfiguration.default
            configuration.language = language
            XCTAssertEqual(try AppConfigurationParser().parse(AppConfigurationFile.render(configuration)), configuration)
        }
        XCTAssertEqual(try AppConfigurationParser().parse("[appearance]\nmode = \"system\"").language, .automatic)
        XCTAssertThrowsError(try AppConfigurationParser().parse("[appearance]\nlanguage = \"fr\""))
    }

    func testSettingsOffersPersistedLanguageChoiceInBothLanguages() throws {
        defer { L10n.configure(.english) }
        for language in [AppLanguage.english, .chinese] {
            L10n.configure(language)
            var configuration = AppConfiguration.default
            configuration.language = language
            var saved: AppConfiguration?
            let controller = SettingsWindowController(configuration: configuration) { saved = $0 }
            defer { controller.close() }
            let window = try XCTUnwrap(controller.window)
            controller.showWindow(nil)
            window.displayIfNeeded()
            XCTAssertEqual(window.title, language == .chinese ? "设置" : "Settings")
            var views = [try XCTUnwrap(window.contentView)]
            var popup: NSPopUpButton?
            while let view = views.popLast() {
                if view.identifier?.rawValue == "languagePopUp" { popup = view as? NSPopUpButton }
                views.append(contentsOf: view.subviews)
            }
            let control = try XCTUnwrap(popup)
            XCTAssertEqual(control.itemTitles, [language == .chinese ? "自动" : "Automatic", "English", "中文"])
            XCTAssertEqual(control.selectedItem?.representedObject as? String, language.rawValue)
            control.selectItem(at: 0)
            _ = control.target?.perform(try XCTUnwrap(control.action), with: control)
            XCTAssertEqual(saved?.language, .automatic)
            if let directory = ProcessInfo.processInfo.environment["SEREIN_TRANSLATION_PREVIEW"],
               let view = window.contentView {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-\(language.rawValue).png"))
            }
        }
    }
}
