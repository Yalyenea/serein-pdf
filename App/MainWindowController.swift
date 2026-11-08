import AppKit
import QuartzCore

extension NSToolbarItem.Identifier {
    static let toggleDocumentSidebar = NSToolbarItem.Identifier("local.yfff.Serein.toggleDocumentSidebar")
    static let titlebarTabs = NSToolbarItem.Identifier("local.yfff.Serein.titlebarTabs")
}

private final class DocumentSidebarButton: NSButton {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChromeColors()
    }

    func refreshChromeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = NightModeStyle.secondaryTextColor
        }
    }
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private struct WindowChromeState: Equatable {
        let tabPresentationMode: TabPresentationMode
        let tabsOnRight: Bool
        let isTabsPaneVisible: Bool
        let hidesTitlebarTabs: Bool
        let isDemoModeEnabled: Bool
        let isOverviewPresentationActive: Bool
        let hasTabs: Bool
    }

    private struct WindowTitleState: Equatable {
        let title: String
        let representedURL: URL?
    }

    private struct TabSnapshot {
        let frame: NSRect
        let image: NSImage
        var isComposited = false
    }

    private struct TabTransfer {
        let workspaceID: UUID?
        let targetMode: TabPresentationMode
        let panel: NSPanel
        let sources: [String: TabSnapshot]
        var cells: [String: (view: NSView, image: NSImageView)]
        let backdrop: NSImageView
        var targets: [String: TabSnapshot] = [:]
        var isAnimating = false
    }

    static let defaultContentSize = NSSize(width: 1480, height: 960)
    static let minimumWindowSize = NSSize(width: 560, height: 360)

    let documentStore: DocumentStore
    let windowID: UUID
    private let splitViewController: SplitViewController
    private let toolbar = NSToolbar(identifier: "MainToolbar")
    private let sidebarToggleItem = NSToolbarItem(itemIdentifier: .toggleDocumentSidebar)
    private let sidebarToggleButton = DocumentSidebarButton(title: "", target: nil, action: nil)
    private let titlebarTabsItem = NSToolbarItem(itemIdentifier: .titlebarTabs)
    private var allowsTerminationWithoutPrompt = false
    private var demoModeSnapshot: DemoModeSnapshot?
    private var immersiveModeSnapshot: ImmersiveModeSnapshot?
    private var hidesTitlebarTabs = false
    private var appliedWindowChromeState: WindowChromeState?
    private var appliedWindowTitleState: WindowTitleState?
    private var readerInteractionInstallers: [(ReaderViewController) -> Void] = []
    private var tabTransfer: TabTransfer?
    var shouldCloseHandler: ((MainWindowController) -> Bool)?
    var didCloseHandler: ((MainWindowController) -> Void)?

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        splitViewController = SplitViewController(documentStore: documentStore, windowID: windowID)
        let window = ReaderShortcutWindow(contentViewController: splitViewController)

        window.title = "Serein"
        window.setContentSize(Self.defaultContentSize)
        // A separate frame minimum would make AppKit raise the content minimum
        // when the compact toolbar is attached.
        window.contentMinSize = Self.minimumWindowSize
        window.minFullScreenContentSize = Self.minimumWindowSize
        window.center()
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenAllowsTiling)
        window.tabbingMode = .disallowed
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        toolbar.centeredItemIdentifier = nil
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = SplitViewController.splitBackgroundColor
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        super.init(window: window)

        splitViewController.onReaderControllersDidChange = { [weak self] in
            guard let self else { return }
            for reader in self.splitViewController.readerWorkspaceViewController.allReaderViewControllers {
                self.readerInteractionInstallers.forEach { $0(reader) }
            }
        }
        splitViewController.readerWorkspaceViewController.onOverviewPresentationDidChange = { [weak self] in
            self?.applyWindowChromeState()
        }
        splitViewController.onWillAnimateSidebarChange = { [weak self] in
            self?.beginTabTransferIfNeeded() ?? false
        }
        splitViewController.onDidApplyChromeLayout = { [weak self] in
            self?.startTabTransferIfReady()
        }

        window.numberedTabShortcutHandler = { [weak self] oneBasedIndex in
            self?.activateNumberedTab(oneBasedIndex)
        }
        window.presentationShortcutHandler = { [weak self] event in
            self?.handlePresentationShortcut(event) ?? false
        }
        window.delegate = self
        toolbar.delegate = self
        configureSidebarToggleItem()
        shouldCascadeWindows = true
        splitViewController.verticalTabsViewController.onCloseSessionRequested = { [weak self] sessionID in
            self?.requestCloseSession(sessionID)
        }
        splitViewController.titlebarTabsController.onCloseSessionRequested = { [weak self] sessionID in
            self?.requestCloseSession(sessionID)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        refreshThemeAppearance()
        applyWindowChromeState()
        refreshWindowTitle()
    }

    convenience init(documentStore: DocumentStore) {
        self.init(documentStore: documentStore, windowID: documentStore.defaultWindowID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshThemeAppearance()
        applyWindowChromeState()
        refreshWindowTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        let invalidatesTabViews = !notification.isOnlySidebarVisibilityChange
            && !notification.documentStoreChange.intersection([.content, .tabs, .annotations, .appearance]).isEmpty
        if let tabTransfer,
           invalidatesTabViews || tabTransfer.workspaceID != documentStore.activeWorkspaceID(in: windowID)
            || tabTransfer.targetMode != documentStore.tabPresentationMode(in: windowID) {
            cancelTabTransfer()
        }
        guard notification.isOnlySidebarChromeChange == false else {
            applyWindowChromeState()
            return
        }
        guard notification.isOnlyReadingPositionChange == false else { return }
        let change = notification.documentStoreChange
        if change.intersection([.content, .tabs, .appearance]).isEmpty == false {
            applyWindowChromeState()
        }
        if change.intersection([.content, .tabs]).isEmpty == false {
            refreshWindowTitle()
        }
    }

    private func configureTitlebarTabsItemIfNeeded() {
        updateTitlebarTabsAvailableWidth()
        let tabsView = splitViewController.titlebarTabsController.view
        titlebarTabsItem.label = ""
        titlebarTabsItem.paletteLabel = ""
        titlebarTabsItem.view = tabsView
        titlebarTabsItem.isBordered = false
        titlebarTabsItem.visibilityPriority = .high
    }

    private func configureSidebarToggleItem() {
        sidebarToggleButton.identifier = NSUserInterfaceItemIdentifier("toggleDocumentSidebar")
        sidebarToggleButton.isBordered = false
        sidebarToggleButton.bezelStyle = .regularSquare
        sidebarToggleButton.focusRingType = .none
        sidebarToggleButton.imagePosition = .imageOnly
        sidebarToggleButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleDocumentSidebar)
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sidebarToggleButton.widthAnchor.constraint(equalToConstant: 28),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 26),
        ])
        sidebarToggleItem.label = L10n.text("Document Sidebar", "文档侧栏")
        sidebarToggleItem.paletteLabel = sidebarToggleItem.label
        sidebarToggleItem.view = sidebarToggleButton
        sidebarToggleItem.isBordered = false
        // Keep the layout switch reachable before tabs enter the overflow menu.
        sidebarToggleItem.visibilityPriority = .user
    }

    @objc
    private func toggleDocumentSidebar() {
        let tabsOnRight = documentStore.appConfiguration.layout.sidebarsSwapped
        if tabsOnRight {
            documentStore.setRightSidebarVisible(!documentStore.isRightSidebarVisible(in: windowID), in: windowID)
        } else {
            documentStore.setLeftSidebarVisible(!documentStore.isLeftSidebarVisible(in: windowID), in: windowID)
        }
    }

    private func refreshSidebarToggle(tabsOnRight: Bool, isVisible: Bool) {
        let label = isVisible
            ? L10n.text("Hide Document Sidebar", "隐藏文档侧栏")
            : L10n.text("Show Document Sidebar", "显示文档侧栏")
        sidebarToggleButton.image = NSImage(
            systemSymbolName: tabsOnRight ? "sidebar.right" : "sidebar.left",
            accessibilityDescription: label
        )
        sidebarToggleButton.toolTip = label
        sidebarToggleButton.setAccessibilityLabel(label)
        sidebarToggleButton.setAccessibilityValue(isVisible ? 1 : 0)
        sidebarToggleButton.refreshChromeColors()
    }

    private func updateTitlebarTabsAvailableWidth() {
        guard let window else { return }
        let buttonEdge = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .filter { !$0.isHidden }
            .map { $0.convert($0.bounds, to: nil).maxX }
            .max() ?? 0
        let leadingInset = max(buttonEdge + 16, 16)
        // Reserve the persistent toggle and native spacing before sizing tabs.
        let trailingInset: CGFloat = 20 + 28 + 16
        splitViewController.titlebarTabsController.setAvailableWidth(
            max(window.frame.width - leadingInset - trailingInset, 1)
        )
    }

    private func applyWindowChromeState() {
        let tabsOnRight = documentStore.appConfiguration.layout.sidebarsSwapped
        let tabsPaneVisible = tabsOnRight
            ? documentStore.isRightSidebarVisible(in: windowID)
            : documentStore.isLeftSidebarVisible(in: windowID)
        let tabPresentationMode = documentStore.tabPresentationMode(in: windowID)
        let hasTabs = !documentStore.sessions(in: windowID).isEmpty
        let changedTabPresentation = appliedWindowChromeState.map {
            $0.tabPresentationMode != tabPresentationMode
        } ?? false
        if changedTabPresentation || tabsPaneVisible || !hasTabs {
            hidesTitlebarTabs = false
        }
        let state = WindowChromeState(
            tabPresentationMode: tabPresentationMode,
            tabsOnRight: tabsOnRight,
            isTabsPaneVisible: tabsPaneVisible,
            hidesTitlebarTabs: hidesTitlebarTabs,
            isDemoModeEnabled: isDemoModeEnabled,
            isOverviewPresentationActive: splitViewController.readerWorkspaceViewController.isOverviewPresentationActive,
            hasTabs: hasTabs
        )
        guard appliedWindowChromeState != state else { return }
        if changedTabPresentation, tabTransfer == nil { beginTabTransferIfNeeded() }
        appliedWindowChromeState = state
        refreshSidebarToggle(tabsOnRight: tabsOnRight, isVisible: tabsPaneVisible)
        let shouldShowTitlebarTabs =
            state.tabPresentationMode == .horizontalTitlebar &&
            !tabsPaneVisible &&
            !state.hidesTitlebarTabs &&
            !state.isDemoModeEnabled &&
            !state.isOverviewPresentationActive

        splitViewController.titlebarTabsController.setTabsStripVisible(shouldShowTitlebarTabs)
        synchronizeWindowToolbar(isVisible: !state.isDemoModeEnabled)
        synchronizeTitlebarTabsItem(isVisible: shouldShowTitlebarTabs)
        splitViewController.setTitlebarRegionVisible(shouldShowTitlebarTabs)
        startTabTransferIfReady()
    }

    private func tabContainer(for mode: TabPresentationMode) -> NSView {
        mode == .verticalSidebar
            ? splitViewController.verticalTabsViewController.view
            : splitViewController.titlebarTabsController.view
    }

    private func tabImage(of view: NSView, in rect: NSRect) -> NSImage? {
        guard rect.width > 1, rect.height > 1,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func presentationItems(for mode: TabPresentationMode) -> [(id: String, view: NSView)] {
        mode == .verticalSidebar
            ? splitViewController.verticalTabsViewController.presentationItems()
            : splitViewController.titlebarTabsController.presentationItems()
    }

    private func transferFrame(_ rect: NSRect, from view: NSView, in window: NSWindow, to panel: NSPanel) -> NSRect {
        panel.convertFromScreen(window.convertToScreen(view.convert(rect, to: nil)))
    }

    private func presentationSnapshots(for mode: TabPresentationMode, panel: NSPanel) -> [String: TabSnapshot] {
        var snapshots: [String: TabSnapshot] = [:]
        guard let window else { return snapshots }
        for item in presentationItems(for: mode) {
            let view = item.view
            let visible = view.visibleRect.intersection(view.bounds)
            guard view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  let image = tabImage(of: view, in: visible) else { continue }
            snapshots[item.id] = TabSnapshot(frame: transferFrame(visible, from: view, in: window, to: panel), image: image)
        }
        return snapshots
    }

    private func transferCell(_ snapshot: TabSnapshot, id: String) -> (view: NSView, image: NSImageView) {
        let view = NSView(frame: snapshot.frame)
        view.identifier = NSUserInterfaceItemIdentifier(id)
        view.wantsLayer = true
        if !snapshot.isComposited {
            window?.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.layer?.backgroundColor = NightModeStyle.readerBackdropColor.cgColor
            }
        }
        let image = NSImageView(frame: view.bounds)
        image.autoresizingMask = [.width, .height]
        image.imageScaling = .scaleAxesIndependently
        image.image = snapshot.image
        view.addSubview(image)
        return (view, image)
    }

    private func inFlightTabSnapshots() -> [String: TabSnapshot]? {
        guard let transfer = tabTransfer else { return nil }
        guard transfer.isAnimating else { return transfer.sources }
        var snapshots: [String: TabSnapshot] = [:]
        for (id, cell) in transfer.cells {
            guard let layer = cell.view.layer?.presentation() else {
                snapshots[id] = transfer.sources[id]
                continue
            }
            guard layer.opacity > 0.01, layer.bounds.width > 1, layer.bounds.height > 1 else { continue }
            let image = NSImage(size: layer.bounds.size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.translateBy(x: -layer.bounds.minX, y: -layer.bounds.minY)
                layer.render(in: context)
            }
            image.unlockFocus()
            snapshots[id] = TabSnapshot(frame: layer.frame, image: image, isComposited: true)
        }
        return snapshots
    }

    @discardableResult
    private func beginTabTransferIfNeeded() -> Bool {
        guard let window, window.isVisible,
              SplitViewController.sidebarAnimationDuration > 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !isDemoModeEnabled, !isAllPagesOverviewActive,
              let previous = appliedWindowChromeState, !previous.hidesTitlebarTabs,
              previous.tabPresentationMode != documentStore.tabPresentationMode(in: windowID) else { return false }
        // A reversal starts from the displayed layer positions, not the final
        // layout already prepared beneath the previous animation.
        let interrupted = inFlightTabSnapshots()
        cancelTabTransfer()

        let panel = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("tabPresentationTransfer")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = window.effectiveAppearance
        let canvas = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        canvas.wantsLayer = true
        panel.contentView = canvas
        let sources = interrupted ?? presentationSnapshots(for: previous.tabPresentationMode, panel: panel)
        guard !sources.isEmpty else { return false }

        // Keep native window controls above every moving navigation item.
        let maskPath = CGMutablePath()
        maskPath.addRect(canvas.bounds)
        for button in [window.standardWindowButton(.closeButton), window.standardWindowButton(.miniaturizeButton),
                       window.standardWindowButton(.zoomButton), sidebarToggleButton].compactMap({ $0 })
            where button.window === window && !button.isHidden {
            maskPath.addRect(transferFrame(button.bounds, from: button, in: window, to: panel).insetBy(dx: -2, dy: -2))
        }
        let mask = CAShapeLayer()
        mask.frame = canvas.bounds
        mask.path = maskPath
        mask.fillRule = .evenOdd
        canvas.layer?.mask = mask

        let container = tabContainer(for: previous.tabPresentationMode)
        let visibleItems = presentationItems(for: previous.tabPresentationMode).filter { sources[$0.id] != nil }
        visibleItems.forEach { $0.view.alphaValue = 0 }
        var bounds = container.bounds
        if previous.tabPresentationMode == .verticalSidebar {
            let insets = container.safeAreaInsets
            bounds.origin.y += container.isFlipped ? insets.top : insets.bottom
            bounds.size.height -= insets.top + insets.bottom
        }
        let backdrop = NSImageView(frame: transferFrame(bounds, from: container, in: window, to: panel))
        backdrop.image = tabImage(of: container, in: bounds)
        backdrop.imageScaling = .scaleAxesIndependently
        canvas.addSubview(backdrop)
        visibleItems.forEach { $0.view.alphaValue = 1 }
        var cells: [String: (view: NSView, image: NSImageView)] = [:]
        for (id, snapshot) in sources {
            let cell = transferCell(snapshot, id: id)
            canvas.addSubview(cell.view)
            cells[id] = cell
        }
        let targetMode = documentStore.tabPresentationMode(in: windowID)
        tabTransfer = TabTransfer(workspaceID: documentStore.activeWorkspaceID(in: windowID), targetMode: targetMode,
                                  panel: panel, sources: sources, cells: cells, backdrop: backdrop)
        container.alphaValue = 0
        tabContainer(for: targetMode).alphaValue = 0
        window.addChildWindow(panel, ordered: .above)
        return true
    }

    private func startTabTransferIfReady() {
        guard var transfer = tabTransfer, !transfer.isAnimating, let window,
              !splitViewController.isApplyingSidebarLayout,
              appliedWindowChromeState?.tabPresentationMode == transfer.targetMode else { return }
        transfer.isAnimating = true
        tabTransfer = transfer

        // Finish the real destination layout and scrolling before measuring any
        // endpoints. Nothing is moved or remeasured after this single animation.
        window.layoutIfNeeded()
        if transfer.targetMode == .verticalSidebar {
            splitViewController.verticalTabsViewController.revealActiveTabForTransition()
        } else {
            splitViewController.titlebarTabsController.revealActiveTabForTransition()
        }
        window.layoutIfNeeded()
        let targets = presentationSnapshots(for: transfer.targetMode, panel: transfer.panel)
        tabTransfer?.targets = targets
        var cells = transfer.cells
        for (id, snapshot) in targets where cells[id] == nil {
            let cell = transferCell(snapshot, id: id)
            cell.view.alphaValue = 0
            transfer.panel.contentView?.addSubview(cell.view)
            cells[id] = cell
        }
        tabTransfer?.cells = cells
        var incomingImages: [String: NSImageView] = [:]
        for (id, cell) in cells {
            guard let snapshot = targets[id], transfer.sources[id] != nil else { continue }
            let image = NSImageView(frame: cell.view.bounds)
            image.autoresizingMask = [.width, .height]
            image.imageScaling = .scaleAxesIndependently
            image.image = snapshot.image
            image.alphaValue = 0
            cell.view.addSubview(image)
            incomingImages[id] = image
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transfer.backdrop.animator().alphaValue = 0
            for (id, cell) in cells {
                if let target = targets[id] {
                    cell.view.animator().frame = target.frame
                    cell.view.animator().alphaValue = 1
                    if let incoming = incomingImages[id] {
                        cell.image.animator().alphaValue = 0
                        incoming.animator().alphaValue = 1
                    }
                } else {
                    cell.view.animator().alphaValue = 0
                }
            }
        } completionHandler: { [weak self, panel = transfer.panel] in
            MainActor.assumeIsolated {
                guard self?.tabTransfer?.panel === panel else { return }
                self?.cancelTabTransfer()
            }
        }
    }

    private func cancelTabTransfer() {
        guard let transfer = tabTransfer else { return }
        tabTransfer = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            tabContainer(for: .verticalSidebar).animator().alphaValue = 1
            tabContainer(for: .horizontalTitlebar).animator().alphaValue = 1
        }
        transfer.panel.parent?.removeChildWindow(transfer.panel)
        transfer.panel.orderOut(nil)
    }

    private func synchronizeWindowToolbar(isVisible: Bool) {
        guard let window else { return }

        if isVisible {
            if window.toolbar !== toolbar {
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unifiedCompact
            if toolbar.items.contains(where: { $0.itemIdentifier == .toggleDocumentSidebar }) == false {
                toolbar.insertItem(withItemIdentifier: .toggleDocumentSidebar, at: 0)
            }
            return
        }

        window.toolbar = nil
    }

    private func synchronizeTitlebarTabsItem(isVisible: Bool) {
        let itemIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == .titlebarTabs })

        if isVisible {
            configureTitlebarTabsItemIfNeeded()
            if itemIndex == nil {
                toolbar.insertItem(withItemIdentifier: .titlebarTabs, at: toolbar.items.count)
            }
            toolbar.centeredItemIdentifier = nil
            return
        }

        toolbar.centeredItemIdentifier = nil
        if let itemIndex {
            toolbar.removeItem(at: itemIndex)
        }
    }

    private func refreshWindowTitle() {
        guard let window else { return }
        let state: WindowTitleState
        if let session = documentStore.activeSession(in: windowID), session.isBlank == false {
            state = WindowTitleState(title: session.title, representedURL: session.url)
        } else {
            state = WindowTitleState(title: "Serein", representedURL: nil)
        }
        guard appliedWindowTitleState != state else { return }
        appliedWindowTitleState = state
        window.title = state.title
        window.representedURL = state.representedURL
        window.representedFilename = state.representedURL?.path ?? ""
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleDocumentSidebar, .titlebarTabs]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .toggleDocumentSidebar { return sidebarToggleItem }
        guard itemIdentifier == .titlebarTabs else { return nil }
        configureTitlebarTabsItemIfNeeded()
        return titlebarTabsItem
    }

    func fitReaderToWidth() {
        splitViewController.fitToWidth()
    }

    func fitReaderToTextWidth() {
        splitViewController.fitToTextWidth()
    }

    func fitReaderToHeight() {
        splitViewController.fitToHeight()
    }

    func fitReaderToPage() {
        splitViewController.fitToPage()
    }

    func zoomIn() {
        splitViewController.zoomIn()
    }

    func zoomOut() {
        splitViewController.zoomOut()
    }

    func goToNextPage() {
        splitViewController.goToNextPage()
    }

    func goToPreviousPage() {
        splitViewController.goToPreviousPage()
    }

    func scrollHalfPageDown() {
        splitViewController.scrollHalfPageDown()
    }

    func scrollHalfPageUp() {
        splitViewController.scrollHalfPageUp()
    }

    func goToFirstPage() {
        splitViewController.goToFirstPage()
    }

    func goToLastPage() {
        splitViewController.goToLastPage()
    }

    func navigateBack() {
        splitViewController.navigateBack()
    }

    func navigateForward() {
        splitViewController.navigateForward()
    }

    var canGoBack: Bool { splitViewController.readerViewController.canGoBack }
    var canGoForward: Bool { splitViewController.readerViewController.canGoForward }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        splitViewController.goToPage(pageIndex)
    }

    var currentPageCount: Int { splitViewController.readerViewController.currentPageCount }
    var selectedReaderText: String? { splitViewController.readerViewController.selectedText }

    var isAllPagesOverviewActive: Bool {
        splitViewController.readerViewController.isAllPagesOverviewActive
    }

    func setAllPagesOverviewActive(_ active: Bool) {
        splitViewController.readerViewController.setAllPagesOverviewActive(active)
    }

    @discardableResult
    func toggleAllPagesOverview() -> Bool {
        splitViewController.readerViewController.toggleAllPagesOverview()
    }

    func toggleRightSidebarMode() {
        splitViewController.rightSidebarViewController.toggleMode()
    }

    var isReadingFocusModeEnabled: Bool {
        splitViewController.readerWorkspaceViewController.isReadingFocusModeEnabled
    }

    @discardableResult
    func toggleReadingFocusMode() -> Bool {
        guard documentStore.activeSession(in: windowID)?.isBlank == false else {
            return isReadingFocusModeEnabled
        }
        return splitViewController.readerWorkspaceViewController.toggleReadingFocusMode()
    }

    var isHorizontalPanLocked: Bool {
        splitViewController.readerWorkspaceViewController.isHorizontalPanLocked
    }

    @discardableResult
    func toggleHorizontalPanLock() -> Bool {
        guard let session = documentStore.activeSession(in: windowID),
              session.isBlank == false,
              session.displayMode.usesBookLayout == false else {
            return isHorizontalPanLocked
        }
        return splitViewController.readerWorkspaceViewController.toggleHorizontalPanLock()
    }

    func showReadingFocusControls() {
        guard documentStore.activeSession(in: windowID)?.isBlank == false else { return }
        splitViewController.readerWorkspaceViewController.showReadingFocusControls()
    }

    func toggleReaderSplit() {
        splitViewController.readerWorkspaceViewController.toggleSplit()
    }

    @discardableResult
    func splitCurrentPDF(layout: ReaderSplitLayout, sessionID: UUID? = nil) -> Bool {
        splitViewController.readerWorkspaceViewController.splitActivePane(layout: layout, sessionID: sessionID)
    }

    @discardableResult
    func splitDocument(at url: URL, layout: ReaderSplitLayout) throws -> Bool {
        try splitViewController.readerWorkspaceViewController.splitActivePane(documentAt: url, layout: layout)
    }

    func focusReaderPane(_ direction: ReaderPaneDirection) {
        _ = splitViewController.readerWorkspaceViewController.focusPane(direction: direction)
    }

    func toggleReaderPaneZoom() {
        splitViewController.readerWorkspaceViewController.togglePaneZoom()
    }

    func showQuickOutline() {
        splitViewController.showQuickOutline()
    }

    func translateSelection() {
        splitViewController.readerWorkspaceViewController.activeReaderViewController().translateSelection()
    }

    var isReaderSplitEnabled: Bool {
        documentStore.isSplitEnabled(in: windowID)
    }

    var isDemoModeEnabled: Bool {
        demoModeSnapshot != nil
    }

    var isImmersiveModeEnabled: Bool {
        // Horizontal tabs stay available when both panes are closed normally.
        hidesTitlebarTabs &&
            documentStore.isLeftSidebarVisible(in: windowID) == false &&
            documentStore.isRightSidebarVisible(in: windowID) == false &&
            documentStore.sessionCount(in: windowID) > 0
    }

    func toggleDemoMode() {
        if let snapshot = demoModeSnapshot {
            demoModeSnapshot = nil
            restoreDemoMode(from: snapshot)
            return
        }

        guard documentStore.activeSession(in: windowID)?.isBlank == false else { return }
        enterDemoMode()
    }

    func handlePresentationShortcut(_ event: NSEvent) -> Bool {
        guard isDemoModeEnabled,
              ReaderShortcutsController.shouldHandlePlainShortcut(for: window?.firstResponder) else {
            return false
        }
        return splitViewController.readerWorkspaceViewController
            .activeReaderViewController().handlePresentationShortcut(event)
    }

    func toggleImmersiveMode() {
        guard documentStore.activeSession(in: windowID) != nil else { return }

        immersiveModeSnapshot = nil
        let shouldOpenBothSidebars = isImmersiveModeEnabled
        documentStore.setLeftSidebarVisible(shouldOpenBothSidebars, in: windowID)
        documentStore.setRightSidebarVisible(shouldOpenBothSidebars, in: windowID)
        hidesTitlebarTabs = !shouldOpenBothSidebars
        applyWindowChromeState()
    }

    private func enterDemoMode() {
        hideFindBar()
        setAllPagesOverviewActive(false)
        demoModeSnapshot = DemoModeSnapshot(
            wasFullScreen: window?.styleMask.contains(.fullScreen) == true,
            wasImmersiveModeEnabled: isImmersiveModeEnabled,
            hidesTitlebarTabs: hidesTitlebarTabs,
            readerState: currentDemoReaderState()
        )
        splitViewController.readerWorkspaceViewController.setPresentationEnabled(true)
        if isImmersiveModeEnabled == false {
            enterImmersiveMode()
        }
        hidesTitlebarTabs = true
        applyWindowChromeState()
        applyDemoReaderState()
        if window?.isVisible == true,
           window?.styleMask.contains(.fullScreen) != true {
            window?.toggleFullScreen(nil)
        }
        scheduleDemoFitToPage()
    }

    private func restoreDemoMode(from snapshot: DemoModeSnapshot) {
        splitViewController.readerWorkspaceViewController.setPresentationEnabled(false)
        restoreDemoReaderState(snapshot.readerState)
        if snapshot.wasImmersiveModeEnabled == false, let immersiveModeSnapshot {
            self.immersiveModeSnapshot = nil
            restoreImmersiveMode(from: immersiveModeSnapshot)
        }
        hidesTitlebarTabs = snapshot.hidesTitlebarTabs
        applyWindowChromeState()
        if snapshot.wasFullScreen == false,
           window?.isVisible == true,
           window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        }
    }

    private func enterImmersiveMode() {
        immersiveModeSnapshot = ImmersiveModeSnapshot(
            isLeftSidebarVisible: documentStore.isLeftSidebarVisible(in: windowID),
            isRightSidebarVisible: documentStore.isRightSidebarVisible(in: windowID)
        )
        documentStore.setLeftSidebarVisible(false, in: windowID)
        documentStore.setRightSidebarVisible(false, in: windowID)
        hidesTitlebarTabs = true
        applyWindowChromeState()
    }

    private func restoreImmersiveMode(from snapshot: ImmersiveModeSnapshot) {
        documentStore.setLeftSidebarVisible(snapshot.isLeftSidebarVisible, in: windowID)
        documentStore.setRightSidebarVisible(snapshot.isRightSidebarVisible, in: windowID)
        applyWindowChromeState()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        updateTitlebarTabsAvailableWidth()
        guard let snapshot = demoModeSnapshot else { return }
        demoModeSnapshot = nil
        restoreDemoMode(from: snapshot)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        updateTitlebarTabsAvailableWidth()
        guard demoModeSnapshot != nil else { return }
        scheduleDemoFitToPage()
    }

    func windowDidResize(_ notification: Notification) {
        cancelTabTransfer()
        updateTitlebarTabsAvailableWidth()
    }

    func installPlainShortcutHandler(_ handler: @escaping (NSEvent, NSWindow) -> Bool) {
        guard let window = window as? ReaderShortcutWindow else { return }
        window.plainShortcutHandler = handler
    }

    private func activateNumberedTab(_ oneBasedIndex: Int) {
        let sessions = documentStore.sessions(in: windowID)
        let index = oneBasedIndex - 1
        guard sessions.indices.contains(index) else { return }

        let sessionID = sessions[index].id
        documentStore.activateTab(sessionID: sessionID, in: windowID)
    }

    func installSidebarRecentOpenHandler(_ handler: @escaping (URL, UUID) -> Void) {
        splitViewController.verticalTabsViewController.onOpenRecentURLRequested = { [weak self] url in
            guard let self else { return }
            handler(url, self.windowID)
        }
    }

    func installReaderOpenURLsHandler(_ handler: @escaping ([URL], UUID) -> Void) {
        installReaderInteraction { [weak self] reader in
            reader.onOpenURLsRequested = { [weak self] urls in
                guard let self else { return }
                handler(urls, self.windowID)
            }
        }
    }

    func installCodexShareHandlers(
        selectionHandler: @escaping (String, UUID) -> Void,
        pageImageHandler: @escaping (NSImage, Int, UUID) -> Void
    ) {
        installReaderInteraction { [weak self] reader in
            reader.onSendSelectionToCodexRequested = { [weak self] text in
                guard let self else { return }
                selectionHandler(text, self.windowID)
            }
            reader.onSendPageImageToCodexRequested = { [weak self] image, pageNumber in
                guard let self else { return }
                pageImageHandler(image, pageNumber, self.windowID)
            }
        }
    }

    private func installReaderInteraction(_ installer: @escaping (ReaderViewController) -> Void) {
        readerInteractionInstallers.append(installer)
        splitViewController.readerWorkspaceViewController.allReaderViewControllers.forEach(installer)
    }

    func installOpenWithMenuProvider(_ provider: @escaping (UUID, UUID) -> NSMenu?) {
        splitViewController.verticalTabsViewController.onOpenWithMenuRequested = { [weak self] sessionID in
            guard let self else { return nil }
            return provider(sessionID, self.windowID)
        }
        splitViewController.titlebarTabsController.onOpenWithMenuRequested = { [weak self] sessionID in
            guard let self else { return nil }
            return provider(sessionID, self.windowID)
        }
    }

    func installRevealInFinderHandler(_ handler: @escaping (UUID, UUID) -> Void) {
        splitViewController.verticalTabsViewController.onRevealInFinderRequested = { [weak self] sessionID in
            guard let self else { return }
            handler(sessionID, self.windowID)
        }
        splitViewController.titlebarTabsController.onRevealInFinderRequested = { [weak self] sessionID in
            guard let self else { return }
            handler(sessionID, self.windowID)
        }
    }

    func requestCloseActiveSession() {
        if documentStore.isSplitEnabled(in: windowID) {
            _ = splitViewController.readerWorkspaceViewController.closeFocusedPane()
            return
        }

        let selectedSessionIDs = documentStore.selectedSessionIDsInWindowOrder(in: windowID)
        if selectedSessionIDs.count > 1 {
            requestCloseSessions(selectedSessionIDs)
            return
        }

        guard let sessionID = documentStore.activeSessionID(in: windowID) else { return }
        requestCloseSession(sessionID)
    }

    private func requestCloseSessions(_ sessionIDs: [UUID]) {
        for sessionID in sessionIDs {
            guard requestCloseSession(sessionID) else { return }
        }
        if documentStore.isSplitEnabled(in: windowID),
           documentStore.sessionCount(in: windowID) < 2 {
            documentStore.setSplitEnabled(false, in: windowID)
        }
    }

    @discardableResult
    func requestCloseSession(_ sessionID: UUID, collapseSplitKeeping survivorPane: ReaderPane? = nil) -> Bool {
        guard let session = documentStore.session(for: sessionID) else { return true }
        guard session.isDirty else {
            closeSession(sessionID, collapseSplitKeeping: survivorPane)
            return true
        }

        switch presentUnsavedChangesAlert(
            title: L10n.text("Save changes to “\(session.title)” before closing?", "关闭“\(session.title)”前保存更改？"),
            detail: L10n.text("Your highlights are only in memory until you save them.", "高亮尚未保存到文件。")
        ) {
        case .save:
            do {
                try documentStore.saveAnnotations(for: sessionID)
                closeSession(sessionID, collapseSplitKeeping: survivorPane)
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            closeSession(sessionID, collapseSplitKeeping: survivorPane)
            return true
        case .cancel:
            return false
        }
    }

    private func closeSession(_ sessionID: UUID, collapseSplitKeeping survivorPane: ReaderPane?) {
        documentStore.close(sessionID: sessionID, from: windowID)

        guard let survivorPane,
              documentStore.isSplitEnabled(in: windowID) else { return }

        documentStore.setFocusedPane(survivorPane, in: windowID)
        documentStore.setSplitEnabled(false, in: windowID)
    }

    func flushPendingReadingPositions() {
        splitViewController.flushPendingReadingPositions()
    }

    @discardableResult
    func requestDeleteWorkspace(_ workspaceID: UUID) -> Bool {
        let workspaces = documentStore.workspaces(in: windowID)
        guard workspaces.count > 1, let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return false }
        flushPendingReadingPositions()
        let dirtySessions = documentStore.exclusiveDirtySessions(inWorkspace: workspaceID, in: windowID)
        if !dirtySessions.isEmpty {
            let titles = dirtySessions.prefix(3).map(\.title).joined(separator: "\n")
            let suffix = dirtySessions.count > 3 ? "\n…" : ""
            let decision = presentUnsavedChangesAlert(
                title: L10n.text("Save changes before deleting “\(workspace.name)”?", "删除“\(workspace.name)”前保存更改？"),
                detail: L10n.text("These PDFs have unsaved annotations:\n\(titles)\(suffix)", "以下 PDF 有未保存的批注：\n\(titles)\(suffix)")
            )
            do {
                switch decision {
                case .save:
                    try dirtySessions.forEach { try documentStore.saveAnnotations(for: $0.id) }
                case .discard:
                    try dirtySessions.forEach { try documentStore.discardUnsavedAnnotations(for: $0.id) }
                case .cancel:
                    return false
                }
            } catch {
                presentSaveError(error)
                return false
            }
        }
        return documentStore.deleteWorkspace(workspaceID, in: windowID)
    }

    func prepareForApplicationTermination() -> Bool {
        if allowsTerminationWithoutPrompt {
            allowsTerminationWithoutPrompt = false
            return true
        }

        let dirtySessions = documentStore.sessions.filter(\.isDirty)
        guard dirtySessions.isEmpty == false else { return true }

        let detail: String
        if dirtySessions.count == 1, let session = dirtySessions.first {
            detail = L10n.text("“\(session.title)” still has unsaved highlights.", "“\(session.title)”仍有未保存的高亮。")
        } else {
            let titles = dirtySessions.prefix(3).map(\.title).joined(separator: "\n")
            let suffix = dirtySessions.count > 3 ? "\n…" : ""
            detail = L10n.text("These documents still have unsaved highlights:\n\(titles)\(suffix)", "以下文档仍有未保存的高亮：\n\(titles)\(suffix)")
        }

        switch presentUnsavedChangesAlert(
            title: L10n.text("Save changes before quitting Serein?", "退出 Serein 前保存更改？"),
            detail: detail
        ) {
        case .save:
            do {
                try dirtySessions.forEach { try documentStore.saveAnnotations(for: $0.id) }
                allowsTerminationWithoutPrompt = true
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            allowsTerminationWithoutPrompt = true
            return true
        case .cancel:
            return false
        }
    }

    func prepareForWindowClosure() -> Bool {
        let dirtySessions = documentStore.exclusiveDirtySessions(in: windowID)
        guard dirtySessions.isEmpty == false else { return true }

        let detail: String
        if dirtySessions.count == 1, let session = dirtySessions.first {
            detail = L10n.text("“\(session.title)” is only open in this window. Closing it will discard unsaved highlights.", "“\(session.title)” 只在当前窗口打开，关闭窗口会丢失未保存高亮。")
        } else {
            let titles = dirtySessions.prefix(3).map(\.title).joined(separator: "\n")
            let suffix = dirtySessions.count > 3 ? "\n…" : ""
            detail = L10n.text("These documents are only open in this window. Closing it will discard unsaved highlights:\n\(titles)\(suffix)", "这些文档只在当前窗口打开，关闭窗口会丢失未保存高亮:\n\(titles)\(suffix)")
        }

        switch presentUnsavedChangesAlert(
            title: L10n.text("Save changes before closing this window?", "关闭此窗口前保存更改？"),
            detail: detail
        ) {
        case .save:
            do {
                try dirtySessions.forEach { try documentStore.saveAnnotations(for: $0.id) }
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .discard:
            do {
                try dirtySessions.forEach { try documentStore.discardUnsavedAnnotations(for: $0.id) }
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        case .cancel:
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldCloseHandler?(self) ?? true
    }

    func windowWillClose(_ notification: Notification) {
        cancelTabTransfer()
        splitViewController.readerWorkspaceViewController.setPresentationEnabled(false)
        didCloseHandler?(self)
    }

    @discardableResult
    func triggerAnnotationShortcut(_ type: AnnotationMarkupType) -> Bool {
        splitViewController.triggerAnnotationShortcut(type)
    }

    @discardableResult
    func addOrEditComment() -> Bool {
        splitViewController.addOrEditComment()
    }

    @discardableResult
    func exitTransientReaderState() -> Bool {
        if isFindBarVisible {
            hideFindBar()
            return true
        }
        if isAllPagesOverviewActive {
            setAllPagesOverviewActive(false)
            return true
        }
        if isDemoModeEnabled {
            if splitViewController.readerWorkspaceViewController.activeReaderViewController()
                .exitPresentationTool() {
                return true
            }
            toggleDemoMode()
            return true
        }
        if isAnnotationModeEnabled {
            exitHighlightMode()
            return true
        }
        return false
    }

    func exitHighlightMode() {
        splitViewController.exitHighlightMode()
    }

    func setHighlightColor(_ color: HighlightColor) {
        splitViewController.setHighlightColor(color)
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        splitViewController.removeHighlightUnderCursor()
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        splitViewController.undoLastHighlight()
    }

    var hasUndoableHighlight: Bool {
        splitViewController.readerViewController.hasUndoableHighlight
    }

    var hasRedoableHighlight: Bool {
        splitViewController.readerViewController.hasRedoableHighlight
    }

    func redoLastHighlight() -> Bool {
        splitViewController.redoLastHighlight()
    }

    var currentHighlightColor: HighlightColor {
        splitViewController.readerViewController.currentHighlightColor
    }

    func refreshThemeAppearance() {
        cancelTabTransfer()
        window?.backgroundColor = SplitViewController.splitBackgroundColor
        sidebarToggleButton.refreshChromeColors()
        splitViewController.refreshChromeColors()
    }

    func saveAnnotations() throws {
        try splitViewController.saveAnnotations()
    }

    func showFindBar(scope: SearchScope? = nil) {
        splitViewController.showFindBar(scope: scope)
    }

    func hideFindBar() {
        splitViewController.hideFindBar()
    }

    var isFindBarVisible: Bool {
        splitViewController.readerViewController.isFindBarVisible
    }

    @discardableResult
    func findNextMatch() -> Bool {
        splitViewController.findNextMatch()
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        splitViewController.findPreviousMatch()
    }

    var isAnnotationModeEnabled: Bool {
        splitViewController.readerViewController.isAnnotationModeEnabled
    }

    var isNightModeEnabled: Bool {
        (window?.effectiveAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

    private func presentUnsavedChangesAlert(title: String, detail: String) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.text("Save", "保存"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        alert.addButton(withTitle: L10n.text("Discard", "不保存"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.text("Failed to save annotations", "无法保存批注")
        alert.runModal()
    }

    private func currentDemoReaderState() -> DemoReaderState? {
        guard let session = documentStore.activeSession(in: windowID) else { return nil }
        return DemoReaderState(
            sessionID: session.id,
            displayMode: session.displayMode,
            scaleMode: session.scaleMode,
            zoomScale: session.zoomScale
        )
    }

    private func applyDemoReaderState() {
        guard let sessionID = demoModeSnapshot?.readerState?.sessionID,
              documentStore.session(for: sessionID) != nil else { return }
        documentStore.setDisplayMode(.singlePage, for: sessionID)
        fitReaderToPage()
    }

    private func restoreDemoReaderState(_ state: DemoReaderState?) {
        guard let state,
              documentStore.session(for: state.sessionID) != nil else { return }
        documentStore.setDisplayMode(state.displayMode, for: state.sessionID)
        documentStore.setScaleMode(state.scaleMode, scaleFactor: state.zoomScale, for: state.sessionID)
    }

    private func scheduleDemoFitToPage() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.demoModeSnapshot != nil else { return }
            self.window?.layoutIfNeeded()
            self.fitReaderToPage()
            self.window?.layoutIfNeeded()
        }
    }

    private struct DemoModeSnapshot {
        let wasFullScreen: Bool
        let wasImmersiveModeEnabled: Bool
        let hidesTitlebarTabs: Bool
        let readerState: DemoReaderState?
    }

    private struct ImmersiveModeSnapshot {
        let isLeftSidebarVisible: Bool
        let isRightSidebarVisible: Bool
    }

    private struct DemoReaderState {
        let sessionID: UUID
        let displayMode: ReaderDisplayMode
        let scaleMode: ReaderScaleMode
        let zoomScale: CGFloat
    }
}

#if DEBUG
extension MainWindowController {
    var testingTabTransferSourceFrames: [String: NSRect] {
        tabTransfer?.sources.mapValues { $0.frame } ?? [:]
    }

    var testingTabTransferTargetFrames: [String: NSRect] {
        tabTransfer?.targets.mapValues { $0.frame } ?? [:]
    }
}
#endif
