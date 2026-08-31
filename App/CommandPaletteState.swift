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
        if let binding {
            sequences.append(KeyboardShortcutSequence([binding]))
        }
        if let builtInSequence = command.builtInShortcutSequence {
            sequences.append(builtInSequence)
        }
        shortcutSequences = sequences
    }

    func matches(query: String, binding: KeyboardShortcut?) -> Bool {
        command.matchesShortcutSearch(query, binding: binding, additionalText: title)
    }
}

struct CommandPaletteState {
    private(set) var allItems: [CommandPaletteItem] = []
    private(set) var filteredItems: [CommandPaletteItem] = []
    private(set) var highlightedIndex: Int?
    private var bindings: [ShortcutCommand: KeyboardShortcut] = [:]

    var query = "" {
        didSet { applyFilter() }
    }

    var highlightedItem: CommandPaletteItem? {
        guard let highlightedIndex, filteredItems.indices.contains(highlightedIndex) else { return nil }
        return filteredItems[highlightedIndex]
    }

    mutating func replaceCommands(
        _ commands: [ShortcutCommand],
        bindings: [ShortcutCommand: KeyboardShortcut],
        titles: [ShortcutCommand: String] = [:]
    ) {
        let availableCommands = Set(commands)
        self.bindings = bindings
        allItems = ShortcutCommand.allCases
            .filter(availableCommands.contains)
            .map { CommandPaletteItem(command: $0, binding: bindings[$0], title: titles[$0]) }
        applyFilter()
    }

    mutating func moveHighlight(delta: Int) {
        guard filteredItems.isEmpty == false else {
            highlightedIndex = nil
            return
        }
        let current = highlightedIndex ?? 0
        highlightedIndex = (current + delta + filteredItems.count) % filteredItems.count
    }

    mutating func setHighlightedIndex(_ index: Int?) {
        guard let index, filteredItems.indices.contains(index) else {
            highlightedIndex = filteredItems.isEmpty ? nil : 0
            return
        }
        highlightedIndex = index
    }

    private mutating func applyFilter() {
        filteredItems = allItems.filter { item in
            item.matches(query: query, binding: bindings[item.command])
        }
        highlightedIndex = filteredItems.isEmpty ? nil : 0
    }
}
