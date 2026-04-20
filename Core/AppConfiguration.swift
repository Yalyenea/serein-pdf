import AppKit
import Foundation

struct AppConfiguration: Equatable, Sendable {
    struct Reader: Equatable, Sendable {
        var defaultDisplayMode: ReaderDisplayMode
        var fitWidthOnOpen: Bool

        static let `default` = Reader(
            defaultDisplayMode: .singlePageContinuous,
            fitWidthOnOpen: false
        )
    }

    struct Annotations: Equatable, Sendable {
        var autoSavePolicy: AnnotationSavePolicy

        static let `default` = Annotations(autoSavePolicy: .default)
    }

    struct Layout: Equatable, Sendable {
        var leftSidebarWidth: CGFloat
        var leftSidebarMinWidth: CGFloat
        var leftSidebarMaxWidth: CGFloat
        var rightSidebarWidth: CGFloat
        var rightSidebarMinWidth: CGFloat
        var rightSidebarMaxWidth: CGFloat
        var sidebarsSwapped: Bool

        static let `default` = Layout(
            leftSidebarWidth: 220,
            leftSidebarMinWidth: 36,
            leftSidebarMaxWidth: 520,
            rightSidebarWidth: 320,
            rightSidebarMinWidth: 120,
            rightSidebarMaxWidth: 720,
            sidebarsSwapped: false
        )
    }

    struct Shortcuts: Equatable, Sendable {
        var bindings: [ShortcutCommand: KeyboardShortcut]

        static let `default` = Shortcuts(bindings: [
            .highlightSelection: KeyboardShortcut(key: "a", modifiers: []),
            .exitHighlightMode: KeyboardShortcut(key: "escape", modifiers: []),
            .toggleNightMode: KeyboardShortcut(key: "i", modifiers: []),
            .saveAnnotations: KeyboardShortcut(key: "s", modifiers: [.command]),
            .copyHighlightsMarkdown: KeyboardShortcut(key: "e", modifiers: [.command, .shift]),
            .removeHighlight: KeyboardShortcut(key: "d", modifiers: []),
            .highlightColorPink: KeyboardShortcut(key: "p", modifiers: [.command, .shift]),
            .highlightColorYellow: KeyboardShortcut(key: "y", modifiers: [.command, .shift]),
            .highlightColorGreen: KeyboardShortcut(key: "g", modifiers: [.command, .shift]),
            .toggleLeftSidebar: KeyboardShortcut(key: "b", modifiers: [.command]),
            .toggleRightSidebar: KeyboardShortcut(key: "b", modifiers: [.command, .option]),
            .useSidebarTabs: KeyboardShortcut(key: "1", modifiers: [.command, .shift]),
            .useTitlebarTabs: KeyboardShortcut(key: "2", modifiers: [.command, .shift]),
            .closeCurrentTab: KeyboardShortcut(key: "w", modifiers: [.command]),
            .previousTab: KeyboardShortcut(key: "[", modifiers: [.command, .shift]),
            .nextTab: KeyboardShortcut(key: "]", modifiers: [.command, .shift]),
            .fitWidth: KeyboardShortcut(key: "0", modifiers: [.command]),
            .zoomIn: KeyboardShortcut(key: "=", modifiers: [.command]),
            .zoomOut: KeyboardShortcut(key: "-", modifiers: [.command]),
            .singlePage: KeyboardShortcut(key: "1", modifiers: [.command]),
            .singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command]),
            .twoUp: KeyboardShortcut(key: "3", modifiers: [.command]),
            .twoUpContinuous: KeyboardShortcut(key: "4", modifiers: [.command]),
            .pageDown: KeyboardShortcut(key: "j", modifiers: []),
            .pageUp: KeyboardShortcut(key: "k", modifiers: []),
            .navigateBack: KeyboardShortcut(key: "[", modifiers: [.command]),
            .navigateForward: KeyboardShortcut(key: "]", modifiers: [.command]),
            .gotoPage: KeyboardShortcut(key: "g", modifiers: [.command, .option]),
            .reopenLastClosed: KeyboardShortcut(key: "t", modifiers: [.command, .shift]),
            .newWindow: KeyboardShortcut(key: "n", modifiers: [.command, .shift]),
            .toggleAllPagesOverview: KeyboardShortcut(key: "o", modifiers: [.command, .shift]),
            .toggleReaderSplit: KeyboardShortcut(key: "\\", modifiers: [.command, .control]),
            .toggleRightSidebarMode: KeyboardShortcut(key: "l", modifiers: [.command, .shift]),
            .swapSidebars: KeyboardShortcut(key: "x", modifiers: [.command, .shift]),
            .undoLastHighlight: KeyboardShortcut(key: "z", modifiers: [.command]),
        ])
    }

    var reader: Reader
    var annotations: Annotations
    var shortcuts: Shortcuts
    var layout: Layout

    static let `default` = AppConfiguration(
        reader: .default,
        annotations: .default,
        shortcuts: .default,
        layout: .default
    )
}

enum KeyboardShortcutModifier: String, CaseIterable, Sendable {
    case command
    case shift
    case option
    case control

    var eventModifier: NSEvent.ModifierFlags {
        switch self {
        case .command:
            .command
        case .shift:
            .shift
        case .option:
            .option
        case .control:
            .control
        }
    }
}

struct KeyboardShortcut: Equatable, Sendable {
    var key: String
    var modifiers: Set<KeyboardShortcutModifier>

    init(key: String, modifiers: Set<KeyboardShortcutModifier>) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    var modifierMask: NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { partialResult, modifier in
            partialResult.insert(modifier.eventModifier)
        }
    }

    var isPlainShortcut: Bool {
        modifiers.isEmpty
    }

    var menuKeyEquivalent: String {
        switch key {
        case "escape":
            "\u{1b}"
        default:
            key
        }
    }

    func matches(event: NSEvent) -> Bool {
        let normalizedModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard normalizedModifiers == modifierMask else { return false }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let normalizedKey = switch characters {
        case "\u{1b}":
            "escape"
        default:
            characters
        }

        return normalizedKey == key
    }

    var serializedValue: String {
        let orderedModifiers = KeyboardShortcutModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.rawValue)
        return (orderedModifiers + [key]).joined(separator: "+")
    }

    static func parse(_ rawValue: String) throws -> KeyboardShortcut {
        let tokens = rawValue
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }

        guard let key = tokens.last, isSupportedKeyToken(key) else {
            throw AppConfigurationError.invalidShortcut(rawValue)
        }

        let modifiers = try Set(tokens.dropLast().map { token in
            guard let modifier = KeyboardShortcutModifier(rawValue: token) else {
                throw AppConfigurationError.invalidShortcut(rawValue)
            }
            return modifier
        })

        return KeyboardShortcut(key: key, modifiers: modifiers)
    }

    private static func isSupportedKeyToken(_ token: String) -> Bool {
        token.count == 1 || token == "escape"
    }
}

enum AppConfigurationError: LocalizedError {
    case invalidLine(Int, String)
    case invalidBoolean(String)
    case invalidDisplayMode(String)
    case invalidShortcut(String)
    case invalidAnnotationSavePolicy(String)
    case invalidWidth(String)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(lineNumber, line):
            "Invalid config line \(lineNumber): \(line)"
        case let .invalidBoolean(value):
            "Invalid boolean value in config: \(value)"
        case let .invalidDisplayMode(value):
            "Invalid reader display mode in config: \(value)"
        case let .invalidShortcut(value):
            "Invalid keyboard shortcut in config: \(value)"
        case let .invalidAnnotationSavePolicy(value):
            "Invalid annotation auto-save policy in config: \(value)"
        case let .invalidWidth(value):
            "Invalid sidebar width in config: \(value)"
        }
    }
}

struct AppConfigurationFile {
    static let defaultContents = """
# SlatePDF configuration
# Location: ~/Library/Application Support/SlatePDF/config.toml

[reader]
default_display_mode = "single_page_continuous"
fit_width_on_open = false

[annotations]
auto_save = "after_10_minutes"

[layout]
left_sidebar_width = 220
left_sidebar_min_width = 36
left_sidebar_max_width = 520
right_sidebar_width = 320
right_sidebar_min_width = 120
right_sidebar_max_width = 720
sidebars_swapped = false

[shortcuts]
highlight_selection = "a"
exit_highlight_mode = "escape"
toggle_night_mode = "i"
save_annotations = "command+s"
copy_highlights_markdown = "command+shift+e"
remove_highlight = "d"
highlight_color_pink = "command+shift+p"
highlight_color_yellow = "command+shift+y"
highlight_color_green = "command+shift+g"
toggle_left_sidebar = "command+b"
toggle_right_sidebar = "command+option+b"
use_sidebar_tabs = "command+shift+1"
use_titlebar_tabs = "command+shift+2"
close_current_tab = "command+w"
previous_tab = "command+shift+["
next_tab = "command+shift+]"
fit_width = "command+0"
zoom_in = "command+="
zoom_out = "command+-"
single_page = "command+1"
single_page_continuous = "command+2"
two_up = "command+3"
two_up_continuous = "command+4"
page_down = "j"
page_up = "k"
navigate_back = "command+["
navigate_forward = "command+]"
goto_page = "command+option+g"
reopen_last_closed = "command+shift+t"
new_window = "command+shift+n"
toggle_all_pages_overview = "command+shift+o"
toggle_reader_split = "command+control+\\"
toggle_right_sidebar_mode = "command+shift+l"
swap_sidebars = "command+shift+x"
undo_last_highlight = "command+z"
"""

    static func render(_ configuration: AppConfiguration) -> String {
        """
# SlatePDF configuration
# Location: ~/Library/Application Support/SlatePDF/config.toml

[reader]
default_display_mode = "\(configuration.reader.defaultDisplayMode.rawValue)"
fit_width_on_open = \(configuration.reader.fitWidthOnOpen ? "true" : "false")

[annotations]
auto_save = "\(configuration.annotations.autoSavePolicy.rawValue)"

[layout]
left_sidebar_width = \(Int(configuration.layout.leftSidebarWidth.rounded()))
left_sidebar_min_width = \(Int(configuration.layout.leftSidebarMinWidth.rounded()))
left_sidebar_max_width = \(Int(configuration.layout.leftSidebarMaxWidth.rounded()))
right_sidebar_width = \(Int(configuration.layout.rightSidebarWidth.rounded()))
right_sidebar_min_width = \(Int(configuration.layout.rightSidebarMinWidth.rounded()))
right_sidebar_max_width = \(Int(configuration.layout.rightSidebarMaxWidth.rounded()))
sidebars_swapped = \(configuration.layout.sidebarsSwapped ? "true" : "false")

[shortcuts]
highlight_selection = "\(serializedShortcut(.highlightSelection, configuration: configuration))"
exit_highlight_mode = "\(serializedShortcut(.exitHighlightMode, configuration: configuration))"
toggle_night_mode = "\(serializedShortcut(.toggleNightMode, configuration: configuration))"
save_annotations = "\(serializedShortcut(.saveAnnotations, configuration: configuration))"
copy_highlights_markdown = "\(serializedShortcut(.copyHighlightsMarkdown, configuration: configuration))"
remove_highlight = "\(serializedShortcut(.removeHighlight, configuration: configuration))"
highlight_color_pink = "\(serializedShortcut(.highlightColorPink, configuration: configuration))"
highlight_color_yellow = "\(serializedShortcut(.highlightColorYellow, configuration: configuration))"
highlight_color_green = "\(serializedShortcut(.highlightColorGreen, configuration: configuration))"
toggle_left_sidebar = "\(serializedShortcut(.toggleLeftSidebar, configuration: configuration))"
toggle_right_sidebar = "\(serializedShortcut(.toggleRightSidebar, configuration: configuration))"
use_sidebar_tabs = "\(serializedShortcut(.useSidebarTabs, configuration: configuration))"
use_titlebar_tabs = "\(serializedShortcut(.useTitlebarTabs, configuration: configuration))"
close_current_tab = "\(serializedShortcut(.closeCurrentTab, configuration: configuration))"
previous_tab = "\(serializedShortcut(.previousTab, configuration: configuration))"
next_tab = "\(serializedShortcut(.nextTab, configuration: configuration))"
fit_width = "\(serializedShortcut(.fitWidth, configuration: configuration))"
zoom_in = "\(serializedShortcut(.zoomIn, configuration: configuration))"
zoom_out = "\(serializedShortcut(.zoomOut, configuration: configuration))"
single_page = "\(serializedShortcut(.singlePage, configuration: configuration))"
single_page_continuous = "\(serializedShortcut(.singlePageContinuous, configuration: configuration))"
two_up = "\(serializedShortcut(.twoUp, configuration: configuration))"
two_up_continuous = "\(serializedShortcut(.twoUpContinuous, configuration: configuration))"
page_down = "\(serializedShortcut(.pageDown, configuration: configuration))"
page_up = "\(serializedShortcut(.pageUp, configuration: configuration))"
navigate_back = "\(serializedShortcut(.navigateBack, configuration: configuration))"
navigate_forward = "\(serializedShortcut(.navigateForward, configuration: configuration))"
goto_page = "\(serializedShortcut(.gotoPage, configuration: configuration))"
reopen_last_closed = "\(serializedShortcut(.reopenLastClosed, configuration: configuration))"
new_window = "\(serializedShortcut(.newWindow, configuration: configuration))"
toggle_all_pages_overview = "\(serializedShortcut(.toggleAllPagesOverview, configuration: configuration))"
toggle_reader_split = "\(serializedShortcut(.toggleReaderSplit, configuration: configuration))"
toggle_right_sidebar_mode = "\(serializedShortcut(.toggleRightSidebarMode, configuration: configuration))"
swap_sidebars = "\(serializedShortcut(.swapSidebars, configuration: configuration))"
undo_last_highlight = "\(serializedShortcut(.undoLastHighlight, configuration: configuration))"
"""
    }

    private static func serializedShortcut(
        _ command: ShortcutCommand,
        configuration: AppConfiguration
    ) -> String {
        configuration.shortcuts.bindings[command]?.serializedValue ?? "none"
    }
}

struct AppConfigurationParser {
    func parse(_ content: String) throws -> AppConfiguration {
        var configuration = AppConfiguration.default
        var section = ""

        for (index, rawLine) in content.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }

            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else {
                throw AppConfigurationError.invalidLine(index + 1, rawLine)
            }

            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            try apply(value: value, for: key, in: section, to: &configuration)
        }

        return configuration
    }

    private func apply(
        value rawValue: String,
        for key: String,
        in section: String,
        to configuration: inout AppConfiguration
    ) throws {
        switch (section, key) {
        case ("shortcuts", "highlight_selection"):
            try applyShortcut(rawValue, command: .highlightSelection, to: &configuration)
        case ("shortcuts", "exit_highlight_mode"):
            try applyShortcut(rawValue, command: .exitHighlightMode, to: &configuration)
        case ("shortcuts", "toggle_night_mode"):
            try applyShortcut(rawValue, command: .toggleNightMode, to: &configuration)
        case ("shortcuts", "save_annotations"):
            try applyShortcut(rawValue, command: .saveAnnotations, to: &configuration)
        case ("shortcuts", "copy_highlights_markdown"):
            try applyShortcut(rawValue, command: .copyHighlightsMarkdown, to: &configuration)
        case ("reader", "default_display_mode"):
            let value = parseString(rawValue)
            guard let displayMode = ReaderDisplayMode(rawValue: value) else {
                throw AppConfigurationError.invalidDisplayMode(value)
            }
            configuration.reader.defaultDisplayMode = displayMode
        case ("reader", "fit_width_on_open"):
            configuration.reader.fitWidthOnOpen = try parseBool(rawValue)
        case ("annotations", "auto_save"):
            let value = parseString(rawValue)
            guard let policy = AnnotationSavePolicy(rawValue: value) else {
                throw AppConfigurationError.invalidAnnotationSavePolicy(value)
            }
            configuration.annotations.autoSavePolicy = policy
        case ("layout", "left_sidebar_width"):
            configuration.layout.leftSidebarWidth = try parseWidth(rawValue)
        case ("layout", "left_sidebar_min_width"):
            configuration.layout.leftSidebarMinWidth = try parseWidth(rawValue)
        case ("layout", "left_sidebar_max_width"):
            configuration.layout.leftSidebarMaxWidth = try parseWidth(rawValue)
        case ("layout", "right_sidebar_width"):
            configuration.layout.rightSidebarWidth = try parseWidth(rawValue)
        case ("layout", "right_sidebar_min_width"):
            configuration.layout.rightSidebarMinWidth = try parseWidth(rawValue)
        case ("layout", "right_sidebar_max_width"):
            configuration.layout.rightSidebarMaxWidth = try parseWidth(rawValue)
        case ("layout", "sidebars_swapped"):
            configuration.layout.sidebarsSwapped = try parseBool(rawValue)
        case ("shortcuts", "remove_highlight"):
            try applyShortcut(rawValue, command: .removeHighlight, to: &configuration)
        case ("shortcuts", "highlight_color_pink"):
            try applyShortcut(rawValue, command: .highlightColorPink, to: &configuration)
        case ("shortcuts", "highlight_color_yellow"):
            try applyShortcut(rawValue, command: .highlightColorYellow, to: &configuration)
        case ("shortcuts", "highlight_color_green"):
            try applyShortcut(rawValue, command: .highlightColorGreen, to: &configuration)
        case ("shortcuts", "toggle_left_sidebar"):
            try applyShortcut(rawValue, command: .toggleLeftSidebar, to: &configuration)
        case ("shortcuts", "toggle_right_sidebar"):
            try applyShortcut(rawValue, command: .toggleRightSidebar, to: &configuration)
        case ("shortcuts", "use_sidebar_tabs"):
            try applyShortcut(rawValue, command: .useSidebarTabs, to: &configuration)
        case ("shortcuts", "use_titlebar_tabs"):
            try applyShortcut(rawValue, command: .useTitlebarTabs, to: &configuration)
        case ("shortcuts", "close_current_tab"):
            try applyShortcut(rawValue, command: .closeCurrentTab, to: &configuration)
        case ("shortcuts", "previous_tab"):
            try applyShortcut(rawValue, command: .previousTab, to: &configuration)
        case ("shortcuts", "next_tab"):
            try applyShortcut(rawValue, command: .nextTab, to: &configuration)
        case ("shortcuts", "fit_width"):
            try applyShortcut(rawValue, command: .fitWidth, to: &configuration)
        case ("shortcuts", "single_page"):
            try applyShortcut(rawValue, command: .singlePage, to: &configuration)
        case ("shortcuts", "single_page_continuous"):
            try applyShortcut(rawValue, command: .singlePageContinuous, to: &configuration)
        case ("shortcuts", "two_up"):
            try applyShortcut(rawValue, command: .twoUp, to: &configuration)
        case ("shortcuts", "two_up_continuous"):
            try applyShortcut(rawValue, command: .twoUpContinuous, to: &configuration)
        case ("shortcuts", "zoom_in"):
            try applyShortcut(rawValue, command: .zoomIn, to: &configuration)
        case ("shortcuts", "zoom_out"):
            try applyShortcut(rawValue, command: .zoomOut, to: &configuration)
        case ("shortcuts", "page_down"):
            try applyShortcut(rawValue, command: .pageDown, to: &configuration)
        case ("shortcuts", "page_up"):
            try applyShortcut(rawValue, command: .pageUp, to: &configuration)
        case ("shortcuts", "navigate_back"):
            try applyShortcut(rawValue, command: .navigateBack, to: &configuration)
        case ("shortcuts", "navigate_forward"):
            try applyShortcut(rawValue, command: .navigateForward, to: &configuration)
        case ("shortcuts", "goto_page"):
            try applyShortcut(rawValue, command: .gotoPage, to: &configuration)
        case ("shortcuts", "reopen_last_closed"):
            try applyShortcut(rawValue, command: .reopenLastClosed, to: &configuration)
        case ("shortcuts", "new_window"):
            try applyShortcut(rawValue, command: .newWindow, to: &configuration)
        case ("shortcuts", "toggle_all_pages_overview"):
            try applyShortcut(rawValue, command: .toggleAllPagesOverview, to: &configuration)
        case ("shortcuts", "toggle_reader_split"):
            try applyShortcut(rawValue, command: .toggleReaderSplit, to: &configuration)
        case ("shortcuts", "toggle_right_sidebar_mode"), ("shortcuts", "toggle_left_tabs_mode"):
            try applyShortcut(rawValue, command: .toggleRightSidebarMode, to: &configuration)
        case ("shortcuts", "swap_sidebars"):
            try applyShortcut(rawValue, command: .swapSidebars, to: &configuration)
        case ("shortcuts", "undo_last_highlight"):
            try applyShortcut(rawValue, command: .undoLastHighlight, to: &configuration)
        default:
            break
        }
    }

    private func parseString(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func applyShortcut(
        _ rawValue: String,
        command: ShortcutCommand,
        to configuration: inout AppConfiguration
    ) throws {
        let value = parseString(rawValue)
        if value == "none" {
            configuration.shortcuts.bindings.removeValue(forKey: command)
            return
        }
        configuration.shortcuts.bindings[command] = try KeyboardShortcut.parse(value)
    }

    private func parseBool(_ rawValue: String) throws -> Bool {
        switch rawValue.lowercased() {
        case "true":
            true
        case "false":
            false
        default:
            throw AppConfigurationError.invalidBoolean(rawValue)
        }
    }

    private func parseWidth(_ rawValue: String) throws -> CGFloat {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard let value = Double(trimmed), value > 0 else {
            throw AppConfigurationError.invalidWidth(rawValue)
        }
        return CGFloat(value)
    }
}

struct AppConfigurationStore {
    let fileURL: URL
    private let parser: AppConfigurationParser

    init(
        fileURL: URL = AppConfigurationStore.defaultFileURL(),
        parser: AppConfigurationParser = AppConfigurationParser()
    ) throws {
        self.fileURL = fileURL
        self.parser = parser
        try bootstrapIfNeeded()
    }

    func load() throws -> AppConfiguration {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try parser.parse(content)
    }

    func save(_ configuration: AppConfiguration) throws {
        try AppConfigurationFile.render(configuration).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func bootstrapIfNeeded() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try AppConfigurationFile.defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
        let requiredKeys = [
            "[annotations]",
            "auto_save",
            "[layout]",
            "left_sidebar_width",
            "left_sidebar_min_width",
            "left_sidebar_max_width",
            "right_sidebar_width",
            "right_sidebar_min_width",
            "right_sidebar_max_width",
            "sidebars_swapped",
            "highlight_selection",
            "exit_highlight_mode",
            "toggle_night_mode",
            "save_annotations",
            "copy_highlights_markdown",
            "remove_highlight",
            "highlight_color_pink",
            "highlight_color_yellow",
            "highlight_color_green",
            "toggle_left_sidebar",
            "toggle_right_sidebar",
            "use_sidebar_tabs",
            "use_titlebar_tabs",
            "close_current_tab",
            "previous_tab",
            "next_tab",
            "zoom_in",
            "zoom_out",
            "page_down",
            "page_up",
            "navigate_back",
            "navigate_forward",
            "goto_page",
            "reopen_last_closed",
            "new_window",
            "toggle_all_pages_overview",
            "toggle_reader_split",
            "toggle_right_sidebar_mode",
            "swap_sidebars",
            "undo_last_highlight",
        ]

        var configuration = try parser.parse(existingContent)
        let legacyRemoveHighlight = KeyboardShortcut(key: "d", modifiers: [.command, .shift])
        var didMigrate = false
        if configuration.shortcuts.bindings[.removeHighlight] == legacyRemoveHighlight {
            configuration.shortcuts.bindings[.removeHighlight] = KeyboardShortcut(key: "d", modifiers: [])
            didMigrate = true
        }

        let missingKeys = requiredKeys.contains(where: { existingContent.contains($0) == false })
        guard missingKeys || didMigrate else { return }

        try AppConfigurationFile.render(configuration).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlatePDF", isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}
