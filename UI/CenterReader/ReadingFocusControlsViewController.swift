import AppKit

final class ReadingFocusControlsViewController: NSViewController {
    var onSettingsChanged: ((ReadingFocusSettings) -> Void)?
    var onResetToDefaults: (() -> Void)?

    private var settings: ReadingFocusSettings
    private var defaultSettings: ReadingFocusSettings
    private var isApplyingSettings = false

    private let widthModeControl = NSSegmentedControl(
        labels: ["Page", "Column", "Custom"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let customWidthSlider = NSSlider(
        value: Double(ReadingFocusSettings.default.customWidthRatio),
        minValue: Double(ReadingFocusSettings.minimumCustomWidthRatio),
        maxValue: Double(ReadingFocusSettings.maximumCustomWidthRatio),
        target: nil,
        action: nil
    )
    private let customWidthValueLabel = NSTextField(labelWithString: "72%")
    private let heightSlider = NSSlider(
        value: Double(ReadingFocusSettings.default.height),
        minValue: Double(ReadingFocusSettings.minimumHeight),
        maxValue: Double(ReadingFocusSettings.maximumHeight),
        target: nil,
        action: nil
    )
    private let heightValueLabel = NSTextField(labelWithString: "96 pt")
    private let resetButton = NSButton(title: "Use Defaults", target: nil, action: nil)

    init(settings: ReadingFocusSettings, defaultSettings: ReadingFocusSettings) {
        self.settings = settings
        self.defaultSettings = defaultSettings
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 350, height: 180)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: "Reading Focus")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureControls()

        let widthRow = makeRow(label: "Width", control: widthModeControl)
        let customWidthRow = makeSliderRow(
            label: "Custom",
            slider: customWidthSlider,
            valueLabel: customWidthValueLabel
        )
        let heightRow = makeSliderRow(
            label: "Height",
            slider: heightSlider,
            valueLabel: heightValueLabel
        )
        let controlsStack = NSStackView(views: [widthRow, customWidthRow, heightRow])
        controlsStack.orientation = .vertical
        controlsStack.alignment = .leading
        controlsStack.spacing = 9
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = NSTextField(labelWithString: "Current window only · defaults are in Settings")
        hintLabel.font = .systemFont(ofSize: 10.5)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        resetButton.controlSize = .small
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetToDefaults(_:))
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(controlsStack)
        container.addSubview(hintLabel)
        container.addSubview(resetButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),

            controlsStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            controlsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            controlsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -13),
            resetButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            resetButton.centerYAnchor.constraint(equalTo: hintLabel.centerYAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -10),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        apply(settings: settings, defaultSettings: defaultSettings)
    }

    func apply(settings: ReadingFocusSettings, defaultSettings: ReadingFocusSettings) {
        self.settings = settings
        self.defaultSettings = defaultSettings
        guard isViewLoaded else { return }

        isApplyingSettings = true
        defer { isApplyingSettings = false }
        widthModeControl.selectedSegment = ReadingFocusWidthMode.allCases.firstIndex(of: settings.widthMode) ?? 0
        customWidthSlider.doubleValue = Double(settings.customWidthRatio)
        heightSlider.doubleValue = Double(settings.height)
        refreshLabelsAndAvailability()
    }

    private func configureControls() {
        widthModeControl.identifier = NSUserInterfaceItemIdentifier("readingFocusWidthModeControl")
        widthModeControl.controlSize = .small
        widthModeControl.target = self
        widthModeControl.action = #selector(controlChanged(_:))
        widthModeControl.translatesAutoresizingMaskIntoConstraints = false

        customWidthSlider.identifier = NSUserInterfaceItemIdentifier("readingFocusCustomWidthSlider")
        customWidthSlider.controlSize = .small
        customWidthSlider.isContinuous = true
        customWidthSlider.numberOfTickMarks = 8
        customWidthSlider.allowsTickMarkValuesOnly = false
        customWidthSlider.target = self
        customWidthSlider.action = #selector(controlChanged(_:))
        customWidthSlider.translatesAutoresizingMaskIntoConstraints = false

        heightSlider.identifier = NSUserInterfaceItemIdentifier("readingFocusHeightSlider")
        heightSlider.controlSize = .small
        heightSlider.isContinuous = true
        heightSlider.numberOfTickMarks = 9
        heightSlider.allowsTickMarkValuesOnly = false
        heightSlider.target = self
        heightSlider.action = #selector(controlChanged(_:))
        heightSlider.translatesAutoresizingMaskIntoConstraints = false

        for label in [customWidthValueLabel, heightValueLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func makeRow(label title: String, control: NSView) -> NSView {
        let label = rowLabel(title)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 52),
            control.widthAnchor.constraint(equalToConstant: 230),
        ])
        return row
    }

    private func makeSliderRow(label title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let label = rowLabel(title)
        let row = NSStackView(views: [label, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 52),
            slider.widthAnchor.constraint(equalToConstant: 176),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
        ])
        return row
    }

    private func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.alignment = .right
        return label
    }

    @objc
    private func controlChanged(_ sender: Any?) {
        guard isApplyingSettings == false else { return }
        let selectedIndex = min(max(widthModeControl.selectedSegment, 0), ReadingFocusWidthMode.allCases.count - 1)
        settings.widthMode = ReadingFocusWidthMode.allCases[selectedIndex]
        settings.customWidthRatio = CGFloat(customWidthSlider.doubleValue)
        settings.height = CGFloat(heightSlider.doubleValue.rounded())
        refreshLabelsAndAvailability()
        onSettingsChanged?(settings)
    }

    @objc
    private func resetToDefaults(_ sender: Any?) {
        onResetToDefaults?()
    }

    private func refreshLabelsAndAvailability() {
        customWidthSlider.isEnabled = settings.widthMode == .custom
        customWidthValueLabel.textColor = settings.widthMode == .custom
            ? .secondaryLabelColor
            : .tertiaryLabelColor
        customWidthValueLabel.stringValue = "\(Int((settings.customWidthRatio * 100).rounded()))%"
        heightValueLabel.stringValue = "\(Int(settings.height.rounded())) pt"
        resetButton.isEnabled = settings != defaultSettings
    }
}
