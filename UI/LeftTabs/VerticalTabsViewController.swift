import AppKit
import PDFKit

final class VerticalTabsViewController: NSViewController {
    enum Mode: Int { case tabs = 0, thumbnails = 1 }

    let documentStore: DocumentStore
    var onCloseSessionRequested: ((UUID) -> Void)?
    private let countLabel = NSTextField(labelWithString: "0 open")
    private let emptyStateLabel = NSTextField(
        labelWithString: "Open multiple PDFs and switch them here.")
    private let listStackView = NSStackView()
    private let modeSegmented = NSSegmentedControl()
    private let thumbnailView = PDFThumbnailView()
    private var mode: Mode = .tabs

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
        title = "Documents"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pdfView: PDFView) {
        thumbnailView.pdfView = pdfView
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
        applyMode()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        let headerStack = NSStackView(views: [NSView(), countLabel])
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

        modeSegmented.segmentCount = 2
        modeSegmented.setLabel("Tabs", forSegment: 0)
        modeSegmented.setLabel("Pages", forSegment: 1)
        modeSegmented.selectedSegment = 0
        modeSegmented.controlSize = .small
        modeSegmented.segmentStyle = .rounded
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))

        thumbnailView.thumbnailSize = NSSize(width: 96, height: 128)
        thumbnailView.maximumNumberOfColumns = 1
        thumbnailView.backgroundColor = .clear

        for view in [modeSegmented, headerStack, emptyStateLabel, listStackView, thumbnailView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            modeSegmented.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            modeSegmented.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            modeSegmented.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),

            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            headerStack.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
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

            thumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: modeSegmented.bottomAnchor, constant: 10),
            thumbnailView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .tabs
        applyMode()
    }

    private func applyMode() {
        let isTabs = mode == .tabs
        let noSessions = documentStore.sessions.isEmpty
        listStackView.isHidden = !isTabs || noSessions
        emptyStateLabel.isHidden = !isTabs || !noSessions
        countLabel.isHidden = !isTabs
        thumbnailView.isHidden = isTabs
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor.cgColor
        }
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildList()
        applyMode()
    }

    private func rebuildList() {
        guard isViewLoaded else { return }

        listStackView.arrangedSubviews.forEach { subview in
            listStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let sessions = documentStore.sessions
        countLabel.stringValue = "\(sessions.count) open"

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
