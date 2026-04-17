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
        return NSColor(calibratedWhite: isDark ? 0.05 : 0.86, alpha: 1.0)
    }

    static let selectedChromeBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.20 : 0.90, alpha: 1.0)
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
        leftItem.minimumThickness = 180
        leftItem.maximumThickness = 260
        leftItem.preferredThicknessFraction = 0.18

        let centerItem = NSSplitViewItem(viewController: readerViewController)
        centerItem.minimumThickness = 480
        centerItem.holdingPriority = .defaultLow

        let rightItem = NSSplitViewItem(viewController: outlineViewController)
        rightItem.canCollapse = true
        rightItem.minimumThickness = 220
        rightItem.maximumThickness = 320
        rightItem.preferredThicknessFraction = 0.22

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        applyStoreState()
    }

    private func applyStoreState() {
        leftSidebarItem?.isCollapsed = !documentStore.isLeftSidebarVisible
        rightSidebarItem?.isCollapsed = !documentStore.isRightSidebarVisible
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
