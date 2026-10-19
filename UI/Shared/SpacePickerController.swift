import AppKit

/// Keep the name button alive through the first click so the second can start editing.
final class SpaceButton: NSButton {
    var onDoubleClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
        else if event.clickCount == 2, let onDoubleClick { onDoubleClick() }
        else { super.mouseDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick() } else { performClick(nil) }
    }
}

private final class SpacePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SpacePickerSurface: NSView {
    override var isFlipped: Bool { true }
}

private final class SpacePickerRow: NSView {
    let iconButton = SpaceButton(title: "", target: nil, action: nil)
    let nameButton = SpaceButton(title: "", target: nil, action: nil)
    let field = NSTextField(string: "")
    var isActive = false
    var isFocused = false
    var isEditing = false
    var isHovered = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        for button in [iconButton, nameButton] {
            button.isBordered = false
            button.focusRingType = .none
            button.font = .systemFont(ofSize: 13)
            addSubview(button)
        }
        iconButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        nameButton.alignment = .left
        nameButton.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isHidden = true
        field.setAccessibilityLabel(L10n.text("Space name", "空间名称"))
        addSubview(field)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        iconButton.frame = NSRect(x: 4, y: 3, width: 24, height: 22)
        nameButton.frame = NSRect(x: 31, y: 3, width: bounds.width - 39, height: 22)
        field.frame = NSRect(x: 31, y: 5, width: bounds.width - 39, height: 19)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; refreshTheme() }
    override func mouseExited(with event: NSEvent) { isHovered = false; refreshTheme() }
    override func rightMouseDown(with event: NSEvent) { nameButton.performClick(nil) }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isEditing {
            NightModeStyle.secondaryTextColor.withAlphaComponent(0.4).setFill()
            NSRect(x: 31, y: 4, width: bounds.width - 39, height: 0.5).fill()
        }
    }
    func refreshTheme() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let amount = isActive ? 0.4 : (isFocused || isHovered ? 0.22 : 0)
            layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor.withAlphaComponent(amount).cgColor
            nameButton.attributedTitle = NSAttributedString(string: nameButton.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isActive ? .medium : .regular),
                .foregroundColor: NightModeStyle.primaryTextColor,
            ])
            iconButton.contentTintColor = NightModeStyle.secondaryTextColor
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
            needsDisplay = true
        }
    }
}

/// One anchored surface owns switching, inline editing and icon selection.
/// Only completed edits reach DocumentStore; switching never replaces an active field editor.
@MainActor
final class SpacePickerController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var onActivate: ((UUID) -> Void)?
    var onCreate: ((String, SpaceIcon?) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onIcon: ((UUID, SpaceIcon?) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private let panel = SpacePickerPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private let surface = SpacePickerSurface()
    private let scroll = NSScrollView()
    private let list = SpacePickerSurface()
    private let newButton = SpaceButton(title: "", target: nil, action: nil)
    private let divider = NSView()
    private let iconGrid = SpacePickerSurface()
    private var iconChoices: [NSButton] = []
    private var rows: [UUID: SpacePickerRow] = [:]
    private var draftRow: SpacePickerRow?
    private var spaces: [NamedWorkspace] = []
    private var activeID: UUID?
    private var focusedID: UUID?
    private var editingID: UUID?
    private var isCreating = false
    private var draftIcon: SpaceIcon?
    private var iconTarget: UUID?
    private var choosingDraftIcon = false
    private var focusedIconIndex = 0
    private var isFinishing = false
    private var isDismissing = false
    private var anchorIsAbove = false
    private weak var anchor: NSView?
    nonisolated(unsafe) private var eventMonitor: Any?
    private static let width: CGFloat = 196

    var isVisible: Bool { panel.isVisible }
    var activeNameField: NSTextField? { editingRow?.field }
    private var editingRow: SpacePickerRow? { isCreating ? draftRow : editingID.flatMap { rows[$0] } }

    override init() {
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.contentView = surface
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 7
        surface.layer?.borderWidth = 0.5
        surface.layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        surface.addSubview(scroll)
        divider.wantsLayer = true
        surface.addSubview(divider)
        newButton.isBordered = false
        newButton.focusRingType = .none
        newButton.alignment = .left
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        newButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        newButton.imagePosition = .imageLeading
        newButton.title = "  " + L10n.text("New space", "新建空间")
        newButton.target = self
        newButton.action = #selector(createSpace)
        surface.addSubview(newButton)
        surface.addSubview(iconGrid)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(parentWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func update(spaces: [NamedWorkspace], activeID: UUID?) {
        self.spaces = spaces
        self.activeID = activeID
        if let editingID, !spaces.contains(where: { $0.id == editingID }) { finishEditing(commit: false) }
        if let iconTarget, !spaces.contains(where: { $0.id == iconTarget }) { self.iconTarget = nil }
        if let focusedID, !spaces.contains(where: { $0.id == focusedID }) { self.focusedID = activeID }
        // Retain rows and fields during notifications from activation and live theme switching.
        let ids = Set(spaces.map(\.id))
        for id in Array(rows.keys) where !ids.contains(id) { rows.removeValue(forKey: id)?.removeFromSuperview() }
        for space in spaces {
            let row = rows[space.id] ?? makeRow(id: space.id)
            rows[space.id] = row
            row.nameButton.title = space.name
            row.nameButton.toolTip = space.name + "\n" + L10n.text("Double-click to rename. Delete to remove.", "双击改名，Delete 删除。")
            row.nameButton.setAccessibilityLabel(space.name)
            row.nameButton.setAccessibilityValue(space.id == activeID ? L10n.text("Current Space", "当前空间") : nil)
            row.iconButton.image = space.icon.flatMap { NSImage(systemSymbolName: $0.rawValue, accessibilityDescription: nil) }
            row.iconButton.title = space.icon == nil ? String(space.name.prefix(1)).uppercased() : ""
            row.iconButton.imagePosition = space.icon == nil ? .noImage : .imageOnly
            row.iconButton.toolTip = L10n.text("Choose icon", "选择图标")
            row.iconButton.setAccessibilityLabel(L10n.text("Icon for \(space.name)", "\(space.name)的图标"))
            row.isActive = space.id == activeID
            row.isFocused = space.id == focusedID
            row.refreshTheme()
        }
        layoutSurface()
    }

    private func makeRow(id: UUID?) -> SpacePickerRow {
        let row = SpacePickerRow(frame: .zero)
        let identity = NSUserInterfaceItemIdentifier(id?.uuidString ?? "newSpace")
        row.nameButton.identifier = identity
        row.nameButton.target = self
        row.nameButton.action = #selector(activateRow(_:))
        row.nameButton.onDoubleClick = { [weak self] in if let id { self?.beginRenaming(id) } }
        row.iconButton.identifier = identity
        row.iconButton.target = self
        row.iconButton.action = #selector(chooseRowIcon(_:))
        row.field.delegate = self
        list.addSubview(row)
        return row
    }

    func show(relativeTo anchor: NSView, above: Bool = false) {
        guard let parent = anchor.window else { return }
        if let previous = panel.parent, previous !== parent { previous.removeChildWindow(panel) }
        self.anchor = anchor
        anchorIsAbove = above
        focusedID = activeID
        refreshTheme(appearance: anchor.effectiveAppearance)
        layoutSurface()
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                let shouldPass = MainActor.assumeIsolated { self?.handleEvent(event) != nil }
                return shouldPass ? event : nil
            }
        }
    }

    func dismiss(commit: Bool = true) {
        guard !isDismissing else { return }
        isDismissing = true
        finishEditing(commit: commit)
        iconTarget = nil
        choosingDraftIcon = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        let parent = panel.parent
        let wasKey = panel.isKeyWindow
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // A child panel must give focus back to the reader when dismissed by Escape.
        if wasKey { parent?.makeKey() }
        isDismissing = false
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.window === panel, activeNameField == nil {
            if handleKey(event) { return nil }
        } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if event.window !== panel {
                let clickedAnchor = anchor.map { view in
                    event.window === view.window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                } ?? false
                dismiss()
                if clickedAnchor { return nil }
            }
        }
        return event
    }

    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if iconTarget != nil || choosingDraftIcon {
            let count = SpaceIcon.allCases.count + 1
            switch event.keyCode {
            case 53:
                iconTarget = nil
                choosingDraftIcon = false
                layoutSurface()
            case 123, 124, 125, 126:
                let offset = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? 6 : -6
                focusedIconIndex = (focusedIconIndex + offset + count) % count
                refreshTheme(appearance: panel.effectiveAppearance)
            case 36, 76, 49:
                selectIcon(focusedIconIndex == 0 ? nil : SpaceIcon.allCases[focusedIconIndex - 1])
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case 53:
            if activeNameField != nil { finishEditing(commit: false) }
            else if iconTarget != nil || choosingDraftIcon { iconTarget = nil; choosingDraftIcon = false; layoutSurface() }
            else { dismiss() }
        case 125, 126:
            guard !spaces.isEmpty else { return true }
            let index = spaces.firstIndex { $0.id == focusedID } ?? 0
            focusedID = spaces[(index + (event.keyCode == 125 ? 1 : spaces.count - 1)) % spaces.count].id
            update(spaces: spaces, activeID: activeID)
            if let focusedID, let row = rows[focusedID] { row.scrollToVisible(row.bounds) }
        case 36, 76, 49:
            if let focusedID { onActivate?(focusedID) }
        case 51, 117:
            if spaces.count > 1, let focusedID { onDelete?(focusedID) }
        case 120:
            if let focusedID { beginRenaming(focusedID) }
        default: return false
        }
        return true
    }

    func beginCreating() {
        guard finishEditing(commit: true) else { return }
        isCreating = true
        draftIcon = nil
        iconTarget = nil
        let row = makeRow(id: nil)
        draftRow = row
        row.iconButton.title = "+"
        row.iconButton.toolTip = L10n.text("Choose icon", "选择图标")
        row.iconButton.setAccessibilityLabel(row.iconButton.toolTip)
        var number = spaces.count + 1
        while spaces.contains(where: { $0.name == L10n.text("Space \(number)", "空间 \(number)") }) { number += 1 }
        startEditing(row, name: L10n.text("Space \(number)", "空间 \(number)"))
    }

    func beginRenaming(_ id: UUID) {
        guard editingID != id, finishEditing(commit: true), let row = rows[id],
              let space = spaces.first(where: { $0.id == id }) else { return }
        editingID = id
        iconTarget = nil
        startEditing(row, name: space.name)
    }

    private func startEditing(_ row: SpacePickerRow, name: String) {
        row.isEditing = true
        row.nameButton.isHidden = true
        row.field.stringValue = name
        row.field.isHidden = false
        layoutSurface()
        row.layoutSubtreeIfNeeded()
        row.scrollToVisible(row.bounds)
        panel.makeKey()
        row.field.selectText(nil)
        row.refreshTheme()
    }

    @discardableResult
    func finishEditing(commit: Bool) -> Bool {
        guard !isFinishing, let row = editingRow else { return true }
        let id = editingID
        let creating = isCreating
        let icon = draftIcon
        let name = row.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit, name.isEmpty, !isDismissing {
            row.field.toolTip = L10n.text("Enter a space name", "请输入空间名称")
            row.field.setAccessibilityLabel(row.field.toolTip)
            return false
        }
        isFinishing = true
        editingID = nil
        isCreating = false
        choosingDraftIcon = false
        // End the field editor before a store notification can remove its host row.
        panel.makeFirstResponder(nil)
        row.isEditing = false
        row.field.isHidden = true
        row.nameButton.isHidden = false
        row.field.toolTip = nil
        row.field.setAccessibilityLabel(L10n.text("Space name", "空间名称"))
        if creating { draftRow?.removeFromSuperview(); draftRow = nil }
        isFinishing = false
        if commit, !name.isEmpty {
            if creating { onCreate?(name, icon) } else if let id { onRename?(id, name) }
        }
        layoutSurface()
        return true
    }

    func showIcons(for id: UUID) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        iconTarget = iconTarget == id ? nil : id
        choosingDraftIcon = false
        focusedIconIndex = spaces.first { $0.id == id }?.icon.flatMap { SpaceIcon.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        layoutSurface()
    }

    func selectIcon(_ icon: SpaceIcon?) {
        if choosingDraftIcon {
            draftIcon = icon
            draftRow?.iconButton.title = icon == nil ? "+" : ""
            draftRow?.iconButton.image = icon.flatMap { NSImage(systemSymbolName: $0.rawValue, accessibilityDescription: nil) }
            draftRow?.iconButton.imagePosition = icon == nil ? .noImage : .imageOnly
            choosingDraftIcon = false
        } else if let id = iconTarget {
            iconTarget = nil
            onIcon?(id, icon)
        }
        layoutSurface()
        if let row = editingRow { panel.makeFirstResponder(row.field); row.refreshTheme() }
    }

    @objc private func createSpace() { beginCreating() }
    @objc private func activateRow(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let id = UUID(uuidString: value), finishEditing(commit: true) else { return }
        focusedID = id
        onActivate?(id)
    }
    @objc private func chooseRowIcon(_ sender: NSButton) {
        if sender.identifier?.rawValue == "newSpace" {
            choosingDraftIcon.toggle()
            iconTarget = nil
            focusedIconIndex = draftIcon.flatMap { SpaceIcon.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            layoutSurface()
        } else if let value = sender.identifier?.rawValue, let id = UUID(uuidString: value) { showIcons(for: id) }
    }
    @objc private func chooseSymbol(_ sender: NSButton) {
        selectIcon(sender.tag == 0 ? nil : SpaceIcon.allCases[sender.tag - 1])
    }

    private func layoutSurface() {
        let rowWidth = Self.width - 12
        for (index, space) in spaces.enumerated() {
            rows[space.id]?.frame = NSRect(x: 0, y: CGFloat(index) * 28, width: rowWidth, height: 28)
        }
        draftRow?.frame = NSRect(x: 0, y: CGFloat(spaces.count) * 28, width: rowWidth, height: 28)
        let listHeight = CGFloat(spaces.count + (isCreating ? 1 : 0)) * 28
        let visibleHeight = min(280, listHeight)
        scroll.frame = NSRect(x: 6, y: 6, width: rowWidth, height: visibleHeight)
        list.frame = NSRect(x: 0, y: 0, width: rowWidth, height: listHeight)
        divider.frame = NSRect(x: 12, y: visibleHeight + 11, width: Self.width - 24, height: 0.5)
        newButton.frame = NSRect(x: 13, y: visibleHeight + 16, width: Self.width - 26, height: 26)
        newButton.isEnabled = !isCreating
        let showGrid = iconTarget != nil || choosingDraftIcon
        iconGrid.isHidden = !showGrid
        var height = visibleHeight + 48
        if showGrid {
            rebuildIconChoices()
            iconGrid.frame = NSRect(x: 10, y: height, width: Self.width - 20, height: 100)
            height += 104
        }
        surface.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        if let anchor, let parent = anchor.window {
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = parent.screen?.visibleFrame ?? rect
            var origin = NSPoint(x: rect.minX, y: anchorIsAbove ? rect.maxY + 5 : rect.minY - height - 5)
            if origin.y < screen.minY { origin.y = rect.maxY + 5 }
            if origin.y + height > screen.maxY { origin.y = rect.minY - height - 5 }
            origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - Self.width - 6)
            origin.y = max(screen.minY + 6, min(origin.y, screen.maxY - height - 6))
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: isVisible)
        }
        rows.values.forEach { $0.needsLayout = true }
        draftRow?.needsLayout = true
        refreshTheme(appearance: panel.effectiveAppearance)
    }

    private func rebuildIconChoices() {
        iconChoices.forEach { $0.removeFromSuperview() }
        let selected = choosingDraftIcon ? draftIcon : spaces.first { $0.id == iconTarget }?.icon
        iconChoices = (0...SpaceIcon.allCases.count).map { index in
            let icon = index == 0 ? nil : SpaceIcon.allCases[index - 1]
            let button = SpaceButton(title: "", target: self, action: #selector(chooseSymbol(_:)))
            button.tag = index
            button.isBordered = false
            button.focusRingType = .none
            button.image = NSImage(systemSymbolName: icon?.rawValue ?? "textformat.abc", accessibilityDescription: nil)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.toolTip = icon?.label ?? L10n.text("Use initial", "使用首字")
            button.setAccessibilityLabel(button.toolTip)
            button.setAccessibilityValue(icon == selected ? L10n.text("Selected", "已选中") : nil)
            button.wantsLayer = true
            button.layer?.cornerRadius = 4
            button.frame = NSRect(x: CGFloat(index % 6) * 29, y: CGFloat(index / 6) * 30 + 4, width: 28, height: 28)
            iconGrid.addSubview(button)
            return button
        }
    }

    func refreshTheme(appearance: NSAppearance) {
        panel.appearance = appearance
        appearance.performAsCurrentDrawingAppearance {
            surface.layer?.backgroundColor = NightModeStyle.readerBackdropColor.cgColor
            surface.layer?.borderColor = NightModeStyle.tertiaryTextColor.withAlphaComponent(0.25).cgColor
            divider.layer?.backgroundColor = NightModeStyle.tertiaryTextColor.withAlphaComponent(0.2).cgColor
            newButton.contentTintColor = NightModeStyle.secondaryTextColor
            newButton.attributedTitle = NSAttributedString(string: newButton.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: isCreating ? NightModeStyle.tertiaryTextColor : NightModeStyle.secondaryTextColor,
            ])
            for button in iconChoices {
                button.contentTintColor = NightModeStyle.secondaryTextColor
                button.layer?.backgroundColor = button.tag == focusedIconIndex
                    ? SplitViewController.selectedChromeBackgroundColor.withAlphaComponent(0.4).cgColor : NSColor.clear.cgColor
            }
        }
        rows.values.forEach { $0.refreshTheme() }
        draftRow?.refreshTheme()
    }

    func controlTextDidBeginEditing(_ notification: Notification) { editingRow?.refreshTheme() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if !finishEditing(commit: true) { NSSound.beep() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishEditing(commit: false)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            return finishEditing(commit: true)
        default: return false
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        // Context menus keep the panel key; switching apps/windows ends the interaction.
        if !isDismissing, panel.isVisible { dismiss() }
    }
    @objc private func applicationDidDeactivate() { dismiss() }
    @objc private func parentWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel.parent { dismiss(commit: false) }
    }
}

#if DEBUG
extension SpacePickerController {
    var testingPanel: NSPanel { panel }
    var testingNameButtons: [NSButton] { spaces.compactMap { rows[$0.id]?.nameButton } }
    var testingIconButtons: [NSButton] { spaces.compactMap { rows[$0.id]?.iconButton } }
    var testingIconChoices: [NSButton] { iconChoices }
    var testingDraftIconButton: NSButton? { draftRow?.iconButton }
    var testingNewButton: NSButton { newButton }
}
#endif
