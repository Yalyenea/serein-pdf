import AppKit

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
    static let maximumVisibleStripSize = NSSize(width: 760, height: 28)
    private static let hiddenStripSize = NSSize(width: 1, height: 1)
    private static let contentHorizontalPadding: CGFloat = 16
    private static let stripCornerRadius: CGFloat = 3
    let documentStore: DocumentStore
    let windowID: UUID
    var onCloseSessionRequested: ((UUID) -> Void)?
    var onAlternateSessionActivationRequested: ((UUID) -> Void)?
    var onRevealInFinderRequested: ((UUID) -> Void)?
    var onOpenWithMenuRequested: ((UUID) -> NSMenu?)?
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let documentContainerView = NSView()
    private var isTabsStripVisible = true
    private var stripWidthConstraint: NSLayoutConstraint?
    private var displayedTabsFingerprint: TabsFingerprint?
    nonisolated(unsafe) private var eventMonitors: [Any] = []

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.maximumVisibleStripSize
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
        container.frame = NSRect(origin: .zero, size: Self.maximumVisibleStripSize)
        container.destinationWindowID = windowID
        container.onMoveTab = { [weak self] payload in
            self?.handleDroppedTab(payload) == true
        }
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.stripCornerRadius
        container.layer?.masksToBounds = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 0
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)

        let stripWidthConstraint = container.widthAnchor.constraint(equalToConstant: Self.maximumVisibleStripSize.width)
        self.stripWidthConstraint = stripWidthConstraint

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stripWidthConstraint,
            container.heightAnchor.constraint(equalToConstant: Self.maximumVisibleStripSize.height),
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
        stackView.arrangedSubviews
            .compactMap { $0 as? TitlebarTabItemView }
            .forEach { $0.refreshChromeColors() }
    }

    private func applyChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = SplitViewController.selectedChromeBackgroundColor
                .withAlphaComponent(0.18)
                .cgColor
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateDocumentContainerFrame()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        let change = notification.documentStoreChange
        guard change.intersection([.content, .tabs, .annotations]).isEmpty == false else { return }
        rebuildTabs()
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }

        let fingerprint = TabsFingerprint.capture(from: documentStore, windowID: windowID)
        guard fingerprint != displayedTabsFingerprint else { return }
        displayedTabsFingerprint = fingerprint

        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let sessions = documentStore.sessions(in: windowID)
        let selectedSessionIDs = documentStore.selectedSessionIDs(in: windowID)
        let continuousSessionIDs = documentStore.continuousReadingSessionIDs(in: windowID)
        let continuousSessionSet = Set(continuousSessionIDs)
        let continuousLeaderID = continuousSessionIDs.first
        let activeSessionID = documentStore.activeSessionID(in: windowID)

        for session in sessions {
            let itemView = TitlebarTabItemView(
                sessionID: session.id,
                title: session.title,
                isSelected: activeSessionID == session.id,
                isTabSelected: selectedSessionIDs.contains(session.id),
                isDirty: session.isDirty,
                isContinuousReadingMember: continuousSessionSet.contains(session.id),
                isContinuousReadingLeader: continuousLeaderID == session.id,
                canStartContinuousReading: selectedSessionIDs.count > 1,
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
                }
            )
            itemView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(itemView)
        }

        updateDocumentContainerFrame()
        refreshPreferredStripSize()
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
        documentContainerView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: Self.maximumVisibleStripSize.height)
    }

    private func refreshPreferredStripSize() {
        guard isTabsStripVisible else {
            preferredContentSize = Self.hiddenStripSize
            stripWidthConstraint?.constant = Self.hiddenStripSize.width
            view.frame.size = preferredContentSize
            return
        }

        let fittingWidth = stackView.fittingSize.width + Self.contentHorizontalPadding
        let width = min(max(fittingWidth, Self.hiddenStripSize.width), Self.maximumVisibleStripSize.width)
        preferredContentSize = NSSize(width: width, height: Self.maximumVisibleStripSize.height)
        stripWidthConstraint?.constant = width
        view.frame.size = preferredContentSize
    }

    func setTabsStripVisible(_ isVisible: Bool) {
        isTabsStripVisible = isVisible
        preferredContentSize = isVisible ? preferredContentSize : Self.hiddenStripSize
        guard isViewLoaded else { return }
        refreshPreferredStripSize()
        applyVisibilityState()
    }

    private func applyVisibilityState() {
        view.isHidden = !isTabsStripVisible
        scrollView.isHidden = !isTabsStripVisible
        view.frame.size = preferredContentSize
    }

    private func setupEventMonitors() {
        // Double-click on a tab → rename
        let mouse = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.clickCount == 2 else { return event }
            guard eventBelongsToOwnWindow(event) else { return event }
            let locationInView = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(locationInView) else { return event }
            guard let selectedView = stackView.arrangedSubviews.compactMap({ $0 as? TitlebarTabItemView }).first(where: { $0.isSelected }) else { return event }
            selectedView.beginEditing()
            return nil
        }
        eventMonitors.append(mouse as Any)

        // Enter on selected tab → rename (macOS Finder convention)
        let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRenameKeyEvent(event) ?? event
        }
        eventMonitors.append(key as Any)
    }

    private func handleRenameKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard isPlainReturnKeyEvent(event) else { return event }
        guard isTabsStripVisible else { return event }
        guard documentStore.tabPresentationMode(in: windowID) == .horizontalTitlebar else { return event }
        guard eventBelongsToOwnWindow(event), let window = view.window else { return event }
        guard window.firstResponder is NSTextView == false else { return event }
        guard let selectedView = selectedTabItemView() else { return event }
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
