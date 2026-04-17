import AppKit

final class TitlebarTabItemView: NSView {
    private let sessionID: UUID
    private let selectButton = NSButton(title: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let dividerView = NSView()
    private var onSelect: ((UUID) -> Void)?
    private var onClose: ((UUID) -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    override var intrinsicContentSize: NSSize {
        let titleWidth = min(max(titleLabel.intrinsicContentSize.width, 72), 240)
        return NSSize(width: titleWidth + 44, height: 28)
    }

    init(
        sessionID: UUID,
        title: String,
        isSelected: Bool,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.sessionID = sessionID
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.borderWidth = 0

        selectButton.isBordered = false
        selectButton.title = ""
        selectButton.bezelStyle = .regularSquare
        selectButton.focusRingType = .none
        selectButton.target = self
        selectButton.action = #selector(handleSelect)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.setButtonType(.momentaryChange)

        dividerView.wantsLayer = true

        let stack = NSStackView(views: [titleLabel, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)

        addSubview(selectButton)
        addSubview(stack)
        addSubview(dividerView)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectButton.topAnchor.constraint(equalTo: topAnchor),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dividerView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            dividerView.widthAnchor.constraint(equalToConstant: 1),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 28),
        ])

        self.isSelected = isSelected
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleSelect() {
        onSelect?(sessionID)
    }

    @objc
    private func handleClose() {
        onClose?(sessionID)
    }

    private func updateAppearance() {
        layer?.backgroundColor = isSelected
            ? NSColor(calibratedWhite: 0.91, alpha: 1.0).cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        closeButton.contentTintColor = isSelected ? .labelColor : .tertiaryLabelColor
        dividerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.84, alpha: 0.9).cgColor
        dividerView.isHidden = isSelected
    }
}
