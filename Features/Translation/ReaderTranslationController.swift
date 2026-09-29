import AppKit
import AVFoundation
import PDFKit

@MainActor
final class ReaderTranslationController: NSObject, NSWindowDelegate, AVSpeechSynthesizerDelegate {
    typealias HostFactory = @MainActor (NSView, SelectionTranslation) -> (any TranslationTaskHosting)?

    private let documentStore: DocumentStore
    private let makeHost: HostFactory
    private var panel: NSPanel?
    private var translation: SelectionTranslation?
    private var bridge: (any TranslationTaskHosting)?
    private var dictionaryTask: Task<Void, Never>?
    private let content = TranslationPanelContent(frame: .zero)
    private let speech = AVSpeechSynthesizer()
    private var spokenUtteranceID: ObjectIdentifier?
    private weak var speakingButton: NSButton?

    init(documentStore: DocumentStore, makeHost: @escaping HostFactory = ReaderTranslationController.systemHost) {
        self.documentStore = documentStore
        self.makeHost = makeHost
        super.init()
        speech.delegate = self
        for (button, action) in [
            (content.reverseButton, #selector(reverseDirection(_:))),
            (content.closeButton, #selector(dismiss(_:))),
            (content.sourceSpeechButton, #selector(speak(_:))),
            (content.targetSpeechButton, #selector(speak(_:))),
            (content.copyButton, #selector(copyResult(_:))),
            (content.addButton, #selector(addAnnotation(_:))),
            (content.retryButton, #selector(retry(_:))),
            (content.dictionaryButton, #selector(showDictionary(_:))),
        ] {
            button.target = self
            button.action = action
        }
    }

    static func systemHost(content: NSView, translation: SelectionTranslation) -> (any TranslationTaskHosting)? {
        if #available(macOS 15.0, *) {
            return AppleTranslationBridge(content: content, translation: translation)
        }
        return nil
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
        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: TranslationPanelContent.width, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        panel.title = L10n.text("Translate", "翻译")
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
        bridge = makeHost(content, translation)
        panel.contentView = bridge?.view ?? content
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
        startRequest()
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
        dictionaryTask?.cancel()
        dictionaryTask = nil
        stopSpeech()
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
    @objc private func dismiss(_ sender: Any?) { close() }
    @objc private func ownerWillClose(_ notification: Notification) { close() }
    @objc private func applicationDidResignActive(_ notification: Notification) { close() }

    func refreshThemeAppearance() {
        guard let panel else { return }
        panel.appearance = panel.parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        content.refreshThemeAppearance()
    }

    private func startRequest() {
        guard let translation else { return }
        dictionaryTask?.cancel()
        stopSpeech()
        content.prepare(for: translation)
        updateResult()
        if let word = translation.englishWord {
            let requestID = translation.request.id
            dictionaryTask = Task { [weak self] in
                let entry = await Task.detached(priority: .userInitiated) { EnglishDictionary.lookup(word) }.value
                guard !Task.isCancelled, let self, self.translation?.request.id == requestID else { return }
                self.content.display(dictionary: entry)
                self.resizeToContent()
            }
        }
        if let bridge {
            bridge.start(translation.request)
        } else {
            translation.complete(translation.request, with: .failure(SelectionTranslationError.requiresMacOS15))
        }
    }

    private func updateResult() {
        guard let translation else { return }
        content.display(translation)
        if bridge == nil { content.retryButton.isHidden = true }
        resizeToContent()
    }

    private func resizeToContent() {
        guard let panel else { return }
        let height = content.fittedHeight()
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - height,
                           width: TranslationPanelContent.width, height: height)
        if let screen = panel.screen ?? panel.parent?.screen {
            frame.origin.y = max(frame.minY, screen.visibleFrame.minY + 8)
        }
        panel.setFrame(frame, display: true)
        content.layoutSubtreeIfNeeded()
    }

    @objc private func reverseDirection(_ sender: Any?) {
        guard let translation else { return }
        _ = translation.reverseDirection()
        startRequest()
    }

    @objc private func retry(_ sender: Any?) {
        guard let translation else { return }
        _ = translation.retry()
        startRequest()
    }

    @objc private func copyResult(_ sender: Any?) {
        guard case let .translated(text) = translation?.state else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        content.showStatus(L10n.text("Copied", "已复制"))
        resizeToContent()
    }

    @objc private func addAnnotation(_ sender: Any?) {
        do {
            _ = try translation?.addAnnotation()
        } catch {
            content.showStatus(error.localizedDescription)
            content.addButton.isEnabled = false
            resizeToContent()
        }
    }

    @objc private func showDictionary(_ sender: Any?) {
        guard let word = translation?.englishWord else { return }
        content.showDefinition(for: NSAttributedString(string: word), at: content.dictionaryButton.convert(NSPoint(x: 0, y: content.dictionaryButton.bounds.midY), to: content))
    }

    @objc private func speak(_ sender: NSButton) {
        if sender === speakingButton { stopSpeech(); return }
        guard let translation else { return }
        let text: String
        let language: Locale.Language?
        if sender === content.sourceSpeechButton {
            text = translation.englishWord ?? translation.request.text
            language = translation.request.sourceLanguage
        } else {
            guard case let .translated(result) = translation.state else { return }
            text = result
            language = translation.request.targetLanguage
        }
        stopSpeech()
        guard let language,
              let voice = AVSpeechSynthesisVoice(language: sender === content.sourceSpeechButton
                ? content.sourceSpeechLanguageIdentifier
                : (language.languageCode?.identifier == "en" ? "en-US" : "zh-CN")) else {
            content.showStatus(L10n.text("No voice is available for this language. Add one in System Settings.", "此语言的系统语音不可用，请在系统设置中添加语音。"))
            resizeToContent()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        spokenUtteranceID = ObjectIdentifier(utterance)
        speakingButton = sender
        content.setSpeaking(sender)
        content.showStatus("")
        resizeToContent()
        speech.speak(utterance)
    }

    private func stopSpeech() {
        spokenUtteranceID = nil
        speakingButton = nil
        speech.stopSpeaking(at: .immediate)
        content.setSpeaking(nil)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechEnded(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechEnded(ObjectIdentifier(utterance))
    }

    private nonisolated func speechEnded(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.spokenUtteranceID == id else { return }
            self.spokenUtteranceID = nil
            self.speakingButton = nil
            self.content.setSpeaking(nil)
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
        if event.type == .keyDown, event.keyCode == 53 {
            cancelOperation(nil)
            return
        }
        super.sendEvent(event)
    }
}
