import AppKit

private enum AnnotationRow {
    case section(String)
    case highlight(DocumentHighlightGroup)
}

private final class AnnotationColorDotView: NSView {
    var color: NSColor = HighlightColor.default.nsColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

private final class AnnotationHighlightCellView: NSTableCellView {
    private let colorDotView = AnnotationColorDotView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        colorDotView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(colorDotView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            colorDotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            colorDotView.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            colorDotView.widthAnchor.constraint(equalToConstant: 8),
            colorDotView.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: colorDotView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with group: DocumentHighlightGroup) {
        colorDotView.color = group.color.nsColor
        titleLabel.stringValue = group.snippet
        subtitleLabel.stringValue = group.commentPreview
    }
}

final class AnnotationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    let documentStore: DocumentStore
    let windowID: UUID
    var onActivateHighlight: ((DocumentHighlightGroup) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AnnotationColumn"))
    private let emptyStateLabel = NSTextField(labelWithString: "Highlights will appear here once you annotate the PDF.")
    private let detailContainer = NSView()
    private let detailDivider = NSBox()
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let commentLabel = NSTextField(labelWithString: "Comment")
    private let commentScrollView = NSScrollView()
    private let commentTextView = NSTextView()
    private let applyCommentButton = NSButton(title: "Apply", target: nil, action: nil)
    private let clearCommentButton = NSButton(title: "Clear", target: nil, action: nil)
    private var rows: [AnnotationRow] = []
    private var currentGroupID: String?

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        title = "Annotations"
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

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        column.isEditable = false
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .small
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        tableView.allowsEmptySelection = false
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(handleRowAction(_:))
        tableView.doubleAction = #selector(handleRowAction(_:))

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

        detailDivider.boxType = .separator
        detailDivider.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        snippetLabel.font = .systemFont(ofSize: 11, weight: .medium)
        snippetLabel.maximumNumberOfLines = 2
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        commentLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        commentLabel.translatesAutoresizingMaskIntoConstraints = false

        commentTextView.isRichText = false
        commentTextView.usesFontPanel = false
        commentTextView.isAutomaticQuoteSubstitutionEnabled = false
        commentTextView.isEditable = true
        commentTextView.isSelectable = true
        commentTextView.isHorizontallyResizable = false
        commentTextView.isVerticallyResizable = true
        commentTextView.allowsUndo = true
        commentTextView.font = .systemFont(ofSize: 12)
        commentTextView.backgroundColor = .textBackgroundColor
        commentTextView.textContainerInset = NSSize(width: 4, height: 6)
        commentTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        commentTextView.textContainer?.widthTracksTextView = true
        commentTextView.delegate = self

        commentScrollView.drawsBackground = true
        commentScrollView.borderType = .bezelBorder
        commentScrollView.hasHorizontalScroller = false
        commentScrollView.hasVerticalScroller = true
        commentScrollView.autohidesScrollers = true
        commentScrollView.documentView = commentTextView
        commentScrollView.translatesAutoresizingMaskIntoConstraints = false
        commentScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        applyCommentButton.bezelStyle = .rounded
        applyCommentButton.controlSize = .small
        applyCommentButton.target = self
        applyCommentButton.action = #selector(applyComment(_:))
        applyCommentButton.translatesAutoresizingMaskIntoConstraints = false
        applyCommentButton.setContentCompressionResistancePriority(.required, for: .vertical)

        clearCommentButton.bezelStyle = .rounded
        clearCommentButton.controlSize = .small
        clearCommentButton.target = self
        clearCommentButton.action = #selector(clearComment(_:))
        clearCommentButton.translatesAutoresizingMaskIntoConstraints = false
        clearCommentButton.setContentCompressionResistancePriority(.required, for: .vertical)

        container.addSubview(scrollView)
        container.addSubview(emptyStateLabel)
        container.addSubview(detailDivider)
        container.addSubview(detailContainer)

        for subview in [snippetLabel, metaLabel, commentLabel, commentScrollView, applyCommentButton, clearCommentButton] {
            detailContainer.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),

            emptyStateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyStateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            emptyStateLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            detailDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            detailContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            detailContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            detailContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            detailContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 174),

            scrollView.bottomAnchor.constraint(equalTo: detailDivider.topAnchor),
            detailDivider.bottomAnchor.constraint(equalTo: detailContainer.topAnchor, constant: -8),

            snippetLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: detailContainer.topAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 4),

            commentLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            commentLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 10),

            commentScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            commentScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            commentScrollView.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: 6),
            commentScrollView.bottomAnchor.constraint(equalTo: applyCommentButton.topAnchor, constant: -8),
            commentScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            applyCommentButton.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            applyCommentButton.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),

            clearCommentButton.centerYAnchor.constraint(equalTo: applyCommentButton.centerYAnchor),
            clearCommentButton.trailingAnchor.constraint(equalTo: applyCommentButton.leadingAnchor, constant: -8),
        ])

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
            tableView.backgroundColor = PlaceholderViewController.paneBackgroundColor
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildRows()
    }

    @objc
    private func handleRowAction(_ sender: Any?) {
        guard let group = selectedGroup() else { return }
        currentGroupID = group.groupID
        onActivateHighlight?(group)
    }

    @objc
    private func applyComment(_ sender: Any?) {
        guard let group = currentGroup(),
              let sessionID = documentStore.activeSessionID(in: windowID) else { return }
        _ = documentStore.updateComment(commentTextView.string, forHighlightGroup: group.groupID, in: sessionID)
    }

    @objc
    private func clearComment(_ sender: Any?) {
        guard currentGroup() != nil else { return }
        commentTextView.string = ""
        updateCommentButtons()
        applyComment(sender)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .highlight = rows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 24 }
        switch rows[row] {
        case .section:
            return 26
        case .highlight:
            return 46
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedGroup = selectedGroup() else {
            updateCommentButtons()
            return
        }
        currentGroupID = selectedGroup.groupID
        updateDetail()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case let .section(title):
            let identifier = NSUserInterfaceItemIdentifier("AnnotationSectionCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeSectionCell(identifier: identifier)
            cell.textField?.stringValue = title
            return cell
        case let .highlight(group):
            let identifier = NSUserInterfaceItemIdentifier("AnnotationHighlightCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AnnotationHighlightCellView
                ?? AnnotationHighlightCellView()
            cell.identifier = identifier
            cell.configure(with: group)
            return cell
        }
    }

    func textDidChange(_ notification: Notification) {
        updateCommentButtons()
    }

    private func rebuildRows() {
        guard isViewLoaded else { return }
        let previousGroupID = currentGroupID ?? selectedGroup()?.groupID
        rows = documentStore.annotationSections(in: windowID).flatMap { section in
            [AnnotationRow.section(section.title)] + section.highlights.map { .highlight($0) }
        }
        tableView.reloadData()

        let isEmpty = rows.isEmpty
        emptyStateLabel.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
        detailDivider.isHidden = isEmpty
        detailContainer.isHidden = isEmpty

        if let previousGroupID,
           let row = rowIndex(for: previousGroupID) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else if let firstRow = firstHighlightRow() {
            tableView.selectRowIndexes(IndexSet(integer: firstRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(firstRow)
        }

        updateDetail()
    }

    private func updateDetail() {
        guard let group = currentGroup() else {
            currentGroupID = nil
            snippetLabel.stringValue = ""
            metaLabel.stringValue = ""
            commentTextView.string = ""
            detailContainer.isHidden = rows.isEmpty
            updateCommentButtons()
            return
        }

        currentGroupID = group.groupID
        snippetLabel.stringValue = group.snippet
        let dateText: String
        if let createdAt = group.createdAt {
            dateText = DateFormatter.annotationSidebarFormatter.string(from: createdAt)
        } else {
            dateText = "Unknown date"
        }
        metaLabel.stringValue = "Page \(group.pageIndex + 1) · \(group.color.menuTitle) · \(dateText)"
        commentTextView.string = group.comment
        updateCommentButtons()
    }

    private func updateCommentButtons() {
        guard let group = currentGroup() else {
            applyCommentButton.isEnabled = false
            clearCommentButton.isEnabled = false
            return
        }

        let currentComment = commentTextView.string
        applyCommentButton.isEnabled = currentComment != group.comment
        clearCommentButton.isEnabled = currentComment.isEmpty == false || group.comment.isEmpty == false
    }

    private func selectedGroup() -> DocumentHighlightGroup? {
        guard rows.indices.contains(tableView.selectedRow) else { return nil }
        if case let .highlight(group) = rows[tableView.selectedRow] {
            return group
        }
        return nil
    }

    private func currentGroup() -> DocumentHighlightGroup? {
        if let currentGroupID,
           let group = group(for: currentGroupID) {
            return group
        }
        return selectedGroup()
    }

    private func firstHighlightRow() -> Int? {
        rows.firstIndex {
            if case .highlight = $0 { return true }
            return false
        }
    }

    private func group(for groupID: String) -> DocumentHighlightGroup? {
        for row in rows {
            guard case let .highlight(group) = row else { continue }
            if group.groupID == groupID {
                return group
            }
        }
        return nil
    }

    private func rowIndex(for groupID: String) -> Int? {
        rows.firstIndex { row in
            guard case let .highlight(group) = row else { return false }
            return group.groupID == groupID
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
}

private extension DateFormatter {
    static let annotationSidebarFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
