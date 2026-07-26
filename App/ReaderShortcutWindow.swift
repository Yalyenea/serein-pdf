import AppKit
import IOKit

final class ReaderShortcutWindow: NSWindow {
    var plainShortcutHandler: ((NSEvent, NSWindow) -> Bool)?
    var numberedTabShortcutHandler: ((Int) -> Void)?
    var reservesTransparentTitlebarDragArea = true

    override func sendEvent(_ event: NSEvent) {
        if shouldHandleTransparentTitlebarDrag(with: event) {
            performDrag(with: event)
            return
        }

        if handlePhysicalCommandNumberShortcut(with: event) {
            return
        }

        if event.type == .keyDown,
           plainShortcutHandler?(event, self) == true {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlePhysicalCommandNumberShortcut(with: event) {
            return true
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers.isEmpty {
            return false
        }
        if plainShortcutHandler?(event, self) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func handlePhysicalCommandNumberShortcut(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let number = Int(characters),
              (1...4).contains(number) else { return false }

        let rawModifiers = event.modifierFlags.rawValue
        let usesLeftCommand = rawModifiers & UInt(NX_DEVICELCMDKEYMASK) != 0
        let usesRightCommand = rawModifiers & UInt(NX_DEVICERCMDKEYMASK) != 0

        switch (usesLeftCommand, usesRightCommand) {
        case (true, false):
            if number <= 3 {
                numberedTabShortcutHandler?(number)
            }
            return true
        case (false, true):
            return false
        case (false, false), (true, true):
            return true
        }
    }

    func shouldHandleTransparentTitlebarDrag(with event: NSEvent) -> Bool {
        guard reservesTransparentTitlebarDragArea,
              event.type == .leftMouseDown,
              event.clickCount == 1,
              toolbar == nil,
              styleMask.contains(.fullSizeContentView),
              styleMask.contains(.fullScreen) == false,
              isMovable else {
            return false
        }
        guard let contentView else { return false }

        let location = event.locationInWindow
        guard contentView.bounds.contains(location),
              locationIntersectsStandardWindowButton(location) == false else {
            return false
        }

        let dragBoundaryY = min(max(contentLayoutRect.maxY, contentView.bounds.minY), contentView.bounds.maxY)
        return location.y >= dragBoundaryY
    }

    private func locationIntersectsStandardWindowButton(_ location: NSPoint) -> Bool {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return buttonTypes.contains { type in
            guard let button = standardWindowButton(type), button.isHidden == false else { return false }
            let buttonFrame = button.convert(button.bounds, to: nil).insetBy(dx: -4, dy: -4)
            return buttonFrame.contains(location)
        }
    }
}
