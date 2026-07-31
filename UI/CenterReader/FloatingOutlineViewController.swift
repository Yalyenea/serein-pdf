import AppKit

private final class FloatingOutlineHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onPress: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        super.updateTrackingAreas()

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}

private enum FloatingOutlineResizeEdge {
    case top
    case bottom
}

private final class FloatingOutlineResizeHandleView: NSView {
    var onResizeBegan: (() -> Void)?
    var onResizeDelta: ((CGFloat) -> Void)?
    var onResizeEnded: ((NSPoint) -> Void)?
    private var previousMouseY: CGFloat?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        previousMouseY = event.locationInWindow.y
        onResizeBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previousMouseY else { return }
        let currentMouseY = event.locationInWindow.y
        self.previousMouseY = currentMouseY
        onResizeDelta?(currentMouseY - previousMouseY)
    }

    override func mouseUp(with event: NSEvent) {
        previousMouseY = nil
        onResizeEnded?(event.locationInWindow)
    }
}

private final class FloatingOutlineMarkerView: NSView {
    private static let maximumMarkerCount = 28
    private var levels: [Int] = []
    private var activeItemIndex: Int?

    override var isFlipped: Bool { true }

    func update(levels: [Int], activeItemIndex: Int?) {
        self.levels = levels
        self.activeItemIndex = activeItemIndex
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard levels.isEmpty == false else { return }

        let visibleCount = min(levels.count, Self.maximumMarkerCount)
        let pitch = min(6, max((bounds.height - 12) / CGFloat(visibleCount), 3.5))
        let lineHeight: CGFloat = 2
        let contentHeight = pitch * CGFloat(visibleCount - 1) + lineHeight
        let startY = max((bounds.height - contentHeight) / 2, 6)
        let activeSlot = activeItemIndex.map { itemIndex in
            guard levels.count > 1, visibleCount > 1 else { return 0 }
            return Int(
                round(
                    Double(itemIndex) / Double(levels.count - 1) *
                        Double(visibleCount - 1)
                )
            )
        }

        for slot in 0..<visibleCount {
            let sourceIndex: Int
            if visibleCount == 1 {
                sourceIndex = 0
            } else {
                sourceIndex = Int(
                    round(
                        Double(slot) / Double(visibleCount - 1) *
                            Double(levels.count - 1)
                    )
                )
            }
            let level = min(levels[sourceIndex], 3)
            let width = max(8, 20 - CGFloat(level) * 3)
            let rect = NSRect(
                x: bounds.maxX - width - 3,
                y: startY + CGFloat(slot) * pitch,
                width: width,
                height: lineHeight
            )
            let color = slot == activeSlot
                ? NightModeStyle.primaryTextColor.withAlphaComponent(0.82)
                : NightModeStyle.tertiaryTextColor.withAlphaComponent(0.52)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}

final class FloatingOutlineViewController: NSViewController {
    private struct Item: Hashable {
        let node: OutlineNode
        let level: Int
    }

    private static let collapsedWidth: CGFloat = 28
    private static let expandedWidth: CGFloat = 300
    private static let minimumCollapsedHeight: CGFloat = 56
    private static let maximumCollapsedHeight: CGFloat = 220

    let documentStore: DocumentStore
    let windowID: UUID
    private let outlineViewController: OutlineViewController
    private let hoverView = FloatingOutlineHoverView()
    private let markerView = FloatingOutlineMarkerView()
    private let panelView = NSVisualEffectView()
    private let topResizeHandle = FloatingOutlineResizeHandleView()
    private let bottomResizeHandle = FloatingOutlineResizeHandleView()
    private var items: [Item] = []
    private var activeItemIndex: Int?
    private var isExpanded = false
    private var isOutlineInstalled = false
    private var isSuppressed = false
    private var isResizing = false
    private var userAdjustedHeight: CGFloat?
    private var maximumAvailableHeight = AppConfiguration.Layout.maximumFloatingOutlineHeight
    private var lastReportedSize: NSSize?

    var preferredSizeDidChange: ((NSSize) -> Void)?

    var preferredSize: NSSize {
        if isExpanded {
            return NSSize(
                width: Self.expandedWidth,
                height: effectiveExpandedHeight
            )
        }

        let markerHeight = CGFloat(min(items.count, 28)) * 6 + 12
        return NSSize(
            width: Self.collapsedWidth,
            height: min(max(markerHeight, Self.minimumCollapsedHeight), Self.maximumCollapsedHeight)
        )
    }

    private var effectiveExpandedHeight: CGFloat {
        let configuredHeight = userAdjustedHeight ?? documentStore.appConfiguration.layout.floatingOutlineHeight
        let maximumHeight = min(
            AppConfiguration.Layout.maximumFloatingOutlineHeight,
            maximumAvailableHeight
        )
        return min(
            max(configuredHeight, AppConfiguration.Layout.minimumFloatingOutlineHeight),
            max(maximumHeight, AppConfiguration.Layout.minimumFloatingOutlineHeight)
        )
    }

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.outlineViewController = OutlineViewController(documentStore: documentStore, windowID: windowID)
        super.init(nibName: nil, bundle: nil)
        title = "Floating Outline"
        addChild(outlineViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hoverView.wantsLayer = true
        hoverView.setAccessibilityElement(true)
        hoverView.setAccessibilityRole(.button)
        hoverView.setAccessibilityLabel("Document outline")
        hoverView.setAccessibilityHelp("Move the pointer here to expand the document outline.")
        hoverView.onHoverChanged = { [weak self] isHovered in
            self?.setHovered(isHovered)
        }
        hoverView.onPress = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }

        markerView.identifier = NSUserInterfaceItemIdentifier("floatingOutlineMarkerRail")
        markerView.translatesAutoresizingMaskIntoConstraints = false
        markerView.toolTip = "Document outline"
        hoverView.addSubview(markerView)

        panelView.identifier = NSUserInterfaceItemIdentifier("floatingOutlinePanel")
        panelView.material = .popover
        panelView.blendingMode = .withinWindow
        panelView.state = .active
        panelView.wantsLayer = true
        panelView.layer?.cornerRadius = 8
        panelView.layer?.masksToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.isHidden = true
        hoverView.addSubview(panelView)

        configureResizeHandle(topResizeHandle, identifier: "floatingOutlineTopResizeHandle")
        configureResizeHandle(bottomResizeHandle, identifier: "floatingOutlineBottomResizeHandle")
        wireResizeHandle(topResizeHandle, edge: .top)
        wireResizeHandle(bottomResizeHandle, edge: .bottom)
        hoverView.addSubview(topResizeHandle)
        hoverView.addSubview(bottomResizeHandle)

        NSLayoutConstraint.activate([
            markerView.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            markerView.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            markerView.topAnchor.constraint(equalTo: hoverView.topAnchor),
            markerView.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor),

            panelView.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            panelView.topAnchor.constraint(equalTo: hoverView.topAnchor),
            panelView.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor),

            topResizeHandle.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            topResizeHandle.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            topResizeHandle.topAnchor.constraint(equalTo: hoverView.topAnchor),
            topResizeHandle.heightAnchor.constraint(equalToConstant: 8),

            bottomResizeHandle.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            bottomResizeHandle.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            bottomResizeHandle.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor),
            bottomResizeHandle.heightAnchor.constraint(equalToConstant: 8),
        ])

        view = hoverView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        refreshFromStore()
        refreshChromeColors()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refreshChromeColors() {
        guard isViewLoaded else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            panelView.layer?.backgroundColor = NightModeStyle.paneBackgroundColor
                .withAlphaComponent(0.94)
                .cgColor
            panelView.layer?.borderColor = NightModeStyle.chromeStrokeColor
                .withAlphaComponent(0.72)
                .cgColor
            panelView.layer?.borderWidth = 1
        }
        markerView.needsDisplay = true
        if outlineViewController.isViewLoaded {
            outlineViewController.refreshChromeColors()
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        guard isSuppressed != suppressed else { return }
        isSuppressed = suppressed
        refreshFromStore()
    }

    func setMaximumAvailableHeight(_ height: CGFloat) {
        let normalizedHeight = max(height, AppConfiguration.Layout.minimumFloatingOutlineHeight)
        guard abs(maximumAvailableHeight - normalizedHeight) > 0.5 else { return }
        maximumAvailableHeight = normalizedHeight
        reportPreferredGeometryIfNeeded()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        refreshFromStore()
    }

    private func refreshFromStore() {
        guard isViewLoaded else { return }
        guard isSuppressed == false,
              documentStore.isOutlineSidebarVisible(in: windowID) == false else {
            hideFloatingOutline()
            return
        }

        let outlineTree = documentStore.outlineTreeForSidebar(in: windowID)
        let nextItems = Self.flatten(outlineTree)
        guard nextItems.isEmpty == false else {
            hideFloatingOutline()
            return
        }

        items = nextItems
        let nextActiveItemIndex = resolveActiveItemIndex()
        let activeItemChanged = activeItemIndex != nextActiveItemIndex
        activeItemIndex = nextActiveItemIndex
        markerView.update(levels: items.map(\.level), activeItemIndex: activeItemIndex)
        view.isHidden = false

        // Configuration updates can change the default height without changing the outline.
        reportPreferredGeometryIfNeeded()
        if isExpanded, activeItemChanged, outlineViewController.isViewLoaded {
            outlineViewController.view.needsLayout = true
        }
    }

    private func hideFloatingOutline() {
        setExpanded(false)
        items = []
        activeItemIndex = nil
        markerView.update(levels: [], activeItemIndex: nil)
        view.isHidden = true
        reportPreferredGeometryIfNeeded()
    }

    private func setHovered(_ isHovered: Bool) {
        guard isHovered || isResizing == false else { return }
        setExpanded(isHovered)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        if expanded {
            installOutlineIfNeeded()
        } else {
            isResizing = false
        }
        markerView.isHidden = expanded
        panelView.isHidden = !expanded
        topResizeHandle.isHidden = !expanded
        bottomResizeHandle.isHidden = !expanded
        hoverView.setAccessibilityExpanded(expanded)
        hoverView.setAccessibilityHelp(
            expanded
                ? "Press to collapse the document outline."
                : "Move the pointer here or press to expand the document outline."
        )
        reportPreferredGeometryIfNeeded()
    }

    private func configureResizeHandle(
        _ handle: FloatingOutlineResizeHandleView,
        identifier: String
    ) {
        handle.identifier = NSUserInterfaceItemIdentifier(identifier)
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.isHidden = true
        handle.setAccessibilityElement(false)
    }

    private func wireResizeHandle(
        _ handle: FloatingOutlineResizeHandleView,
        edge: FloatingOutlineResizeEdge
    ) {
        handle.onResizeBegan = { [weak self] in
            self?.isResizing = true
        }
        handle.onResizeDelta = { [weak self] deltaY in
            self?.resizeExpandedOutline(from: edge, mouseDeltaY: deltaY)
        }
        handle.onResizeEnded = { [weak self] locationInWindow in
            self?.finishResizing(at: locationInWindow)
        }
    }

    private func resizeExpandedOutline(
        from edge: FloatingOutlineResizeEdge,
        mouseDeltaY: CGFloat
    ) {
        guard isExpanded else { return }
        let currentHeight = effectiveExpandedHeight
        let edgeDelta = edge == .top ? mouseDeltaY : -mouseDeltaY
        let heightDelta = edgeDelta * 2
        let maximumHeight = min(
            AppConfiguration.Layout.maximumFloatingOutlineHeight,
            maximumAvailableHeight
        )
        let nextHeight = min(
            max(currentHeight + heightDelta, AppConfiguration.Layout.minimumFloatingOutlineHeight),
            max(maximumHeight, AppConfiguration.Layout.minimumFloatingOutlineHeight)
        )
        let appliedDelta = nextHeight - currentHeight
        guard abs(appliedDelta) > 0.01 else { return }

        userAdjustedHeight = nextHeight
        reportPreferredGeometryIfNeeded()
    }

    private func finishResizing(at locationInWindow: NSPoint) {
        isResizing = false
        let locationInView = view.convert(locationInWindow, from: nil)
        if view.bounds.insetBy(dx: -8, dy: -8).contains(locationInView) == false {
            setExpanded(false)
        }
    }

    private func reportPreferredGeometryIfNeeded() {
        let size = preferredSize
        guard lastReportedSize != size else { return }
        lastReportedSize = size
        preferredSizeDidChange?(size)
    }

    private func installOutlineIfNeeded() {
        guard isOutlineInstalled == false else { return }
        isOutlineInstalled = true

        let outlineView = outlineViewController.view
        outlineView.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(outlineView)
        NSLayoutConstraint.activate([
            outlineView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 4),
            outlineView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -4),
            outlineView.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 4),
            outlineView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -4),
        ])
        outlineViewController.refreshChromeColors()
    }

    private func resolveActiveItemIndex() -> Int? {
        guard let sessionID = documentStore.activeSessionID(in: windowID),
              let session = documentStore.session(for: sessionID) else { return nil }

        return items.enumerated()
            .filter { _, item in
                (item.node.sourceSessionID ?? sessionID) == sessionID &&
                    (item.node.pageIndex ?? Int.max) <= session.currentPageIndex
            }
            .max { lhs, rhs in
                let lhsPage = lhs.element.node.pageIndex ?? -1
                let rhsPage = rhs.element.node.pageIndex ?? -1
                if lhsPage == rhsPage {
                    return lhs.element.level < rhs.element.level
                }
                return lhsPage < rhsPage
            }?
            .offset
    }

    private static func flatten(_ nodes: [OutlineNode]) -> [Item] {
        var result: [Item] = []

        func append(_ nodes: [OutlineNode], level: Int) {
            for node in nodes {
                result.append(Item(node: node, level: level))
                append(node.children, level: level + 1)
            }
        }

        append(nodes, level: 0)
        return result
    }

    var testingIsPresented: Bool {
        isViewLoaded && view.isHidden == false
    }

    var testingIsExpanded: Bool {
        isExpanded
    }

    var testingItemCount: Int {
        items.count
    }

    var testingOutlineViewController: OutlineViewController {
        installOutlineIfNeeded()
        return outlineViewController
    }

    func testingSetHovered(_ hovered: Bool) {
        setHovered(hovered)
    }

    func testingResizeFromTop(by deltaY: CGFloat) {
        resizeExpandedOutline(from: .top, mouseDeltaY: deltaY)
    }

    func testingResizeFromBottom(by deltaY: CGFloat) {
        resizeExpandedOutline(from: .bottom, mouseDeltaY: deltaY)
    }
}
