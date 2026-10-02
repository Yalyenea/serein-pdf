import AppKit

final class TitlebarTabItemView: NSView {
    override var acceptsFirstResponder: Bool { true }
    private static let cornerRadius: CGFloat = 4
    private static let minimumWidth: CGFloat = 88
    private static let maximumWidth: CGFloat = 196
    let sessionID: UUID
    private let selectButton = TabDragSourceButton(title: "", target: nil, action: nil)
    private let dirtyIndicator = NSView()
    private let groupIndicator = NSView()
    private let titleLabel = NSTextField()
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let contentStackView = NSStackView()
    private var isDirty: Bool
    private var isContinuousReadingMember: Bool
    private var isContinuousReadingLeader: Bool
    private var canStartContinuousReading: Bool
    private var onSelect: ((UUID, NSEvent.ModifierFlags) -> Void)?
    private var onAlternateSelect: ((UUID) -> Void)?
    private var onClose: ((UUID) -> Void)?
    private var onRename: ((UUID, String) -> Void)?
    private var onContextMenu: ((UUID) -> Void)?
    private var onRevealInFinder: ((UUID) -> Void)?
    private var onOpenWithMenu: ((UUID) -> NSMenu?)?
    private var onMoveToWorkspaceMenu: ((UUID) -> NSMenu?)?
    private var onStartContinuousReading: ((UUID) -> Void)?
    private var onExitContinuousReading: ((UUID) -> Void)?
    private var preEditTitle = ""
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?
    private var preferredWidthConstraint: NSLayoutConstraint?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isTabSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isEditing: Bool { titleLabel.isEditable }

    override var intrinsicContentSize: NSSize {
        let dirtyWidth: CGFloat = isDirty ? 12 : 0
        let groupWidth: CGFloat = isContinuousReadingMember ? 8 : 0
        let width = titleLabel.intrinsicContentSize.width + dirtyWidth + groupWidth + 40
        return NSSize(width: min(max(width, Self.minimumWidth), Self.maximumWidth), height: 24)
    }

    init(
        sessionID: UUID,
        title: String,
        filename: String? = nil,
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
        onExitContinuousReading: @escaping (UUID) -> Void,
        onMoveToWorkspaceMenu: ((UUID) -> NSMenu?)? = nil
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
        self.onMoveToWorkspaceMenu = onMoveToWorkspaceMenu
        self.onStartContinuousReading = onStartContinuousReading
        self.onExitContinuousReading = onExitContinuousReading
        super.init(frame: .zero)

        toolTip = filename
        titleLabel.toolTip = filename
        selectButton.toolTip = filename

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
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
        titleLabel.font = .systemFont(ofSize: 11.5)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.textColor = NightModeStyle.primaryTextColor
        titleLabel.backgroundColor = .clear
        titleLabel.delegate = self

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.text("Close Tab", "关闭标签"))
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        closeButton.toolTip = L10n.text("Close Tab", "关闭标签")
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.setButtonType(.momentaryChange)

        let stack = contentStackView
        [groupIndicator, dirtyIndicator, titleLabel, closeButton].forEach(stack.addArrangedSubview)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(
            top: 0,
            left: isContinuousReadingMember ? 12 : 9,
            bottom: 0,
            right: 6
        )

        addSubview(selectButton)
        addSubview(stack)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let preferredWidthConstraint = widthAnchor.constraint(equalToConstant: intrinsicContentSize.width)
        preferredWidthConstraint.priority = .defaultHigh
        self.preferredWidthConstraint = preferredWidthConstraint

        NSLayoutConstraint.activate([
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectButton.topAnchor.constraint(equalTo: topAnchor),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            preferredWidthConstraint,
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumWidth),
            groupIndicator.widthAnchor.constraint(equalToConstant: 2),
            groupIndicator.heightAnchor.constraint(equalToConstant: 14),
            dirtyIndicator.widthAnchor.constraint(equalToConstant: 6),
            dirtyIndicator.heightAnchor.constraint(equalToConstant: 6),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 24),
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
            window?.makeFirstResponder(self)
            onSelect?(sessionID, modifierFlags)
        }
    }

    @objc
    private func handleClose() {
        onClose?(sessionID)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if titleLabel.isEditable {
            return super.hitTest(point)
        }

        let localPoint = convert(point, from: superview)
        let closePoint = closeButton.convert(localPoint, from: self)
        if closeButton.alphaValue > 0, closeButton.bounds.contains(closePoint) {
            return closeButton
        }
        return selectButton
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(sessionID)
        let menu = NSMenu()
        if let workspaces = onMoveToWorkspaceMenu?(sessionID) {
            let moveItem = NSMenuItem(title: L10n.text("Move to Workspace", "移至工作区"), action: nil, keyEquivalent: "")
            moveItem.submenu = workspaces
            menu.addItem(moveItem)
            menu.addItem(.separator())
        }
        if let openWithMenu = onOpenWithMenu?(sessionID) {
            let revealItem = NSMenuItem(
                title: L10n.text("Reveal in Finder", "在访达中显示"),
                action: #selector(handleRevealInFinder),
                keyEquivalent: ""
            )
            revealItem.target = self
            menu.addItem(revealItem)

            let openWithItem = NSMenuItem(title: L10n.text("Open With", "打开方式"), action: nil, keyEquivalent: "")
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
            menu.addItem(.separator())
        }
        let startItem = NSMenuItem(
            title: L10n.text("Start Continuous Reading", "开始连续阅读"),
            action: #selector(handleStartContinuousReading),
            keyEquivalent: ""
        )
        startItem.target = self
        startItem.isEnabled = canStartContinuousReading
        menu.addItem(startItem)

        let exitItem = NSMenuItem(
            title: L10n.text("Exit Continuous Reading", "退出连续阅读"),
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
        updateAppearance()
        window?.makeFirstResponder(titleLabel)
        updateAppearance()
        titleLabel.currentEditor()?.selectAll(nil)
    }

    func finishEditing() {
        guard isEditing else { return }
        if let editor = titleLabel.currentEditor() { titleLabel.stringValue = editor.string }
        commitEditing()
        window?.makeFirstResponder(nil)
    }

    private func commitEditing() {
        guard titleLabel.isEditable else { return }
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.backgroundColor = .clear

        let newTitle = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newTitle.isEmpty == false, newTitle != preEditTitle else {
            titleLabel.stringValue = preEditTitle
            updateAppearance()
            return
        }
        titleLabel.stringValue = newTitle
        updateAppearance()
        let onRename = self.onRename
        let sessionID = self.sessionID
        DispatchQueue.main.async {
            onRename?(sessionID, newTitle)
        }
    }

    private func cancelEditing() {
        titleLabel.stringValue = preEditTitle
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.backgroundColor = .clear
        updateAppearance()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshChromeColors() {
        updateAppearance()
    }

    func updateState(
        isSelected: Bool, isTabSelected: Bool, isDirty: Bool,
        isContinuousReadingMember: Bool, isContinuousReadingLeader: Bool,
        canStartContinuousReading: Bool
    ) {
        self.isSelected = isSelected
        self.isTabSelected = isTabSelected
        self.isDirty = isDirty
        self.isContinuousReadingMember = isContinuousReadingMember
        self.isContinuousReadingLeader = isContinuousReadingLeader
        self.canStartContinuousReading = canStartContinuousReading
        dirtyIndicator.isHidden = !isDirty
        groupIndicator.isHidden = !(isContinuousReadingMember || isContinuousReadingLeader)
        contentStackView.edgeInsets.left = isContinuousReadingMember ? 12 : 9
        invalidateIntrinsicContentSize()
        updateAppearance()
    }

    private func updateAppearance() {
        preferredWidthConstraint?.constant = intrinsicContentSize.width
        let showsCloseButton = isSelected || isHovered || isEditing
        closeButton.alphaValue = showsCloseButton ? 1 : 0
        closeButton.isEnabled = showsCloseButton
        closeButton.setAccessibilityHidden(!showsCloseButton)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelected {
                layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor.withAlphaComponent(0.5).cgColor
            } else if isTabSelected {
                layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor
                    .withAlphaComponent(0.3)
                    .cgColor
            } else if isHovered {
                layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor
                    .withAlphaComponent(0.16)
                    .cgColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            dirtyIndicator.layer?.backgroundColor = HighlightColor.pink.nsColor.cgColor
            groupIndicator.layer?.backgroundColor = isContinuousReadingLeader
                ? HighlightColor.pink.nsColor.cgColor
                : SplitViewController.chromeStrokeColor.withAlphaComponent(0.75).cgColor
            titleLabel.textColor = isSelected || isTabSelected || titleLabel.isEditable
                ? NightModeStyle.primaryTextColor
                : NightModeStyle.secondaryTextColor
            titleLabel.backgroundColor = titleLabel.isEditable ? NightModeStyle.readerBackdropColor : .clear
            closeButton.contentTintColor = isSelected
                ? NightModeStyle.secondaryTextColor
                : NightModeStyle.tertiaryTextColor
            if let editor = titleLabel.currentEditor() as? NSTextView {
                editor.textColor = NightModeStyle.primaryTextColor
                editor.backgroundColor = NightModeStyle.readerBackdropColor
                editor.insertionPointColor = NightModeStyle.primaryTextColor
                editor.selectedTextAttributes = [
                    .backgroundColor: SplitViewController.selectedChromeBackgroundColor,
                    .foregroundColor: NightModeStyle.primaryTextColor,
                ]
            }
        }
    }
}

extension TitlebarTabItemView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            titleLabel.stringValue = textView.string
            commitEditing()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
}

#if DEBUG
extension TitlebarTabItemView {
    var testingIsEditing: Bool {
        titleLabel.isEditable
    }
}
#endif
