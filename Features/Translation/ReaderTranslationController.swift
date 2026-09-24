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
    private let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let output = NSTextView()
    private let scroll = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private var textHeight: NSLayoutConstraint!
    private static let width = AnnotationPreviewView.contentWidth
    private static let maximumTextHeight: CGFloat = 240

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
        output.string = ""
        languages = [translation.request.targetLanguage]
        updateLanguagePicker()

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 70),
            styleMask: .borderless,
            backing: .buffered, defer: false
        )
        panel.title = "Translate"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
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
            output.string = "Translation requires macOS 15 or later."
            languagePicker.isEnabled = false
            addButton.isEnabled = false
            retryButton.isHidden = true
            resizeToContent()
        }

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 6
        panel.contentView?.layer?.masksToBounds = true

        owner.addChildWindow(panel, ordered: .above)
        NotificationCenter.default.addObserver(
            self, selector: #selector(ownerWillClose(_:)), name: NSWindow.willCloseNotification, object: owner
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification, object: NSApp
        )
        refreshThemeAppearance()
        position(panel, near: selection, in: source)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        let owner = panel.parent
        let restoreFocus = panel.isKeyWindow && NSApp.isActive
        panel.delegate = nil
        languageTask?.cancel()
        languageTask = nil
        translation?.onChange = nil
        translation?.cancel()
        translation = nil
        bridge?.cancel()
        bridge = nil
        NotificationCenter.default.removeObserver(self)
        owner?.removeChildWindow(panel)
        panel.close()
        if restoreFocus, owner?.isVisible == true { owner?.makeKey() }
    }

    func windowDidResignKey(_ notification: Notification) {
        // The system may present a language-download sheet inside the translation window.
        guard panel?.attachedSheet == nil else { return }
        close()
    }

    func windowWillClose(_ notification: Notification) { close() }
    @objc private func ownerWillClose(_ notification: Notification) { close() }
    @objc private func applicationDidResignActive(_ notification: Notification) { close() }

    func refreshThemeAppearance() {
        guard let panel else { return }
        panel.appearance = panel.parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.cgColor
            content.layer?.borderColor = NightModeStyle.secondaryTextColor.withAlphaComponent(0.16).cgColor
            statusLabel.textColor = NightModeStyle.secondaryTextColor
            output.textColor = NightModeStyle.primaryTextColor
            output.insertionPointColor = NightModeStyle.primaryTextColor
            languagePicker.contentTintColor = NightModeStyle.secondaryTextColor
            addButton.contentTintColor = NightModeStyle.primaryTextColor
            retryButton.contentTintColor = NightModeStyle.primaryTextColor
        }
    }

    private func configureContent() {
        content.wantsLayer = true
        content.layer?.cornerRadius = 6
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.lineBreakMode = .byTruncatingTail
        languagePicker.controlSize = .small
        languagePicker.font = .systemFont(ofSize: 10.5)
        languagePicker.isBordered = false
        languagePicker.target = self
        languagePicker.action = #selector(changeLanguage(_:))
        languagePicker.setAccessibilityLabel("Translation target language")
        languagePicker.toolTip = "Translation target language"

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
        scroll.documentView = output
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        for button in [addButton, retryButton] {
            button.bezelStyle = .recessed
            button.isBordered = false
            button.controlSize = .small
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.target = self
        }
        addButton.action = #selector(addAnnotation(_:))
        addButton.imagePosition = .imageOnly
        addButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Add Annotation")
        addButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        addButton.toolTip = "Add Annotation"
        addButton.setAccessibilityLabel("Add Annotation")
        retryButton.action = #selector(retry(_:))
        let actions = NSStackView(views: [retryButton, addButton])
        actions.spacing = 8
        for view in [scroll, languagePicker, actions, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        textHeight = scroll.heightAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            textHeight,
            addButton.widthAnchor.constraint(equalToConstant: 22),
            addButton.heightAnchor.constraint(equalToConstant: 22),
            languagePicker.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            languagePicker.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: -3),
            languagePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
            languagePicker.heightAnchor.constraint(equalToConstant: 22),
            actions.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            actions.centerYAnchor.constraint(equalTo: languagePicker.centerYAnchor),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: languagePicker.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: languagePicker.bottomAnchor, constant: 3),
            statusLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
        ])
    }

    private func updateResult() {
        guard let translation else { return }
        retryButton.isHidden = true
        addButton.isEnabled = false
        let added = translation.addedGroupID != nil
        let label = added ? "Annotation Added" : "Add Annotation"
        addButton.image = NSImage(systemSymbolName: added ? "checkmark.circle" : "plus.circle", accessibilityDescription: label)
        addButton.toolTip = label
        addButton.setAccessibilityLabel(label)
        statusLabel.stringValue = ""
        statusLabel.toolTip = nil
        switch translation.state {
        case .translating:
            output.string = "Translating…"
        case let .translated(text):
            output.string = text
            addButton.isEnabled = translation.addedGroupID == nil
        case let .failed(message):
            output.string = message
            retryButton.isHidden = false
        case .cancelled:
            break
        }
        output.scrollToBeginningOfDocument(nil)
        resizeToContent()
    }

    private func resizeToContent() {
        guard let panel, let container = output.textContainer, let layout = output.layoutManager else { return }
        let width = Self.width - 28
        output.setFrameSize(NSSize(width: width, height: max(output.frame.height, 20)))
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = max(20, ceil(layout.usedRect(for: container).height))
        textHeight.constant = min(height, Self.maximumTextHeight)
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
        let statusHeight: CGFloat = statusLabel.isHidden ? 0 : 18
        let size = NSSize(width: Self.width, height: 12 + textHeight.constant + 8 + 22 + 8 + statusHeight)
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        if let screen = panel.screen ?? panel.parent?.screen {
            frame.origin.y = max(frame.minY, screen.visibleFrame.minY + 8)
        }
        panel.setFrame(frame, display: true)
        content.layoutSubtreeIfNeeded()
        output.setFrameSize(NSSize(width: width, height: height))
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
            resizeToContent()
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

    override func sendEvent(_ event: NSEvent) {
        // Handle Escape before SwiftUI or the selectable text view consumes it.
        if event.type == .keyDown, event.keyCode == 53 {
            cancelOperation(nil)
            return
        }
        super.sendEvent(event)
    }
}
