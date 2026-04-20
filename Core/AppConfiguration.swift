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
highlight_selection = "\(configuration.shortcuts.bindings[.highlightSelection]?.serializedValue ?? "a")"
exit_highlight_mode = "\(configuration.shortcuts.bindings[.exitHighlightMode]?.serializedValue ?? "escape")"
toggle_night_mode = "\(configuration.shortcuts.bindings[.toggleNightMode]?.serializedValue ?? "i")"
save_annotations = "\(configuration.shortcuts.bindings[.saveAnnotations]?.serializedValue ?? "command+s")"
remove_highlight = "\(configuration.shortcuts.bindings[.removeHighlight]?.serializedValue ?? "d")"
highlight_color_pink = "\(configuration.shortcuts.bindings[.highlightColorPink]?.serializedValue ?? "command+shift+p")"
highlight_color_yellow = "\(configuration.shortcuts.bindings[.highlightColorYellow]?.serializedValue ?? "command+shift+y")"
highlight_color_green = "\(configuration.shortcuts.bindings[.highlightColorGreen]?.serializedValue ?? "command+shift+g")"
toggle_left_sidebar = "\(configuration.shortcuts.bindings[.toggleLeftSidebar]?.serializedValue ?? "command+b")"
toggle_right_sidebar = "\(configuration.shortcuts.bindings[.toggleRightSidebar]?.serializedValue ?? "command+option+b")"
use_sidebar_tabs = "\(configuration.shortcuts.bindings[.useSidebarTabs]?.serializedValue ?? "command+shift+1")"
use_titlebar_tabs = "\(configuration.shortcuts.bindings[.useTitlebarTabs]?.serializedValue ?? "command+shift+2")"
close_current_tab = "\(configuration.shortcuts.bindings[.closeCurrentTab]?.serializedValue ?? "command+w")"
previous_tab = "\(configuration.shortcuts.bindings[.previousTab]?.serializedValue ?? "command+shift+[")"
next_tab = "\(configuration.shortcuts.bindings[.nextTab]?.serializedValue ?? "command+shift+]")"
fit_width = "\(configuration.shortcuts.bindings[.fitWidth]?.serializedValue ?? "command+0")"
zoom_in = "\(configuration.shortcuts.bindings[.zoomIn]?.serializedValue ?? "command+=")"
zoom_out = "\(configuration.shortcuts.bindings[.zoomOut]?.serializedValue ?? "command+-")"
single_page = "\(configuration.shortcuts.bindings[.singlePage]?.serializedValue ?? "command+1")"
single_page_continuous = "\(configuration.shortcuts.bindings[.singlePageContinuous]?.serializedValue ?? "command+2")"
two_up = "\(configuration.shortcuts.bindings[.twoUp]?.serializedValue ?? "command+3")"
two_up_continuous = "\(configuration.shortcuts.bindings[.twoUpContinuous]?.serializedValue ?? "command+4")"
page_down = "\(configuration.shortcuts.bindings[.pageDown]?.serializedValue ?? "j")"
page_up = "\(configuration.shortcuts.bindings[.pageUp]?.serializedValue ?? "k")"
navigate_back = "\(configuration.shortcuts.bindings[.navigateBack]?.serializedValue ?? "command+[")"
navigate_forward = "\(configuration.shortcuts.bindings[.navigateForward]?.serializedValue ?? "command+]")"
goto_page = "\(configuration.shortcuts.bindings[.gotoPage]?.serializedValue ?? "command+option+g")"
reopen_last_closed = "\(configuration.shortcuts.bindings[.reopenLastClosed]?.serializedValue ?? "command+shift+t")"
new_window = "\(configuration.shortcuts.bindings[.newWindow]?.serializedValue ?? "command+shift+n")"
toggle_all_pages_overview = "\(configuration.shortcuts.bindings[.toggleAllPagesOverview]?.serializedValue ?? "command+shift+o")"
toggle_reader_split = "\(configuration.shortcuts.bindings[.toggleReaderSplit]?.serializedValue ?? "command+control+\\")"
toggle_right_sidebar_mode = "\(configuration.shortcuts.bindings[.toggleRightSidebarMode]?.serializedValue ?? "command+shift+l")"
swap_sidebars = "\(configuration.shortcuts.bindings[.swapSidebars]?.serializedValue ?? "command+shift+x")"
undo_last_highlight = "\(configuration.shortcuts.bindings[.undoLastHighlight]?.serializedValue ?? "command+z")"
"""
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
            configuration.shortcuts.bindings[.highlightSelection] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "exit_highlight_mode"):
            configuration.shortcuts.bindings[.exitHighlightMode] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_night_mode"):
            configuration.shortcuts.bindings[.toggleNightMode] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "save_annotations"):
            configuration.shortcuts.bindings[.saveAnnotations] = try KeyboardShortcut.parse(parseString(rawValue))
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
            configuration.shortcuts.bindings[.removeHighlight] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "highlight_color_pink"):
            configuration.shortcuts.bindings[.highlightColorPink] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "highlight_color_yellow"):
            configuration.shortcuts.bindings[.highlightColorYellow] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "highlight_color_green"):
            configuration.shortcuts.bindings[.highlightColorGreen] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_left_sidebar"):
            configuration.shortcuts.bindings[.toggleLeftSidebar] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_right_sidebar"):
            configuration.shortcuts.bindings[.toggleRightSidebar] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "use_sidebar_tabs"):
            configuration.shortcuts.bindings[.useSidebarTabs] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "use_titlebar_tabs"):
            configuration.shortcuts.bindings[.useTitlebarTabs] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "close_current_tab"):
            configuration.shortcuts.bindings[.closeCurrentTab] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "previous_tab"):
            configuration.shortcuts.bindings[.previousTab] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "next_tab"):
            configuration.shortcuts.bindings[.nextTab] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "fit_width"):
            configuration.shortcuts.bindings[.fitWidth] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "single_page"):
            configuration.shortcuts.bindings[.singlePage] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "single_page_continuous"):
            configuration.shortcuts.bindings[.singlePageContinuous] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "two_up"):
            configuration.shortcuts.bindings[.twoUp] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "two_up_continuous"):
            configuration.shortcuts.bindings[.twoUpContinuous] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "zoom_in"):
            configuration.shortcuts.bindings[.zoomIn] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "zoom_out"):
            configuration.shortcuts.bindings[.zoomOut] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "page_down"):
            configuration.shortcuts.bindings[.pageDown] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "page_up"):
            configuration.shortcuts.bindings[.pageUp] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "navigate_back"):
            configuration.shortcuts.bindings[.navigateBack] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "navigate_forward"):
            configuration.shortcuts.bindings[.navigateForward] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "goto_page"):
            configuration.shortcuts.bindings[.gotoPage] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "reopen_last_closed"):
            configuration.shortcuts.bindings[.reopenLastClosed] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "new_window"):
            configuration.shortcuts.bindings[.newWindow] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_all_pages_overview"):
            configuration.shortcuts.bindings[.toggleAllPagesOverview] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_reader_split"):
            configuration.shortcuts.bindings[.toggleReaderSplit] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "toggle_right_sidebar_mode"), ("shortcuts", "toggle_left_tabs_mode"):
            configuration.shortcuts.bindings[.toggleRightSidebarMode] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "swap_sidebars"):
            configuration.shortcuts.bindings[.swapSidebars] = try KeyboardShortcut.parse(parseString(rawValue))
        case ("shortcuts", "undo_last_highlight"):
            configuration.shortcuts.bindings[.undoLastHighlight] = try KeyboardShortcut.parse(parseString(rawValue))
        default:
            break
        }
    }

    private func parseString(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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
