import AppKit

/// Shared empty-state copy block (M12-013): one typography / color language for
/// sidebar and placeholder panes. Hosts own placement — top-aligned under a
/// section header or centered in a pane — and the surrounding pane surface.
final class EmptyStateView: NSView {
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let stackView = NSStackView()

    init(title: String, detail: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NightModeStyle.secondaryTextColor
        titleLabel.alignment = .center
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.stringValue = detail ?? ""
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = NightModeStyle.secondaryTextColor
        detailLabel.alignment = .center
        detailLabel.isHidden = detail == nil
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(detailLabel)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshChromeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            titleLabel.textColor = NightModeStyle.secondaryTextColor
            detailLabel.textColor = NightModeStyle.secondaryTextColor
        }
    }
}
