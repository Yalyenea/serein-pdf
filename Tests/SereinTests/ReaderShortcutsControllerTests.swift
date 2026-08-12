import AppKit
import IOKit
import XCTest
@testable import Serein

private final class PDFMockTextView: NSTextView {}

@MainActor
final class ReaderShortcutsControllerTests: XCTestCase {
    func testHighlightModeNumberKeysSelectPinkYellowAndGreen() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [
                    .highlightColorPink: { triggeredCommands.append(.highlightColorPink) },
                    .highlightColorYellow: { triggeredCommands.append(.highlightColorYellow) },
                    .highlightColorGreen: { triggeredCommands.append(.highlightColorGreen) },
                ]
            },
            isHighlightModeEnabledProvider: { _ in true }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifiers: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "2", modifiers: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "3", modifiers: []), in: window))
        XCTAssertEqual(
            triggeredCommands,
            [.highlightColorPink, .highlightColorYellow, .highlightColorGreen]
        )
    }

    func testHighlightModeNumberKeysRequireActiveModeAndNoModifiers() {
        var didTrigger = false
        let disabledController = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.highlightColorPink: { didTrigger = true }]
            },
            isHighlightModeEnabledProvider: { _ in false }
        )
        let enabledController = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.highlightColorPink: { didTrigger = true }]
            },
            isHighlightModeEnabledProvider: { _ in true }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(disabledController.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifiers: []), in: window))
        XCTAssertFalse(
            enabledController.handleShortcutEvent(
                for: makeKeyEvent(characters: "1", modifiers: [.command]),
                in: window
            )
        )
        XCTAssertFalse(didTrigger)
    }

    func testHighlightModeNumberKeysRespectEditableTextInput() {
        var didTrigger = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.highlightColorPink: { didTrigger = true }]
            },
            isHighlightModeEnabledProvider: { _ in true }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView()
        window.contentView = textView
        window.makeFirstResponder(textView)

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifiers: []), in: window))
        XCTAssertFalse(didTrigger)
    }

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

    func testPlainFTogglesReadingFocus() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.toggleReadingFocus: KeyboardShortcut(key: "f", modifiers: [])]
            },
            handlerProvider: {
                [.toggleReadingFocus: { triggeredCommands.append(.toggleReadingFocus) }]
            }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(
            controller.handlePlainShortcut(
                for: makeKeyEvent(characters: "f", modifiers: []),
                in: window
            )
        )
        XCTAssertEqual(triggeredCommands, [.toggleReadingFocus])
    }

    func testPlainLTogglesHorizontalPanLock() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.toggleHorizontalPanLock: KeyboardShortcut(key: "l", modifiers: [])]
            },
            handlerProvider: {
                [.toggleHorizontalPanLock: { triggeredCommands.append(.toggleHorizontalPanLock) }]
            }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(
            controller.handlePlainShortcut(
                for: makeKeyEvent(characters: "l", modifiers: []),
                in: window
            )
        )
        XCTAssertEqual(triggeredCommands, [.toggleHorizontalPanLock])
    }

    func testOptionFReadingFocusShortcutMatchesModifiedCharacterEvent() {
        let shortcut = KeyboardShortcut(key: "f", modifiers: [.option])
        let event = makeKeyEvent(
            characters: "ƒ",
            charactersIgnoringModifiers: "f",
            modifiers: [.option]
        )

        XCTAssertTrue(shortcut.matches(event: event))
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
            ("e", .shareDocument),
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

    func testReaderWindowRoutesNavigationShortcutsWithoutMenuState() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [
                    .navigateBack: KeyboardShortcut(key: "[", modifiers: [.command]),
                    .navigateForward: KeyboardShortcut(key: "]", modifiers: [.command]),
                ]
            },
            handlerProvider: {
                [
                    .navigateBack: { triggeredCommands.append(.navigateBack) },
                    .navigateForward: { triggeredCommands.append(.navigateForward) },
                ]
            }
        )
        window.plainShortcutHandler = { event, window in
            controller.handleShortcutEvent(for: event, in: window)
        }

        XCTAssertTrue(
            window.performKeyEquivalent(
                with: makeKeyEvent(characters: "[", modifiers: [.command])
            )
        )
        XCTAssertTrue(
            window.performKeyEquivalent(
                with: makeKeyEvent(characters: "]", modifiers: [.command])
            )
        )
        XCTAssertEqual(triggeredCommands, [.navigateBack, .navigateForward])
    }

    func testReaderWindowRoutesOnlyLeftCommandOneThroughThreeToNumberedTabs() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var activatedTabs: [Int] = []
        window.numberedTabShortcutHandler = { activatedTabs.append($0) }

        for number in 1...3 {
            XCTAssertTrue(
                window.handlePhysicalCommandNumberShortcut(
                    with: makePhysicalCommandNumberEvent(number, left: true)
                )
            )
        }
        XCTAssertTrue(
            window.handlePhysicalCommandNumberShortcut(
                with: makePhysicalCommandNumberEvent(4, left: true)
            )
        )

        XCTAssertEqual(activatedTabs, [1, 2, 3])
    }

    func testReaderWindowLeavesRightCommandNumbersForConfiguredMenuShortcuts() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var activatedTabs: [Int] = []
        window.numberedTabShortcutHandler = { activatedTabs.append($0) }

        for number in 1...4 {
            XCTAssertFalse(
                window.handlePhysicalCommandNumberShortcut(
                    with: makePhysicalCommandNumberEvent(number, right: true)
                )
            )
        }

        XCTAssertTrue(activatedTabs.isEmpty)
    }

    func testReaderWindowConsumesAmbiguousCommandNumberEvents() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var activatedTabs: [Int] = []
        window.numberedTabShortcutHandler = { activatedTabs.append($0) }

        XCTAssertTrue(
            window.handlePhysicalCommandNumberShortcut(
                with: makePhysicalCommandNumberEvent(1)
            )
        )
        XCTAssertTrue(
            window.handlePhysicalCommandNumberShortcut(
                with: makePhysicalCommandNumberEvent(1, left: true, right: true)
            )
        )
        XCTAssertFalse(
            window.handlePhysicalCommandNumberShortcut(
                with: makeKeyEvent(characters: "5", modifiers: [.command])
            )
        )

        XCTAssertTrue(activatedTabs.isEmpty)
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

    func testFindNextShortcutRunsWhileEditingText() {
        var triggered: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [
                    .findNextMatch: KeyboardShortcut(key: "g", modifiers: [.command]),
                    .findPreviousMatch: KeyboardShortcut(key: "g", modifiers: [.command, .shift]),
                ]
            },
            handlerProvider: {
                [
                    .findNextMatch: { triggered.append(.findNextMatch) },
                    .findPreviousMatch: { triggered.append(.findPreviousMatch) },
                ]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = NSTextView()
        window.contentView = textView
        window.makeFirstResponder(textView)

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "g", modifiers: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "g", modifiers: [.command, .shift]), in: window))
        XCTAssertEqual(triggered, [.findNextMatch, .findPreviousMatch])
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
        charactersIgnoringModifiers: String? = nil,
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
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: 0
        )!
    }

    private func makePhysicalCommandNumberEvent(
        _ number: Int,
        left: Bool = false,
        right: Bool = false
    ) -> NSEvent {
        var rawModifiers = NSEvent.ModifierFlags.command.rawValue
        if left {
            rawModifiers |= UInt(NX_DEVICELCMDKEYMASK)
        }
        if right {
            rawModifiers |= UInt(NX_DEVICERCMDKEYMASK)
        }
        return makeKeyEvent(
            characters: String(number),
            modifiers: NSEvent.ModifierFlags(rawValue: rawModifiers)
        )
    }
}
