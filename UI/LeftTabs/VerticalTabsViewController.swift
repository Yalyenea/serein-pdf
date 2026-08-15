import AppKit

private final class CollapsibleContainerView: SidebarMaterialView {
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

    override var fittingSize: NSSize {
        NSSize(width: 1, height: super.fittingSize.height)
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

final class VerticalTabsViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    var onCloseSessionRequested: ((UUID) -> Void)?
    var onAlternateSessionActivationRequested: ((UUID) -> Void)?
    var onOpenRecentURLRequested: ((URL) -> Void)?
    private let documentsTitleLabel = NSTextField(labelWithString: "Documents")
    private let countLabel = NSTextField(labelWithString: "0 open")
    private let emptyStateView = EmptyStateView(
        title: "No Documents Open",
        detail: "Press ⌘O to open a PDF"
    )
    private let listStackView = NSStackView()
    private let recentSectionContainer = NSStackView()
    private let recentTitleLabel = NSTextField(labelWithString: "Recent PDFs")
    private let recentListStackView = NSStackView()
    private var recentBottomConstraints: [NSLayoutConstraint] = []
    private var recentTopConstraints: [NSLayoutConstraint] = []
    private var recentButtons: [NSButton] = []
    private var recentButtonURLs: [URL] = []
    private static let recentDisplayLimit = 5
    private var displayedTabsFingerprint: TabsFingerprint?
    nonisolated(unsafe) private var eventMonitors: [Any] = []
    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        title = "Documents"
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
        rebuildList()
        applyEmptyState()
        setupEventMonitors()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        eventMonitors.forEach(NSEvent.removeMonitor)
    }

    override func loadView() {
        let container = CollapsibleContainerView()
        container.destinationWindowID = windowID
        container.onMoveTab = { [weak self] payload in
            self?.handleDroppedTab(payload) == true
        }
        container.applySurface()
        container.allowsWindowDragFromBackground = true
        container.layer?.masksToBounds = true

        documentsTitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        documentsTitleLabel.textColor = NightModeStyle.tertiaryTextColor
        documentsTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = NightModeStyle.secondaryTextColor
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [documentsTitleLabel, NSView(), countLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        emptyStateView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        listStackView.orientation = .vertical
        listStackView.alignment = .leading
        listStackView.spacing = 5
        listStackView.translatesAutoresizingMaskIntoConstraints = false
        listStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recentSectionContainer.orientation = .vertical
        recentSectionContainer.alignment = .leading
        recentSectionContainer.spacing = 6
        recentSectionContainer.translatesAutoresizingMaskIntoConstraints = false
        recentSectionContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recentTitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        recentTitleLabel.textColor = NightModeStyle.tertiaryTextColor

        recentListStackView.orientation = .vertical
        recentListStackView.alignment = .leading
        recentListStackView.spacing = 2
        recentListStackView.translatesAutoresizingMaskIntoConstraints = false
        recentListStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recentListStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recentSectionContainer.addArrangedSubview(recentTitleLabel)
        recentSectionContainer.addArrangedSubview(recentListStackView)
        let recentListWidthMatch = recentListStackView.widthAnchor.constraint(equalTo: recentSectionContainer.widthAnchor)
        recentListWidthMatch.priority = .required
        recentListWidthMatch.isActive = true

        for view in [headerStack, emptyStateView, listStackView, recentSectionContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        let pinned: [NSLayoutConstraint] = [
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            emptyStateView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            emptyStateView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            emptyStateView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),

            listStackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            listStackView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -8),
            listStackView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
        ]
        pinned.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(pinned)

        // Recent section: pinned to the bottom while documents are open, moved up
        // under the Documents header when the window is empty (M12-012).
        recentBottomConstraints = [
            recentSectionContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            recentSectionContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            recentSectionContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            listStackView.bottomAnchor.constraint(
                lessThanOrEqualTo: recentSectionContainer.topAnchor, constant: -10),
        ]
        recentTopConstraints = [
            recentSectionContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            recentSectionContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            recentSectionContainer.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
        ]
        recentBottomConstraints.forEach { $0.priority = .defaultHigh }
        recentTopConstraints.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(recentBottomConstraints)

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            (view as? SidebarMaterialView)?.applySurface()
            documentsTitleLabel.textColor = NightModeStyle.tertiaryTextColor
            countLabel.textColor = NightModeStyle.secondaryTextColor
            emptyStateView.refreshChromeColors()
            recentTitleLabel.textColor = NightModeStyle.tertiaryTextColor
            recentButtons.forEach {
                $0.contentTintColor = NightModeStyle.secondaryTextColor
            }
            listStackView.arrangedSubviews
                .compactMap { $0 as? VerticalTabItemView }
                .forEach { $0.refreshChromeColors() }
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.isLightweightStoreChange == false else { return }
        rebuildList()
        applyEmptyState()
    }

    /// M12-012: with documents open, the recent footer stays pinned to the
    /// bottom; in an empty window the recents move up under the Documents header
    /// as the primary quick-entry content, falling back to the shared hint.
    private func applyEmptyState() {
        let noSessions = documentStore.sessions(in: windowID).isEmpty
        listStackView.isHidden = noSessions
        countLabel.isHidden = noSessions

        if noSessions {
            let recentsVisible = recentSectionContainer.isHidden == false
            emptyStateView.isHidden = recentsVisible
            recentTopConstraints.forEach { $0.isActive = recentsVisible }
            recentBottomConstraints.forEach { $0.isActive = false }
        } else {
            emptyStateView.isHidden = true
            recentTopConstraints.forEach { $0.isActive = false }
            recentBottomConstraints.forEach { $0.isActive = true }
        }
        view.needsLayout = true
    }

    private func rebuildList() {
        guard isViewLoaded else { return }

        let fingerprint = TabsFingerprint.capture(
            from: documentStore,
            windowID: windowID,
            recentURLs: recentFingerprintURLs(),
            showRecentSection: documentStore.appConfiguration.layout.showRecentFilesInSidebar
        )
        guard fingerprint != displayedTabsFingerprint else { return }
        displayedTabsFingerprint = fingerprint

        listStackView.arrangedSubviews.forEach { subview in
            listStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let sessions = documentStore.sessions(in: windowID)
        let selectedSessionIDs = documentStore.selectedSessionIDs(in: windowID)
        let continuousSessionIDs = documentStore.continuousReadingSessionIDs(in: windowID)
        let continuousSessionSet = Set(continuousSessionIDs)
        let continuousLeaderID = continuousSessionIDs.first
        let activeSessionID = documentStore.activeSessionID(in: windowID)
        countLabel.stringValue = "\(sessions.count) open"

        for session in sessions {
            let itemView = VerticalTabItemView(
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
            listStackView.addArrangedSubview(itemView)
            let widthMatch = itemView.widthAnchor.constraint(equalTo: listStackView.widthAnchor)
            widthMatch.priority = .defaultHigh
            widthMatch.isActive = true
        }

        rebuildRecentList()
    }

    private func recentFingerprintURLs() -> [URL] {
        guard documentStore.appConfiguration.layout.showRecentFilesInSidebar else { return [] }
        let openURLs = Set(documentStore.sessions(in: windowID).map(\.url.standardizedFileURL))
        return documentStore.recentDocumentURLs
            .filter { openURLs.contains($0.standardizedFileURL) == false }
            .prefix(Self.recentDisplayLimit)
            .map(\.self)
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
        documentStore.selectSessions([sessionID], in: windowID)
        documentStore.clearSearch(in: windowID)
        documentStore.activate(sessionID: sessionID, in: windowID)
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

    private func rebuildRecentList() {
        recentButtons.removeAll(keepingCapacity: true)
        recentButtonURLs.removeAll(keepingCapacity: true)
        recentListStackView.arrangedSubviews.forEach { subview in
            recentListStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let shouldShowRecents = documentStore.appConfiguration.layout.showRecentFilesInSidebar
        let recentURLs = Array(documentStore.recentDocumentURLs.prefix(Self.recentDisplayLimit))
        guard shouldShowRecents, recentURLs.isEmpty == false else {
            recentSectionContainer.isHidden = true
            return
        }

        recentSectionContainer.isHidden = false
        for url in recentURLs {
            let button = NSButton(title: url.deletingPathExtension().lastPathComponent, target: self, action: #selector(openRecentDocument(_:)))
            button.isBordered = false
            button.alignment = .left
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .regular)
            button.contentTintColor = NightModeStyle.secondaryTextColor
            button.setButtonType(.momentaryChange)
            button.bezelStyle = .regularSquare
            button.lineBreakMode = .byTruncatingMiddle
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.toolTip = url.path
            button.tag = recentButtons.count
            button.target = self
            button.action = #selector(openRecentDocument(_:))
            recentListStackView.addArrangedSubview(button)
            let widthMatch = button.widthAnchor.constraint(equalTo: recentListStackView.widthAnchor)
            widthMatch.priority = .required
            widthMatch.isActive = true
            recentButtons.append(button)
            recentButtonURLs.append(url)
        }
    }

    @objc
    private func openRecentDocument(_ sender: NSButton) {
        guard recentButtonURLs.indices.contains(sender.tag) else { return }
        onOpenRecentURLRequested?(recentButtonURLs[sender.tag])
    }

    private func setupEventMonitors() {
        // Double-click on a tab → rename
        let mouse = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleRenameMouseEvent(event) ?? event
        }
        eventMonitors.append(mouse as Any)

        // Enter on selected tab → rename (macOS Finder convention)
        let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRenameKeyEvent(event) ?? event
        }
        eventMonitors.append(key as Any)
    }

    private func handleRenameMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard event.clickCount == 2,
              eventBelongsToOwnWindow(event),
              let itemView = tabItemView(at: event.locationInWindow) else { return event }
        itemView.beginEditing()
        return nil
    }

    private func tabItemView(at locationInWindow: NSPoint) -> VerticalTabItemView? {
        listStackView.arrangedSubviews
            .compactMap { $0 as? VerticalTabItemView }
            .first { itemView in
                itemView.bounds.contains(itemView.convert(locationInWindow, from: nil))
            }
    }

    private func handleRenameKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard isPlainReturnKeyEvent(event) else { return event }
        guard documentStore.tabPresentationMode(in: windowID) == .verticalSidebar else { return event }
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

    private func selectedTabItemView() -> VerticalTabItemView? {
        listStackView.arrangedSubviews
            .compactMap { $0 as? VerticalTabItemView }
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
extension VerticalTabsViewController {
    var testingRecentFileTitles: [String] {
        recentButtons.map(\.title)
    }

    var testingRecentSectionVisible: Bool {
        recentSectionContainer.isHidden == false
    }

    var testingRecentSectionTopPinned: Bool {
        recentTopConstraints.allSatisfy(\.isActive)
    }

    var testingEmptyStateVisible: Bool {
        emptyStateView.isHidden == false
    }

    var testingCountLabelVisible: Bool {
        countLabel.isHidden == false
    }

    var testingDocumentsTitle: String {
        documentsTitleLabel.stringValue
    }

    var testingRecentListWidth: CGFloat {
        recentListStackView.frame.width
    }

    var testingRecentButtonWidths: [CGFloat] {
        recentButtons.map(\.frame.width)
    }

    func testingTriggerOpenRecent(at index: Int) {
        guard recentButtons.indices.contains(index) else { return }
        recentButtons[index].performClick(nil)
    }

    var testingIsSelectedTabEditing: Bool {
        selectedTabItemView()?.testingIsEditing == true
    }

    func testingHandleRenameKeyEvent(_ event: NSEvent) -> NSEvent? {
        handleRenameKeyEvent(event)
    }

    func testingHandleRenameMouseEvent(_ event: NSEvent) -> NSEvent? {
        handleRenameMouseEvent(event)
    }

    var testingWindowDragBackgroundView: NSView? {
        (view as? SidebarMaterialView)?.testingBackgroundView
    }

    func testingMoveTab(_ payload: TabDragPayload) -> Bool {
        handleDroppedTab(payload)
    }

    var testingTabDragSourceHitTargets: [Bool] {
        listStackView.arrangedSubviews
            .compactMap { $0 as? VerticalTabItemView }
            .map { itemView in
                itemView.hitTest(NSPoint(x: itemView.bounds.midX, y: itemView.bounds.midY))
                    is TabDragSourceButton
            }
    }
}
#endif
