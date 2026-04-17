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
    case toggleLeftSidebar = "toggle_left_sidebar"
    case toggleRightSidebar = "toggle_right_sidebar"
    case useSidebarTabs = "use_sidebar_tabs"
    case useTitlebarTabs = "use_titlebar_tabs"
    case closeCurrentTab = "close_current_tab"
    case previousTab = "previous_tab"
    case nextTab = "next_tab"
    case fitWidth = "fit_width"
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"

    var menuTitle: String {
        switch self {
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
        case .singlePage:
            ReaderDisplayMode.singlePage.menuTitle
        case .singlePageContinuous:
            ReaderDisplayMode.singlePageContinuous.menuTitle
        case .twoUp:
            ReaderDisplayMode.twoUp.menuTitle
        case .twoUpContinuous:
            ReaderDisplayMode.twoUpContinuous.menuTitle
        }
    }

    var displayMode: ReaderDisplayMode? {
        switch self {
        case .toggleLeftSidebar,
             .toggleRightSidebar,
             .useSidebarTabs,
             .useTitlebarTabs,
             .closeCurrentTab,
             .previousTab,
             .nextTab:
            nil
        case .fitWidth:
            nil
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
}
