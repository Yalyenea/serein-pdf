import AppKit

private enum AnnotationRow {
    case section(String)
    case highlight(DocumentHighlightGroup)
}

private final class AnnotationTableView: NSTableView {
    var onMoveSelection: ((Int) -> Void)?
    var onBeginEditing: (() -> Void)?
    var onDeleteSelection: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopySelection?()
            return
        }
        guard modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onBeginEditing?()
        case 51, 117: // delete / forward delete
            onDeleteSelection?()
        case 2: // D
            onDeleteSelection?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0, selectedRow != row {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?()
    }
}

private final class AnnotationRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let color = NightModeStyle.primaryTextColor.withAlphaComponent(isEmphasized ? 0.09 : 0.065)
        color.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 0.5),
            xRadius: 5,
            yRadius: 5
        ).fill()
    }
}

private final class AnnotationColorBarView: NSView {
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
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

private final class AnnotationCommentTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return
        }
        if modifiers.isEmpty, event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

final class AnnotationHighlightCellView: NSTableCellView {
    private static let snippetFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    private static let commentFont = NSFont.systemFont(ofSize: 11.5)
    static let snippetMaxLines = 0
    static let commentMaxLines = 16
    private static let heightSafetyMaxLines: CGFloat = 40
    private static let colorBarLeading: CGFloat = 4
    private static let colorBarWidth: CGFloat = 2.5
    private static let contentLeadingInset: CGFloat = 12
    private static let contentTrailingInset: CGFloat = 6
    private static let verticalPadding: CGFloat = 6
    private static let stackSpacing: CGFloat = 3
    private static let editorHeight: CGFloat = 64
    private static let editorFooterHeight: CGFloat = 20

    private let colorBarView = AnnotationColorBarView()
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let commentLabel = NSTextField(wrappingLabelWithString: "")
    private let editorScrollView = NSScrollView()
    private let commentTextView = AnnotationCommentTextView()
    private let editorFooter = NSView()
    private let shortcutLabel = NSTextField(labelWithString: "⌘↩ Save  ·  Esc Cancel")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var representedGroupID: String?
    private var isEditingComment = false
    private var onSave: ((String) -> Void)?
    private var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Frame layout only — Auto Layout + preferredMaxLayoutWidth fights NSTableView row height.
        clipsToBounds = true

        colorBarView.wantsLayer = true

        Self.styleWrappingLabel(snippetLabel, font: Self.snippetFont, color: NightModeStyle.primaryTextColor)
        Self.styleWrappingLabel(commentLabel, font: Self.commentFont, color: NightModeStyle.secondaryTextColor)

        commentTextView.isRichText = false
        commentTextView.usesFontPanel = false
        commentTextView.isAutomaticQuoteSubstitutionEnabled = false
        commentTextView.isEditable = true
        commentTextView.isSelectable = true
        commentTextView.isHorizontallyResizable = false
        commentTextView.isVerticallyResizable = true
        commentTextView.allowsUndo = true
        commentTextView.font = Self.commentFont
        commentTextView.backgroundColor = .clear
        commentTextView.textContainerInset = NSSize(width: 5, height: 5)
        commentTextView.textContainer?.widthTracksTextView = true
        commentTextView.onCommit = { [weak self] in self?.saveComment() }
        commentTextView.onCancel = { [weak self] in self?.onCancel?() }

        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = NightModeStyle.primaryTextColor.withAlphaComponent(0.035)
        editorScrollView.borderType = .noBorder
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.hasVerticalScroller = true
        editorScrollView.autohidesScrollers = true
        editorScrollView.horizontalScrollElasticity = .none
        editorScrollView.documentView = commentTextView
        editorScrollView.wantsLayer = true
        editorScrollView.layer?.cornerRadius = 5

        shortcutLabel.font = .systemFont(ofSize: 9.5)
        shortcutLabel.textColor = NightModeStyle.tertiaryTextColor

        saveButton.bezelStyle = .recessed
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        saveButton.target = self
        saveButton.action = #selector(handleSave(_:))

        editorFooter.addSubview(shortcutLabel)
        editorFooter.addSubview(saveButton)

        addSubview(colorBarView)
        addSubview(snippetLabel)
        addSubview(commentLabel)
        addSubview(editorScrollView)
        addSubview(editorFooter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        with group: DocumentHighlightGroup,
        isEditing: Bool = false,
        onSave: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        representedGroupID = group.groupID
        self.onSave = onSave
        self.onCancel = onCancel
        isEditingComment = isEditing
        colorBarView.color = group.color.nsColor
        snippetLabel.stringValue = group.snippet
        commentLabel.stringValue = group.normalizedComment
        commentLabel.isHidden = isEditing || group.normalizedComment.isEmpty
        editorScrollView.isHidden = isEditing == false
        editorFooter.isHidden = isEditing == false
        if isEditing {
            commentTextView.identifier = NSUserInterfaceItemIdentifier("AnnotationCommentEditor.\(group.groupID)")
            commentTextView.string = group.comment
        }
        let tooltipParts = [group.snippet, group.normalizedComment].filter { $0.isEmpty == false }
        toolTip = tooltipParts.isEmpty ? nil : tooltipParts.joined(separator: "\n\n")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1 else { return }

        let textX = Self.contentLeadingInset
        let textW = max(width - Self.contentLeadingInset - Self.contentTrailingInset, 1)
        let top = height - Self.verticalPadding

        colorBarView.frame = NSRect(
            x: Self.colorBarLeading,
            y: Self.verticalPadding,
            width: Self.colorBarWidth,
            height: max(height - Self.verticalPadding * 2, 1)
        )

        // preferredMaxLayoutWidth must match the frame width used for drawing, not a stale AL width.
        snippetLabel.preferredMaxLayoutWidth = textW
        commentLabel.preferredMaxLayoutWidth = textW

        let snippetH = Self.measuredHeight(
            for: snippetLabel.stringValue,
            font: Self.snippetFont,
            width: textW,
            maximumLines: Self.snippetMaxLines
        )
        var cursorY = top - snippetH
        snippetLabel.frame = NSRect(x: textX, y: cursorY, width: textW, height: snippetH)

        if isEditingComment {
            cursorY -= Self.stackSpacing + Self.editorHeight
            editorScrollView.frame = NSRect(x: textX, y: cursorY, width: textW, height: Self.editorHeight)
            commentTextView.frame = NSRect(x: 0, y: 0, width: textW, height: Self.editorHeight)
            commentTextView.textContainer?.containerSize = NSSize(
                width: max(textW - 10, 1),
                height: CGFloat.greatestFiniteMagnitude
            )

            cursorY -= Self.stackSpacing + Self.editorFooterHeight
            editorFooter.frame = NSRect(x: textX, y: cursorY, width: textW, height: Self.editorFooterHeight)
            saveButton.sizeToFit()
            let saveSize = saveButton.frame.size
            saveButton.frame = NSRect(
                x: textW - saveSize.width,
                y: (Self.editorFooterHeight - saveSize.height) / 2,
                width: saveSize.width,
                height: saveSize.height
            )
            shortcutLabel.sizeToFit()
            shortcutLabel.frame = NSRect(
                x: 0,
                y: (Self.editorFooterHeight - shortcutLabel.frame.height) / 2,
                width: max(textW - saveSize.width - 6, 1),
                height: shortcutLabel.frame.height
            )
        } else if commentLabel.isHidden == false {
            let commentH = Self.measuredHeight(
                for: commentLabel.stringValue,
                font: Self.commentFont,
                width: textW,
                maximumLines: Self.commentMaxLines
            )
            cursorY -= Self.stackSpacing + commentH
            commentLabel.frame = NSRect(x: textX, y: cursorY, width: textW, height: commentH)
        }
    }

    @discardableResult
    func focusEditor() -> Bool {
        guard editorScrollView.isHidden == false else { return false }
        return window?.makeFirstResponder(commentTextView) ?? false
    }

    var editingComment: String? {
        editorScrollView.isHidden ? nil : commentTextView.string
    }

    /// `width` is the full table column / cell width (not text-only width).
    static func preferredHeight(
        for group: DocumentHighlightGroup,
        width: CGFloat,
        isEditing: Bool = false
    ) -> CGFloat {
        let textW = max(width - contentLeadingInset - contentTrailingInset, 1)
        let snippetH = measuredHeight(
            for: group.snippet,
            font: snippetFont,
            width: textW,
            maximumLines: snippetMaxLines
        )
        var bodyH: CGFloat = 0
        var gaps: CGFloat = 0
        if isEditing {
            bodyH = editorHeight + editorFooterHeight
            gaps = stackSpacing * 2
        } else if group.normalizedComment.isEmpty == false {
            bodyH = measuredHeight(
                for: group.normalizedComment,
                font: commentFont,
                width: textW,
                maximumLines: commentMaxLines
            )
            gaps = stackSpacing
        }
        return ceil(verticalPadding * 2 + snippetH + bodyH + gaps)
    }

    @objc
    private func handleSave(_ sender: Any?) {
        saveComment()
    }

    private func saveComment() {
        guard representedGroupID != nil else { return }
        onSave?(commentTextView.string)
    }

    private static func styleWrappingLabel(_ label: NSTextField, font: NSFont, color: NSColor) {
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        label.cell?.truncatesLastVisibleLine = false
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.refusesFirstResponder = true
    }

    /// `maximumLines == 0` → natural height, soft-capped for safety.
    static func measuredHeight(
        for text: String,
        font: NSFont,
        width: CGFloat,
        maximumLines: Int
    ) -> CGFloat {
        guard text.isEmpty == false else { return lineHeight(for: font) }
        let usableWidth = max(width, 1)
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let natural = max(ceil(rect.height), lineHeight(for: font))
        let lineCap = maximumLines > 0 ? CGFloat(maximumLines) : heightSafetyMaxLines
        return min(natural, lineHeight(for: font) * lineCap)
    }

    private static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}

final class AnnotationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private struct SourceFingerprint: Equatable {
        let sessionID: UUID?
        let fileSnapshot: PDFFileSnapshot?
        let isCacheLoaded: Bool
    }

    private static let horizontalInset: CGFloat = 2
    private static let textInset: CGFloat = 10

    let documentStore: DocumentStore
    let windowID: UUID
    var onActivateHighlight: ((DocumentHighlightGroup) -> Void)?
    var onDeleteHighlight: ((DocumentHighlightGroup) -> Void)?
    var onChangeHighlightColor: ((DocumentHighlightGroup, HighlightColor) -> Void)?
    var onSelectionDidChange: ((String?) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = AnnotationTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AnnotationColumn"))
    private let emptyStateLabel = NSTextField(labelWithString: "No annotations")
    private var rows: [AnnotationRow] = []
    private var currentGroupID: String?
    private var editingGroupID: String?
    private var editingSessionID: UUID?
    private var lastMeasuredTableWidth: CGFloat = 0
    private var displayedSourceFingerprint: SourceFingerprint?

    var selectedGroupID: String? {
        currentGroupID ?? selectedGroup()?.groupID
    }

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

    override func viewDidLayout() {
        super.viewDidLayout()
        syncTableColumnWidthAndRowHeights()
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        column.isEditable = false
        column.resizingMask = .autoresizingMask
        column.minWidth = 60
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(handleRowAction(_:))
        tableView.doubleAction = #selector(handleDoubleClick(_:))
        tableView.onMoveSelection = { [weak self] delta in self?.moveSelection(by: delta) }
        tableView.onBeginEditing = { [weak self] in self?.beginEditingSelectedGroup() }
        tableView.onDeleteSelection = { [weak self] in self?.deleteSelectedGroup() }
        tableView.onCopySelection = { [weak self] in self?.copySelectedSnippet() }
        tableView.menuProvider = { [weak self] in self?.makeContextMenu() }
        tableView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tableView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = NightModeStyle.secondaryTextColor
        emptyStateLabel.maximumNumberOfLines = 0
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        emptyStateLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

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
            view.layer?.backgroundColor = NSColor.clear.cgColor
            tableView.backgroundColor = .clear
            emptyStateLabel.textColor = NightModeStyle.secondaryTextColor
        }
        tableView.reloadData()
    }

    func reveal(groupID: String, focusEditor: Bool) {
        loadViewIfNeeded()
        if rowIndex(for: groupID) == nil {
            rebuildRows()
        }
        guard let row = rowIndex(for: groupID) else { return }

        currentGroupID = groupID
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        guard focusEditor else { return }
        beginEditing(groupID: groupID)
        view.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(row)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        let change = notification.documentStoreChange
        guard change.intersection([.content, .tabs, .annotations]).isEmpty == false else { return }
        if change == .all, displayedSourceFingerprint == sourceFingerprint() {
            return
        }
        if let editingGroupID {
            _ = commitEditing(groupID: editingGroupID)
        }
        rebuildRows()
    }

    @objc
    private func handleRowAction(_ sender: Any?) {
        guard let group = selectedGroup() else { return }
        currentGroupID = group.groupID
        onSelectionDidChange?(group.groupID)
        onActivateHighlight?(group)
    }

    @objc
    private func handleDoubleClick(_ sender: Any?) {
        beginEditingSelectedGroup()
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
            return 22
        case let .highlight(group):
            // Must use the same single width as cell layout — never max() of several
            // candidates, or height underestimates wrap and clips to one partial line.
            return AnnotationHighlightCellView.preferredHeight(
                for: group,
                width: tableContentWidth(),
                isEditing: editingGroupID == group.groupID
            )
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedGroup = selectedGroup() else {
            currentGroupID = nil
            onSelectionDidChange?(nil)
            return
        }
        let previousEditingGroupID = editingGroupID
        currentGroupID = selectedGroup.groupID
        onSelectionDidChange?(selectedGroup.groupID)
        guard let previousEditingGroupID,
              previousEditingGroupID != selectedGroup.groupID else { return }
        if commitEditing(groupID: previousEditingGroupID) {
            return
        }
        editingGroupID = nil
        reloadHighlightRow(groupID: previousEditingGroupID)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        AnnotationRowView()
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
            cell.configure(
                with: group,
                isEditing: editingGroupID == group.groupID,
                onSave: { [weak self] comment in
                    self?.save(comment: comment, for: group.groupID)
                },
                onCancel: { [weak self] in
                    self?.endEditing(groupID: group.groupID)
                }
            )
            // Force frame layout with the live column width before first paint.
            let w = tableContentWidth()
            if w > 1 {
                cell.frame.size.width = w
                cell.needsLayout = true
                cell.layoutSubtreeIfNeeded()
            }
            return cell
        }
    }

    /// Single source of truth for column/cell width used by height + layout.
    /// Prefer the scroll view's own bounds (pane width), not documentView size,
    /// which can lag and create a feedback loop with column sizing.
    private func tableContentWidth() -> CGFloat {
        if scrollView.bounds.width > 1 {
            return floor(scrollView.bounds.width)
        }
        if view.bounds.width > 1 {
            return floor(max(view.bounds.width - Self.horizontalInset * 2, 1))
        }
        if column.width > 1 { return floor(column.width) }
        return 1
    }

    private func rebuildRows() {
        guard isViewLoaded else { return }
        let previousGroupID = currentGroupID ?? selectedGroup()?.groupID
        rows = documentStore.annotationSections(in: windowID).flatMap { section in
            [AnnotationRow.section(section.title)] + section.highlights.map { .highlight($0) }
        }
        displayedSourceFingerprint = sourceFingerprint()
        if let editingGroupID, group(for: editingGroupID) == nil {
            self.editingGroupID = nil
            editingSessionID = nil
        }
        tableView.reloadData()

        let isEmpty = rows.isEmpty
        emptyStateLabel.stringValue = emptyStateText()
        emptyStateLabel.isHidden = isEmpty == false
        scrollView.isHidden = isEmpty

        if let previousGroupID,
           let row = rowIndex(for: previousGroupID) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else if let firstRow = firstHighlightRow() {
            tableView.selectRowIndexes(IndexSet(integer: firstRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(firstRow)
        } else {
            currentGroupID = nil
            onSelectionDidChange?(nil)
        }
    }

    private func sourceFingerprint() -> SourceFingerprint {
        let session = documentStore.activeSession(in: windowID)
        return SourceFingerprint(
            sessionID: session?.id,
            fileSnapshot: session?.fileSnapshot,
            isCacheLoaded: session?.isAnnotationCacheLoaded == true
        )
    }

    private func emptyStateText() -> String {
        let actions: [(String, ShortcutCommand)] = [
            ("Select text", .highlightSelection),
            ("Comment", .addComment),
        ]
        let hints = actions.compactMap { title, command in
            documentStore.appConfiguration.shortcuts.bindings[command].map {
                "\(title) · \($0.displayString)"
            }
        }
        return (["No annotations"] + hints).joined(separator: "\n")
    }

    private func moveSelection(by delta: Int) {
        guard delta != 0 else { return }
        var candidate = tableView.selectedRow
        if candidate < 0 {
            candidate = delta > 0 ? -1 : rows.count
        }

        while true {
            candidate += delta
            guard rows.indices.contains(candidate) else { return }
            guard case let .highlight(group) = rows[candidate] else { continue }
            tableView.selectRowIndexes(IndexSet(integer: candidate), byExtendingSelection: false)
            tableView.scrollRowToVisible(candidate)
            currentGroupID = group.groupID
            onActivateHighlight?(group)
            return
        }
    }

    private func beginEditingSelectedGroup() {
        guard let group = selectedGroup() else { return }
        beginEditing(groupID: group.groupID)
    }

    private func deleteSelectedGroup() {
        guard let group = selectedGroup() else { return }
        if editingGroupID == group.groupID {
            editingGroupID = nil
            editingSessionID = nil
        }
        onDeleteHighlight?(group)
    }

    private func copySelectedSnippet() {
        guard let group = selectedGroup(), group.snippet.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(group.snippet, forType: .string)
    }

    private func makeContextMenu() -> NSMenu? {
        guard let group = selectedGroup() else { return nil }
        let menu = NSMenu(title: "Annotation")
        menu.autoenablesItems = false

        let editItem = NSMenuItem(title: "Edit Comment", action: #selector(contextEditComment(_:)), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let copyItem = NSMenuItem(title: "Copy Snippet", action: #selector(contextCopySnippet(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let colorMenu = NSMenu(title: "Color")
        for color in HighlightColor.allCases {
            let item = NSMenuItem(
                title: color.menuTitle,
                action: #selector(contextChangeColor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = color.rawValue
            item.state = color == group.color ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc
    private func contextEditComment(_ sender: Any?) {
        beginEditingSelectedGroup()
    }

    @objc
    private func contextCopySnippet(_ sender: Any?) {
        copySelectedSnippet()
    }

    @objc
    private func contextChangeColor(_ sender: NSMenuItem) {
        guard let group = selectedGroup(),
              let raw = sender.representedObject as? String,
              let color = HighlightColor(rawValue: raw) else { return }
        onChangeHighlightColor?(group, color)
    }

    @objc
    private func contextDelete(_ sender: Any?) {
        deleteSelectedGroup()
    }

    private func beginEditing(groupID: String) {
        guard let row = rowIndex(for: groupID),
              let sessionID = documentStore.activeSessionID(in: windowID) else { return }
        let previousEditingGroupID = editingGroupID
        editingGroupID = groupID
        editingSessionID = sessionID
        if let previousEditingGroupID, previousEditingGroupID != groupID {
            reloadHighlightRow(groupID: previousEditingGroupID)
        }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integer: 0)
        )
        view.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(row)
        let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? AnnotationHighlightCellView
        _ = cell?.focusEditor()
    }

    private func save(comment: String, for groupID: String) {
        guard editingGroupID == groupID,
              let sessionID = editingSessionID else { return }
        editingGroupID = nil
        editingSessionID = nil
        _ = documentStore.updateComment(comment, forHighlightGroup: groupID, in: sessionID)
        reloadHighlightRow(groupID: groupID)
    }

    private func commitEditing(groupID: String) -> Bool {
        guard let row = rowIndex(for: groupID),
              let cell = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: true
              ) as? AnnotationHighlightCellView,
              let comment = cell.editingComment,
              let sessionID = editingSessionID else { return false }

        editingGroupID = nil
        editingSessionID = nil
        let didChange = documentStore.updateComment(
            comment,
            forHighlightGroup: groupID,
            in: sessionID
        )
        if didChange == false {
            reloadHighlightRow(groupID: groupID)
        }
        return true
    }

    private func endEditing(groupID: String) {
        guard editingGroupID == groupID else { return }
        editingGroupID = nil
        editingSessionID = nil
        reloadHighlightRow(groupID: groupID)
        tableView.window?.makeFirstResponder(tableView)
    }

    private func reloadHighlightRow(groupID: String) {
        guard let row = rowIndex(for: groupID) else { return }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    private func syncTableColumnWidthAndRowHeights() {
        let targetWidth = tableContentWidth()
        guard targetWidth > 1 else { return }

        column.minWidth = targetWidth
        column.maxWidth = targetWidth
        column.width = targetWidth

        var tableFrame = tableView.frame
        if abs(tableFrame.width - targetWidth) > 0.5 {
            tableFrame.size.width = targetWidth
            tableView.frame = tableFrame
        }
        if scrollView.contentView.bounds.origin.x != 0 {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
        }

        guard abs(lastMeasuredTableWidth - targetWidth) > 0.5 else { return }
        lastMeasuredTableWidth = targetWidth

        // Width changed → recompute every highlight row height with the new wrap width.
        let highlightRows = IndexSet(
            rows.enumerated().compactMap { index, row in
                if case .highlight = row {
                    return index
                }
                return nil
            }
        )
        guard highlightRows.isEmpty == false else { return }
        tableView.noteHeightOfRows(withIndexesChanged: highlightRows)
        tableView.enumerateAvailableRowViews { _, row in
            guard rows.indices.contains(row), case .highlight = rows[row] else { return }
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? AnnotationHighlightCellView {
                cell.needsLayout = true
                cell.layoutSubtreeIfNeeded()
            }
        }
    }

    private func selectedGroup() -> DocumentHighlightGroup? {
        guard rows.indices.contains(tableView.selectedRow) else { return nil }
        if case let .highlight(group) = rows[tableView.selectedRow] {
            return group
        }
        return nil
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
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = NightModeStyle.secondaryTextColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
