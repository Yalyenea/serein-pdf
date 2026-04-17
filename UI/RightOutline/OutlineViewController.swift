import AppKit

final class OutlineViewController: PlaceholderViewController {
    let documentStore: DocumentStore

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(
            titleText: "Outline",
            detailText: "PDF outline will appear here for the active document."
        )
        title = "Outline"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
