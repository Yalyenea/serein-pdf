import AppKit

private final class OpenTabsPaletteCollectionView: NSCollectionView {
    var onKeyEvent: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class OpenTabsPaletteTileView: NSView {
    private let activeIndicator = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let pageLabel = NSTextField(labelWithString: "")
    private let paneBadgeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        activeIndicator.translatesAutoresizingMaskIntoConstraints = false
        activeIndicator.font = .systemFont(ofSize: 14, weight: .semibold)
        activeIndicator.alignment = .center
        activeIndicator.textColor = NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = NightModeStyle.secondaryTextColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1

        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .systemFont(ofSize: 10, weight: .medium)
        pageLabel.textColor = NightModeStyle.secondaryTextColor
        pageLabel.alignment = .right

        paneBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        paneBadgeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        paneBadgeLabel.alignment = .center
        paneBadgeLabel.textColor = NightModeStyle.secondaryTextColor
        paneBadgeLabel.wantsLayer = true
        paneBadgeLabel.layer?.cornerRadius = 4

        addSubview(activeIndicator)
        addSubview(titleLabel)
        addSubview(pathLabel)
        addSubview(pageLabel)
        addSubview(paneBadgeLabel)

        NSLayoutConstraint.activate([
            activeIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            activeIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            activeIndicator.widthAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: activeIndicator.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: activeIndicator.centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),

            pageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: paneBadgeLabel.leadingAnchor, constant: -8),
            pageLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 5),
            pageLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            paneBadgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            paneBadgeLabel.centerYAnchor.constraint(equalTo: pageLabel.centerYAnchor),
            paneBadgeLabel.widthAnchor.constraint(equalToConstant: 22),
            paneBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])

        updateSelection(isSelected: false, isActive: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: OpenTabsPaletteItem) {
        activeIndicator.stringValue = item.isActive ? "●" : ""
        titleLabel.textColor = NightModeStyle.primaryTextColor
        pathLabel.textColor = NightModeStyle.secondaryTextColor
        pageLabel.textColor = NightModeStyle.secondaryTextColor
        activeIndicator.textColor = NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance)
        titleLabel.stringValue = item.isDirty ? "\(item.title) •" : item.title
        pathLabel.stringValue = item.subtitle
        pageLabel.stringValue = item.pageText
        paneBadgeLabel.stringValue = item.paneBadge ?? ""
        paneBadgeLabel.isHidden = item.paneBadge == nil
        paneBadgeLabel.textColor = item.isFocusedPane ? NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance) : NightModeStyle.secondaryTextColor
    }

    func updateSelection(isSelected: Bool, isActive: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            paneBadgeLabel.layer?.backgroundColor = NightModeStyle.chromeStrokeColor.withAlphaComponent(0.35).cgColor
            let selectedColor = NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance).withAlphaComponent(0.85)
            let activeColor = NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance).withAlphaComponent(0.35)
            layer?.backgroundColor = isSelected
                ? selectedColor.withAlphaComponent(0.10).cgColor
                : NSColor.clear.cgColor
            layer?.borderColor = (isSelected ? selectedColor : (isActive ? activeColor : NightModeStyle.chromeStrokeColor.withAlphaComponent(0.45))).cgColor
            layer?.borderWidth = isSelected ? 2 : 1
        }
    }
}

private final class OpenTabsPaletteTileItem: NSCollectionViewItem {
    private var tabItem: OpenTabsPaletteItem?

    override var isSelected: Bool {
        didSet {
            guard let view = view as? OpenTabsPaletteTileView, let tabItem else { return }
            view.updateSelection(isSelected: isSelected, isActive: tabItem.isActive)
        }
    }

    override func loadView() {
        view = OpenTabsPaletteTileView()
    }

    func configure(item: OpenTabsPaletteItem) {
        tabItem = item
        (view as? OpenTabsPaletteTileView)?.configure(item: item)
        (view as? OpenTabsPaletteTileView)?.updateSelection(isSelected: isSelected, isActive: item.isActive)
    }
}

@MainActor
final class OpenTabsPaletteController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private static let panelSize = NSSize(width: 760, height: 520)
    private static let tileIdentifier = NSUserInterfaceItemIdentifier("OpenTabsPaletteTileItem")
    private static let tileSize = NSSize(width: 340, height: 82)

    private let onActivateSession: (UUID, Bool) -> Void
    private var state = OpenTabsPaletteState(sessions: [], activeSessionID: nil)
    private var isApplyingSelection = false

    private let titleLabel = NSTextField(labelWithString: "Show All Tabs")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let footerView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let collectionView = OpenTabsPaletteCollectionView()

    init(onActivateSession: @escaping (UUID, Bool) -> Void) {
        self.onActivateSession = onActivateSession

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Show All Tabs"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = SplitViewController.splitBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        buildInterface(in: panel)
        refreshChromeColors()
        reloadUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        with sessions: [DocumentSession],
        activeSessionID: UUID?,
        primarySessionID: UUID?,
        secondarySessionID: UUID?,
        focusedPane: ReaderPane,
        relativeTo parentWindow: NSWindow?
    ) {
        refreshChromeColors()
        state.replaceSessions(
            sessions,
            activeSessionID: activeSessionID,
            primarySessionID: primarySessionID,
            secondarySessionID: secondarySessionID,
            focusedPane: focusedPane
        )
        reloadUI()
        positionPanel(relativeTo: parentWindow)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(collectionView)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
        panel.contentView = contentView

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = NightModeStyle.primaryTextColor

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 11)
        secondaryLabel.textColor = NightModeStyle.secondaryTextColor
        secondaryLabel.alignment = .right

        configureFooter()

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = NightModeStyle.secondaryTextColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = Self.tileSize
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = false
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(OpenTabsPaletteTileItem.self, forItemWithIdentifier: Self.tileIdentifier)
        collectionView.onKeyEvent = { [weak self] event in
            self?.handlePaletteKeyEvent(event) ?? false
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = collectionView

        contentView.addSubview(titleLabel)
        contentView.addSubview(secondaryLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(footerView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),

            secondaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            secondaryLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            secondaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),

            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: secondaryLabel.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -20),

            footerView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.leadingAnchor),
            footerView.trailingAnchor.constraint(lessThanOrEqualTo: secondaryLabel.trailingAnchor),
            footerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    private func configureFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.orientation = .horizontal
        footerView.alignment = .centerY
        footerView.spacing = 14
        let hints: [([KeyboardShortcut], String)] = [
            (["h", "j", "k", "l", "left", "down", "up", "right"].map { KeyboardShortcut(key: $0, modifiers: []) }, "选中"),
            ([KeyboardShortcut(key: "return", modifiers: [])], "打开"),
            ([KeyboardShortcut(key: "return", modifiers: [.option])], "编辑分屏"),
            ([KeyboardShortcut(key: "escape", modifiers: [])], "关闭"),
        ]
        for (shortcuts, title) in hints {
            let group = NSStackView()
            group.orientation = .horizontal
            group.alignment = .centerY
            group.spacing = 4
            for shortcut in shortcuts {
                let key = ShortcutSequenceView()
                key.configure(sequences: [KeyboardShortcutSequence([shortcut])])
                group.addArrangedSubview(key)
            }
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = NightModeStyle.tertiaryTextColor
            group.addArrangedSubview(label)
            footerView.addArrangedSubview(group)
        }
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = NightModeStyle.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = NightModeStyle.splitBackgroundColor.cgColor
            titleLabel.textColor = NightModeStyle.primaryTextColor
            secondaryLabel.textColor = NightModeStyle.secondaryTextColor
            for group in footerView.arrangedSubviews.compactMap({ $0 as? NSStackView }) {
                for view in group.arrangedSubviews {
                    (view as? ShortcutSequenceView)?.refreshChromeColors()
                    (view as? NSTextField)?.textColor = NightModeStyle.tertiaryTextColor
                }
            }
            emptyLabel.textColor = NightModeStyle.secondaryTextColor
            for indexPath in collectionView.indexPathsForVisibleItems() {
                (collectionView.item(at: indexPath) as? OpenTabsPaletteTileItem)?
                    .configure(item: state.items[indexPath.item])
            }
        }
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
        emptyLabel.stringValue = "No open PDFs."
        emptyLabel.isHidden = state.items.isEmpty == false
        scrollView.isHidden = state.items.isEmpty

        isApplyingSelection = true
        collectionView.reloadData()
        applyHighlightedSelection()
        isApplyingSelection = false
    }

    private func secondaryText() -> String {
        let count = state.items.count
        return count == 1 ? "1 tab" : "\(count) tabs"
    }

    private func applyHighlightedSelection() {
        guard let highlightedIndex = state.highlightedIndex else {
            collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: highlightedIndex, section: 0)
        if collectionView.selectionIndexPaths.isEmpty == false {
            collectionView.deselectItems(at: collectionView.selectionIndexPaths)
        }
        collectionView.selectItems(at: [indexPath], scrollPosition: .centeredVertically)
    }

    private func activateHighlightedAndClose(alternatePane: Bool = false) {
        guard let sessionID = state.highlightedItem?.sessionID else {
            NSSound.beep()
            return
        }
        close()
        onActivateSession(sessionID, alternatePane)
    }

    private func handlePaletteKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])

        switch Int(event.keyCode) {
        case 53:
            close()
            return true
        case 36 where modifiers == [.option],
             76 where modifiers == [.option]:
            activateHighlightedAndClose(alternatePane: true)
            return true
        default:
            break
        }

        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 123:
            moveSelection(.left)
            return true
        case 124:
            moveSelection(.right)
            return true
        case 125:
            moveSelection(.down)
            return true
        case 126:
            moveSelection(.up)
            return true
        case 36, 76:
            activateHighlightedAndClose()
            return true
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h":
            moveSelection(.left)
            return true
        case "j":
            moveSelection(.down)
            return true
        case "k":
            moveSelection(.up)
            return true
        case "l":
            moveSelection(.right)
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ direction: OpenTabsPaletteMoveDirection) {
        state.moveHighlight(direction, columnCount: currentColumnCount())
        isApplyingSelection = true
        applyHighlightedSelection()
        isApplyingSelection = false
    }

    private func currentColumnCount() -> Int {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return 1 }
        let availableWidth = max(scrollView.contentView.bounds.width, collectionView.bounds.width)
        let fullItemWidth = layout.itemSize.width + layout.minimumInteritemSpacing
        guard fullItemWidth > 0 else { return 1 }
        return max(1, Int((availableWidth + layout.minimumInteritemSpacing) / fullItemWidth))
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        state.items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.tileIdentifier, for: indexPath)
        guard let tileItem = item as? OpenTabsPaletteTileItem else { return item }
        let tabItem = state.items[indexPath.item]
        tileItem.configure(item: tabItem)
        return tileItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard isApplyingSelection == false,
              let index = indexPaths.first?.item else { return }
        state.setHighlightedIndex(index)
        let isAlternate = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        activateHighlightedAndClose(alternatePane: isAlternate)
    }
}

#if DEBUG
extension OpenTabsPaletteController {
    var testingHighlightedIndex: Int? { state.highlightedIndex }
    var testingCurrentColumnCount: Int { currentColumnCount() }
    var testingCollectionViewIsFirstResponder: Bool {
        window?.firstResponder === collectionView
    }
    var testingSelectedItemCount: Int {
        collectionView.selectionIndexPaths.count
    }
    var testingWindowIsVisible: Bool {
        window?.isVisible == true
    }

    func testingHandlePaletteKeyEvent(_ event: NSEvent) -> Bool {
        handlePaletteKeyEvent(event)
    }

    func testingClickItem(at index: Int) {
        collectionView(collectionView, didSelectItemsAt: [IndexPath(item: index, section: 0)])
    }

}
#endif
