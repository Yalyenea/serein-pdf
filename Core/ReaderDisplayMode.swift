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
            L10n.text("Single Page", "单页")
        case .singlePageContinuous:
            L10n.text("Single Page Continuous", "单页连续")
        case .twoUp:
            L10n.text("Two-Up", "双页")
        case .twoUpContinuous:
            L10n.text("Two-Up Continuous", "双页连续")
        case .book:
            L10n.text("Book", "书籍")
        case .bookContinuous:
            L10n.text("Book · Continuous Turn", "书籍 · 连续翻页")
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
    case fitTextWidth = "fit_text_width"
}

enum ShortcutCommand: String, CaseIterable, Sendable {
    case highlightSelection = "highlight_selection"
    case underlineSelection = "underline_selection"
    case strikethroughSelection = "strikethrough_selection"
    case addComment = "add_comment"
    case translateSelection = "translate_selection"
    case exitHighlightMode = "exit_highlight_mode"
    case toggleNightMode = "toggle_night_mode"
    case toggleReadingFocus = "toggle_reading_focus"
    case adjustReadingFocus = "adjust_reading_focus"
    case toggleHorizontalPanLock = "toggle_horizontal_pan_lock"
    case toggleGlobalHorizontalPanLock = "toggle_global_horizontal_pan_lock"
    case toggleSeamlessPages = "toggle_seamless_pages"
    case switchCurrentTheme = "switch_current_theme"
    case openLibraryPDF = "open_library_pdf"
    case refreshLibraryIndex = "refresh_library_index"
    case openLibrarySettings = "open_library_settings"
    case openShortcutSettings = "open_shortcut_settings"
    case saveAnnotations = "save_annotations"
    case shareDocument = "share_document"
    case printDocument = "print_document"
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
    case previousWorkspace = "previous_workspace"
    case nextWorkspace = "next_workspace"
    case workspace1 = "workspace_1"
    case workspace2 = "workspace_2"
    case workspace3 = "workspace_3"
    case workspace4 = "workspace_4"
    case workspace5 = "workspace_5"
    case workspace6 = "workspace_6"
    case workspace7 = "workspace_7"
    case workspace8 = "workspace_8"
    case workspace9 = "workspace_9"
    case showAllTabs = "show_all_tabs"
    case toggleContinuousReading = "toggle_continuous_reading"
    case fitHeight = "fit_height"
    case fitWidth = "fit_width"
    case fitTextWidth = "fit_text_width"
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
    case quickOutline = "quick_outline"
    case showRecentFilesPalette = "show_recent_files_palette"
    case showRecentWindows = "show_recent_windows"
    case paletteSplitRight = "palette_split_right"
    case paletteSplitDown = "palette_split_down"
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
    case splitCurrentPDFRight = "split_current_pdf_right"
    case splitCurrentPDFDown = "split_current_pdf_down"
    case focusPaneLeft = "focus_pane_left"
    case focusPaneDown = "focus_pane_down"
    case focusPaneUp = "focus_pane_up"
    case focusPaneRight = "focus_pane_right"
    case togglePaneZoom = "toggle_pane_zoom"
    case toggleRightSidebarMode = "toggle_right_sidebar_mode"
    case swapSidebars = "swap_sidebars"
    case undoLastHighlight = "undo_last_highlight"
    case redoLastHighlight = "redo_last_highlight"

    static let commandPaletteShortcut = KeyboardShortcut(key: "k", modifiers: [.command])
    static let workspaceIndexCommands: [ShortcutCommand] = [
        .workspace1, .workspace2, .workspace3, .workspace4, .workspace5,
        .workspace6, .workspace7, .workspace8, .workspace9,
    ]

    var workspaceIndex: Int? {
        Self.workspaceIndexCommands.firstIndex(of: self).map { $0 + 1 }
    }

    var menuTitle: String {
        switch self {
        case .highlightSelection:
            L10n.text("Highlight Selection or Enter Highlight Mode", "高亮选区或进入高亮模式")
        case .underlineSelection:
            L10n.text("Underline Selection or Enter Underline Mode", "为选区加下划线或进入下划线模式")
        case .strikethroughSelection:
            L10n.text("Strikethrough Selection or Enter Strikethrough Mode", "为选区加删除线或进入删除线模式")
        case .addComment:
            L10n.text("Add or Edit Comment", "添加或编辑评论")
        case .translateSelection:
            L10n.text("Translate Selection…", "翻译选区…")
        case .exitHighlightMode:
            L10n.text("Exit Annotation Mode", "退出批注模式")
        case .toggleNightMode:
            L10n.text("Toggle Night Mode", "切换夜间模式")
        case .toggleReadingFocus:
            L10n.text("Toggle Reading Focus", "切换阅读聚焦")
        case .adjustReadingFocus:
            L10n.text("Adjust Reading Focus…", "调整阅读聚焦…")
        case .toggleGlobalHorizontalPanLock:
            L10n.text("Global Lock", "全局锁定")
        case .toggleSeamlessPages:
            L10n.text("Seamless Pages", "无缝页面")
        case .toggleHorizontalPanLock:
            L10n.text("Toggle Horizontal Pan Lock", "切换横向移动锁定")
        case .switchCurrentTheme:
            L10n.text("Switch Current Theme", "切换当前主题")
        case .openLibraryPDF:
            L10n.text("Open from PDF Library…", "从 PDF 库打开…")
        case .refreshLibraryIndex:
            L10n.text("Refresh PDF Library Index", "刷新 PDF 库索引")
        case .openLibrarySettings:
            L10n.text("Open Library Settings", "打开 PDF 库设置")
        case .openShortcutSettings:
            L10n.text("Open Shortcuts Settings", "打开快捷键设置")
        case .saveAnnotations:
            L10n.text("Save Annotations", "保存批注")
        case .shareDocument:
            L10n.text("Share…", "共享…")
        case .printDocument:
            L10n.text("Print…", "打印…")
        case .exportCleanCopy:
            L10n.text("Export Clean Copy…", "导出无批注副本…")
        case .copyHighlightsMarkdown:
            L10n.text("Copy Highlights as Markdown", "将高亮复制为 Markdown")
        case .copyCurrentPDFPath:
            L10n.text("Copy Current PDF Path", "复制当前 PDF 路径")
        case .copyCurrentPageAsImage:
            L10n.text("Copy Page as Image", "将当前页复制为图片")
        case .sendContextToCodex:
            L10n.text("Send Context to Codex", "发送当前内容到 Codex")
        case .sendCurrentPDFToCodex:
            L10n.text("Send Current PDF to Codex", "发送当前 PDF 到 Codex")
        case .removeHighlight:
            L10n.text("Remove Annotation", "删除批注")
        case .highlightColorPink:
            L10n.text("Highlight Color: \(HighlightColor.pink.menuTitle)", "高亮颜色：\(HighlightColor.pink.menuTitle)")
        case .highlightColorYellow:
            L10n.text("Highlight Color: \(HighlightColor.yellow.menuTitle)", "高亮颜色：\(HighlightColor.yellow.menuTitle)")
        case .highlightColorGreen:
            L10n.text("Highlight Color: \(HighlightColor.green.menuTitle)", "高亮颜色：\(HighlightColor.green.menuTitle)")
        case .toggleLeftSidebar:
            L10n.text("Toggle Left Sidebar", "切换左侧栏")
        case .toggleRightSidebar:
            L10n.text("Toggle Right Sidebar", "切换右侧栏")
        case .useSidebarTabs:
            L10n.text("Use Sidebar Tabs", "使用侧栏标签页")
        case .useTitlebarTabs:
            L10n.text("Use Titlebar Tabs", "使用标题栏标签页")
        case .closeCurrentTab:
            L10n.text("Close Current Tab", "关闭当前标签页")
        case .closeCurrentWindow:
            L10n.text("Close Current Window", "关闭当前窗口")
        case .previousTab:
            L10n.text("Previous Tab", "上一个标签页")
        case .nextTab:
            L10n.text("Next Tab", "下一个标签页")
        case .previousWorkspace:
            L10n.text("Previous Space", "上一个空间")
        case .nextWorkspace:
            L10n.text("Next Space", "下一个空间")
        case .workspace1, .workspace2, .workspace3, .workspace4, .workspace5,
             .workspace6, .workspace7, .workspace8, .workspace9:
            L10n.text("Go to Space \(workspaceIndex!)", "切换至空间 \(workspaceIndex!)")
        case .showAllTabs:
            L10n.text("Show All Tabs", "显示所有标签页")
        case .toggleContinuousReading:
            L10n.text("Toggle Continuous Reading", "切换连续阅读")
        case .fitHeight:
            L10n.text("Fit Height", "适应高度")
        case .fitWidth:
            L10n.text("Fit Width", "适应宽度")
        case .fitTextWidth:
            L10n.text("Fit Text Width", "适应文本宽度")
        case .zoomIn:
            L10n.text("Zoom In", "放大")
        case .zoomOut:
            L10n.text("Zoom Out", "缩小")
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
            L10n.text("Toggle Current Layout Continuity", "切换当前布局的连续模式")
        case .pageDown:
            L10n.text("Next Page", "下一页")
        case .pageUp:
            L10n.text("Previous Page", "上一页")
        case .halfPageDown:
            L10n.text("Half Page Down", "向下半页")
        case .halfPageUp:
            L10n.text("Half Page Up", "向上半页")
        case .goToFirstPage:
            L10n.text("Go to First Page", "跳转到首页")
        case .goToLastPage:
            L10n.text("Go to Last Page", "跳转到末页")
        case .navigateBack:
            L10n.text("Back", "后退")
        case .navigateForward:
            L10n.text("Forward", "前进")
        case .findAllOpen:
            L10n.text("Find in All Open PDFs…", "在所有打开的 PDF 中查找…")
        case .findNextMatch:
            L10n.text("Find Next Match", "查找下一处")
        case .findPreviousMatch:
            L10n.text("Find Previous Match", "查找上一处")
        case .gotoPage:
            L10n.text("Go to Page…", "跳转到页面…")
        case .quickOutline:
            L10n.text("Toggle Outline", "切换目录")
        case .showRecentFilesPalette:
            L10n.text("Open Recent Quickly…", "快速打开最近文件…")
        case .showRecentWindows:
            L10n.text("Recent Windows…", "最近窗口…")
        case .paletteSplitRight:
            L10n.text("Open List Selection in Right Split", "在右侧分屏打开列表选中项")
        case .paletteSplitDown:
            L10n.text("Open List Selection in Split Below", "在下方分屏打开列表选中项")
        case .openContainingFolder:
            L10n.text("Reveal in Finder", "在访达中显示")
        case .reopenLastClosed:
            L10n.text("Reopen Closed Tab", "重新打开已关闭的标签页")
        case .newBlankTab:
            L10n.text("New Blank Tab", "新建空白标签页")
        case .newWindow:
            L10n.text("New Window", "新建窗口")
        case .mergeAllWindows:
            L10n.text("Merge All Windows", "合并所有窗口")
        case .moveCurrentPDFToNewWindow:
            L10n.text("Move Current PDF to New Window", "将当前 PDF 移至新窗口")
        case .toggleAllPagesOverview:
            L10n.text("All Pages Overview", "全部页面概览")
        case .toggleDemoMode:
            L10n.text("Toggle Demo Mode", "切换演示模式")
        case .toggleImmersiveMode:
            L10n.text("Toggle Immersive Mode", "切换沉浸模式")
        case .toggleReaderSplit:
            L10n.text("Toggle Compare Split", "切换对比分屏")
        case .splitCurrentPDFRight:
            L10n.text("Split Current PDF Right", "在右侧分屏打开当前 PDF")
        case .splitCurrentPDFDown:
            L10n.text("Split Current PDF Down", "在下方分屏打开当前 PDF")
        case .focusPaneLeft:
            L10n.text("Focus Pane Left", "聚焦左侧阅读区")
        case .focusPaneDown:
            L10n.text("Focus Pane Below", "聚焦下方阅读区")
        case .focusPaneUp:
            L10n.text("Focus Pane Above", "聚焦上方阅读区")
        case .focusPaneRight:
            L10n.text("Focus Pane Right", "聚焦右侧阅读区")
        case .togglePaneZoom:
            L10n.text("Toggle Pane Zoom", "切换阅读区放大")
        case .toggleRightSidebarMode:
            L10n.text("Toggle Outline / Pages", "切换目录／页面")
        case .swapSidebars:
            L10n.text("Swap Left and Right Sidebars", "交换左右侧栏")
        case .undoLastHighlight:
            L10n.text("Undo Highlight", "撤销高亮")
        case .redoLastHighlight:
            L10n.text("Redo Highlight", "重做高亮")
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
             .addComment, .translateSelection, .exitHighlightMode, .saveAnnotations, .removeHighlight,
             .highlightColorPink, .highlightColorYellow, .highlightColorGreen,
             .undoLastHighlight, .redoLastHighlight, .copyHighlightsMarkdown:
            .annotations
        case .toggleNightMode, .toggleReadingFocus, .adjustReadingFocus,
             .toggleHorizontalPanLock, .toggleGlobalHorizontalPanLock, .toggleSeamlessPages, .switchCurrentTheme, .fitHeight, .fitWidth, .fitTextWidth,
             .zoomIn, .zoomOut, .singlePage, .singlePageContinuous, .twoUp,
             .twoUpContinuous, .book, .bookContinuous, .toggleDisplayModeContinuity,
             .toggleContinuousReading, .toggleAllPagesOverview, .toggleDemoMode:
            .reading
        case .pageDown, .pageUp, .halfPageDown, .halfPageUp, .goToFirstPage,
             .goToLastPage, .navigateBack, .navigateForward, .findAllOpen,
             .findNextMatch, .findPreviousMatch, .gotoPage, .quickOutline:
            .navigation
        case .openLibraryPDF, .refreshLibraryIndex, .openLibrarySettings,
             .openShortcutSettings, .shareDocument, .printDocument, .exportCleanCopy,
             .copyCurrentPDFPath, .copyCurrentPageAsImage, .sendContextToCodex,
             .sendCurrentPDFToCodex, .showRecentFilesPalette, .openContainingFolder,
             .reopenLastClosed, .newBlankTab:
            .documents
        case .toggleLeftSidebar, .toggleRightSidebar, .useSidebarTabs,
             .useTitlebarTabs, .closeCurrentTab, .closeCurrentWindow, .previousTab,
             .nextTab, .showAllTabs, .showRecentWindows, .paletteSplitRight, .paletteSplitDown,
             .previousWorkspace, .nextWorkspace, .workspace1, .workspace2,
             .workspace3, .workspace4, .workspace5, .workspace6, .workspace7, .workspace8, .workspace9,
             .newWindow, .mergeAllWindows,
             .moveCurrentPDFToNewWindow, .toggleImmersiveMode, .toggleReaderSplit,
             .splitCurrentPDFRight, .splitCurrentPDFDown, .focusPaneLeft,
             .focusPaneDown, .focusPaneUp, .focusPaneRight, .togglePaneZoom,
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
        case .annotations: L10n.text("Annotations", "批注")
        case .reading: L10n.text("Reading", "阅读")
        case .navigation: L10n.text("Navigation & Search", "导航与搜索")
        case .documents: L10n.text("Documents & Library", "文档与 PDF 库")
        case .windows: L10n.text("Tabs & Windows", "标签页与窗口")
        }
    }
}
