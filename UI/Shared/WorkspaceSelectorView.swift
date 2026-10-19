import AppKit

private final class WorkspaceIconsScrollView: NSScrollView {
    var onScroll: ((NSEvent) -> Bool)?
    var onLayout: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true { super.scrollWheel(with: event) }
    }
    override func layout() { super.layout(); onLayout?() }
}

final class WorkspaceSelectorView: NSView {
    enum Style { case compact, sidebarFooter }
    private struct MoveDestination {
        let sessionID: UUID
        let workspaceID: UUID
    }
    let style: Style
    private let documentStore: DocumentStore
    private let windowID: UUID
    private let menuButton = SpaceButton(title: "", target: nil, action: nil)
    private let iconsScrollView = WorkspaceIconsScrollView()
    private let iconsDocumentView = NSView()
    private let iconsStack = NSStackView()
    private let addButton = SpaceButton(title: "", target: nil, action: nil)
    private var iconButtons: [NSButton] = []
    private var displayedItems: [NamedWorkspace] = []
    private var displayedActiveID: UUID?
    private var needsRevealActiveIcon = false
    private var gestureIsHorizontal: Bool?
    private var gestureDeltaX: CGFloat = 0
    private var didSwitchInGesture = false

    private lazy var picker: SpacePickerController = {
        let picker = SpacePickerController()
        picker.onActivate = { [weak self] in self?.activateWorkspace($0) }
        picker.onCreate = { [weak self] name, icon in
            guard let self else { return }
            self.flushPendingReadingPositions()
            self.documentStore.createWorkspace(name: name, icon: icon, in: self.windowID)
            self.refresh()
        }
        picker.onRename = { [weak self] id, name in
            guard let self else { return }
            self.documentStore.renameWorkspace(id, name: name, in: self.windowID)
            self.refresh()
        }
        picker.onIcon = { [weak self] id, icon in
            guard let self else { return }
            self.documentStore.setWorkspaceIcon(icon, for: id, in: self.windowID)
            self.refresh()
        }
        picker.onDelete = { [weak self] in self?.deleteWorkspace($0) }
        return picker
    }()

    init(documentStore: DocumentStore, windowID: UUID, style: Style = .compact) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.style = style
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(style == .sidebarFooter ? "workspaceFooter" : "workspaceSelector")
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if style == .sidebarFooter { configureFooter() } else { configureNameButton() }
        refresh()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        if style == .sidebarFooter { return NSSize(width: 120, height: 28) }
        return NSSize(width: 26, height: 24)
    }
    private func configureNameButton() {
        menuButton.isBordered = false
        menuButton.focusRingType = .none
        menuButton.target = self
        menuButton.action = #selector(showWorkspacePicker)
        menuButton.identifier = NSUserInterfaceItemIdentifier("workspaceMenuButton")
        menuButton.setAccessibilityLabel(L10n.text("Space", "空间"))
        menuButton.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        menuButton.imagePosition = .imageOnly
        menuButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(equalToConstant: 26),
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    private func configureFooter() {
        iconsStack.orientation = .horizontal
        iconsStack.alignment = .centerY
        iconsStack.spacing = 4
        iconsStack.translatesAutoresizingMaskIntoConstraints = false
        iconsDocumentView.addSubview(iconsStack)
        iconsScrollView.drawsBackground = false
        iconsScrollView.borderType = .noBorder
        iconsScrollView.hasHorizontalScroller = true
        iconsScrollView.hasVerticalScroller = false
        iconsScrollView.scrollerStyle = .overlay
        iconsScrollView.autohidesScrollers = true
        iconsScrollView.documentView = iconsDocumentView
        iconsScrollView.onScroll = { [weak self] in self?.handleScrollWheel($0) == true }
        iconsScrollView.onLayout = { [weak self] in self?.layoutWorkspaceIcons() }
        addButton.isBordered = false
        addButton.focusRingType = .none
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        addButton.toolTip = L10n.text("New space", "新建空间")
        addButton.setAccessibilityLabel(addButton.toolTip)
        addButton.target = self
        addButton.action = #selector(createWorkspace)
        let content = NSStackView(views: [iconsScrollView, addButton])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconsScrollView.heightAnchor.constraint(equalToConstant: 24),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24),
            iconsStack.leadingAnchor.constraint(equalTo: iconsDocumentView.leadingAnchor),
            iconsStack.topAnchor.constraint(equalTo: iconsDocumentView.topAnchor),
            iconsStack.bottomAnchor.constraint(equalTo: iconsDocumentView.bottomAnchor),
        ])
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return style == .sidebarFooter || hit == nil ? hit : menuButton
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChromeColors()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { picker.dismiss() }
        super.viewWillMove(toWindow: newWindow)
    }
    func refresh() {
        let items = documentStore.workspaces(in: windowID)
        let activeID = documentStore.activeWorkspaceID(in: windowID)
        let active = items.first { $0.id == activeID }
        menuButton.toolTip = active?.name
        menuButton.setAccessibilityValue(active?.name)
        // Selection and editing must not replace buttons halfway through a double click.
        if style == .sidebarFooter, items.map(\.id) != displayedItems.map(\.id) {
            iconsStack.arrangedSubviews.forEach {
                iconsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            iconButtons = items.map { item in
                let button = SpaceButton(title: "", target: self, action: #selector(activateIcon(_:)))
                // Sidebar clicks switch directly; right-clicks use the titlebar's picker.
                button.onRightClick = { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.togglePicker(relativeTo: button)
                }
                button.onDoubleClick = { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.showPicker(relativeTo: button)
                    self.picker.beginRenaming(item.id)
                }
                button.isBordered = false
                button.focusRingType = .none
                button.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
                button.wantsLayer = true
                button.layer?.cornerRadius = 3
                button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                iconsStack.addArrangedSubview(button)
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 24),
                    button.heightAnchor.constraint(equalToConstant: 24),
                ])
                return button
            }
        }
        for (button, item) in zip(iconButtons, items) {
            button.title = item.icon == nil ? String(item.name.prefix(1)).uppercased() : ""
            button.image = item.icon.flatMap { NSImage(systemSymbolName: $0.rawValue, accessibilityDescription: nil) }
            button.imagePosition = item.icon == nil ? .noImage : .imageOnly
            button.toolTip = item.name
            button.setAccessibilityLabel(item.name)
        }
        needsRevealActiveIcon = needsRevealActiveIcon || items.map(\.id) != displayedItems.map(\.id) || activeID != displayedActiveID
        displayedItems = items
        displayedActiveID = activeID
        picker.update(spaces: items, activeID: activeID)
        invalidateIntrinsicContentSize()
        iconsScrollView.needsLayout = true
        needsLayout = true
        refreshChromeColors()
    }
    private func layoutWorkspaceIcons() {
        iconsDocumentView.frame.size = NSSize(width: max(iconsScrollView.contentSize.width, iconsStack.fittingSize.width), height: 24)
        iconsDocumentView.layoutSubtreeIfNeeded()
        if needsRevealActiveIcon, let button = activeIconButton {
            button.scrollToVisible(button.bounds)
            needsRevealActiveIcon = false
        }
    }
    private var activeIconButton: NSButton? {
        iconButtons.first { $0.identifier?.rawValue == displayedActiveID?.uuidString }
    }
    func refreshChromeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            menuButton.contentTintColor = NightModeStyle.secondaryTextColor
            addButton.contentTintColor = NightModeStyle.secondaryTextColor
            for button in iconButtons {
                let isActive = button === activeIconButton
                button.contentTintColor = isActive ? NightModeStyle.primaryTextColor : NightModeStyle.secondaryTextColor
                button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: isActive ? NightModeStyle.primaryTextColor : NightModeStyle.secondaryTextColor,
                ])
                button.layer?.backgroundColor = isActive
                    ? SplitViewController.selectedChromeBackgroundColor.withAlphaComponent(0.45).cgColor : NSColor.clear.cgColor
                button.setAccessibilityValue(isActive ? L10n.text("Current Space", "当前空间") : nil)
            }
        }
        picker.refreshTheme(appearance: effectiveAppearance)
    }
    override func scrollWheel(with event: NSEvent) {
        if !handleScrollWheel(event) { super.scrollWheel(with: event) }
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, event.hasPreciseScrollingDeltas else { return false }
        if !event.momentumPhase.isEmpty {
            return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            gestureIsHorizontal = nil
            gestureDeltaX = 0
            didSwitchInGesture = false
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let consumed = gestureIsHorizontal == true
            gestureIsHorizontal = nil
            gestureDeltaX = 0
            didSwitchInGesture = false
            return consumed
        }
        guard !event.phase.isEmpty else { return false }
        if gestureIsHorizontal == nil {
            guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return false }
            gestureIsHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        guard gestureIsHorizontal == true else { return false }
        gestureDeltaX += event.scrollingDeltaX
        if !didSwitchInGesture, abs(gestureDeltaX) >= 18 {
            didSwitchInGesture = true
            flushPendingReadingPositions()
            documentStore.activateAdjacentWorkspace(direction: gestureDeltaX < 0 ? 1 : -1, in: windowID)
            refresh()
        }
        return true
    }

    private func flushPendingReadingPositions() {
        (window?.windowController as? MainWindowController)?.flushPendingReadingPositions()
    }

    private func activateWorkspace(_ id: UUID) {
        guard id != documentStore.activeWorkspaceID(in: windowID) else { return }
        flushPendingReadingPositions()
        documentStore.activateWorkspace(id, in: windowID)
        refresh()
    }

    @objc private func activateIcon(_ sender: NSButton) {
        guard let rawID = sender.identifier?.rawValue, let id = UUID(uuidString: rawID) else { return }
        activateWorkspace(id)
    }
    private func showPicker(relativeTo anchor: NSView) {
        refresh()
        picker.show(relativeTo: anchor, above: style == .sidebarFooter)
    }
    private func togglePicker(relativeTo anchor: NSView) {
        if picker.isVisible { picker.dismiss() } else { showPicker(relativeTo: anchor) }
    }
    @objc private func showWorkspacePicker() {
        togglePicker(relativeTo: menuButton)
    }
    @objc private func createWorkspace() {
        showPicker(relativeTo: style == .sidebarFooter ? addButton : menuButton)
        picker.beginCreating()
    }
    private func deleteWorkspace(_ id: UUID) {
        guard let controller = window?.windowController as? MainWindowController else { return }
        picker.dismiss()
        controller.requestDeleteWorkspace(id)
        refresh()
    }
    func moveMenu(for sessionID: UUID) -> NSMenu? {
        guard let session = documentStore.session(for: sessionID), !session.isBlank else { return nil }
        let activeID = documentStore.activeWorkspaceID(in: windowID)
        let destinations = documentStore.workspaces(in: windowID).filter { $0.id != activeID }
        guard !destinations.isEmpty else { return nil }
        let menu = NSMenu()
        for workspace in destinations {
            let item = NSMenuItem(title: workspace.name, action: #selector(moveDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MoveDestination(sessionID: sessionID, workspaceID: workspace.id)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func moveDocument(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? MoveDestination else { return }
        flushPendingReadingPositions()
        documentStore.moveSession(destination.sessionID, toWorkspace: destination.workspaceID, in: windowID)
    }
}

#if DEBUG
extension WorkspaceSelectorView {
    var testingCurrentWorkspaceName: String { displayedItems.first { $0.id == displayedActiveID }?.name ?? "" }
    var testingWorkspaceButtons: [NSButton] { iconButtons }
    var testingAddButton: NSButton { addButton }
    var testingPicker: SpacePickerController { picker }
    func testingActivateWorkspace(_ id: UUID) { activateWorkspace(id) }
    func testingHandleScrollWheel(_ event: NSEvent) -> Bool { handleScrollWheel(event) }
    func testingShowPicker() { showPicker(relativeTo: style == .sidebarFooter ? addButton : menuButton) }
}
#endif
