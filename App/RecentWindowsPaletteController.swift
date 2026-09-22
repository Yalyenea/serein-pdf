import AppKit

struct RecentWindowsPaletteItem: Equatable, Sendable {
    let windowID: UUID
    let title: String
    let documentSummary: String
    var canSplit: Bool = true
}

@MainActor
final class RecentWindowsPaletteController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let onActivateWindow: (UUID) -> Void
    private let onSplitWindow: (UUID, ReaderSplitLayout) -> Void
    private var items: [RecentWindowsPaletteItem] = []
    private var filteredItems: [RecentWindowsPaletteItem] = []
    private var highlightedIndex: Int?
    private var isApplyingSelection = false
    private weak var parentWindow: NSWindow?
    private let queryField = NSTextField(frame: .zero)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No recent windows.")
    private let footerLabel = NSTextField(labelWithString: "")
    private var rightSplitShortcut: KeyboardShortcut? = KeyboardShortcut(key: "return", modifiers: [.option])
    private var downSplitShortcut: KeyboardShortcut? = KeyboardShortcut(key: "return", modifiers: [.option, .shift])

    init(onActivateWindow: @escaping (UUID) -> Void, onSplitWindow: @escaping (UUID, ReaderSplitLayout) -> Void) {
        self.onActivateWindow = onActivateWindow
        self.onSplitWindow = onSplitWindow
        let panel = CompactPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 160),
                                        styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Recent Windows"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        super.init(window: panel)
        panel.onKeyEvent = { [weak self] in self?.handleKeyEvent($0) ?? false }
        buildInterface(in: panel)
        refreshChromeColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureSplitShortcuts(right: KeyboardShortcut?, down: KeyboardShortcut?) {
        rightSplitShortcut = right
        downSplitShortcut = down
        updateFooter()
    }

    func show(with items: [RecentWindowsPaletteItem], relativeTo parentWindow: NSWindow?) {
        self.items = items
        self.parentWindow = parentWindow
        queryField.stringValue = ""
        filterItems()
        refreshChromeColors()
        guard let window else { return }
        let frame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(queryField)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = NightModeStyle.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = NightModeStyle.splitBackgroundColor.cgColor
            queryField.textColor = NightModeStyle.primaryTextColor
            queryField.placeholderAttributedString = NSAttributedString(
                string: "Filter recent windows", attributes: [.foregroundColor: NightModeStyle.tertiaryTextColor]
            )
            emptyLabel.textColor = NightModeStyle.secondaryTextColor
            footerLabel.textColor = NightModeStyle.tertiaryTextColor
            isApplyingSelection = true
            tableView.reloadData()
            isApplyingSelection = false
            applySelection()
        }
    }

    private func buildInterface(in panel: NSPanel) {
        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content
        queryField.font = .systemFont(ofSize: 17)
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.delegate = self
        footerLabel.font = .systemFont(ofSize: 10)
        emptyLabel.font = .systemFont(ofSize: 12)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(activateClickedItem)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        for view in [queryField, scrollView, emptyLabel, footerLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            queryField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            queryField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            queryField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            queryField.heightAnchor.constraint(equalToConstant: 28),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -8),
            footerLabel.leadingAnchor.constraint(equalTo: queryField.leadingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private var highlightedItem: RecentWindowsPaletteItem? {
        guard let highlightedIndex, filteredItems.indices.contains(highlightedIndex) else { return nil }
        return filteredItems[highlightedIndex]
    }

    private func filterItems() {
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = items.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.documentSummary.localizedStandardContains(query) }
        highlightedIndex = filteredItems.isEmpty ? nil : 0
        isApplyingSelection = true
        tableView.reloadData()
        isApplyingSelection = false
        emptyLabel.stringValue = items.isEmpty ? "No recent windows." : "No windows match the current query."
        emptyLabel.isHidden = !filteredItems.isEmpty
        scrollView.isHidden = filteredItems.isEmpty
        let screenHeight = (parentWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 600
        window?.setContentSize(NSSize(width: 620, height: min(86 + CGFloat(max(1, min(filteredItems.count, 12))) * 44, screenHeight - 40)))
        applySelection()
    }

    private func applySelection() {
        isApplyingSelection = true
        if let highlightedIndex {
            tableView.selectRowIndexes(IndexSet(integer: highlightedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(highlightedIndex)
        } else { tableView.deselectAll(nil) }
        isApplyingSelection = false
        updateFooter()
    }

    private func updateFooter() {
        footerLabel.stringValue = highlightedItem?.canSplit == true
            ? "↩  Switch window    \(rightSplitShortcut?.displayString ?? "—")  Split right    \(downSplitShortcut?.displayString ?? "—")  Split below"
            : "↩  Switch window · This window has no PDF to open in a split"
    }

    private func activate(splitLayout: ReaderSplitLayout? = nil) {
        guard let item = highlightedItem else { return }
        if let splitLayout {
            guard item.canSplit else { updateFooter(); return }
            close()
            onSplitWindow(item.windowID, splitLayout)
        } else {
            close()
            onActivateWindow(item.windowID)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard (window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        if rightSplitShortcut?.matches(event: event) == true { activate(splitLayout: .sideBySide); return true }
        if downSplitShortcut?.matches(event: event) == true { activate(splitLayout: .stacked); return true }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53: close(); return true
        case 36, 76: activate(); return true
        case 125, 126:
            guard !filteredItems.isEmpty else { return true }
            let delta = event.keyCode == 125 ? 1 : -1
            highlightedIndex = ((highlightedIndex ?? 0) + delta + filteredItems.count) % filteredItems.count
            applySelection()
            return true
        default: return false
        }
    }

    @objc private func activateClickedItem() {
        guard tableView.clickedRow >= 0 else { return }
        highlightedIndex = tableView.clickedRow
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        activate(splitLayout: flags.contains(.option) ? (flags.contains(.shift) ? .stacked : .sideBySide) : nil)
    }

    func controlTextDidChange(_ notification: Notification) { filterItems() }
    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredItems[row]
        let view = CompactPaletteRowView()
        view.configure(title: item.title, detail: item.documentSummary, tooltip: item.documentSummary)
        return view
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ThemedTableRowView()
        view.selectionCornerRadius = 4
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        highlightedIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        updateFooter()
    }
}

#if DEBUG
extension RecentWindowsPaletteController {
    var testingHighlightedWindowID: UUID? { highlightedItem?.windowID }
    var testingFooter: String { footerLabel.stringValue }
    func testingHandleKeyEvent(_ event: NSEvent) -> Bool { handleKeyEvent(event) }
    func testingSetQuery(_ query: String) { queryField.stringValue = query; filterItems() }
}
#endif
