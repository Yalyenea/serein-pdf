import AppKit

@MainActor
final class ShortcutSequenceView: NSStackView {
    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(sequences: [KeyboardShortcutSequence]) {
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (sequenceIndex, sequence) in sequences.enumerated() {
            if sequenceIndex > 0 {
                addArrangedSubview(makeSeparatorLabel("or"))
            }
            for (strokeIndex, stroke) in sequence.strokes.enumerated() {
                if strokeIndex > 0 {
                    addArrangedSubview(makeSeparatorLabel("→"))
                }
                addArrangedSubview(ShortcutKeycapLabel(stroke.displayString))
            }
        }
        isHidden = sequences.isEmpty
    }

    private func makeSeparatorLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

private final class ShortcutKeycapLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        textColor = .secondaryLabelColor
        lineBreakMode = .byClipping
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.borderWidth = 0.5
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 10, height: max(20, size.height + 4))
    }
}
