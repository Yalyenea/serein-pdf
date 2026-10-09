import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderTranslationControllerTests: XCTestCase {
    func testEscapeClosesBeforeTheFocusedControlConsumesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let control = EscapeConsumingTextView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        try XCTUnwrap(fixture.panel.contentView).addSubview(control)
        XCTAssertTrue(fixture.panel.makeFirstResponder(control))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.panel.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))

        fixture.panel.sendEvent(event)

        XCTAssertFalse(control.receivedKeyDown)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)
    }

    func testReturningFocusToReaderClosesTheTranslation() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        // SwiftPM runs without an active application; dispatch AppKit's focus lifecycle directly.
        fixture.panel.becomeKey()
        fixture.panel.resignKey()
        fixture.owner.makeKey()
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)
    }

    func testDownloadSheetDoesNotDismissItsTranslationWindow() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: .titled, backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        fixture.panel.beginSheet(sheet)
        defer { fixture.panel.endSheet(sheet); sheet.close() }
        fixture.panel.resignKey()
        XCTAssertTrue(fixture.panel.isVisible)
        XCTAssertTrue(fixture.panel.attachedSheet === sheet)
    }

    func testApplicationDeactivationAndOwnerClosureDismissTheTranslation() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)

        XCTAssertTrue(fixture.controller.show(selection: fixture.selection, sessionID: fixture.sessionID, in: fixture.pdf))
        let reopened = try XCTUnwrap(fixture.owner.childWindows?.first)
        fixture.owner.close()
        XCTAssertFalse(reopened.isVisible)
        XCTAssertNil(reopened.parent)
    }

    @available(macOS 15.0, *)
    func testUnrecognizedLanguageDisplaysAnErrorWithoutRemovingContent() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let content = try XCTUnwrap(fixture.panel.contentView)
        func textViews(in view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        XCTAssertTrue(textViews(in: content).contains {
            $0.string == SelectionTranslationError.unrecognizedLanguage.localizedDescription
        })
    }

    func testWordPresentationAndDirectionCorrectionUseTheSharedRequest() throws {
        var host: TranslationTestHost!
        let fixture = try makeFixture(text: "inference") { view, translation in
            host = TranslationTestHost(view: view, translation: translation)
            return host
        }
        defer { fixture.controller.close(); fixture.owner.close() }
        let content = try XCTUnwrap(fixture.panel.contentView as? TranslationPanelContent)
        XCTAssertEqual(content.wordLabel.stringValue, "inference")
        XCTAssertFalse(content.wordLabel.isHidden)
        XCTAssertEqual(content.reverseButton.title, L10n.text("EN → ZH", "EN → 中文"))
        XCTAssertEqual(content.output.string, "推理")
        XCTAssertTrue(content.copyButton.isEnabled)
        XCTAssertTrue(content.addButton.isEnabled)
        XCTAssertTrue(content.sourceSpeechButton.isEnabled)
        XCTAssertFalse(content.sourceText.isEditable)
        XCTAssertFalse(content.output.isEditable)

        content.reverseButton.performClick(nil)
        XCTAssertEqual(host.requests.last?.sourceLanguage?.languageCode?.identifier, "zh")
        XCTAssertEqual(host.requests.last?.targetLanguage.languageCode?.identifier, "en")
        XCTAssertEqual(host.requests.last?.text, "inference")
        XCTAssertTrue(content.wordLabel.isHidden)
        XCTAssertEqual(content.reverseButton.title, L10n.text("ZH → EN", "中文 → EN"))
        XCTAssertEqual(content.sourceText.string, "inference")
        XCTAssertEqual(content.output.string, "Inference")
        content.addButton.performClick(nil)
        XCTAssertFalse(content.addButton.isEnabled)
        XCTAssertEqual(content.addButton.title, L10n.text("Annotated", "已加入批注"))
        fixture.controller.close()
        XCTAssertTrue(host.cancelled)
    }

    func testOpenPanelRefreshesAcrossAllThemesAndCustomBackgrounds() throws {
        let manager = ThemeManager.shared
        let previous = manager.selection
        defer {
            manager.apply(light: previous.light, dark: previous.dark,
                          lightBackground: previous.lightBackground, darkBackground: previous.darkBackground)
        }
        let fixture = try makeFixture(text: "inference") { TranslationTestHost(view: $0, translation: $1) }
        defer { fixture.controller.close(); fixture.owner.close() }
        let content = try XCTUnwrap(fixture.panel.contentView as? TranslationPanelContent)
        content.display(dictionary: EnglishDictionary(
            text: "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① 推断 ② 推论"
        ))
        content.output.setSelectedRange(NSRange(location: 0, length: 1))
        content.sourceLabel.selectText(nil)
        let pronunciationEditor = try XCTUnwrap(content.sourceLabel.currentEditor() as? NSTextView)
        let selectedPronunciation = pronunciationEditor.selectedRange()
        for theme in LightTheme.allCases {
            manager.apply(light: theme, dark: .rosePineMoon)
            fixture.owner.appearance = NSAppearance(named: .aqua)
            fixture.controller.refreshThemeAppearance()
            try assertTheme(content)
            if theme == .rosePineDawn {
                try assertLayout(content, panel: fixture.panel)
                try savePreview(content, name: "translation-word-dawn")
            }
        }
        for theme in DarkTheme.allCases {
            manager.apply(light: .normal, dark: theme)
            fixture.owner.appearance = NSAppearance(named: .darkAqua)
            fixture.controller.refreshThemeAppearance()
            try assertTheme(content)
            if theme == .rosePineMoon {
                try assertLayout(content, panel: fixture.panel)
                try savePreview(content, name: "translation-word-moon")
            }
        }
        for (appearance, color) in [(NSAppearance.Name.aqua, "#282232"), (.darkAqua, "#f3e8db")] {
            manager.apply(light: .normal, dark: .rosePineMoon,
                          lightBackground: .init(window: ThemeHexColor(hex: color)),
                          darkBackground: .init(window: ThemeHexColor(hex: color)))
            fixture.owner.appearance = NSAppearance(named: appearance)
            fixture.controller.refreshThemeAppearance()
            try assertTheme(content)
        }
        XCTAssertEqual(content.output.selectedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(pronunciationEditor.selectedRange(), selectedPronunciation)
        XCTAssertEqual(content.output.string, "n.\t推理")
    }

    func testWordPronunciationIsVisibleBesideTheSpeechButton() throws {
        for (selection, text, phonetics) in [
            ("learned", "learned 1 | BrE ˈləːnɪd, AmE ˈlərnəd | adjective ① 博学的", "ˈlərnəd"),
            ("use", "use A. noun | BrE juːs, AmE jus | ① 使用", "jus"),
            ("inferences", "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① 推断", "ˈɪnf(ə)rən(t)s"),
        ] {
            let fixture = try makeFixture(text: selection) { TranslationTestHost(view: $0, translation: $1) }
            defer { fixture.controller.close(); fixture.owner.close() }
            let content = try XCTUnwrap(fixture.panel.contentView as? TranslationPanelContent)
            content.display(dictionary: EnglishDictionary(text: text))
            try assertLayout(content, panel: fixture.panel)

            XCTAssertEqual(content.wordLabel.stringValue, selection)
            XCTAssertEqual(content.sourceLabel.stringValue, "/\(phonetics)/")
            XCTAssertFalse(content.sourceLabel.isHidden)
            XCTAssertTrue(content.sourceLabel.isSelectable)
            XCTAssertEqual(content.sourceSpeechLanguageIdentifier, "en-US")
            XCTAssertTrue(content.sourceSpeechButton.isEnabled)
            let label = content.sourceLabel.convert(content.sourceLabel.bounds, to: content)
            let button = content.sourceSpeechButton.convert(content.sourceSpeechButton.bounds, to: content)
            XCTAssertGreaterThan(label.width, 0)
            XCTAssertLessThanOrEqual(label.maxX, button.minX)
            XCTAssertLessThanOrEqual(button.minX - label.maxX, 12)
            XCTAssertEqual(label.midY, button.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(button.maxX, content.bounds.maxX)
            try savePreview(content, name: "translation-pronunciation-\(selection)")
        }
    }

    func testWordPanelUsesChosenInterfaceLanguage() throws {
        defer { L10n.configure(.english) }
        for language in [AppLanguage.english, .chinese] {
            L10n.configure(language)
            let fixture = try makeFixture(text: "Thus") {
                TranslationTestHost(view: $0, translation: $1)
            }
            defer { fixture.controller.close(); fixture.owner.close() }
            let content = try XCTUnwrap(fixture.panel.contentView as? TranslationPanelContent)
            content.display(dictionary: EnglishDictionary.lookup("Thus"))
            try assertLayout(content, panel: fixture.panel)
            XCTAssertEqual(content.kindLabel.stringValue, language == .chinese ? "词典" : "Dictionary")
            XCTAssertEqual(content.addButton.title, language == .chinese ? "加入批注" : "Annotate")
            XCTAssertNil(content.output.enclosingScrollView)
            try savePreview(content, name: "translation-Thus-\(language.rawValue)")
        }
    }

    func testNativeWordAndLongSentenceLayoutsStayWithinThePanel() throws {
        var translation: SelectionTranslation!
        let fixture = try makeFixture(text: "inference") {
            translation = $1
            return TranslationTestHost(view: $0, translation: $1)
        }
        defer { fixture.controller.close(); fixture.owner.close() }
        let content = try XCTUnwrap(fixture.panel.contentView as? TranslationPanelContent)
        let entry = EnglishDictionary.lookup("inference")
        content.display(dictionary: entry)
        try assertLayout(content, panel: fixture.panel)
        if entry?.partOfSpeech != nil { try assertGlossBaseline(content) }
        XCTAssertNil(content.output.enclosingScrollView)
        XCTAssertEqual(content.output.frame.origin, .zero)
        try savePreview(content, name: "translation-word")

        translation.complete(translation.request, with: .success(String(repeating: "推断；推论；推理；", count: 20)))
        try assertLayout(content, panel: fixture.panel)
        if entry?.partOfSpeech != nil { try assertGlossBaseline(content) }
        XCTAssertNil(content.output.enclosingScrollView)
        XCTAssertGreaterThan(content.output.frame.height, 160)
        XCTAssertEqual(content.output.frame.origin, .zero)
        XCTAssertEqual(content.output.frame.height, try XCTUnwrap(content.output.superview).bounds.height, accuracy: 1)
        try savePreview(content, name: "translation-word-wrapped")

        content.reverseButton.performClick(nil)
        content.sourceText.string = "学习与推理密切相关。"
        content.output.string = "Learning and inference are closely related."
        try assertLayout(content, panel: fixture.panel)
        try savePreview(content, name: "translation-sentence-compact")
        content.sourceText.string = String(repeating: "我们使用 attention mechanism 完成推理。", count: 20)
        content.output.string = String(repeating: "We use an attention mechanism for inference. ", count: 20)
        try assertLayout(content, panel: fixture.panel)
        XCTAssertLessThan(fixture.panel.frame.height, 500)
        XCTAssertGreaterThan(content.sourceText.frame.height, content.sourceText.enclosingScrollView!.frame.height)
        XCTAssertGreaterThan(content.output.frame.height, content.output.enclosingScrollView!.frame.height)
        try savePreview(content, name: "translation-sentence")
        fixture.controller.perform(NSSelectorFromString("retry:"), with: nil)
        XCTAssertNotNil(content.output.enclosingScrollView)
        XCTAssertTrue(content.output.isDescendant(of: content))
        content.reverseButton.performClick(nil)
        XCTAssertNil(content.output.enclosingScrollView)
        XCTAssertTrue(content.output.isDescendant(of: content))
    }

    private func assertGlossBaseline(_ content: TranslationPanelContent) throws {
        let text = content.output
        let layout = try XCTUnwrap(text.layoutManager)
        layout.ensureLayout(for: try XCTUnwrap(text.textContainer))
        let chinese = (text.string as NSString).range(of: "推")
        XCTAssertNotEqual(chinese.location, NSNotFound)
        let nounGlyph = layout.glyphIndexForCharacter(at: 0)
        let chineseGlyph = layout.glyphIndexForCharacter(at: chinese.location)
        func baseline(_ glyph: Int) -> CGFloat {
            layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + layout.location(forGlyphAt: glyph).y
        }
        XCTAssertEqual(baseline(nounGlyph), baseline(chineseGlyph), accuracy: 0.1)
        let secondLine = layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil)
        if secondLine.minY > 0 {
            var range = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: &range)
            XCTAssertEqual(layout.location(forGlyphAt: range.location).x + secondLine.minX,
                           layout.location(forGlyphAt: chineseGlyph).x, accuracy: 1)
        }
    }

    private func assertLayout(_ content: TranslationPanelContent, panel: NSWindow) throws {
        let height = content.fittedHeight()
        panel.setContentSize(NSSize(width: TranslationPanelContent.width, height: height))
        content.layoutSubtreeIfNeeded()
        for view in [content.reverseButton, content.closeButton,
                     content.copyButton, content.addButton] {
            let frame = view.convert(view.bounds, to: content)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertGreaterThanOrEqual(frame.minY, 0)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY)
        }
    }

    private func assertTheme(_ content: TranslationPanelContent) throws {
        let background = try XCTUnwrap(NSColor(cgColor: XCTUnwrap(content.layer?.backgroundColor)))
        let storage = try XCTUnwrap(content.output.textStorage)
        let primary = try XCTUnwrap(storage.attribute(.foregroundColor, at: storage.length - 1, effectiveRange: nil) as? NSColor)
        let wordClass = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let secondary = try XCTUnwrap(content.dictionaryText.textColor)
        let pronunciation = try XCTUnwrap(content.sourceLabel.textColor)
        let pronunciationEditorColor = try (content.sourceLabel.currentEditor() as? NSTextView).map {
            try XCTUnwrap($0.textColor)
        }
        let selection = try XCTUnwrap(content.output.selectedTextAttributes[.backgroundColor] as? NSColor)
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(ThemeHexColor(color: background), ThemeHexColor(color: NightModeStyle.paneBackgroundColor))
            XCTAssertEqual(ThemeHexColor(color: primary), ThemeHexColor(color: NightModeStyle.primaryTextColor))
            XCTAssertEqual(ThemeHexColor(color: secondary), ThemeHexColor(color: NightModeStyle.secondaryTextColor))
            XCTAssertEqual(ThemeHexColor(color: pronunciation), ThemeHexColor(color: NightModeStyle.secondaryTextColor))
            if let pronunciationEditorColor {
                XCTAssertEqual(ThemeHexColor(color: pronunciationEditorColor), ThemeHexColor(color: NightModeStyle.secondaryTextColor))
            }
            XCTAssertEqual(ThemeHexColor(color: wordClass), ThemeHexColor(color: NightModeStyle.secondaryTextColor))
            XCTAssertEqual(ThemeHexColor(color: selection), ThemeHexColor(color: NightModeStyle.selectedChromeBackgroundColor))
        }
    }

    private func savePreview(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SEREIN_TRANSLATION_PREVIEW"] else { return }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    private func makeFixture(
        text: String = "12345 + 67890",
        makeHost: @escaping ReaderTranslationController.HostFactory = ReaderTranslationController.systemHost
    ) throws -> (
        controller: ReaderTranslationController, owner: NSWindow, panel: NSWindow,
        pdf: PDFView, selection: PDFSelection, sessionID: UUID
    ) {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        // No language can be inferred from numbers, so lifecycle tests never start a system download.
        let session = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "translation-panel", pages: [text]
        ))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString(text, withOptions: []).first)
        let owner = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 500),
                             styleMask: .titled, backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let pdf = PDFView(frame: owner.contentView!.bounds)
        pdf.document = document
        owner.contentView = pdf
        owner.makeKeyAndOrderFront(nil)
        let controller = ReaderTranslationController(documentStore: store, makeHost: makeHost)
        XCTAssertTrue(controller.show(selection: selection, sessionID: session.id, in: pdf))
        let panel = try XCTUnwrap(owner.childWindows?.first)
        XCTAssertTrue(panel.isVisible)
        return (controller, owner, panel, pdf, selection, session.id)
    }
}

private final class EscapeConsumingTextView: NSTextView {
    var receivedKeyDown = false
    override func keyDown(with event: NSEvent) { receivedKeyDown = true }
}

@MainActor
private final class TranslationTestHost: TranslationTaskHosting {
    let view: NSView
    let translation: SelectionTranslation
    var requests: [SelectionTranslation.Request] = []
    var cancelled = false

    init(view: NSView, translation: SelectionTranslation) {
        self.view = view
        self.translation = translation
    }

    func start(_ request: SelectionTranslation.Request) {
        requests.append(request)
        translation.complete(request, with: .success(request.targetLanguage.languageCode?.identifier == "en" ? "Inference" : "推理"))
    }

    func cancel() { cancelled = true }
}
