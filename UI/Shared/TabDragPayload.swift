import AppKit

struct TabDragPayload: Codable, Equatable, Sendable {
    static let pasteboardType = NSPasteboard.PasteboardType("local.yfff.Serein.tab-session-move")

    let sourceWindowID: UUID
    let sessionID: UUID

    func makePasteboardItem() -> NSPasteboardItem? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: Self.pasteboardType)
        return item
    }

    static func read(from pasteboard: NSPasteboard) -> TabDragPayload? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? JSONDecoder().decode(TabDragPayload.self, from: data)
    }
}

final class TabDragSourceButton: NSButton, NSDraggingSource {
    var dragPayload: TabDragPayload?
    weak var dragPreviewView: NSView?

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1,
              dragPayload != nil else {
            super.mouseDown(with: event)
            return
        }

        let startLocation = event.locationInWindow
        while let nextEvent = NSApp.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let distance = hypot(
                    nextEvent.locationInWindow.x - startLocation.x,
                    nextEvent.locationInWindow.y - startLocation.y
                )
                guard distance >= 4 else { continue }
                beginTabDraggingSession(with: nextEvent)
                return
            case .leftMouseUp:
                let location = convert(nextEvent.locationInWindow, from: nil)
                if bounds.contains(location) {
                    _ = sendAction(action, to: target)
                }
                return
            default:
                continue
            }
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        superview?.menu(for: event) ?? super.menu(for: event)
    }

    private func beginTabDraggingSession(with event: NSEvent) {
        guard let pasteboardItem = dragPayload?.makePasteboardItem() else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let previewView = dragPreviewView ?? self
        let previewImage = snapshot(of: previewView)
        draggingItem.setDraggingFrame(bounds, contents: previewImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshot(of view: NSView) -> NSImage {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return NSImage(size: view.bounds.size)
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }
}
