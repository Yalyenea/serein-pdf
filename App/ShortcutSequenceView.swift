import AppKit

@MainActor
final class ShortcutSequenceView: NSStackView {
    static let symbolSize: CGFloat = 14
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(sequences: [KeyboardShortcutSequence]) {
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (sequenceIndex, sequence) in sequences.enumerated() {
            if sequenceIndex > 0 { addArrangedSubview(makeLabel("/")) }
            for (strokeIndex, stroke) in sequence.strokes.enumerated() {
                if strokeIndex > 0 { addArrangedSubview(makeSymbol("arrow.right", size: 10)) }
                let keys = NSStackView()
                keys.orientation = .horizontal
                keys.alignment = .centerY
                keys.spacing = 3
                keys.translatesAutoresizingMaskIntoConstraints = false
                keys.heightAnchor.constraint(equalToConstant: 22).isActive = true
                for modifier in [KeyboardShortcutModifier.control, .option, .shift, .command] where stroke.modifiers.contains(modifier) {
                    keys.addArrangedSubview(makeSymbol(modifier.rawValue))
                }
                let symbol: String?
                switch stroke.key {
                case "return", "enter", "\r": symbol = "return"
                case "escape": symbol = "escape"
                case "tab": symbol = "arrow.right.to.line"
                case "space": symbol = "space"
                case "up": symbol = "arrow.up"
                case "down": symbol = "arrow.down"
                case "left": symbol = "arrow.left"
                case "right": symbol = "arrow.right"
                default: symbol = nil
                }
                if let symbol {
                    keys.addArrangedSubview(makeSymbol(symbol))
                } else {
                    keys.addArrangedSubview(makeLabel(stroke.key.uppercased()))
                }
                addArrangedSubview(keys)
            }
        }
        isHidden = sequences.isEmpty
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(sequences.map(\.displayString).joined(separator: ", "))
        refreshChromeColors()
    }

    func refreshChromeColors() {
        func refresh(_ view: NSView) {
            if let image = view as? NSImageView {
                image.contentTintColor = NightModeStyle.secondaryTextColor
            } else if let label = view as? NSTextField {
                label.textColor = NightModeStyle.secondaryTextColor
            }
            view.subviews.forEach(refresh)
        }
        subviews.forEach(refresh)
    }

    private func makeSymbol(_ name: String, size: CGFloat = ShortcutSequenceView.symbolSize) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
        view.imageScaling = .scaleProportionallyDown
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: 18),
        ])
        return view
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Self.labelFont
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }
}
