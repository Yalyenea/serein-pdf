import AppKit

final class TitlebarTabsController: NSViewController {
    let documentStore: DocumentStore

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
