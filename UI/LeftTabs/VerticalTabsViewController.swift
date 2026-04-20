import AppKit

private final class CollapsibleContainerView: NSView {
    override var fittingSize: NSSize {
        NSSize(width: 1, height: super.fittingSize.height)
    }
}

final class VerticalTabsViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    var onCloseSessionRequested: ((UUID) -> Void)?
    var onAlternateSessionActivationRequested: ((UUID) -> Void)?
    private let countLabel = NSTextField(labelWithString: "0 open")
    private let emptyStateLabel = NSTextField(
        labelWithString: "Open multiple PDFs and switch them here.")
    private let listStackView = NSStackView()

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
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
        applyEmptyState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = CollapsibleContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        container.layer?.masksToBounds = true

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [NSView(), countLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 0
        emptyStateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        listStackView.orientation = .vertical
        listStackView.alignment = .leading
        listStackView.spacing = 5
        listStackView.translatesAutoresizingMaskIntoConstraints = false
        listStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [headerStack, emptyStateLabel, listStackView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        let pinned: [NSLayoutConstraint] = [
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
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
        ]
        pinned.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(pinned)

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
        applyEmptyState()
    }

    private func applyEmptyState() {
        let noSessions = documentStore.sessions(in: windowID).isEmpty
        listStackView.isHidden = noSessions
        emptyStateLabel.isHidden = !noSessions
    }

    private func rebuildList() {
        guard isViewLoaded else { return }

        listStackView.arrangedSubviews.forEach { subview in
            listStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let sessions = documentStore.sessions(in: windowID)
        countLabel.stringValue = "\(sessions.count) open"

        for session in sessions {
            let itemView = VerticalTabItemView(
                sessionID: session.id,
                title: session.title,
                isSelected: documentStore.activeSessionID(in: windowID) == session.id,
                isDirty: session.isDirty,
                onSelect: { [weak self] sessionID in
                    guard let self else { return }
                    self.documentStore.clearSearch(in: self.windowID)
                    self.documentStore.activate(sessionID: sessionID, in: self.windowID)
                },
                onAlternateSelect: { [weak self] sessionID in
                    self?.onAlternateSessionActivationRequested?(sessionID)
                },
                onClose: { [weak self] sessionID in
                    self?.onCloseSessionRequested?(sessionID)
                }
            )
            itemView.translatesAutoresizingMaskIntoConstraints = false
            listStackView.addArrangedSubview(itemView)
            let widthMatch = itemView.widthAnchor.constraint(equalTo: listStackView.widthAnchor)
            widthMatch.priority = .defaultHigh
            widthMatch.isActive = true
        }
    }
}
