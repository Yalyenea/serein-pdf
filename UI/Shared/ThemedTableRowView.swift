import AppKit

final class ThemedTableRowView: NSTableRowView {
    var selectionCornerRadius: CGFloat = 0
    var selectionInsets: NSSize = .zero

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NightModeStyle.selectedChromeBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: selectionInsets.width, dy: selectionInsets.height),
            xRadius: selectionCornerRadius,
            yRadius: selectionCornerRadius
        ).fill()
    }
}
