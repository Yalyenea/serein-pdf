import AppKit
import PDFKit

enum ReaderDisplayMode: String, CaseIterable, Codable, Sendable {
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"
    case book = "book"
    case bookContinuous = "book_continuous"

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
        case .book, .bookContinuous:
            .twoUp
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
        case .book:
            "Book"
        case .bookContinuous:
            "Book · Continuous Turn"
        }
    }

    var usesTwoUpLayout: Bool {
        switch self {
        case .singlePage, .singlePageContinuous:
            false
        case .twoUp, .twoUpContinuous, .book, .bookContinuous:
            true
        }
    }

    var usesBookLayout: Bool {
        self == .book || self == .bookContinuous
    }

    var displayDirection: PDFDisplayDirection {
        usesBookLayout ? .horizontal : .vertical
    }

    var displaysAsBook: Bool {
        usesBookLayout
    }

    var allowsContinuousBookPageTurn: Bool {
        self == .bookContinuous
    }

    var toggledContinuity: ReaderDisplayMode {
        switch self {
        case .singlePage:
            .singlePageContinuous
        case .singlePageContinuous:
            .singlePage
        case .twoUp:
            .twoUpContinuous
        case .twoUpContinuous:
            .twoUp
        case .book:
            .bookContinuous
        case .bookContinuous:
            .book
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
    case underlineSelection = "underline_selection"
    case strikethroughSelection = "strikethrough_selection"
    case addComment = "add_comment"
    case exitHighlightMode = "exit_highlight_mode"
    case toggleNightMode = "toggle_night_mode"
    case toggleReadingFocus = "toggle_reading_focus"
    case adjustReadingFocus = "adjust_reading_focus"
    case toggleHorizontalPanLock = "toggle_horizontal_pan_lock"
    case switchCurrentTheme = "switch_current_theme"
    case openLibraryPDF = "open_library_pdf"
    case refreshLibraryIndex = "refresh_library_index"
    case openLibrarySettings = "open_library_settings"
    case openShortcutSettings = "open_shortcut_settings"
    case saveAnnotations = "save_annotations"
    case shareDocument = "share_document"
    case exportCleanCopy = "export_clean_copy"
    case copyHighlightsMarkdown = "copy_highlights_markdown"
    case copyCurrentPDFPath = "copy_current_pdf_path"
    case copyCurrentPageAsImage = "copy_current_page_as_image"
    case sendContextToCodex = "send_context_to_codex"
    case sendCurrentPDFToCodex = "send_current_pdf_to_codex"
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
    case book = "book"
    case bookContinuous = "book_continuous"
    case toggleDisplayModeContinuity = "toggle_display_mode_continuity"
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

    static let commandPaletteShortcut = KeyboardShortcut(key: "k", modifiers: [.command])

    var menuTitle: String {
        switch self {
        case .highlightSelection:
            "Highlight Selection or Enter Highlight Mode"
        case .underlineSelection:
            "Underline Selection or Enter Underline Mode"
        case .strikethroughSelection:
            "Strikethrough Selection or Enter Strikethrough Mode"
        case .addComment:
            "Add or Edit Comment"
        case .exitHighlightMode:
            "Exit Annotation Mode"
        case .toggleNightMode:
            "Toggle Night Mode"
        case .toggleReadingFocus:
            "Toggle Reading Focus"
        case .adjustReadingFocus:
            "Adjust Reading Focus…"
        case .toggleHorizontalPanLock:
            "Toggle Horizontal Pan Lock"
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
        case .shareDocument:
            "Share…"
        case .exportCleanCopy:
            "Export Clean Copy…"
        case .copyHighlightsMarkdown:
            "Copy Highlights as Markdown"
        case .copyCurrentPDFPath:
            "Copy Current PDF Path"
        case .copyCurrentPageAsImage:
            "Copy Page as Image"
        case .sendContextToCodex:
            "Send Context to Codex"
        case .sendCurrentPDFToCodex:
            "Send Current PDF to Codex"
        case .removeHighlight:
            "Remove Annotation"
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
        case .book:
            ReaderDisplayMode.book.menuTitle
        case .bookContinuous:
            ReaderDisplayMode.bookContinuous.menuTitle
        case .toggleDisplayModeContinuity:
            "Toggle Current Layout Continuity"
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
            "Reveal in Finder"
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
        case .book:
            .book
        case .bookContinuous:
            .bookContinuous
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

    var annotationMarkupType: AnnotationMarkupType? {
        switch self {
        case .highlightSelection: .highlight
        case .underlineSelection: .underline
        case .strikethroughSelection: .strikethrough
        default: nil
        }
    }

    var builtInShortcutSequence: KeyboardShortcutSequence? {
        let suffix: KeyboardShortcut
        switch self {
        case .switchCurrentTheme:
            suffix = KeyboardShortcut(key: "t", modifiers: [.command])
        case .openLibraryPDF:
            suffix = KeyboardShortcut(key: "o", modifiers: [.command])
        case .refreshLibraryIndex:
            suffix = KeyboardShortcut(key: "r", modifiers: [.command])
        case .openLibrarySettings:
            suffix = KeyboardShortcut(key: "l", modifiers: [.command])
        case .openShortcutSettings:
            suffix = KeyboardShortcut(key: "s", modifiers: [.command])
        case .shareDocument:
            suffix = KeyboardShortcut(key: "e", modifiers: [.command])
        case .mergeAllWindows:
            suffix = KeyboardShortcut(key: "m", modifiers: [.command])
        case .moveCurrentPDFToNewWindow:
            suffix = KeyboardShortcut(key: "n", modifiers: [.command])
        default:
            return nil
        }
        return KeyboardShortcutSequence([Self.commandPaletteShortcut, suffix])
    }

    var builtInChordDisplay: String? {
        builtInShortcutSequence?.displayString
    }

    var shortcutSection: ShortcutSection {
        switch self {
        case .highlightSelection, .underlineSelection, .strikethroughSelection,
             .addComment, .exitHighlightMode, .saveAnnotations, .removeHighlight,
             .highlightColorPink, .highlightColorYellow, .highlightColorGreen,
             .undoLastHighlight, .redoLastHighlight, .copyHighlightsMarkdown:
            .annotations
        case .toggleNightMode, .toggleReadingFocus, .adjustReadingFocus,
             .toggleHorizontalPanLock, .switchCurrentTheme, .fitHeight, .fitWidth,
             .zoomIn, .zoomOut, .singlePage, .singlePageContinuous, .twoUp,
             .twoUpContinuous, .book, .bookContinuous, .toggleDisplayModeContinuity,
             .toggleContinuousReading, .toggleAllPagesOverview, .toggleDemoMode:
            .reading
        case .pageDown, .pageUp, .halfPageDown, .halfPageUp, .goToFirstPage,
             .goToLastPage, .navigateBack, .navigateForward, .findAllOpen,
             .findNextMatch, .findPreviousMatch, .gotoPage:
            .navigation
        case .openLibraryPDF, .refreshLibraryIndex, .openLibrarySettings,
             .openShortcutSettings, .shareDocument, .exportCleanCopy,
             .copyCurrentPDFPath, .copyCurrentPageAsImage, .sendContextToCodex,
             .sendCurrentPDFToCodex, .showRecentFilesPalette, .openContainingFolder,
             .reopenLastClosed, .newBlankTab:
            .documents
        case .toggleLeftSidebar, .toggleRightSidebar, .useSidebarTabs,
             .useTitlebarTabs, .closeCurrentTab, .closeCurrentWindow, .previousTab,
             .nextTab, .showAllTabs, .newWindow, .mergeAllWindows,
             .moveCurrentPDFToNewWindow, .toggleImmersiveMode, .toggleReaderSplit,
             .toggleRightSidebarMode, .swapSidebars:
            .windows
        }
    }

    func matchesShortcutSearch(
        _ query: String,
        binding: KeyboardShortcut?,
        additionalText: String = ""
    ) -> Bool {
        let tokens = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard tokens.isEmpty == false else { return true }
        let searchableText = [
            menuTitle,
            rawValue.replacingOccurrences(of: "_", with: " "),
            shortcutSection.title,
            binding?.displayString ?? "",
            builtInChordDisplay ?? "",
            additionalText,
        ]
            .joined(separator: " ")
            .lowercased()
        return tokens.allSatisfy(searchableText.contains)
    }
}

enum ShortcutSection: Int, CaseIterable, Sendable {
    case annotations
    case reading
    case navigation
    case documents
    case windows

    var title: String {
        switch self {
        case .annotations: "Annotations"
        case .reading: "Reading"
        case .navigation: "Navigation & Search"
        case .documents: "Documents & Library"
        case .windows: "Tabs & Windows"
        }
    }
}
