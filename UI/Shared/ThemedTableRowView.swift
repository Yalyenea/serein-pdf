import AppKit

final class ThemedTableRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NightModeStyle.selectedChromeBackgroundColor.setFill()
        bounds.fill()
    }
}
