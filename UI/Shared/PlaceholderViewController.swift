import AppKit

class PlaceholderViewController: NSViewController {
    /// Matches the reader surface so chrome panes stay continuous.
    static var paneBackgroundColor: NSColor { NightModeStyle.readerBackdropColor }

    static func paneBackgroundColor(opacity: CGFloat) -> NSColor {
        paneBackgroundColor.withAlphaComponent(opacity)
    }

    private let titleText: String
    private let detailText: String
    private let emptyStateView: EmptyStateView

    init(titleText: String, detailText: String) {
        self.titleText = titleText
        self.detailText = detailText
        self.emptyStateView = EmptyStateView(title: titleText, detail: detailText)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Self.paneBackgroundColor.cgColor
        container.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyStateView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            emptyStateView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
        ])

        view = container
    }

    func refreshChromeColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = Self.paneBackgroundColor.cgColor
        }
        emptyStateView.refreshChromeColors()
    }
}
