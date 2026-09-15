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
            isAnnotationModeEnabledProvider: { _ in true }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifierFlags: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "2", modifierFlags: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "3", modifierFlags: []), in: window))
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
            isAnnotationModeEnabledProvider: { _ in false }
        )
        let enabledController = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.highlightColorPink: { didTrigger = true }]
            },
            isAnnotationModeEnabledProvider: { _ in true }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(disabledController.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifierFlags: []), in: window))
        XCTAssertFalse(
            enabledController.handleShortcutEvent(
                for: makeKeyEvent(characters: "1", modifierFlags: [.command]),
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
            isAnnotationModeEnabledProvider: { _ in true }
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

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "1", modifierFlags: []), in: window))
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
        let event = makeKeyEvent(characters: "i", modifierFlags: [])

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
                for: makeKeyEvent(characters: "f", modifierFlags: []),
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
                for: makeKeyEvent(characters: "l", modifierFlags: []),
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
            modifierFlags: [.option]
        )

        XCTAssertTrue(shortcut.matches(event: event))
    }

    func testFitTextWidthShortcutDistinguishesPageWidthAndOptionCharacter() throws {
        let bindings = AppConfiguration.default.shortcuts.bindings
        let textWidthShortcut = try XCTUnwrap(bindings[.fitTextWidth])
        let pageWidthShortcut = try XCTUnwrap(bindings[.fitWidth])
        let textWidthEvent = makeKeyEvent(
            characters: "º",
            charactersIgnoringModifiers: "0",
            modifierFlags: [.command, .option]
        )
        let pageWidthEvent = makeKeyEvent(characters: "0", modifierFlags: [.command])

        XCTAssertTrue(textWidthShortcut.matches(event: textWidthEvent))
        XCTAssertFalse(pageWidthShortcut.matches(event: textWidthEvent))
        XCTAssertTrue(pageWidthShortcut.matches(event: pageWidthEvent))
        XCTAssertFalse(textWidthShortcut.matches(event: pageWidthEvent))
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
        let event = makeKeyEvent(characters: "a", modifierFlags: [])

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
        let event = makeKeyEvent(characters: "f", modifierFlags: [])

        XCTAssertFalse(controller.handlePlainShortcut(for: event, in: window))
    }

    func testPlainCInvokesConfiguredDisplayModeContinuityShortcut() {
        var triggeredCommands: [ShortcutCommand] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.toggleDisplayModeContinuity: KeyboardShortcut(key: "c", modifiers: [])]
            },
            handlerProvider: {
                [.toggleDisplayModeContinuity: { triggeredCommands.append(.toggleDisplayModeContinuity) }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "c", modifierFlags: [])

        XCTAssertTrue(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertEqual(triggeredCommands, [.toggleDisplayModeContinuity])
    }

    func testPlainCRespectsClearedDisplayModeContinuityBinding() {
        var didTrigger = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: {
                [.toggleDisplayModeContinuity: { didTrigger = true }]
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let event = makeKeyEvent(characters: "c", modifierFlags: [])

        XCTAssertFalse(controller.handlePlainShortcut(for: event, in: window))
        XCTAssertFalse(didTrigger)
    }

    func testBookModeUsesArrowAndHLPageTurnAliases() {
        var directions: [Int] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: { [:] },
            bookPageTurnHandler: { direction, _ in
                directions.append(direction)
                return true
            }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "h", modifierFlags: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F702}", modifierFlags: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "l", modifierFlags: []), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F703}", modifierFlags: []), in: window))
        XCTAssertEqual(directions, [-1, -1, 1, 1])
    }

    func testBookPageTurnAliasesRequireNoModifiers() {
        var didTurn = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: { [:] },
            bookPageTurnHandler: { _, _ in
                didTurn = true
                return true
            }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(
            controller.handleShortcutEvent(
                for: makeKeyEvent(characters: "h", modifierFlags: [.command]),
                in: window
            )
        )
        XCTAssertFalse(didTurn)
    }

    func testPlainLFallsThroughToConfiguredPanLockOutsideBookMode() {
        var didTogglePanLock = false
        let controller = ReaderShortcutsController(
            shortcutsProvider: {
                [.toggleHorizontalPanLock: KeyboardShortcut(key: "l", modifiers: [])]
            },
            handlerProvider: {
                [.toggleHorizontalPanLock: { didTogglePanLock = true }]
            },
            bookPageTurnHandler: { _, _ in false }
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "l", modifierFlags: []), in: window))
        XCTAssertTrue(didTogglePanLock)
    }

    func testCommandPaletteShortcutFallsThroughToAppMenu() {
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: { [:] }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "t", modifierFlags: [.command]), in: window))
        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifierFlags: [.command]), in: window))
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

        XCTAssertTrue(window.performKeyEquivalent(with: makeKeyEvent(characters: "o", modifierFlags: [.command])))
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
                with: makeKeyEvent(characters: "[", modifierFlags: [.command])
            )
        )
        XCTAssertTrue(
            window.performKeyEquivalent(
                with: makeKeyEvent(characters: "]", modifierFlags: [.command])
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
                with: makeKeyEvent(characters: "5", modifierFlags: [.command])
            )
        )

        XCTAssertTrue(activatedTabs.isEmpty)
    }

    func testCommandPaletteShortcutFallsThroughWhileEditingText() {
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

        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "k", modifierFlags: [.command]), in: window))
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

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "g", modifierFlags: [.command]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "g", modifierFlags: [.command, .shift]), in: window))
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
            modifierFlags: NSEvent.ModifierFlags(rawValue: rawModifiers)
        )
    }
}
