import AppKit

final class ThemedSearchFieldCell: NSSearchFieldCell {
    var cornerRadius: CGFloat = 6
    private(set) var strokeColor: NSColor = .clear

    func applyTheme(to searchField: NSSearchField, placeholder: String) {
        backgroundColor = NightModeStyle.selectedChromeBackgroundColor
        strokeColor = NightModeStyle.chromeStrokeColor.withAlphaComponent(0.32)
        searchField.textColor = NightModeStyle.primaryTextColor
        searchField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NightModeStyle.tertiaryTextColor,
                .font: searchField.font ?? NSFont.systemFont(ofSize: 11.5),
            ]
        )
        searchField.needsDisplay = true
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSGraphicsContext.saveGraphicsState()
        backgroundColor!.setFill()
        NSBezierPath(
            roundedRect: cellFrame,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
        strokeColor.setStroke()
        let borderPath = NSBezierPath(
            roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius - 0.5,
            yRadius: cornerRadius - 0.5
        )
        borderPath.lineWidth = 1
        borderPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}
