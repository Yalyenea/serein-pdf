import AppKit

@MainActor
final class ReaderShortcutsController {
    typealias ShortcutHandler = @MainActor () -> Void
    typealias BookPageTurnHandler = @MainActor (_ direction: Int, _ window: NSWindow) -> Bool
    typealias VerticalPageTurnHandler = @MainActor (_ direction: Int, _ window: NSWindow) -> Bool

    private static let highlightModeColorShortcuts: [(KeyboardShortcut, ShortcutCommand)] = [
        (KeyboardShortcut(key: "1", modifiers: []), .highlightColorPink),
        (KeyboardShortcut(key: "2", modifiers: []), .highlightColorYellow),
        (KeyboardShortcut(key: "3", modifiers: []), .highlightColorGreen),
    ]
    private static let windowRoutedCommands: [ShortcutCommand] = [
        .navigateBack,
        .navigateForward,
        .translateSelection,
        .quickOutline,
        .showRecentWindows,
        .splitCurrentPDFRight,
        .splitCurrentPDFDown,
        .focusPaneLeft,
        .focusPaneDown,
        .focusPaneUp,
        .focusPaneRight,
    ]

    private let shortcutsProvider: @MainActor () -> [ShortcutCommand: KeyboardShortcut]
    private let handlerProvider: @MainActor () -> [ShortcutCommand: ShortcutHandler]
    private let isAnnotationModeEnabledProvider: @MainActor (NSWindow) -> Bool
    private let bookPageTurnHandler: BookPageTurnHandler
    private let verticalPageTurnHandler: VerticalPageTurnHandler

    init(
        shortcutsProvider: @escaping @MainActor () -> [ShortcutCommand: KeyboardShortcut],
        handlerProvider: @escaping @MainActor () -> [ShortcutCommand: ShortcutHandler],
        isAnnotationModeEnabledProvider: @escaping @MainActor (NSWindow) -> Bool = { _ in false },
        bookPageTurnHandler: @escaping BookPageTurnHandler = { _, _ in false },
        verticalPageTurnHandler: @escaping VerticalPageTurnHandler = { _, _ in false }
    ) {
        self.shortcutsProvider = shortcutsProvider
        self.handlerProvider = handlerProvider
        self.isAnnotationModeEnabledProvider = isAnnotationModeEnabledProvider
        self.bookPageTurnHandler = bookPageTurnHandler
        self.verticalPageTurnHandler = verticalPageTurnHandler
    }

    func handleShortcutEvent(for event: NSEvent, in window: NSWindow) -> Bool {
        // Find next/previous must work while the find-bar field editor has focus.
        if handleFindNavigationShortcut(for: event) {
            return true
        }

        if handleTabNavigationShortcut(for: event) {
            return true
        }

        guard Self.shouldHandlePlainShortcut(for: window.firstResponder) else {
            return false
        }

        if handleBookPageTurnShortcut(for: event, in: window) {
            return true
        }

        if handleVerticalPageTurnShortcut(for: event, in: window) {
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

    private func handleVerticalPageTurnShortcut(for event: NSEvent, in window: NSWindow) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              let key = event.charactersIgnoringModifiers else { return false }
        switch key {
        case "\u{F700}":
            return verticalPageTurnHandler(-1, window)
        case "\u{F701}":
            return verticalPageTurnHandler(1, window)
        default:
            return false
        }
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

    private func handleTabNavigationShortcut(for event: NSEvent) -> Bool {
        guard let shortcut = shortcutsProvider()[.showAllTabs],
              let handler = handlerProvider()[.showAllTabs] else { return false }
        let matchesForward = shortcut.matches(event: event)
        let matchesReverse = shortcut.key == "tab"
            && shortcut.modifiers.contains(.control)
            && shortcut.modifiers.contains(.shift) == false
            && KeyboardShortcut(key: "tab", modifiers: shortcut.modifiers.union([.shift])).matches(event: event)
        guard matchesForward || matchesReverse else { return false }
        handler()
        return true
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
        if let inputClient = firstResponder as? NSTextInputClient, inputClient.hasMarkedText() {
            return false
        }
        guard let textView = firstResponder as? NSTextView else { return true }
        let className = NSStringFromClass(type(of: textView))
        return className.contains("PDF") || (textView.isEditable == false && textView.isSelectable == false)
    }
}
