import AppKit

private final class WorkspaceIconsScrollView: NSScrollView {
    var onScroll: ((NSEvent) -> Bool)?
    var onLayout: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true { super.scrollWheel(with: event) }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

private final class WorkspaceMenuRowView: NSView {
    var isHighlighted = false { didSet { needsDisplay = true } }

    init(width: CGFloat, isSeparator: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: isSeparator ? 7 : 26))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool {
        enclosingMenuItem?.isEnabled == true && enclosingMenuItem?.isSeparatorItem == false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = enclosingMenuItem else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NightModeStyle.readerBackdropColor.setFill()
            bounds.fill()
            if item.isSeparatorItem {
                NightModeStyle.tertiaryTextColor.withAlphaComponent(0.18).setFill()
                NSRect(x: 10, y: bounds.midY, width: bounds.width - 20, height: 0.5).fill()
                return
            }
            if isHighlighted || item.state == .on {
                SplitViewController.selectedChromeBackgroundColor
                    .withAlphaComponent(isHighlighted ? 0.65 : 0.4).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 4, yRadius: 4).fill()
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let title = NSAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: item.isEnabled ? NightModeStyle.primaryTextColor : NightModeStyle.tertiaryTextColor,
                .paragraphStyle: paragraph,
            ])
            let height = title.size().height
            title.draw(in: NSRect(x: 10, y: (bounds.height - height) / 2,
                                  width: bounds.width - 20, height: height))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        performMenuAction(enclosingMenuItem)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            performMenuAction(enclosingMenuItem?.menu?.highlightedItem)
        } else {
            super.keyDown(with: event)
        }
    }

    private func performMenuAction(_ item: NSMenuItem?) {
        guard let item, item.isEnabled, !item.isSeparatorItem,
              let menu = item.menu else { return }
        let index = menu.index(of: item)
        menu.cancelTracking()
        menu.performActionForItem(at: index)
    }
}

final class WorkspaceSelectorView: NSView, NSTextFieldDelegate, NSMenuDelegate {
    enum Style {
        case compact
        case sidebarFooter
    }

    private struct MoveDestination {
        let sessionID: UUID
        let workspaceID: UUID
    }

    private struct WorkspaceItem: Equatable {
        let id: UUID
        let name: String
    }

    let style: Style
    private let documentStore: DocumentStore
    private let windowID: UUID
    private let menuButton = NSButton(title: "", target: nil, action: nil)
    private let iconsScrollView = WorkspaceIconsScrollView()
    private let iconsDocumentView = NSView()
    private let iconsStack = NSStackView()
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private var iconButtons: [NSButton] = []
    private var displayedItems: [WorkspaceItem] = []
    private var displayedActiveID: UUID?
    private var needsRevealActiveIcon = false
    private var gestureIsHorizontal: Bool?
    private var gestureDeltaX: CGFloat = 0
    private var didSwitchInGesture = false
    private weak var nameSubmitButton: NSButton?
    private weak var nameField: NSTextField?
    private weak var openMenu: NSMenu?

    init(documentStore: DocumentStore, windowID: UUID, style: Style = .compact) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.style = style
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(style == .sidebarFooter ? "workspaceFooter" : "workspaceSelector")
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if style == .sidebarFooter {
            configureFooter()
        } else {
            configureNameButton()
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        if style == .sidebarFooter { return NSSize(width: 120, height: 28) }
        return NSSize(width: 26, height: 24)
    }

    private func configureNameButton() {
        menuButton.isBordered = false
        menuButton.focusRingType = .none
        menuButton.target = self
        menuButton.action = #selector(showWorkspaceMenu)
        menuButton.identifier = NSUserInterfaceItemIdentifier("workspaceMenuButton")
        menuButton.setAccessibilityLabel(L10n.text("Workspace", "工作区"))
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        menuButton.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        menuButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        menuButton.imagePosition = .imageOnly
        widthAnchor.constraint(equalToConstant: 26).isActive = true
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
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.text("New Workspace", "新建工作区"))
        addButton.imageScaling = .scaleProportionallyDown
        addButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        addButton.toolTip = L10n.text("New Workspace", "新建工作区")
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

    func refresh() {
        let workspaces = documentStore.workspaces(in: windowID)
        let activeID = documentStore.activeWorkspaceID(in: windowID)
        let active = workspaces.first { $0.id == activeID }
        menuButton.toolTip = active?.name
        menuButton.setAccessibilityValue(active?.name)
        let items = workspaces.map { WorkspaceItem(id: $0.id, name: $0.name) }
        if style == .sidebarFooter, items != displayedItems {
            iconsStack.arrangedSubviews.forEach {
                iconsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            iconButtons = items.map { item in
                let button = NSButton(title: monogram(for: item.name), target: self, action: #selector(activateIcon(_:)))
                button.font = .systemFont(ofSize: 11, weight: .medium)
                button.isBordered = false
                button.focusRingType = .none
                button.toolTip = item.name
                button.setAccessibilityLabel(item.name)
                button.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
                button.menu = workspaceMenu(for: item.id)
                button.wantsLayer = true
                button.layer?.cornerRadius = 3
                iconsStack.addArrangedSubview(button)
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 24),
                    button.heightAnchor.constraint(equalToConstant: 24),
                ])
                return button
            }
        }
        needsRevealActiveIcon = needsRevealActiveIcon || items != displayedItems || activeID != displayedActiveID
        displayedItems = items
        displayedActiveID = activeID
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
                    ? SplitViewController.selectedChromeBackgroundColor.withAlphaComponent(0.45).cgColor
                    : NSColor.clear.cgColor
                button.setAccessibilityValue(isActive ? L10n.text("Current Workspace", "当前工作区") : nil)
            }
        }
        refreshMenuColors(openMenu)
        refreshNameEditorColors()
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

    @objc private func activateMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        activateWorkspace(id)
    }

    private func workspaceMenu(for workspaceID: UUID? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let font = NSFont.systemFont(ofSize: 13)
        menu.font = font
        menu.appearance = effectiveAppearance
        menu.delegate = self
        if style == .compact {
            for workspace in documentStore.workspaces(in: windowID) {
                let item = NSMenuItem(title: workspace.name, action: #selector(activateMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = workspace.id
                item.state = workspace.id == documentStore.activeWorkspaceID(in: windowID) ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let create = NSMenuItem(title: L10n.text("New Workspace", "新建工作区"), action: #selector(createWorkspace), keyEquivalent: "")
        create.target = self
        menu.addItem(create)
        let rename = NSMenuItem(title: L10n.text("Rename", "重命名"), action: #selector(renameWorkspace(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = (workspaceID ?? documentStore.activeWorkspaceID(in: windowID))?.uuidString
        rename.isEnabled = rename.representedObject != nil
        menu.addItem(rename)
        let delete = NSMenuItem(title: L10n.text("Delete Workspace", "删除工作区"), action: #selector(deleteWorkspace(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = rename.representedObject
        delete.isEnabled = delete.representedObject != nil && documentStore.workspaces(in: windowID).count > 1
        menu.addItem(delete)
        let width = min(max(menu.items.map {
            ($0.title as NSString).size(withAttributes: [.font: font]).width + 20
        }.max() ?? 0, 140), 240)
        for item in menu.items {
            let row = WorkspaceMenuRowView(width: ceil(width), isSeparator: item.isSeparatorItem)
            row.appearance = effectiveAppearance
            row.toolTip = item.title
            item.view = row
        }
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenu = menu
        refreshMenuColors(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenu = nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for rowItem in menu.items {
            (rowItem.view as? WorkspaceMenuRowView)?.isHighlighted = rowItem === item
        }
    }

    private func refreshMenuColors(_ menu: NSMenu?) {
        menu?.appearance = effectiveAppearance
        menu?.items.forEach {
            $0.view?.appearance = effectiveAppearance
            $0.view?.needsDisplay = true
        }
    }

    @objc private func showWorkspaceMenu() {
        workspaceMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }

    @objc private func createWorkspace() { presentNameEditor(workspaceID: nil) }

    @objc private func renameWorkspace(_ sender: NSMenuItem) {
        if let rawID = sender.representedObject as? String, let id = UUID(uuidString: rawID) {
            presentNameEditor(workspaceID: id)
        }
    }

    @objc private func deleteWorkspace(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String, let id = UUID(uuidString: rawID),
              let controller = window?.windowController as? MainWindowController else { return }
        controller.requestDeleteWorkspace(id)
        refresh()
    }

    private func monogram(for name: String) -> String { String(name.prefix(1)).uppercased() }

    private func presentNameEditor(workspaceID: UUID?) {
        guard let window else { return }
        let workspaces = documentStore.workspaces(in: windowID)
        let currentName = workspaces.first { $0.id == workspaceID }?.name
        var nextNumber = workspaces.count + 1
        while workspaces.contains(where: { $0.name == L10n.text("Workspace \(nextNumber)", "工作区 \(nextNumber)") }) { nextNumber += 1 }
        let alert = NSAlert()
        alert.messageText = workspaceID == nil ? L10n.text("New Workspace", "新建工作区") : L10n.text("Rename Workspace", "重命名工作区")
        alert.addButton(withTitle: workspaceID == nil ? L10n.text("Create", "创建") : L10n.text("Rename", "重命名"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        let field = NSTextField(string: currentName ?? L10n.text("Workspace \(nextNumber)", "工作区 \(nextNumber)"))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.setAccessibilityLabel(L10n.text("Workspace name", "工作区名称"))
        field.delegate = self
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        nameSubmitButton = alert.buttons.first
        nameField = field
        refreshNameEditorColors()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.nameSubmitButton = nil
            self.nameField = nil
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            if let workspaceID {
                self.documentStore.renameWorkspace(workspaceID, name: name, in: self.windowID)
            } else {
                self.flushPendingReadingPositions()
                self.documentStore.createWorkspace(name: name, in: self.windowID)
            }
            self.refresh()
        }
    }

    private func refreshNameEditorColors() {
        guard let field = nameField else { return }
        field.window?.appearance = effectiveAppearance
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            field.textColor = NightModeStyle.primaryTextColor
            field.backgroundColor = NightModeStyle.readerBackdropColor
            if let editor = field.currentEditor() as? NSTextView {
                editor.textColor = NightModeStyle.primaryTextColor
                editor.backgroundColor = NightModeStyle.readerBackdropColor
                editor.insertionPointColor = NightModeStyle.primaryTextColor
                editor.selectedTextAttributes = [
                    .foregroundColor: NightModeStyle.primaryTextColor,
                    .backgroundColor: SplitViewController.selectedChromeBackgroundColor,
                ]
            }
        }
    }

    func controlTextDidBeginEditing(_ notification: Notification) { refreshNameEditorColors() }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        nameSubmitButton?.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    var testingMenu: NSMenu { workspaceMenu() }
    var testingWorkspaceButtons: [NSButton] { iconButtons }
    var testingAddButton: NSButton { addButton }
    var testingNameField: NSTextField? { nameField }
    func testingActivateWorkspace(_ id: UUID) { activateWorkspace(id) }
    func testingHandleScrollWheel(_ event: NSEvent) -> Bool { handleScrollWheel(event) }
    func testingPresentNameEditor(workspaceID: UUID?) { presentNameEditor(workspaceID: workspaceID) }
}
#endif
