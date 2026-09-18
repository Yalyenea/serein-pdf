import Foundation
import XCTest
@testable import Serein

final class AppConfigurationTests: XCTestCase {
    func testPlusShortcutsRoundTripWithoutConfusingModifierSeparator() throws {
        let modifiers: [Set<KeyboardShortcutModifier>] = [[], [.command], [.shift], [.command, .shift]]
        for flags in modifiers {
            let shortcut = KeyboardShortcut(key: "+", modifiers: flags)
            XCTAssertTrue(shortcut.serializedValue.hasSuffix("plus"))
            XCTAssertEqual(try KeyboardShortcut.parse(shortcut.serializedValue), shortcut)
        }
    }

    func testBootstrapCreatesDefaultTomlConfig() throws {
        try withTemporaryConfigRoot(self) { rootURL in
            let fileURL = rootURL.appendingPathComponent("config.toml")
            let store = try AppConfigurationStore(fileURL: fileURL)
            let configuration = try store.load()

            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            // Full default surface: laundry-list key checks live in
            // testConfigKeyListsStayInSyncAndMissingKeysSelfHeal.
            XCTAssertEqual(configuration, .default)
            XCTAssertEqual(
                configuration.shortcuts.bindings[.fitTextWidth],
                KeyboardShortcut(key: "0", modifiers: [.command, .option])
            )
            XCTAssertEqual(configuration.layout.floatingOutlineHeight, 360, accuracy: 0.001)
            XCTAssertEqual(
                configuration.shortcuts.bindings[.copyCurrentPageAsImage],
                KeyboardShortcut(key: "c", modifiers: [.command, .option])
            )
            XCTAssertEqual(
                configuration.shortcuts.bindings[.toggleDisplayModeContinuity],
                KeyboardShortcut(key: "c", modifiers: [])
            )
            XCTAssertEqual(
                configuration.shortcuts.bindings[.addComment],
                KeyboardShortcut(key: "m", modifiers: [])
            )
            XCTAssertTrue(configuration.integrations.codexEnabled)
            XCTAssertEqual(
                configuration.shortcuts.bindings[.sendContextToCodex],
                KeyboardShortcut(key: "c", modifiers: [.command, .control])
            )
            XCTAssertEqual(
                configuration.shortcuts.bindings[.sendCurrentPDFToCodex],
                KeyboardShortcut(key: "c", modifiers: [.command, .control, .shift])
            )
        }
    }

    func testKeyboardShortcutRejectsRawControlCharacters() {
        XCTAssertFalse(KeyboardShortcut.isSupportedKeyToken("\r"))
        XCTAssertFalse(KeyboardShortcut.isSupportedKeyToken("\n"))
        XCTAssertFalse(KeyboardShortcut.isSupportedKeyToken("\u{7f}"))
        XCTAssertTrue(KeyboardShortcut.isSupportedKeyToken("tab"))
        XCTAssertTrue(KeyboardShortcut.isSupportedKeyToken("escape"))
    }

    func testParserRejectsReservedCommandPaletteShortcut() {
        XCTAssertThrowsError(
            try AppConfigurationParser().parse(
                "[shortcuts]\nopen_library_pdf = \"command+k\""
            )
        ) { error in
            guard case AppConfigurationError.invalidShortcut("command+k") = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testLoadTomlOverridesReaderDefaultsAndShortcuts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try """
[appearance]
mode = "light"
light_theme = "rose_pine_dawn"
dark_theme = "normal"

[reader]
default_display_mode = "two_up"
fit_width_on_open = false
reading_focus_width = "column"
reading_focus_custom_width = 0.64
reading_focus_height = 112

[integrations]
codex_enabled = false

[shortcuts]
highlight_selection = "h"
underline_selection = "v"
strikethrough_selection = "z"
add_comment = "command+shift+m"
exit_highlight_mode = "escape"
toggle_night_mode = "n"
adjust_reading_focus = "control+r"
switch_current_theme = "command+option+t"
save_annotations = "command+shift+s"
share_document = "command+option+e"
export_clean_copy = "command+option+shift+e"
copy_current_pdf_path = "command+shift+c"
send_context_to_codex = "command+option+x"
toggle_left_sidebar = "command+shift+l"
close_current_tab = "command+e"
close_current_window = "command+shift+e"
fit_width = "command+shift+9"
fit_text_width = "command+option+8"
fit_height = "command+shift+8"
previous_tab = "command+["
two_up = "command+option+8"
book = "command+option+5"
book_continuous = "command+option+6"
half_page_down = "control+f"
go_to_last_page = "shift+l"
find_previous_match = "shift+n"
show_recent_files_palette = "command+space"
show_all_tabs = "control+tab"
toggle_continuous_reading = "command+option+c"
open_containing_folder = "command+option+r"
find_all_open = "command+option+f"
refresh_library_index = "command+option+r"
open_library_settings = "command+option+l"
open_shortcut_settings = "command+option+s"
merge_all_windows = "command+option+m"
move_current_pdf_to_new_window = "command+option+n"

[layout]
show_recent_files_in_sidebar = false
sidebar_opacity = 0.42
floating_outline_height = 480

[library]
folders = ["/tmp/Books", "/tmp/Papers"]

[access]
roots = ["/Users"]
root_bookmarks = []

[shortcuts]
open_library_pdf = "command+option+o"
""".write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()

        XCTAssertEqual(configuration.appearance.mode, .light)
        XCTAssertEqual(configuration.appearance.lightTheme, .rosePineDawn)
        XCTAssertEqual(configuration.appearance.darkTheme, .normal)
        XCTAssertEqual(configuration.reader.defaultDisplayMode, .twoUp)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.reader.readingFocus.widthMode, .column)
        XCTAssertEqual(configuration.reader.readingFocus.customWidthRatio, 0.64, accuracy: 0.001)
        XCTAssertEqual(configuration.reader.readingFocus.height, 112, accuracy: 0.001)
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "h", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.underlineSelection], KeyboardShortcut(key: "v", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.strikethroughSelection], KeyboardShortcut(key: "z", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.addComment], KeyboardShortcut(key: "m", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.exitHighlightMode], KeyboardShortcut(key: "escape", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleNightMode], KeyboardShortcut(key: "n", modifiers: []))
        XCTAssertEqual(configuration.shortcuts.bindings[.adjustReadingFocus], KeyboardShortcut(key: "r", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.switchCurrentTheme], KeyboardShortcut(key: "t", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openLibraryPDF], KeyboardShortcut(key: "o", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.saveAnnotations], KeyboardShortcut(key: "s", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.shareDocument], KeyboardShortcut(key: "e", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.exportCleanCopy], KeyboardShortcut(key: "e", modifiers: [.command, .option, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.copyCurrentPDFPath], KeyboardShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertFalse(configuration.integrations.codexEnabled)
        XCTAssertEqual(configuration.shortcuts.bindings[.sendContextToCodex], KeyboardShortcut(key: "x", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleLeftSidebar], KeyboardShortcut(key: "l", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentTab], KeyboardShortcut(key: "e", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.closeCurrentWindow], KeyboardShortcut(key: "e", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth], KeyboardShortcut(key: "9", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitTextWidth], KeyboardShortcut(key: "8", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.fitHeight], KeyboardShortcut(key: "8", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.previousTab], KeyboardShortcut(key: "[", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.twoUp], KeyboardShortcut(key: "8", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.book], KeyboardShortcut(key: "5", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.bookContinuous], KeyboardShortcut(key: "6", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.halfPageDown], KeyboardShortcut(key: "f", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.goToLastPage], KeyboardShortcut(key: "l", modifiers: [.shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findPreviousMatch], KeyboardShortcut(key: "n", modifiers: [.shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showRecentFilesPalette], KeyboardShortcut(key: "space", modifiers: [.command]))
        XCTAssertEqual(configuration.shortcuts.bindings[.showAllTabs], KeyboardShortcut(key: "tab", modifiers: [.control]))
        XCTAssertEqual(configuration.shortcuts.bindings[.toggleContinuousReading], KeyboardShortcut(key: "c", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openContainingFolder], KeyboardShortcut(key: "r", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.findAllOpen], KeyboardShortcut(key: "f", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.refreshLibraryIndex], KeyboardShortcut(key: "r", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openLibrarySettings], KeyboardShortcut(key: "l", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.openShortcutSettings], KeyboardShortcut(key: "s", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.mergeAllWindows], KeyboardShortcut(key: "m", modifiers: [.command, .option]))
        XCTAssertEqual(configuration.shortcuts.bindings[.moveCurrentPDFToNewWindow], KeyboardShortcut(key: "n", modifiers: [.command, .option]))
        XCTAssertFalse(configuration.layout.showRecentFilesInSidebar)
        XCTAssertEqual(configuration.layout.sidebarOpacity, 0.42, accuracy: 0.001)
        XCTAssertEqual(configuration.layout.floatingOutlineHeight, 480, accuracy: 0.001)
        XCTAssertEqual(
            configuration.library.folderURLs.map(\.path),
            ["/tmp/Books", "/tmp/Papers"]
        )
    }

    func testParserRejectsOutOfRangeSidebarOpacity() {
        let parser = AppConfigurationParser()

        XCTAssertThrowsError(try parser.parse("[layout]\nsidebar_opacity = 1.2")) { error in
            guard case AppConfigurationError.invalidOpacity = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
        XCTAssertThrowsError(try parser.parse("[layout]\nsidebar_opacity = -0.1")) { error in
            guard case AppConfigurationError.invalidOpacity = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testParserRejectsOutOfRangeFloatingOutlineHeight() {
        let parser = AppConfigurationParser()

        for value in [179, 721] {
            XCTAssertThrowsError(
                try parser.parse("[layout]\nfloating_outline_height = \(value)")
            ) { error in
                guard case AppConfigurationError.invalidFloatingOutlineHeight = error else {
                    XCTFail("Unexpected error: \(error)")
                    return
                }
            }
        }
    }

    func testParserRejectsInvalidReadingFocusSettings() {
        let parser = AppConfigurationParser()

        XCTAssertThrowsError(try parser.parse("[reader]\nreading_focus_width = \"viewport\"")) { error in
            guard case AppConfigurationError.invalidReadingFocusWidthMode = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
        XCTAssertThrowsError(try parser.parse("[reader]\nreading_focus_custom_width = 0.2")) { error in
            guard case AppConfigurationError.invalidReadingFocusWidthRatio = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
        XCTAssertThrowsError(try parser.parse("[reader]\nreading_focus_height = 260")) { error in
            guard case AppConfigurationError.invalidReadingFocusHeight = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testExistingConfigGetsMissingShortcutKeysBackfilled() throws {
        try withTemporaryConfigRoot(self) { rootURL in
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
            let keys = assignmentKeys(in: content)

            // Minimal seed is expanded to the full required key set + templates.
            XCTAssertTrue(keys.isSuperset(of: Set(AppConfigurationFile.requiredKeys)))
            XCTAssertTrue(content.contains("fit_width = \"command+9\""), "user override preserved")
            XCTAssertTrue(content.contains("[appearance]"))
            XCTAssertTrue(content.contains("[library]"))
            XCTAssertTrue(content.contains("[access]"))
            // Sample of self-healed defaults (not every key).
            XCTAssertTrue(content.contains("highlight_selection = \"a\""))
            XCTAssertTrue(content.contains("new_blank_tab = \"command+t\""))
            XCTAssertTrue(content.contains("sidebar_opacity = 0.48"))
        }
    }

    func testMissingBookShortcutIsNotHiddenByLongerKeys() throws {
        try withTemporaryConfigRoot(self) { rootURL in
            let fileURL = rootURL.appendingPathComponent("config.toml")
            try AppConfigurationFile.defaultContents
                .replacingOccurrences(of: "book = \"none\"\n", with: "")
                .write(to: fileURL, atomically: true, encoding: .utf8)

            let configuration = try AppConfigurationStore(fileURL: fileURL).load()
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            XCTAssertNil(configuration.shortcuts.bindings[.book])
            XCTAssertTrue(content.contains("book = \"none\""))
            XCTAssertTrue(content.contains("book_continuous = \"none\""))
            XCTAssertTrue(content.contains("root_bookmarks = []"))
        }
    }

    func testNewContinuityShortcutDoesNotOverrideExistingPlainCBinding() throws {
        try withTemporaryConfigRoot(self) { rootURL in
            let fileURL = rootURL.appendingPathComponent("config.toml")
            try AppConfigurationFile.defaultContents
                .replacingOccurrences(of: "book = \"none\"", with: "book = \"c\"")
                .replacingOccurrences(of: "toggle_display_mode_continuity = \"c\"\n", with: "")
                .write(to: fileURL, atomically: true, encoding: .utf8)

            let configuration = try AppConfigurationStore(fileURL: fileURL).load()

            XCTAssertEqual(
                configuration.shortcuts.bindings[.book],
                KeyboardShortcut(key: "c", modifiers: [])
            )
            XCTAssertNil(configuration.shortcuts.bindings[.toggleDisplayModeContinuity])
        }
    }

    func testLegacyGreenShortcutMigratesAwayFromFindPreviousConflict() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
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

    func testBootstrapMigratesLegacyAddCommentShortcut() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "add_comment = \"m\"", with: "add_comment = \"command+option+m\"")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.addComment], KeyboardShortcut(key: "m", modifiers: []))
        XCTAssertTrue(persistedContent.contains("add_comment = \"m\""))
        XCTAssertFalse(persistedContent.contains("add_comment = \"command+option+m\""))
    }

    func testBootstrapMigratesLegacyRemoveHighlightShortcut() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
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
        defer { try? FileManager.default.removeItem(at: rootURL) }
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
        defer { try? FileManager.default.removeItem(at: rootURL) }
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

    func testBootstrapMigratesLegacyContinuousReadingShortcutToCopyPath() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "copy_current_pdf_path = \"command+shift+c\"\n", with: "")
            .replacingOccurrences(
                of: "toggle_continuous_reading = \"none\"",
                with: "toggle_continuous_reading = \"command+shift+c\""
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(configuration.shortcuts.bindings[.copyCurrentPDFPath], KeyboardShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertNil(configuration.shortcuts.bindings[.toggleContinuousReading])
        XCTAssertTrue(persistedContent.contains("copy_current_pdf_path = \"command+shift+c\""))
        XCTAssertTrue(persistedContent.contains("toggle_continuous_reading = \"none\""))
        XCTAssertFalse(persistedContent.contains("toggle_continuous_reading = \"command+shift+c\""))
    }

    func testBootstrapMigratesLegacyCodexShortcutsToContextPair() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(
                of: "send_context_to_codex = \"command+control+c\"",
                with: "send_selection_to_codex = \"none\"\nsend_current_page_to_codex = \"none\""
            )
            .replacingOccurrences(
                of: "send_current_pdf_to_codex = \"command+control+shift+c\"",
                with: "send_current_pdf_to_codex = \"none\""
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(
            configuration.shortcuts.bindings[.sendContextToCodex],
            KeyboardShortcut(key: "c", modifiers: [.command, .control])
        )
        XCTAssertEqual(
            configuration.shortcuts.bindings[.sendCurrentPDFToCodex],
            KeyboardShortcut(key: "c", modifiers: [.command, .control, .shift])
        )
        XCTAssertFalse(persistedContent.contains("send_selection_to_codex"))
        XCTAssertFalse(persistedContent.contains("send_current_page_to_codex"))
    }

    func testBootstrapLeavesNewMarkupShortcutUnboundWhenLegacyBindingConflicts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "underline_selection = \"u\"\n", with: "")
            .replacingOccurrences(of: "highlight_selection = \"a\"", with: "highlight_selection = \"u\"")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(
            configuration.shortcuts.bindings[.highlightSelection],
            KeyboardShortcut(key: "u", modifiers: [])
        )
        XCTAssertNil(configuration.shortcuts.bindings[.underlineSelection])
        XCTAssertTrue(persistedContent.contains("underline_selection = \"none\""))
    }

    func testParseStringStripsInlineCommentsOutsideQuotes() throws {
        let parser = AppConfigurationParser()
        let configuration = try parser.parse("""
        [appearance]
        mode = "system" # follow macOS
        light_theme = "normal"
        dark_theme = "rose_pine_moon"

        [shortcuts]
        highlight_selection = "a" # one-shot highlight
        """)

        XCTAssertEqual(configuration.appearance.mode, .system)
        XCTAssertEqual(configuration.shortcuts.bindings[.highlightSelection], KeyboardShortcut(key: "a", modifiers: []))
    }

    func testConfigKeyListsStayInSyncAndMissingKeysSelfHeal() throws {
        let defaultKeys = assignmentKeys(in: AppConfigurationFile.defaultContents)
        let renderKeys = assignmentKeys(in: AppConfigurationFile.render(.default))
        let required = Set(AppConfigurationFile.requiredKeys)

        XCTAssertEqual(defaultKeys, renderKeys, "defaultContents and render() must declare the same assignment keys")
        XCTAssertTrue(required.isSubset(of: defaultKeys), "requiredKeys must be a subset of templates")
        XCTAssertTrue(
            assignmentKeys(in: AppConfigurationFile.defaultContents, section: "shortcuts").isSubset(of: required),
            "every shortcut key must be self-healable via requiredKeys"
        )
        XCTAssertTrue(required.contains("new_blank_tab"))
        XCTAssertTrue(required.contains("floating_outline_height"))

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")
        try AppConfigurationFile.defaultContents
            .replacingOccurrences(of: "new_blank_tab = \"command+t\"\n", with: "")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try AppConfigurationStore(fileURL: fileURL)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("new_blank_tab = \"command+t\""))
    }

    private func assignmentKeys(in content: String, section filterSection: String? = nil) -> Set<String> {
        var keys = Set<String>()
        var section = ""
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                if filterSection == nil {
                    keys.insert(line)
                }
                continue
            }
            if let filterSection, section != filterSection {
                continue
            }
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            keys.insert(pair[0].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return keys
    }

    func testSavePersistsUpdatedReaderAndAnnotationDefaults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        configuration.appearance.mode = .dark
        configuration.appearance.lightTheme = .rosePineDawn
        configuration.appearance.darkTheme = .normal
        configuration.reader.defaultDisplayMode = .bookContinuous
        configuration.reader.fitWidthOnOpen = true
        configuration.reader.readingFocus = ReadingFocusSettings(
            widthMode: .custom,
            customWidthRatio: 0.58,
            height: 128
        )
        configuration.annotations.autoSavePolicy = .never
        configuration.shortcuts.bindings[.fitTextWidth] = KeyboardShortcut(key: "0", modifiers: [.command, .control])
        configuration.layout.floatingOutlineHeight = 540
        configuration.library.folderURLs = [
            URL(fileURLWithPath: "/tmp/Books"),
            URL(fileURLWithPath: "/tmp/Papers"),
        ]
        configuration.access.rootURLs = [
            URL(fileURLWithPath: "/Users", isDirectory: true),
        ]
        configuration.access.rootBookmarkData = [
            "/Users": Data("users-bookmark".utf8),
        ]

        try store.save(configuration)
        let reloadedConfiguration = try store.load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(reloadedConfiguration.appearance.mode, .dark)
        XCTAssertEqual(reloadedConfiguration.appearance.lightTheme, .rosePineDawn)
        XCTAssertEqual(reloadedConfiguration.appearance.darkTheme, .normal)
        XCTAssertEqual(reloadedConfiguration.reader.defaultDisplayMode, .bookContinuous)
        XCTAssertTrue(reloadedConfiguration.reader.fitWidthOnOpen)
        XCTAssertEqual(reloadedConfiguration.reader.readingFocus.widthMode, .custom)
        XCTAssertEqual(reloadedConfiguration.reader.readingFocus.customWidthRatio, 0.58, accuracy: 0.001)
        XCTAssertEqual(reloadedConfiguration.reader.readingFocus.height, 128, accuracy: 0.001)
        XCTAssertEqual(reloadedConfiguration.annotations.autoSavePolicy, .never)
        XCTAssertEqual(
            reloadedConfiguration.shortcuts.bindings[.fitTextWidth],
            KeyboardShortcut(key: "0", modifiers: [.command, .control])
        )
        XCTAssertEqual(reloadedConfiguration.layout.floatingOutlineHeight, 540, accuracy: 0.001)
        XCTAssertEqual(reloadedConfiguration.library.folderURLs.map(\.path), ["/tmp/Books", "/tmp/Papers"])
        XCTAssertEqual(reloadedConfiguration.access.rootURLs.map(\.path), ["/Users"])
        XCTAssertEqual(reloadedConfiguration.access.rootBookmarkData["/Users"], Data("users-bookmark".utf8))
        XCTAssertTrue(persistedContent.contains("mode = \"dark\""))
        XCTAssertTrue(persistedContent.contains("light_theme = \"rose_pine_dawn\""))
        XCTAssertTrue(persistedContent.contains("dark_theme = \"normal\""))
        XCTAssertTrue(persistedContent.contains("default_display_mode = \"book_continuous\""))
        XCTAssertTrue(persistedContent.contains("fit_width_on_open = true"))
        XCTAssertTrue(persistedContent.contains("reading_focus_width = \"custom\""))
        XCTAssertTrue(persistedContent.contains("reading_focus_custom_width = 0.58"))
        XCTAssertTrue(persistedContent.contains("reading_focus_height = 128"))
        XCTAssertTrue(persistedContent.contains("floating_outline_height = 540"))
        XCTAssertTrue(persistedContent.contains("auto_save = \"never\""))
        XCTAssertTrue(persistedContent.contains("folders = [\"/tmp/Books\", \"/tmp/Papers\"]"))
        XCTAssertTrue(persistedContent.contains("roots = [\"/Users\"]"))
        XCTAssertTrue(persistedContent.contains("root_bookmarks = ["))
    }

    func testLoadAccessRootBookmarks() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let path = "/Users"
        let bookmark = Data("bookmark-data".utf8)
        let entry = "\(Data(path.utf8).base64EncodedString()):\(bookmark.base64EncodedString())"

        try """
[access]
roots = ["\(path)"]
root_bookmarks = ["\(entry)"]
""".write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()

        XCTAssertEqual(configuration.access.rootURLs.map(\.path), [path])
        XCTAssertEqual(configuration.access.rootBookmarkData[path], bookmark)
    }

    func testLegacyToggleLeftTabsModeMigratesToRightSidebarMode() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
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
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        XCTAssertFalse(configuration.layout.sidebarsSwapped)
        XCTAssertEqual(configuration.layout.sidebarOpacity, 0.48, accuracy: 0.001)
        configuration.layout.sidebarsSwapped = true
        configuration.layout.sidebarOpacity = 0.48

        try store.save(configuration)
        let reloadedConfiguration = try store.load()
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(reloadedConfiguration.layout.sidebarsSwapped)
        XCTAssertEqual(reloadedConfiguration.layout.sidebarOpacity, 0.48, accuracy: 0.001)
        XCTAssertTrue(persistedContent.contains("sidebars_swapped = true"))
        XCTAssertTrue(persistedContent.contains("sidebar_opacity = 0.48"))
    }

    func testClearedShortcutPersistsAsNone() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("config.toml")
        let store = try AppConfigurationStore(fileURL: fileURL)

        var configuration = try store.load()
        configuration.shortcuts.bindings[.copyHighlightsMarkdown] = nil
        configuration.shortcuts.bindings[.fitTextWidth] = nil

        try store.save(configuration)
        let persistedContent = try String(contentsOf: fileURL, encoding: .utf8)
        let reloaded = try store.load()

        XCTAssertTrue(persistedContent.contains("copy_highlights_markdown = \"none\""))
        XCTAssertNil(reloaded.shortcuts.bindings[.copyHighlightsMarkdown])
        XCTAssertTrue(persistedContent.contains("fit_text_width = \"none\""))
        XCTAssertNil(reloaded.shortcuts.bindings[.fitTextWidth])
    }
}
