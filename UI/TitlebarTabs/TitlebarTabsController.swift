import AppKit

private final class TitlebarTabsScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

private final class TitlebarTabsContainerView: NSView {
    var destinationWindowID: UUID?
    var onMoveTab: ((TabDragPayload) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([TabDragPayload.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedPayload(from: sender) == nil ? [] : .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedPayload(from: sender) == nil ? [] : .move
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedPayload(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = acceptedPayload(from: sender) else { return false }
        return onMoveTab?(payload) == true
    }

    private func acceptedPayload(from sender: NSDraggingInfo) -> TabDragPayload? {
        guard let destinationWindowID,
              let payload = TabDragPayload.read(from: sender.draggingPasteboard),
              payload.sourceWindowID != destinationWindowID else { return nil }
        return payload
    }
}

final class TitlebarTabsController: NSViewController {
    static let defaultStripSize = NSSize(width: 760, height: 28)
    private static let hiddenStripSize = NSSize(width: 1, height: 1)
    private static let contentHorizontalPadding: CGFloat = 16
    let documentStore: DocumentStore
    let windowID: UUID
    var onCloseSessionRequested: ((UUID) -> Void)?
    var onAlternateSessionActivationRequested: ((UUID) -> Void)?
    var onRevealInFinderRequested: ((UUID) -> Void)?
    var onOpenWithMenuRequested: ((UUID) -> NSMenu?)?
    private lazy var workspaceSelector = WorkspaceSelectorView(documentStore: documentStore, windowID: windowID)
    private let scrollView = TitlebarTabsScrollView()
    private let stackView = NSStackView()
    private let documentContainerView = NSView()
    private var isTabsStripVisible = true
    private var availableWidth = TitlebarTabsController.defaultStripSize.width
    private var needsRevealActiveTab = false
    private var stripWidthConstraint: NSLayoutConstraint?
    private var stripHeightConstraint: NSLayoutConstraint?
    private var displayedTabsFingerprint: TabsFingerprint?
    nonisolated(unsafe) private var eventMonitors: [Any] = []

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.defaultStripSize
    }

    convenience init(documentStore: DocumentStore) {
        self.init(documentStore: documentStore, windowID: documentStore.defaultWindowID)
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
        rebuildTabs()
        setupEventMonitors()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        eventMonitors.forEach(NSEvent.removeMonitor)
    }

    override func loadView() {
        let container = TitlebarTabsContainerView()
        container.frame = NSRect(origin: .zero, size: Self.defaultStripSize)
        container.destinationWindowID = windowID
        container.onMoveTab = { [weak self] payload in
            self?.handleDroppedTab(payload) == true
        }
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 3
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentContainerView.wantsLayer = true
        documentContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        documentContainerView.addSubview(stackView)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentContainerView
        scrollView.onLayout = { [weak self] in self?.revealActiveTabAfterViewportLayout() }
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        workspaceSelector.translatesAutoresizingMaskIntoConstraints = false
        workspaceSelector.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let stripStack = NSStackView(views: [workspaceSelector, scrollView])
        stripStack.orientation = .horizontal
        stripStack.spacing = 8
        stripStack.alignment = .centerY
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stripStack)

        let stripWidthConstraint = container.widthAnchor.constraint(equalToConstant: Self.defaultStripSize.width)
        self.stripWidthConstraint = stripWidthConstraint
        let stripHeightConstraint = container.heightAnchor.constraint(equalToConstant: Self.defaultStripSize.height)
        self.stripHeightConstraint = stripHeightConstraint

        NSLayoutConstraint.activate([
            stripStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stripStack.topAnchor.constraint(equalTo: container.topAnchor),
            stripStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            workspaceSelector.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            scrollView.heightAnchor.constraint(equalTo: container.heightAnchor),
            stripWidthConstraint,
            stripHeightConstraint,
            stackView.leadingAnchor.constraint(equalTo: documentContainerView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: documentContainerView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: documentContainerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentContainerView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
        ])

        view = container
        applyChromeColors()
        applyVisibilityState()
    }

    func refreshChromeColors() {
        guard isViewLoaded else { return }
        applyChromeColors()
        workspaceSelector.refreshChromeColors()
        stackView.arrangedSubviews
            .compactMap { $0 as? TitlebarTabItemView }
            .forEach { $0.refreshChromeColors() }
    }

    private func applyChromeColors() {
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateDocumentContainerFrame()
    }

    private func revealActiveTabAfterViewportLayout() {
        updateDocumentContainerFrame()
        documentContainerView.layoutSubtreeIfNeeded()
        if needsRevealActiveTab, isTabsStripVisible, let selectedView = selectedTabItemView() {
            selectedView.scrollToVisible(selectedView.bounds)
            needsRevealActiveTab = false
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        let change = notification.documentStoreChange
        guard change.intersection([.content, .tabs, .annotations, .appearance]).isEmpty == false else { return }
        rebuildTabs()
        if change.contains(.appearance) { refreshChromeColors() }
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }
        workspaceSelector.refresh()

        let fingerprint = TabsFingerprint.capture(from: documentStore, windowID: windowID)
        guard fingerprint != displayedTabsFingerprint else {
            refreshPreferredStripSize()
            return
        }
        let restoreTabFocus = stackView.arrangedSubviews.contains {
            view.window?.firstResponder === $0
        }
        needsRevealActiveTab = fingerprint.activeSessionID != displayedTabsFingerprint?.activeSessionID
            || fingerprint.items.map(\.id) != displayedTabsFingerprint?.items.map(\.id)
        displayedTabsFingerprint = fingerprint

        let editingItem = stackView.arrangedSubviews
            .compactMap { $0 as? TitlebarTabItemView }
            .first(where: \.isEditing)
        let sessions = documentStore.sessions(in: windowID)
        if let editingItem, !sessions.contains(where: { $0.id == editingItem.sessionID }) {
            editingItem.finishEditing()
        }
        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            if subview !== editingItem { subview.removeFromSuperview() }
        }

        let selectedSessionIDs = documentStore.selectedSessionIDs(in: windowID)
        let continuousSessionIDs = documentStore.continuousReadingSessionIDs(in: windowID)
        let continuousSessionSet = Set(continuousSessionIDs)
        let continuousLeaderID = continuousSessionIDs.first
        let activeSessionID = fingerprint.activeSessionID

        for session in sessions {
            let itemView = editingItem.flatMap { $0.sessionID == session.id ? $0 : nil } ?? TitlebarTabItemView(
                sessionID: session.id,
                title: session.title,
                filename: session.isBlank ? nil : session.url.lastPathComponent,
                isSelected: activeSessionID == session.id,
                isTabSelected: selectedSessionIDs.contains(session.id),
                isDirty: session.isDirty,
                isContinuousReadingMember: continuousSessionSet.contains(session.id),
                isContinuousReadingLeader: continuousLeaderID == session.id,
                canStartContinuousReading: documentStore.canStartContinuousReadingFromSelection(in: windowID),
                dragPayload: session.isBlank
                    ? nil
                    : TabDragPayload(sourceWindowID: windowID, sessionID: session.id),
                onSelect: { [weak self] sessionID, modifierFlags in
                    self?.handleSessionSelection(sessionID, modifierFlags: modifierFlags)
                },
                onAlternateSelect: { [weak self] sessionID in
                    self?.onAlternateSessionActivationRequested?(sessionID)
                },
                onClose: { [weak self] sessionID in
                    self?.onCloseSessionRequested?(sessionID)
                },
                onRename: { [weak self] sessionID, newTitle in
                    self?.documentStore.renameSession(newTitle, for: sessionID)
                },
                onContextMenu: { [weak self] sessionID in
                    self?.selectForContextMenuIfNeeded(sessionID)
                },
                onRevealInFinder: { [weak self] sessionID in
                    self?.onRevealInFinderRequested?(sessionID)
                },
                onOpenWithMenu: { [weak self] sessionID in
                    self?.onOpenWithMenuRequested?(sessionID)
                },
                onStartContinuousReading: { [weak self] _ in
                    guard let self else { return }
                    _ = self.documentStore.startContinuousReadingFromSelectedSessions(in: self.windowID)
                },
                onExitContinuousReading: { [weak self] _ in
                    guard let self else { return }
                    self.documentStore.stopContinuousReading(in: self.windowID)
                },
                onMoveToWorkspaceMenu: { [weak self] sessionID in
                    self?.workspaceSelector.moveMenu(for: sessionID)
                }
            )
            if itemView === editingItem {
                itemView.updateState(
                    isSelected: activeSessionID == session.id,
                    isTabSelected: selectedSessionIDs.contains(session.id),
                    isDirty: session.isDirty,
                    isContinuousReadingMember: continuousSessionSet.contains(session.id),
                    isContinuousReadingLeader: continuousLeaderID == session.id,
                    canStartContinuousReading: documentStore.canStartContinuousReadingFromSelection(in: windowID)
                )
            }
            itemView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(itemView)
        }
        if let editingItem, !sessions.contains(where: { $0.id == editingItem.sessionID }) {
            editingItem.removeFromSuperview()
        }

        updateDocumentContainerFrame()
        refreshPreferredStripSize()
        if restoreTabFocus { view.window?.makeFirstResponder(selectedTabItemView()) }
        scrollView.needsLayout = true
        view.needsLayout = true
    }

    private func handleSessionSelection(_ sessionID: UUID, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            documentStore.toggleSessionSelection(sessionID, in: windowID)
            return
        }
        if modifierFlags.contains(.shift) {
            documentStore.selectSessionRange(through: sessionID, in: windowID)
            return
        }
        documentStore.activateTab(sessionID: sessionID, in: windowID)
    }

    private func selectForContextMenuIfNeeded(_ sessionID: UUID) {
        guard documentStore.selectedSessionIDs(in: windowID).contains(sessionID) == false else { return }
        documentStore.selectSessions([sessionID], in: windowID)
    }

    private func handleDroppedTab(_ payload: TabDragPayload) -> Bool {
        guard documentStore.moveSession(
            payload.sessionID,
            from: payload.sourceWindowID,
            to: windowID
        ) else { return false }
        view.window?.makeKeyAndOrderFront(nil)
        return true
    }

    private func updateDocumentContainerFrame() {
        let fittingWidth = stackView.fittingSize.width + Self.contentHorizontalPadding
        let contentWidth = max(scrollView.contentSize.width, fittingWidth)
        documentContainerView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: Self.defaultStripSize.height)
    }

    private func refreshPreferredStripSize() {
        let size: NSSize
        if isTabsStripVisible {
            let fittingWidth = stackView.fittingSize.width + Self.contentHorizontalPadding
                + workspaceSelector.intrinsicContentSize.width + 8
            let width = min(max(fittingWidth, Self.hiddenStripSize.width), availableWidth)
            size = NSSize(width: width, height: Self.defaultStripSize.height)
        } else {
            size = Self.hiddenStripSize
        }
        let sizeChanged = preferredContentSize != size
        preferredContentSize = size
        stripWidthConstraint?.constant = size.width
        stripHeightConstraint?.constant = size.height
        view.frame.size = preferredContentSize
        if sizeChanged { view.invalidateIntrinsicContentSize() }
    }

    func setAvailableWidth(_ width: CGFloat) {
        let width = max(width, Self.hiddenStripSize.width)
        guard availableWidth != width else { return }
        availableWidth = width
        guard isViewLoaded else { return }
        needsRevealActiveTab = true
        refreshPreferredStripSize()
        scrollView.needsLayout = true
        view.needsLayout = true
    }

    func setTabsStripVisible(_ isVisible: Bool) {
        isTabsStripVisible = isVisible
        guard isViewLoaded else { return }
        needsRevealActiveTab = isVisible
        refreshPreferredStripSize()
        applyVisibilityState()
        scrollView.needsLayout = true
    }

    private func applyVisibilityState() {
        view.isHidden = !isTabsStripVisible
        workspaceSelector.isHidden = !isTabsStripVisible
        scrollView.isHidden = !isTabsStripVisible
        view.frame.size = preferredContentSize
    }

    private func setupEventMonitors() {
        // Double-click on a tab → rename
        let mouse = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.clickCount == 2 else { return event }
            guard isTabsStripVisible, !view.isHiddenOrHasHiddenAncestor else { return event }
            guard documentStore.tabPresentationMode(in: windowID) == .horizontalTitlebar else { return event }
            guard eventBelongsToOwnWindow(event) else { return event }
            let locationInView = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(locationInView) else { return event }
            guard scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) else { return event }
            guard let itemView = stackView.arrangedSubviews.compactMap({ $0 as? TitlebarTabItemView }).first(where: {
                $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
            }) else { return event }
            itemView.beginEditing()
            return nil
        }
        eventMonitors.append(mouse as Any)

        // Enter on selected tab → rename (macOS Finder convention)
        let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleRenameKeyEvent(event)
        }
        eventMonitors.append(key as Any)
    }

    private func handleRenameKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard isPlainReturnKeyEvent(event) else { return event }
        guard isTabsStripVisible, !view.isHiddenOrHasHiddenAncestor else { return event }
        guard documentStore.tabPresentationMode(in: windowID) == .horizontalTitlebar else { return event }
        guard eventBelongsToOwnWindow(event), let window = view.window else { return event }
        guard window.firstResponder is NSTextView == false else { return event }
        guard let selectedView = selectedTabItemView(),
              let responder = window.firstResponder as? NSView,
              responder === selectedView || responder.isDescendant(of: selectedView) else { return event }
        selectedView.scrollToVisible(selectedView.bounds)
        selectedView.beginEditing()
        return nil
    }

    private func isPlainReturnKeyEvent(_ event: NSEvent) -> Bool {
        guard event.characters == "\r" || event.characters == "\n" else { return false }
        return event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private func selectedTabItemView() -> TitlebarTabItemView? {
        stackView.arrangedSubviews
            .compactMap { $0 as? TitlebarTabItemView }
            .first { $0.isSelected }
    }

    private func eventBelongsToOwnWindow(_ event: NSEvent) -> Bool {
        guard let window = view.window else { return false }
        if let eventWindow = event.window {
            return eventWindow === window
        }
        return event.windowNumber == window.windowNumber
    }
}

#if DEBUG
extension TitlebarTabsController {
    var testingIsSelectedTabEditing: Bool {
        selectedTabItemView()?.testingIsEditing == true
    }

    func testingHandleRenameKeyEvent(_ event: NSEvent) -> NSEvent? {
        handleRenameKeyEvent(event)
    }

    func testingMoveTab(_ payload: TabDragPayload) -> Bool {
        handleDroppedTab(payload)
    }

    var testingTabDragSourceHitTargets: [Bool] {
        stackView.arrangedSubviews
            .compactMap { $0 as? TitlebarTabItemView }
            .map { itemView in
                itemView.hitTest(NSPoint(x: itemView.frame.midX, y: itemView.frame.midY))
                    is TabDragSourceButton
            }
    }
}
#endif
