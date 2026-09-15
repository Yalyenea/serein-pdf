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

    var toggled: LightTheme {
        switch self {
        case .normal:
            .rosePineDawn
        case .rosePineDawn:
            .normal
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

    var toggled: DarkTheme {
        switch self {
        case .normal:
            .rosePineMoon
        case .rosePineMoon:
            .normal
        }
    }
}

enum ReadingFocusWidthMode: String, CaseIterable, Codable, Sendable {
    case page
    case column
    case custom

    var menuTitle: String {
        switch self {
        case .page:
            "Page Width"
        case .column:
            "Column (½ Page)"
        case .custom:
            "Custom"
        }
    }
}

struct ReadingFocusSettings: Equatable, Sendable {
    static let minimumCustomWidthRatio: CGFloat = 0.3
    static let maximumCustomWidthRatio: CGFloat = 1
    static let minimumHeight: CGFloat = 48
    static let maximumHeight: CGFloat = 240
    static let `default` = ReadingFocusSettings(
        widthMode: .page,
        customWidthRatio: 0.72,
        height: 96
    )

    var widthMode: ReadingFocusWidthMode
    var customWidthRatio: CGFloat
    var height: CGFloat
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
        var readingFocus: ReadingFocusSettings

        init(
            defaultDisplayMode: ReaderDisplayMode,
            fitWidthOnOpen: Bool,
            readingFocus: ReadingFocusSettings = .default
        ) {
            self.defaultDisplayMode = defaultDisplayMode
            self.fitWidthOnOpen = fitWidthOnOpen
            self.readingFocus = readingFocus
        }

        static let `default` = Reader(
            defaultDisplayMode: .singlePageContinuous,
            fitWidthOnOpen: false,
            readingFocus: .default
        )
    }

    struct Annotations: Equatable, Sendable {
        var autoSavePolicy: AnnotationSavePolicy

        static let `default` = Annotations(autoSavePolicy: .default)
    }

    struct Layout: Equatable, Sendable {
        static let minimumFloatingOutlineHeight: CGFloat = 180
        static let maximumFloatingOutlineHeight: CGFloat = 720

        var leftSidebarWidth: CGFloat
        var leftSidebarMinWidth: CGFloat
        var leftSidebarMaxWidth: CGFloat
        var rightSidebarWidth: CGFloat
        var rightSidebarMinWidth: CGFloat
        var rightSidebarMaxWidth: CGFloat
        var sidebarsSwapped: Bool
        var showRecentFilesInSidebar: Bool = true
        var sidebarOpacity: CGFloat = 0.48
        var floatingOutlineHeight: CGFloat = 360

        static let `default` = Layout(
            leftSidebarWidth: 220,
            leftSidebarMinWidth: 36,
            leftSidebarMaxWidth: 520,
            rightSidebarWidth: 320,
            rightSidebarMinWidth: 120,
            rightSidebarMaxWidth: 720,
            sidebarsSwapped: false,
            showRecentFilesInSidebar: true,
            sidebarOpacity: 0.48,
            floatingOutlineHeight: 360
        )
    }

    struct Library: Equatable, Sendable {
        var folderURLs: [URL]

        static let `default` = Library(folderURLs: [])
    }

    struct Access: Equatable, Sendable {
        var rootURLs: [URL]
        var rootBookmarkData: [String: Data]

        static let `default` = Access(
            rootURLs: [URL(fileURLWithPath: "/Users", isDirectory: true)],
            rootBookmarkData: [:]
        )
    }

    struct Updates: Equatable, Sendable {
        /// Check GitHub Releases shortly after launch.
        var autoCheck: Bool
        /// Classic/fine-grained PAT for private repos (repo Contents read + release assets).
        var githubToken: String

        static let `default` = Updates(
            autoCheck: true,
            githubToken: ""
        )
    }

    struct Integrations: Equatable, Sendable {
        var codexEnabled: Bool

        static let `default` = Integrations(codexEnabled: true)
    }

    struct Shortcuts: Equatable, Sendable {
        var bindings: [ShortcutCommand: KeyboardShortcut]

        static let `default` = Shortcuts(bindings: [
            .highlightSelection: KeyboardShortcut(key: "a", modifiers: []),
            .underlineSelection: KeyboardShortcut(key: "u", modifiers: []),
            .strikethroughSelection: KeyboardShortcut(key: "s", modifiers: []),
            .addComment: KeyboardShortcut(key: "m", modifiers: [.command, .option]),
            .exitHighlightMode: KeyboardShortcut(key: "escape", modifiers: []),
            .toggleNightMode: KeyboardShortcut(key: "i", modifiers: []),
            .toggleReadingFocus: KeyboardShortcut(key: "f", modifiers: []),
            .adjustReadingFocus: KeyboardShortcut(key: "f", modifiers: [.option]),
            .toggleHorizontalPanLock: KeyboardShortcut(key: "l", modifiers: []),
            .saveAnnotations: KeyboardShortcut(key: "s", modifiers: [.command]),
            .copyHighlightsMarkdown: KeyboardShortcut(key: "e", modifiers: [.command, .shift]),
            .copyCurrentPDFPath: KeyboardShortcut(key: "c", modifiers: [.command, .shift]),
            .copyCurrentPageAsImage: KeyboardShortcut(key: "c", modifiers: [.command, .option]),
            .sendContextToCodex: KeyboardShortcut(key: "c", modifiers: [.command, .control]),
            .sendCurrentPDFToCodex: KeyboardShortcut(key: "c", modifiers: [.command, .control, .shift]),
            .removeHighlight: KeyboardShortcut(key: "d", modifiers: []),
            .highlightColorPink: KeyboardShortcut(key: "p", modifiers: [.command, .shift]),
            .highlightColorYellow: KeyboardShortcut(key: "y", modifiers: [.command, .shift]),
            .highlightColorGreen: KeyboardShortcut(key: "g", modifiers: [.command, .control]),
            .toggleLeftSidebar: KeyboardShortcut(key: "b", modifiers: [.command]),
            .toggleRightSidebar: KeyboardShortcut(key: "b", modifiers: [.command, .option]),
            .useSidebarTabs: KeyboardShortcut(key: "1", modifiers: [.command, .shift]),
            .useTitlebarTabs: KeyboardShortcut(key: "2", modifiers: [.command, .shift]),
            .closeCurrentTab: KeyboardShortcut(key: "w", modifiers: [.command]),
            .closeCurrentWindow: KeyboardShortcut(key: "w", modifiers: [.command, .shift]),
            .previousTab: KeyboardShortcut(key: "[", modifiers: [.command, .shift]),
            .nextTab: KeyboardShortcut(key: "]", modifiers: [.command, .shift]),
            .fitHeight: KeyboardShortcut(key: "9", modifiers: [.command]),
            .fitWidth: KeyboardShortcut(key: "0", modifiers: [.command]),
            .fitTextWidth: KeyboardShortcut(key: "0", modifiers: [.command, .option]),
            .zoomIn: KeyboardShortcut(key: "=", modifiers: [.command]),
            .zoomOut: KeyboardShortcut(key: "-", modifiers: [.command]),
            .singlePage: KeyboardShortcut(key: "1", modifiers: [.command]),
            .singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command]),
            .twoUp: KeyboardShortcut(key: "3", modifiers: [.command]),
            .twoUpContinuous: KeyboardShortcut(key: "4", modifiers: [.command]),
            .toggleDisplayModeContinuity: KeyboardShortcut(key: "c", modifiers: []),
            .pageDown: KeyboardShortcut(key: "j", modifiers: []),
            .pageUp: KeyboardShortcut(key: "k", modifiers: []),
            .halfPageDown: KeyboardShortcut(key: "d", modifiers: [.control]),
            .halfPageUp: KeyboardShortcut(key: "u", modifiers: [.control]),
            .goToFirstPage: KeyboardShortcut(key: "g", modifiers: []),
            .goToLastPage: KeyboardShortcut(key: "g", modifiers: [.shift]),
            .navigateBack: KeyboardShortcut(key: "[", modifiers: [.command]),
            .navigateForward: KeyboardShortcut(key: "]", modifiers: [.command]),
            .findAllOpen: KeyboardShortcut(key: "f", modifiers: [.command, .shift]),
            .findNextMatch: KeyboardShortcut(key: "g", modifiers: [.command]),
            .findPreviousMatch: KeyboardShortcut(key: "g", modifiers: [.command, .shift]),
            .gotoPage: KeyboardShortcut(key: "g", modifiers: [.command, .option]),
            .showRecentFilesPalette: KeyboardShortcut(key: "space", modifiers: [.command, .shift]),
            .openContainingFolder: KeyboardShortcut(key: "r", modifiers: [.command]),
            .reopenLastClosed: KeyboardShortcut(key: "t", modifiers: [.command, .shift]),
            .newBlankTab: KeyboardShortcut(key: "t", modifiers: [.command]),
            .showAllTabs: KeyboardShortcut(key: "tab", modifiers: [.control]),
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
    var library: Library
    var access: Access
    var updates: Updates
    var integrations: Integrations

    init(
        appearance: Appearance = .default,
        reader: Reader = .default,
        annotations: Annotations = .default,
        shortcuts: Shortcuts = .default,
        layout: Layout = .default,
        library: Library = .default,
        access: Access = .default,
        updates: Updates = .default,
        integrations: Integrations = .default
    ) {
        self.appearance = appearance
        self.reader = reader
        self.annotations = annotations
        self.shortcuts = shortcuts
        self.layout = layout
        self.library = library
        self.access = access
        self.updates = updates
        self.integrations = integrations
    }

    static let `default` = AppConfiguration(
        appearance: .default,
        reader: .default,
        annotations: .default,
        shortcuts: .default,
        layout: .default,
        library: .default,
        access: .default,
        updates: .default,
        integrations: .default
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
        case "tab":
            "\t"
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
        case "\t":
            "tab"
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

    var displayString: String {
        let modifierPrefix = KeyboardShortcutModifier.allCases.compactMap { modifier -> String? in
            guard modifiers.contains(modifier) else { return nil }
            switch modifier {
            case .command:
                return "⌘"
            case .shift:
                return "⇧"
            case .option:
                return "⌥"
            case .control:
                return "⌃"
            }
        }.joined()

        let keyDisplay: String
        switch key {
        case "escape":
            keyDisplay = "Esc"
        case "space":
            keyDisplay = "Space"
        case "tab":
            keyDisplay = "Tab"
        default:
            keyDisplay = key.uppercased()
        }

        return modifierPrefix + keyDisplay
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

    static func isSupportedKeyToken(_ token: String) -> Bool {
        if token == "escape" || token == "space" || token == "tab" {
            return true
        }
        return token.count == 1 && token.unicodeScalars.allSatisfy {
            CharacterSet.controlCharacters.contains($0) == false
        }
    }
}

struct KeyboardShortcutSequence: Equatable, Sendable {
    let strokes: [KeyboardShortcut]

    init(_ strokes: [KeyboardShortcut]) {
        precondition(strokes.isEmpty == false)
        self.strokes = strokes
    }

    var displayString: String {
        strokes.map(\.displayString).joined(separator: " → ")
    }
}

enum AppConfigurationError: LocalizedError {
    case invalidLine(Int, String)
    case invalidBoolean(String)
    case invalidAppearanceMode(String)
    case invalidLightTheme(String)
    case invalidDarkTheme(String)
    case invalidDisplayMode(String)
    case invalidReadingFocusWidthMode(String)
    case invalidReadingFocusWidthRatio(String)
    case invalidReadingFocusHeight(String)
    case invalidShortcut(String)
    case invalidStringArray(String)
    case invalidAnnotationSavePolicy(String)
    case invalidWidth(String)
    case invalidOpacity(String)
    case invalidFloatingOutlineHeight(String)

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
        case let .invalidReadingFocusWidthMode(value):
            "Invalid reading focus width mode in config: \(value)"
        case let .invalidReadingFocusWidthRatio(value):
            "Invalid reading focus width ratio in config: \(value)"
        case let .invalidReadingFocusHeight(value):
            "Invalid reading focus height in config: \(value)"
        case let .invalidShortcut(value):
            "Invalid keyboard shortcut in config: \(value)"
        case let .invalidStringArray(value):
            "Invalid string array in config: \(value)"
        case let .invalidAnnotationSavePolicy(value):
            "Invalid annotation auto-save policy in config: \(value)"
        case let .invalidWidth(value):
            "Invalid sidebar width in config: \(value)"
        case let .invalidOpacity(value):
            "Invalid sidebar opacity in config: \(value)"
        case let .invalidFloatingOutlineHeight(value):
            "Invalid floating outline height in config: \(value)"
        }
    }
}

struct AppConfigurationFile {
    static let defaultContents = """
# Serein configuration
# Location: ~/Library/Application Support/Serein/config.toml

[appearance]
mode = "system"
light_theme = "normal"
dark_theme = "rose_pine_moon"

[reader]
default_display_mode = "single_page_continuous"
fit_width_on_open = false
reading_focus_width = "page"
reading_focus_custom_width = 0.72
reading_focus_height = 96

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
sidebar_opacity = 0.48
floating_outline_height = 360

[library]
folders = []

[access]
roots = ["/Users"]
root_bookmarks = []

[updates]
auto_check = true
# Required for private GitHub repos. classic PAT with repo scope, or fine-grained: Contents read + metadata.
github_token = ""

[integrations]
codex_enabled = true

[shortcuts]
highlight_selection = "a"
underline_selection = "u"
strikethrough_selection = "s"
add_comment = "command+option+m"
exit_highlight_mode = "escape"
toggle_night_mode = "i"
toggle_reading_focus = "f"
adjust_reading_focus = "option+f"
toggle_horizontal_pan_lock = "l"
# Cmd+K, Cmd+T is a built-in chord.
switch_current_theme = "none"
# Cmd+K, Cmd+O is a built-in chord.
open_library_pdf = "none"
# Cmd+K, Cmd+R is a built-in chord.
refresh_library_index = "none"
# Cmd+K, Cmd+L is a built-in chord.
open_library_settings = "none"
# Cmd+K, Cmd+S is a built-in chord.
open_shortcut_settings = "none"
save_annotations = "command+s"
# Cmd+K, Cmd+E is a built-in chord.
share_document = "none"
export_clean_copy = "none"
copy_highlights_markdown = "command+shift+e"
copy_current_pdf_path = "command+shift+c"
copy_current_page_as_image = "command+option+c"
send_context_to_codex = "command+control+c"
send_current_pdf_to_codex = "command+control+shift+c"
remove_highlight = "d"
highlight_color_pink = "command+shift+p"
highlight_color_yellow = "command+shift+y"
highlight_color_green = "command+control+g"
toggle_left_sidebar = "command+b"
toggle_right_sidebar = "command+option+b"
use_sidebar_tabs = "command+shift+1"
use_titlebar_tabs = "command+shift+2"
close_current_tab = "command+w"
close_current_window = "command+shift+w"
previous_tab = "command+shift+["
next_tab = "command+shift+]"
show_all_tabs = "control+tab"
toggle_continuous_reading = "none"
fit_height = "command+9"
fit_width = "command+0"
fit_text_width = "command+option+0"
zoom_in = "command+="
zoom_out = "command+-"
single_page = "command+1"
single_page_continuous = "command+2"
two_up = "command+3"
two_up_continuous = "command+4"
book = "none"
book_continuous = "none"
toggle_display_mode_continuity = "c"
page_down = "j"
page_up = "k"
half_page_down = "control+d"
half_page_up = "control+u"
go_to_first_page = "g"
go_to_last_page = "shift+g"
navigate_back = "command+["
navigate_forward = "command+]"
find_all_open = "command+shift+f"
find_next_match = "command+g"
find_previous_match = "command+shift+g"
goto_page = "command+option+g"
show_recent_files_palette = "command+shift+space"
open_containing_folder = "command+r"
reopen_last_closed = "command+shift+t"
new_blank_tab = "command+t"
new_window = "command+shift+n"
# Cmd+K, Cmd+M is a built-in chord.
merge_all_windows = "none"
# Cmd+K, Cmd+N is a built-in chord.
move_current_pdf_to_new_window = "none"
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
# Serein configuration
# Location: ~/Library/Application Support/Serein/config.toml

[appearance]
mode = "\(configuration.appearance.mode.rawValue)"
light_theme = "\(configuration.appearance.lightTheme.rawValue)"
dark_theme = "\(configuration.appearance.darkTheme.rawValue)"

[reader]
default_display_mode = "\(configuration.reader.defaultDisplayMode.rawValue)"
fit_width_on_open = \(configuration.reader.fitWidthOnOpen ? "true" : "false")
reading_focus_width = "\(configuration.reader.readingFocus.widthMode.rawValue)"
reading_focus_custom_width = \(serializedDecimal(configuration.reader.readingFocus.customWidthRatio))
reading_focus_height = \(Int(configuration.reader.readingFocus.height.rounded()))

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
sidebar_opacity = \(serializedDecimal(configuration.layout.sidebarOpacity))
floating_outline_height = \(Int(configuration.layout.floatingOutlineHeight.rounded()))

[library]
folders = \(serializedPathArray(configuration.library.folderURLs))

[access]
roots = \(serializedPathArray(configuration.access.rootURLs))
root_bookmarks = \(serializedBookmarkArray(configuration.access.rootBookmarkData))

[updates]
auto_check = \(configuration.updates.autoCheck ? "true" : "false")
github_token = "\(escapedTOMLString(configuration.updates.githubToken))"

[integrations]
codex_enabled = \(configuration.integrations.codexEnabled ? "true" : "false")

[shortcuts]
highlight_selection = "\(serializedShortcut(.highlightSelection, configuration: configuration))"
underline_selection = "\(serializedShortcut(.underlineSelection, configuration: configuration))"
strikethrough_selection = "\(serializedShortcut(.strikethroughSelection, configuration: configuration))"
add_comment = "\(serializedShortcut(.addComment, configuration: configuration))"
exit_highlight_mode = "\(serializedShortcut(.exitHighlightMode, configuration: configuration))"
toggle_night_mode = "\(serializedShortcut(.toggleNightMode, configuration: configuration))"
toggle_reading_focus = "\(serializedShortcut(.toggleReadingFocus, configuration: configuration))"
adjust_reading_focus = "\(serializedShortcut(.adjustReadingFocus, configuration: configuration))"
toggle_horizontal_pan_lock = "\(serializedShortcut(.toggleHorizontalPanLock, configuration: configuration))"
switch_current_theme = "\(serializedShortcut(.switchCurrentTheme, configuration: configuration))"
open_library_pdf = "\(serializedShortcut(.openLibraryPDF, configuration: configuration))"
refresh_library_index = "\(serializedShortcut(.refreshLibraryIndex, configuration: configuration))"
open_library_settings = "\(serializedShortcut(.openLibrarySettings, configuration: configuration))"
open_shortcut_settings = "\(serializedShortcut(.openShortcutSettings, configuration: configuration))"
save_annotations = "\(serializedShortcut(.saveAnnotations, configuration: configuration))"
share_document = "\(serializedShortcut(.shareDocument, configuration: configuration))"
export_clean_copy = "\(serializedShortcut(.exportCleanCopy, configuration: configuration))"
copy_highlights_markdown = "\(serializedShortcut(.copyHighlightsMarkdown, configuration: configuration))"
copy_current_pdf_path = "\(serializedShortcut(.copyCurrentPDFPath, configuration: configuration))"
copy_current_page_as_image = "\(serializedShortcut(.copyCurrentPageAsImage, configuration: configuration))"
send_context_to_codex = "\(serializedShortcut(.sendContextToCodex, configuration: configuration))"
send_current_pdf_to_codex = "\(serializedShortcut(.sendCurrentPDFToCodex, configuration: configuration))"
remove_highlight = "\(serializedShortcut(.removeHighlight, configuration: configuration))"
highlight_color_pink = "\(serializedShortcut(.highlightColorPink, configuration: configuration))"
highlight_color_yellow = "\(serializedShortcut(.highlightColorYellow, configuration: configuration))"
highlight_color_green = "\(serializedShortcut(.highlightColorGreen, configuration: configuration))"
toggle_left_sidebar = "\(serializedShortcut(.toggleLeftSidebar, configuration: configuration))"
toggle_right_sidebar = "\(serializedShortcut(.toggleRightSidebar, configuration: configuration))"
use_sidebar_tabs = "\(serializedShortcut(.useSidebarTabs, configuration: configuration))"
use_titlebar_tabs = "\(serializedShortcut(.useTitlebarTabs, configuration: configuration))"
close_current_tab = "\(serializedShortcut(.closeCurrentTab, configuration: configuration))"
close_current_window = "\(serializedShortcut(.closeCurrentWindow, configuration: configuration))"
previous_tab = "\(serializedShortcut(.previousTab, configuration: configuration))"
next_tab = "\(serializedShortcut(.nextTab, configuration: configuration))"
show_all_tabs = "\(serializedShortcut(.showAllTabs, configuration: configuration))"
toggle_continuous_reading = "\(serializedShortcut(.toggleContinuousReading, configuration: configuration))"
fit_height = "\(serializedShortcut(.fitHeight, configuration: configuration))"
fit_width = "\(serializedShortcut(.fitWidth, configuration: configuration))"
fit_text_width = "\(serializedShortcut(.fitTextWidth, configuration: configuration))"
zoom_in = "\(serializedShortcut(.zoomIn, configuration: configuration))"
zoom_out = "\(serializedShortcut(.zoomOut, configuration: configuration))"
single_page = "\(serializedShortcut(.singlePage, configuration: configuration))"
single_page_continuous = "\(serializedShortcut(.singlePageContinuous, configuration: configuration))"
two_up = "\(serializedShortcut(.twoUp, configuration: configuration))"
two_up_continuous = "\(serializedShortcut(.twoUpContinuous, configuration: configuration))"
book = "\(serializedShortcut(.book, configuration: configuration))"
book_continuous = "\(serializedShortcut(.bookContinuous, configuration: configuration))"
toggle_display_mode_continuity = "\(serializedShortcut(.toggleDisplayModeContinuity, configuration: configuration))"
page_down = "\(serializedShortcut(.pageDown, configuration: configuration))"
page_up = "\(serializedShortcut(.pageUp, configuration: configuration))"
half_page_down = "\(serializedShortcut(.halfPageDown, configuration: configuration))"
half_page_up = "\(serializedShortcut(.halfPageUp, configuration: configuration))"
go_to_first_page = "\(serializedShortcut(.goToFirstPage, configuration: configuration))"
go_to_last_page = "\(serializedShortcut(.goToLastPage, configuration: configuration))"
navigate_back = "\(serializedShortcut(.navigateBack, configuration: configuration))"
navigate_forward = "\(serializedShortcut(.navigateForward, configuration: configuration))"
find_all_open = "\(serializedShortcut(.findAllOpen, configuration: configuration))"
find_next_match = "\(serializedShortcut(.findNextMatch, configuration: configuration))"
find_previous_match = "\(serializedShortcut(.findPreviousMatch, configuration: configuration))"
goto_page = "\(serializedShortcut(.gotoPage, configuration: configuration))"
show_recent_files_palette = "\(serializedShortcut(.showRecentFilesPalette, configuration: configuration))"
open_containing_folder = "\(serializedShortcut(.openContainingFolder, configuration: configuration))"
reopen_last_closed = "\(serializedShortcut(.reopenLastClosed, configuration: configuration))"
new_blank_tab = "\(serializedShortcut(.newBlankTab, configuration: configuration))"
new_window = "\(serializedShortcut(.newWindow, configuration: configuration))"
merge_all_windows = "\(serializedShortcut(.mergeAllWindows, configuration: configuration))"
move_current_pdf_to_new_window = "\(serializedShortcut(.moveCurrentPDFToNewWindow, configuration: configuration))"
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

    /// Keys that must appear in an existing config.toml; missing any triggers a re-render self-heal.
    /// Keep in sync with `defaultContents` and `render` — covered by AppConfigurationTests.
    static let requiredKeys: [String] = [
        "[appearance]",
        "mode",
        "light_theme",
        "dark_theme",
        "[reader]",
        "default_display_mode",
        "fit_width_on_open",
        "reading_focus_width",
        "reading_focus_custom_width",
        "reading_focus_height",
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
        "sidebar_opacity",
        "floating_outline_height",
        "[library]",
        "folders",
        "[access]",
        "roots",
        "root_bookmarks",
        "[updates]",
        "auto_check",
        "github_token",
        "[integrations]",
        "codex_enabled",
        "highlight_selection",
        "underline_selection",
        "strikethrough_selection",
        "add_comment",
        "exit_highlight_mode",
        "toggle_night_mode",
        "toggle_reading_focus",
        "adjust_reading_focus",
        "toggle_horizontal_pan_lock",
        "switch_current_theme",
        "open_library_pdf",
        "refresh_library_index",
        "open_library_settings",
        "open_shortcut_settings",
        "save_annotations",
        "share_document",
        "export_clean_copy",
        "copy_highlights_markdown",
        "copy_current_pdf_path",
        "copy_current_page_as_image",
        "send_context_to_codex",
        "send_current_pdf_to_codex",
        "remove_highlight",
        "highlight_color_pink",
        "highlight_color_yellow",
        "highlight_color_green",
        "toggle_left_sidebar",
        "toggle_right_sidebar",
        "use_sidebar_tabs",
        "use_titlebar_tabs",
        "close_current_tab",
        "close_current_window",
        "previous_tab",
        "next_tab",
        "show_all_tabs",
        "toggle_continuous_reading",
        "fit_height",
        "fit_width",
        "fit_text_width",
        "single_page",
        "single_page_continuous",
        "two_up",
        "two_up_continuous",
        "book",
        "book_continuous",
        "toggle_display_mode_continuity",
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
        "find_all_open",
        "find_next_match",
        "find_previous_match",
        "goto_page",
        "show_recent_files_palette",
        "open_containing_folder",
        "reopen_last_closed",
        "new_blank_tab",
        "new_window",
        "merge_all_windows",
        "move_current_pdf_to_new_window",
        "toggle_all_pages_overview",
        "toggle_demo_mode",
        "toggle_immersive_mode",
        "toggle_reader_split",
        "toggle_right_sidebar_mode",
        "swap_sidebars",
        "undo_last_highlight",
        "redo_last_highlight",
    ]

    private static func serializedDecimal(_ value: CGFloat) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }

    private static func escapedTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func serializedPathArray(_ urls: [URL]) -> String {
        let paths = urls.map { url in
            let escapedPath = url.standardizedFileURL.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escapedPath)\""
        }
        return "[\(paths.joined(separator: ", "))]"
    }

    private static func serializedBookmarkArray(_ bookmarksByPath: [String: Data]) -> String {
        let entries = bookmarksByPath
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { path, data in
                let pathData = Data(path.utf8).base64EncodedString()
                return "\"\(pathData):\(data.base64EncodedString())\""
            }
        return "[\(entries.joined(separator: ", "))]"
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
        case ("shortcuts", "underline_selection"):
            try applyShortcut(rawValue, command: .underlineSelection, to: &configuration)
        case ("shortcuts", "strikethrough_selection"):
            try applyShortcut(rawValue, command: .strikethroughSelection, to: &configuration)
        case ("shortcuts", "exit_highlight_mode"):
            try applyShortcut(rawValue, command: .exitHighlightMode, to: &configuration)
        case ("shortcuts", "toggle_night_mode"):
            try applyShortcut(rawValue, command: .toggleNightMode, to: &configuration)
        case ("shortcuts", "toggle_reading_focus"):
            try applyShortcut(rawValue, command: .toggleReadingFocus, to: &configuration)
        case ("shortcuts", "adjust_reading_focus"):
            try applyShortcut(rawValue, command: .adjustReadingFocus, to: &configuration)
        case ("shortcuts", "toggle_horizontal_pan_lock"):
            try applyShortcut(rawValue, command: .toggleHorizontalPanLock, to: &configuration)
        case ("shortcuts", "switch_current_theme"):
            try applyShortcut(rawValue, command: .switchCurrentTheme, to: &configuration)
        case ("shortcuts", "open_library_pdf"):
            try applyShortcut(rawValue, command: .openLibraryPDF, to: &configuration)
        case ("shortcuts", "refresh_library_index"):
            try applyShortcut(rawValue, command: .refreshLibraryIndex, to: &configuration)
        case ("shortcuts", "open_library_settings"):
            try applyShortcut(rawValue, command: .openLibrarySettings, to: &configuration)
        case ("shortcuts", "open_shortcut_settings"):
            try applyShortcut(rawValue, command: .openShortcutSettings, to: &configuration)
        case ("shortcuts", "save_annotations"):
            try applyShortcut(rawValue, command: .saveAnnotations, to: &configuration)
        case ("shortcuts", "share_document"):
            try applyShortcut(rawValue, command: .shareDocument, to: &configuration)
        case ("shortcuts", "export_clean_copy"):
            try applyShortcut(rawValue, command: .exportCleanCopy, to: &configuration)
        case ("shortcuts", "copy_highlights_markdown"):
            try applyShortcut(rawValue, command: .copyHighlightsMarkdown, to: &configuration)
        case ("shortcuts", "copy_current_pdf_path"):
            try applyShortcut(rawValue, command: .copyCurrentPDFPath, to: &configuration)
        case ("shortcuts", "copy_current_page_as_image"):
            try applyShortcut(rawValue, command: .copyCurrentPageAsImage, to: &configuration)
        case ("shortcuts", "send_context_to_codex"):
            try applyShortcut(rawValue, command: .sendContextToCodex, to: &configuration)
        case ("shortcuts", "send_current_pdf_to_codex"):
            try applyShortcut(rawValue, command: .sendCurrentPDFToCodex, to: &configuration)
        case ("integrations", "codex_enabled"):
            configuration.integrations.codexEnabled = try parseBool(rawValue)
        case ("reader", "default_display_mode"):
            let value = parseString(rawValue)
            guard let displayMode = ReaderDisplayMode(rawValue: value) else {
                throw AppConfigurationError.invalidDisplayMode(value)
            }
            configuration.reader.defaultDisplayMode = displayMode
        case ("reader", "fit_width_on_open"):
            configuration.reader.fitWidthOnOpen = try parseBool(rawValue)
        case ("reader", "reading_focus_width"):
            let value = parseString(rawValue)
            guard let widthMode = ReadingFocusWidthMode(rawValue: value) else {
                throw AppConfigurationError.invalidReadingFocusWidthMode(value)
            }
            configuration.reader.readingFocus.widthMode = widthMode
        case ("reader", "reading_focus_custom_width"):
            configuration.reader.readingFocus.customWidthRatio = try parseReadingFocusWidthRatio(rawValue)
        case ("reader", "reading_focus_height"):
            configuration.reader.readingFocus.height = try parseReadingFocusHeight(rawValue)
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
        case ("layout", "sidebar_opacity"):
            configuration.layout.sidebarOpacity = try parseOpacity(rawValue)
        case ("layout", "floating_outline_height"):
            configuration.layout.floatingOutlineHeight = try parseFloatingOutlineHeight(rawValue)
        case ("library", "folders"):
            configuration.library.folderURLs = try parseStringArray(rawValue)
                .map { URL(fileURLWithPath: $0).standardizedFileURL }
        case ("access", "roots"):
            configuration.access.rootURLs = try parseStringArray(rawValue)
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        case ("access", "root_bookmarks"):
            configuration.access.rootBookmarkData = try parseBookmarkArray(rawValue)
        case ("updates", "auto_check"):
            configuration.updates.autoCheck = try parseBool(rawValue)
        case ("updates", "github_token"):
            configuration.updates.githubToken = parseString(rawValue)
        case ("shortcuts", "remove_highlight"):
            try applyShortcut(rawValue, command: .removeHighlight, to: &configuration)
        case ("shortcuts", "add_comment"):
            try applyShortcut(rawValue, command: .addComment, to: &configuration)
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
        case ("shortcuts", "close_current_window"):
            try applyShortcut(rawValue, command: .closeCurrentWindow, to: &configuration)
        case ("shortcuts", "previous_tab"):
            try applyShortcut(rawValue, command: .previousTab, to: &configuration)
        case ("shortcuts", "next_tab"):
            try applyShortcut(rawValue, command: .nextTab, to: &configuration)
        case ("shortcuts", "show_all_tabs"):
            try applyShortcut(rawValue, command: .showAllTabs, to: &configuration)
        case ("shortcuts", "toggle_continuous_reading"):
            try applyShortcut(rawValue, command: .toggleContinuousReading, to: &configuration)
        case ("shortcuts", "fit_height"):
            try applyShortcut(rawValue, command: .fitHeight, to: &configuration)
        case ("shortcuts", "fit_width"):
            try applyShortcut(rawValue, command: .fitWidth, to: &configuration)
        case ("shortcuts", "fit_text_width"):
            try applyShortcut(rawValue, command: .fitTextWidth, to: &configuration)
        case ("shortcuts", "single_page"):
            try applyShortcut(rawValue, command: .singlePage, to: &configuration)
        case ("shortcuts", "single_page_continuous"):
            try applyShortcut(rawValue, command: .singlePageContinuous, to: &configuration)
        case ("shortcuts", "two_up"):
            try applyShortcut(rawValue, command: .twoUp, to: &configuration)
        case ("shortcuts", "two_up_continuous"):
            try applyShortcut(rawValue, command: .twoUpContinuous, to: &configuration)
        case ("shortcuts", "book"):
            try applyShortcut(rawValue, command: .book, to: &configuration)
        case ("shortcuts", "book_continuous"):
            try applyShortcut(rawValue, command: .bookContinuous, to: &configuration)
        case ("shortcuts", "toggle_display_mode_continuity"):
            try applyShortcut(rawValue, command: .toggleDisplayModeContinuity, to: &configuration)
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
        case ("shortcuts", "find_all_open"):
            try applyShortcut(rawValue, command: .findAllOpen, to: &configuration)
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
        case ("shortcuts", "new_blank_tab"):
            try applyShortcut(rawValue, command: .newBlankTab, to: &configuration)
        case ("shortcuts", "new_window"):
            try applyShortcut(rawValue, command: .newWindow, to: &configuration)
        case ("shortcuts", "merge_all_windows"):
            try applyShortcut(rawValue, command: .mergeAllWindows, to: &configuration)
        case ("shortcuts", "move_current_pdf_to_new_window"):
            try applyShortcut(rawValue, command: .moveCurrentPDFToNewWindow, to: &configuration)
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
        let withoutInlineComment = stripInlineComment(from: rawValue)
        return withoutInlineComment.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Strips a trailing `# …` comment when it appears outside a double-quoted string.
    private func stripInlineComment(from rawValue: String) -> String {
        var inQuotes = false
        var isEscaped = false
        for (index, character) in rawValue.enumerated() {
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == "#", inQuotes == false {
                return String(rawValue.prefix(index)).trimmingCharacters(in: .whitespaces)
            }
        }
        return rawValue
    }

    private func parseStringArray(_ rawValue: String) throws -> [String] {
        let data = Data(rawValue.utf8)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [String] else {
            throw AppConfigurationError.invalidStringArray(rawValue)
        }
        return array
    }

    private func parseBookmarkArray(_ rawValue: String) throws -> [String: Data] {
        let entries = try parseStringArray(rawValue)
        var bookmarks: [String: Data] = [:]
        for entry in entries {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let pathData = Data(base64Encoded: parts[0]),
                  let path = String(data: pathData, encoding: .utf8),
                  let bookmarkData = Data(base64Encoded: parts[1]) else {
                throw AppConfigurationError.invalidStringArray(rawValue)
            }
            bookmarks[path] = bookmarkData
        }
        return bookmarks
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
        let shortcut = try KeyboardShortcut.parse(value)
        guard shortcut != ShortcutCommand.commandPaletteShortcut else {
            throw AppConfigurationError.invalidShortcut(value)
        }
        configuration.shortcuts.bindings[command] = shortcut
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

    private func parseOpacity(_ rawValue: String) throws -> CGFloat {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard let value = Double(trimmed), value.isFinite, (0...1).contains(value) else {
            throw AppConfigurationError.invalidOpacity(rawValue)
        }
        return CGFloat(value)
    }

    private func parseFloatingOutlineHeight(_ rawValue: String) throws -> CGFloat {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard let value = Double(trimmed),
              value.isFinite,
              (Double(AppConfiguration.Layout.minimumFloatingOutlineHeight)...Double(AppConfiguration.Layout.maximumFloatingOutlineHeight))
                .contains(value) else {
            throw AppConfigurationError.invalidFloatingOutlineHeight(rawValue)
        }
        return CGFloat(value)
    }

    private func parseReadingFocusWidthRatio(_ rawValue: String) throws -> CGFloat {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard let value = Double(trimmed),
              value.isFinite,
              (Double(ReadingFocusSettings.minimumCustomWidthRatio)...Double(ReadingFocusSettings.maximumCustomWidthRatio))
                .contains(value) else {
            throw AppConfigurationError.invalidReadingFocusWidthRatio(rawValue)
        }
        return CGFloat(value)
    }

    private func parseReadingFocusHeight(_ rawValue: String) throws -> CGFloat {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard let value = Double(trimmed),
              value.isFinite,
              (Double(ReadingFocusSettings.minimumHeight)...Double(ReadingFocusSettings.maximumHeight))
                .contains(value) else {
            throw AppConfigurationError.invalidReadingFocusHeight(rawValue)
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
        let requiredKeys = AppConfigurationFile.requiredKeys
        let existingAssignmentPaths = Self.tomlAssignmentPaths(in: existingContent)
        let existingSections = Self.tomlSections(in: existingContent)
        let hasShortcutKey: (String) -> Bool = {
            existingAssignmentPaths.contains("shortcuts.\($0)")
        }

        var configuration = try parser.parse(existingContent)
        let legacyRemoveHighlight = KeyboardShortcut(key: "d", modifiers: [.command, .shift])
        let legacyGreenHighlight = KeyboardShortcut(key: "g", modifiers: [.command, .shift])
        let legacyImmersiveMode = KeyboardShortcut(key: "l", modifiers: [.command, .option])
        let legacyShowAllTabs = KeyboardShortcut(key: "t", modifiers: [.command, .option])
        let legacyContinuousReading = KeyboardShortcut(key: "c", modifiers: [.command, .shift])
        var didMigrate = false
        if configuration.shortcuts.bindings[.removeHighlight] == legacyRemoveHighlight {
            configuration.shortcuts.bindings[.removeHighlight] = KeyboardShortcut(key: "d", modifiers: [])
            didMigrate = true
        }
        if hasShortcutKey("find_previous_match") == false,
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
        if configuration.shortcuts.bindings[.showAllTabs] == legacyShowAllTabs {
            configuration.shortcuts.bindings[.showAllTabs] =
                AppConfiguration.default.shortcuts.bindings[.showAllTabs]
                ?? KeyboardShortcut(key: "tab", modifiers: [.control])
            didMigrate = true
        }
        if hasShortcutKey("copy_current_pdf_path") == false,
           configuration.shortcuts.bindings[.toggleContinuousReading] == legacyContinuousReading {
            configuration.shortcuts.bindings[.copyCurrentPDFPath] =
                AppConfiguration.default.shortcuts.bindings[.copyCurrentPDFPath]
                ?? legacyContinuousReading
            configuration.shortcuts.bindings[.toggleContinuousReading] = nil
            didMigrate = true
        }
        let hasLegacyCodexShortcuts =
            hasShortcutKey("send_context_to_codex") == false &&
            (hasShortcutKey("send_selection_to_codex") ||
                hasShortcutKey("send_current_page_to_codex"))
        if hasLegacyCodexShortcuts {
            configuration.shortcuts.bindings[.sendContextToCodex] =
                AppConfiguration.default.shortcuts.bindings[.sendContextToCodex]
            if configuration.shortcuts.bindings[.sendCurrentPDFToCodex] == nil {
                configuration.shortcuts.bindings[.sendCurrentPDFToCodex] =
                    AppConfiguration.default.shortcuts.bindings[.sendCurrentPDFToCodex]
            }
            didMigrate = true
        }
        for command: ShortcutCommand in [.underlineSelection, .strikethroughSelection]
        where hasShortcutKey(command.rawValue) == false {
            guard let shortcut = configuration.shortcuts.bindings[command] else { continue }
            let hasConflict = configuration.shortcuts.bindings.contains {
                $0.key != command && $0.value == shortcut
            }
            if hasConflict {
                configuration.shortcuts.bindings[command] = nil
                didMigrate = true
            }
        }

        if hasShortcutKey(ShortcutCommand.toggleDisplayModeContinuity.rawValue) == false,
           let shortcut = configuration.shortcuts.bindings[.toggleDisplayModeContinuity] {
            let hasConflict = configuration.shortcuts.bindings.contains {
                $0.key != .toggleDisplayModeContinuity && $0.value == shortcut
            }
            if hasConflict {
                configuration.shortcuts.bindings[.toggleDisplayModeContinuity] = nil
                didMigrate = true
            }
        }

        let requiredAssignmentKeys = Set(requiredKeys.filter { $0.hasPrefix("[") == false })
        let requiredAssignmentPaths = Self.tomlAssignmentPaths(in: AppConfigurationFile.defaultContents)
            .filter { path in
                requiredAssignmentKeys.contains(path.split(separator: ".").last.map(String.init) ?? "")
            }
        let missingKeys = requiredKeys.contains { requiredKey in
            requiredKey.hasPrefix("[")
                && requiredKey.hasSuffix("]")
                && existingSections.contains(String(requiredKey.dropFirst().dropLast())) == false
        } || requiredAssignmentPaths.isSubset(of: existingAssignmentPaths) == false
        guard missingKeys || didMigrate else { return }

        try AppConfigurationFile.render(configuration).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func tomlAssignmentPaths(in content: String) -> Set<String> {
        var section = ""
        var paths = Set<String>()
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let closingBracket = line.firstIndex(of: "]") {
                section = String(line[line.index(after: line.startIndex)..<closingBracket])
                continue
            }
            guard line.isEmpty == false,
                  line.hasPrefix("#") == false,
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.isEmpty == false else { continue }
            paths.insert(section.isEmpty ? key : "\(section).\(key)")
        }
        return paths
    }

    private static func tomlSections(in content: String) -> Set<String> {
        Set(content.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["),
                  let closingBracket = line.firstIndex(of: "]") else { return nil }
            return String(line[line.index(after: line.startIndex)..<closingBracket])
        })
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Serein", isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}
