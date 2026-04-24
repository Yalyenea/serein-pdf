import AppKit

private enum SettingsWindowMetrics {
    static let generalContentSize = NSSize(width: 520, height: 367)
    static let shortcutsContentSize = NSSize(width: 920, height: 620)
}

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindowController: NSWindowController {
    private let settingsViewController: SettingsViewController
    private var pendingContentSize: NSSize?

    init(
        configuration: AppConfiguration,
        onConfigurationChanged: @escaping (AppConfiguration) -> Void
    ) {
        settingsViewController = SettingsViewController(configuration: configuration)
        settingsViewController.loadViewIfNeeded()
        let initialContentSize = settingsViewController.preferredContentSizeForCurrentPage()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
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
        settingsViewController.onPreferredContentSizeChanged = { [weak self] size in
            self?.schedulePreferredWindowSize(size)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func sync(configuration: AppConfiguration) {
        settingsViewController.apply(configuration: configuration)
    }

#if DEBUG
    func selectPageForTesting(_ index: Int) {
        settingsViewController.selectPageForTesting(index)
        applyPreferredWindowSize(settingsViewController.preferredContentSizeForCurrentPage())
    }
#endif

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        applyPreferredWindowSize(settingsViewController.preferredContentSizeForCurrentPage())
    }

    private func schedulePreferredWindowSize(_ contentSize: NSSize) {
        let snappedSize = snappedContentSize(contentSize)
        pendingContentSize = snappedSize
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingContentSize == snappedSize else { return }
            self.pendingContentSize = nil
            self.applyPreferredWindowSize(snappedSize)
        }
    }

    private func applyPreferredWindowSize(_ contentSize: NSSize) {
        guard let window else { return }
        let snappedSize = snappedContentSize(contentSize)
        guard window.contentRect(forFrameRect: window.frame).size != snappedSize else { return }
        window.setContentSize(snappedSize)
    }

    private func snappedContentSize(_ contentSize: NSSize) -> NSSize {
        NSSize(width: ceil(contentSize.width), height: ceil(contentSize.height))
    }
}

private enum SettingsPage: Int {
    case general = 0
    case shortcuts = 1
}

private final class ShortcutCaptureButton: NSButton {
    var shortcut: KeyboardShortcut? {
        didSet { updateTitle() }
    }

    var onShortcutCaptured: ((KeyboardShortcut?) -> Void)?
    private var isCapturing = false {
        didSet { updateTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginCapture(_:))
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc
    private func beginCapture(_ sender: Any?) {
        isCapturing = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let modifiers = Set(
            KeyboardShortcutModifier.allCases.filter { event.modifierFlags.contains($0.eventModifier) }
        )
        if modifiers.isEmpty, [51, 117].contains(Int(event.keyCode)) {
            isCapturing = false
            onShortcutCaptured?(nil)
            return
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            NSSound.beep()
            return
        }
        let key = switch characters {
        case "\u{1b}":
            "escape"
        case " ":
            "space"
        default:
            characters
        }

        guard key.count == 1 || key == "escape" || key == "space" else {
            NSSound.beep()
            return
        }

        isCapturing = false
        onShortcutCaptured?(KeyboardShortcut(key: key, modifiers: modifiers))
    }

    private func updateTitle() {
        if isCapturing {
            title = "Type Shortcut"
            return
        }
        title = shortcut?.displayString ?? "None"
    }
}

private final class SettingsViewController: NSViewController {
    var onConfigurationChanged: ((AppConfiguration) -> Void)?
    var onPreferredContentSizeChanged: ((NSSize) -> Void)?

    private var configuration: AppConfiguration
    private var isApplyingConfiguration = false

    private let pageControl = NSSegmentedControl(labels: ["General", "Shortcuts"], trackingMode: .selectOne, target: nil, action: nil)
    private let generalContainer = NSView()
    private let shortcutsScrollView = NSScrollView()
    private let shortcutsContentView = FlippedContentView()
    private let shortcutsStackView = NSStackView()
    private let shortcutsHintLabel = NSTextField(
        wrappingLabelWithString: "Click a shortcut to capture. Press Delete while capturing to clear. Changes apply immediately."
    )
    private let shortcutsErrorLabel = NSTextField(labelWithString: "")

    private let modePopUp = NSPopUpButton()
    private let lightThemePopUp = NSPopUpButton()
    private let darkThemePopUp = NSPopUpButton()
    private let displayModePopUp = NSPopUpButton()
    private let fitWidthCheckbox = NSButton(
        checkboxWithTitle: "Fit width when opening a document",
        target: nil,
        action: nil
    )
    private let autoSavePopUp = NSPopUpButton()
    private let swapSidebarsCheckbox = NSButton(
        checkboxWithTitle: "Swap left and right sidebars",
        target: nil,
        action: nil
    )
    private let showRecentInSidebarCheckbox = NSButton(
        checkboxWithTitle: "Show recent PDFs in left sidebar footer",
        target: nil,
        action: nil
    )
    private let footnoteLabel = NSTextField(
        wrappingLabelWithString: "Reader defaults apply to newly opened PDFs. Auto-save applies immediately to open PDFs."
    )

    private var shortcutButtons: [ShortcutCommand: ShortcutCaptureButton] = [:]
    private var shortcutDefaultLabels: [ShortcutCommand: NSTextField] = [:]
    private var shortcutClearButtons: [ShortcutCommand: NSButton] = [:]
    private var shortcutRestoreButtons: [ShortcutCommand: NSButton] = [:]

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

        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.selectedSegment = SettingsPage.general.rawValue
        pageControl.controlSize = .small
        pageControl.target = self
        pageControl.action = #selector(handlePageChanged(_:))

        buildGeneralPage()
        buildShortcutsPage()

        generalContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutsScrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(pageControl)
        contentView.addSubview(generalContainer)
        contentView.addSubview(shortcutsScrollView)

        NSLayoutConstraint.activate([
            pageControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            generalContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            generalContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            generalContainer.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 14),
            generalContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            shortcutsScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shortcutsScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shortcutsScrollView.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 14),
            shortcutsScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        for mode in ReaderDisplayMode.allCases {
            displayModePopUp.addItem(withTitle: mode.menuTitle)
            displayModePopUp.lastItem?.representedObject = mode.rawValue
        }

        for mode in AppearanceMode.allCases {
            modePopUp.addItem(withTitle: mode.menuTitle)
            modePopUp.lastItem?.representedObject = mode.rawValue
        }

        for theme in LightTheme.allCases {
            lightThemePopUp.addItem(withTitle: theme.menuTitle)
            lightThemePopUp.lastItem?.representedObject = theme.rawValue
        }

        for theme in DarkTheme.allCases {
            darkThemePopUp.addItem(withTitle: theme.menuTitle)
            darkThemePopUp.lastItem?.representedObject = theme.rawValue
        }

        for policy in AnnotationSavePolicy.allCases {
            autoSavePopUp.addItem(withTitle: policy.menuTitle)
            autoSavePopUp.lastItem?.representedObject = policy.rawValue
        }

        rebuildShortcutRows()
        apply(configuration: configuration)
        applySelectedPage()
    }

    func preferredContentSizeForCurrentPage() -> NSSize {
        preferredContentSize(for: SettingsPage(rawValue: pageControl.selectedSegment) ?? .general)
    }

    func apply(configuration: AppConfiguration) {
        self.configuration = configuration
        guard isViewLoaded else { return }

        isApplyingConfiguration = true
        defer { isApplyingConfiguration = false }

        selectItem(in: modePopUp, matching: configuration.appearance.mode.rawValue)
        selectItem(in: lightThemePopUp, matching: configuration.appearance.lightTheme.rawValue)
        selectItem(in: darkThemePopUp, matching: configuration.appearance.darkTheme.rawValue)
        selectItem(in: displayModePopUp, matching: configuration.reader.defaultDisplayMode.rawValue)
        fitWidthCheckbox.state = configuration.reader.fitWidthOnOpen ? .on : .off
        selectItem(in: autoSavePopUp, matching: configuration.annotations.autoSavePolicy.rawValue)
        swapSidebarsCheckbox.state = configuration.layout.sidebarsSwapped ? .on : .off
        showRecentInSidebarCheckbox.state = configuration.layout.showRecentFilesInSidebar ? .on : .off
        shortcutsErrorLabel.stringValue = ""

        for command in ShortcutCommand.allCases {
            shortcutButtons[command]?.shortcut = configuration.shortcuts.bindings[command]
            shortcutDefaultLabels[command]?.stringValue =
                "Default: \(AppConfiguration.default.shortcuts.bindings[command]?.displayString ?? "None")"
            shortcutClearButtons[command]?.isEnabled = configuration.shortcuts.bindings[command] != nil
            shortcutRestoreButtons[command]?.isEnabled =
                configuration.shortcuts.bindings[command] != AppConfiguration.default.shortcuts.bindings[command]
        }

    }

    @objc
    private func handlePageChanged(_ sender: Any?) {
        applySelectedPage()
    }

#if DEBUG
    func selectPageForTesting(_ index: Int) {
        pageControl.selectedSegment = index
        applySelectedPage()
    }
#endif

    @objc
    private func handleGeneralControlChanged(_ sender: Any?) {
        guard isApplyingConfiguration == false else { return }
        guard let modeRawValue = modePopUp.selectedItem?.representedObject as? String,
              let mode = AppearanceMode(rawValue: modeRawValue),
              let lightThemeRawValue = lightThemePopUp.selectedItem?.representedObject as? String,
              let lightTheme = LightTheme(rawValue: lightThemeRawValue),
              let darkThemeRawValue = darkThemePopUp.selectedItem?.representedObject as? String,
              let darkTheme = DarkTheme(rawValue: darkThemeRawValue),
              let displayModeRawValue = displayModePopUp.selectedItem?.representedObject as? String,
              let displayMode = ReaderDisplayMode(rawValue: displayModeRawValue),
              let autoSaveRawValue = autoSavePopUp.selectedItem?.representedObject as? String,
              let autoSavePolicy = AnnotationSavePolicy(rawValue: autoSaveRawValue) else {
            return
        }

        var updatedConfiguration = configuration
        updatedConfiguration.appearance.mode = mode
        updatedConfiguration.appearance.lightTheme = lightTheme
        updatedConfiguration.appearance.darkTheme = darkTheme
        updatedConfiguration.reader.defaultDisplayMode = displayMode
        updatedConfiguration.reader.fitWidthOnOpen = fitWidthCheckbox.state == .on
        updatedConfiguration.annotations.autoSavePolicy = autoSavePolicy
        updatedConfiguration.layout.sidebarsSwapped = swapSidebarsCheckbox.state == .on
        updatedConfiguration.layout.showRecentFilesInSidebar = showRecentInSidebarCheckbox.state == .on
        publishConfigurationIfChanged(updatedConfiguration)
    }

    private func applySelectedPage() {
        let page = SettingsPage(rawValue: pageControl.selectedSegment) ?? .general
        generalContainer.isHidden = page != .general
        shortcutsScrollView.isHidden = page != .shortcuts
        if page == .shortcuts {
            shortcutsScrollView.contentView.scroll(to: .zero)
            shortcutsScrollView.reflectScrolledClipView(shortcutsScrollView.contentView)
        }
        onPreferredContentSizeChanged?(preferredContentSize(for: page))
    }

    private func buildGeneralPage() {
        modePopUp.translatesAutoresizingMaskIntoConstraints = false
        modePopUp.controlSize = .small
        modePopUp.target = self
        modePopUp.action = #selector(handleGeneralControlChanged(_:))

        lightThemePopUp.translatesAutoresizingMaskIntoConstraints = false
        lightThemePopUp.controlSize = .small
        lightThemePopUp.target = self
        lightThemePopUp.action = #selector(handleGeneralControlChanged(_:))

        darkThemePopUp.translatesAutoresizingMaskIntoConstraints = false
        darkThemePopUp.controlSize = .small
        darkThemePopUp.target = self
        darkThemePopUp.action = #selector(handleGeneralControlChanged(_:))

        displayModePopUp.translatesAutoresizingMaskIntoConstraints = false
        displayModePopUp.controlSize = .small
        displayModePopUp.target = self
        displayModePopUp.action = #selector(handleGeneralControlChanged(_:))

        fitWidthCheckbox.translatesAutoresizingMaskIntoConstraints = false
        fitWidthCheckbox.controlSize = .small
        fitWidthCheckbox.target = self
        fitWidthCheckbox.action = #selector(handleGeneralControlChanged(_:))

        autoSavePopUp.translatesAutoresizingMaskIntoConstraints = false
        autoSavePopUp.controlSize = .small
        autoSavePopUp.target = self
        autoSavePopUp.action = #selector(handleGeneralControlChanged(_:))

        swapSidebarsCheckbox.translatesAutoresizingMaskIntoConstraints = false
        swapSidebarsCheckbox.controlSize = .small
        swapSidebarsCheckbox.target = self
        swapSidebarsCheckbox.action = #selector(handleGeneralControlChanged(_:))

        showRecentInSidebarCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showRecentInSidebarCheckbox.controlSize = .small
        showRecentInSidebarCheckbox.target = self
        showRecentInSidebarCheckbox.action = #selector(handleGeneralControlChanged(_:))

        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.font = .systemFont(ofSize: 11)
        footnoteLabel.textColor = .secondaryLabelColor
        footnoteLabel.maximumNumberOfLines = 0

        let layoutOptionsStack = NSStackView(views: [swapSidebarsCheckbox, showRecentInSidebarCheckbox])
        layoutOptionsStack.orientation = .vertical
        layoutOptionsStack.alignment = .leading
        layoutOptionsStack.spacing = 6
        layoutOptionsStack.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [makeRowLabel("Mode"), modePopUp],
            [makeRowLabel("Light Theme"), lightThemePopUp],
            [makeRowLabel("Dark Theme"), darkThemePopUp],
            [makeRowLabel("Default Display"), displayModePopUp],
            [makeRowLabel("Open Behavior"), fitWidthCheckbox],
            [makeRowLabel("Annotation Auto-Save"), autoSavePopUp],
            [makeRowLabel("Layout"), layoutOptionsStack],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 18
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        generalContainer.addSubview(grid)
        generalContainer.addSubview(footnoteLabel)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: generalContainer.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: generalContainer.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: generalContainer.topAnchor, constant: 20),
            modePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            lightThemePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            darkThemePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            displayModePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            autoSavePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            footnoteLabel.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: generalContainer.trailingAnchor, constant: -24),
            footnoteLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            footnoteLabel.bottomAnchor.constraint(lessThanOrEqualTo: generalContainer.bottomAnchor, constant: -20),
        ])
    }

    private func buildShortcutsPage() {
        shortcutsHintLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutsHintLabel.font = .systemFont(ofSize: 11)
        shortcutsHintLabel.textColor = .secondaryLabelColor
        shortcutsHintLabel.maximumNumberOfLines = 0

        shortcutsErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutsErrorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutsErrorLabel.textColor = .systemRed
        shortcutsErrorLabel.maximumNumberOfLines = 0

        shortcutsStackView.orientation = .vertical
        shortcutsStackView.spacing = 8
        shortcutsStackView.translatesAutoresizingMaskIntoConstraints = false

        shortcutsContentView.translatesAutoresizingMaskIntoConstraints = false
        shortcutsContentView.addSubview(shortcutsHintLabel)
        shortcutsContentView.addSubview(shortcutsErrorLabel)
        shortcutsContentView.addSubview(shortcutsStackView)

        NSLayoutConstraint.activate([
            shortcutsHintLabel.leadingAnchor.constraint(equalTo: shortcutsContentView.leadingAnchor, constant: 20),
            shortcutsHintLabel.trailingAnchor.constraint(equalTo: shortcutsContentView.trailingAnchor, constant: -20),
            shortcutsHintLabel.topAnchor.constraint(equalTo: shortcutsContentView.topAnchor, constant: 18),

            shortcutsErrorLabel.leadingAnchor.constraint(equalTo: shortcutsHintLabel.leadingAnchor),
            shortcutsErrorLabel.trailingAnchor.constraint(equalTo: shortcutsHintLabel.trailingAnchor),
            shortcutsErrorLabel.topAnchor.constraint(equalTo: shortcutsHintLabel.bottomAnchor, constant: 8),

            shortcutsStackView.leadingAnchor.constraint(equalTo: shortcutsContentView.leadingAnchor, constant: 20),
            shortcutsStackView.trailingAnchor.constraint(equalTo: shortcutsContentView.trailingAnchor, constant: -20),
            shortcutsStackView.topAnchor.constraint(equalTo: shortcutsErrorLabel.bottomAnchor, constant: 14),
            shortcutsStackView.bottomAnchor.constraint(equalTo: shortcutsContentView.bottomAnchor, constant: -20),
            shortcutsStackView.widthAnchor.constraint(equalTo: shortcutsContentView.widthAnchor, constant: -40),
        ])

        shortcutsScrollView.drawsBackground = false
        shortcutsScrollView.borderType = .noBorder
        shortcutsScrollView.hasHorizontalScroller = false
        shortcutsScrollView.hasVerticalScroller = true
        shortcutsScrollView.autohidesScrollers = true
        shortcutsScrollView.documentView = shortcutsContentView

        NSLayoutConstraint.activate([
            shortcutsContentView.leadingAnchor.constraint(equalTo: shortcutsScrollView.contentView.leadingAnchor),
            shortcutsContentView.trailingAnchor.constraint(equalTo: shortcutsScrollView.contentView.trailingAnchor),
            shortcutsContentView.topAnchor.constraint(equalTo: shortcutsScrollView.contentView.topAnchor),
            shortcutsContentView.bottomAnchor.constraint(greaterThanOrEqualTo: shortcutsScrollView.contentView.bottomAnchor),
            shortcutsContentView.widthAnchor.constraint(equalTo: shortcutsScrollView.contentView.widthAnchor),
        ])
    }

    private func rebuildShortcutRows() {
        shortcutsStackView.arrangedSubviews.forEach { view in
            shortcutsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shortcutButtons.removeAll(keepingCapacity: true)
        shortcutDefaultLabels.removeAll(keepingCapacity: true)
        shortcutClearButtons.removeAll(keepingCapacity: true)
        shortcutRestoreButtons.removeAll(keepingCapacity: true)

        for command in ShortcutCommand.allCases {
            let row = makeShortcutRow(for: command)
            shortcutsStackView.addArrangedSubview(row)
        }
    }

    private func makeShortcutRow(for command: ShortcutCommand) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: command.menuTitle)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let captureButton = ShortcutCaptureButton(frame: .zero)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.onShortcutCaptured = { [weak self] shortcut in
            self?.updateShortcut(shortcut, for: command)
        }

        let defaultLabel = NSTextField(labelWithString: "")
        defaultLabel.font = .systemFont(ofSize: 11)
        defaultLabel.textColor = .secondaryLabelColor
        defaultLabel.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
        clearButton.controlSize = .small
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        let restoreButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreShortcutDefault(_:)))
        restoreButton.controlSize = .small
        restoreButton.bezelStyle = .rounded
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        row.addSubview(titleLabel)
        row.addSubview(captureButton)
        row.addSubview(defaultLabel)
        row.addSubview(clearButton)
        row.addSubview(restoreButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 220),

            captureButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            captureButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 128),

            defaultLabel.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 12),
            defaultLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            defaultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            restoreButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            restoreButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: restoreButton.centerYAnchor),

            row.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])

        shortcutButtons[command] = captureButton
        shortcutDefaultLabels[command] = defaultLabel
        shortcutClearButtons[command] = clearButton
        shortcutRestoreButtons[command] = restoreButton
        return row
    }

    @objc
    private func clearShortcut(_ sender: NSButton) {
        guard let command = sender.identifier.flatMap({ ShortcutCommand(rawValue: $0.rawValue) }) else { return }
        updateShortcut(nil, for: command)
    }

    @objc
    private func restoreShortcutDefault(_ sender: NSButton) {
        guard let command = sender.identifier.flatMap({ ShortcutCommand(rawValue: $0.rawValue) }) else { return }
        updateShortcut(AppConfiguration.default.shortcuts.bindings[command], for: command)
    }

    private func updateShortcut(_ shortcut: KeyboardShortcut?, for command: ShortcutCommand) {
        guard isApplyingConfiguration == false else { return }

        if let shortcut,
           let conflict = configuration.shortcuts.bindings.first(where: { $0.key != command && $0.value == shortcut }) {
            shortcutsErrorLabel.stringValue = "“\(shortcut.displayString)” is already used by “\(conflict.key.menuTitle)”."
            NSSound.beep()
            apply(configuration: configuration)
            return
        }

        shortcutsErrorLabel.stringValue = ""
        var updatedConfiguration = configuration
        updatedConfiguration.shortcuts.bindings[command] = shortcut
        publishConfigurationIfChanged(updatedConfiguration)
    }

    private func publishConfigurationIfChanged(_ updatedConfiguration: AppConfiguration) {
        guard updatedConfiguration != configuration else {
            apply(configuration: configuration)
            return
        }
        configuration = updatedConfiguration
        onConfigurationChanged?(updatedConfiguration)
        apply(configuration: updatedConfiguration)
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

    private func preferredContentSize(for page: SettingsPage) -> NSSize {
        switch page {
        case .general:
            return SettingsWindowMetrics.generalContentSize
        case .shortcuts:
            return SettingsWindowMetrics.shortcutsContentSize
        }
    }
}

private extension KeyboardShortcut {
    var displayString: String {
        let modifierPrefix = KeyboardShortcutModifier.allCases.compactMap { modifier -> String? in
            guard modifiers.contains(modifier) else { return nil }
            switch modifier {
            case .command:
                return "⌘"
            case .shift:
                return "⇧"
            case .option:
                return "⌥"
            case .control:
                return "⌃"
            }
        }.joined()

        let keyDisplay: String
        switch key {
        case "escape":
            keyDisplay = "Esc"
        case "space":
            keyDisplay = "Space"
        default:
            keyDisplay = key.uppercased()
        }

        return modifierPrefix + keyDisplay
    }
}
