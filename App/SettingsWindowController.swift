import AppKit

private enum SettingsWindowMetrics {
    static let contentWidth: CGFloat = 680
    static let generalContentSize = NSSize(width: contentWidth, height: 766)
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
        window.title = L10n.text("Settings", "设置")
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

    func refreshChromeColors() {
        var pending = settingsViewController.view.subviews
        while let view = pending.popLast() {
            if let shortcuts = view as? ShortcutSequenceView {
                shortcuts.refreshChromeColors()
            } else {
                pending.append(contentsOf: view.subviews)
            }
        }
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

    func setShortcutSearchForTesting(_ query: String) {
        settingsViewController.setShortcutSearchForTesting(query)
    }
#endif

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshChromeColors()
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
    private let shortcutView = ShortcutSequenceView()
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
        font = .systemFont(ofSize: 12, weight: .medium)
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginCapture(_:))
        addSubview(shortcutView)
        NSLayoutConstraint.activate([
            shortcutView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            shortcutView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

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

        guard let key = KeyboardShortcut.keyToken(for: event),
              KeyboardShortcut.isSupportedKeyToken(key) else {
            NSSound.beep()
            return
        }

        isCapturing = false
        onShortcutCaptured?(KeyboardShortcut(key: key, modifiers: modifiers))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func updateTitle() {
        shortcutView.configure(sequences: shortcut.map { [KeyboardShortcutSequence([$0])] } ?? [])
        shortcutView.isHidden = isCapturing || shortcut == nil
        if isCapturing {
            title = L10n.text("Type Shortcut", "输入快捷键")
            setAccessibilityLabel(title)
            return
        }
        title = shortcut == nil ? L10n.text("None", "无") : ""
        setAccessibilityLabel(shortcut?.displayString ?? L10n.text("None", "无"))
        toolTip = L10n.text("Click to change shortcut", "点击修改快捷键")
    }
}

private final class SettingsViewController: NSViewController, NSSearchFieldDelegate {
    var onConfigurationChanged: ((AppConfiguration) -> Void)?
    var onPreferredContentSizeChanged: ((NSSize) -> Void)?

    private var configuration: AppConfiguration
    private var isApplyingConfiguration = false

    private let pageControl = NSSegmentedControl(labels: [L10n.text("General", "通用"), L10n.text("Library", "资料库"), L10n.text("Shortcuts", "快捷键")], trackingMode: .selectOne, target: nil, action: nil)
    private let generalContainer = NSView()
    private let libraryContainer = NSView()
    private let libraryScrollView = NSScrollView()
    private let libraryContentView = FlippedContentView()
    private let libraryFoldersStackView = NSStackView()
    private let libraryHintLabel = NSTextField(
        wrappingLabelWithString: L10n.text("Library folders are scanned for PDFs when opening from the library.", "打开资料库时会扫描这些文件夹中的 PDF。")
    )
    private let libraryEmptyLabel = NSTextField(labelWithString: L10n.text("No library folders configured.", "尚未添加资料库文件夹。"))
    private let addLibraryFolderButton = NSButton(title: L10n.text("Add Folder…", "添加文件夹…"), target: nil, action: nil)
    private let shortcutsScrollView = NSScrollView()
    private let shortcutsContentView = FlippedContentView()
    private let shortcutsStackView = NSStackView()
    private let shortcutsHintLabel = NSTextField(
        wrappingLabelWithString: L10n.text("Select a shortcut and type a new combination. Built-in ⌘K sequences remain available and changes apply immediately.", "点击快捷键后输入新组合，修改立即生效。内置 ⌘K 连续快捷键仍然可用。")
    )
    private let shortcutSearchField = NSSearchField(frame: .zero)
    private let resetAllShortcutsButton = NSButton(title: L10n.text("Reset All", "全部重置"), target: nil, action: nil)
    private let shortcutsErrorLabel = NSTextField(labelWithString: "")

    private let languagePopUp = NSPopUpButton()
    private let modePopUp = NSPopUpButton()
    private let lightThemePopUp = NSPopUpButton()
    private let darkThemePopUp = NSPopUpButton()
    private let lightPageBackground = NSColorWell()
    private let lightWindowBackground = NSColorWell()
    private let darkPageBackground = NSColorWell()
    private let darkWindowBackground = NSColorWell()
    private let resetLightBackground = NSButton()
    private let resetDarkBackground = NSButton()
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
        checkboxWithTitle: L10n.text("Fit width when opening a document", "打开文档时适应宽度"),
        target: nil,
        action: nil
    )
    private let showPageCounterCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Show at bottom right", "在右下角显示"),
        target: nil,
        action: nil
    )
    private let autoSavePopUp = NSPopUpButton()
    private let scrollSpeedSlider = NSSlider(value: 1, minValue: 0.5, maxValue: 3, target: nil, action: nil)
    private let scrollSpeedValueLabel = NSTextField(labelWithString: "1.0×")
    private let seamlessPagesCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Remove gaps between pages", "移除页面间距"), target: nil, action: nil
    )
    private let swapSidebarsCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Swap left and right sidebars", "交换左右侧栏"),
        target: nil,
        action: nil
    )
    private let leftSidebarWidthField = NSTextField()
    private let leftSidebarWidthStepper = NSStepper()
    private let rightSidebarWidthField = NSTextField()
    private let rightSidebarWidthStepper = NSStepper()
    private let floatingOutlineHeightSlider = NSSlider(
        value: Double(AppConfiguration.default.layout.floatingOutlineHeight),
        minValue: Double(AppConfiguration.Layout.minimumFloatingOutlineHeight),
        maxValue: Double(AppConfiguration.Layout.maximumFloatingOutlineHeight),
        target: nil,
        action: nil
    )
    private let floatingOutlineHeightValueLabel = NSTextField(labelWithString: "360 pt")
    private let showRecentInSidebarCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Show recent PDFs in left sidebar footer", "在左侧栏底部显示最近的 PDF"),
        target: nil,
        action: nil
    )
    private let autoCheckUpdatesCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Check for updates on launch (GitHub Releases)", "启动时检查更新（GitHub Releases）"),
        target: nil,
        action: nil
    )
    private let codexIntegrationCheckbox = NSButton(
        checkboxWithTitle: L10n.text("Enable Codex integration", "启用 Codex 集成"),
        target: nil,
        action: nil
    )
    private let footnoteLabel = NSTextField(
        wrappingLabelWithString: L10n.text("Reading focus defaults apply immediately unless a window has a temporary ⌥F adjustment. Other reader defaults apply to newly opened PDFs. Private GitHub repos need [updates] github_token in config.toml.", "阅读聚焦设置立即生效，使用 ⌥F 临时调整的窗口除外。其他阅读默认设置应用于新打开的 PDF。私有 GitHub 仓库需在 config.toml 的 [updates] 中配置 github_token。")
    )

    private var shortcutButtons: [ShortcutCommand: ShortcutCaptureButton] = [:]
    private var shortcutDefaultLabels: [ShortcutCommand: NSTextField] = [:]
    private var shortcutDefaultViews: [ShortcutCommand: ShortcutSequenceView] = [:]
    private var shortcutClearButtons: [ShortcutCommand: NSButton] = [:]
    private var shortcutRestoreButtons: [ShortcutCommand: NSButton] = [:]

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        title = L10n.text("Settings", "设置")
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

        for language in AppLanguage.allCases {
            let title: String
            switch language {
            case .automatic: title = L10n.text("Automatic", "自动")
            case .english: title = "English"
            case .chinese: title = "中文"
            }
            languagePopUp.addItem(withTitle: title)
            languagePopUp.lastItem?.representedObject = language.rawValue
        }

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
        let shouldRebuildShortcutRows = isViewLoaded
            && self.configuration.shortcuts != configuration.shortcuts
            && shortcutSearchField.stringValue.isEmpty == false
        self.configuration = configuration
        guard isViewLoaded else { return }

        isApplyingConfiguration = true
        defer { isApplyingConfiguration = false }

        selectItem(in: languagePopUp, matching: configuration.language.rawValue)
        selectItem(in: modePopUp, matching: configuration.appearance.mode.rawValue)
        selectItem(in: lightThemePopUp, matching: configuration.appearance.lightTheme.rawValue)
        selectItem(in: darkThemePopUp, matching: configuration.appearance.darkTheme.rawValue)
        applyBackgroundControls()
        selectItem(in: displayModePopUp, matching: configuration.reader.defaultDisplayMode.rawValue)
        fitWidthCheckbox.state = configuration.reader.fitWidthOnOpen ? .on : .off
        showPageCounterCheckbox.state = configuration.reader.showPageCounter ? .on : .off
        seamlessPagesCheckbox.state = configuration.reader.seamlessPages ? .on : .off
        scrollSpeedSlider.doubleValue = Double(configuration.reader.scrollSpeed)
        scrollSpeedValueLabel.stringValue = String(format: "%.1f×", scrollSpeedSlider.doubleValue)
        applyReadingFocusControls(configuration.reader.readingFocus)
        selectItem(in: autoSavePopUp, matching: configuration.annotations.autoSavePolicy.rawValue)
        swapSidebarsCheckbox.state = configuration.layout.sidebarsSwapped ? .on : .off
        applySidebarWidthControls(configuration.layout)
        applyFloatingOutlineHeightControls(configuration.layout)
        showRecentInSidebarCheckbox.state = configuration.layout.showRecentFilesInSidebar ? .on : .off
        autoCheckUpdatesCheckbox.state = configuration.updates.autoCheck ? .on : .off
        codexIntegrationCheckbox.state = configuration.integrations.codexEnabled ? .on : .off
        shortcutsErrorLabel.stringValue = ""
        resetAllShortcutsButton.isEnabled = configuration.shortcuts != .default
        rebuildLibraryFolderRows()

        if shouldRebuildShortcutRows {
            rebuildShortcutRows()
        }
        applyShortcutRows(configuration)
    }

    private func applyShortcutRows(_ configuration: AppConfiguration) {
        for command in ShortcutCommand.allCases {
            shortcutButtons[command]?.shortcut = configuration.shortcuts.bindings[command]
            if let defaultShortcut = AppConfiguration.default.shortcuts.bindings[command] {
                shortcutDefaultLabels[command]?.stringValue = L10n.text("Default", "默认")
                shortcutDefaultViews[command]?.configure(sequences: [KeyboardShortcutSequence([defaultShortcut])])
            } else if command.builtInShortcutSequence != nil {
                shortcutDefaultLabels[command]?.stringValue = L10n.text("Direct shortcut optional", "可选直接快捷键")
            } else {
                shortcutDefaultLabels[command]?.stringValue = L10n.text("No default shortcut", "无默认快捷键")
            }
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
        guard let languageRawValue = languagePopUp.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: languageRawValue),
              let modeRawValue = modePopUp.selectedItem?.representedObject as? String,
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
        updatedConfiguration.language = language
        updatedConfiguration.appearance.mode = mode
        updatedConfiguration.appearance.lightTheme = lightTheme
        updatedConfiguration.appearance.darkTheme = darkTheme
        updatedConfiguration.reader.defaultDisplayMode = displayMode
        updatedConfiguration.reader.fitWidthOnOpen = fitWidthCheckbox.state == .on
        updatedConfiguration.reader.showPageCounter = showPageCounterCheckbox.state == .on
        updatedConfiguration.reader.seamlessPages = seamlessPagesCheckbox.state == .on
        updatedConfiguration.reader.scrollSpeed = CGFloat((scrollSpeedSlider.doubleValue * 10).rounded() / 10)
        scrollSpeedValueLabel.stringValue = String(format: "%.1f×", Double(updatedConfiguration.reader.scrollSpeed))
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
        updatedConfiguration.layout.floatingOutlineHeight = normalizedFloatingOutlineHeight(
            from: floatingOutlineHeightSlider
        )
        updatedConfiguration.layout.showRecentFilesInSidebar = showRecentInSidebarCheckbox.state == .on
        updatedConfiguration.updates.autoCheck = autoCheckUpdatesCheckbox.state == .on
        updatedConfiguration.integrations.codexEnabled = codexIntegrationCheckbox.state == .on
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
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        languagePopUp.identifier = NSUserInterfaceItemIdentifier("languagePopUp")
        languagePopUp.controlSize = .small
        languagePopUp.target = self
        languagePopUp.action = #selector(handleGeneralControlChanged(_:))
        let languageHint = NSTextField(labelWithString: L10n.text(
            "Restart Serein to apply", "重新打开 Serein 后生效"
        ))
        languageHint.font = .systemFont(ofSize: 11)
        languageHint.textColor = .secondaryLabelColor
        let languageControls = NSStackView(views: [languagePopUp, languageHint])
        languageControls.spacing = 8
        languageControls.alignment = .centerY

        modePopUp.translatesAutoresizingMaskIntoConstraints = false
        modePopUp.controlSize = .small
        modePopUp.target = self
        modePopUp.action = #selector(handleGeneralControlChanged(_:))

        lightThemePopUp.translatesAutoresizingMaskIntoConstraints = false
        lightThemePopUp.identifier = NSUserInterfaceItemIdentifier("lightThemePopUp")
        lightThemePopUp.controlSize = .small
        lightThemePopUp.target = self
        lightThemePopUp.action = #selector(handleGeneralControlChanged(_:))

        darkThemePopUp.translatesAutoresizingMaskIntoConstraints = false
        darkThemePopUp.identifier = NSUserInterfaceItemIdentifier("darkThemePopUp")
        darkThemePopUp.controlSize = .small
        darkThemePopUp.target = self
        darkThemePopUp.action = #selector(handleGeneralControlChanged(_:))

        displayModePopUp.translatesAutoresizingMaskIntoConstraints = false
        displayModePopUp.identifier = NSUserInterfaceItemIdentifier("defaultDisplayModePopUp")
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

        showPageCounterCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showPageCounterCheckbox.identifier = NSUserInterfaceItemIdentifier("showPageCounterCheckbox")
        showPageCounterCheckbox.controlSize = .small
        showPageCounterCheckbox.target = self
        showPageCounterCheckbox.action = #selector(handleGeneralControlChanged(_:))
        seamlessPagesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        seamlessPagesCheckbox.identifier = NSUserInterfaceItemIdentifier("seamlessPagesCheckbox")
        seamlessPagesCheckbox.controlSize = .small
        seamlessPagesCheckbox.target = self
        seamlessPagesCheckbox.action = #selector(handleGeneralControlChanged(_:))
        scrollSpeedSlider.translatesAutoresizingMaskIntoConstraints = false
        scrollSpeedSlider.identifier = NSUserInterfaceItemIdentifier("scrollSpeedSlider")
        scrollSpeedSlider.controlSize = .small
        scrollSpeedSlider.isContinuous = true
        scrollSpeedSlider.target = self
        scrollSpeedSlider.action = #selector(handleGeneralControlChanged(_:))
        scrollSpeedSlider.toolTip = L10n.text("Base scrolling speed in continuous page layouts. Default: 1.0×.", "连续页面布局中的滚动速度，默认为 1.0×。")
        scrollSpeedValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        scrollSpeedValueLabel.textColor = .secondaryLabelColor
        scrollSpeedValueLabel.identifier = NSUserInterfaceItemIdentifier("scrollSpeedValueLabel")

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

        codexIntegrationCheckbox.translatesAutoresizingMaskIntoConstraints = false
        codexIntegrationCheckbox.identifier = NSUserInterfaceItemIdentifier("codexIntegrationCheckbox")
        codexIntegrationCheckbox.controlSize = .small
        codexIntegrationCheckbox.target = self
        codexIntegrationCheckbox.action = #selector(handleGeneralControlChanged(_:))

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
            [makeRowLabel(L10n.text("Language", "语言")), languageControls],
            [makeRowLabel(L10n.text("Mode", "模式")), modePopUp],
            [makeRowLabel(L10n.text("Light Theme", "浅色主题")), makeThemeControls(isDark: false)],
            [makeRowLabel(L10n.text("Dark Theme", "深色主题")), makeThemeControls(isDark: true)],
        ])
        let readingGrid = makeSettingsGrid([
            [makeRowLabel(L10n.text("Default Display", "默认显示")), displayModePopUp],
            [makeRowLabel(L10n.text("Open Behavior", "打开文档")), fitWidthCheckbox],
            [makeRowLabel(L10n.text("Page Counter", "页码")), showPageCounterCheckbox],
            [makeRowLabel(L10n.text("Seamless Pages", "无缝页面")), seamlessPagesCheckbox],
            [makeRowLabel(L10n.text("Scroll Speed", "滚动速度")), makeReadingFocusSliderStack(
                leadingControl: nil, slider: scrollSpeedSlider, valueLabel: scrollSpeedValueLabel
            )],
            [makeRowLabel(L10n.text("Focus Width", "聚焦宽度")), readingFocusWidthStack],
            [makeRowLabel(L10n.text("Focus Height", "聚焦高度")), readingFocusHeightStack],
            [makeRowLabel(L10n.text("Annotation Auto-Save", "自动保存批注")), autoSavePopUp],
        ])
        let layoutGrid = makeSettingsGrid([
            [makeRowLabel(L10n.text("Sidebar Widths", "侧栏宽度")), sidebarDefaultsStack],
            [makeRowLabel(L10n.text("Floating Outline Height", "浮动目录最大高度")), floatingOutlineHeightStack],
            [makeRowLabel(L10n.text("Layout", "布局")), layoutOptionsStack],
        ])
        let integrationsGrid = makeSettingsGrid([
            [makeRowLabel("Codex"), codexIntegrationCheckbox],
        ])
        let sectionsStack = NSStackView(views: [
            makeSettingsSection(title: L10n.text("Appearance", "外观"), content: appearanceGrid),
            makeSettingsSection(title: L10n.text("Reading", "阅读"), content: readingGrid),
            makeSettingsSection(title: L10n.text("Layout", "布局"), content: layoutGrid),
            makeSettingsSection(title: L10n.text("Integrations", "集成"), content: integrationsGrid),
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
            languagePopUp.widthAnchor.constraint(equalToConstant: 140),
            modePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            lightThemePopUp.widthAnchor.constraint(equalToConstant: 156),
            darkThemePopUp.widthAnchor.constraint(equalToConstant: 156),
            displayModePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            readingFocusWidthPopUp.widthAnchor.constraint(equalToConstant: 138),
            autoSavePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            footnoteLabel.leadingAnchor.constraint(equalTo: sectionsStack.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: generalContainer.trailingAnchor, constant: -32),
            footnoteLabel.topAnchor.constraint(equalTo: sectionsStack.bottomAnchor, constant: 14),
            footnoteBottomConstraint,
        ])
    }

    private func makeThemeControls(isDark: Bool) -> NSStackView {
        let prefix = isDark ? "dark" : "light"
        let page = isDark ? darkPageBackground : lightPageBackground
        let window = isDark ? darkWindowBackground : lightWindowBackground
        let reset = isDark ? resetDarkBackground : resetLightBackground
        for (well, name, label) in [
            (page, "Page", L10n.text("PDF page", "PDF 页面")),
            (window, "Window", L10n.text("Window and sidebars", "窗口与侧栏")),
        ] {
            well.identifier = NSUserInterfaceItemIdentifier("\(prefix)\(name)Background")
            well.colorWellStyle = .minimal
            well.supportsAlpha = false
            well.target = self
            well.action = #selector(handleBackgroundChanged(_:))
            well.setAccessibilityLabel(L10n.text(
                "\(isDark ? "Dark" : "Light") \(label) background",
                "\(isDark ? "深色" : "浅色")\(label)背景"
            ))
            well.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                well.widthAnchor.constraint(equalToConstant: 28),
                well.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        reset.identifier = NSUserInterfaceItemIdentifier(isDark ? "resetDarkBackground" : "resetLightBackground")
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L10n.text("Reset backgrounds", "重置背景"))
        reset.isBordered = false
        reset.controlSize = .small
        reset.target = self
        reset.action = #selector(handleResetBackground(_:))
        reset.toolTip = L10n.text("Use the theme’s page and window backgrounds", "使用主题默认的页面与窗口背景")
        reset.widthAnchor.constraint(equalToConstant: 22).isActive = true

        func label(_ title: String) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            return label
        }
        let stack = NSStackView(views: [
            isDark ? darkThemePopUp : lightThemePopUp,
            label(L10n.text("Page", "页面")), page, label(L10n.text("Window", "窗口")), window, reset,
        ])
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    private func applyBackgroundControls() {
        let appearance = configuration.appearance
        let snapshot = ThemeRegistry.snapshot(for: ThemeSelection(
            light: appearance.lightTheme, dark: appearance.darkTheme,
            lightBackground: appearance.lightBackground, darkBackground: appearance.darkBackground
        ))
        for (descriptor, name, page, window) in [
            (snapshot.light, NSAppearance.Name.aqua, lightPageBackground, lightWindowBackground),
            (snapshot.dark, NSAppearance.Name.darkAqua, darkPageBackground, darkWindowBackground),
        ] {
            let resolved = NSAppearance(named: name)!
            page.color = descriptor.color(for: .pageBackground, appearance: resolved)
            window.color = descriptor.color(for: .readerBackdrop, appearance: resolved)
            page.toolTip = L10n.text("PDF page", "PDF 页面") + " · \(ThemeHexColor(color: page.color)!.hexString)"
            window.toolTip = L10n.text("Window and sidebars", "窗口与侧栏") + " · \(ThemeHexColor(color: window.color)!.hexString)"
        }
        resetLightBackground.isEnabled = appearance.lightBackground != ThemeBackgroundOverrides()
        resetDarkBackground.isEnabled = appearance.darkBackground != ThemeBackgroundOverrides()
    }

    @objc private func handleBackgroundChanged(_ sender: NSColorWell) {
        guard !isApplyingConfiguration, let color = ThemeHexColor(color: sender.color) else { return }
        var updated = configuration
        switch sender {
        case lightPageBackground: updated.appearance.lightBackground.page = color
        case lightWindowBackground: updated.appearance.lightBackground.window = color
        case darkPageBackground: updated.appearance.darkBackground.page = color
        case darkWindowBackground: updated.appearance.darkBackground.window = color
        default: return
        }
        publishConfigurationIfChanged(updated)
    }

    @objc private func handleResetBackground(_ sender: NSButton) {
        var updated = configuration
        if sender === resetLightBackground {
            updated.appearance.lightBackground = .init()
        } else if sender === resetDarkBackground {
            updated.appearance.darkBackground = .init()
        }
        publishConfigurationIfChanged(updated)
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
            makeSidebarWidthRow(title: L10n.text("Left", "左侧"), field: leftSidebarWidthField, stepper: leftSidebarWidthStepper),
            makeSidebarWidthRow(title: L10n.text("Right", "右侧"), field: rightSidebarWidthField, stepper: rightSidebarWidthStepper),
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

    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField,
              searchField === shortcutSearchField else { return }
        rebuildShortcutRows()
        applyShortcutRows(configuration)
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

        shortcutSearchField.translatesAutoresizingMaskIntoConstraints = false
        shortcutSearchField.identifier = NSUserInterfaceItemIdentifier("shortcutSearchField")
        shortcutSearchField.placeholderString = L10n.text("Filter actions", "搜索操作")
        shortcutSearchField.controlSize = .small
        shortcutSearchField.delegate = self

        resetAllShortcutsButton.translatesAutoresizingMaskIntoConstraints = false
        resetAllShortcutsButton.controlSize = .small
        resetAllShortcutsButton.bezelStyle = .rounded
        resetAllShortcutsButton.target = self
        resetAllShortcutsButton.action = #selector(resetAllShortcuts(_:))

        shortcutsErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutsErrorLabel.identifier = NSUserInterfaceItemIdentifier("shortcutsErrorLabel")
        shortcutsErrorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutsErrorLabel.textColor = .systemRed
        shortcutsErrorLabel.maximumNumberOfLines = 0

        shortcutsStackView.orientation = .vertical
        shortcutsStackView.spacing = 0
        shortcutsStackView.translatesAutoresizingMaskIntoConstraints = false

        shortcutsContentView.translatesAutoresizingMaskIntoConstraints = false
        shortcutsContentView.addSubview(shortcutsHintLabel)
        shortcutsContentView.addSubview(shortcutSearchField)
        shortcutsContentView.addSubview(resetAllShortcutsButton)
        shortcutsContentView.addSubview(shortcutsErrorLabel)
        shortcutsContentView.addSubview(shortcutsStackView)

        NSLayoutConstraint.activate([
            shortcutsHintLabel.leadingAnchor.constraint(equalTo: shortcutsContentView.leadingAnchor, constant: 32),
            shortcutsHintLabel.trailingAnchor.constraint(equalTo: shortcutsContentView.trailingAnchor, constant: -32),
            shortcutsHintLabel.topAnchor.constraint(equalTo: shortcutsContentView.topAnchor, constant: 16),

            shortcutSearchField.leadingAnchor.constraint(equalTo: shortcutsHintLabel.leadingAnchor),
            shortcutSearchField.topAnchor.constraint(equalTo: shortcutsHintLabel.bottomAnchor, constant: 10),
            shortcutSearchField.widthAnchor.constraint(equalToConstant: 240),

            resetAllShortcutsButton.trailingAnchor.constraint(equalTo: shortcutsHintLabel.trailingAnchor),
            resetAllShortcutsButton.centerYAnchor.constraint(equalTo: shortcutSearchField.centerYAnchor),

            shortcutsErrorLabel.leadingAnchor.constraint(equalTo: shortcutsHintLabel.leadingAnchor),
            shortcutsErrorLabel.trailingAnchor.constraint(equalTo: shortcutsHintLabel.trailingAnchor),
            shortcutsErrorLabel.topAnchor.constraint(equalTo: shortcutSearchField.bottomAnchor, constant: 7),

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
        shortcutDefaultViews.removeAll(keepingCapacity: true)
        shortcutClearButtons.removeAll(keepingCapacity: true)
        shortcutRestoreButtons.removeAll(keepingCapacity: true)

        let matchingCommands = ShortcutCommand.allCases.filter {
            $0.matchesShortcutSearch(
                shortcutSearchField.stringValue,
                binding: configuration.shortcuts.bindings[$0]
            )
        }
        for section in ShortcutSection.allCases {
            let sectionCommands = matchingCommands.filter { $0.shortcutSection == section }
            guard sectionCommands.isEmpty == false else { continue }
            shortcutsStackView.addArrangedSubview(makeShortcutSectionHeader(section.title))
            for command in sectionCommands {
                let row = makeShortcutRow(for: command)
                shortcutsStackView.addArrangedSubview(row)
            }
        }
    }

    private func makeShortcutSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            container.heightAnchor.constraint(equalToConstant: 30),
        ])
        return container
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

        let removeButton = NSButton(title: L10n.text("Remove", "移除"), target: self, action: #selector(removeLibraryFolder(_:)))
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
        panel.message = L10n.text("Choose folders whose PDFs should appear in the library.", "选择需要在资料库中显示 PDF 的文件夹。")

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

        let defaultView = ShortcutSequenceView()
        defaultView.identifier = NSUserInterfaceItemIdentifier("shortcutDefault.\(command.rawValue)")
        defaultView.configure(sequences: [])

        let metadataViews: [NSView]
        if let builtInSequence = command.builtInShortcutSequence {
            let builtInLabel = NSTextField(labelWithString: L10n.text("Built-in", "内置"))
            builtInLabel.font = .systemFont(ofSize: 10.5)
            builtInLabel.textColor = .secondaryLabelColor
            let builtInView = ShortcutSequenceView()
            builtInView.identifier = NSUserInterfaceItemIdentifier("shortcutBuiltIn.\(command.rawValue)")
            builtInView.configure(sequences: [builtInSequence])
            metadataViews = [defaultLabel, defaultView, builtInLabel, builtInView]
        } else {
            metadataViews = [defaultLabel, defaultView]
        }
        let metadataStack = NSStackView(views: metadataViews)
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .centerY
        metadataStack.spacing = 6
        metadataStack.translatesAutoresizingMaskIntoConstraints = false
        metadataStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let clearButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.text("Clear Shortcut", "清除快捷键"))!,
            target: self,
            action: #selector(clearShortcut(_:))
        )
        clearButton.controlSize = .small
        clearButton.bezelStyle = .inline
        clearButton.toolTip = L10n.text("Clear Shortcut", "清除快捷键")
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        let restoreButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L10n.text("Restore Default", "恢复默认"))!,
            target: self,
            action: #selector(restoreShortcutDefault(_:))
        )
        restoreButton.controlSize = .small
        restoreButton.bezelStyle = .inline
        restoreButton.toolTip = L10n.text("Restore Default", "恢复默认")
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.identifier = NSUserInterfaceItemIdentifier(command.rawValue)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(captureButton)
        row.addSubview(metadataStack)
        row.addSubview(clearButton)
        row.addSubview(restoreButton)
        row.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: captureButton.leadingAnchor, constant: -16),

            metadataStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataStack.trailingAnchor.constraint(lessThanOrEqualTo: captureButton.leadingAnchor, constant: -16),
            metadataStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            captureButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            captureButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 160),
            captureButton.heightAnchor.constraint(equalToConstant: 28),

            restoreButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            restoreButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            restoreButton.widthAnchor.constraint(equalToConstant: 26),

            clearButton.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 26),

            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            row.heightAnchor.constraint(equalToConstant: 50),
        ])

        shortcutButtons[command] = captureButton
        shortcutDefaultLabels[command] = defaultLabel
        shortcutDefaultViews[command] = defaultView
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

    @objc
    private func resetAllShortcuts(_ sender: Any?) {
        var updatedConfiguration = configuration
        updatedConfiguration.shortcuts = .default
        publishConfigurationIfChanged(updatedConfiguration)
    }

    private func updateShortcut(_ shortcut: KeyboardShortcut?, for command: ShortcutCommand) {
        guard isApplyingConfiguration == false else { return }

        if shortcut == ShortcutCommand.commandPaletteShortcut {
            shortcutsErrorLabel.stringValue = L10n.text("⌘K is reserved for Command Palette.", "⌘K 已保留用于命令面板。")
            NSSound.beep()
            shortcutButtons[command]?.shortcut = configuration.shortcuts.bindings[command]
            return
        }

        if let shortcut,
           let conflict = configuration.shortcuts.bindings.first(where: { $0.key != command && $0.value == shortcut }) {
            shortcutsErrorLabel.stringValue = L10n.text(
                "“\(shortcut.displayString)” is already used by “\(conflict.key.menuTitle)”.",
                "“\(shortcut.displayString)” 已用于“\(conflict.key.menuTitle)”。"
            )
            NSSound.beep()
            shortcutButtons[command]?.shortcut = configuration.shortcuts.bindings[command]
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

#if DEBUG
extension SettingsViewController {
    func setShortcutSearchForTesting(_ query: String) {
        shortcutSearchField.stringValue = query
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: shortcutSearchField))
    }
}
#endif
