import AppKit

final class TitlebarTabsController: NSViewController {
    static let visibleStripSize = NSSize(width: 760, height: 28)
    let documentStore: DocumentStore
    let windowID: UUID
    var onCloseSessionRequested: ((UUID) -> Void)?
    var onAlternateSessionActivationRequested: ((UUID) -> Void)?
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let documentContainerView = NSView()
    private let bottomBorderView = NSView()
    private var isTabsStripVisible = true
    nonisolated(unsafe) private var eventMonitors: [Any] = []

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.visibleStripSize
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
        let container = NSView()
        container.frame = NSRect(origin: .zero, size: Self.visibleStripSize)
        container.wantsLayer = true

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

        bottomBorderView.wantsLayer = true
        bottomBorderView.translatesAutoresizingMaskIntoConstraints = false
        bottomBorderView.isHidden = !isTabsStripVisible

        container.addSubview(scrollView)
        container.addSubview(bottomBorderView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBorderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBorderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBorderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBorderView.heightAnchor.constraint(equalToConstant: 1),
            container.widthAnchor.constraint(equalToConstant: Self.visibleStripSize.width),
            container.heightAnchor.constraint(equalToConstant: Self.visibleStripSize.height),
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
    }

    private func applyChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
            bottomBorderView.layer?.backgroundColor = SplitViewController.dividerBackgroundColor.cgColor
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateDocumentContainerFrame()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildTabs()
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }

        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let selectedSessionIDs = documentStore.selectedSessionIDs(in: windowID)
        let continuousSessionIDs = documentStore.continuousReadingSessionIDs(in: windowID)
        let continuousSessionSet = Set(continuousSessionIDs)
        let continuousLeaderID = continuousSessionIDs.first

        for session in documentStore.sessions(in: windowID) {
            let itemView = TitlebarTabItemView(
                sessionID: session.id,
                title: session.title,
                isSelected: documentStore.activeSessionID(in: windowID) == session.id,
                isTabSelected: selectedSessionIDs.contains(session.id),
                isDirty: session.isDirty,
                isContinuousReadingMember: continuousSessionSet.contains(session.id),
                isContinuousReadingLeader: continuousLeaderID == session.id,
                canStartContinuousReading: selectedSessionIDs.count > 1,
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
            stackView.addArrangedSubview(itemView)
        }

        updateDocumentContainerFrame()
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

    private func updateDocumentContainerFrame() {
        let fittingWidth = stackView.fittingSize.width + 16
        let contentWidth = max(scrollView.contentSize.width, fittingWidth)
        documentContainerView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 28)
    }

    func setTabsStripVisible(_ isVisible: Bool) {
        isTabsStripVisible = isVisible
        preferredContentSize = isVisible ? Self.visibleStripSize : NSSize(width: 1, height: 1)
        guard isViewLoaded else { return }
        applyVisibilityState()
    }

    private func applyVisibilityState() {
        view.isHidden = !isTabsStripVisible
        scrollView.isHidden = !isTabsStripVisible
        bottomBorderView.isHidden = !isTabsStripVisible
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
}
#endif
