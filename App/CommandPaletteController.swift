import AppKit

private final class CommandPalettePanel: NSPanel {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyEvent?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class CommandPaletteTableView: NSTableView {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class CommandPaletteRowView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let sectionLabel = NSTextField(labelWithString: "")
    private let shortcutsView = ShortcutSequenceView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.font = .systemFont(ofSize: 10)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.lineBreakMode = .byTruncatingTail

        addSubview(titleLabel)
        addSubview(sectionLabel)
        addSubview(shortcutsView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutsView.leadingAnchor, constant: -12),

            sectionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutsView.leadingAnchor, constant: -12),
            sectionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            sectionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),

            shortcutsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutsView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: CommandPaletteItem) {
        titleLabel.stringValue = item.title
        sectionLabel.stringValue = item.section.title
        shortcutsView.configure(sequences: item.shortcutSequences)
    }
}

@MainActor
final class CommandPaletteController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static let panelSize = NSSize(width: 580, height: 500)

    private let onInvokeCommand: (ShortcutCommand, UUID?) -> Void
    private let onVisibilityChange: ((Bool) -> Void)?
    private var state = CommandPaletteState()
    private var isApplyingSelection = false
    private var isInvokingCommand = false
    private var keyEventMonitor: Any?
    private weak var parentWindow: NSWindow?
    private var targetWindowID: UUID?

    private let queryField = NSSearchField(frame: .zero)
    private let resultCountLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No commands match.")
    private let footerLabel = NSTextField(
        labelWithString: "↑ ↓ Select    ↵ Run    ⌘K Close    ⌘K chords work while this panel is open"
    )
    private let scrollView = NSScrollView()
    private let tableView = CommandPaletteTableView()

    init(
        onInvokeCommand: @escaping (ShortcutCommand, UUID?) -> Void,
        onVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.onInvokeCommand = onInvokeCommand
        self.onVisibilityChange = onVisibilityChange

        let panel = CommandPalettePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Command Palette"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = SplitViewController.splitBackgroundColor
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        panel.delegate = self
        panel.onKeyEvent = { [weak self] event in
            self?.handlePanelKeyEvent(event) ?? false
        }
        buildInterface(in: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        commands: [ShortcutCommand],
        bindings: [ShortcutCommand: KeyboardShortcut],
        titles: [ShortcutCommand: String] = [:],
        targetWindowID: UUID?,
        relativeTo parentWindow: NSWindow?
    ) {
        self.parentWindow = parentWindow
        self.targetWindowID = targetWindowID
        state.query = ""
        state.replaceCommands(commands, bindings: bindings, titles: titles)
        queryField.stringValue = ""
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        refreshChromeColors()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(queryField)
        startKeyEventMonitor()
        onVisibilityChange?(true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss(restoreParent: Bool = true) {
        let wasVisible = window?.isVisible == true
        stopKeyEventMonitor()
        window?.orderOut(nil)
        if wasVisible {
            onVisibilityChange?(false)
        }
        if restoreParent {
            parentWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.identifier = NSUserInterfaceItemIdentifier("commandPaletteQuery")
        let searchCell = ThemedSearchFieldCell(textCell: "")
        searchCell.cornerRadius = 8
        queryField.cell = searchCell
        queryField.delegate = self
        queryField.placeholderString = "Search commands"
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 20, weight: .semibold)
        queryField.controlSize = .large
        queryField.isBezeled = true
        queryField.bezelStyle = .squareBezel
        queryField.drawsBackground = false
        queryField.sendsSearchStringImmediately = true
        queryField.sendsWholeSearchString = false
        queryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        queryField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        resultCountLabel.translatesAutoresizingMaskIntoConstraints = false
        resultCountLabel.font = .systemFont(ofSize: 10.5)
        resultCountLabel.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("commandPaletteResults")
        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(invokeHighlightedCommand(_:))
        tableView.onKeyEvent = { [weak self] event in
            self?.handleTableKeyEvent(event) ?? false
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.alignment = .center

        contentView.addSubview(queryField)
        contentView.addSubview(resultCountLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            queryField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            queryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            queryField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            queryField.heightAnchor.constraint(equalToConstant: 34),

            resultCountLabel.leadingAnchor.constraint(equalTo: queryField.leadingAnchor, constant: 2),
            resultCountLabel.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 7),

            scrollView.leadingAnchor.constraint(equalTo: queryField.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: resultCountLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            footerLabel.leadingAnchor.constraint(equalTo: queryField.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    private func positionPanel(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }
        let targetFrame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        let visibleFrame = parentWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? targetFrame
        let desiredOrigin = NSPoint(
            x: targetFrame.midX - window.frame.width / 2,
            y: targetFrame.maxY - window.frame.height - 88
        )
        let origin = NSPoint(
            x: min(max(desiredOrigin.x, visibleFrame.minX), visibleFrame.maxX - window.frame.width),
            y: min(max(desiredOrigin.y, visibleFrame.minY), visibleFrame.maxY - window.frame.height)
        )
        window.setFrameOrigin(origin)
    }

    private func reloadUI() {
        resultCountLabel.stringValue = "\(state.filteredItems.count) commands"
        emptyLabel.isHidden = state.filteredItems.isEmpty == false
        scrollView.isHidden = state.filteredItems.isEmpty

        isApplyingSelection = true
        tableView.reloadData()
        if let highlightedIndex = state.highlightedIndex {
            tableView.selectRowIndexes(IndexSet(integer: highlightedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(highlightedIndex)
        } else {
            tableView.deselectAll(nil)
        }
        isApplyingSelection = false
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = SplitViewController.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
            let searchCell = queryField.cell as! ThemedSearchFieldCell
            searchCell.applyTheme(to: queryField, placeholder: "Search commands")
            resultCountLabel.textColor = NightModeStyle.secondaryTextColor
            emptyLabel.textColor = NightModeStyle.secondaryTextColor
            footerLabel.textColor = NightModeStyle.tertiaryTextColor
        }
    }

    private func startKeyEventMonitor() {
        stopKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            return self.handlePanelKeyEvent(event) ? nil : event
        }
    }

    private func stopKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        if ShortcutCommand.commandPaletteShortcut.matches(event: event) {
            dismiss()
            return true
        }

        if let command = ShortcutCommand.allCases.first(where: {
            $0.builtInShortcutSequence?.strokes.last?.matches(event: event) == true
        }) {
            invoke(command)
            return true
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case 53:
            dismiss()
            return true
        case 125:
            state.moveHighlight(delta: 1)
            reloadUI()
            return true
        case 126:
            state.moveHighlight(delta: -1)
            reloadUI()
            return true
        case 36, 76:
            invokeHighlightedCommand(nil)
            return true
        default:
            return false
        }
    }

    private func handleTableKeyEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let characters = event.charactersIgnoringModifiers,
              characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) == false }) else {
            return false
        }
        window?.makeFirstResponder(queryField)
        if let editor = window?.fieldEditor(true, for: queryField) as? NSTextView {
            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
            editor.keyDown(with: event)
        }
        return true
    }

    @objc
    private func invokeHighlightedCommand(_ sender: Any?) {
        guard let command = state.highlightedItem?.command else {
            NSSound.beep()
            return
        }
        invoke(command)
    }

    private func invoke(_ command: ShortcutCommand) {
        guard isInvokingCommand == false else { return }
        isInvokingCommand = true
        dismiss()
        onInvokeCommand(command, targetWindowID)
        isInvokingCommand = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window,
              window?.isVisible == true else { return }
        dismiss(restoreParent: false)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let searchField = notification.object as? NSSearchField,
              searchField === queryField else { return }
        state.query = queryField.stringValue
        reloadUI()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("CommandPaletteRow")
        let rowView = (tableView.makeView(withIdentifier: identifier, owner: self) as? CommandPaletteRowView)
            ?? {
                let view = CommandPaletteRowView()
                view.identifier = identifier
                return view
            }()
        rowView.configure(with: state.filteredItems[row])
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isApplyingSelection == false else { return }
        state.setHighlightedIndex(tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
    }
}

#if DEBUG
extension CommandPaletteController {
    var testingFilteredCommands: [ShortcutCommand] { state.filteredItems.map(\.command) }
    var testingQueryField: NSSearchField { queryField }

    func testingSetQuery(_ query: String) {
        queryField.stringValue = query
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: queryField))
    }

    func testingHandlePanelKeyEvent(_ event: NSEvent) -> Bool {
        handlePanelKeyEvent(event)
    }
}
#endif
