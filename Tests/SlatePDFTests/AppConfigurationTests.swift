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
        XCTAssertEqual(configuration.shortcuts.bindings[.removeHighlight], KeyboardShortcut(key: "d", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth]?.key, "0")
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "b", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "w", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.pageDown], KeyboardShortcut(key: "j", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.pageUp], KeyboardShortcut(key: "k", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.navigateBack], KeyboardShortcut(key: "[", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.navigateForward], KeyboardShortcut(key: "]", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.gotoPage], KeyboardShortcut(key: "g", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.zoomIn], KeyboardShortcut(key: "=", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.zoomOut], KeyboardShortcut(key: "-", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.undoLastHighlight], KeyboardShortcut(key: "z", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleRightSidebarMode], KeyboardShortcut(key: "l", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.swapSidebars], KeyboardShortcut(key: "x", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.layout.leftSidebarMinWidth, 36)
        XCTAssertFalse(configuration.layout.sidebarsSwapped)
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
        XCTAssertTrue(content.contains("remove_highlight = \"d\""))
        XCTAssertTrue(content.contains("page_down = \"j\""))
        XCTAssertTrue(content.contains("page_up = \"k\""))
        XCTAssertTrue(content.contains("navigate_back = \"command+[\""))
        XCTAssertTrue(content.contains("navigate_forward = \"command+]\""))
        XCTAssertTrue(content.contains("goto_page = \"command+option+g\""))
        XCTAssertTrue(content.contains("zoom_in = \"command+=\""))
        XCTAssertTrue(content.contains("zoom_out = \"command+-\""))
        XCTAssertTrue(content.contains("undo_last_highlight = \"command+z\""))
    }

    func testBootstrapMigratesLegacyRemoveHighlightShortcut() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "remove_highlight = \"d\"", with: "remove_highlight = \"command+shift+d\"")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.removeHighlight], KeyboardShortcut(key: "d", modifiers: []))
        XCTAssertTrue(persistedContent.contains("remove_highlight = \"d\""))
        XCTAssertFalse(persistedContent.contains("remove_highlight = \"command+shift+d\""))
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

    func testLegacyToggleLeftTabsModeMigratesToRightSidebarMode() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(
                of: "toggle_right_sidebar_mode = \"command+shift+l\"",
                with: "toggle_left_tabs_mode = \"command+shift+k\""
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(
            configuration.shortcuts.bindings[.toggleRightSidebarMode],
            KeyboardShortcut(key: "k", modifiers: [.command, .shift])
        )
        XCTAssertTrue(persistedContent.contains("toggle_right_sidebar_mode = \"command+shift+k\""))
        XCTAssertFalse(persistedContent.contains("toggle_left_tabs_mode"))
    }

    func testSidebarsSwappedPersistsAndRoundTrips() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        XCTAssertFalse(configuration.layout.sidebarsSwapped)
        configuration.layout.sidebarsSwapped = true

        try store.save(configuration)
        let reloadedConfiguration = try store.load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(reloadedConfiguration.layout.sidebarsSwapped)
        XCTAssertTrue(persistedContent.contains("sidebars_swapped = true"))
    }
}
