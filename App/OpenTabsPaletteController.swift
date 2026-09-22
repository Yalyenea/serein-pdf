import AppKit

final class CompactPalettePanel: NSPanel {
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { onFlagsChanged?(event) }
        if event.type == .keyDown, onKeyEvent?(event) == true { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyEvent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

final class CompactPaletteRowView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 10)
        trailingLabel.font = .systemFont(ofSize: 10)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.lineBreakMode = .byTruncatingMiddle
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for label in [titleLabel, detailLabel, trailingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -12),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailingLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, detail: String, trailing: String = "", isActive: Bool = false, tooltip: String? = nil) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        trailingLabel.stringValue = trailing
        titleLabel.textColor = isActive ? NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance) : NightModeStyle.primaryTextColor
        detailLabel.textColor = NightModeStyle.secondaryTextColor
        trailingLabel.textColor = NightModeStyle.tertiaryTextColor
        toolTip = tooltip
    }
}

@MainActor
final class OpenTabsPaletteController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let panelWidth: CGFloat = 620
    private static let rowHeight: CGFloat = 44
    private let onActivateSession: (UUID, ReaderSplitLayout?) -> Void
    private var state = OpenTabsPaletteState(sessions: [], activeSessionID: nil)
    private var activationMode: OpenTabsPaletteActivationMode = .explicitSelection
    private var isApplyingSelection = false
    private weak var parentWindow: NSWindow?
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "Open Tabs")
    private let footerLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No open PDFs.")
    private var rightSplitShortcut: KeyboardShortcut? = KeyboardShortcut(key: "return", modifiers: [.option])
    private var downSplitShortcut: KeyboardShortcut? = KeyboardShortcut(key: "return", modifiers: [.option, .shift])

    init(onActivateSession: @escaping (UUID, ReaderSplitLayout?) -> Void) {
        self.onActivateSession = onActivateSession
        let panel = CompactPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 160),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        panel.title = "Open Tabs"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        super.init(window: panel)
        panel.delegate = self
        panel.onKeyEvent = { [weak self] in self?.handlePaletteKeyEvent($0) ?? false }
        panel.onFlagsChanged = { [weak self] in self?.handleFlagsChanged($0) }
        buildInterface(in: panel)
        refreshChromeColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureSplitShortcuts(right: KeyboardShortcut?, down: KeyboardShortcut?) {
        rightSplitShortcut = right
        downSplitShortcut = down
    }

    func show(
        with sessions: [DocumentSession], activeSessionID: UUID?, primarySessionID: UUID?,
        secondarySessionID: UUID?, focusedPane: ReaderPane, relativeTo parentWindow: NSWindow?,
        activationMode: OpenTabsPaletteActivationMode = .explicitSelection
    ) {
        show(items: sessions.map {
            OpenTabsPaletteItem(session: $0, isActive: $0.id == activeSessionID,
                                primarySessionID: primarySessionID, secondarySessionID: secondarySessionID,
                                focusedPane: focusedPane)
        }, activationMode: activationMode, relativeTo: parentWindow)
    }

    func show(items: [OpenTabsPaletteItem], activationMode: OpenTabsPaletteActivationMode, relativeTo parentWindow: NSWindow?) {
        self.parentWindow = parentWindow
        self.activationMode = activationMode
        state.replaceItems(items, activationMode: activationMode)
        footerLabel.stringValue = activationMode == .explicitSelection
            ? "↑ ↓  Select    ↩  Open    Esc  Cancel"
            : "Tab / ↑ ↓  Select    Release Control to open    Esc  Cancel"
        reloadUI()
        refreshChromeColors()
        guard let window else { return }
        let height = CGFloat(max(1, min(items.count, 12))) * Self.rowHeight + 72
        let frame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        window.setContentSize(NSSize(width: Self.panelWidth, height: min(height, frame.height - 32)))
        window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tableView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func advance(reverse: Bool) {
        guard window?.isVisible == true else { return }
        state.moveHighlight(delta: reverse ? -1 : 1)
        applySelection()
    }

    override func close() {
        activationMode = .explicitSelection
        super.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        if case .heldControl = activationMode { close() }
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = NightModeStyle.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = NightModeStyle.splitBackgroundColor.cgColor
            titleLabel.textColor = NightModeStyle.secondaryTextColor
            footerLabel.textColor = NightModeStyle.tertiaryTextColor
            emptyLabel.textColor = NightModeStyle.secondaryTextColor
            reloadUI()
        }
    }

    private func buildInterface(in panel: NSPanel) {
        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        footerLabel.font = .systemFont(ofSize: 10)
        emptyLabel.font = .systemFont(ofSize: 12)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tab"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(openClickedItem)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        for view in [titleLabel, footerLabel, emptyLabel, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -8),
            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func reloadUI() {
        isApplyingSelection = true
        tableView.reloadData()
        emptyLabel.isHidden = !state.items.isEmpty
        scrollView.isHidden = state.items.isEmpty
        applySelection()
        isApplyingSelection = false
    }

    private func applySelection() {
        isApplyingSelection = true
        if let index = state.highlightedIndex {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else { tableView.deselectAll(nil) }
        isApplyingSelection = false
    }

    private func activateHighlightedAndClose(splitLayout: ReaderSplitLayout? = nil) {
        guard let sessionID = state.highlightedItem?.sessionID else { return }
        close()
        onActivateSession(sessionID, splitLayout)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard window?.isVisible == true, case .heldControl = activationMode,
              !event.modifierFlags.contains(.control) else { return }
        activateHighlightedAndClose()
    }

    private func handlePaletteKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 { close(); return true }
        if rightSplitShortcut?.matches(event: event) == true {
            activateHighlightedAndClose(splitLayout: .sideBySide); return true
        }
        if downSplitShortcut?.matches(event: event) == true {
            activateHighlightedAndClose(splitLayout: .stacked); return true
        }
        if event.keyCode == 48, modifiers.contains(.control), modifiers.isDisjoint(with: [.command, .option]) {
            advance(reverse: modifiers.contains(.shift)); return true
        }
        guard modifiers.isDisjoint(with: [.command, .option]) else { return false }
        switch Int(event.keyCode) {
        case 123, 126: advance(reverse: true); return true
        case 124, 125: advance(reverse: false); return true
        case 36, 76: activateHighlightedAndClose(); return true
        default: break
        }
        guard modifiers.isEmpty else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h", "k": advance(reverse: true); return true
        case "j", "l": advance(reverse: false); return true
        default: return false
        }
    }

    @objc private func openClickedItem() {
        guard tableView.clickedRow >= 0 else { return }
        state.setHighlightedIndex(tableView.clickedRow)
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        activateHighlightedAndClose(splitLayout: modifiers.contains(.option) ? (modifiers.contains(.shift) ? .stacked : .sideBySide) : nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { state.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = state.items[row]
        let view = CompactPaletteRowView()
        let detail = [item.workspaceName, item.subtitle].compactMap { $0 }.joined(separator: "  ·  ")
        view.configure(title: item.isDirty ? "\(item.title) •" : item.title,
                       detail: detail, trailing: item.pageText, isActive: item.isActive, tooltip: item.subtitle)
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let row = ThemedTableRowView()
        row.selectionCornerRadius = 4
        return row
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        state.setHighlightedIndex(tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
    }
}

#if DEBUG
extension OpenTabsPaletteController {
    var testingHighlightedIndex: Int? { state.highlightedIndex }
    var testingTableIsFirstResponder: Bool { window?.firstResponder === tableView }
    var testingSelectedItemCount: Int { tableView.selectedRowIndexes.count }
    var testingWindowIsVisible: Bool { window?.isVisible == true }
    var testingItems: [OpenTabsPaletteItem] { state.items }
    func testingHandlePaletteKeyEvent(_ event: NSEvent) -> Bool { handlePaletteKeyEvent(event) }
    func testingHandleFlagsChanged(_ event: NSEvent) { handleFlagsChanged(event) }
    func testingClickItem(at index: Int) {
        state.setHighlightedIndex(index)
        activateHighlightedAndClose()
    }
}
#endif
