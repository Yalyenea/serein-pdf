import AppKit
import PDFKit

private final class FloatingOutlineHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onPress: (() -> Void)?
    var onEffectiveAppearanceChanged: (() -> Void)?
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
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
    private static let collapsedWidth: CGFloat = 28
    private static let expandedWidth: CGFloat = 300
    private static let panelContentInset: CGFloat = 4
    private static let panelBackgroundAlpha: CGFloat = 0.92
    private static let minimumCollapsedHeight: CGFloat = 56
    private static let maximumCollapsedHeight: CGFloat = 220

    let documentStore: DocumentStore
    let windowID: UUID
    private let outlineViewController: OutlineViewController
    private let hoverView = FloatingOutlineHoverView()
    private let markerView = FloatingOutlineMarkerView()
    private let panelView = NSView()
    private let topResizeHandle = FloatingOutlineResizeHandleView()
    private let bottomResizeHandle = FloatingOutlineResizeHandleView()
    private var locationResolver = OutlineLocationResolver(nodes: [])
    private var items: [OutlineLocationResolver.Entry] { locationResolver.entries }
    private var itemLevels: [Int] = []
    private var activeItemIndex: Int?
    private var displayedActiveLocation: OutlineReadingLocation?
    private var liveReadingLocation: OutlineReadingLocation?
    private weak var observedPDFView: PDFView?
    private var displayedSourceFingerprint: OutlineSourceFingerprint?
    private(set) var outlineFlattenCount = 0
    private var isExpanded = false
    private var isHovered = false
    private var isFilterFieldFocused = false
    private var isOutlineInstalled = false
    private var isSuppressed = false
    private var isResizing = false
    private var userAdjustedHeight: CGFloat?
    private var maximumAvailableHeight = CGFloat.greatestFiniteMagnitude
    private var lastReportedSize: NSSize?

    var preferredSizeDidChange: ((NSSize) -> Void)?
    var onNavigationRequested: ((OutlineNavigationRequest) -> Void)? {
        get { outlineViewController.onNavigationRequested }
        set { outlineViewController.onNavigationRequested = newValue }
    }
    var onQuickNavigationEnded: (() -> Void)? {
        get { outlineViewController.onQuickNavigationEnded }
        set { outlineViewController.onQuickNavigationEnded = newValue }
    }

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
        let configuredMaximumHeight = userAdjustedHeight
            ?? documentStore.appConfiguration.layout.floatingOutlineHeight
        let configuredHeightLimit = max(
            configuredMaximumHeight,
            AppConfiguration.Layout.minimumFloatingOutlineHeight
        )
        let heightLimit = min(configuredHeightLimit, maximumAvailableHeight)
        let outlineWidth = Self.expandedWidth - Self.panelContentInset * 2
        let naturalHeight = outlineViewController.preferredContentHeight(for: outlineWidth)
            + Self.panelContentInset * 2
        return min(naturalHeight, heightLimit)
    }

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.outlineViewController = OutlineViewController(
            documentStore: documentStore,
            windowID: windowID,
            isFloatingPresentation: true
        )
        super.init(nibName: nil, bundle: nil)
        title = "Floating Outline"
        addChild(outlineViewController)
        outlineViewController.preferredContentHeightDidChange = { [weak self] in
            self?.reportPreferredGeometryIfNeeded()
        }
        outlineViewController.filterFieldFocusDidChange = { [weak self] isFocused in
            self?.setFilterFieldFocused(isFocused)
        }
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
        hoverView.onEffectiveAppearanceChanged = { [weak self] in
            self?.refreshChromeColors()
        }

        markerView.identifier = NSUserInterfaceItemIdentifier("floatingOutlineMarkerRail")
        markerView.translatesAutoresizingMaskIntoConstraints = false
        markerView.toolTip = "Document outline"
        hoverView.addSubview(markerView)

        panelView.identifier = NSUserInterfaceItemIdentifier("floatingOutlinePanel")
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

    func bind(to pdfView: PDFView?) {
        outlineViewController.bind(to: pdfView)
        guard observedPDFView !== pdfView else { return }
        if let observedPDFView {
            NotificationCenter.default.removeObserver(self, name: .readerViewportDidChange, object: observedPDFView)
        }
        observedPDFView = pdfView
        liveReadingLocation = nil
        if let pdfView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleReaderViewportDidChange(_:)),
                name: .readerViewportDidChange,
                object: pdfView
            )
        }
        refreshActiveItemFromStore(forceMarkerUpdate: true)
    }

    @objc
    private func handleReaderViewportDidChange(_ notification: Notification) {
        guard let sessionID = notification.userInfo?["sessionID"] as? UUID,
              let position = notification.userInfo?["position"] as? ReadingPosition,
              let location = OutlineReadingLocation.capture(from: documentStore, windowID: windowID),
              location.sessionID == sessionID else { return }
        liveReadingLocation = OutlineReadingLocation(
            sessionID: sessionID, sourceSessionID: location.sourceSessionID, position: position
        )
        refreshActiveItemFromStore()
    }

    func refreshChromeColors() {
        guard isViewLoaded else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            panelView.layer?.backgroundColor = NightModeStyle.paneBackgroundColor
                .withAlphaComponent(Self.panelBackgroundAlpha)
                .cgColor
            panelView.layer?.borderColor = NightModeStyle.chromeStrokeColor
                .withAlphaComponent(0.48)
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
        let normalizedHeight = max(height, 0)
        guard abs(maximumAvailableHeight - normalizedHeight) > 0.5 else { return }
        maximumAvailableHeight = normalizedHeight
        reportPreferredGeometryIfNeeded()
    }

    @discardableResult
    func showQuickNavigation() -> Bool {
        loadViewIfNeeded()
        refreshFromStore()
        guard view.isHidden == false else { return false }
        setExpanded(true)
        view.superview?.layoutSubtreeIfNeeded()
        let didFocus = outlineViewController.focusSearchForQuickNavigation()
        if didFocus == false { updateExpansionForInteraction() }
        return didFocus
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        if notification.isOnlyReadingPositionChange {
            refreshActiveItemFromStore()
            return
        }
        let change = notification.documentStoreChange
        guard change.intersection([.content, .tabs, .sidebarVisibility, .rightSidebarMode, .appearance]).isEmpty == false else {
            return
        }
        refreshFromStore()
    }

    private func refreshFromStore() {
        guard isViewLoaded else { return }
        guard isSuppressed == false,
              documentStore.isOutlineSidebarVisible(in: windowID) == false else {
            hideFloatingOutline(clearItems: false)
            return
        }

        let wasHidden = view.isHidden
        let sourceFingerprint = OutlineSourceFingerprint.capture(
            from: documentStore,
            windowID: windowID
        )
        let outlineChanged = displayedSourceFingerprint != sourceFingerprint
        if outlineChanged {
            locationResolver = OutlineLocationResolver(nodes: documentStore.outlineTreeForSidebar(in: windowID))
            itemLevels = items.map(\.level)
            outlineFlattenCount += 1
            displayedSourceFingerprint = OutlineSourceFingerprint.capture(
                from: documentStore,
                windowID: windowID
            )
        }
        guard items.isEmpty == false else {
            hideFloatingOutline(clearItems: true)
            return
        }

        view.isHidden = false
        refreshActiveItemFromStore(forceMarkerUpdate: outlineChanged || wasHidden)

        // Configuration updates can change the default height without changing the outline.
        reportPreferredGeometryIfNeeded()
    }

    private func refreshActiveItemFromStore(forceMarkerUpdate: Bool = false) {
        guard isViewLoaded, view.isHidden == false else { return }
        let storedLocation = OutlineReadingLocation.capture(from: documentStore, windowID: windowID)
        let activeLocation = liveReadingLocation?.sessionID == storedLocation?.sessionID
            ? liveReadingLocation ?? storedLocation : storedLocation
        guard forceMarkerUpdate || displayedActiveLocation != activeLocation else { return }
        displayedActiveLocation = activeLocation
        let nextActiveItemIndex = activeLocation.flatMap {
            locationResolver.activeEntryIndex(at: $0.position, sessionIDs: $0.sessionIDs)
        }
        let activeItemChanged = activeItemIndex != nextActiveItemIndex
        guard activeItemChanged || forceMarkerUpdate else { return }
        activeItemIndex = nextActiveItemIndex
        markerView.update(levels: itemLevels, activeItemIndex: activeItemIndex)
    }

    private func hideFloatingOutline(clearItems: Bool) {
        setExpanded(false)
        if clearItems {
            locationResolver = OutlineLocationResolver(nodes: [])
            itemLevels = []
        }
        activeItemIndex = nil
        displayedActiveLocation = nil
        markerView.update(levels: [], activeItemIndex: nil)
        view.isHidden = true
        reportPreferredGeometryIfNeeded()
    }

    private func setHovered(_ isHovered: Bool) {
        self.isHovered = isHovered
        updateExpansionForInteraction()
    }

    private func setFilterFieldFocused(_ isFocused: Bool) {
        isFilterFieldFocused = isFocused
        updateExpansionForInteraction()
    }

    private func updateExpansionForInteraction() {
        guard isResizing == false else { return }
        setExpanded(isHovered || isFilterFieldFocused)
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
        let currentHeightLimit = userAdjustedHeight
            ?? documentStore.appConfiguration.layout.floatingOutlineHeight
        let edgeDelta = edge == .top ? mouseDeltaY : -mouseDeltaY
        let heightDelta = edgeDelta * 2
        let nextHeight = min(
            max(
                currentHeightLimit + heightDelta,
                AppConfiguration.Layout.minimumFloatingOutlineHeight
            ),
            max(maximumAvailableHeight, AppConfiguration.Layout.minimumFloatingOutlineHeight)
        )
        let appliedDelta = nextHeight - currentHeightLimit
        guard abs(appliedDelta) > 0.01 else { return }

        userAdjustedHeight = nextHeight
        reportPreferredGeometryIfNeeded()
    }

    private func finishResizing(at locationInWindow: NSPoint) {
        isResizing = false
        let locationInView = view.convert(locationInWindow, from: nil)
        isHovered = view.bounds.insetBy(dx: -8, dy: -8).contains(locationInView)
        updateExpansionForInteraction()
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
            outlineView.leadingAnchor.constraint(
                equalTo: panelView.leadingAnchor,
                constant: Self.panelContentInset
            ),
            outlineView.trailingAnchor.constraint(
                equalTo: panelView.trailingAnchor,
                constant: -Self.panelContentInset
            ),
            outlineView.topAnchor.constraint(
                equalTo: panelView.topAnchor,
                constant: Self.panelContentInset
            ),
            outlineView.bottomAnchor.constraint(
                equalTo: panelView.bottomAnchor,
                constant: -Self.panelContentInset
            ),
        ])
        outlineViewController.refreshChromeColors()
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

    var testingActiveItemIndex: Int? { activeItemIndex }

    var testingOutlineViewController: OutlineViewController {
        installOutlineIfNeeded()
        return outlineViewController
    }

    var testingPanelBackgroundColor: NSColor? {
        guard let backgroundColor = panelView.layer?.backgroundColor else { return nil }
        return NSColor(cgColor: backgroundColor)
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
