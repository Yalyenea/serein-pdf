import AppKit

final class VerticalTabItemView: NSView {
    private let sessionID: UUID
    private let selectButton = NSButton(title: "", target: nil, action: nil)
    private let dirtyIndicator = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let separator = NSBox()
    private let isDirty: Bool
    private var onSelect: ((UUID) -> Void)?
    private var onClose: ((UUID) -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    init(
        sessionID: UUID,
        title: String,
        isSelected: Bool,
        isDirty: Bool,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.sessionID = sessionID
        self.isDirty = isDirty
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0

        selectButton.isBordered = false
        selectButton.title = ""
        selectButton.bezelStyle = .regularSquare
        selectButton.focusRingType = .none
        selectButton.target = self
        selectButton.action = #selector(handleSelect)

        dirtyIndicator.wantsLayer = true
        dirtyIndicator.layer?.cornerRadius = 3
        dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false
        dirtyIndicator.isHidden = !isDirty

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.cell?.wraps = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setButtonType(.momentaryChange)

        separator.boxType = .custom
        separator.isTransparent = false
        separator.fillColor = SplitViewController.dividerBackgroundColor

        let row = NSStackView(views: [dirtyIndicator, titleLabel, closeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)

        addSubview(selectButton)
        addSubview(row)
        addSubview(separator)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectButton.topAnchor.constraint(equalTo: topAnchor),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            dirtyIndicator.widthAnchor.constraint(equalToConstant: 6),
            dirtyIndicator.heightAnchor.constraint(equalToConstant: 6),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected
                ? SplitViewController.selectedChromeBackgroundColor.cgColor
                : NSColor.clear.cgColor
            layer?.borderColor = isSelected ? SplitViewController.chromeStrokeColor.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isSelected ? 1 : 0
            dirtyIndicator.layer?.backgroundColor = HighlightColor.pink.nsColor.cgColor
        }
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        closeButton.contentTintColor = isSelected ? .labelColor : .tertiaryLabelColor
        separator.isHidden = isSelected
    }
}
