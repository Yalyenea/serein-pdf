import Foundation

struct CommandPaletteItem: Equatable, Sendable {
    let command: ShortcutCommand
    let title: String
    let section: ShortcutSection
    let shortcutSequences: [KeyboardShortcutSequence]

    init(command: ShortcutCommand, binding: KeyboardShortcut?, title: String? = nil) {
        self.command = command
        self.title = title ?? command.menuTitle
        section = command.shortcutSection
        var sequences: [KeyboardShortcutSequence] = []
        if let binding { sequences.append(KeyboardShortcutSequence([binding])) }
        if let builtIn = command.builtInShortcutSequence { sequences.append(builtIn) }
        shortcutSequences = sequences
    }

    var shortcutTitle: String {
        shortcutSequences.map { $0.strokes.map(\.displayString).joined(separator: " → ") }
            .joined(separator: " / ")
    }
}

struct CommandPaletteState {
    private(set) var allItems: [CommandPaletteItem] = []
    private(set) var rows: [[Int]] = []
    private(set) var highlightedIndex: Int?

    var highlightedItem: CommandPaletteItem? {
        guard let highlightedIndex else { return nil }
        return allItems[highlightedIndex]
    }

    mutating func replaceCommands(
        _ commands: [ShortcutCommand],
        bindings: [ShortcutCommand: KeyboardShortcut],
        titles: [ShortcutCommand: String] = [:]
    ) {
        let available = Set(commands)
        allItems = ShortcutSection.allCases.flatMap { section in
            ShortcutCommand.allCases.filter { available.contains($0) && $0.shortcutSection == section }
                .map { CommandPaletteItem(command: $0, binding: bindings[$0], title: titles[$0]) }
        }
        rows = []
        for index in allItems.indices {
            if let last = rows.last, last.count == 1, allItems[last[0]].section == allItems[index].section {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        highlightedIndex = allItems.isEmpty ? nil : 0
    }

    mutating func moveHighlight(horizontal: Int = 0, vertical: Int = 0) {
        guard let highlightedIndex else {
            self.highlightedIndex = allItems.isEmpty ? nil : 0
            return
        }
        guard let row = rows.firstIndex(where: { $0.contains(highlightedIndex) }),
              let column = rows[row].firstIndex(of: highlightedIndex) else { return }
        let targetRow = min(max(row + vertical, 0), rows.count - 1)
        let targetColumn = min(max(column + horizontal, 0), rows[targetRow].count - 1)
        self.highlightedIndex = rows[targetRow][targetColumn]
    }

    mutating func setHighlightedIndex(_ index: Int?) {
        guard let index else {
            highlightedIndex = nil
            return
        }
        guard allItems.indices.contains(index) else { return }
        highlightedIndex = index
    }
}
