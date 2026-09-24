import AppKit
import IOKit
import PDFKit
import XCTest
@testable import Serein

private final class PDFMockTextView: NSTextView {}
private final class PDFComposingTextView: NSTextView {
    override func hasMarkedText() -> Bool { true }
}
private final class ShortcutRecordingTextView: NSTextView {
    var receivedKeys: [String] = []
    override func keyDown(with event: NSEvent) {
        receivedKeys.append(event.charactersIgnoringModifiers ?? "")
    }
}
private final class ShortcutTableDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        "Result \(row + 1)"
    }
}

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

    func testShiftLMatchesGlobalLockWithoutMatchingIndividualLock() throws {
        let bindings = AppConfiguration.default.shortcuts.bindings
        let global = try XCTUnwrap(bindings[.toggleGlobalHorizontalPanLock])
        let individual = try XCTUnwrap(bindings[.toggleHorizontalPanLock])
        let event = makeKeyEvent(characters: "L", modifierFlags: [.shift])
        XCTAssertTrue(global.matches(event: event))
        XCTAssertFalse(individual.matches(event: event))
        XCTAssertEqual(global.menuKeyEquivalent, "l")
        XCTAssertEqual(global.modifierMask, [.shift])
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
        let pdfView = PDFView()
        window.contentView = pdfView
        window.makeFirstResponder(pdfView)

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
        let pdfView = PDFView()
        window.contentView = pdfView
        window.makeFirstResponder(pdfView)

        XCTAssertFalse(
            controller.handleShortcutEvent(
                for: makeKeyEvent(characters: "h", modifierFlags: [.command]),
                in: window
            )
        )
        XCTAssertFalse(didTurn)
    }

    func testVerticalArrowPageTurnsRequireNoModifiers() {
        var directions: [Int] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: { [:] },
            verticalPageTurnHandler: { direction, _ in
                directions.append(direction)
                return true
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let pdfView = PDFView()
        window.contentView = pdfView
        window.makeFirstResponder(pdfView)

        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F700}"), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F701}"), in: window))
        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F701}", modifierFlags: [.shift]), in: window))
        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\u{F702}"), in: window))
        XCTAssertEqual(directions, [-1, 1])
    }

    func testWindowSendsArrowKeysToFocusedTableAndPageTurnsToPDF() {
        _ = NSApplication.shared
        let window = ReaderShortcutWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 400),
                                          styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        let dataSource = ShortcutTableDataSource()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
        table.dataSource = dataSource
        table.reloadData()
        let pdfView = PDFView(frame: NSRect(x: 200, y: 0, width: 300, height: 400))
        window.contentView?.addSubview(table)
        window.contentView?.addSubview(pdfView)
        var turns: [Int] = []
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [:] }, handlerProvider: { [:] },
            bookPageTurnHandler: { direction, _ in turns.append(direction); return true },
            verticalPageTurnHandler: { direction, _ in turns.append(direction); return true }
        )
        window.plainShortcutHandler = { controller.handleShortcutEvent(for: $0, in: $1) }
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(table))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.sendEvent(makeKeyEvent(characters: "\u{F701}", keyCode: 125, window: window))
        XCTAssertEqual(table.selectedRow, 1)
        window.sendEvent(makeKeyEvent(characters: "\u{F700}", keyCode: 126, window: window))
        XCTAssertEqual(table.selectedRow, 0)
        for (key, code) in [("\u{F702}", UInt16(123)), ("\u{F703}", UInt16(124))] {
            window.sendEvent(makeKeyEvent(characters: key, keyCode: code, window: window))
        }
        XCTAssertTrue(turns.isEmpty)

        XCTAssertTrue(window.makeFirstResponder(pdfView))
        for (key, code) in [("\u{F700}", UInt16(126)), ("\u{F701}", UInt16(125)),
                            ("\u{F702}", UInt16(123)), ("\u{F703}", UInt16(124))] {
            window.sendEvent(makeKeyEvent(characters: key, keyCode: code, window: window))
        }
        XCTAssertEqual(turns, [-1, 1, -1, 1])
        withExtendedLifetime(dataSource) {}
    }

    func testPaneShortcutsRouteModifiedKeysAndLeaveTextEditingAlone() {
        var triggered: [ShortcutCommand] = []
        let commands: [ShortcutCommand] = [
            .translateSelection, .quickOutline, .showRecentWindows,
            .splitCurrentPDFRight, .splitCurrentPDFDown,
            .focusPaneLeft, .focusPaneDown, .focusPaneUp, .focusPaneRight,
        ]
        let controller = ReaderShortcutsController(
            shortcutsProvider: { AppConfiguration.default.shortcuts.bindings },
            handlerProvider: {
                var handlers: [ShortcutCommand: ReaderShortcutsController.ShortcutHandler] = [:]
                for command in commands {
                    handlers[command] = { @MainActor in triggered.append(command) }
                }
                return handlers
            }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let events = [
            makeKeyEvent(characters: "t"),
            makeKeyEvent(characters: "o"),
            makeKeyEvent(characters: "w"),
            makeKeyEvent(characters: "b"),
            makeKeyEvent(characters: "B", modifierFlags: [.shift]),
            makeKeyEvent(characters: "h", modifierFlags: [.control]),
            makeKeyEvent(characters: "j", modifierFlags: [.control]),
            makeKeyEvent(characters: "k", modifierFlags: [.control]),
            makeKeyEvent(characters: "l", modifierFlags: [.control]),
        ]

        for event in events {
            XCTAssertTrue(controller.handleShortcutEvent(for: event, in: window))
        }
        XCTAssertEqual(triggered, commands)

        let editor = NSTextView()
        window.contentView = editor
        window.makeFirstResponder(editor)
        for event in events {
            XCTAssertFalse(controller.handleShortcutEvent(for: event, in: window))
        }
        XCTAssertEqual(triggered, commands)
    }

    func testReaderShortcutsDoNotInterruptMarkedTextComposition() {
        XCTAssertFalse(ReaderShortcutsController.shouldHandlePlainShortcut(for: PDFComposingTextView()))
    }

    func testReturnShortcutMatchesMainKeyboardAndKeypadEvents() {
        let shortcut = KeyboardShortcut(key: "return", modifiers: [.option])
        for (characters, keyCode): (String, UInt16) in [("\r", 36), ("\u{3}", 76), ("\r", 0)] {
            XCTAssertTrue(shortcut.matches(event: makeKeyEvent(characters: characters, keyCode: keyCode, modifierFlags: [.option])))
        }
        XCTAssertFalse(shortcut.matches(event: makeKeyEvent(characters: "\r", keyCode: 36)))
        XCTAssertFalse(shortcut.matches(event: makeKeyEvent(characters: "r", modifierFlags: [.option])))
        XCTAssertTrue(KeyboardShortcut(key: "tab", modifiers: [.control, .shift]).matches(event: makeKeyEvent(characters: "\u{19}", modifierFlags: [.control, .shift])))
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

    func testReaderWindowDeliversEditingKeysBeforeMenuEquivalents() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = ShortcutRecordingTextView()
        window.contentView = editor
        window.makeFirstResponder(editor)
        var readerActionCount = 0
        let controller = ReaderShortcutsController(
            shortcutsProvider: { AppConfiguration.default.shortcuts.bindings },
            handlerProvider: {
                [
                    .focusPaneLeft: { readerActionCount += 1 },
                    .focusPaneDown: { readerActionCount += 1 },
                    .focusPaneUp: { readerActionCount += 1 },
                    .focusPaneRight: { readerActionCount += 1 },
                    .splitCurrentPDFDown: { readerActionCount += 1 },
                    .translateSelection: { readerActionCount += 1 },
                ]
            }
        )
        window.plainShortcutHandler = { event, window in
            controller.handleShortcutEvent(for: event, in: window)
        }
        let events = [
            makeKeyEvent(characters: "h", modifierFlags: [.control]),
            makeKeyEvent(characters: "j", modifierFlags: [.control]),
            makeKeyEvent(characters: "k", modifierFlags: [.control]),
            makeKeyEvent(characters: "l", modifierFlags: [.control]),
            makeKeyEvent(characters: "B", modifierFlags: [.shift]),
            makeKeyEvent(characters: "t"),
        ]
        for event in events {
            XCTAssertTrue(window.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(editor.receivedKeys, ["h", "j", "k", "l", "B", "t"])
        XCTAssertEqual(readerActionCount, 0)
    }

    func testControlShiftTabStartsReverseNavigationWhileEditing() {
        let window = ReaderShortcutWindow(
            contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = ShortcutRecordingTextView()
        window.contentView = editor
        window.makeFirstResponder(editor)
        var navigationCount = 0
        let controller = ReaderShortcutsController(
            shortcutsProvider: { AppConfiguration.default.shortcuts.bindings },
            handlerProvider: { [.showAllTabs: { navigationCount += 1 }] }
        )
        window.plainShortcutHandler = { event, window in
            controller.handleShortcutEvent(for: event, in: window)
        }

        XCTAssertTrue(window.performKeyEquivalent(with: makeKeyEvent(characters: "\u{19}", modifierFlags: [.control, .shift])))
        XCTAssertTrue(window.performKeyEquivalent(with: makeKeyEvent(characters: "\t", modifierFlags: [.control])))
        XCTAssertEqual(navigationCount, 2)
        XCTAssertTrue(editor.receivedKeys.isEmpty)
    }

    func testReverseTabNavigationRespectsClearedOrReassignedBinding() {
        var navigationCount = 0
        let controller = ReaderShortcutsController(
            shortcutsProvider: { [.showAllTabs: KeyboardShortcut(key: "t", modifiers: [.command])] },
            handlerProvider: { [.showAllTabs: { navigationCount += 1 }] }
        )
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        XCTAssertFalse(controller.handleShortcutEvent(for: makeKeyEvent(characters: "\t", modifierFlags: [.control, .shift]), in: window))
        XCTAssertTrue(controller.handleShortcutEvent(for: makeKeyEvent(characters: "t", modifierFlags: [.command]), in: window))
        XCTAssertEqual(navigationCount, 1)

        let clearedController = ReaderShortcutsController(
            shortcutsProvider: { [:] },
            handlerProvider: { [.showAllTabs: { navigationCount += 1 }] }
        )
        XCTAssertFalse(clearedController.handleShortcutEvent(for: makeKeyEvent(characters: "\t", modifierFlags: [.control, .shift]), in: window))
        XCTAssertEqual(navigationCount, 1)
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
