import Foundation
import PDFKit

struct DocumentSearchMatch {
    let matchIndex: Int
    let pageIndex: Int
    let matchedText: String
    let previewText: String
    let selection: PDFSelection
}

struct SearchOptions: Equatable, Sendable {
    var isCaseSensitive: Bool = false
    var matchesWholeWords: Bool = false

    static let `default` = SearchOptions()
}

struct DocumentSearchCache {
    var query: String = ""
    var options: SearchOptions = .default
    var matches: [DocumentSearchMatch] = []

    mutating func clear() {
        query = ""
        options = .default
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

struct SearchSnapshotSource: Equatable {
    struct Target: Equatable {
        let sessionID: UUID
        let sessionTitle: String
        let fileSnapshot: PDFFileSnapshot?
    }

    let query: String
    let scope: SearchScope
    let options: SearchOptions
    let targets: [Target]
}

struct SearchSnapshot {
    let source: SearchSnapshotSource
    let sections: [SearchSidebarSection]
    let matchesBySessionID: [UUID: [DocumentSearchMatch]]
    let totalMatches: Int

    var query: String { source.query }
    var scope: SearchScope { source.scope }
    var options: SearchOptions { source.options }

    func matches(for sessionID: UUID) -> [DocumentSearchMatch] {
        matchesBySessionID[sessionID] ?? []
    }

    static func empty(
        query: String = "",
        scope: SearchScope = .currentDocument,
        options: SearchOptions = .default
    ) -> SearchSnapshot {
        SearchSnapshot(
            source: SearchSnapshotSource(query: query, scope: scope, options: options, targets: []),
            sections: [],
            matchesBySessionID: [:],
            totalMatches: 0
        )
    }
}

enum DocumentSearchService {
    private static let wordCharacters = CharacterSet.alphanumerics
        .union(.nonBaseCharacters)
        .union(CharacterSet(charactersIn: "_"))

    static func buildMatches(
        for query: String,
        options: SearchOptions = .default,
        in document: PDFDocument
    ) -> [DocumentSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let compareOptions: NSString.CompareOptions = options.isCaseSensitive ? [] : .caseInsensitive
        let selections = document.findString(trimmed, withOptions: compareOptions)
        var nextSearchStartByPage: [Int: String.Index] = [:]

        var matchIndex = 0
        return selections.compactMap { selection in
            guard let page = selection.pages.first else { return nil }
            if options.matchesWholeWords,
               selectionMatchesWholeWord(selection, on: page) == false {
                return nil
            }
            let pageIndex = document.index(for: page)
            let matchedText = normalize(selection.string ?? trimmed)
            let pageText = normalize(page.string ?? matchedText)

            let searchRange = (nextSearchStartByPage[pageIndex] ?? pageText.startIndex)..<pageText.endIndex
            let matchRange =
                pageText.range(of: matchedText, options: compareOptions, range: searchRange)
                ?? pageText.range(of: normalize(trimmed), options: compareOptions, range: searchRange)
                ?? pageText.range(of: matchedText, options: compareOptions)
                ?? pageText.range(of: normalize(trimmed), options: compareOptions)

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

    private static func selectionMatchesWholeWord(_ selection: PDFSelection, on page: PDFPage) -> Bool {
        guard let pageText = page.string else { return false }
        let text = pageText as NSString
        let range = selection.range(at: 0, on: page)
        guard range.location != NSNotFound,
              range.length > 0,
              range.location >= 0,
              NSMaxRange(range) <= text.length else { return false }

        let startsWithWordCharacter = isWordCharacter(in: text, at: range.location)
        let endsWithWordCharacter = isWordCharacter(in: text, at: NSMaxRange(range) - 1)
        let hasWordCharacterBefore = range.location > 0
            && isWordCharacter(in: text, at: range.location - 1)
        let hasWordCharacterAfter = NSMaxRange(range) < text.length
            && isWordCharacter(in: text, at: NSMaxRange(range))

        return (startsWithWordCharacter == false || hasWordCharacterBefore == false)
            && (endsWithWordCharacter == false || hasWordCharacterAfter == false)
    }

    private static func isWordCharacter(in text: NSString, at index: Int) -> Bool {
        guard index >= 0, index < text.length else { return false }
        let range = text.rangeOfComposedCharacterSequence(at: index)
        return text.substring(with: range).unicodeScalars.contains { wordCharacters.contains($0) }
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
