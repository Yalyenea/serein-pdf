import AppKit

private final class RecentFilesPaletteWindow: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
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
        selectionIndicator.font = .systemFont(ofSize: 14, weight: .semibold)
        selectionIndicator.alignment = .center
        selectionIndicator.textColor = HighlightColor.pink.nsColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(selectionIndicator)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            selectionIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            selectionIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: selectionIndicator.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
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
final class RecentFilesPaletteController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static let panelSize = NSSize(width: 720, height: 420)

    private let onOpenURLs: ([URL]) -> Void
    private var state = RecentFilesPaletteState(recentURLs: [])
    private var isApplyingSelection = false

    private let titleLabel = NSTextField(labelWithString: "Recent Files")
    private let queryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let helpContainer = NSView()
    private let helpLabel = NSTextField(
        wrappingLabelWithString: "↑ / ↓ 选择结果    Space 多选    Enter 打开    Delete 删除搜索字符    ? 显示帮助    Esc 关闭"
    )
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var helpTopConstraint: NSLayoutConstraint?
    private var scrollTopToHelpConstraint: NSLayoutConstraint?
    private var scrollTopToSecondaryConstraint: NSLayoutConstraint?

    init(onOpenURLs: @escaping ([URL]) -> Void) {
        self.onOpenURLs = onOpenURLs

        let panel = RecentFilesPaletteWindow(
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

        super.init(window: panel)
        panel.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
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
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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

        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        queryLabel.font = .monospacedSystemFont(ofSize: 24, weight: .semibold)
        queryLabel.lineBreakMode = .byTruncatingMiddle

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
        tableView.rowHeight = 52
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
        contentView.addSubview(queryLabel)
        contentView.addSubview(secondaryLabel)
        contentView.addSubview(helpContainer)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),

            queryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            queryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            queryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            secondaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: queryLabel.trailingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 6),

            helpContainer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            helpContainer.trailingAnchor.constraint(equalTo: queryLabel.trailingAnchor),
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
            scrollView.trailingAnchor.constraint(equalTo: queryLabel.trailingAnchor),
            {
                let constraint = scrollView.topAnchor.constraint(equalTo: helpContainer.bottomAnchor, constant: 12)
                scrollTopToHelpConstraint = constraint
                return constraint
            }(),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

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
        queryLabel.stringValue = state.query.isEmpty ? "Type to filter recent files" : state.query
        queryLabel.textColor = state.query.isEmpty ? .secondaryLabelColor : .labelColor
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
            return "\(base)  ·  Press ? for help"
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

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        if modifiers.isEmpty == false {
            return false
        }

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
        case 51, 117:
            state.deleteBackward()
            reloadUI()
            return true
        default:
            break
        }

        guard let characters = event.characters, characters.isEmpty == false else { return false }
        if characters == "?" {
            state.toggleHelp()
            reloadUI()
            return true
        }

        let printableScalars = characters.unicodeScalars.filter { scalar in
            CharacterSet.controlCharacters.contains(scalar) == false
        }
        guard printableScalars.isEmpty == false else { return false }
        state.appendToQuery(String(String.UnicodeScalarView(printableScalars)))
        reloadUI()
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        52
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
