import AppKit

@MainActor
final class ReaderShortcutsController {
    typealias ShortcutHandler = @MainActor () -> Void
    typealias BookPageTurnHandler = @MainActor (_ direction: Int, _ window: NSWindow) -> Bool

    private static let highlightModeColorShortcuts: [(KeyboardShortcut, ShortcutCommand)] = [
        (KeyboardShortcut(key: "1", modifiers: []), .highlightColorPink),
        (KeyboardShortcut(key: "2", modifiers: []), .highlightColorYellow),
        (KeyboardShortcut(key: "3", modifiers: []), .highlightColorGreen),
    ]
    private static let windowRoutedCommands: [ShortcutCommand] = [
        .navigateBack,
        .navigateForward,
    ]

    private let shortcutsProvider: @MainActor () -> [ShortcutCommand: KeyboardShortcut]
    private let handlerProvider: @MainActor () -> [ShortcutCommand: ShortcutHandler]
    private let isAnnotationModeEnabledProvider: @MainActor (NSWindow) -> Bool
    private let bookPageTurnHandler: BookPageTurnHandler

    init(
        shortcutsProvider: @escaping @MainActor () -> [ShortcutCommand: KeyboardShortcut],
        handlerProvider: @escaping @MainActor () -> [ShortcutCommand: ShortcutHandler],
        isAnnotationModeEnabledProvider: @escaping @MainActor (NSWindow) -> Bool = { _ in false },
        bookPageTurnHandler: @escaping BookPageTurnHandler = { _, _ in false }
    ) {
        self.shortcutsProvider = shortcutsProvider
        self.handlerProvider = handlerProvider
        self.isAnnotationModeEnabledProvider = isAnnotationModeEnabledProvider
        self.bookPageTurnHandler = bookPageTurnHandler
    }

    func handleShortcutEvent(for event: NSEvent, in window: NSWindow) -> Bool {
        // Find next/previous must work while the find-bar field editor has focus.
        if handleFindNavigationShortcut(for: event) {
            return true
        }

        guard Self.shouldHandlePlainShortcut(for: window.firstResponder) else {
            return false
        }

        if handleBookPageTurnShortcut(for: event, in: window) {
            return true
        }

        if handleWindowRoutedShortcut(for: event) {
            return true
        }

        return handlePlainShortcut(for: event, in: window)
    }

    private func handleBookPageTurnShortcut(for event: NSEvent, in window: NSWindow) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        let direction: Int
        switch key {
        case "h", "\u{F702}":
            direction = -1
        case "l", "\u{F703}":
            direction = 1
        default:
            return false
        }
        return bookPageTurnHandler(direction, window)
    }

    private func handleWindowRoutedShortcut(for event: NSEvent) -> Bool {
        let shortcuts = shortcutsProvider()
        let handlers = handlerProvider()
        for command in Self.windowRoutedCommands {
            guard let shortcut = shortcuts[command],
                  shortcut.matches(event: event),
                  let handler = handlers[command] else { continue }
            handler()
            return true
        }
        return false
    }

    private func handleFindNavigationShortcut(for event: NSEvent) -> Bool {
        let shortcuts = shortcutsProvider()
        let handlers = handlerProvider()
        for command: ShortcutCommand in [.findNextMatch, .findPreviousMatch] {
            guard let shortcut = shortcuts[command],
                  shortcut.matches(event: event),
                  let handler = handlers[command] else { continue }
            handler()
            return true
        }
        return false
    }

    func handlePlainShortcut(for event: NSEvent, in window: NSWindow) -> Bool {
        guard Self.shouldHandlePlainShortcut(for: window.firstResponder) else { return false }

        if handleHighlightModeColorShortcut(for: event, in: window) {
            return true
        }

        let shortcuts = shortcutsProvider()
        let handlers = handlerProvider()

        for (command, shortcut) in shortcuts where shortcut.isPlainShortcut {
            guard shortcut.matches(event: event) else { continue }
            guard let handler = handlers[command] else { continue }
            handler()
            return true
        }

        return false
    }

    private func handleHighlightModeColorShortcut(for event: NSEvent, in window: NSWindow) -> Bool {
        guard isAnnotationModeEnabledProvider(window) else { return false }
        let handlers = handlerProvider()
        for (shortcut, command) in Self.highlightModeColorShortcuts {
            guard shortcut.matches(event: event),
                  let handler = handlers[command] else { continue }
            handler()
            return true
        }
        return false
    }

    static func shouldHandlePlainShortcut(for firstResponder: NSResponder?) -> Bool {
        guard let firstResponder else { return true }
        guard let textView = firstResponder as? NSTextView else { return true }
        let className = NSStringFromClass(type(of: textView))
        return className.contains("PDF") || (textView.isEditable == false && textView.isSelectable == false)
    }
}
