import Foundation

struct RecentFilesPaletteItem: Equatable, Sendable {
    let url: URL
    let title: String
    let subtitle: String
    private let normalizedTitle: String
    private let normalizedSubtitle: String

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.subtitle = url.path
        self.normalizedTitle = Self.normalize(title)
        self.normalizedSubtitle = Self.normalize(subtitle)
    }

    func matches(query: String) -> Bool {
        let normalizedQuery = Self.normalize(query)
        guard normalizedQuery.isEmpty == false else { return true }
        return normalizedTitle.contains(normalizedQuery) || normalizedSubtitle.contains(normalizedQuery)
    }

    private static func normalize(_ string: String) -> String {
        String(
            string
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .unicodeScalars
                .filter { scalar in
                    CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
                    CharacterSet.punctuationCharacters.contains(scalar) == false &&
                    CharacterSet.symbols.contains(scalar) == false
                }
        )
    }
}

struct RecentFilesPaletteState {
    private(set) var allItems: [RecentFilesPaletteItem]
    private(set) var filteredItems: [RecentFilesPaletteItem]
    private(set) var selectedURLs: [URL]
    private(set) var highlightedIndex: Int?
    var query: String {
        didSet { rebuildFilteredItems() }
    }
    var isHelpVisible: Bool

    init(recentURLs: [URL]) {
        let items = recentURLs.map(RecentFilesPaletteItem.init(url:))
        self.allItems = items
        self.filteredItems = items
        self.selectedURLs = []
        self.highlightedIndex = items.isEmpty ? nil : 0
        self.query = ""
        self.isHelpVisible = false
    }

    var highlightedItem: RecentFilesPaletteItem? {
        guard let highlightedIndex,
              filteredItems.indices.contains(highlightedIndex) else { return nil }
        return filteredItems[highlightedIndex]
    }

    mutating func replaceRecentURLs(_ urls: [URL]) {
        allItems = urls.map(RecentFilesPaletteItem.init(url:))
        query = ""
        selectedURLs = []
        isHelpVisible = false
        rebuildFilteredItems()
    }

    mutating func appendToQuery(_ string: String) {
        guard string.isEmpty == false else { return }
        query.append(string)
    }

    mutating func deleteBackward() {
        guard query.isEmpty == false else { return }
        query.removeLast()
    }

    mutating func moveHighlight(delta: Int) {
        guard filteredItems.isEmpty == false else {
            highlightedIndex = nil
            return
        }
        let current = highlightedIndex ?? 0
        let count = filteredItems.count
        highlightedIndex = (current + delta + count) % count
    }

    mutating func setHighlightedIndex(_ index: Int?) {
        guard let index else {
            highlightedIndex = filteredItems.isEmpty ? nil : 0
            return
        }
        guard filteredItems.indices.contains(index) else { return }
        highlightedIndex = index
    }

    mutating func toggleSelectionForHighlightedItem() {
        guard let url = highlightedItem?.url else { return }
        if let existingIndex = selectedURLs.firstIndex(of: url) {
            selectedURLs.remove(at: existingIndex)
        } else {
            selectedURLs.append(url)
        }
    }

    mutating func toggleHelp() {
        isHelpVisible.toggle()
    }

    func isSelected(_ url: URL) -> Bool {
        selectedURLs.contains(url)
    }

    func openTargets() -> [URL] {
        if selectedURLs.isEmpty == false {
            return filteredItems
                .map(\.url)
                .filter { selectedURLs.contains($0) }
        }
        return highlightedItem.map { [$0.url] } ?? []
    }

    private mutating func rebuildFilteredItems() {
        filteredItems = allItems.filter { $0.matches(query: query) }
        selectedURLs = selectedURLs.filter { url in
            filteredItems.contains { $0.url == url }
        }

        guard filteredItems.isEmpty == false else {
            highlightedIndex = nil
            return
        }

        if let highlightedIndex, filteredItems.indices.contains(highlightedIndex) {
            return
        }
        highlightedIndex = 0
    }
}
