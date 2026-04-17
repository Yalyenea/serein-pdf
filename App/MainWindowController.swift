import AppKit

final class MainWindowController: NSWindowController {
    let documentStore: DocumentStore

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        let contentViewController = SplitViewController(documentStore: documentStore)
        let window = NSWindow(contentViewController: contentViewController)

        window.title = "SlatePDF"
        window.setContentSize(NSSize(width: 1360, height: 900))
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        refreshWindowTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        refreshWindowTitle()
    }

    private func refreshWindowTitle() {
        window?.title = documentStore.activeSession?.title ?? "SlatePDF"
    }
}
