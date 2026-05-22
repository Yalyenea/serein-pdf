import AppKit

final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static let outlineFontSize: CGFloat = 13
    private static let rowHorizontalPadding: CGFloat = 4
    private static let rowVerticalPadding: CGFloat = 2
    private static let wrappedLineHeight: CGFloat = 14
    private static let minimumRowHeight: CGFloat = 22

    let documentStore: DocumentStore
    let windowID: UUID
    private let titleLabel = NSTextField(labelWithString: "Outline")
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF with a table of contents to see it here.")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let outlineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
    private let pageCounterLabel = NSTextField(labelWithString: "")
    private var nodes: [OutlineNode] = []
    private var displayedSessionID: UUID?

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
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NightModeStyle.primaryTextColor

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
        outlineView.floatsGroupRows = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        outlineView.focusRingType = .none
        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = outlineView

        for view in [titleLabel, emptyStateLabel, scrollView, pageCounterLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            emptyStateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            emptyStateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: pageCounterLabel.topAnchor, constant: -4),

            pageCounterLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            pageCounterLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            pageCounterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
        ])

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
            outlineView.backgroundColor = PlaceholderViewController.paneBackgroundColor
            titleLabel.textColor = NightModeStyle.primaryTextColor
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
        expandAllNodes()
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
    }

    private func syncOutlineColumnWidth() {
        let targetWidth = max(scrollView.contentSize.width, scrollView.bounds.width)
        guard targetWidth > 0,
              abs(outlineColumn.width - targetWidth) > 0.5 else { return }
        outlineColumn.width = targetWidth
        invalidateRowHeights()
    }

    private func expandAllNodes() {
        var row = 0
        while row < outlineView.numberOfRows {
            outlineView.expandItem(outlineView.item(atRow: row), expandChildren: true)
            row += 1
        }
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
        paragraphStyle.lineBreakMode = .byWordWrapping
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
        return max(
            outlineColumn.width - indentation - Self.rowHorizontalPadding * 2 - 20,
            48
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
            options: [.usesLineFragmentOrigin]
        ).height
        return max(Self.minimumRowHeight, ceil(textHeight) + Self.rowVerticalPadding * 2)
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
            textField.lineBreakMode = .byWordWrapping
            textField.translatesAutoresizingMaskIntoConstraints = false
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
        textField.attributedStringValue = attributedTitle(for: node)
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
