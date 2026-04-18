import AppKit

final class VerticalTabsViewController: NSViewController {
    let documentStore: DocumentStore
    var onCloseSessionRequested: ((UUID) -> Void)?
    private let titleLabel = NSTextField(labelWithString: "Documents")
    private let countLabel = NSTextField(labelWithString: "0 open")
    private let emptyStateLabel = NSTextField(
        labelWithString: "Open multiple PDFs and switch them here.")
    private let listStackView = NSStackView()

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
        title = "Documents"
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
        rebuildList()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        let headerStack = NSStackView(views: [titleLabel, NSView(), countLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 0

        listStackView.orientation = .vertical
        listStackView.alignment = .leading
        listStackView.spacing = 5
        listStackView.translatesAutoresizingMaskIntoConstraints = false

        for view in [headerStack, emptyStateLabel, listStackView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            emptyStateLabel.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -12),
            emptyStateLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),

            listStackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            listStackView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -8),
            listStackView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
            listStackView.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildList()
    }

    private func rebuildList() {
        guard isViewLoaded else { return }

        listStackView.arrangedSubviews.forEach { subview in
            listStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let sessions = documentStore.sessions
        countLabel.stringValue = "\(sessions.count) open"
        let isEmpty = sessions.isEmpty
        emptyStateLabel.isHidden = !isEmpty
        listStackView.isHidden = isEmpty

        for session in sessions {
            let itemView = VerticalTabItemView(
                sessionID: session.id,
                title: session.title,
                isSelected: documentStore.activeSessionID == session.id,
                isDirty: session.isDirty,
                onSelect: { [weak self] sessionID in
                    self?.documentStore.activate(sessionID: sessionID)
                },
                onClose: { [weak self] sessionID in
                    self?.onCloseSessionRequested?(sessionID)
                }
            )
            itemView.translatesAutoresizingMaskIntoConstraints = false
            listStackView.addArrangedSubview(itemView)
            itemView.widthAnchor.constraint(equalTo: listStackView.widthAnchor).isActive = true
        }
    }
}
