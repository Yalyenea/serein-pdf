import AppKit

private final class RecentFilesPaletteQueryField: NSTextField {
    var onCommandEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if shouldHandleAsCommand(event), onCommandEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    private func shouldHandleAsCommand(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty, hasMarkedText == false else { return false }

        switch Int(event.keyCode) {
        case 53, 125, 126, 36, 76:
            return true
        case 49:
            return stringValue.isEmpty
        default:
            break
        }

        return event.characters == "?"
    }

    private var hasMarkedText: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }
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

    private let onOpenURLs: ([URL]) -> Void
    private var state = RecentFilesPaletteState(recentURLs: [])
    private var isApplyingSelection = false

    private let titleLabel = NSTextField(labelWithString: "Recent Files")
    private let queryField = RecentFilesPaletteQueryField(frame: .zero)
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let helpContainer = NSView()
    private let helpLabel = NSTextField(
        wrappingLabelWithString: "↑ / ↓ 选中    Space 多选    Enter 打开    ? 帮助    Esc 关闭"
    )
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var helpTopConstraint: NSLayoutConstraint?
    private var scrollTopToHelpConstraint: NSLayoutConstraint?
    private var scrollTopToSecondaryConstraint: NSLayoutConstraint?

    init(onOpenURLs: @escaping ([URL]) -> Void) {
        self.onOpenURLs = onOpenURLs

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Recent Files"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = SplitViewController.splitBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        buildInterface(in: panel)
        reloadUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(with recentURLs: [URL], relativeTo parentWindow: NSWindow?) {
        state.replaceRecentURLs(recentURLs)
        queryField.stringValue = ""
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(queryField)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.delegate = self
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 22, weight: .semibold)
        queryField.placeholderString = "Filter recent files"
        queryField.textColor = .labelColor
        queryField.lineBreakMode = .byTruncatingTail
        queryField.maximumNumberOfLines = 1
        queryField.onCommandEvent = { [weak self] event in
            self?.handleCommandEvent(event) ?? false
        }

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 11)
        secondaryLabel.textColor = .secondaryLabelColor

        helpContainer.translatesAutoresizingMaskIntoConstraints = false
        helpContainer.wantsLayer = true
        helpContainer.layer?.cornerRadius = 8
        helpContainer.layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor.cgColor
        helpContainer.layer?.borderWidth = 1
        helpContainer.layer?.borderColor = SplitViewController.chromeStrokeColor.cgColor

        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = .systemFont(ofSize: 12)
        helpContainer.addSubview(helpLabel)

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
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openHighlightedItem(_:))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        contentView.addSubview(titleLabel)
        contentView.addSubview(queryField)
        contentView.addSubview(secondaryLabel)
        contentView.addSubview(helpContainer)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

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

            helpContainer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            helpContainer.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            {
                let constraint = helpContainer.topAnchor.constraint(equalTo: secondaryLabel.bottomAnchor, constant: 12)
                helpTopConstraint = constraint
                return constraint
            }(),

            helpLabel.leadingAnchor.constraint(equalTo: helpContainer.leadingAnchor, constant: 12),
            helpLabel.trailingAnchor.constraint(equalTo: helpContainer.trailingAnchor, constant: -12),
            helpLabel.topAnchor.constraint(equalTo: helpContainer.topAnchor, constant: 10),
            helpLabel.bottomAnchor.constraint(equalTo: helpContainer.bottomAnchor, constant: -10),

            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            {
                let constraint = scrollView.topAnchor.constraint(equalTo: helpContainer.bottomAnchor, constant: 12)
                scrollTopToHelpConstraint = constraint
                return constraint
            }(),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),
        ])

        let fallbackTopConstraint = scrollView.topAnchor.constraint(equalTo: secondaryLabel.bottomAnchor, constant: 12)
        fallbackTopConstraint.isActive = false
        scrollTopToSecondaryConstraint = fallbackTopConstraint
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
        helpContainer.isHidden = !state.isHelpVisible
        helpTopConstraint?.isActive = state.isHelpVisible
        scrollTopToHelpConstraint?.isActive = state.isHelpVisible
        scrollTopToSecondaryConstraint?.isActive = !state.isHelpVisible

        if state.filteredItems.isEmpty {
            emptyLabel.stringValue = state.allItems.isEmpty ? "No recent files yet." : "No recent files match the current query."
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyLabel.isHidden = true
            scrollView.isHidden = false
        }

        tableView.reloadData()
        applyHighlightedSelection()
    }

    private func secondaryText() -> String {
        let selectedCount = state.selectedURLs.count
        let filteredCount = state.filteredItems.count
        let base = filteredCount == 0 ? "0 results" : "\(filteredCount) results"
        if selectedCount == 0 {
            return "\(base)  ·  支持中英文输入"
        }
        return "\(base)  ·  \(selectedCount) selected"
    }

    private func applyHighlightedSelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }

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

    private func handleCommandEvent(_ event: NSEvent) -> Bool {
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

        if event.characters == "?" {
            state.toggleHelp()
            reloadUI()
            return true
        }

        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        state.query = queryField.stringValue
        reloadUI()
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
        state.setHighlightedIndex(tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
        reloadUI()
    }
}
