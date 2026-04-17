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

    struct Shortcuts: Equatable, Sendable {
        var bindings: [ShortcutCommand: KeyboardShortcut]

        static let `default` = Shortcuts(bindings: [
            .toggleLeftSidebar: KeyboardShortcut(key: "b", modifiers: [.command]),
            .toggleRightSidebar: KeyboardShortcut(key: "b", modifiers: [.command, .option]),
            .useSidebarTabs: KeyboardShortcut(key: "1", modifiers: [.command, .shift]),
            .useTitlebarTabs: KeyboardShortcut(key: "2", modifiers: [.command, .shift]),
            .closeCurrentTab: KeyboardShortcut(key: "w", modifiers: [.command]),
            .previousTab: KeyboardShortcut(key: "[", modifiers: [.command, .shift]),
            .nextTab: KeyboardShortcut(key: "]", modifiers: [.command, .shift]),
            .fitWidth: KeyboardShortcut(key: "0", modifiers: [.command]),
            .singlePage: KeyboardShortcut(key: "1", modifiers: [.command]),
            .singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command]),
            .twoUp: KeyboardShortcut(key: "3", modifiers: [.command]),
            .twoUpContinuous: KeyboardShortcut(key: "4", modifiers: [.command]),
        ])
    }

    var reader: Reader
    var shortcuts: Shortcuts

    static let `default` = AppConfiguration(
        reader: .default,
        shortcuts: .default
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

        guard let key = tokens.last, key.count == 1 else {
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
}

enum AppConfigurationError: LocalizedError {
    case invalidLine(Int, String)
    case invalidBoolean(String)
    case invalidDisplayMode(String)
    case invalidShortcut(String)

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

[shortcuts]
toggle_left_sidebar = "command+b"
toggle_right_sidebar = "command+option+b"
use_sidebar_tabs = "command+shift+1"
use_titlebar_tabs = "command+shift+2"
close_current_tab = "command+w"
previous_tab = "command+shift+["
next_tab = "command+shift+]"
fit_width = "command+0"
single_page = "command+1"
single_page_continuous = "command+2"
two_up = "command+3"
two_up_continuous = "command+4"
"""

    static func render(_ configuration: AppConfiguration) -> String {
        """
# SlatePDF configuration
# Location: ~/Library/Application Support/SlatePDF/config.toml

[reader]
default_display_mode = "\(configuration.reader.defaultDisplayMode.rawValue)"
fit_width_on_open = \(configuration.reader.fitWidthOnOpen ? "true" : "false")

[shortcuts]
toggle_left_sidebar = "\(configuration.shortcuts.bindings[.toggleLeftSidebar]?.serializedValue ?? "command+b")"
toggle_right_sidebar = "\(configuration.shortcuts.bindings[.toggleRightSidebar]?.serializedValue ?? "command+option+b")"
use_sidebar_tabs = "\(configuration.shortcuts.bindings[.useSidebarTabs]?.serializedValue ?? "command+shift+1")"
use_titlebar_tabs = "\(configuration.shortcuts.bindings[.useTitlebarTabs]?.serializedValue ?? "command+shift+2")"
close_current_tab = "\(configuration.shortcuts.bindings[.closeCurrentTab]?.serializedValue ?? "command+w")"
previous_tab = "\(configuration.shortcuts.bindings[.previousTab]?.serializedValue ?? "command+shift+[")"
next_tab = "\(configuration.shortcuts.bindings[.nextTab]?.serializedValue ?? "command+shift+]")"
fit_width = "\(configuration.shortcuts.bindings[.fitWidth]?.serializedValue ?? "command+0")"
single_page = "\(configuration.shortcuts.bindings[.singlePage]?.serializedValue ?? "command+1")"
single_page_continuous = "\(configuration.shortcuts.bindings[.singlePageContinuous]?.serializedValue ?? "command+2")"
two_up = "\(configuration.shortcuts.bindings[.twoUp]?.serializedValue ?? "command+3")"
two_up_continuous = "\(configuration.shortcuts.bindings[.twoUpContinuous]?.serializedValue ?? "command+4")"
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
        case ("reader", "default_display_mode"):
            let value = parseString(rawValue)
            guard let displayMode = ReaderDisplayMode(rawValue: value) else {
                throw AppConfigurationError.invalidDisplayMode(value)
            }
            configuration.reader.defaultDisplayMode = displayMode
        case ("reader", "fit_width_on_open"):
            configuration.reader.fitWidthOnOpen = try parseBool(rawValue)
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

    private func bootstrapIfNeeded() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try AppConfigurationFile.defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
        let requiredShortcutKeys = [
            "toggle_left_sidebar",
            "toggle_right_sidebar",
            "use_sidebar_tabs",
            "use_titlebar_tabs",
            "close_current_tab",
            "previous_tab",
            "next_tab",
        ]

        guard requiredShortcutKeys.contains(where: { existingContent.contains($0) == false }) else { return }

        let configuration = try parser.parse(existingContent)
        try AppConfigurationFile.render(configuration).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlatePDF", isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}
