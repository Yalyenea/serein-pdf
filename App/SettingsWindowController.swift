import AppKit

private enum SettingsWindowMetrics {
    static let contentWidth: CGFloat = 680
    static let generalContentSize = NSSize(width: contentWidth, height: 642)
    static let libraryContentSize = NSSize(width: contentWidth, height: 484)
    static let shortcutsContentSize = NSSize(width: contentWidth, height: 620)
    static let pageSegmentWidth: CGFloat = 88
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
        window.isRestorable = false
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

    func selectPage(_ page: SettingsPage) {
        settingsViewController.selectPage(page)
        applyPreferredWindowSize(settingsViewController.preferredContentSizeForCurrentPage())
    }

#if DEBUG
    func selectPageForTesting(_ index: Int) {
        settingsViewController.selectPage(SettingsPage(rawValue: index) ?? .general)
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

enum SettingsPage: Int {
    case general = 0
    case library = 1
    case shortcuts = 2
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
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
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
        case "\t":
            "tab"
        default:
            characters
        }

        guard KeyboardShortcut.isSupportedKeyToken(key) else {
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

private final class SettingsViewController: NSViewController, NSTextFieldDelegate {
    var onConfigurationChanged: ((AppConfiguration) -> Void)?
    var onPreferredContentSizeChanged: ((NSSize) -> Void)?

    private var configuration: AppConfiguration
    private var isApplyingConfiguration = false

    private let pageControl = NSSegmentedControl(labels: ["General", "Library", "Shortcuts"], trackingMode: .selectOne, target: nil, action: nil)
    private let generalContainer = NSView()
    private let libraryContainer = NSView()
    private let libraryScrollView = NSScrollView()
    private let libraryContentView = FlippedContentView()
    private let libraryFoldersStackView = NSStackView()
    private let libraryHintLabel = NSTextField(
        wrappingLabelWithString: "Library folders are scanned for PDFs when opening from the library."
    )
    private let libraryEmptyLabel = NSTextField(labelWithString: "No library folders configured.")
    private let addLibraryFolderButton = NSButton(title: "Add Folder…", target: nil, action: nil)
    private let shortcutsScrollView = NSScrollView()
    private let shortcutsContentView = FlippedContentView()
    private let shortcutsStackView = NSStackView()
    private let shortcutsHintLabel = NSTextField(
        wrappingLabelWithString: "Select a shortcut, then press its new key combination. Delete clears it; changes apply immediately."
    )
    private let shortcutsErrorLabel = NSTextField(labelWithString: "")

    private let modePopUp = NSPopUpButton()
    private let lightThemePopUp = NSPopUpButton()
    private let darkThemePopUp = NSPopUpButton()
    private let displayModePopUp = NSPopUpButton()
    private let readingFocusWidthPopUp = NSPopUpButton()
    private let readingFocusCustomWidthSlider = NSSlider(
        value: Double(ReadingFocusSettings.default.customWidthRatio),
        minValue: Double(ReadingFocusSettings.minimumCustomWidthRatio),
        maxValue: Double(ReadingFocusSettings.maximumCustomWidthRatio),
        target: nil,
        action: nil
    )
    private let readingFocusCustomWidthValueLabel = NSTextField(labelWithString: "72%")
    private let readingFocusHeightSlider = NSSlider(
        value: Double(ReadingFocusSettings.default.height),
        minValue: Double(ReadingFocusSettings.minimumHeight),
        maxValue: Double(ReadingFocusSettings.maximumHeight),
        target: nil,
        action: nil
    )
    private let readingFocusHeightValueLabel = NSTextField(labelWithString: "96 pt")
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
    private let leftSidebarWidthField = NSTextField()
    private let leftSidebarWidthStepper = NSStepper()
    private let rightSidebarWidthField = NSTextField()
    private let rightSidebarWidthStepper = NSStepper()
    private let sidebarOpacitySlider = NSSlider(
        value: Double(AppConfiguration.default.layout.sidebarOpacity),
        minValue: 0.05,
        maxValue: 0.9,
        target: nil,
        action: nil
    )
    private let sidebarOpacityValueLabel = NSTextField(labelWithString: "48%")
    private let floatingOutlineHeightSlider = NSSlider(
        value: Double(AppConfiguration.default.layout.floatingOutlineHeight),
        minValue: Double(AppConfiguration.Layout.minimumFloatingOutlineHeight),
        maxValue: Double(AppConfiguration.Layout.maximumFloatingOutlineHeight),
        target: nil,
        action: nil
    )
    private let floatingOutlineHeightValueLabel = NSTextField(labelWithString: "360 pt")
    private let showRecentInSidebarCheckbox = NSButton(
        checkboxWithTitle: "Show recent PDFs in left sidebar footer",
        target: nil,
        action: nil
    )
    private let autoCheckUpdatesCheckbox = NSButton(
        checkboxWithTitle: "Check for updates on launch (GitHub Releases)",
        target: nil,
        action: nil
    )
    private let footnoteLabel = NSTextField(
        wrappingLabelWithString: "Reading focus defaults apply immediately unless a window has a temporary ⌥F adjustment. Other reader defaults apply to newly opened PDFs. Private GitHub repos need [updates] github_token in config.toml."
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
        pageControl.identifier = NSUserInterfaceItemIdentifier("settingsPageControl")
        pageControl.selectedSegment = SettingsPage.general.rawValue
        pageControl.controlSize = .small
        pageControl.target = self
        pageControl.action = #selector(handlePageChanged(_:))
        for segment in 0..<pageControl.segmentCount {
            pageControl.setWidth(SettingsWindowMetrics.pageSegmentWidth, forSegment: segment)
        }

        buildGeneralPage()
        buildLibraryPage()
        buildShortcutsPage()

        generalContainer.translatesAutoresizingMaskIntoConstraints = false
        libraryContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutsScrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(pageControl)
        contentView.addSubview(generalContainer)
        contentView.addSubview(libraryContainer)
        contentView.addSubview(shortcutsScrollView)

        NSLayoutConstraint.activate([
            pageControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            generalContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            generalContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            generalContainer.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 14),
            generalContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            libraryContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            libraryContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            libraryContainer.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 14),
            libraryContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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

        for mode in ReadingFocusWidthMode.allCases {
            readingFocusWidthPopUp.addItem(withTitle: mode.menuTitle)
            readingFocusWidthPopUp.lastItem?.representedObject = mode.rawValue
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
        applyReadingFocusControls(configuration.reader.readingFocus)
        selectItem(in: autoSavePopUp, matching: configuration.annotations.autoSavePolicy.rawValue)
        swapSidebarsCheckbox.state = configuration.layout.sidebarsSwapped ? .on : .off
        applySidebarWidthControls(configuration.layout)
        applySidebarOpacityControls(configuration.layout)
        applyFloatingOutlineHeightControls(configuration.layout)
        showRecentInSidebarCheckbox.state = configuration.layout.showRecentFilesInSidebar ? .on : .off
        autoCheckUpdatesCheckbox.state = configuration.updates.autoCheck ? .on : .off
        shortcutsErrorLabel.stringValue = ""
        rebuildLibraryFolderRows()

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

    func selectPage(_ page: SettingsPage) {
        pageControl.selectedSegment = page.rawValue
        applySelectedPage()
    }

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
              let focusWidthRawValue = readingFocusWidthPopUp.selectedItem?.representedObject as? String,
              let focusWidthMode = ReadingFocusWidthMode(rawValue: focusWidthRawValue),
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
        updatedConfiguration.reader.readingFocus = ReadingFocusSettings(
            widthMode: focusWidthMode,
            customWidthRatio: normalizedReadingFocusCustomWidth(),
            height: normalizedReadingFocusHeight()
        )
        updatedConfiguration.annotations.autoSavePolicy = autoSavePolicy
        updatedConfiguration.layout.sidebarsSwapped = swapSidebarsCheckbox.state == .on
        updatedConfiguration.layout.leftSidebarWidth = normalizedSidebarWidth(
            from: leftSidebarWidthField,
            minWidth: updatedConfiguration.layout.leftSidebarMinWidth,
            maxWidth: updatedConfiguration.layout.leftSidebarMaxWidth
        )
        updatedConfiguration.layout.rightSidebarWidth = normalizedSidebarWidth(
            from: rightSidebarWidthField,
            minWidth: updatedConfiguration.layout.rightSidebarMinWidth,
            maxWidth: updatedConfiguration.layout.rightSidebarMaxWidth
        )
        updatedConfiguration.layout.sidebarOpacity = normalizedSidebarOpacity(from: sidebarOpacitySlider)
        updatedConfiguration.layout.floatingOutlineHeight = normalizedFloatingOutlineHeight(
            from: floatingOutlineHeightSlider
        )
        updatedConfiguration.layout.showRecentFilesInSidebar = showRecentInSidebarCheckbox.state == .on
        updatedConfiguration.updates.autoCheck = autoCheckUpdatesCheckbox.state == .on
        publishConfigurationIfChanged(updatedConfiguration)
    }

    @objc
    private func handleSidebarWidthStepperChanged(_ sender: NSStepper) {
        guard isApplyingConfiguration == false else { return }
        switch sender {
        case leftSidebarWidthStepper:
            leftSidebarWidthField.integerValue = Int(sender.doubleValue.rounded())
        case rightSidebarWidthStepper:
            rightSidebarWidthField.integerValue = Int(sender.doubleValue.rounded())
        default:
            return
        }
        handleGeneralControlChanged(sender)
    }

    @objc
    private func handleSidebarOpacitySliderChanged(_ sender: NSSlider) {
        guard isApplyingConfiguration == false else { return }
        sidebarOpacityValueLabel.stringValue = sidebarOpacityDisplayString(
            normalizedSidebarOpacity(from: sender)
        )
        handleGeneralControlChanged(sender)
    }

    @objc
    private func handleFloatingOutlineHeightSliderChanged(_ sender: NSSlider) {
        guard isApplyingConfiguration == false else { return }
        floatingOutlineHeightValueLabel.stringValue = floatingOutlineHeightDisplayString(
            normalizedFloatingOutlineHeight(from: sender)
        )
        handleGeneralControlChanged(sender)
    }

    @objc
    private func handleReadingFocusControlChanged(_ sender: Any?) {
        guard isApplyingConfiguration == false else { return }
        refreshReadingFocusLabelsAndAvailability()
        handleGeneralControlChanged(sender)
    }

    private func applySelectedPage() {
        let page = SettingsPage(rawValue: pageControl.selectedSegment) ?? .general
        generalContainer.isHidden = page != .general
        libraryContainer.isHidden = page != .library
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

        readingFocusWidthPopUp.translatesAutoresizingMaskIntoConstraints = false
        readingFocusWidthPopUp.identifier = NSUserInterfaceItemIdentifier("readingFocusWidthPopUp")
        readingFocusWidthPopUp.controlSize = .small
        readingFocusWidthPopUp.target = self
        readingFocusWidthPopUp.action = #selector(handleReadingFocusControlChanged(_:))

        configureReadingFocusSlider(
            readingFocusCustomWidthSlider,
            identifier: "readingFocusCustomWidthSlider"
        )
        configureReadingFocusSlider(
            readingFocusHeightSlider,
            identifier: "readingFocusHeightSlider"
        )
        readingFocusCustomWidthValueLabel.identifier = NSUserInterfaceItemIdentifier(
            "readingFocusCustomWidthValueLabel"
        )
        readingFocusHeightValueLabel.identifier = NSUserInterfaceItemIdentifier(
            "readingFocusHeightValueLabel"
        )
        for label in [readingFocusCustomWidthValueLabel, readingFocusHeightValueLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
        }

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

        configureSidebarWidthField(
            leftSidebarWidthField,
            identifier: "leftSidebarWidthField"
        )
        configureSidebarWidthField(
            rightSidebarWidthField,
            identifier: "rightSidebarWidthField"
        )
        configureSidebarWidthStepper(
            leftSidebarWidthStepper,
            minWidth: configuration.layout.leftSidebarMinWidth,
            maxWidth: configuration.layout.leftSidebarMaxWidth
        )
        configureSidebarWidthStepper(
            rightSidebarWidthStepper,
            minWidth: configuration.layout.rightSidebarMinWidth,
            maxWidth: configuration.layout.rightSidebarMaxWidth
        )

        sidebarOpacitySlider.translatesAutoresizingMaskIntoConstraints = false
        sidebarOpacitySlider.identifier = NSUserInterfaceItemIdentifier("sidebarOpacitySlider")
        sidebarOpacitySlider.controlSize = .small
        sidebarOpacitySlider.isContinuous = true
        sidebarOpacitySlider.target = self
        sidebarOpacitySlider.action = #selector(handleSidebarOpacitySliderChanged(_:))

        sidebarOpacityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebarOpacityValueLabel.identifier = NSUserInterfaceItemIdentifier("sidebarOpacityValueLabel")
        sidebarOpacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sidebarOpacityValueLabel.textColor = .secondaryLabelColor
        sidebarOpacityValueLabel.alignment = .right

        floatingOutlineHeightSlider.translatesAutoresizingMaskIntoConstraints = false
        floatingOutlineHeightSlider.identifier = NSUserInterfaceItemIdentifier("floatingOutlineHeightSlider")
        floatingOutlineHeightSlider.controlSize = .small
        floatingOutlineHeightSlider.isContinuous = true
        floatingOutlineHeightSlider.target = self
        floatingOutlineHeightSlider.action = #selector(handleFloatingOutlineHeightSliderChanged(_:))

        floatingOutlineHeightValueLabel.translatesAutoresizingMaskIntoConstraints = false
        floatingOutlineHeightValueLabel.identifier = NSUserInterfaceItemIdentifier(
            "floatingOutlineHeightValueLabel"
        )
        floatingOutlineHeightValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        floatingOutlineHeightValueLabel.textColor = .secondaryLabelColor
        floatingOutlineHeightValueLabel.alignment = .right

        showRecentInSidebarCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showRecentInSidebarCheckbox.controlSize = .small
        showRecentInSidebarCheckbox.target = self
        showRecentInSidebarCheckbox.action = #selector(handleGeneralControlChanged(_:))

        autoCheckUpdatesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        autoCheckUpdatesCheckbox.controlSize = .small
        autoCheckUpdatesCheckbox.target = self
        autoCheckUpdatesCheckbox.action = #selector(handleGeneralControlChanged(_:))

        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.font = .systemFont(ofSize: 11)
        footnoteLabel.textColor = .secondaryLabelColor
        footnoteLabel.maximumNumberOfLines = 0

        let layoutOptionsStack = NSStackView(views: [
            swapSidebarsCheckbox,
            showRecentInSidebarCheckbox,
            autoCheckUpdatesCheckbox,
        ])
        layoutOptionsStack.orientation = .vertical
        layoutOptionsStack.alignment = .leading
        layoutOptionsStack.spacing = 6
        layoutOptionsStack.translatesAutoresizingMaskIntoConstraints = false

        let sidebarDefaultsStack = makeSidebarDefaultsStack()
        let sidebarOpacityStack = makeSidebarOpacityStack()
        let floatingOutlineHeightStack = makeFloatingOutlineHeightStack()
        let readingFocusWidthStack = makeReadingFocusSliderStack(
            leadingControl: readingFocusWidthPopUp,
            slider: readingFocusCustomWidthSlider,
            valueLabel: readingFocusCustomWidthValueLabel
        )
        let readingFocusHeightStack = makeReadingFocusSliderStack(
            leadingControl: nil,
            slider: readingFocusHeightSlider,
            valueLabel: readingFocusHeightValueLabel
        )

        let appearanceGrid = makeSettingsGrid([
            [makeRowLabel("Mode"), modePopUp],
            [makeRowLabel("Light Theme"), lightThemePopUp],
            [makeRowLabel("Dark Theme"), darkThemePopUp],
        ])
        let readingGrid = makeSettingsGrid([
            [makeRowLabel("Default Display"), displayModePopUp],
            [makeRowLabel("Open Behavior"), fitWidthCheckbox],
            [makeRowLabel("Focus Width"), readingFocusWidthStack],
            [makeRowLabel("Focus Height"), readingFocusHeightStack],
            [makeRowLabel("Annotation Auto-Save"), autoSavePopUp],
        ])
        let layoutGrid = makeSettingsGrid([
            [makeRowLabel("Sidebar Widths"), sidebarDefaultsStack],
            [makeRowLabel("Sidebar Opacity"), sidebarOpacityStack],
            [makeRowLabel("Floating Outline Height"), floatingOutlineHeightStack],
            [makeRowLabel("Layout"), layoutOptionsStack],
        ])
        let sectionsStack = NSStackView(views: [
            makeSettingsSection(title: "Appearance", content: appearanceGrid),
            makeSettingsSection(title: "Reading", content: readingGrid),
            makeSettingsSection(title: "Layout", content: layoutGrid),
        ])
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .leading
        sectionsStack.spacing = 18
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false

        generalContainer.addSubview(sectionsStack)
        generalContainer.addSubview(footnoteLabel)

        let footnoteBottomConstraint = footnoteLabel.bottomAnchor.constraint(
            lessThanOrEqualTo: generalContainer.bottomAnchor,
            constant: -20
        )
        footnoteBottomConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            sectionsStack.leadingAnchor.constraint(equalTo: generalContainer.leadingAnchor, constant: 32),
            sectionsStack.trailingAnchor.constraint(lessThanOrEqualTo: generalContainer.trailingAnchor, constant: -32),
            sectionsStack.topAnchor.constraint(equalTo: generalContainer.topAnchor, constant: 16),
            modePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            lightThemePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            darkThemePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            displayModePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            readingFocusWidthPopUp.widthAnchor.constraint(equalToConstant: 138),
            autoSavePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            footnoteLabel.leadingAnchor.constraint(equalTo: sectionsStack.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: generalContainer.trailingAnchor, constant: -32),
            footnoteLabel.topAnchor.constraint(equalTo: sectionsStack.bottomAnchor, constant: 14),
            footnoteBottomConstraint,
        ])
    }

    private func makeSettingsGrid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 18
        grid.column(at: 0).width = 154
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func makeSettingsSection(title: String, content: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func configureSidebarWidthField(_ field: NSTextField, identifier: String) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.controlSize = .small
        field.alignment = .right
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.target = self
        field.action = #selector(handleGeneralControlChanged(_:))
        field.delegate = self
    }

    private func configureSidebarWidthStepper(_ stepper: NSStepper, minWidth: CGFloat, maxWidth: CGFloat) {
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.minValue = Double(minWidth)
        stepper.maxValue = Double(maxWidth)
        stepper.increment = 10
        stepper.target = self
        stepper.action = #selector(handleSidebarWidthStepperChanged(_:))
    }

    private func makeSidebarDefaultsStack() -> NSStackView {
        let stack = NSStackView(views: [
            makeSidebarWidthRow(title: "Left", field: leftSidebarWidthField, stepper: leftSidebarWidthStepper),
            makeSidebarWidthRow(title: "Right", field: rightSidebarWidthField, stepper: rightSidebarWidthStepper),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSidebarWidthRow(title: String, field: NSTextField, stepper: NSStepper) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let suffix = NSTextField(labelWithString: "pt")
        suffix.font = .systemFont(ofSize: 12)
        suffix.textColor = .secondaryLabelColor
        suffix.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, field, stepper, suffix])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 36),
            field.widthAnchor.constraint(equalToConstant: 64),
        ])

        return row
    }

    private func makeSidebarOpacityStack() -> NSStackView {
        let stack = NSStackView(views: [sidebarOpacitySlider, sidebarOpacityValueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            sidebarOpacitySlider.widthAnchor.constraint(equalToConstant: 180),
            sidebarOpacityValueLabel.widthAnchor.constraint(equalToConstant: 44),
        ])

        return stack
    }

    private func makeFloatingOutlineHeightStack() -> NSStackView {
        let stack = NSStackView(views: [floatingOutlineHeightSlider, floatingOutlineHeightValueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            floatingOutlineHeightSlider.widthAnchor.constraint(equalToConstant: 180),
            floatingOutlineHeightValueLabel.widthAnchor.constraint(equalToConstant: 48),
        ])

        return stack
    }

    private func configureReadingFocusSlider(_ slider: NSSlider, identifier: String) {
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.identifier = NSUserInterfaceItemIdentifier(identifier)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(handleReadingFocusControlChanged(_:))
    }

    private func makeReadingFocusSliderStack(
        leadingControl: NSView?,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSStackView {
        let views = [leadingControl, slider, valueLabel].compactMap { $0 }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(equalToConstant: leadingControl == nil ? 190 : 120),
            valueLabel.widthAnchor.constraint(equalToConstant: 48),
        ])
        return stack
    }

    private func applySidebarWidthControls(_ layout: AppConfiguration.Layout) {
        leftSidebarWidthField.integerValue = Int(layout.leftSidebarWidth.rounded())
        leftSidebarWidthStepper.minValue = Double(layout.leftSidebarMinWidth)
        leftSidebarWidthStepper.maxValue = Double(layout.leftSidebarMaxWidth)
        leftSidebarWidthStepper.doubleValue = Double(layout.leftSidebarWidth)

        rightSidebarWidthField.integerValue = Int(layout.rightSidebarWidth.rounded())
        rightSidebarWidthStepper.minValue = Double(layout.rightSidebarMinWidth)
        rightSidebarWidthStepper.maxValue = Double(layout.rightSidebarMaxWidth)
        rightSidebarWidthStepper.doubleValue = Double(layout.rightSidebarWidth)
    }

    private func applySidebarOpacityControls(_ layout: AppConfiguration.Layout) {
        sidebarOpacitySlider.doubleValue = Double(layout.sidebarOpacity)
        sidebarOpacityValueLabel.stringValue = sidebarOpacityDisplayString(layout.sidebarOpacity)
    }

    private func applyFloatingOutlineHeightControls(_ layout: AppConfiguration.Layout) {
        floatingOutlineHeightSlider.doubleValue = Double(layout.floatingOutlineHeight)
        floatingOutlineHeightValueLabel.stringValue = floatingOutlineHeightDisplayString(
            layout.floatingOutlineHeight
        )
    }

    private func applyReadingFocusControls(_ settings: ReadingFocusSettings) {
        selectItem(in: readingFocusWidthPopUp, matching: settings.widthMode.rawValue)
        readingFocusCustomWidthSlider.doubleValue = Double(settings.customWidthRatio)
        readingFocusHeightSlider.doubleValue = Double(settings.height)
        refreshReadingFocusLabelsAndAvailability()
    }

    private func normalizedSidebarWidth(from field: NSTextField, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(max(CGFloat(field.doubleValue.rounded()), minWidth), maxWidth)
    }

    private func normalizedSidebarOpacity(from slider: NSSlider) -> CGFloat {
        min(max(CGFloat(slider.doubleValue), CGFloat(slider.minValue)), CGFloat(slider.maxValue))
    }

    private func sidebarOpacityDisplayString(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func normalizedFloatingOutlineHeight(from slider: NSSlider) -> CGFloat {
        min(
            max(
                CGFloat(slider.doubleValue.rounded()),
                AppConfiguration.Layout.minimumFloatingOutlineHeight
            ),
            AppConfiguration.Layout.maximumFloatingOutlineHeight
        )
    }

    private func floatingOutlineHeightDisplayString(_ value: CGFloat) -> String {
        "\(Int(value.rounded())) pt"
    }

    private func normalizedReadingFocusCustomWidth() -> CGFloat {
        min(
            max(
                CGFloat(readingFocusCustomWidthSlider.doubleValue),
                ReadingFocusSettings.minimumCustomWidthRatio
            ),
            ReadingFocusSettings.maximumCustomWidthRatio
        )
    }

    private func normalizedReadingFocusHeight() -> CGFloat {
        min(
            max(
                CGFloat(readingFocusHeightSlider.doubleValue.rounded()),
                ReadingFocusSettings.minimumHeight
            ),
            ReadingFocusSettings.maximumHeight
        )
    }

    private func refreshReadingFocusLabelsAndAvailability() {
        let widthMode = (readingFocusWidthPopUp.selectedItem?.representedObject as? String)
            .flatMap(ReadingFocusWidthMode.init(rawValue:))
            ?? .page
        let usesCustomWidth = widthMode == .custom
        readingFocusCustomWidthSlider.isEnabled = usesCustomWidth
        readingFocusCustomWidthValueLabel.textColor = usesCustomWidth
            ? .secondaryLabelColor
            : .tertiaryLabelColor
        readingFocusCustomWidthValueLabel.stringValue =
            "\(Int((normalizedReadingFocusCustomWidth() * 100).rounded()))%"
        readingFocusHeightValueLabel.stringValue =
            "\(Int(normalizedReadingFocusHeight().rounded())) pt"
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isApplyingConfiguration == false,
              let field = obj.object as? NSTextField,
              field === leftSidebarWidthField || field === rightSidebarWidthField else { return }
        handleGeneralControlChanged(field)
    }

    private func buildLibraryPage() {
        libraryHintLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryHintLabel.font = .systemFont(ofSize: 11)
        libraryHintLabel.textColor = .secondaryLabelColor
        libraryHintLabel.maximumNumberOfLines = 0

        addLibraryFolderButton.translatesAutoresizingMaskIntoConstraints = false
        addLibraryFolderButton.controlSize = .small
        addLibraryFolderButton.bezelStyle = .rounded
        addLibraryFolderButton.target = self
        addLibraryFolderButton.action = #selector(addLibraryFolder(_:))

        libraryEmptyLabel.font = .systemFont(ofSize: 12)
        libraryEmptyLabel.textColor = .secondaryLabelColor

        libraryFoldersStackView.orientation = .vertical
        libraryFoldersStackView.alignment = .leading
        libraryFoldersStackView.spacing = 8
        libraryFoldersStackView.translatesAutoresizingMaskIntoConstraints = false

        libraryContentView.translatesAutoresizingMaskIntoConstraints = false
        libraryContentView.addSubview(libraryFoldersStackView)

        libraryScrollView.translatesAutoresizingMaskIntoConstraints = false
        libraryScrollView.drawsBackground = false
        libraryScrollView.borderType = .noBorder
        libraryScrollView.hasHorizontalScroller = false
        libraryScrollView.hasVerticalScroller = true
        libraryScrollView.autohidesScrollers = true
        libraryScrollView.documentView = libraryContentView

        libraryContainer.addSubview(libraryHintLabel)
        libraryContainer.addSubview(addLibraryFolderButton)
        libraryContainer.addSubview(libraryScrollView)

        NSLayoutConstraint.activate([
            libraryHintLabel.leadingAnchor.constraint(equalTo: libraryContainer.leadingAnchor, constant: 32),
            libraryHintLabel.trailingAnchor.constraint(equalTo: addLibraryFolderButton.leadingAnchor, constant: -16),
            libraryHintLabel.topAnchor.constraint(equalTo: libraryContainer.topAnchor, constant: 16),

            addLibraryFolderButton.trailingAnchor.constraint(equalTo: libraryContainer.trailingAnchor, constant: -32),
            addLibraryFolderButton.centerYAnchor.constraint(equalTo: libraryHintLabel.centerYAnchor),

            libraryScrollView.leadingAnchor.constraint(equalTo: libraryHintLabel.leadingAnchor),
            libraryScrollView.trailingAnchor.constraint(equalTo: libraryContainer.trailingAnchor, constant: -32),
            libraryScrollView.topAnchor.constraint(equalTo: libraryHintLabel.bottomAnchor, constant: 16),
            libraryScrollView.bottomAnchor.constraint(equalTo: libraryContainer.bottomAnchor, constant: -20),

            libraryContentView.leadingAnchor.constraint(equalTo: libraryScrollView.contentView.leadingAnchor),
            libraryContentView.trailingAnchor.constraint(equalTo: libraryScrollView.contentView.trailingAnchor),
            libraryContentView.topAnchor.constraint(equalTo: libraryScrollView.contentView.topAnchor),
            libraryContentView.bottomAnchor.constraint(greaterThanOrEqualTo: libraryScrollView.contentView.bottomAnchor),
            libraryContentView.widthAnchor.constraint(equalTo: libraryScrollView.contentView.widthAnchor),

            libraryFoldersStackView.leadingAnchor.constraint(equalTo: libraryContentView.leadingAnchor),
            libraryFoldersStackView.trailingAnchor.constraint(equalTo: libraryContentView.trailingAnchor),
            libraryFoldersStackView.topAnchor.constraint(equalTo: libraryContentView.topAnchor),
            libraryFoldersStackView.bottomAnchor.constraint(equalTo: libraryContentView.bottomAnchor),
            libraryFoldersStackView.widthAnchor.constraint(equalTo: libraryContentView.widthAnchor),
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
        shortcutsStackView.spacing = 0
        shortcutsStackView.translatesAutoresizingMaskIntoConstraints = false

        shortcutsContentView.translatesAutoresizingMaskIntoConstraints = false
        shortcutsContentView.addSubview(shortcutsHintLabel)
        shortcutsContentView.addSubview(shortcutsErrorLabel)
        shortcutsContentView.addSubview(shortcutsStackView)

        NSLayoutConstraint.activate([
            shortcutsHintLabel.leadingAnchor.constraint(equalTo: shortcutsContentView.leadingAnchor, constant: 32),
            shortcutsHintLabel.trailingAnchor.constraint(equalTo: shortcutsContentView.trailingAnchor, constant: -32),
            shortcutsHintLabel.topAnchor.constraint(equalTo: shortcutsContentView.topAnchor, constant: 16),

            shortcutsErrorLabel.leadingAnchor.constraint(equalTo: shortcutsHintLabel.leadingAnchor),
            shortcutsErrorLabel.trailingAnchor.constraint(equalTo: shortcutsHintLabel.trailingAnchor),
            shortcutsErrorLabel.topAnchor.constraint(equalTo: shortcutsHintLabel.bottomAnchor, constant: 8),

            shortcutsStackView.leadingAnchor.constraint(equalTo: shortcutsContentView.leadingAnchor, constant: 32),
            shortcutsStackView.trailingAnchor.constraint(equalTo: shortcutsContentView.trailingAnchor, constant: -32),
            shortcutsStackView.topAnchor.constraint(equalTo: shortcutsErrorLabel.bottomAnchor, constant: 12),
            shortcutsStackView.bottomAnchor.constraint(equalTo: shortcutsContentView.bottomAnchor, constant: -20),
            shortcutsStackView.widthAnchor.constraint(equalTo: shortcutsContentView.widthAnchor, constant: -64),
        ])

        shortcutsScrollView.identifier = NSUserInterfaceItemIdentifier("shortcutsScrollView")
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

    private func rebuildLibraryFolderRows() {
        libraryFoldersStackView.arrangedSubviews.forEach { view in
            libraryFoldersStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard configuration.library.folderURLs.isEmpty == false else {
            libraryFoldersStackView.addArrangedSubview(libraryEmptyLabel)
            return
        }

        for folderURL in configuration.library.folderURLs {
            let row = makeLibraryFolderRow(for: folderURL)
            libraryFoldersStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: libraryFoldersStackView.widthAnchor).isActive = true
        }
    }

    private func makeLibraryFolderRow(for folderURL: URL) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: folderURL.path)
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeLibraryFolder(_:)))
        removeButton.controlSize = .small
        removeButton.bezelStyle = .rounded
        removeButton.identifier = NSUserInterfaceItemIdentifier(folderURL.path)
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(pathLabel)
        row.addSubview(removeButton)

        NSLayoutConstraint.activate([
            pathLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            pathLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -12),

            removeButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(equalToConstant: 28),
        ])

        return row
    }

    @objc
    private func addLibraryFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Choose folders whose PDFs should appear in the library."

        guard panel.runModal() == .OK else { return }

        var folderURLs = configuration.library.folderURLs
        var seenPaths = Set(folderURLs.map { $0.standardizedFileURL.path })
        for url in panel.urls.map(\.standardizedFileURL) {
            guard seenPaths.insert(url.path).inserted else { continue }
            folderURLs.append(url)
        }
        updateLibraryFolderURLs(folderURLs)
    }

    @objc
    private func removeLibraryFolder(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        updateLibraryFolderURLs(
            configuration.library.folderURLs.filter { $0.standardizedFileURL.path != path }
        )
    }

    private func updateLibraryFolderURLs(_ folderURLs: [URL]) {
        var updatedConfiguration = configuration
        updatedConfiguration.library.folderURLs = folderURLs
        publishConfigurationIfChanged(updatedConfiguration)
    }

    private func makeShortcutRow(for command: ShortcutCommand) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.identifier = NSUserInterfaceItemIdentifier("shortcutRow.\(command.rawValue)")

        let titleLabel = NSTextField(labelWithString: command.menuTitle)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let captureButton = ShortcutCaptureButton(frame: .zero)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.identifier = NSUserInterfaceItemIdentifier("shortcutCapture.\(command.rawValue)")
        captureButton.onShortcutCaptured = { [weak self] shortcut in
            self?.updateShortcut(shortcut, for: command)
        }

        let defaultLabel = NSTextField(labelWithString: "")
        defaultLabel.font = .systemFont(ofSize: 10.5)
        defaultLabel.textColor = .secondaryLabelColor
        defaultLabel.lineBreakMode = .byTruncatingTail
        defaultLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        defaultLabel.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
        clearButton.controlSize = .small
        clearButton.bezelStyle = .inline
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        let restoreButton = NSButton(title: "Reset", target: self, action: #selector(restoreShortcutDefault(_:)))
        restoreButton.controlSize = .small
        restoreButton.bezelStyle = .inline
        restoreButton.toolTip = "Restore Default"
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(captureButton)
        row.addSubview(defaultLabel)
        row.addSubview(clearButton)
        row.addSubview(restoreButton)
        row.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: captureButton.leadingAnchor, constant: -16),

            defaultLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            defaultLabel.trailingAnchor.constraint(lessThanOrEqualTo: captureButton.leadingAnchor, constant: -16),
            defaultLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            captureButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            captureButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 116),

            restoreButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            restoreButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            restoreButton.widthAnchor.constraint(equalToConstant: 52),

            clearButton.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 44),

            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            row.heightAnchor.constraint(equalToConstant: 44),
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
        case .library:
            return SettingsWindowMetrics.libraryContentSize
        case .shortcuts:
            return SettingsWindowMetrics.shortcutsContentSize
        }
    }
}
