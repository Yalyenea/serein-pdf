import Foundation
import XCTest
@testable import Serein

final class AppConfigurationTests: XCTestCase {
    func testBootstrapCreatesDefaultTomlConfig() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        let store = try AppConfigurationStore(fileURL: fileURL)
        let configuration = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(configuration.appearance.mode, .system)
        XCTAssertEqual(configuration.appearance.lightTheme, .normal)
        XCTAssertEqual(configuration.appearance.darkTheme, .rosePineMoon)
        XCTAssertEqual(configuration.reader.defaultDisplayMode, .singlePageContinuous)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.library.folderURLs, [])
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "a", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.exitHighlightMode], KeyboardShortcut(key: "escape", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleNightMode], KeyboardShortcut(key: "i", modifiers: []))
        XCTAssertNil(configuration.shortcuts.bindings[.switchCurrentTheme])
        XCTAssertNil(configuration.shortcuts.bindings[.openLibraryPDF])
        XCTAssertEqual(configuration.shortcuts.bindings[.saveAnnotations], KeyboardShortcut(key: "s", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.copyHighlightsMarkdown], KeyboardShortcut(key: "e", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.removeHighlight], KeyboardShortcut(key: "d", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth]?.key, "0")
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "b", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "w", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightColorGreen], KeyboardShortcut(key: "g", modifiers: [.command, .control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.pageDown], KeyboardShortcut(key: "j", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.pageUp], KeyboardShortcut(key: "k", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.halfPageDown], KeyboardShortcut(key: "d", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.halfPageUp], KeyboardShortcut(key: "u", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.goToFirstPage], KeyboardShortcut(key: "g", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.goToLastPage], KeyboardShortcut(key: "g", modifiers: [.shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.navigateBack], KeyboardShortcut(key: "[", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.navigateForward], KeyboardShortcut(key: "]", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findAllOpen], KeyboardShortcut(key: "f", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findNextMatch], KeyboardShortcut(key: "g", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findPreviousMatch], KeyboardShortcut(key: "g", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.gotoPage], KeyboardShortcut(key: "g", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showRecentFilesPalette], KeyboardShortcut(key: "space", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showAllTabs], KeyboardShortcut(key: "tab", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleContinuousReading], KeyboardShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openContainingFolder], KeyboardShortcut(key: "r", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitHeight], KeyboardShortcut(key: "9", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.zoomIn], KeyboardShortcut(key: "=", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.zoomOut], KeyboardShortcut(key: "-", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.undoLastHighlight], KeyboardShortcut(key: "z", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.redoLastHighlight], KeyboardShortcut(key: "z", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleDemoMode], KeyboardShortcut(key: "l", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleImmersiveMode], KeyboardShortcut(key: "l", modifiers: [.command, .control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleRightSidebarMode], KeyboardShortcut(key: "l", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.swapSidebars], KeyboardShortcut(key: "x", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.layout.leftSidebarMinWidth, 36)
        XCTAssertFalse(configuration.layout.sidebarsSwapped)
        XCTAssertTrue(configuration.layout.showRecentFilesInSidebar)
    }

    func testLoadTomlOverridesReaderDefaultsAndShortcuts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try """
[appearance]
mode = "light"
light_theme = "rose_pine_dawn"
dark_theme = "normal"

[reader]
default_display_mode = "two_up"
fit_width_on_open = false

[shortcuts]
highlight_selection = "h"
exit_highlight_mode = "escape"
toggle_night_mode = "n"
switch_current_theme = "command+option+t"
save_annotations = "command+shift+s"
toggle_left_sidebar = "command+shift+l"
close_current_tab = "command+e"
fit_width = "command+shift+9"
fit_height = "command+shift+8"
previous_tab = "command+["
two_up = "command+option+8"
half_page_down = "control+f"
go_to_last_page = "shift+l"
find_previous_match = "shift+n"
show_recent_files_palette = "command+space"
show_all_tabs = "control+tab"
toggle_continuous_reading = "command+option+c"
open_containing_folder = "command+option+r"
find_all_open = "command+option+f"

[layout]
show_recent_files_in_sidebar = false

[library]
folders = ["/tmp/Books", "/tmp/Papers"]

[shortcuts]
open_library_pdf = "command+option+o"
""".write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()

        XCTAssertEqual(configuration.appearance.mode, .light)
        XCTAssertEqual(configuration.appearance.lightTheme, .rosePineDawn)
        XCTAssertEqual(configuration.appearance.darkTheme, .normal)
        XCTAssertEqual(configuration.reader.defaultDisplayMode, .twoUp)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "h", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.exitHighlightMode], KeyboardShortcut(key: "escape", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleNightMode], KeyboardShortcut(key: "n", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.switchCurrentTheme], KeyboardShortcut(key: "t", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openLibraryPDF], KeyboardShortcut(key: "o", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.saveAnnotations], KeyboardShortcut(key: "s", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "l", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "e", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth], KeyboardShortcut(key: "9", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitHeight], KeyboardShortcut(key: "8", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.previousTab], KeyboardShortcut(key: "[", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.twoUp], KeyboardShortcut(key: "8", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.halfPageDown], KeyboardShortcut(key: "f", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.goToLastPage], KeyboardShortcut(key: "l", modifiers: [.shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findPreviousMatch], KeyboardShortcut(key: "n", modifiers: [.shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showRecentFilesPalette], KeyboardShortcut(key: "space", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showAllTabs], KeyboardShortcut(key: "tab", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleContinuousReading], KeyboardShortcut(key: "c", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openContainingFolder], KeyboardShortcut(key: "r", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findAllOpen], KeyboardShortcut(key: "f", modifiers: [.command, .option]))
        XCTAssertFalse(configuration.layout.showRecentFilesInSidebar)
        XCTAssertEqual(
            configuration.library.folderURLs.map(\.path),
            ["/tmp/Books", "/tmp/Papers"]
        )
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

        XCTAssertTrue(content.contains("[appearance]"))
        XCTAssertTrue(content.contains("mode = \"system\""))
        XCTAssertTrue(content.contains("light_theme = \"normal\""))
        XCTAssertTrue(content.contains("dark_theme = \"rose_pine_moon\""))
        XCTAssertTrue(content.contains("highlight_selection = \"a\""))
        XCTAssertTrue(content.contains("exit_highlight_mode = \"escape\""))
        XCTAssertTrue(content.contains("toggle_night_mode = \"i\""))
        XCTAssertTrue(content.contains("switch_current_theme = \"none\""))
        XCTAssertTrue(content.contains("open_library_pdf = \"none\""))
        XCTAssertTrue(content.contains("save_annotations = \"command+s\""))
        XCTAssertTrue(content.contains("copy_highlights_markdown = \"command+shift+e\""))
        XCTAssertTrue(content.contains("toggle_left_sidebar = \"command+b\""))
        XCTAssertTrue(content.contains("close_current_tab = \"command+w\""))
        XCTAssertTrue(content.contains("fit_height = \"command+9\""))
        XCTAssertTrue(content.contains("fit_width = \"command+9\""))
        XCTAssertTrue(content.contains("remove_highlight = \"d\""))
        XCTAssertTrue(content.contains("page_down = \"j\""))
        XCTAssertTrue(content.contains("page_up = \"k\""))
        XCTAssertTrue(content.contains("half_page_down = \"control+d\""))
        XCTAssertTrue(content.contains("half_page_up = \"control+u\""))
        XCTAssertTrue(content.contains("go_to_first_page = \"g\""))
        XCTAssertTrue(content.contains("go_to_last_page = \"shift+g\""))
        XCTAssertTrue(content.contains("navigate_back = \"command+[\""))
        XCTAssertTrue(content.contains("navigate_forward = \"command+]\""))
        XCTAssertTrue(content.contains("find_all_open = \"command+shift+f\""))
        XCTAssertTrue(content.contains("find_next_match = \"command+g\""))
        XCTAssertTrue(content.contains("find_previous_match = \"command+shift+g\""))
        XCTAssertTrue(content.contains("goto_page = \"command+option+g\""))
        XCTAssertTrue(content.contains("show_recent_files_palette = \"command+shift+space\""))
        XCTAssertTrue(content.contains("show_all_tabs = \"control+tab\""))
        XCTAssertTrue(content.contains("toggle_continuous_reading = \"command+shift+c\""))
        XCTAssertTrue(content.contains("open_containing_folder = \"command+r\""))
        XCTAssertTrue(content.contains("zoom_in = \"command+=\""))
        XCTAssertTrue(content.contains("zoom_out = \"command+-\""))
        XCTAssertTrue(content.contains("undo_last_highlight = \"command+z\""))
        XCTAssertTrue(content.contains("redo_last_highlight = \"command+shift+z\""))
        XCTAssertTrue(content.contains("toggle_demo_mode = \"command+l\""))
        XCTAssertTrue(content.contains("toggle_immersive_mode = \"command+control+l\""))
        XCTAssertTrue(content.contains("show_recent_files_in_sidebar = true"))
        XCTAssertTrue(content.contains("[library]"))
        XCTAssertTrue(content.contains("folders = []"))
    }

    func testLegacyGreenShortcutMigratesAwayFromFindPreviousConflict() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "highlight_color_green = \"command+control+g\"", with: "highlight_color_green = \"command+shift+g\"")
            .replacingOccurrences(of: "find_previous_match = \"command+shift+g\"\n", with: "")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.highlightColorGreen], KeyboardShortcut(key: "g", modifiers: [.command, .control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findPreviousMatch], KeyboardShortcut(key: "g", modifiers: [.command, .shift]))
        XCTAssertTrue(persistedContent.contains("highlight_color_green = \"command+control+g\""))
        XCTAssertTrue(persistedContent.contains("find_previous_match = \"command+shift+g\""))
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

    func testBootstrapMigratesLegacyImmersiveModeShortcut() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(
                of: "toggle_immersive_mode = \"command+control+l\"",
                with: "toggle_immersive_mode = \"command+option+l\""
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.toggleImmersiveMode], KeyboardShortcut(key: "l", modifiers: [.command, .control]))
        XCTAssertTrue(persistedContent.contains("toggle_immersive_mode = \"command+control+l\""))
        XCTAssertFalse(persistedContent.contains("toggle_immersive_mode = \"command+option+l\""))
    }

    func testBootstrapMigratesLegacyShowAllTabsShortcut() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(
                of: "show_all_tabs = \"control+tab\"",
                with: "show_all_tabs = \"command+option+t\""
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.showAllTabs], KeyboardShortcut(key: "tab", modifiers: [.control]))
        XCTAssertTrue(persistedContent.contains("show_all_tabs = \"control+tab\""))
        XCTAssertFalse(persistedContent.contains("show_all_tabs = \"command+option+t\""))
    }

    func testSavePersistsUpdatedReaderAndAnnotationDefaults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        configuration.appearance.mode = .dark
        configuration.appearance.lightTheme = .rosePineDawn
        configuration.appearance.darkTheme = .normal
        configuration.reader.defaultDisplayMode = .twoUpContinuous
        configuration.reader.fitWidthOnOpen = true
        configuration.annotations.autoSavePolicy = .never
        configuration.library.folderURLs = [
            URL(fileURLWithPath: "/tmp/Books"),
            URL(fileURLWithPath: "/tmp/Papers"),
        ]

        try store.save(configuration)
        let reloadedConfiguration = try store.load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(reloadedConfiguration.appearance.mode, .dark)
        XCTAssertEqual(reloadedConfiguration.appearance.lightTheme, .rosePineDawn)
        XCTAssertEqual(reloadedConfiguration.appearance.darkTheme, .normal)
        XCTAssertEqual(reloadedConfiguration.reader.defaultDisplayMode, .twoUpContinuous)
        XCTAssertTrue(reloadedConfiguration.reader.fitWidthOnOpen)
        XCTAssertEqual(reloadedConfiguration.annotations.autoSavePolicy, .never)
        XCTAssertEqual(reloadedConfiguration.library.folderURLs.map(\.path), ["/tmp/Books", "/tmp/Papers"])
        XCTAssertTrue(persistedContent.contains("mode = \"dark\""))
        XCTAssertTrue(persistedContent.contains("light_theme = \"rose_pine_dawn\""))
        XCTAssertTrue(persistedContent.contains("dark_theme = \"normal\""))
        XCTAssertTrue(persistedContent.contains("default_display_mode = \"two_up_continuous\""))
        XCTAssertTrue(persistedContent.contains("fit_width_on_open = true"))
        XCTAssertTrue(persistedContent.contains("auto_save = \"never\""))
        XCTAssertTrue(persistedContent.contains("folders = [\"/tmp/Books\", \"/tmp/Papers\"]"))
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

    func testClearedShortcutPersistsAsNone() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        configuration.shortcuts.bindings[.copyHighlightsMarkdown] = nil

        try store.save(configuration)
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)
        let reloaded = try store.load()

        XCTAssertTrue(persistedContent.contains("copy_highlights_markdown = \"none\""))
        XCTAssertNil(reloaded.shortcuts.bindings[.copyHighlightsMarkdown])
    }
}
