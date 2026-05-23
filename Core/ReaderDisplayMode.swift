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
    case fitHeight = "fit_height"
    case fitWidth = "fit_width"
}

enum ShortcutCommand: String, CaseIterable, Sendable {
    case highlightSelection = "highlight_selection"
    case exitHighlightMode = "exit_highlight_mode"
    case toggleNightMode = "toggle_night_mode"
    case switchCurrentTheme = "switch_current_theme"
    case openLibraryPDF = "open_library_pdf"
    case refreshLibraryIndex = "refresh_library_index"
    case openLibrarySettings = "open_library_settings"
    case openShortcutSettings = "open_shortcut_settings"
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
    case closeCurrentWindow = "close_current_window"
    case previousTab = "previous_tab"
    case nextTab = "next_tab"
    case showAllTabs = "show_all_tabs"
    case toggleContinuousReading = "toggle_continuous_reading"
    case fitHeight = "fit_height"
    case fitWidth = "fit_width"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"
    case pageDown = "page_down"
    case pageUp = "page_up"
    case halfPageDown = "half_page_down"
    case halfPageUp = "half_page_up"
    case goToFirstPage = "go_to_first_page"
    case goToLastPage = "go_to_last_page"
    case navigateBack = "navigate_back"
    case navigateForward = "navigate_forward"
    case findAllOpen = "find_all_open"
    case findNextMatch = "find_next_match"
    case findPreviousMatch = "find_previous_match"
    case gotoPage = "goto_page"
    case showRecentFilesPalette = "show_recent_files_palette"
    case openContainingFolder = "open_containing_folder"
    case reopenLastClosed = "reopen_last_closed"
    case newBlankTab = "new_blank_tab"
    case newWindow = "new_window"
    case mergeAllWindows = "merge_all_windows"
    case moveCurrentPDFToNewWindow = "move_current_pdf_to_new_window"
    case toggleAllPagesOverview = "toggle_all_pages_overview"
    case toggleDemoMode = "toggle_demo_mode"
    case toggleImmersiveMode = "toggle_immersive_mode"
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
        case .switchCurrentTheme:
            "Switch Current Theme"
        case .openLibraryPDF:
            "Open from PDF Library…"
        case .refreshLibraryIndex:
            "Refresh PDF Library Index"
        case .openLibrarySettings:
            "Open Library Settings"
        case .openShortcutSettings:
            "Open Shortcuts Settings"
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
        case .closeCurrentWindow:
            "Close Current Window"
        case .previousTab:
            "Previous Tab"
        case .nextTab:
            "Next Tab"
        case .showAllTabs:
            "Show All Tabs"
        case .toggleContinuousReading:
            "Toggle Continuous Reading"
        case .fitHeight:
            "Fit Height"
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
        case .halfPageDown:
            "Half Page Down"
        case .halfPageUp:
            "Half Page Up"
        case .goToFirstPage:
            "Go to First Page"
        case .goToLastPage:
            "Go to Last Page"
        case .navigateBack:
            "Back"
        case .navigateForward:
            "Forward"
        case .findAllOpen:
            "Find in All Open PDFs…"
        case .findNextMatch:
            "Find Next Match"
        case .findPreviousMatch:
            "Find Previous Match"
        case .gotoPage:
            "Go to Page…"
        case .showRecentFilesPalette:
            "Open Recent Quickly…"
        case .openContainingFolder:
            "Show in Finder"
        case .reopenLastClosed:
            "Reopen Closed Tab"
        case .newBlankTab:
            "New Blank Tab"
        case .newWindow:
            "New Window"
        case .mergeAllWindows:
            "Merge All Windows"
        case .moveCurrentPDFToNewWindow:
            "Move Current PDF to New Window"
        case .toggleAllPagesOverview:
            "All Pages Overview"
        case .toggleDemoMode:
            "Toggle Demo Mode"
        case .toggleImmersiveMode:
            "Toggle Immersive Mode"
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

    var builtInChordDisplay: String? {
        switch self {
        case .switchCurrentTheme:
            "⌘K ⌘T"
        case .openLibraryPDF:
            "⌘K ⌘O"
        case .refreshLibraryIndex:
            "⌘K ⌘R"
        case .openLibrarySettings:
            "⌘K ⌘L"
        case .openShortcutSettings:
            "⌘K ⌘S"
        case .mergeAllWindows:
            "⌘K ⌘M"
        case .moveCurrentPDFToNewWindow:
            "⌘K ⌘N"
        default:
            nil
        }
    }
}
