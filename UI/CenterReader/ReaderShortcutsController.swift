import AppKit

@MainActor
final class ReaderShortcutsController {
    typealias ShortcutHandler = @MainActor () -> Void

    private static let chordPrefix = KeyboardShortcut(key: "k", modifiers: [.command])
    private static let switchCurrentThemeChord = KeyboardShortcut(key: "t", modifiers: [.command])

    private let shortcutsProvider: @MainActor () -> [ShortcutCommand: KeyboardShortcut]
    private let handlerProvider: @MainActor () -> [ShortcutCommand: ShortcutHandler]
    private var isWaitingForChordKey = false

    init(
        shortcutsProvider: @escaping @MainActor () -> [ShortcutCommand: KeyboardShortcut],
        handlerProvider: @escaping @MainActor () -> [ShortcutCommand: ShortcutHandler]
    ) {
        self.shortcutsProvider = shortcutsProvider
        self.handlerProvider = handlerProvider
    }

    func handleShortcutEvent(for event: NSEvent, in window: NSWindow) -> Bool {
        guard Self.shouldHandlePlainShortcut(for: window.firstResponder) else {
            isWaitingForChordKey = false
            return false
        }

        if handleChord(for: event) {
            return true
        }

        return handlePlainShortcut(for: event, in: window)
    }

    func handlePlainShortcut(for event: NSEvent, in window: NSWindow) -> Bool {
        guard Self.shouldHandlePlainShortcut(for: window.firstResponder) else { return false }

        for (command, shortcut) in shortcutsProvider() where shortcut.isPlainShortcut {
            guard shortcut.matches(event: event) else { continue }
            guard let handler = handlerProvider()[command] else { continue }
            handler()
            return true
        }

        return false
    }

    private func handleChord(for event: NSEvent) -> Bool {
        if isWaitingForChordKey {
            isWaitingForChordKey = false

            if Self.switchCurrentThemeChord.matches(event: event) {
                handlerProvider()[.switchCurrentTheme]?()
                return true
            }

            if KeyboardShortcut(key: "escape", modifiers: []).matches(event: event) {
                return true
            }

            return false
        }

        if Self.chordPrefix.matches(event: event) {
            isWaitingForChordKey = true
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
