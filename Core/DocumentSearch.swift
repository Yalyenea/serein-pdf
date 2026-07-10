import Foundation
import PDFKit

struct DocumentSearchMatch {
    let matchIndex: Int
    let pageIndex: Int
    let matchedText: String
    let previewText: String
    let selection: PDFSelection
}

struct DocumentSearchCache {
    var query: String = ""
    var matches: [DocumentSearchMatch] = []

    mutating func clear() {
        query = ""
        matches = []
    }
}

struct SearchSidebarMatch {
    let sessionID: UUID
    let sessionTitle: String
    let matchIndex: Int
    let pageIndex: Int
    let matchedText: String
    let previewText: String
    let selection: PDFSelection
}

struct SearchSidebarSection {
    let title: String
    let matches: [SearchSidebarMatch]
}

enum DocumentSearchService {
    static func buildMatches(for query: String, in document: PDFDocument) -> [DocumentSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let selections = document.findString(trimmed, withOptions: .caseInsensitive)
        var nextSearchStartByPage: [Int: String.Index] = [:]

        var matchIndex = 0
        return selections.compactMap { selection in
            guard let page = selection.pages.first else { return nil }
            let pageIndex = document.index(for: page)
            let matchedText = normalize(selection.string ?? trimmed)
            let pageText = normalize(page.string ?? matchedText)

            let searchRange = (nextSearchStartByPage[pageIndex] ?? pageText.startIndex)..<pageText.endIndex
            let matchRange =
                pageText.range(of: matchedText, options: .caseInsensitive, range: searchRange)
                ?? pageText.range(of: normalize(trimmed), options: .caseInsensitive, range: searchRange)
                ?? pageText.range(of: matchedText, options: .caseInsensitive)
                ?? pageText.range(of: normalize(trimmed), options: .caseInsensitive)

            if let matchRange {
                nextSearchStartByPage[pageIndex] = matchRange.upperBound
            }

            let match = DocumentSearchMatch(
                matchIndex: matchIndex,
                pageIndex: pageIndex,
                matchedText: matchedText,
                previewText: previewSnippet(in: pageText, around: matchRange, fallback: matchedText),
                selection: selection
            )
            matchIndex += 1
            return match
        }
    }

    private static func previewSnippet(
        in pageText: String,
        around range: Range<String.Index>?,
        fallback: String
    ) -> String {
        guard let range else { return fallback }

        let prefixStart = pageText.index(range.lowerBound, offsetBy: -36, limitedBy: pageText.startIndex)
            ?? pageText.startIndex
        let suffixEnd = pageText.index(range.upperBound, offsetBy: 44, limitedBy: pageText.endIndex)
            ?? pageText.endIndex
        let snippet = pageText[prefixStart..<suffixEnd]
        let trimmedPrefix = prefixStart == pageText.startIndex ? "" : "…"
        let trimmedSuffix = suffixEnd == pageText.endIndex ? "" : "…"
        return "\(trimmedPrefix)\(snippet)\(trimmedSuffix)"
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
