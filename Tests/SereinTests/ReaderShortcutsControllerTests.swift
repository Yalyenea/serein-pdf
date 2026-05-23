import AppKit
import XCTest
@testable import Serein

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

    func testHandlePlainShortcutDoesNotConsumeCommandWithoutHandler() {
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.fitWidth: KeyboardShortcut(key: "f", modifiers: [])]
            },
            handlerProvider: { [:] }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "f", modifiers: [])

        XCTAssertFalse(controller.handlePlainShortcut(for: event, in: window))
    }

    func testPlainCInvokesSinglePageContinuousSupplementalShortcut() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command])]
            },
            handlerProvider: {
                [.singlePageContinuous: { triggeredCommands.append(.singlePageContinuous) }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "c", modifiers: [])

        XCTAssertTrue(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertEqual(triggeredCommands, [.singlePageContinuous])
    }

    func testPlainCUsesSupplementalToggleHandlerWhenProvided() {
        var triggeredCommands: [String] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.singlePageContinuous: KeyboardShortcut(key: "2", modifiers: [.command])]
            },
            handlerProvider: {
                [.singlePageContinuous: { triggeredCommands.append("cmd-2") }]
            },
            supplementalHandlerProvider: {
                [.singlePageContinuous: { triggeredCommands.append("toggle-c") }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "c", modifiers: [])

        XCTAssertTrue(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertEqual(triggeredCommands, ["toggle-c"])
    }

    func testPlainCSupplementalShortcutRespectsClearedSinglePageContinuousBinding() {
        var didTrigger = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.singlePageContinuous: { didTrigger = true }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "c", modifiers: [])

        XCTAssertFalse(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertFalse(didTrigger)
    }

    func testThemeChordInvokesSwitchCurrentTheme() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.switchCurrentTheme: { triggeredCommands.append(.switchCurrentTheme) }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifiers: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "t", modifiers: [.command]), in: window))
        XCTAssertEqual(triggeredCommands, [.switchCurrentTheme])
    }

    func testCommandTMenuShortcutDoesNotBlockThemeChord() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.newBlankTab: KeyboardShortcut(key: "t", modifiers: [.command])]
            },
            handlerProvider: {
                [
                    .newBlankTab: { triggeredCommands.append(.newBlankTab) },
                    .switchCurrentTheme: { triggeredCommands.append(.switchCurrentTheme) },
                ]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "t", modifiers: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifiers: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "t", modifiers: [.command]), in: window))
        XCTAssertEqual(triggeredCommands, [.switchCurrentTheme])
    }

    func testLibraryChordInvokesOpenLibraryPDF() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.openLibraryPDF: { triggeredCommands.append(.openLibraryPDF) }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifiers: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "o", modifiers: [.command]), in: window))
        XCTAssertEqual(triggeredCommands, [.openLibraryPDF])
    }

    func testAdditionalCommandKChordsInvokeHandlers() {
        let cases: [(String, ShortcutCommand)] = [
            ("r", .refreshLibraryIndex),
            ("l", .openLibrarySettings),
            ("s", .openShortcutSettings),
            ("m", .mergeAllWindows),
            ("n", .moveCurrentPDFToNewWindow),
        ]

        for (key, command) in cases {
            var triggeredCommands: [ShortcutCommand] = []
            let controller = ReaderShortcutsController(
                shortcutsProvider: { [:] },
                handlerProvider: {
                    [command: { triggeredCommands.append(command) }]
                }
            )
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)

            XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifiers: [.command]), in: window))
            XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: key, modifiers: [.command]), in: window))
            XCTAssertEqual(triggeredCommands, [command])
        }
    }

    func testReaderWindowChecksShortcutHandlerBeforeMenuKeyEquivalent() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var handledEvents: [String] = []
        window.plainShortcutHandler = { event, _ in
            handledEvents.append(event.charactersIgnoringModifiers ?? "")
            return true
        }

        XCTAssertTrue(window.performKeyEquivalent(with: makeKeyEvent(characters: "o", modifiers: [.command])))
        XCTAssertEqual(handledEvents, ["o"])
    }

    func testThemeChordDoesNotRunWhileEditingText() {
        var didTrigger = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.switchCurrentTheme: { didTrigger = true }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = NSTextView()
        window.contentView = textView
        window.makeFirstResponder(textView)

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifiers: [.command]), in: window))
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
