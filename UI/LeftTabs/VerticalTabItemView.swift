import AppKit

final class VerticalTabItemView: NSView {
    private let sessionID: UUID
    private let selectButton = TabDragSourceButton(title: "", target: nil, action: nil)
    private let dirtyIndicator = NSView()
    private let groupIndicator = NSView()
    private let titleLabel = NSTextField()
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let separator = NSBox()
    private let isDirty: Bool
    private let isContinuousReadingMember: Bool
    private let isContinuousReadingLeader: Bool
    private let canStartContinuousReading: Bool
    private var onSelect: ((UUID, NSEvent.ModifierFlags) -> Void)?
    private var onAlternateSelect: ((UUID) -> Void)?
    private var onClose: ((UUID) -> Void)?
    private var onRename: ((UUID, String) -> Void)?
    private var onContextMenu: ((UUID) -> Void)?
    private var onRevealInFinder: ((UUID) -> Void)?
    private var onOpenWithMenu: ((UUID) -> NSMenu?)?
    private var onStartContinuousReading: ((UUID) -> Void)?
    private var onExitContinuousReading: ((UUID) -> Void)?
    private var preEditTitle = ""

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isTabSelected: Bool = false {
        didSet { updateAppearance() }
    }

    init(
        sessionID: UUID,
        title: String,
        isSelected: Bool,
        isTabSelected: Bool,
        isDirty: Bool,
        isContinuousReadingMember: Bool = false,
        isContinuousReadingLeader: Bool = false,
        canStartContinuousReading: Bool = false,
        dragPayload: TabDragPayload?,
        onSelect: @escaping (UUID, NSEvent.ModifierFlags) -> Void,
        onAlternateSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onRename: @escaping (UUID, String) -> Void,
        onContextMenu: @escaping (UUID) -> Void,
        onRevealInFinder: @escaping (UUID) -> Void,
        onOpenWithMenu: @escaping (UUID) -> NSMenu?,
        onStartContinuousReading: @escaping (UUID) -> Void,
        onExitContinuousReading: @escaping (UUID) -> Void
    ) {
        self.sessionID = sessionID
        self.isDirty = isDirty
        self.isContinuousReadingMember = isContinuousReadingMember
        self.isContinuousReadingLeader = isContinuousReadingLeader
        self.canStartContinuousReading = canStartContinuousReading
        self.onSelect = onSelect
        self.onAlternateSelect = onAlternateSelect
        self.onClose = onClose
        self.onRename = onRename
        self.onContextMenu = onContextMenu
        self.onRevealInFinder = onRevealInFinder
        self.onOpenWithMenu = onOpenWithMenu
        self.onStartContinuousReading = onStartContinuousReading
        self.onExitContinuousReading = onExitContinuousReading
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0

        selectButton.dragPayload = dragPayload
        selectButton.dragPreviewView = self
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

        groupIndicator.wantsLayer = true
        groupIndicator.layer?.cornerRadius = 1
        groupIndicator.translatesAutoresizingMaskIntoConstraints = false
        groupIndicator.isHidden = !(isContinuousReadingMember || isContinuousReadingLeader)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.cell?.wraps = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.textColor = NightModeStyle.primaryTextColor
        titleLabel.backgroundColor = .clear
        titleLabel.delegate = self

        closeButton.font = .systemFont(ofSize: 13, weight: .regular)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.contentTintColor = NightModeStyle.secondaryTextColor
        closeButton.setButtonType(.momentaryChange)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        separator.boxType = .custom
        separator.isTransparent = false
        separator.fillColor = SplitViewController.dividerBackgroundColor

        let row = NSStackView(views: [dirtyIndicator, titleLabel, closeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 7
        row.edgeInsets = NSEdgeInsets(
            top: 6,
            left: isContinuousReadingMember ? 24 : 10,
            bottom: 6,
            right: 6
        )

        addSubview(selectButton)
        addSubview(groupIndicator)
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
            groupIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            groupIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            groupIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            groupIndicator.widthAnchor.constraint(equalToConstant: 2),
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
        self.isTabSelected = isTabSelected
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleSelect() {
        let modifierFlags = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift, .option, .control]) ?? []
        let isAlternate = modifierFlags.contains(.option)
        if isAlternate {
            onAlternateSelect?(sessionID)
        } else {
            onSelect?(sessionID, modifierFlags)
        }
    }

    @objc
    private func handleClose() {
        onClose?(sessionID)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if titleLabel.isEditable {
            return super.hitTest(point)
        }

        let localPoint = convert(point, from: superview)
        let closePoint = closeButton.convert(localPoint, from: self)
        if closeButton.bounds.contains(closePoint) {
            return closeButton
        }
        return selectButton
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(sessionID)
        let menu = NSMenu()
        if let openWithMenu = onOpenWithMenu?(sessionID) {
            let revealItem = NSMenuItem(
                title: "Reveal in Finder",
                action: #selector(handleRevealInFinder),
                keyEquivalent: ""
            )
            revealItem.target = self
            menu.addItem(revealItem)

            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
            menu.addItem(.separator())
        }
        let startItem = NSMenuItem(
            title: "Start Continuous Reading",
            action: #selector(handleStartContinuousReading),
            keyEquivalent: ""
        )
        startItem.target = self
        startItem.isEnabled = canStartContinuousReading
        menu.addItem(startItem)

        let exitItem = NSMenuItem(
            title: "Exit Continuous Reading",
            action: #selector(handleExitContinuousReading),
            keyEquivalent: ""
        )
        exitItem.target = self
        exitItem.isEnabled = isContinuousReadingMember || isContinuousReadingLeader
        menu.addItem(exitItem)
        return menu
    }

    @objc
    private func handleStartContinuousReading() {
        onStartContinuousReading?(sessionID)
    }

    @objc
    private func handleExitContinuousReading() {
        onExitContinuousReading?(sessionID)
    }

    @objc
    private func handleRevealInFinder() {
        onRevealInFinder?(sessionID)
    }

    func beginEditing() {
        guard titleLabel.isEditable == false else { return }
        preEditTitle = titleLabel.stringValue
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.isBezeled = true
        titleLabel.drawsBackground = true
        titleLabel.backgroundColor = .controlBackgroundColor
        window?.makeFirstResponder(titleLabel)
        titleLabel.currentEditor()?.selectAll(nil)
    }

    private func commitEditing() {
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.backgroundColor = .clear

        let newTitle = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newTitle.isEmpty == false, newTitle != preEditTitle else {
            titleLabel.stringValue = preEditTitle
            return
        }
        titleLabel.stringValue = newTitle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onRename?(self.sessionID, newTitle)
        }
    }

    private func cancelEditing() {
        titleLabel.stringValue = preEditTitle
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.backgroundColor = .clear
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshChromeColors() {
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelected {
                layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor.cgColor
            } else if isTabSelected {
                layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor
                    .withAlphaComponent(0.45)
                    .cgColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
            layer?.borderColor = isSelected ? SplitViewController.chromeStrokeColor.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isSelected ? 1 : 0
            dirtyIndicator.layer?.backgroundColor = HighlightColor.pink.nsColor.cgColor
            groupIndicator.layer?.backgroundColor = isContinuousReadingLeader
                ? HighlightColor.pink.nsColor.cgColor
                : SplitViewController.chromeStrokeColor.withAlphaComponent(0.75).cgColor
        }
        titleLabel.textColor = isSelected || isTabSelected
            ? NightModeStyle.primaryTextColor
            : NightModeStyle.secondaryTextColor
        closeButton.contentTintColor = isSelected
            ? NightModeStyle.primaryTextColor
            : NightModeStyle.tertiaryTextColor
        separator.isHidden = isSelected
    }
}

extension VerticalTabItemView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}

#if DEBUG
extension VerticalTabItemView {
    var testingIsEditing: Bool {
        titleLabel.isEditable
    }
}
#endif
