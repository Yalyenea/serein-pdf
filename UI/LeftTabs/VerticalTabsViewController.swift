import AppKit

final class VerticalTabsViewController: PlaceholderViewController {
    let documentStore: DocumentStore

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(
            titleText: "Documents",
            detailText: "Vertical tabs will list open PDF sessions here."
        )
        title = "Documents"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
