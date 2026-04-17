import AppKit

final class VerticalTabItemView: NSView {
    private let sessionID: UUID
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let separator = NSBox()
    private var onSelect: ((UUID) -> Void)?
    private var onClose: ((UUID) -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
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
        layer?.cornerRadius = 8

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        closeButton.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setButtonType(.momentaryChange)

        separator.boxType = .custom
        separator.isTransparent = false
        separator.fillColor = NSColor(calibratedWhite: 0.84, alpha: 1.0)

        let row = NSStackView(views: [titleLabel, closeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)

        addSubview(row)
        addSubview(separator)
        row.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleSelect))
        addGestureRecognizer(clickRecognizer)

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
            ? NSColor(calibratedWhite: 0.90, alpha: 1.0).cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        closeButton.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
    }
}
