import AppKit

final class SplitViewController: NSSplitViewController {
    let documentStore: DocumentStore
    let verticalTabsViewController: VerticalTabsViewController
    let readerViewController: ReaderViewController
    let outlineViewController: OutlineViewController
    let titlebarTabsController: TitlebarTabsController
    private var leftSidebarItem: NSSplitViewItem?
    private var rightSidebarItem: NSSplitViewItem?

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

        view.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"
        splitView.wantsLayer = true
        applyChromeColors()

        let leftItem = NSSplitViewItem(viewController: verticalTabsViewController)
        leftItem.canCollapse = true
        leftItem.minimumThickness = 96

        let centerItem = NSSplitViewItem(viewController: readerViewController)
        centerItem.minimumThickness = 320
        centerItem.holdingPriority = .defaultLow

        let rightItem = NSSplitViewItem(viewController: outlineViewController)
        rightItem.canCollapse = true
        rightItem.minimumThickness = 120

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
