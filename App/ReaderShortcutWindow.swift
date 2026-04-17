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
}
