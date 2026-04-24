import AppKit
import Foundation

enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var menuTitle: String {
        switch self {
        case .system:
            "Follow System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var appAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    func toggled(currentIsDark: Bool) -> AppearanceMode {
        currentIsDark ? .light : .dark
    }
}

enum LightTheme: String, CaseIterable, Codable, Sendable {
    case normal
    case rosePineDawn = "rose_pine_dawn"

    var menuTitle: String {
        switch self {
        case .normal:
            "Normal"
        case .rosePineDawn:
            "Rose Pine Dawn"
        }
    }
}

enum DarkTheme: String, CaseIterable, Codable, Sendable {
    case normal
    case rosePineMoon = "rose_pine_moon"

    var menuTitle: String {
        switch self {
        case .normal:
            "Normal"
        case .rosePineMoon:
            "Rose Pine Moon"
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    struct Appearance: Equatable, Sendable {
        var mode: AppearanceMode
        var lightTheme: LightTheme
        var darkTheme: DarkTheme

        static let `default` = Appearance(
            mode: .system,
            lightTheme: .normal,
            darkTheme: .rosePineMoon
        )
    }

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
        var showRecentFilesInSidebar: Bool = true

        static let `default` = Layout(
            leftSidebarWidth: 220,
            leftSidebarMinWidth: 36,
            leftSidebarMaxWidth: 520,
            rightSidebarWidth: 320,
            rightSidebarMinWidth: 120,
            rightSidebarMaxWidth: 720,
            sidebarsSwapped: false,
            showRecentFilesInSidebar: true
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
            .highlightColorGreen: KeyboardShortcut(key: "g", modifiers: [.command, .control]),
            .toggleLeftSidebar: KeyboardShortcut(key: "b", modifiers: [.command]),
            .toggleRightSidebar: KeyboardShortcut(key: "b", modifiers: [.command, .option]),
            .useSidebarTabs: KeyboardShortcut(key: "1", modifiers: [.command, .shift]),
            .useTitlebarTabs: KeyboardShortcut(key: "2", modifiers: [.command, .shift]),
            .closeCurrentTab: KeyboardShortcut(key: "w", modifiers: [.command]),
            .previousTab: KeyboardShortcut(key: "[", modifiers: [.command, .shift]),
            .nextTab: KeyboardShortcut(key: "]", modifiers: [.command, .shift]),
            .fitHeight: KeyboardShortcut(key: "9", modifiers: [.command]),
            .fitWidth: KeyboardShortcut(key: "0", modifiers: [.command]),
            .zoomIn: KeyboardShortcut(key: "=", modifiers: [.command]),
            .zoomOut: KeyboardShortcut(key: "-", modifiers: [.command]),
            .singlePage: KeyboardShortcut(key: "1", modifiers: [.command]),
            .singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command]),
            .twoUp: KeyboardShortcut(key: "3", modifiers: [.command]),
            .twoUpContinuous: KeyboardShortcut(key: "4", modifiers: [.command]),
            .pageDown: KeyboardShortcut(key: "j", modifiers: []),
            .pageUp: KeyboardShortcut(key: "k", modifiers: []),
            .halfPageDown: KeyboardShortcut(key: "d", modifiers: [.control]),
            .halfPageUp: KeyboardShortcut(key: "u", modifiers: [.control]),
            .goToFirstPage: KeyboardShortcut(key: "g", modifiers: []),
            .goToLastPage: KeyboardShortcut(key: "g", modifiers: [.shift]),
            .navigateBack: KeyboardShortcut(key: "[", modifiers: [.command]),
            .navigateForward: KeyboardShortcut(key: "]", modifiers: [.command]),
            .findNextMatch: KeyboardShortcut(key: "g", modifiers: [.command]),
            .findPreviousMatch: KeyboardShortcut(key: "g", modifiers: [.command, .shift]),
            .gotoPage: KeyboardShortcut(key: "g", modifiers: [.command, .option]),
            .showRecentFilesPalette: KeyboardShortcut(key: "space", modifiers: [.command, .shift]),
            .openContainingFolder: KeyboardShortcut(key: "r", modifiers: [.command]),
            .reopenLastClosed: KeyboardShortcut(key: "t", modifiers: [.command, .shift]),
            .newWindow: KeyboardShortcut(key: "n", modifiers: [.command, .shift]),
            .toggleAllPagesOverview: KeyboardShortcut(key: "o", modifiers: [.command, .shift]),
            .toggleDemoMode: KeyboardShortcut(key: "l", modifiers: [.command]),
            .toggleImmersiveMode: KeyboardShortcut(key: "l", modifiers: [.command, .control]),
            .toggleReaderSplit: KeyboardShortcut(key: "\\", modifiers: [.command, .control]),
            .toggleRightSidebarMode: KeyboardShortcut(key: "l", modifiers: [.command, .shift]),
            .swapSidebars: KeyboardShortcut(key: "x", modifiers: [.command, .shift]),
            .undoLastHighlight: KeyboardShortcut(key: "z", modifiers: [.command]),
            .redoLastHighlight: KeyboardShortcut(key: "z", modifiers: [.command, .shift]),
        ])
    }

    var appearance: Appearance
    var reader: Reader
    var annotations: Annotations
    var shortcuts: Shortcuts
    var layout: Layout

    init(
        appearance: Appearance = .default,
        reader: Reader = .default,
        annotations: Annotations = .default,
        shortcuts: Shortcuts = .default,
        layout: Layout = .default
    ) {
        self.appearance = appearance
        self.reader = reader
        self.annotations = annotations
        self.shortcuts = shortcuts
        self.layout = layout
    }

    static let `default` = AppConfiguration(
        appearance: .default,
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
        case "space":
            " "
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
        case " ":
            "space"
        default:
            characters
        }

        return normalizedKey == key
    }

    var serializedValue: String {
        let orderedModifiers = KeyboardShortcutModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.rawValue)
        let serializedKey = key == " " ? "space" : key
        return (orderedModifiers + [serializedKey]).joined(separator: "+")
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

        let normalizedKey = key == "space" ? "space" : key
        return KeyboardShortcut(key: normalizedKey, modifiers: modifiers)
    }

    private static func isSupportedKeyToken(_ token: String) -> Bool {
        token.count == 1 || token == "escape" || token == "space"
    }
}

enum AppConfigurationError: LocalizedError {
    case invalidLine(Int, String)
    case invalidBoolean(String)
    case invalidAppearanceMode(String)
    case invalidLightTheme(String)
    case invalidDarkTheme(String)
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
        case let .invalidAppearanceMode(value):
            "Invalid appearance mode in config: \(value)"
        case let .invalidLightTheme(value):
            "Invalid light theme in config: \(value)"
        case let .invalidDarkTheme(value):
            "Invalid dark theme in config: \(value)"
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

[appearance]
mode = "system"
light_theme = "normal"
dark_theme = "rose_pine_moon"

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
show_recent_files_in_sidebar = true

[shortcuts]
highlight_selection = "a"
exit_highlight_mode = "escape"
toggle_night_mode = "i"
save_annotations = "command+s"
copy_highlights_markdown = "command+shift+e"
remove_highlight = "d"
highlight_color_pink = "command+shift+p"
highlight_color_yellow = "command+shift+y"
highlight_color_green = "command+control+g"
toggle_left_sidebar = "command+b"
toggle_right_sidebar = "command+option+b"
use_sidebar_tabs = "command+shift+1"
use_titlebar_tabs = "command+shift+2"
close_current_tab = "command+w"
previous_tab = "command+shift+["
next_tab = "command+shift+]"
fit_height = "command+9"
fit_width = "command+0"
zoom_in = "command+="
zoom_out = "command+-"
single_page = "command+1"
single_page_continuous = "command+2"
two_up = "command+3"
two_up_continuous = "command+4"
page_down = "j"
page_up = "k"
half_page_down = "control+d"
half_page_up = "control+u"
go_to_first_page = "g"
go_to_last_page = "shift+g"
navigate_back = "command+["
navigate_forward = "command+]"
find_next_match = "command+g"
find_previous_match = "command+shift+g"
goto_page = "command+option+g"
show_recent_files_palette = "command+shift+space"
open_containing_folder = "command+r"
reopen_last_closed = "command+shift+t"
new_window = "command+shift+n"
toggle_all_pages_overview = "command+shift+o"
toggle_demo_mode = "command+l"
toggle_immersive_mode = "command+control+l"
toggle_reader_split = "command+control+\\"
toggle_right_sidebar_mode = "command+shift+l"
swap_sidebars = "command+shift+x"
undo_last_highlight = "command+z"
redo_last_highlight = "command+shift+z"
"""

    static func render(_ configuration: AppConfiguration) -> String {
        """
# SlatePDF configuration
# Location: ~/Library/Application Support/SlatePDF/config.toml

[appearance]
mode = "\(configuration.appearance.mode.rawValue)"
light_theme = "\(configuration.appearance.lightTheme.rawValue)"
dark_theme = "\(configuration.appearance.darkTheme.rawValue)"

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
show_recent_files_in_sidebar = \(configuration.layout.showRecentFilesInSidebar ? "true" : "false")

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
fit_height = "\(serializedShortcut(.fitHeight, configuration: configuration))"
fit_width = "\(serializedShortcut(.fitWidth, configuration: configuration))"
zoom_in = "\(serializedShortcut(.zoomIn, configuration: configuration))"
zoom_out = "\(serializedShortcut(.zoomOut, configuration: configuration))"
single_page = "\(serializedShortcut(.singlePage, configuration: configuration))"
single_page_continuous = "\(serializedShortcut(.singlePageContinuous, configuration: configuration))"
two_up = "\(serializedShortcut(.twoUp, configuration: configuration))"
two_up_continuous = "\(serializedShortcut(.twoUpContinuous, configuration: configuration))"
page_down = "\(serializedShortcut(.pageDown, configuration: configuration))"
page_up = "\(serializedShortcut(.pageUp, configuration: configuration))"
half_page_down = "\(serializedShortcut(.halfPageDown, configuration: configuration))"
half_page_up = "\(serializedShortcut(.halfPageUp, configuration: configuration))"
go_to_first_page = "\(serializedShortcut(.goToFirstPage, configuration: configuration))"
go_to_last_page = "\(serializedShortcut(.goToLastPage, configuration: configuration))"
navigate_back = "\(serializedShortcut(.navigateBack, configuration: configuration))"
navigate_forward = "\(serializedShortcut(.navigateForward, configuration: configuration))"
find_next_match = "\(serializedShortcut(.findNextMatch, configuration: configuration))"
find_previous_match = "\(serializedShortcut(.findPreviousMatch, configuration: configuration))"
goto_page = "\(serializedShortcut(.gotoPage, configuration: configuration))"
show_recent_files_palette = "\(serializedShortcut(.showRecentFilesPalette, configuration: configuration))"
open_containing_folder = "\(serializedShortcut(.openContainingFolder, configuration: configuration))"
reopen_last_closed = "\(serializedShortcut(.reopenLastClosed, configuration: configuration))"
new_window = "\(serializedShortcut(.newWindow, configuration: configuration))"
toggle_all_pages_overview = "\(serializedShortcut(.toggleAllPagesOverview, configuration: configuration))"
toggle_demo_mode = "\(serializedShortcut(.toggleDemoMode, configuration: configuration))"
toggle_immersive_mode = "\(serializedShortcut(.toggleImmersiveMode, configuration: configuration))"
toggle_reader_split = "\(serializedShortcut(.toggleReaderSplit, configuration: configuration))"
toggle_right_sidebar_mode = "\(serializedShortcut(.toggleRightSidebarMode, configuration: configuration))"
swap_sidebars = "\(serializedShortcut(.swapSidebars, configuration: configuration))"
undo_last_highlight = "\(serializedShortcut(.undoLastHighlight, configuration: configuration))"
redo_last_highlight = "\(serializedShortcut(.redoLastHighlight, configuration: configuration))"
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
        case ("appearance", "mode"):
            let value = parseString(rawValue)
            guard let mode = AppearanceMode(rawValue: value) else {
                throw AppConfigurationError.invalidAppearanceMode(value)
            }
            configuration.appearance.mode = mode
        case ("appearance", "light_theme"):
            let value = parseString(rawValue)
            guard let theme = LightTheme(rawValue: value) else {
                throw AppConfigurationError.invalidLightTheme(value)
            }
            configuration.appearance.lightTheme = theme
        case ("appearance", "dark_theme"):
            let value = parseString(rawValue)
            guard let theme = DarkTheme(rawValue: value) else {
                throw AppConfigurationError.invalidDarkTheme(value)
            }
            configuration.appearance.darkTheme = theme
        case ("appearance", "theme"):
            let value = parseString(rawValue)
            switch value {
            case "system":
                configuration.appearance.mode = .system
            case LightTheme.rosePineDawn.rawValue:
                configuration.appearance.mode = .light
                configuration.appearance.lightTheme = .rosePineDawn
            case DarkTheme.rosePineMoon.rawValue:
                configuration.appearance.mode = .dark
                configuration.appearance.darkTheme = .rosePineMoon
            default:
                throw AppConfigurationError.invalidAppearanceMode(value)
            }
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
        case ("layout", "show_recent_files_in_sidebar"):
            configuration.layout.showRecentFilesInSidebar = try parseBool(rawValue)
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
        case ("shortcuts", "fit_height"):
            try applyShortcut(rawValue, command: .fitHeight, to: &configuration)
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
        case ("shortcuts", "half_page_down"):
            try applyShortcut(rawValue, command: .halfPageDown, to: &configuration)
        case ("shortcuts", "half_page_up"):
            try applyShortcut(rawValue, command: .halfPageUp, to: &configuration)
        case ("shortcuts", "go_to_first_page"):
            try applyShortcut(rawValue, command: .goToFirstPage, to: &configuration)
        case ("shortcuts", "go_to_last_page"):
            try applyShortcut(rawValue, command: .goToLastPage, to: &configuration)
        case ("shortcuts", "navigate_back"):
            try applyShortcut(rawValue, command: .navigateBack, to: &configuration)
        case ("shortcuts", "navigate_forward"):
            try applyShortcut(rawValue, command: .navigateForward, to: &configuration)
        case ("shortcuts", "find_next_match"):
            try applyShortcut(rawValue, command: .findNextMatch, to: &configuration)
        case ("shortcuts", "find_previous_match"):
            try applyShortcut(rawValue, command: .findPreviousMatch, to: &configuration)
        case ("shortcuts", "goto_page"):
            try applyShortcut(rawValue, command: .gotoPage, to: &configuration)
        case ("shortcuts", "show_recent_files_palette"):
            try applyShortcut(rawValue, command: .showRecentFilesPalette, to: &configuration)
        case ("shortcuts", "open_containing_folder"):
            try applyShortcut(rawValue, command: .openContainingFolder, to: &configuration)
        case ("shortcuts", "reopen_last_closed"):
            try applyShortcut(rawValue, command: .reopenLastClosed, to: &configuration)
        case ("shortcuts", "new_window"):
            try applyShortcut(rawValue, command: .newWindow, to: &configuration)
        case ("shortcuts", "toggle_all_pages_overview"):
            try applyShortcut(rawValue, command: .toggleAllPagesOverview, to: &configuration)
        case ("shortcuts", "toggle_demo_mode"):
            try applyShortcut(rawValue, command: .toggleDemoMode, to: &configuration)
        case ("shortcuts", "toggle_immersive_mode"):
            try applyShortcut(rawValue, command: .toggleImmersiveMode, to: &configuration)
        case ("shortcuts", "toggle_reader_split"):
            try applyShortcut(rawValue, command: .toggleReaderSplit, to: &configuration)
        case ("shortcuts", "toggle_right_sidebar_mode"), ("shortcuts", "toggle_left_tabs_mode"):
            try applyShortcut(rawValue, command: .toggleRightSidebarMode, to: &configuration)
        case ("shortcuts", "swap_sidebars"):
            try applyShortcut(rawValue, command: .swapSidebars, to: &configuration)
        case ("shortcuts", "undo_last_highlight"):
            try applyShortcut(rawValue, command: .undoLastHighlight, to: &configuration)
        case ("shortcuts", "redo_last_highlight"):
            try applyShortcut(rawValue, command: .redoLastHighlight, to: &configuration)
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
            "[appearance]",
            "mode",
            "light_theme",
            "dark_theme",
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
            "show_recent_files_in_sidebar",
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
            "fit_height",
            "fit_width",
            "single_page",
            "single_page_continuous",
            "two_up",
            "two_up_continuous",
            "zoom_in",
            "zoom_out",
            "page_down",
            "page_up",
            "half_page_down",
            "half_page_up",
            "go_to_first_page",
            "go_to_last_page",
            "navigate_back",
            "navigate_forward",
            "find_next_match",
            "find_previous_match",
            "goto_page",
            "show_recent_files_palette",
            "open_containing_folder",
            "reopen_last_closed",
            "new_window",
            "toggle_all_pages_overview",
            "toggle_demo_mode",
            "toggle_immersive_mode",
            "toggle_reader_split",
            "toggle_right_sidebar_mode",
            "swap_sidebars",
            "undo_last_highlight",
            "redo_last_highlight",
        ]

        var configuration = try parser.parse(existingContent)
        let legacyRemoveHighlight = KeyboardShortcut(key: "d", modifiers: [.command, .shift])
        let legacyGreenHighlight = KeyboardShortcut(key: "g", modifiers: [.command, .shift])
        let legacyImmersiveMode = KeyboardShortcut(key: "l", modifiers: [.command, .option])
        var didMigrate = false
        if configuration.shortcuts.bindings[.removeHighlight] == legacyRemoveHighlight {
            configuration.shortcuts.bindings[.removeHighlight] = KeyboardShortcut(key: "d", modifiers: [])
            didMigrate = true
        }
        if existingContent.contains("find_previous_match") == false,
           configuration.shortcuts.bindings[.highlightColorGreen] == legacyGreenHighlight {
            configuration.shortcuts.bindings[.highlightColorGreen] =
                AppConfiguration.default.shortcuts.bindings[.highlightColorGreen]
                ?? KeyboardShortcut(key: "g", modifiers: [.command, .control])
            didMigrate = true
        }
        if configuration.shortcuts.bindings[.toggleImmersiveMode] == legacyImmersiveMode {
            configuration.shortcuts.bindings[.toggleImmersiveMode] =
                AppConfiguration.default.shortcuts.bindings[.toggleImmersiveMode]
                ?? KeyboardShortcut(key: "l", modifiers: [.command, .control])
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
