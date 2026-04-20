import Foundation
import PDFKit

struct DocumentHighlightGroup {
    let groupID: String
    let pageIndex: Int
    let snippet: String
    let color: HighlightColor
    let createdAt: Date?
    let comment: String
    let primarySelection: PDFSelection?
    let records: [HighlightAnnotationRecord]

    var normalizedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var commentPreview: String {
        let trimmed = normalizedComment
        guard trimmed.isEmpty == false else { return "No comment" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

struct DocumentHighlightSection {
    let title: String
    let highlights: [DocumentHighlightGroup]
}

struct DocumentHighlightCache {
    var groups: [DocumentHighlightGroup] = []

    mutating func clear() {
        groups.removeAll(keepingCapacity: false)
    }
}

struct ExportedHighlight: Codable, Equatable {
    let page: Int
    let snippet: String
    let color: String
    let comment: String?
    let createdAt: String?
}

enum HighlightExportFormat: String, CaseIterable {
    case markdown
    case plainText = "plain_text"
    case json

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .plainText:
            "Plain Text"
        case .json:
            "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .plainText:
            "txt"
        case .json:
            "json"
        }
    }
}
