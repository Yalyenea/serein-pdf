import AppKit

private final class RecentFilesPaletteResultsTableView: NSTableView {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class RecentFilesPalettePanel: NSPanel {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           onKeyEvent?(event) == true {
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

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

enum RecentFilesPaletteInteractionMode {
    case editingQuery
    case navigatingResults
}

private final class RecentFilesPaletteRowView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            subtitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: RecentFilesPaletteItem, isMarked: Bool, showsFolder: Bool) {
        iconView.image = NSImage(systemSymbolName: isMarked ? "checkmark.circle.fill" : "doc", accessibilityDescription: isMarked ? "Selected PDF" : "PDF")
        iconView.contentTintColor = isMarked
            ? NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance)
            : NightModeStyle.tertiaryTextColor
        titleLabel.textColor = NightModeStyle.primaryTextColor
        subtitleLabel.textColor = NightModeStyle.secondaryTextColor
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = showsFolder ? item.url.deletingLastPathComponent().lastPathComponent : ""
        toolTip = item.url.path
    }
}

@MainActor
final class RecentFilesPaletteController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let panelWidth: CGFloat = 680
    private static let rowHeight: CGFloat = 36
    private static let maximumVisibleRows = 14

    private let queryPlaceholder: String
    private let emptyItemsMessage: String
    private let emptyQueryMessage: String
    private let onOpenURLs: ([URL]) -> Void
    private var state = RecentFilesPaletteState(recentURLs: [])
    private var isApplyingSelection = false
    private var interactionMode: RecentFilesPaletteInteractionMode = .editingQuery
    private var duplicateTitles: Set<String> = []
    private weak var parentWindow: NSWindow?
    private var escapeEventMonitor: Any?

    private let queryField = NSTextField(frame: .zero)
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = RecentFilesPaletteResultsTableView()

    init(
        title: String = "Recent Files",
        queryPlaceholder: String = "Filter recent files",
        emptyItemsMessage: String = "No recent files yet.",
        emptyQueryMessage: String = "No recent files match the current query.",
        onOpenURLs: @escaping ([URL]) -> Void
    ) {
        self.queryPlaceholder = queryPlaceholder
        self.emptyItemsMessage = emptyItemsMessage
        self.emptyQueryMessage = emptyQueryMessage
        self.onOpenURLs = onOpenURLs

        let panel = RecentFilesPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = SplitViewController.splitBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        panel.delegate = self
        panel.onKeyEvent = { [weak self] event in
            self?.handlePanelKeyEvent(event) ?? false
        }
        buildInterface(in: panel)
        reloadUI()
        refreshChromeColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(with recentURLs: [URL], relativeTo parentWindow: NSWindow?) {
        self.parentWindow = parentWindow
        state.replaceRecentURLs(recentURLs)
        duplicateTitles = Set(Dictionary(grouping: state.allItems, by: \.title)
            .filter { $0.value.count > 1 }.keys)
        interactionMode = .editingQuery
        queryField.stringValue = ""
        reloadUI()
        refreshChromeColors()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        focusQueryField()
        startEscapeEventMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        stopEscapeEventMonitor()
        super.close()
    }

    func windowWillClose(_ notification: Notification) {
        stopEscapeEventMonitor()
    }

    private func startEscapeEventMonitor() {
        stopEscapeEventMonitor()
        escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true,
                  event.keyCode == 53,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            self.close()
            return nil
        }
    }

    private func stopEscapeEventMonitor() {
        if let escapeEventMonitor {
            NSEvent.removeMonitor(escapeEventMonitor)
            self.escapeEventMonitor = nil
        }
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = NightModeStyle.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = NightModeStyle.splitBackgroundColor.cgColor
            queryField.textColor = NightModeStyle.primaryTextColor
            queryField.placeholderAttributedString = NSAttributedString(
                string: queryPlaceholder,
                attributes: [.foregroundColor: NightModeStyle.tertiaryTextColor]
            )
            emptyLabel.textColor = NightModeStyle.secondaryTextColor
            if let editor = queryField.currentEditor() as? NSTextView {
                editor.textColor = NightModeStyle.primaryTextColor
                editor.insertionPointColor = NightModeStyle.primaryTextColor
            }
            for row in 0..<tableView.numberOfRows {
                if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? RecentFilesPaletteRowView {
                    let item = state.filteredItems[row]
                    cell.configure(item: item, isMarked: state.isSelected(item.url), showsFolder: duplicateTitles.contains(item.title))
                }
                tableView.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
            }
        }
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.delegate = self
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 17)
        queryField.placeholderString = queryPlaceholder
        queryField.textColor = .labelColor
        queryField.lineBreakMode = .byTruncatingTail
        queryField.maximumNumberOfLines = 1

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent-file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(openClickedItem(_:))
        tableView.onKeyEvent = { [weak self] event in
            self?.handleResultsKeyEvent(event) ?? false
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        contentView.addSubview(queryField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            queryField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            queryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            queryField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            queryField.heightAnchor.constraint(equalToConstant: 28),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),
        ])
    }

    private func positionPanel(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }
        let targetFrame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        let origin = NSPoint(
            x: targetFrame.midX - window.frame.width / 2,
            y: targetFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func reloadUI() {
        isApplyingSelection = true
        tableView.reloadData()

        if state.filteredItems.isEmpty {
            emptyLabel.stringValue = state.allItems.isEmpty ? emptyItemsMessage : emptyQueryMessage
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyLabel.isHidden = true
            scrollView.isHidden = false
        }

        resizePanelToFitResults()
        applyHighlightedSelection()
        isApplyingSelection = false
    }

    private func resizePanelToFitResults() {
        guard let window else { return }
        let visibleRows = min(state.filteredItems.count, Self.maximumVisibleRows)
        let listHeight = visibleRows == 0 ? 44 : CGFloat(visibleRows) * Self.rowHeight
        let availableHeight = (parentWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 600
        let height = min(64 + listHeight, availableHeight - 40)
        guard window.contentView?.frame.height != height else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: Self.panelWidth, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
    }

    private func focusQueryField() {
        interactionMode = .editingQuery
        window?.makeFirstResponder(queryField)
        if let editor = window?.fieldEditor(true, for: queryField) as? NSTextView {
            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
        }
    }

    private func focusResults() {
        guard state.filteredItems.isEmpty == false else { return }
        interactionMode = .navigatingResults
        window?.makeFirstResponder(tableView)
    }

    private func applyHighlightedSelection() {
        if let highlightedIndex = state.highlightedIndex {
            tableView.selectRowIndexes(IndexSet(integer: highlightedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(highlightedIndex)
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func openTargetsAndClose() {
        let urls = state.openTargets()
        guard urls.isEmpty == false else {
            NSSound.beep()
            return
        }
        close()
        onOpenURLs(urls)
    }

    @objc
    private func openClickedItem(_ sender: Any?) {
        guard tableView.clickedRow >= 0,
              state.filteredItems.indices.contains(tableView.clickedRow) else { return }
        let url = state.filteredItems[tableView.clickedRow].url
        close()
        onOpenURLs([url])
    }

    private func handleResultsKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 53:
            close()
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
            openTargetsAndClose()
            return true
        case 49:
            state.toggleSelectionForHighlightedItem()
            reloadUI()
            return true
        default:
            break
        }

        guard shouldReturnToQueryField(for: event) else { return false }
        forwardEventToQueryField(event)
        return true
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 53:
            close()
            return true
        case 36, 76:
            openTargetsAndClose()
            return true
        default:
            return false
        }
    }

    private func shouldReturnToQueryField(for event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 51, 117:
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers, characters.isEmpty == false else {
            return false
        }
        return characters.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) == false }
    }

    private func forwardEventToQueryField(_ event: NSEvent) {
        focusQueryField()
        if let editor = window?.firstResponder as? NSTextView {
            editor.keyDown(with: event)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        interactionMode = .editingQuery
        state.query = queryField.stringValue
        reloadUI()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === queryField else { return false }

        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)),
             #selector(NSResponder.moveUp(_:)):
            guard state.filteredItems.isEmpty == false else { return false }
            focusResults()
            reloadUI()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openTargetsAndClose()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("RecentFilesPaletteRowView")
        let item = state.filteredItems[row]
        let rowView = (tableView.makeView(withIdentifier: identifier, owner: self) as? RecentFilesPaletteRowView)
            ?? {
                let view = RecentFilesPaletteRowView()
                view.identifier = identifier
                return view
            }()
        rowView.configure(item: item, isMarked: state.isSelected(item.url), showsFolder: duplicateTitles.contains(item.title))
        return rowView
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ThemedTableRowView()
        view.selectionCornerRadius = 5
        view.selectionInsets = NSSize(width: 4, height: 2)
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isApplyingSelection == false else { return }
        interactionMode = .navigatingResults
        state.setHighlightedIndex(tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
    }
}

#if DEBUG
extension RecentFilesPaletteController {
    var testingInteractionMode: RecentFilesPaletteInteractionMode { interactionMode }
    var testingHighlightedIndex: Int? { state.highlightedIndex }
    var testingSelectedURLs: [URL] { state.selectedURLs }
    var testingQuery: String { queryField.stringValue }
    var testingQueryFieldIsFirstResponder: Bool {
        guard let window else { return false }
        if window.firstResponder === queryField { return true }
        if let editor = window.fieldEditor(false, for: queryField),
           window.firstResponder === editor {
            return true
        }
        return false
    }
    var testingResultsTableIsFirstResponder: Bool {
        window?.firstResponder === tableView
    }

    func testingSetQuery(_ query: String) {
        queryField.stringValue = query
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: queryField))
    }

    func testingHandleQueryCommand(_ commandSelector: Selector) -> Bool {
        control(queryField, textView: window?.firstResponder as? NSTextView ?? NSTextView(), doCommandBy: commandSelector)
    }

    func testingHandleResultsKeyEvent(_ event: NSEvent) -> Bool {
        handleResultsKeyEvent(event)
    }

    func testingHandlePanelKeyEvent(_ event: NSEvent) -> Bool {
        handlePanelKeyEvent(event)
    }
}
#endif
