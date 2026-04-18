import Foundation
import XCTest
@testable import SlatePDF

final class AppConfigurationTests: XCTestCase {
    func testBootstrapCreatesDefaultTomlConfig() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        let store = try AppConfigurationStore(fileURL: fileURL)
        let configuration = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(configuration.reader.defaultDisplayMode, .singlePageContinuous)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "a", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.exitHighlightMode], KeyboardShortcut(key: "escape", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleNightMode], KeyboardShortcut(key: "i", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.saveAnnotations], KeyboardShortcut(key: "s", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth]?.key, "0")
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "b", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "w", modifiers: [.command]))
    }

    func testLoadTomlOverridesReaderDefaultsAndShortcuts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try """
[reader]
default_display_mode = "two_up"
fit_width_on_open = false

[shortcuts]
highlight_selection = "h"
exit_highlight_mode = "escape"
toggle_night_mode = "n"
save_annotations = "command+shift+s"
toggle_left_sidebar = "command+shift+l"
close_current_tab = "command+e"
fit_width = "command+shift+9"
previous_tab = "command+["
two_up = "command+option+8"
""".write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()

        XCTAssertEqual(configuration.reader.defaultDisplayMode, .twoUp)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "h", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.exitHighlightMode], KeyboardShortcut(key: "escape", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleNightMode], KeyboardShortcut(key: "n", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.saveAnnotations], KeyboardShortcut(key: "s", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "l", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "e", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth], KeyboardShortcut(key: "9", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.previousTab], KeyboardShortcut(key: "[", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.twoUp], KeyboardShortcut(key: "8", modifiers: [.command, .option]))
    }

    func testExistingConfigGetsMissingShortcutKeysBackfilled() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try """
[reader]
default_display_mode = "single_page"
fit_width_on_open = false

[shortcuts]
fit_width = "command+9"
""".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try AppConfigurationStore(fileURL: fileURL)
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(content.contains("highlight_selection = \"a\""))
        XCTAssertTrue(content.contains("exit_highlight_mode = \"escape\""))
        XCTAssertTrue(content.contains("toggle_night_mode = \"i\""))
        XCTAssertTrue(content.contains("save_annotations = \"command+s\""))
        XCTAssertTrue(content.contains("toggle_left_sidebar = \"command+b\""))
        XCTAssertTrue(content.contains("close_current_tab = \"command+w\""))
        XCTAssertTrue(content.contains("fit_width = \"command+9\""))
    }

    func testSavePersistsUpdatedReaderAndAnnotationDefaults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        configuration.reader.defaultDisplayMode = .twoUpContinuous
        configuration.reader.fitWidthOnOpen = true
        configuration.annotations.autoSavePolicy = .never

        try store.save(configuration)
        let reloadedConfiguration = try store.load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(reloadedConfiguration.reader.defaultDisplayMode, .twoUpContinuous)
        XCTAssertTrue(reloadedConfiguration.reader.fitWidthOnOpen)
        XCTAssertEqual(reloadedConfiguration.annotations.autoSavePolicy, .never)
        XCTAssertTrue(persistedContent.contains("default_display_mode = \"two_up_continuous\""))
        XCTAssertTrue(persistedContent.contains("fit_width_on_open = true"))
        XCTAssertTrue(persistedContent.contains("auto_save = \"never\""))
    }
}
