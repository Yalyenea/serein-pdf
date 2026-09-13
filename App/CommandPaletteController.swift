import AppKit

private final class CommandPalettePanel: NSPanel {
    var onKeyEvent: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyEvent?(event) == true { return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyEvent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private final class CommandPaletteGridView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

private final class CommandPaletteTile: NSControl {
    let titleLabel = NSTextField(labelWithString: "")
    let shortcutsView = ShortcutSequenceView()
    var isSelected = false { didSet { refreshColors() } }
    var onHover: ((Bool) -> Void)?
    var onInvoke: (() -> Void)?

    init(item: CommandPaletteItem) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        shortcutsView.configure(sequences: item.shortcutSequences)
        addSubview(titleLabel)
        addSubview(shortcutsView)
        NSLayoutConstraint.activate([
            shortcutsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortcutsView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp(item.shortcutTitle)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        refreshColors()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var preferredWidth: CGFloat {
        ceil(titleLabel.intrinsicContentSize.width) + shortcutWidth + 36
    }
    private var shortcutWidth: CGFloat { ceil(shortcutsView.fittingSize.width) }

    override func layout() {
        super.layout()
        let shortcutWidth = self.shortcutWidth
        titleLabel.frame = NSRect(x: 8, y: (bounds.height - 18) / 2, width: max(0, bounds.width - shortcutWidth - 28), height: 18)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseMoved(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onInvoke?() }

    override func accessibilityPerformPress() -> Bool { onInvoke?(); return true }
    func refreshColors() {
        titleLabel.textColor = NightModeStyle.primaryTextColor
        shortcutsView.refreshChromeColors()
        let background = NightModeStyle.selectedChromeBackgroundColor
        layer?.backgroundColor = isSelected ? background.cgColor : NSColor.clear.cgColor

    }
}

@MainActor
final class CommandPaletteController: NSWindowController, NSWindowDelegate {
    private let onInvokeCommand: (ShortcutCommand, UUID?) -> Void
    private let onVisibilityChange: ((Bool) -> Void)?
    private var state = CommandPaletteState()
    private var isPointerSelection = false
    private var isInvokingCommand = false
    private var keyEventMonitor: Any?
    private weak var parentWindow: NSWindow?
    private var targetWindowID: UUID?
    private let scrollView = NSScrollView()
    private let gridView = CommandPaletteGridView()
    private var tiles: [CommandPaletteTile] = []
    private var sectionLabels: [NSTextField] = []

    init(onInvokeCommand: @escaping (ShortcutCommand, UUID?) -> Void, onVisibilityChange: ((Bool) -> Void)? = nil) {
        self.onInvokeCommand = onInvokeCommand
        self.onVisibilityChange = onVisibilityChange
        let panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 400),
                                        styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Commands"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(type)?.isHidden = true
        }
        super.init(window: panel)
        panel.delegate = self
        panel.onKeyEvent = { [weak self] in self?.handlePanelKeyEvent($0) ?? false }
        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content
        scrollView.frame = content.bounds.insetBy(dx: 10, dy: 8)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = gridView
        content.addSubview(scrollView)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(commands: [ShortcutCommand], bindings: [ShortcutCommand: KeyboardShortcut],
              titles: [ShortcutCommand: String] = [:], targetWindowID: UUID?, relativeTo parentWindow: NSWindow?) {
        self.parentWindow = parentWindow
        self.targetWindowID = targetWindowID
        isPointerSelection = false
        state.replaceCommands(commands, bindings: bindings, titles: titles)
        rebuildGrid()
        positionPanel(relativeTo: parentWindow)
        refreshChromeColors()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(gridView)
        startKeyEventMonitor()
        onVisibilityChange?(true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss(restoreParent: Bool = true) {
        let wasVisible = window?.isVisible == true
        stopKeyEventMonitor()
        window?.orderOut(nil)
        if wasVisible { onVisibilityChange?(false) }
        if restoreParent { parentWindow?.makeKeyAndOrderFront(nil) }
    }

    private func rebuildGrid() {
        gridView.subviews.forEach { $0.removeFromSuperview() }
        sectionLabels = []
        tiles = state.allItems.enumerated().map { index, item in
            let tile = CommandPaletteTile(item: item)
            tile.identifier = NSUserInterfaceItemIdentifier("commandPalette.\(item.command.rawValue)")
            tile.onInvoke = { [weak self] in
                self?.state.setHighlightedIndex(index)
                self?.invoke(item.command)
            }
            tile.onHover = { [weak self] isInside in
                self?.updatePointerSelection(index: index, isInside: isInside)
            }
            gridView.addSubview(tile)
            return tile
        }
        let screen = parentWindow?.screen ?? NSScreen.main
        let availableWidth = (screen?.visibleFrame.width ?? 1000) - 32
        let width = min(max(700, (tiles.map(\.preferredWidth).max() ?? 330) * 2 + 52), availableWidth)
        let columnWidth = (width - 52) / 2
        var y: CGFloat = 0
        var previousSection: ShortcutSection?
        for row in state.rows {
            let section = state.allItems[row[0]].section
            if section != previousSection {
                if previousSection != nil { y += 8 }
                let label = NSTextField(labelWithString: section.title)
                label.font = .systemFont(ofSize: 10.5, weight: .semibold)
                label.frame = NSRect(x: 8, y: y + 3, width: width - 36, height: 16)
                gridView.addSubview(label)
                sectionLabels.append(label)
                y += 23
                previousSection = section
            }
            for (column, index) in row.enumerated() {
                tiles[index].frame = NSRect(x: CGFloat(column) * (columnWidth + 12), y: y, width: columnWidth, height: 32)
            }
            y += 32
        }
        if state.allItems.isEmpty {
            let label = NSTextField(labelWithString: "No commands available.")
            label.font = .systemFont(ofSize: 12)
            label.frame = NSRect(x: 8, y: 8, width: width - 36, height: 18)
            gridView.addSubview(label)
            sectionLabels.append(label)
            y = 34
        }
        let maxHeight = min(600, (screen?.visibleFrame.height ?? 800) - 100)
        window?.setContentSize(NSSize(width: width, height: min(y + 16, maxHeight)))
        gridView.frame = NSRect(x: 0, y: 0, width: width - 20, height: y)
        gridView.scroll(.zero)
        updateSelection()
    }

    private func updatePointerSelection(index: Int, isInside: Bool) {
        if isInside {
            isPointerSelection = true
            state.setHighlightedIndex(index)
        } else {
            guard isPointerSelection, state.highlightedIndex == index else { return }
            state.setHighlightedIndex(nil)
        }
        updateSelection()
    }

    private func updateSelection(scrollToSelection: Bool = false) {
        for (index, tile) in tiles.enumerated() { tile.isSelected = index == state.highlightedIndex }
        if scrollToSelection, let index = state.highlightedIndex { gridView.scrollToVisible(tiles[index].frame) }
    }

    private func moveSelection(horizontal: Int = 0, vertical: Int = 0) {
        isPointerSelection = false
        state.moveHighlight(horizontal: horizontal, vertical: vertical)
        updateSelection(scrollToSelection: true)
    }

    private func positionPanel(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }
        let target = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? window.frame
        let visible = parentWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? target
        window.setFrameOrigin(NSPoint(
            x: min(max(target.midX - window.frame.width / 2, visible.minX), visible.maxX - window.frame.width),
            y: min(max(target.maxY - window.frame.height - 88, visible.minY), visible.maxY - window.frame.height)))
    }

    func refreshChromeColors() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = SplitViewController.splitBackgroundColor
            window.contentView?.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
            tiles.forEach { $0.refreshColors() }
            sectionLabels.forEach { $0.textColor = NightModeStyle.secondaryTextColor }
        }
    }
    private func startKeyEventMonitor() {
        stopKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            return self.handlePanelKeyEvent(event) ? nil : event
        }
    }
    private func stopKeyEventMonitor() {
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor); self.keyEventMonitor = nil }
    }
    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        if ShortcutCommand.commandPaletteShortcut.matches(event: event) { dismiss(); return true }
        if let command = ShortcutCommand.allCases.first(where: {
            $0.builtInShortcutSequence?.strokes.last?.matches(event: event) == true
        }) { invoke(command); return true }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case 53: dismiss()
        case 123: moveSelection(horizontal: -1)
        case 124: moveSelection(horizontal: 1)
        case 125: moveSelection(vertical: 1)
        case 126: moveSelection(vertical: -1)
        case 36, 76:
            if let command = state.highlightedItem?.command { invoke(command) }
        default: return true
        }
        return true
    }
    private func invoke(_ command: ShortcutCommand) {
        guard isInvokingCommand == false else { return }
        isInvokingCommand = true
        dismiss()
        onInvokeCommand(command, targetWindowID)
        isInvokingCommand = false
    }
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window, window?.isVisible == true else { return }
        dismiss(restoreParent: false)
    }
}

#if DEBUG
extension CommandPaletteController {
    var testingCommands: [ShortcutCommand] { state.allItems.map(\.command) }
    var testingTiles: [NSView] { tiles }
    var testingTileFrames: [NSRect] { tiles.map(\.frame) }
    func testingHandlePanelKeyEvent(_ event: NSEvent) -> Bool { handlePanelKeyEvent(event) }
}
#endif
