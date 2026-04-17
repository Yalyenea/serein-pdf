import AppKit

final class SplitViewController: NSSplitViewController {
    let documentStore: DocumentStore
    let verticalTabsViewController: VerticalTabsViewController
    let readerViewController: ReaderViewController
    let outlineViewController: OutlineViewController
    let titlebarTabsController: TitlebarTabsController

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

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0).cgColor
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor(calibratedWhite: 0.86, alpha: 1.0).cgColor

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

        addSplitViewItem(leftItem)
        addSplitViewItem(centerItem)
        addSplitViewItem(rightItem)
    }
}
