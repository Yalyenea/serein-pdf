import AppKit

final class ReaderShortcutWindow: NSWindow {
    var plainShortcutHandler: ((NSEvent, NSWindow) -> Bool)?
    var reservesTransparentTitlebarDragArea = true

    override func sendEvent(_ event: NSEvent) {
        if shouldHandleTransparentTitlebarDrag(with: event) {
            performDrag(with: event)
            return
        }

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
        if plainShortcutHandler?(event, self) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
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
