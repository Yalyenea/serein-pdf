import AppKit

final class SplitViewController: NSSplitViewController {
    private static let legacyAutosaveNames = [
        "MainSplitView",
        "SlatePDFSplit.v2",
        "SlatePDFSplit.v3",
    ]
    let documentStore: DocumentStore
    let verticalTabsViewController: VerticalTabsViewController
    let readerViewController: ReaderViewController
    let outlineViewController: OutlineViewController
    let titlebarTabsController: TitlebarTabsController
    private var leftSidebarItem: NSSplitViewItem?
    private var rightSidebarItem: NSSplitViewItem?
    private var appliedWidthsForSessionID: UUID?
    private var isApplyingSidebarWidths = false

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        verticalTabsViewController = VerticalTabsViewController(documentStore: documentStore)
        readerViewController = ReaderViewController(documentStore: documentStore)
        outlineViewController = OutlineViewController(documentStore: documentStore)
        titlebarTabsController = TitlebarTabsController(documentStore: documentStore)
        super.init(nibName: nil, bundle: nil)
        verticalTabsViewController.configure(pdfView: readerViewController.pdfView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static let splitBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.10 : 0.96, alpha: 1.0)
    }

    static let dividerBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.12 : 0.88, alpha: 1.0)
    }

    static let selectedChromeBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.19 : 0.915, alpha: 1.0)
    }

    static let chromeStrokeColor: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.28 : 0.82, alpha: 1.0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        purgeLegacyAutosaveKeys()
        view.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = nil
        splitView.wantsLayer = true
        applyChromeColors()

        let sidebarHoldingPriority = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 10
        )
        let layout = documentStore.appConfiguration.layout

        let leftItem = NSSplitViewItem(viewController: verticalTabsViewController)
        leftItem.canCollapse = true
        leftItem.minimumThickness = layout.leftSidebarMinWidth
        leftItem.maximumThickness = layout.leftSidebarMaxWidth
        leftItem.holdingPriority = sidebarHoldingPriority

        let centerItem = NSSplitViewItem(viewController: readerViewController)
        centerItem.minimumThickness = 320
        centerItem.holdingPriority = .defaultLow

        let rightItem = NSSplitViewItem(viewController: outlineViewController)
        rightItem.canCollapse = true
        rightItem.minimumThickness = layout.rightSidebarMinWidth
        rightItem.maximumThickness = layout.rightSidebarMaxWidth
        rightItem.holdingPriority = sidebarHoldingPriority

        leftSidebarItem = leftItem
        rightSidebarItem = rightItem
        addSplitViewItem(leftItem)
        addSplitViewItem(centerItem)
        addSplitViewItem(rightItem)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        applyStoreState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyStoreState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applySidebarWidthsForActiveSession()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard isApplyingSidebarWidths == false,
              appliedWidthsForSessionID != nil,
              let sessionID = documentStore.activeSessionID,
              appliedWidthsForSessionID == sessionID else { return }

        let leftWidth = leftSidebarItem?.isCollapsed == true
            ? nil
            : splitView.arrangedSubviews[safe: 0]?.frame.width
        let rightWidth = rightSidebarItem?.isCollapsed == true
            ? nil
            : splitView.arrangedSubviews[safe: 2]?.frame.width

        documentStore.updateSidebarWidths(
            left: leftWidth,
            right: rightWidth,
            for: sessionID
        )
    }

    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let padding: CGFloat = 10
        if splitView.isVertical {
            return NSRect(
                x: drawnRect.minX - padding,
                y: 0,
                width: drawnRect.width + padding * 2,
                height: splitView.bounds.height
            )
        }
        return NSRect(
            x: 0,
            y: drawnRect.minY - padding,
            width: splitView.bounds.width,
            height: drawnRect.height + padding * 2
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        applyStoreState()
        applySidebarWidthsForActiveSession()
    }

    private func applyStoreState() {
        let leftShouldCollapse = !documentStore.isLeftSidebarVisible
        if let leftItem = leftSidebarItem, leftItem.isCollapsed != leftShouldCollapse {
            leftItem.isCollapsed = leftShouldCollapse
        }
        let rightShouldCollapse = !documentStore.isRightSidebarVisible
        if let rightItem = rightSidebarItem, rightItem.isCollapsed != rightShouldCollapse {
            rightItem.isCollapsed = rightShouldCollapse
        }
    }

    private func applySidebarWidthsForActiveSession() {
        guard splitView.bounds.width > 0,
              splitView.arrangedSubviews.count >= 3 else { return }

        let layout = documentStore.appConfiguration.layout
        let targetLeft: CGFloat
        let targetRight: CGFloat
        let sessionID = documentStore.activeSessionID

        if let session = documentStore.activeSession {
            targetLeft = session.leftSidebarWidth ?? layout.leftSidebarWidth
            targetRight = session.rightSidebarWidth ?? layout.rightSidebarWidth
        } else {
            targetLeft = layout.leftSidebarWidth
            targetRight = layout.rightSidebarWidth
        }

        if appliedWidthsForSessionID == sessionID {
            // Already applied for this session; avoid fighting the user's drag.
            return
        }

        let clampedLeft = min(max(targetLeft, layout.leftSidebarMinWidth), layout.leftSidebarMaxWidth)
        let clampedRight = min(max(targetRight, layout.rightSidebarMinWidth), layout.rightSidebarMaxWidth)

        isApplyingSidebarWidths = true
        defer { isApplyingSidebarWidths = false }

        let total = splitView.bounds.width
        splitView.setPosition(clampedLeft, ofDividerAt: 0)
        splitView.setPosition(total - clampedRight, ofDividerAt: 1)

        appliedWidthsForSessionID = sessionID
    }

    private func purgeLegacyAutosaveKeys() {
        Self.legacyAutosaveNames.forEach { name in
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name)")
        }
        UserDefaults.standard.removeObject(forKey: "SlatePDF.Layout.lastConfigLeftWidth")
        UserDefaults.standard.removeObject(forKey: "SlatePDF.Layout.lastConfigRightWidth")
    }

    func refreshChromeColors() {
        applyChromeColors()
        verticalTabsViewController.refreshChromeColors()
        outlineViewController.refreshChromeColors()
        titlebarTabsController.refreshChromeColors()
    }

    private func applyChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = Self.splitBackgroundColor.cgColor
            splitView.layer?.backgroundColor = Self.dividerBackgroundColor.cgColor
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
