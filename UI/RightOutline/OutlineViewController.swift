import AppKit

final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let documentStore: DocumentStore
    let windowID: UUID
    private let titleLabel = NSTextField(labelWithString: "Outline")
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF with a table of contents to see it here.")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let outlineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
    private let pageCounterLabel = NSTextField(labelWithString: "")
    private var nodes: [OutlineNode] = []

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 0

        pageCounterLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pageCounterLabel.textColor = .secondaryLabelColor
        pageCounterLabel.alignment = .right

        outlineColumn.title = "Outline"
        outlineColumn.resizingMask = .autoresizingMask
        outlineView.addTableColumn(outlineColumn)
        outlineView.outlineTableColumn = outlineColumn
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 12
        outlineView.floatsGroupRows = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        outlineView.focusRingType = .none
        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
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
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        reloadOutline()
        updatePageCounter()
    }

    private func updatePageCounter() {
        guard let session = documentStore.activeSession(in: windowID) else {
            pageCounterLabel.stringValue = ""
            return
        }
        let total = session.pdfDocument.pageCount
        guard total > 0 else {
            pageCounterLabel.stringValue = ""
            return
        }
        let current = min(max(session.currentPageIndex + 1, 1), total)
        pageCounterLabel.stringValue = "\(current) / \(total)"
    }

    private func reloadOutline() {
        guard isViewLoaded else { return }

        nodes = documentStore.activeSession(in: windowID)?.outlineTree ?? []
        outlineView.deselectAll(nil)
        outlineView.reloadData()
        expandAllNodes()

        let isEmpty = nodes.isEmpty
        if documentStore.activeSession(in: windowID) == nil {
            emptyStateLabel.stringValue = "Open a PDF to inspect its outline."
        } else {
            emptyStateLabel.stringValue = "This PDF has no outline."
        }
        emptyStateLabel.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    private func expandAllNodes() {
        for row in 0..<outlineView.numberOfRows {
            outlineView.expandItem(outlineView.item(atRow: row), expandChildren: true)
        }
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
            textField.font = .systemFont(ofSize: 12, weight: .regular)
            textField.textColor = .labelColor
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.textField = textField
            cellView.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        textField.stringValue = node.title
        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? OutlineNode,
              let pageIndex = node.pageIndex,
              let sessionID = documentStore.activeSessionID(in: windowID) else { return }

        documentStore.updateCurrentPage(index: pageIndex, for: sessionID)
    }
}
