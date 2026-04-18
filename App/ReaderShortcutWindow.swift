import AppKit

final class ReaderShortcutWindow: NSWindow {
    var plainShortcutHandler: ((NSEvent, NSWindow) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           plainShortcutHandler?(event, self) == true {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers.isEmpty {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}
