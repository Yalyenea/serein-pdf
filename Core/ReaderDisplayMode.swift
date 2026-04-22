import AppKit
import PDFKit

enum ReaderDisplayMode: String, CaseIterable, Codable, Sendable {
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"

    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .singlePage:
            .singlePage
        case .singlePageContinuous:
            .singlePageContinuous
        case .twoUp:
            .twoUp
        case .twoUpContinuous:
            .twoUpContinuous
        }
    }

    var menuTitle: String {
        switch self {
        case .singlePage:
            "Single Page"
        case .singlePageContinuous:
            "Single Page Continuous"
        case .twoUp:
            "Two-Up"
        case .twoUpContinuous:
            "Two-Up Continuous"
        }
    }

    var usesTwoUpLayout: Bool {
        switch self {
        case .singlePage, .singlePageContinuous:
            false
        case .twoUp, .twoUpContinuous:
            true
        }
    }
}

enum ReaderScaleMode: String, Codable, Sendable {
    case manual
    case fitWidth = "fit_width"
}

enum ShortcutCommand: String, CaseIterable, Sendable {
    case highlightSelection = "highlight_selection"
    case exitHighlightMode = "exit_highlight_mode"
    case toggleNightMode = "toggle_night_mode"
    case saveAnnotations = "save_annotations"
    case copyHighlightsMarkdown = "copy_highlights_markdown"
    case removeHighlight = "remove_highlight"
    case highlightColorPink = "highlight_color_pink"
    case highlightColorYellow = "highlight_color_yellow"
    case highlightColorGreen = "highlight_color_green"
    case toggleLeftSidebar = "toggle_left_sidebar"
    case toggleRightSidebar = "toggle_right_sidebar"
    case useSidebarTabs = "use_sidebar_tabs"
    case useTitlebarTabs = "use_titlebar_tabs"
    case closeCurrentTab = "close_current_tab"
    case previousTab = "previous_tab"
    case nextTab = "next_tab"
    case fitWidth = "fit_width"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"
    case pageDown = "page_down"
    case pageUp = "page_up"
    case navigateBack = "navigate_back"
    case navigateForward = "navigate_forward"
    case gotoPage = "goto_page"
    case showRecentFilesPalette = "show_recent_files_palette"
    case reopenLastClosed = "reopen_last_closed"
    case newWindow = "new_window"
    case toggleAllPagesOverview = "toggle_all_pages_overview"
    case toggleReaderSplit = "toggle_reader_split"
    case toggleRightSidebarMode = "toggle_right_sidebar_mode"
    case swapSidebars = "swap_sidebars"
    case undoLastHighlight = "undo_last_highlight"
    case redoLastHighlight = "redo_last_highlight"

    var menuTitle: String {
        switch self {
        case .highlightSelection:
            "Highlight Selection or Enter Highlight Mode"
        case .exitHighlightMode:
            "Exit Highlight Mode"
        case .toggleNightMode:
            "Toggle Night Mode"
        case .saveAnnotations:
            "Save Annotations"
        case .copyHighlightsMarkdown:
            "Copy Highlights as Markdown"
        case .removeHighlight:
            "Remove Highlight"
        case .highlightColorPink:
            "Highlight Color: \(HighlightColor.pink.menuTitle)"
        case .highlightColorYellow:
            "Highlight Color: \(HighlightColor.yellow.menuTitle)"
        case .highlightColorGreen:
            "Highlight Color: \(HighlightColor.green.menuTitle)"
        case .toggleLeftSidebar:
            "Toggle Left Sidebar"
        case .toggleRightSidebar:
            "Toggle Right Sidebar"
        case .useSidebarTabs:
            "Use Sidebar Tabs"
        case .useTitlebarTabs:
            "Use Titlebar Tabs"
        case .closeCurrentTab:
            "Close Current Tab"
        case .previousTab:
            "Previous Tab"
        case .nextTab:
            "Next Tab"
        case .fitWidth:
            "Fit Width"
        case .zoomIn:
            "Zoom In"
        case .zoomOut:
            "Zoom Out"
        case .singlePage:
            ReaderDisplayMode.singlePage.menuTitle
        case .singlePageContinuous:
            ReaderDisplayMode.singlePageContinuous.menuTitle
        case .twoUp:
            ReaderDisplayMode.twoUp.menuTitle
        case .twoUpContinuous:
            ReaderDisplayMode.twoUpContinuous.menuTitle
        case .pageDown:
            "Next Page"
        case .pageUp:
            "Previous Page"
        case .navigateBack:
            "Back"
        case .navigateForward:
            "Forward"
        case .gotoPage:
            "Go to Page…"
        case .showRecentFilesPalette:
            "Open Recent Quickly…"
        case .reopenLastClosed:
            "Reopen Closed Tab"
        case .newWindow:
            "New Window"
        case .toggleAllPagesOverview:
            "All Pages Overview"
        case .toggleReaderSplit:
            "Toggle Compare Split"
        case .toggleRightSidebarMode:
            "Toggle Outline / Pages"
        case .swapSidebars:
            "Swap Left and Right Sidebars"
        case .undoLastHighlight:
            "Undo Highlight"
        case .redoLastHighlight:
            "Redo Highlight"
        }
    }

    var displayMode: ReaderDisplayMode? {
        switch self {
        case .singlePage:
            .singlePage
        case .singlePageContinuous:
            .singlePageContinuous
        case .twoUp:
            .twoUp
        case .twoUpContinuous:
            .twoUpContinuous
        default:
            nil
        }
    }

    var highlightColor: HighlightColor? {
        switch self {
        case .highlightColorPink: .pink
        case .highlightColorYellow: .yellow
        case .highlightColorGreen: .green
        default: nil
        }
    }
}
