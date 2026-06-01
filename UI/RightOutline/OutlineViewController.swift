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

private final class OutlineScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let isHorizontalOnly = abs(event.scrollingDeltaX) > 0.1 && abs(event.scrollingDeltaY) < 0.1
        guard isHorizontalOnly == false else {
            lockHorizontalPosition()
            return
        }

        super.scrollWheel(with: event)
        lockHorizontalPosition()
    }

    func lockHorizontalPosition() {
        let currentBounds = contentView.bounds
        guard currentBounds.origin.x != 0 else { return }
        contentView.scroll(to: NSPoint(x: 0, y: currentBounds.origin.y))
        reflectScrolledClipView(contentView)
    }
}

private final class OutlineDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class OutlineRowTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        if let rowView = enclosingOutlineRowView {
            rowView.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    private var enclosingOutlineRowView: OutlineRowView? {
        var next: NSView? = superview
        while let view = next {
            if let rowView = view as? OutlineRowView {
                return rowView
            }
            next = view.superview
        }
        return nil
    }
}

final class OutlineRowView: NSControl {
    static let rowIdentifierPrefix = "outlineRow"

    private static let minimumHeight: CGFloat = 22
    private static let horizontalPadding: CGFloat = 6
    private static let verticalPadding: CGFloat = 3
    private static let indentationPerLevel: CGFloat = 13
    private static let disclosureSize: CGFloat = 14
    private static let disclosureTextSpacing: CGFloat = 3

    let node: OutlineNode
    let path: [Int]
    let textField: NSTextField = OutlineRowTextField(labelWithString: "")
    private let disclosureButton = NSButton()
    private let onActivate: (OutlineNode) -> Void
    private let onToggleExpansion: () -> Void
    private var isRowSelected: Bool

    init(
        node: OutlineNode,
        path: [Int],
        level: Int,
        attributedTitle: NSAttributedString,
        isExpandable: Bool,
        isExpanded: Bool,
        isSelected: Bool,
        onActivate: @escaping (OutlineNode) -> Void,
        onToggleExpansion: @escaping () -> Void
    ) {
        self.node = node
        self.path = path
        self.onActivate = onActivate
        self.onToggleExpansion = onToggleExpansion
        self.isRowSelected = isSelected
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier(Self.identifier(for: path))
        wantsLayer = true
        layer?.cornerRadius = 5
        setAccessibilityElement(true)
        setAccessibilityLabel(node.title)
        setAccessibilityRole(.button)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        disclosureButton.identifier = NSUserInterfaceItemIdentifier("outlineDisclosureButton-\(Self.pathKey(path))")
        disclosureButton.isBordered = false
        disclosureButton.bezelStyle = .regularSquare
        disclosureButton.imagePosition = .imageOnly
        disclosureButton.controlSize = .mini
        disclosureButton.focusRingType = .none
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleExpansion(_:))
        disclosureButton.setButtonType(.momentaryChange)
        disclosureButton.isEnabled = isExpandable
        disclosureButton.alphaValue = isExpandable ? 1 : 0
        disclosureButton.image = isExpandable
            ? NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: isExpanded ? "Collapse section" : "Expand section"
            )
            : nil
        disclosureButton.contentTintColor = NightModeStyle.secondaryTextColor
        disclosureButton.toolTip = isExpanded ? "Collapse section" : "Expand section"

        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byCharWrapping
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.cell?.usesSingleLineMode = false
        textField.cell?.lineBreakMode = .byCharWrapping
        textField.cell?.truncatesLastVisibleLine = false
        textField.attributedStringValue = attributedTitle
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        for view in [disclosureButton, textField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let leading = Self.horizontalPadding + CGFloat(level) * Self.indentationPerLevel
        NSLayoutConstraint.activate([
            disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            disclosureButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            disclosureButton.widthAnchor.constraint(equalToConstant: Self.disclosureSize),
            disclosureButton.heightAnchor.constraint(equalToConstant: Self.disclosureSize),

            textField.leadingAnchor.constraint(
                equalTo: disclosureButton.trailingAnchor,
                constant: Self.disclosureTextSpacing
            ),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),

            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),
        ])

        updateSelectionAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func identifier(for path: [Int]) -> String {
        "\(rowIdentifierPrefix)-\(pathKey(path))"
    }

    static func pathKey(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: "-")
    }

    func setSelected(_ selected: Bool) {
        guard isRowSelected != selected else { return }
        isRowSelected = selected
        updateSelectionAppearance()
    }

    func performPrimaryAction() {
        activate()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        activate()
    }

    override func layout() {
        super.layout()
        textField.preferredMaxLayoutWidth = textField.bounds.width
    }

    private func activate() {
        onActivate(node)
    }

    @objc
    private func toggleExpansion(_ sender: NSButton) {
        onToggleExpansion()
    }

    private func updateSelectionAppearance() {
        layer?.backgroundColor = isRowSelected
            ? NightModeStyle.selectedChromeBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }
}

final class OutlineViewController: NSViewController {
    private struct VisibleRow {
        let node: OutlineNode
        let path: [Int]
        let level: Int
    }

    private static let outlineFontSize: CGFloat = 13
    private static let wrappedLineHeight: CGFloat = 14

    let documentStore: DocumentStore
    let windowID: UUID
    private let titleLabel = NSTextField(labelWithString: "Outline")
    private let expansionToggleButton = NSButton()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF with a table of contents to see it here.")
    private let scrollView = OutlineScrollView()
    private let outlineDocumentView = OutlineDocumentView()
    private let rowsStackView = NSStackView()
    private let pageCounterLabel = NSTextField(labelWithString: "")
    private var nodes: [OutlineNode] = []
    private var displayedSessionID: UUID?
    private var collapsedPaths = Set<[Int]>()
    private var selectedPath: [Int]?

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
        syncOutlineContentFrame()
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
        emptyStateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pageCounterLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pageCounterLabel.textColor = NightModeStyle.secondaryTextColor
        pageCounterLabel.alignment = .right

        rowsStackView.identifier = NSUserInterfaceItemIdentifier("outlineRowsStack")
        rowsStackView.orientation = .vertical
        rowsStackView.alignment = .leading
        rowsStackView.distribution = .fill
        rowsStackView.spacing = 1
        rowsStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        rowsStackView.translatesAutoresizingMaskIntoConstraints = false
        rowsStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        outlineDocumentView.identifier = NSUserInterfaceItemIdentifier("outlineDocumentView")
        outlineDocumentView.wantsLayer = true
        outlineDocumentView.layer?.backgroundColor = NSColor.clear.cgColor
        outlineDocumentView.addSubview(rowsStackView)

        NSLayoutConstraint.activate([
            rowsStackView.leadingAnchor.constraint(equalTo: outlineDocumentView.leadingAnchor),
            rowsStackView.trailingAnchor.constraint(equalTo: outlineDocumentView.trailingAnchor),
            rowsStackView.topAnchor.constraint(equalTo: outlineDocumentView.topAnchor),
            rowsStackView.bottomAnchor.constraint(equalTo: outlineDocumentView.bottomAnchor),
        ])

        scrollView.identifier = NSUserInterfaceItemIdentifier("outlineScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView = OutlineClipView()
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.documentView = outlineDocumentView

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
            outlineDocumentView.layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.contentView.backgroundColor = .clear
            titleLabel.textColor = NightModeStyle.primaryTextColor
            expansionToggleButton.contentTintColor = NightModeStyle.secondaryTextColor
            emptyStateLabel.textColor = NightModeStyle.secondaryTextColor
            pageCounterLabel.textColor = NightModeStyle.secondaryTextColor
        }
        renderOutlineRows()
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
        collapsedPaths = collapsedPaths.intersection(allExpandablePaths())
        selectedPath = nil
        renderOutlineRows()

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

    private func renderOutlineRows() {
        rowsStackView.arrangedSubviews.forEach { subview in
            rowsStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for row in visibleRows() {
            let rowView = OutlineRowView(
                node: row.node,
                path: row.path,
                level: row.level,
                attributedTitle: attributedTitle(for: row.node),
                isExpandable: row.node.children.isEmpty == false,
                isExpanded: collapsedPaths.contains(row.path) == false,
                isSelected: selectedPath == row.path,
                onActivate: { [weak self] node in
                    self?.activate(node: node, at: row.path)
                },
                onToggleExpansion: { [weak self] in
                    self?.toggleNodeExpansion(at: row.path)
                }
            )
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowsStackView.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: rowsStackView.widthAnchor).isActive = true
        }

        updateExpansionToggleButton()
        view.needsLayout = true
        syncOutlineContentFrame()
    }

    private func syncOutlineContentFrame() {
        guard isViewLoaded else { return }

        let visibleWidth = max(scrollView.contentSize.width, scrollView.bounds.width, 1)
        let currentHeight = max(outlineDocumentView.frame.height, scrollView.contentSize.height)
        if abs(outlineDocumentView.frame.width - visibleWidth) > 0.5 {
            outlineDocumentView.setFrameSize(NSSize(width: visibleWidth, height: currentHeight))
        }

        outlineDocumentView.layoutSubtreeIfNeeded()
        let fittingHeight = max(ceil(rowsStackView.fittingSize.height), scrollView.contentSize.height)
        if abs(outlineDocumentView.frame.height - fittingHeight) > 0.5 ||
            abs(outlineDocumentView.frame.width - visibleWidth) > 0.5 {
            outlineDocumentView.setFrameSize(NSSize(width: visibleWidth, height: fittingHeight))
            outlineDocumentView.layoutSubtreeIfNeeded()
        }

        scrollView.lockHorizontalPosition()
    }

    private func activate(node: OutlineNode, at path: [Int]) {
        selectedPath = path
        updateSelectionHighlights()

        guard let pageIndex = node.pageIndex else { return }
        let targetSessionID = node.sourceSessionID ?? documentStore.activeSessionID(in: windowID)
        guard let targetSessionID else { return }
        documentStore.updateCurrentPage(index: pageIndex, for: targetSessionID)
        if documentStore.activeSessionID(in: windowID) != targetSessionID {
            documentStore.activate(sessionID: targetSessionID, in: windowID)
        }
    }

    private func updateSelectionHighlights() {
        for case let rowView as OutlineRowView in rowsStackView.arrangedSubviews {
            rowView.setSelected(rowView.path == selectedPath)
        }
    }

    private func toggleNodeExpansion(at path: [Int]) {
        if collapsedPaths.contains(path) {
            collapsedPaths.remove(path)
        } else {
            collapsedPaths.insert(path)
        }
        renderOutlineRows()
    }

    @objc
    private func toggleOutlineExpansion(_ sender: NSButton) {
        let expandablePaths = allExpandablePaths()
        guard expandablePaths.isEmpty == false else { return }

        if collapsedPaths.isEmpty {
            collapsedPaths = expandablePaths
        } else {
            collapsedPaths.removeAll()
        }
        renderOutlineRows()
    }

    private func updateExpansionToggleButton() {
        let expandablePaths = allExpandablePaths()
        expansionToggleButton.isEnabled = expandablePaths.isEmpty == false
        let hasCollapsedRows = collapsedPaths.isEmpty == false
        let symbolName = hasCollapsedRows ? "chevron.right" : "chevron.down"
        let accessibilityDescription = hasCollapsedRows ? "Expand outline" : "Collapse outline"
        expansionToggleButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        expansionToggleButton.toolTip = accessibilityDescription
        expansionToggleButton.contentTintColor = NightModeStyle.secondaryTextColor
    }

    private func visibleRows() -> [VisibleRow] {
        var rows: [VisibleRow] = []

        func append(nodes: [OutlineNode], level: Int, prefix: [Int]) {
            for (index, node) in nodes.enumerated() {
                let path = prefix + [index]
                rows.append(VisibleRow(node: node, path: path, level: level))
                if node.children.isEmpty == false, collapsedPaths.contains(path) == false {
                    append(nodes: node.children, level: level + 1, prefix: path)
                }
            }
        }

        append(nodes: nodes, level: 0, prefix: [])
        return rows
    }

    private func allExpandablePaths() -> Set<[Int]> {
        var paths = Set<[Int]>()

        func collect(nodes: [OutlineNode], prefix: [Int]) {
            for (index, node) in nodes.enumerated() {
                let path = prefix + [index]
                if node.children.isEmpty == false {
                    paths.insert(path)
                    collect(nodes: node.children, prefix: path)
                }
            }
        }

        collect(nodes: nodes, prefix: [])
        return paths
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
}
