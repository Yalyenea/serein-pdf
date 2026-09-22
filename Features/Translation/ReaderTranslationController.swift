import AppKit
import PDFKit
import Translation

@MainActor
final class ReaderTranslationController: NSObject, NSWindowDelegate {
    private let documentStore: DocumentStore
    private var panel: NSPanel?
    private var translation: SelectionTranslation?
    private var bridge: (any TranslationTaskHosting)?
    private var languageTask: Task<Void, Never>?
    private var languages: [Locale.Language] = []
    private let content = NSView()
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "Auto →")
    private let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let output = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "Add Annotation", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init()
        configureContent()
    }

    @discardableResult
    func show(selection: PDFSelection, sessionID: UUID, in source: PDFView) -> Bool {
        guard let owner = source.window,
              let translation = try? SelectionTranslation(
                selection: selection, sessionID: sessionID, documentStore: documentStore
              ) else { return false }
        close()
        self.translation = translation
        translation.onChange = { [weak self] in self?.updateResult() }
        sourceLabel.stringValue = translation.sourceText
        contextLabel.stringValue = "\(translation.documentTitle) · Page \(translation.pageNumber)"
        contextLabel.toolTip = translation.documentTitle
        output.string = ""
        languages = [translation.request.targetLanguage]
        updateLanguagePicker()

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 310),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "Translate"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = true
        panel.minSize = NSSize(width: 330, height: 250)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.collectionBehavior = .fullScreenAuxiliary
        self.panel = panel

        if #available(macOS 15.0, *) {
            let bridge = AppleTranslationBridge(content: content, translation: translation)
            self.bridge = bridge
            panel.contentView = bridge.view
            updateResult()
            languagePicker.isEnabled = true
            bridge.start(translation.request)
            loadSupportedLanguages(for: translation)
        } else {
            panel.contentView = content
            statusLabel.stringValue = "Translation requires macOS 15 or later."
            languagePicker.isEnabled = false
            addButton.isEnabled = false
            retryButton.isHidden = true
        }

        owner.addChildWindow(panel, ordered: .above)
        NotificationCenter.default.addObserver(
            self, selector: #selector(ownerWillClose(_:)), name: NSWindow.willCloseNotification, object: owner
        )
        refreshThemeAppearance()
        position(panel, near: selection, in: source)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        languageTask?.cancel()
        languageTask = nil
        translation?.onChange = nil
        translation?.cancel()
        translation = nil
        bridge?.cancel()
        bridge = nil
        NotificationCenter.default.removeObserver(self)
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.parent?.removeChildWindow(panel)
        panel.close()
    }

    func windowWillClose(_ notification: Notification) { close() }
    @objc private func ownerWillClose(_ notification: Notification) { close() }

    func refreshThemeAppearance() {
        guard let panel else { return }
        panel.appearance = panel.parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            panel.backgroundColor = NightModeStyle.paneBackgroundColor
            content.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.cgColor
            sourceLabel.textColor = NightModeStyle.secondaryTextColor
            contextLabel.textColor = NightModeStyle.secondaryTextColor
            targetLabel.textColor = NightModeStyle.secondaryTextColor
            statusLabel.textColor = NightModeStyle.secondaryTextColor
            output.textColor = NightModeStyle.primaryTextColor
            output.insertionPointColor = NightModeStyle.primaryTextColor
        }
    }

    private func configureContent() {
        content.wantsLayer = true
        sourceLabel.maximumNumberOfLines = 3
        sourceLabel.font = .systemFont(ofSize: 11.5)
        sourceLabel.lineBreakMode = .byTruncatingTail
        contextLabel.font = .systemFont(ofSize: 10.5)
        contextLabel.lineBreakMode = .byTruncatingMiddle
        targetLabel.font = .systemFont(ofSize: 11)
        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.lineBreakMode = .byTruncatingTail
        languagePicker.controlSize = .small
        languagePicker.target = self
        languagePicker.action = #selector(changeLanguage(_:))
        languagePicker.setAccessibilityLabel("Translation target language")

        output.isEditable = false
        output.isSelectable = true
        output.isRichText = false
        output.drawsBackground = false
        output.font = .systemFont(ofSize: 13)
        output.textContainerInset = .zero
        output.textContainer?.lineFragmentPadding = 0
        output.isHorizontallyResizable = false
        output.isVerticallyResizable = true
        output.textContainer?.widthTracksTextView = true
        output.autoresizingMask = [.width]
        output.setAccessibilityLabel("Translation")
        let scroll = NSScrollView()
        scroll.documentView = output
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        for button in [addButton, retryButton] {
            button.bezelStyle = .recessed
            button.controlSize = .small
            button.target = self
        }
        addButton.action = #selector(addAnnotation(_:))
        retryButton.action = #selector(retry(_:))
        let header = NSStackView(views: [targetLabel, languagePicker])
        header.spacing = 6
        let footer = NSStackView(views: [statusLabel, retryButton, addButton])
        footer.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for view in [contextLabel, header, sourceLabel, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            contextLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            contextLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            contextLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: contextLabel.trailingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 9),
            sourceLabel.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: contextLabel.trailingAnchor),
            sourceLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 46),
            scroll.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contextLabel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: contextLabel.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
    }

    private func updateResult() {
        guard let translation else { return }
        retryButton.isHidden = true
        addButton.isEnabled = false
        addButton.title = translation.addedGroupID == nil ? "Add Annotation" : "Added"
        switch translation.state {
        case .translating:
            output.string = ""
            statusLabel.stringValue = "Translating…"
        case let .translated(text):
            output.string = text
            statusLabel.stringValue = translation.addedGroupID == nil ? "" : "Added to PDF"
            addButton.isEnabled = translation.addedGroupID == nil
        case let .failed(message):
            output.string = message
            statusLabel.stringValue = "Translation failed"
            retryButton.isHidden = false
        case .cancelled:
            break
        }
    }

    @available(macOS 15.0, *)
    private func loadSupportedLanguages(for translation: SelectionTranslation) {
        languageTask = Task { [weak self, weak translation] in
            let supported = await Self.supportedLanguages()
            guard Task.isCancelled == false, let self, let translation,
                  self.translation === translation else { return }
            self.languages = supported.sorted {
                self.languageTitle($0).localizedStandardCompare(self.languageTitle($1)) == .orderedAscending
            }
            self.updateLanguagePicker()
        }
    }

    @available(macOS 15.0, *)
    private nonisolated static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    private func updateLanguagePicker() {
        guard let translation else { return }
        let target = translation.request.targetLanguage
        languagePicker.removeAllItems()
        for language in languages { languagePicker.addItem(withTitle: languageTitle(language)) }
        if let index = languages.firstIndex(where: { $0.maximalIdentifier == target.maximalIdentifier }) {
            languagePicker.selectItem(at: index)
        } else {
            languagePicker.select(nil)
        }
    }

    private func languageTitle(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        guard let translation, languages.indices.contains(sender.indexOfSelectedItem) else { return }
        bridge?.start(translation.selectTargetLanguage(languages[sender.indexOfSelectedItem]))
    }

    @objc private func retry(_ sender: Any?) {
        guard let translation else { return }
        bridge?.start(translation.selectTargetLanguage(translation.request.targetLanguage))
    }

    @objc private func addAnnotation(_ sender: Any?) {
        do {
            _ = try translation?.addAnnotation()
        } catch {
            statusLabel.stringValue = error.localizedDescription
            statusLabel.toolTip = error.localizedDescription
            addButton.isEnabled = false
        }
    }

    private func position(_ panel: NSPanel, near selection: PDFSelection, in source: PDFView) {
        guard let owner = source.window, let page = selection.pages.first else { return }
        let rect = source.convert(selection.bounds(for: page), from: page).intersection(source.visibleRect)
        let anchor = rect.isEmpty ? source.visibleRect : rect
        let screenAnchor = owner.convertToScreen(source.convert(anchor, to: nil))
        let available = (owner.screen?.visibleFrame ?? owner.frame).insetBy(dx: 8, dy: 8)
        panel.setFrameOrigin(NSPoint(
            x: min(max(screenAnchor.midX - panel.frame.width / 2, available.minX), available.maxX - panel.frame.width),
            y: min(max(screenAnchor.minY - panel.frame.height - 8, available.minY), available.maxY - panel.frame.height)
        ))
    }
}

private final class TranslationPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
