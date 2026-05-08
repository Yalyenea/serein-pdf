import AppKit

private final class PDFLibraryPaletteQueryField: NSTextField {
}

private final class PDFLibraryPaletteTableView: NSTableView {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class PDFLibraryPalettePanel: NSPanel {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

private enum PDFLibraryPaletteTable: String {
    case folders
    case pdfs
}

private enum PDFLibraryFolderScope: Equatable {
    case all
    case root(URL)
    case folder(URL)
}

private struct PDFLibraryFolderRow: Equatable {
    let scope: PDFLibraryFolderScope
    let title: String
    let subtitle: String
}

private final class PDFLibraryFolderCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(row: PDFLibraryFolderRow) {
        titleLabel.stringValue = row.title
        subtitleLabel.stringValue = row.subtitle
    }
}

private final class PDFLibraryPDFCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: PDFLibraryItem) {
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.relativePath
    }
}

@MainActor
final class PDFLibraryPaletteController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let panelSize = NSSize(width: 860, height: 620)

    private let onOpenURL: (URL) -> Void
    private let catalogCache = PDFLibraryCatalogCache()
    private var catalog = PDFLibraryCatalog(roots: [], items: [])
    private var selectedSegmentIndex = 0
    private var selectedFolderScope: PDFLibraryFolderScope = .all
    private var folderRows: [PDFLibraryFolderRow] = []
    private var filteredItems: [PDFLibraryItem] = []
    private var isApplyingSelection = false

    private let titleLabel = NSTextField(labelWithString: "PDF Library")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let segmentControl = NSSegmentedControl(labels: ["All"], trackingMode: .selectOne, target: nil, action: nil)
    private let queryField = PDFLibraryPaletteQueryField(frame: .zero)
    private let foldersScrollView = NSScrollView()
    private let pdfsScrollView = NSScrollView()
    private let foldersTableView = PDFLibraryPaletteTableView()
    private let pdfsTableView = PDFLibraryPaletteTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "↑ / ↓ 选中    Enter 打开    Esc 关闭")

    init(onOpenURL: @escaping (URL) -> Void) {
        self.onOpenURL = onOpenURL

        let panel = PDFLibraryPalettePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "PDF Library"
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

    func show(folderURLs: [URL], relativeTo parentWindow: NSWindow?) {
        catalog = catalogCache.catalog(folderURLs: folderURLs)
        selectedSegmentIndex = 0
        selectedFolderScope = .all
        queryField.stringValue = ""
        rebuildSegments()
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        focusQueryField()
        NSApp.activate(ignoringOtherApps: true)
    }

    func invalidateCatalogCache() {
        catalogCache.invalidate()
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 11)
        secondaryLabel.textColor = .secondaryLabelColor

        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        segmentControl.target = self
        segmentControl.action = #selector(segmentDidChange(_:))
        segmentControl.selectedSegment = 0

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.delegate = self
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 22, weight: .semibold)
        queryField.placeholderString = "Search library PDFs"
        queryField.maximumNumberOfLines = 1

        configure(tableView: foldersTableView, identifier: PDFLibraryPaletteTable.folders.rawValue)
        foldersTableView.rowHeight = 42
        foldersTableView.target = self
        foldersTableView.doubleAction = #selector(folderDoubleClicked(_:))
        foldersTableView.onKeyEvent = { [weak self] event in
            self?.handleFolderKeyEvent(event) ?? false
        }

        configure(tableView: pdfsTableView, identifier: PDFLibraryPaletteTable.pdfs.rawValue)
        pdfsTableView.rowHeight = 44
        pdfsTableView.target = self
        pdfsTableView.doubleAction = #selector(openSelectedPDF(_:))
        pdfsTableView.onKeyEvent = { [weak self] event in
            self?.handlePDFKeyEvent(event) ?? false
        }

        configure(scrollView: foldersScrollView, documentView: foldersTableView)
        configure(scrollView: pdfsScrollView, documentView: pdfsTableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.alignment = .center

        let contentSplit = NSStackView(views: [foldersScrollView, pdfsScrollView])
        contentSplit.translatesAutoresizingMaskIntoConstraints = false
        contentSplit.orientation = .horizontal
        contentSplit.spacing = 10
        contentSplit.distribution = .fill
        foldersScrollView.widthAnchor.constraint(equalToConstant: 240).isActive = true

        contentView.addSubview(titleLabel)
        contentView.addSubview(secondaryLabel)
        contentView.addSubview(segmentControl)
        contentView.addSubview(queryField)
        contentView.addSubview(contentSplit)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            secondaryLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            secondaryLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            secondaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            segmentControl.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            segmentControl.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            segmentControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

            queryField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            queryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            queryField.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 12),
            queryField.heightAnchor.constraint(equalToConstant: 30),

            contentSplit.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            contentSplit.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            contentSplit.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 12),
            contentSplit.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: pdfsScrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: pdfsScrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pdfsScrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: pdfsScrollView.trailingAnchor, constant: -20),

            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    private func configure(tableView: NSTableView, identifier: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = self
        tableView.dataSource = self
    }

    private func configure(scrollView: NSScrollView, documentView: NSTableView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
    }

    private func rebuildSegments() {
        segmentControl.segmentCount = max(1, catalog.roots.count + 1)
        segmentControl.setLabel("All", forSegment: 0)
        segmentControl.setWidth(64, forSegment: 0)
        for (index, root) in catalog.roots.enumerated() {
            let segment = index + 1
            segmentControl.setLabel(root.title, forSegment: segment)
            segmentControl.setWidth(max(84, min(160, CGFloat(root.title.count * 9 + 24))), forSegment: segment)
        }
        segmentControl.selectedSegment = 0
    }

    private func positionPanel(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }
        let targetFrame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        window.setFrameOrigin(
            NSPoint(
                x: targetFrame.midX - window.frame.width / 2,
                y: targetFrame.midY - window.frame.height / 2
            )
        )
    }

    private func reloadUI(rebuildFolders: Bool = true) {
        if rebuildFolders {
            folderRows = makeFolderRows()
            if folderRows.contains(where: { $0.scope == selectedFolderScope }) == false {
                selectedFolderScope = .all
            }
        }
        filteredItems = makeFilteredItems()
        secondaryLabel.stringValue = "\(filteredItems.count) PDFs"
        emptyLabel.stringValue = emptyMessage()
        emptyLabel.isHidden = filteredItems.isEmpty == false
        pdfsScrollView.isHidden = filteredItems.isEmpty

        isApplyingSelection = true
        if rebuildFolders {
            foldersTableView.reloadData()
            selectCurrentFolder()
        }
        pdfsTableView.reloadData()
        selectFirstPDF()
        isApplyingSelection = false
    }

    private func makeFolderRows() -> [PDFLibraryFolderRow] {
        let rootItems = itemsForSelectedSegment()
        var rows: [PDFLibraryFolderRow] = [
            PDFLibraryFolderRow(scope: .all, title: selectedSegmentIndex == 0 ? "All libraries" : "All PDFs", subtitle: "\(rootItems.count) PDFs"),
        ]

        if selectedSegmentIndex == 0 {
            for root in catalog.roots {
                let count = catalog.rootItemCounts[root.url, default: 0]
                rows.append(PDFLibraryFolderRow(scope: .root(root.url), title: root.title, subtitle: "\(count) PDFs"))
            }
        }

        let folders = Dictionary(grouping: rootItems, by: \.folderURL).map { folderURL, items in
            let relativeFolderPath = folderTitle(for: folderURL, items: items)
            return PDFLibraryFolderRow(scope: .folder(folderURL), title: relativeFolderPath, subtitle: "\(items.count) PDFs")
        }
        rows.append(
            contentsOf: folders.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        )
        return rows
    }

    private func folderTitle(for folderURL: URL, items: [PDFLibraryItem]) -> String {
        guard let firstItem = items.first else { return folderURL.lastPathComponent }
        if selectedSegmentIndex == 0 {
            let rootTitle = catalog.roots.first(where: { $0.url == firstItem.rootURL })?.title ?? firstItem.rootURL.lastPathComponent
            guard firstItem.relativeFolderPath.isEmpty == false else { return rootTitle }
            return rootTitle + "/" + firstItem.relativeFolderPath
        }
        return firstItem.relativeFolderPath.isEmpty ? firstItem.rootURL.lastPathComponent : firstItem.relativeFolderPath
    }

    private func makeFilteredItems() -> [PDFLibraryItem] {
        let scopedItems = itemsForSelectedFolder()
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return scopedItems }
        return scopedItems.filter { item in
            item.searchableText.contains(query)
        }
    }

    private func itemsForSelectedSegment() -> [PDFLibraryItem] {
        guard selectedSegmentIndex > 0,
              catalog.roots.indices.contains(selectedSegmentIndex - 1) else {
            return catalog.items
        }
        let rootURL = catalog.roots[selectedSegmentIndex - 1].url
        return catalog.items(forRootURL: rootURL)
    }

    private func itemsForSelectedFolder() -> [PDFLibraryItem] {
        let segmentItems = itemsForSelectedSegment()
        switch selectedFolderScope {
        case .all:
            return segmentItems
        case .root(let rootURL):
            return catalog.items(forRootURL: rootURL)
        case .folder(let folderURL):
            return catalog.items(forFolderURL: folderURL)
        }
    }

    private func emptyMessage() -> String {
        if catalog.roots.isEmpty {
            return "No library folders configured."
        }
        if catalog.items.isEmpty {
            return "No PDFs found in library folders."
        }
        return "No PDFs match the current filter."
    }

    private func selectCurrentFolder() {
        guard let index = folderRows.firstIndex(where: { $0.scope == selectedFolderScope }) else {
            foldersTableView.deselectAll(nil)
            return
        }
        foldersTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        foldersTableView.scrollRowToVisible(index)
    }

    private func selectFirstPDF() {
        guard filteredItems.isEmpty == false else {
            pdfsTableView.deselectAll(nil)
            return
        }
        let selectedRow = pdfsTableView.selectedRow
        let nextRow = filteredItems.indices.contains(selectedRow) ? selectedRow : 0
        pdfsTableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        pdfsTableView.scrollRowToVisible(nextRow)
    }

    private func focusQueryField() {
        window?.makeFirstResponder(queryField)
        if let editor = window?.fieldEditor(true, for: queryField) as? NSTextView {
            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
        }
    }

    private func openSelectedPDFAndClose() {
        let row = pdfsTableView.selectedRow
        guard filteredItems.indices.contains(row) else {
            NSSound.beep()
            return
        }
        let url = filteredItems[row].url
        close()
        onOpenURL(url)
    }

    @objc
    private func segmentDidChange(_ sender: NSSegmentedControl) {
        selectedSegmentIndex = sender.selectedSegment
        selectedFolderScope = .all
        reloadUI()
    }

    @objc
    private func folderDoubleClicked(_ sender: Any?) {
        window?.makeFirstResponder(pdfsTableView)
    }

    @objc
    private func openSelectedPDF(_ sender: Any?) {
        openSelectedPDFAndClose()
    }

    func controlTextDidChange(_ notification: Notification) {
        reloadUI(rebuildFolders: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === queryField else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            guard filteredItems.isEmpty == false else { return false }
            window?.makeFirstResponder(pdfsTableView)
            return true
        case #selector(NSResponder.moveUp(_:)):
            window?.makeFirstResponder(foldersTableView)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelectedPDFAndClose()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func handleFolderKeyEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53:
            close()
            return true
        case 36, 76:
            window?.makeFirstResponder(pdfsTableView)
            return true
        default:
            return false
        }
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 53:
            close()
            return true
        case 36, 76:
            openSelectedPDFAndClose()
            return true
        default:
            return false
        }
    }

    private func handlePDFKeyEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53:
            close()
            return true
        case 36, 76:
            openSelectedPDFAndClose()
            return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === foldersTableView {
            return folderRows.count
        }
        return filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        tableView === foldersTableView ? 42 : 44
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === foldersTableView {
            let identifier = NSUserInterfaceItemIdentifier("PDFLibraryFolderCellView")
            let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? PDFLibraryFolderCellView)
                ?? {
                    let view = PDFLibraryFolderCellView()
                    view.identifier = identifier
                    return view
                }()
            view.configure(row: folderRows[row])
            return view
        }

        let identifier = NSUserInterfaceItemIdentifier("PDFLibraryPDFCellView")
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? PDFLibraryPDFCellView)
            ?? {
                let view = PDFLibraryPDFCellView()
                view.identifier = identifier
                return view
            }()
        view.configure(item: filteredItems[row])
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isApplyingSelection == false,
              let tableView = notification.object as? NSTableView,
              tableView === foldersTableView,
              folderRows.indices.contains(tableView.selectedRow) else { return }
        selectedFolderScope = folderRows[tableView.selectedRow].scope
        reloadUI(rebuildFolders: false)
    }
}

#if DEBUG
extension PDFLibraryPaletteController {
    var testingFolderRowTitles: [String] { folderRows.map(\.title) }
    var testingPDFTitles: [String] { filteredItems.map(\.title) }

    func testingShow(folderURLs: [URL]) {
        show(folderURLs: folderURLs, relativeTo: nil)
    }

    func testingSetQuery(_ query: String) {
        queryField.stringValue = query
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: queryField))
    }
}
#endif
