import XCTest
@testable import Serein

final class CommandPaletteStateTests: XCTestCase {
    func testBuiltInCommandKSequencesAreUniqueAndIncludeShare() throws {
        let sequences = ShortcutCommand.allCases.compactMap(\.builtInShortcutSequence)
        let suffixes = sequences.compactMap(\.strokes.last)

        XCTAssertEqual(sequences.count, 8)
        XCTAssertEqual(Set(suffixes.map(\.serializedValue)).count, suffixes.count)
        XCTAssertEqual(
            ShortcutCommand.shareDocument.builtInShortcutSequence,
            KeyboardShortcutSequence([
                ShortcutCommand.commandPaletteShortcut,
                KeyboardShortcut(key: "e", modifiers: [.command]),
            ])
        )
        XCTAssertEqual(ShortcutCommand.shareDocument.builtInChordDisplay, "⌘K → ⌘E")
    }

    func testFilteringSearchesTitlesSectionsAndShortcutText() {
        var state = CommandPaletteState()
        state.replaceCommands(
            [.highlightSelection, .openLibraryPDF, .toggleReaderSplit],
            bindings: [.toggleReaderSplit: KeyboardShortcut(key: "\\", modifiers: [.command, .control])]
        )

        state.query = "library"
        XCTAssertEqual(state.filteredItems.map(\.command), [.openLibraryPDF])

        state.query = "tabs windows"
        XCTAssertEqual(state.filteredItems.map(\.command), [.toggleReaderSplit])

        state.query = "highlight"
        XCTAssertEqual(state.highlightedItem?.command, .highlightSelection)
    }

    func testCommandItemShowsDirectAndBuiltInSequencesTogether() throws {
        let direct = KeyboardShortcut(key: "o", modifiers: [.command, .option])
        let item = CommandPaletteItem(command: .openLibraryPDF, binding: direct)

        XCTAssertEqual(
            item.shortcutSequences,
            [
                KeyboardShortcutSequence([direct]),
                try XCTUnwrap(ShortcutCommand.openLibraryPDF.builtInShortcutSequence),
            ]
        )
    }

    func testFilteringIncludesContextualTitle() {
        var state = CommandPaletteState()
        state.replaceCommands(
            [.closeCurrentTab],
            bindings: [:],
            titles: [.closeCurrentTab: "Close Selected Tabs"]
        )

        state.query = "selected tabs"

        XCTAssertEqual(state.filteredItems.map(\.command), [.closeCurrentTab])
    }
}
