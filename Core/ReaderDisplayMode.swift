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

enum ReaderCommand: String, CaseIterable, Sendable {
    case fitWidth = "fit_width"
    case singlePage = "single_page"
    case singlePageContinuous = "single_page_continuous"
    case twoUp = "two_up"
    case twoUpContinuous = "two_up_continuous"

    var menuTitle: String {
        switch self {
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
