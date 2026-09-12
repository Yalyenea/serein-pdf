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
}

enum RecentFilesPaletteInteractionMode {
    case editingQuery
    case navigatingResults
}

private final class RecentFilesPaletteRowView: NSTableCellView {
    private let selectionIndicator = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.font = .systemFont(ofSize: 12, weight: .semibold)
        selectionIndicator.alignment = .center
        selectionIndicator.textColor = HighlightColor.pink.nsColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(selectionIndicator)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            selectionIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            selectionIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: selectionIndicator.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: RecentFilesPaletteItem, isMarked: Bool) {
        selectionIndicator.stringValue = isMarked ? "●" : ""
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
    }
}

@MainActor
final class RecentFilesPaletteController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let panelSize = NSSize(width: 520, height: 640)

    private let panelTitle: String
    private let queryPlaceholder: String
    private let emptyItemsMessage: String
    private let emptyQueryMessage: String
    private let onOpenURLs: ([URL]) -> Void
    private var state = RecentFilesPaletteState(recentURLs: [])
    private var isApplyingSelection = false
    private var interactionMode: RecentFilesPaletteInteractionMode = .editingQuery

    private let titleLabel = NSTextField(labelWithString: "")
    private let queryField = NSTextField(frame: .zero)
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(
        labelWithString: "↑ / ↓ 选中    Space 多选    Enter 打开    Esc 关闭"
    )
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
        self.panelTitle = title
        self.queryPlaceholder = queryPlaceholder
        self.emptyItemsMessage = emptyItemsMessage
        self.emptyQueryMessage = emptyQueryMessage
        self.onOpenURLs = onOpenURLs

        let panel = RecentFilesPalettePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        panel.onKeyEvent = { [weak self] event in
            self?.handlePanelKeyEvent(event) ?? false
        }
        buildInterface(in: panel)
        reloadUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(with recentURLs: [URL], relativeTo parentWindow: NSWindow?) {
        state.replaceRecentURLs(recentURLs)
        interactionMode = .editingQuery
        queryField.stringValue = ""
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        focusQueryField()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = panelTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.delegate = self
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 22, weight: .semibold)
        queryField.placeholderString = queryPlaceholder
        queryField.textColor = .labelColor
        queryField.lineBreakMode = .byTruncatingTail
        queryField.maximumNumberOfLines = 1
        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 11)
        secondaryLabel.textColor = .secondaryLabelColor

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.alignment = .center

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent-file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openHighlightedItem(_:))
        tableView.onKeyEvent = { [weak self] event in
            self?.handleResultsKeyEvent(event) ?? false
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        contentView.addSubview(titleLabel)
        contentView.addSubview(queryField)
        contentView.addSubview(secondaryLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            queryField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            queryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            queryField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            queryField.heightAnchor.constraint(equalToConstant: 30),

            secondaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 4),

            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: secondaryLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),

            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
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
        secondaryLabel.stringValue = secondaryText()

        if state.filteredItems.isEmpty {
            emptyLabel.stringValue = state.allItems.isEmpty ? emptyItemsMessage : emptyQueryMessage
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyLabel.isHidden = true
            scrollView.isHidden = false
        }

        isApplyingSelection = true
        tableView.reloadData()
        applyHighlightedSelection()
        isApplyingSelection = false
    }

    private func secondaryText() -> String {
        let selectedCount = state.selectedURLs.count
        let filteredCount = state.filteredItems.count
        let base = filteredCount == 0 ? "0 results" : "\(filteredCount) results"
        if selectedCount == 0 {
            return base
        }
        return "\(base)  ·  \(selectedCount) selected"
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
    private func openHighlightedItem(_ sender: Any?) {
        openTargetsAndClose()
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
        44
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
        rowView.configure(item: item, isMarked: state.isSelected(item.url))
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isApplyingSelection == false else { return }
        interactionMode = .navigatingResults
        state.setHighlightedIndex(tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
        reloadUI()
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
