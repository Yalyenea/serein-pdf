import AppKit

private enum SearchResultsRow {
    case section(String)
    case match(SearchSidebarMatch)
}

private struct SearchSelectionKey: Equatable {
    let sessionID: UUID
    let matchIndex: Int
}

private final class SearchResultCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pageIndex: Int, previewText: String, sessionTitle: String?, showsSessionTitle: Bool) {
        if showsSessionTitle, let sessionTitle {
            titleLabel.stringValue = "\(sessionTitle) · Page \(pageIndex + 1)"
        } else {
            titleLabel.stringValue = "Page \(pageIndex + 1)"
        }
        subtitleLabel.stringValue = previewText
    }
}

final class SearchResultsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let horizontalInset: CGFloat = 8
    private static let textInset: CGFloat = 12

    let documentStore: DocumentStore
    let windowID: UUID
    var onActivateMatch: ((SearchSidebarMatch) -> Void)?
    var onSelectionChanged: ((Int?, Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SearchResultColumn"))
    private let emptyStateLabel = NSTextField(labelWithString: "Type in the find bar to preview matches here.")
    private var rows: [SearchResultsRow] = []

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        title = "Search"
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
        rebuildRows()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncTableColumnWidth()
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        column.isEditable = false
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowSizeStyle = .small
        tableView.rowHeight = 42
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 0
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        container.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.horizontalInset),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.textInset),
            emptyStateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.textInset),
            emptyStateLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
            tableView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        }
    }

    func selectNextMatch() -> SearchSidebarMatch? {
        selectMatch(offset: 1)
    }

    func selectPreviousMatch() -> SearchSidebarMatch? {
        selectMatch(offset: -1)
    }

    func activateSelectedMatch() -> SearchSidebarMatch? {
        guard let match = selectedMatch() else { return nil }
        onActivateMatch?(match)
        return match
    }

    func selectFirstMatch() -> SearchSidebarMatch? {
        guard let row = firstMatchRow() else { return nil }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        return selectedMatch()
    }

    func selectedMatch() -> SearchSidebarMatch? {
        guard rows.indices.contains(tableView.selectedRow) else { return nil }
        if case let .match(match) = rows[tableView.selectedRow] {
            return match
        }
        return nil
    }

    func selectionSummary() -> (selectedIndex: Int?, totalMatches: Int) {
        (selectedMatchIndex(), totalMatchCount())
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildRows()
    }

    @objc
    private func handleDoubleClick(_ sender: Any?) {
        _ = activateSelectedMatch()
    }

    private func rebuildRows() {
        guard isViewLoaded else { return }
        let previousSelection = selectedMatch().map {
            SearchSelectionKey(sessionID: $0.sessionID, matchIndex: $0.matchIndex)
        }
        rows = documentStore.searchSections(in: windowID).flatMap { section in
            [SearchResultsRow.section(section.title)] + section.matches.map { .match($0) }
        }
        tableView.reloadData()
        emptyStateLabel.isHidden = rows.isEmpty == false
        scrollView.isHidden = rows.isEmpty

        if let previousSelection,
           let row = rowIndex(for: previousSelection) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            if tableView.selectedRow >= 0 {
                tableView.deselectAll(nil)
            }
            notifySelectionChanged()
        }
    }

    private func selectMatch(offset: Int) -> SearchSidebarMatch? {
        guard rows.isEmpty == false else { return nil }
        let direction = offset >= 0 ? 1 : -1
        guard let currentRow = currentMatchRow(for: direction) else { return nil }
        if tableView.selectedRow < 0 {
            tableView.selectRowIndexes(IndexSet(integer: currentRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(currentRow)
            return selectedMatch()
        }

        var row = currentRow
        for _ in 0..<rows.count {
            row = (row + direction + rows.count) % rows.count
            if case .match = rows[row] {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
                return selectedMatch()
            }
        }
        return nil
    }

    private func currentMatchRow(for direction: Int) -> Int? {
        if tableView.selectedRow >= 0 {
            return tableView.selectedRow
        }
        return direction >= 0 ? firstMatchRow() : lastMatchRow()
    }

    private func firstMatchRow() -> Int? {
        rows.firstIndex {
            if case .match = $0 { return true }
            return false
        }
    }

    private func lastMatchRow() -> Int? {
        rows.lastIndex {
            if case .match = $0 { return true }
            return false
        }
    }

    private func rowIndex(for key: SearchSelectionKey) -> Int? {
        rows.firstIndex { row in
            guard case let .match(match) = row else { return false }
            return match.sessionID == key.sessionID && match.matchIndex == key.matchIndex
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .match = rows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 24 }
        switch rows[row] {
        case .section:
            return 26
        case .match:
            return 42
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        notifySelectionChanged()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case let .section(title):
            let identifier = NSUserInterfaceItemIdentifier("SearchSectionCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeSectionCell(identifier: identifier)
            cell.textField?.stringValue = title
            return cell
        case let .match(match):
            let identifier = NSUserInterfaceItemIdentifier("SearchMatchCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SearchResultCellView
                ?? makeMatchCell(identifier: identifier)
            cell.configure(
                pageIndex: match.pageIndex,
                previewText: match.previewText,
                sessionTitle: match.sessionTitle,
                showsSessionTitle: documentStore.searchScope(in: windowID) == .allOpen
            )
            return cell
        }
    }

    private func makeSectionCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeMatchCell(identifier: NSUserInterfaceItemIdentifier) -> SearchResultCellView {
        let cell = SearchResultCellView()
        cell.identifier = identifier
        return cell
    }

    private func notifySelectionChanged() {
        onSelectionChanged?(selectedMatchIndex(), totalMatchCount())
    }

    private func syncTableColumnWidth() {
        let targetWidth = max(scrollView.contentSize.width, scrollView.bounds.width)
        guard targetWidth > 0,
              abs(column.width - targetWidth) > 0.5 else { return }
        column.width = targetWidth
    }

    private func totalMatchCount() -> Int {
        rows.reduce(into: 0) { count, row in
            if case .match = row {
                count += 1
            }
        }
    }

    private func selectedMatchIndex() -> Int? {
        guard rows.indices.contains(tableView.selectedRow) else { return nil }

        var currentIndex = 0
        for (rowIndex, row) in rows.enumerated() {
            if case .match = row {
                if rowIndex == tableView.selectedRow {
                    return currentIndex
                }
                currentIndex += 1
            }
        }
        return nil
    }
}
