import AppKit
import PDFKit

final class ReaderViewController: NSViewController {
    let documentStore: DocumentStore
    let pdfView = PDFView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF to start reading.")

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
        title = "Reader"
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
        refreshDisplayedDocument()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.white
        pdfView.isHidden = true

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor

        container.addSubview(pdfView)
        container.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        view = container
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        refreshDisplayedDocument()
    }

    private func refreshDisplayedDocument() {
        guard isViewLoaded else { return }

        if let session = documentStore.activeSession {
            pdfView.document = session.pdfDocument
            pdfView.isHidden = false
            emptyStateLabel.isHidden = true
        } else {
            pdfView.document = nil
            pdfView.isHidden = true
            emptyStateLabel.isHidden = false
        }
    }
}
