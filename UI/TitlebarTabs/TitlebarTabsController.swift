import AppKit

final class TitlebarTabsController: NSViewController {
    let documentStore: DocumentStore
    var onCloseSessionRequested: ((UUID) -> Void)?
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let documentContainerView = NSView()
    private let bottomBorderView = NSView()
    private var isTabsStripVisible = true

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 720, height: 28)
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
        rebuildTabs()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView()
        container.frame = NSRect(x: 0, y: 0, width: 720, height: 28)
        container.wantsLayer = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentContainerView.wantsLayer = true
        documentContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        documentContainerView.addSubview(stackView)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentContainerView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        bottomBorderView.wantsLayer = true
        bottomBorderView.translatesAutoresizingMaskIntoConstraints = false
        bottomBorderView.isHidden = !isTabsStripVisible

        container.addSubview(scrollView)
        container.addSubview(bottomBorderView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBorderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBorderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBorderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBorderView.heightAnchor.constraint(equalToConstant: 1),
            container.heightAnchor.constraint(equalToConstant: 28),
            stackView.leadingAnchor.constraint(equalTo: documentContainerView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: documentContainerView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: documentContainerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentContainerView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
        ])

        view = container
        applyChromeColors()
        applyVisibilityState()
    }

    func refreshChromeColors() {
        guard isViewLoaded else { return }
        applyChromeColors()
    }

    private func applyChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = SplitViewController.splitBackgroundColor.cgColor
            bottomBorderView.layer?.backgroundColor = SplitViewController.dividerBackgroundColor.cgColor
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateDocumentContainerFrame()
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        rebuildTabs()
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }

        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for session in documentStore.sessions {
            let itemView = TitlebarTabItemView(
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
            stackView.addArrangedSubview(itemView)
        }

        updateDocumentContainerFrame()
    }

    private func updateDocumentContainerFrame() {
        let fittingWidth = stackView.fittingSize.width + 16
        let contentWidth = max(scrollView.contentSize.width, fittingWidth)
        documentContainerView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 28)
    }

    func setTabsStripVisible(_ isVisible: Bool) {
        isTabsStripVisible = isVisible
        preferredContentSize = isVisible ? NSSize(width: 720, height: 28) : NSSize(width: 1, height: 1)
        guard isViewLoaded else { return }
        applyVisibilityState()
    }

    private func applyVisibilityState() {
        view.isHidden = !isTabsStripVisible
        scrollView.isHidden = !isTabsStripVisible
        bottomBorderView.isHidden = !isTabsStripVisible
        view.frame.size = preferredContentSize
    }
}
