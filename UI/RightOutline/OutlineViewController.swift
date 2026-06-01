import AppKit

private final class OutlineClipView: NSClipView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }
}

private final class OutlineRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let selectionRect = bounds.insetBy(dx: 2, dy: 1)
        NightModeStyle.selectedChromeBackgroundColor.setFill()
        NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5).fill()
    }

    override func drawSeparator(in dirtyRect: NSRect) {}
}

final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static let outlineFontSize: CGFloat = 13
    private static let rowHorizontalPadding: CGFloat = 2
    private static let rowVerticalPadding: CGFloat = 2
    private static let wrappedLineHeight: CGFloat = 14
    private static let minimumRowHeight: CGFloat = 22
    private static let disclosureAndIndentReserve: CGFloat = 18

    let documentStore: DocumentStore
    let windowID: UUID
    private let titleLabel = NSTextField(labelWithString: "Outline")
    private let expansionToggleButton = NSButton()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF with a table of contents to see it here.")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let outlineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
    private let pageCounterLabel = NSTextField(labelWithString: "")
    private var nodes: [OutlineNode] = []
    private var displayedSessionID: UUID?
    private var isOutlineCollapsed = false

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        title = "Outline"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        reloadOutline()
        updatePageCounter()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncOutlineColumnWidth()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NightModeStyle.primaryTextColor

        expansionToggleButton.identifier = NSUserInterfaceItemIdentifier("outlineExpansionToggleButton")
        expansionToggleButton.imagePosition = .imageOnly
        expansionToggleButton.isBordered = false
        expansionToggleButton.bezelStyle = .regularSquare
        expansionToggleButton.controlSize = .small
        expansionToggleButton.focusRingType = .none
        expansionToggleButton.target = self
        expansionToggleButton.action = #selector(toggleOutlineExpansion(_:))
        expansionToggleButton.setButtonType(.momentaryChange)

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = NightModeStyle.secondaryTextColor
        emptyStateLabel.maximumNumberOfLines = 0

        pageCounterLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pageCounterLabel.textColor = NightModeStyle.secondaryTextColor
        pageCounterLabel.alignment = .right

        outlineColumn.title = "Outline"
        outlineColumn.resizingMask = .autoresizingMask
        outlineView.addTableColumn(outlineColumn)
        outlineView.outlineTableColumn = outlineColumn
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.rowHeight = Self.minimumRowHeight
        outlineView.indentationPerLevel = 12
        outlineView.intercellSpacing = .zero
        outlineView.floatsGroupRows = false
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.gridStyleMask = []
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = .clear
        outlineView.enclosingScrollView?.drawsBackground = false
        outlineView.wantsLayer = true
        outlineView.layer?.backgroundColor = NSColor.clear.cgColor
        outlineView.autoresizingMask = [.width]
        outlineView.focusRingType = .none
        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView = OutlineClipView()
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.documentView = outlineView

        for view in [titleLabel, expansionToggleButton, emptyStateLabel, scrollView, pageCounterLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: expansionToggleButton.leadingAnchor, constant: -6),

            expansionToggleButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            expansionToggleButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            expansionToggleButton.widthAnchor.constraint(equalToConstant: 22),
            expansionToggleButton.heightAnchor.constraint(equalToConstant: 20),

            emptyStateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            emptyStateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: pageCounterLabel.topAnchor, constant: -4),

            pageCounterLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            pageCounterLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            pageCounterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
        ])

        view = container
        updateExpansionToggleButton()
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            outlineView.backgroundColor = .clear
            outlineView.layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.contentView.backgroundColor = .clear
            titleLabel.textColor = NightModeStyle.primaryTextColor
            expansionToggleButton.contentTintColor = NightModeStyle.secondaryTextColor
            emptyStateLabel.textColor = NightModeStyle.secondaryTextColor
            pageCounterLabel.textColor = NightModeStyle.secondaryTextColor
        }
        outlineView.reloadData()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        let session = documentStore.activeSession(in: windowID)
        let sessionID = session?.id
        let outlineTree = documentStore.outlineTreeForSidebar(in: windowID)
        if displayedSessionID != sessionID || nodes != outlineTree {
            reloadOutline()
        }
        updatePageCounter()
    }

    private func updatePageCounter() {
        guard let session = documentStore.activeSession(in: windowID) else {
            pageCounterLabel.stringValue = ""
            return
        }
        let total = documentStore.pageCount(for: session.id) ?? 0
        guard total > 0 else {
            pageCounterLabel.stringValue = ""
            return
        }
        let current = min(max(session.currentPageIndex + 1, 1), total)
        if documentStore.isContinuousReadingEnabled(in: windowID),
           let index = documentStore.continuousReadingSessionIDs(in: windowID).firstIndex(of: session.id) {
            pageCounterLabel.stringValue = "\(index + 1) / \(documentStore.continuousReadingSessionIDs(in: windowID).count) · \(current) / \(total)"
        } else {
            pageCounterLabel.stringValue = "\(current) / \(total)"
        }
    }

    private func reloadOutline() {
        guard isViewLoaded else { return }

        let session = documentStore.activeSession(in: windowID)
        displayedSessionID = session?.id
        nodes = documentStore.outlineTreeForSidebar(in: windowID)
        outlineView.deselectAll(nil)
        outlineView.reloadData()
        applyOutlineExpansionState()
        invalidateRowHeights()

        let isEmpty = nodes.isEmpty
        if session == nil {
            emptyStateLabel.stringValue = "Open a PDF to inspect its outline."
        } else if documentStore.isContinuousReadingEnabled(in: windowID) {
            emptyStateLabel.stringValue = "No outline in this continuous group."
        } else {
            emptyStateLabel.stringValue = "This PDF has no outline."
        }
        emptyStateLabel.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
        updateExpansionToggleButton()
    }

    private func syncOutlineColumnWidth() {
        let visibleWidth = scrollView.contentView.bounds.width
        let targetWidth = max(visibleWidth > 0 ? visibleWidth : scrollView.bounds.width, 1)
        guard targetWidth > 0,
              abs(outlineColumn.width - targetWidth) > 0.5 ||
              abs(outlineView.frame.width - targetWidth) > 0.5 else {
            lockHorizontalScrollPosition()
            return
        }
        outlineColumn.minWidth = targetWidth
        outlineColumn.maxWidth = targetWidth
        outlineColumn.width = targetWidth
        outlineView.setFrameSize(NSSize(width: targetWidth, height: outlineView.frame.height))
        lockHorizontalScrollPosition()
        invalidateRowHeights()
    }

    private func lockHorizontalScrollPosition() {
        let currentBounds = scrollView.contentView.bounds
        guard currentBounds.origin.x != 0 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: currentBounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func applyOutlineExpansionState() {
        if isOutlineCollapsed {
            collapseAllNodes()
        } else {
            expandAllNodes()
        }
    }

    private func expandAllNodes() {
        var row = 0
        while row < outlineView.numberOfRows {
            outlineView.expandItem(outlineView.item(atRow: row), expandChildren: true)
            row += 1
        }
    }

    private func collapseAllNodes() {
        var row = outlineView.numberOfRows - 1
        while row >= 0 {
            outlineView.collapseItem(outlineView.item(atRow: row), collapseChildren: true)
            row -= 1
        }
    }

    @objc
    private func toggleOutlineExpansion(_ sender: NSButton) {
        isOutlineCollapsed.toggle()
        applyOutlineExpansionState()
        updateExpansionToggleButton()
        invalidateRowHeights()
    }

    private func updateExpansionToggleButton() {
        expansionToggleButton.isEnabled = nodes.contains { !$0.children.isEmpty }
        let symbolName = isOutlineCollapsed ? "chevron.right" : "chevron.down"
        let accessibilityDescription = isOutlineCollapsed ? "Expand outline" : "Collapse outline"
        expansionToggleButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        expansionToggleButton.toolTip = accessibilityDescription
        expansionToggleButton.contentTintColor = NightModeStyle.secondaryTextColor
    }

    private func invalidateRowHeights() {
        guard outlineView.numberOfRows > 0 else { return }
        outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outlineView.numberOfRows))
    }

    private func font(for node: OutlineNode) -> NSFont {
        node.isDocumentRoot
            ? .systemFont(ofSize: Self.outlineFontSize, weight: .semibold)
            : .systemFont(ofSize: Self.outlineFontSize, weight: .regular)
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.minimumLineHeight = Self.wrappedLineHeight
        paragraphStyle.maximumLineHeight = Self.wrappedLineHeight
        paragraphStyle.lineSpacing = 0
        return paragraphStyle
    }

    private func textAttributes(for node: OutlineNode) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: node),
            .foregroundColor: node.isDocumentRoot ? NightModeStyle.primaryTextColor : NightModeStyle.secondaryTextColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    private func attributedTitle(for node: OutlineNode) -> NSAttributedString {
        NSAttributedString(string: node.title, attributes: textAttributes(for: node))
    }

    private func textWidth(for item: Any) -> CGFloat {
        let indentation = CGFloat(outlineView.level(forItem: item)) * outlineView.indentationPerLevel
        let visibleColumnWidth = scrollView.contentView.bounds.width > 0
            ? min(outlineColumn.width, scrollView.contentView.bounds.width)
            : outlineColumn.width
        return max(
            visibleColumnWidth - indentation - Self.disclosureAndIndentReserve - Self.rowHorizontalPadding * 2,
            12
        )
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? OutlineNode
        return node?.children.count ?? nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? OutlineNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? OutlineNode
        return node?.children[index] ?? nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? OutlineNode else { return Self.minimumRowHeight }
        let boundingSize = NSSize(width: textWidth(for: item), height: .greatestFiniteMagnitude)
        let textHeight = attributedTitle(for: node).boundingRect(
            with: boundingSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(Self.minimumRowHeight, ceil(textHeight) + Self.rowVerticalPadding * 2)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        OutlineRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("OutlineCell")
        let cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = identifier

        let textField: NSTextField
        if let existing = cellView.textField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.maximumNumberOfLines = 0
            textField.lineBreakMode = .byCharWrapping
            textField.drawsBackground = false
            textField.backgroundColor = .clear
            textField.isBordered = false
            textField.cell?.wraps = true
            textField.cell?.isScrollable = false
            textField.cell?.usesSingleLineMode = false
            textField.cell?.lineBreakMode = .byCharWrapping
            textField.cell?.truncatesLastVisibleLine = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentCompressionResistancePriority(.required, for: .vertical)
            cellView.textField = textField
            cellView.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: Self.rowHorizontalPadding),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -Self.rowHorizontalPadding),
                textField.topAnchor.constraint(equalTo: cellView.topAnchor, constant: Self.rowVerticalPadding),
                textField.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -Self.rowVerticalPadding),
            ])
        }

        textField.font = font(for: node)
        textField.lineBreakMode = .byCharWrapping
        textField.cell?.lineBreakMode = .byCharWrapping
        textField.cell?.truncatesLastVisibleLine = false
        textField.attributedStringValue = attributedTitle(for: node)
        textField.preferredMaxLayoutWidth = textWidth(for: item)
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = NSColor.clear.cgColor
        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? OutlineNode,
              let pageIndex = node.pageIndex else { return }

        let targetSessionID = node.sourceSessionID ?? documentStore.activeSessionID(in: windowID)
        guard let targetSessionID else { return }
        documentStore.updateCurrentPage(index: pageIndex, for: targetSessionID)
        if documentStore.activeSessionID(in: windowID) != targetSessionID {
            documentStore.activate(sessionID: targetSessionID, in: windowID)
        }
    }
}
