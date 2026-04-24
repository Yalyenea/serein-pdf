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
    var onOpenRecentURLRequested: ((URL) -> Void)?
    private let countLabel = NSTextField(labelWithString: "0 open")
    private let emptyStateLabel = NSTextField(
        labelWithString: "Open multiple PDFs and switch them here.")
    private let listStackView = NSStackView()
    private let recentSectionContainer = NSStackView()
    private let recentTitleLabel = NSTextField(labelWithString: "Recent PDFs")
    private let recentListStackView = NSStackView()
    private var recentButtons: [NSButton] = []
    private var recentButtonURLs: [URL] = []
    private static let recentDisplayLimit = 5

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

        recentSectionContainer.orientation = .vertical
        recentSectionContainer.alignment = .leading
        recentSectionContainer.spacing = 6
        recentSectionContainer.translatesAutoresizingMaskIntoConstraints = false

        recentTitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        recentTitleLabel.textColor = .tertiaryLabelColor

        recentListStackView.orientation = .vertical
        recentListStackView.alignment = .leading
        recentListStackView.spacing = 2
        recentListStackView.translatesAutoresizingMaskIntoConstraints = false

        recentSectionContainer.addArrangedSubview(recentTitleLabel)
        recentSectionContainer.addArrangedSubview(recentListStackView)

        for view in [headerStack, emptyStateLabel, listStackView, recentSectionContainer] {
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

            recentSectionContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            recentSectionContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            recentSectionContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            listStackView.bottomAnchor.constraint(
                lessThanOrEqualTo: recentSectionContainer.topAnchor, constant: -10),
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

        rebuildRecentList()
    }

    private func rebuildRecentList() {
        recentButtons.removeAll(keepingCapacity: true)
        recentButtonURLs.removeAll(keepingCapacity: true)
        recentListStackView.arrangedSubviews.forEach { subview in
            recentListStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let shouldShowRecents = documentStore.appConfiguration.layout.showRecentFilesInSidebar
        let recentURLs = Array(documentStore.recentDocumentURLs.prefix(Self.recentDisplayLimit))
        guard shouldShowRecents, recentURLs.isEmpty == false else {
            recentSectionContainer.isHidden = true
            return
        }

        recentSectionContainer.isHidden = false
        for url in recentURLs {
            let button = NSButton(title: url.deletingPathExtension().lastPathComponent, target: self, action: #selector(openRecentDocument(_:)))
            button.isBordered = false
            button.alignment = .left
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .regular)
            button.contentTintColor = .secondaryLabelColor
            button.setButtonType(.momentaryChange)
            button.bezelStyle = .regularSquare
            button.lineBreakMode = .byTruncatingMiddle
            button.translatesAutoresizingMaskIntoConstraints = false
            button.toolTip = url.path
            button.tag = recentButtons.count
            button.target = self
            button.action = #selector(openRecentDocument(_:))
            recentListStackView.addArrangedSubview(button)
            let widthMatch = button.widthAnchor.constraint(equalTo: recentListStackView.widthAnchor)
            widthMatch.priority = .defaultHigh
            widthMatch.isActive = true
            recentButtons.append(button)
            recentButtonURLs.append(url)
        }
    }

    @objc
    private func openRecentDocument(_ sender: NSButton) {
        guard recentButtonURLs.indices.contains(sender.tag) else { return }
        onOpenRecentURLRequested?(recentButtonURLs[sender.tag])
    }
}

#if DEBUG
extension VerticalTabsViewController {
    var testingRecentFileTitles: [String] {
        recentButtons.map(\.title)
    }

    var testingRecentSectionVisible: Bool {
        recentSectionContainer.isHidden == false
    }

    func testingTriggerOpenRecent(at index: Int) {
        guard recentButtons.indices.contains(index) else { return }
        recentButtons[index].performClick(nil)
    }
}
#endif
