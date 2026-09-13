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

    func testGridNavigationCrossesSectionsAndClampsAtEdges() {
        var state = CommandPaletteState()
        state.replaceCommands([.highlightSelection, .underlineSelection, .addComment, .openLibraryPDF], bindings: [:])
        XCTAssertEqual(state.rows.map(\.count), [2, 1, 1])
        state.moveHighlight(horizontal: 1)
        XCTAssertEqual(state.highlightedIndex, 1)
        state.moveHighlight(vertical: 1)
        XCTAssertEqual(state.highlightedIndex, 2)
        state.moveHighlight(vertical: 1)
        XCTAssertEqual(state.highlightedItem?.command, .openLibraryPDF)
        state.moveHighlight(vertical: 1)
        XCTAssertEqual(state.highlightedItem?.command, .openLibraryPDF)
        state.moveHighlight(vertical: -1)
        state.moveHighlight(vertical: -1)
        XCTAssertEqual(state.highlightedIndex, 0)
        state.moveHighlight(horizontal: -1)
        XCTAssertEqual(state.highlightedIndex, 0)
        state.replaceCommands([], bindings: [:])
        state.moveHighlight(vertical: 1)
        XCTAssertNil(state.highlightedItem)
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

    func testContextualTitleIsPreserved() {
        var state = CommandPaletteState()
        state.replaceCommands([.closeCurrentTab], bindings: [:], titles: [.closeCurrentTab: "Close Selected Tabs"])
        XCTAssertEqual(state.highlightedItem?.title, "Close Selected Tabs")
    }
}
