import Foundation
import PDFKit

struct DocumentSearchMatch {
    let matchIndex: Int
    let pageIndex: Int
    let textRange: NSRange
    let matchedText: String
    let previewText: String
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
    let textRange: NSRange
    let matchedText: String
    let previewText: String
}

struct SearchSidebarSection {
    let title: String
    let matches: [SearchSidebarMatch]
}

struct SearchSnapshotSource: Equatable {
    struct Target: Equatable {
        let sessionID: UUID
        let sessionTitle: String
        let url: URL
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
    let isSearching: Bool

    var query: String { source.query }
    var scope: SearchScope { source.scope }
    var options: SearchOptions { source.options }

    func matches(for sessionID: UUID) -> [DocumentSearchMatch] {
        matchesBySessionID[sessionID] ?? []
    }

    static func make(
        source: SearchSnapshotSource,
        matchesBySessionID: [UUID: [DocumentSearchMatch]],
        isSearching: Bool
    ) -> SearchSnapshot {
        let sidebarMatch: (DocumentSearchMatch, SearchSnapshotSource.Target) -> SearchSidebarMatch = {
            match, target in
            SearchSidebarMatch(
                sessionID: target.sessionID,
                sessionTitle: target.sessionTitle,
                matchIndex: match.matchIndex,
                pageIndex: match.pageIndex,
                textRange: match.textRange,
                matchedText: match.matchedText,
                previewText: match.previewText
            )
        }

        let sections: [SearchSidebarSection]
        switch source.scope {
        case .currentDocument:
            guard let target = source.targets.first else {
                sections = []
                break
            }
            let grouped = Dictionary(
                grouping: matchesBySessionID[target.sessionID, default: []],
                by: \DocumentSearchMatch.pageIndex
            )
            sections = grouped.keys.sorted().map { pageIndex in
                SearchSidebarSection(
                    title: "Page \(pageIndex + 1)",
                    matches: grouped[pageIndex, default: []].map { sidebarMatch($0, target) }
                )
            }
        case .allOpen:
            sections = source.targets.compactMap { target in
                let matches = matchesBySessionID[target.sessionID, default: []]
                guard matches.isEmpty == false else { return nil }
                return SearchSidebarSection(
                    title: target.sessionTitle,
                    matches: matches.map { sidebarMatch($0, target) }
                )
            }
        }

        return SearchSnapshot(
            source: source,
            sections: sections,
            matchesBySessionID: matchesBySessionID,
            totalMatches: matchesBySessionID.values.reduce(0) { $0 + $1.count },
            isSearching: isSearching
        )
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
            totalMatches: 0,
            isSearching: false
        )
    }
}

/// One cancellable PDFKit search per window. Each target uses its own short-lived,
/// read-only PDFDocument so searching never pins the reader's live document cache.
@MainActor
final class DocumentSearchOperation: NSObject {
    typealias UpdateHandler = ([UUID: [DocumentSearchMatch]], Bool) -> Void

    let source: SearchSnapshotSource
    var onUpdate: UpdateHandler?

    private var matchesBySessionID: [UUID: [DocumentSearchMatch]]
    private var targetIndex = 0
    private var currentDocument: PDFDocument?
    private var currentMatches: [DocumentSearchMatch] = []
    private var currentTextContext = DocumentSearchTextContext()
    private var isCancelled = false

    init(
        source: SearchSnapshotSource,
        cachedMatchesBySessionID: [UUID: [DocumentSearchMatch]] = [:]
    ) {
        self.source = source
        matchesBySessionID = cachedMatchesBySessionID
        super.init()
    }

    func start() {
        guard isCancelled == false else { return }
        onUpdate?(matchesBySessionID, source.targets.isEmpty == false)
        advanceToNextTarget()
    }

    func cancel() {
        guard isCancelled == false else { return }
        isCancelled = true
        removeObservers()
        currentDocument?.cancelFindString()
        currentDocument = nil
        currentTextContext = DocumentSearchTextContext()
        currentMatches = []
        onUpdate = nil
    }

    private func advanceToNextTarget() {
        guard isCancelled == false else { return }

        while source.targets.indices.contains(targetIndex),
              matchesBySessionID[source.targets[targetIndex].sessionID] != nil {
            targetIndex += 1
        }

        guard source.targets.indices.contains(targetIndex) else {
            onUpdate?(matchesBySessionID, false)
            return
        }

        let target = source.targets[targetIndex]
        guard let document = PDFDocument(url: target.url) else {
            matchesBySessionID[target.sessionID] = []
            targetIndex += 1
            onUpdate?(matchesBySessionID, true)
            DispatchQueue.main.async { [weak self] in
                self?.advanceToNextTarget()
            }
            return
        }

        currentDocument = document
        currentMatches = []
        currentTextContext = DocumentSearchTextContext()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(consumeMatchNotification(_:)),
            name: .PDFDocumentDidFindMatch,
            object: document
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(finishCurrentTargetNotification(_:)),
            name: .PDFDocumentDidEndFind,
            object: document
        )

        let compareOptions: NSString.CompareOptions = source.options.isCaseSensitive ? [] : .caseInsensitive
        document.beginFindString(source.query, withOptions: compareOptions)
    }

    @objc
    private func consumeMatchNotification(_ notification: Notification) {
        guard isCancelled == false,
              let document = currentDocument,
              let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection,
              let match = DocumentSearchService.makeMatch(
                from: selection,
                query: source.query,
                options: source.options,
                matchIndex: currentMatches.count,
                in: document,
                textContext: &currentTextContext
              ) else { return }
        currentMatches.append(match)
    }

    @objc
    private func finishCurrentTargetNotification(_ notification: Notification) {
        guard isCancelled == false,
              source.targets.indices.contains(targetIndex) else { return }
        let target = source.targets[targetIndex]
        removeObservers()
        matchesBySessionID[target.sessionID] = currentMatches
        currentMatches = []
        currentDocument = nil
        currentTextContext = DocumentSearchTextContext()
        targetIndex += 1
        let hasMoreTargets = targetIndex < source.targets.count
        onUpdate?(matchesBySessionID, hasMoreTargets)
        if hasMoreTargets {
            DispatchQueue.main.async { [weak self] in
                self?.advanceToNextTarget()
            }
        }
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .PDFDocumentDidFindMatch, object: currentDocument)
        NotificationCenter.default.removeObserver(self, name: .PDFDocumentDidEndFind, object: currentDocument)
    }
}

private struct DocumentSearchTextContext {
    var pageIndex: Int?
    var pageText = ""
}

private enum DocumentSearchService {
    private static let wordCharacters = CharacterSet.alphanumerics
        .union(.nonBaseCharacters)
        .union(CharacterSet(charactersIn: "_"))

    static func makeMatch(
        from selection: PDFSelection,
        query: String,
        options: SearchOptions,
        matchIndex: Int,
        in document: PDFDocument,
        textContext: inout DocumentSearchTextContext
    ) -> DocumentSearchMatch? {
        guard let page = selection.pages.first else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let textRange = selection.range(at: 0, on: page)
        guard textRange.location != NSNotFound, textRange.length > 0 else { return nil }
        if textContext.pageIndex != pageIndex {
            textContext.pageIndex = pageIndex
            textContext.pageText = page.string ?? ""
        }
        let pageText = textContext.pageText
        if options.matchesWholeWords,
           selectionMatchesWholeWord(textRange, in: pageText) == false {
            return nil
        }
        let matchRange = Range(textRange, in: pageText)
        let matchedText = normalize(selection.string ?? query)

        return DocumentSearchMatch(
            matchIndex: matchIndex,
            pageIndex: pageIndex,
            textRange: textRange,
            matchedText: matchedText,
            previewText: previewSnippet(in: pageText, around: matchRange, fallback: matchedText)
        )
    }

    private static func selectionMatchesWholeWord(_ range: NSRange, in pageText: String) -> Bool {
        let text = pageText as NSString
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
        let snippet = normalize(String(pageText[prefixStart..<suffixEnd]))
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
