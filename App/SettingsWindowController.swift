import AppKit

final class SettingsWindowController: NSWindowController {
    private let settingsViewController: SettingsViewController

    init(
        configuration: AppConfiguration,
        onConfigurationChanged: @escaping (AppConfiguration) -> Void
    ) {
        settingsViewController = SettingsViewController(configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.title = "Settings"
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        settingsViewController.onConfigurationChanged = onConfigurationChanged
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func sync(configuration: AppConfiguration) {
        settingsViewController.apply(configuration: configuration)
    }
}

private final class SettingsViewController: NSViewController {
    var onConfigurationChanged: ((AppConfiguration) -> Void)?

    private var configuration: AppConfiguration
    private let displayModePopUp = NSPopUpButton()
    private let fitWidthCheckbox = NSButton(
        checkboxWithTitle: "Fit width when opening a document",
        target: nil,
        action: nil
    )
    private let autoSavePopUp = NSPopUpButton()
    private let footnoteLabel = NSTextField(
        wrappingLabelWithString: "Reader defaults apply to newly opened PDFs. Auto-save applies immediately to open PDFs."
    )
    private var isApplyingConfiguration = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = NSView()

        displayModePopUp.translatesAutoresizingMaskIntoConstraints = false
        displayModePopUp.controlSize = .small
        displayModePopUp.target = self
        displayModePopUp.action = #selector(handleControlChanged(_:))

        fitWidthCheckbox.translatesAutoresizingMaskIntoConstraints = false
        fitWidthCheckbox.controlSize = .small
        fitWidthCheckbox.target = self
        fitWidthCheckbox.action = #selector(handleControlChanged(_:))

        autoSavePopUp.translatesAutoresizingMaskIntoConstraints = false
        autoSavePopUp.controlSize = .small
        autoSavePopUp.target = self
        autoSavePopUp.action = #selector(handleControlChanged(_:))

        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.font = .systemFont(ofSize: 11)
        footnoteLabel.textColor = .secondaryLabelColor
        footnoteLabel.maximumNumberOfLines = 0

        let grid = NSGridView(views: [
            [makeRowLabel("Default Display"), displayModePopUp],
            [makeRowLabel("Open Behavior"), fitWidthCheckbox],
            [makeRowLabel("Annotation Auto-Save"), autoSavePopUp],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 18
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        contentView.addSubview(grid)
        contentView.addSubview(footnoteLabel)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            displayModePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            autoSavePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            footnoteLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            footnoteLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            footnoteLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        for mode in ReaderDisplayMode.allCases {
            displayModePopUp.addItem(withTitle: mode.menuTitle)
            displayModePopUp.lastItem?.representedObject = mode.rawValue
        }

        for policy in AnnotationSavePolicy.allCases {
            autoSavePopUp.addItem(withTitle: policy.menuTitle)
            autoSavePopUp.lastItem?.representedObject = policy.rawValue
        }

        apply(configuration: configuration)
    }

    func apply(configuration: AppConfiguration) {
        self.configuration = configuration
        guard isViewLoaded else { return }

        isApplyingConfiguration = true
        defer { isApplyingConfiguration = false }

        selectItem(
            in: displayModePopUp,
            matching: configuration.reader.defaultDisplayMode.rawValue
        )
        fitWidthCheckbox.state = configuration.reader.fitWidthOnOpen ? .on : .off
        selectItem(
            in: autoSavePopUp,
            matching: configuration.annotations.autoSavePolicy.rawValue
        )
    }

    @objc
    private func handleControlChanged(_ sender: Any?) {
        guard isApplyingConfiguration == false else { return }
        guard let displayModeRawValue = displayModePopUp.selectedItem?.representedObject as? String,
              let displayMode = ReaderDisplayMode(rawValue: displayModeRawValue),
              let autoSaveRawValue = autoSavePopUp.selectedItem?.representedObject as? String,
              let autoSavePolicy = AnnotationSavePolicy(rawValue: autoSaveRawValue) else {
            return
        }

        var updatedConfiguration = configuration
        updatedConfiguration.reader.defaultDisplayMode = displayMode
        updatedConfiguration.reader.fitWidthOnOpen = fitWidthCheckbox.state == .on
        updatedConfiguration.annotations.autoSavePolicy = autoSavePolicy

        guard updatedConfiguration != configuration else { return }
        configuration = updatedConfiguration
        onConfigurationChanged?(updatedConfiguration)
    }

    private func selectItem(in popUpButton: NSPopUpButton, matching rawValue: String) {
        guard let item = popUpButton.itemArray.first(where: {
            ($0.representedObject as? String) == rawValue
        }) else {
            return
        }

        popUpButton.select(item)
    }

    private func makeRowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}
