import AppKit
import XCTest
@testable import SlatePDF

private final class PDFMockTextView: NSTextView {}

@MainActor
final class ReaderShortcutsControllerTests: XCTestCase {
    func testHandlePlainShortcutInvokesMatchingHandler() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.toggleNightMode: KeyboardShortcut(key: "i", modifiers: [])]
            },
            handlerProvider: {
                [.toggleNightMode: { triggeredCommands.append(.toggleNightMode) }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "i", modifiers: [])

        XCTAssertTrue(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertEqual(triggeredCommands, [.toggleNightMode])
    }

    func testHandlePlainShortcutSkipsEditableTextView() {
        var didTrigger = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.highlightSelection: KeyboardShortcut(key: "a", modifiers: [])]
            },
            handlerProvider: {
                [.highlightSelection: { didTrigger = true }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = NSTextView()
        window.contentView = textView
        window.makeFirstResponder(textView)
        let event = makeKeyEvent(characters: "a", modifiers: [])

        XCTAssertFalse(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertFalse(didTrigger)
    }

    func testPlainShortcutsAreBlockedWhileEditingText() {
        let textView = NSTextView()

        XCTAssertFalse(ReaderShortcutsController.shouldHandlePlainShortcut(for: textView))
    }

    func testPlainShortcutsAreAllowedForNonTextResponders() {
        XCTAssertTrue(ReaderShortcutsController.shouldHandlePlainShortcut(for: NSView()))
        XCTAssertTrue(ReaderShortcutsController.shouldHandlePlainShortcut(for: nil))
    }

    func testPlainShortcutsAreAllowedForPDFTextResponders() {
        XCTAssertTrue(ReaderShortcutsController.shouldHandlePlainShortcut(for: PDFMockTextView()))
    }

    func testEscapeShortcutUsesEscapeMenuKeyEquivalent() {
        let shortcut = KeyboardShortcut(key: "escape", modifiers: [])

        XCTAssertEqual(shortcut.menuKeyEquivalent, "\u{1b}")
        XCTAssertTrue(shortcut.isPlainShortcut)
    }

    private func makeKeyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
