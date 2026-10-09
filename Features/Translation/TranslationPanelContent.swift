import AppKit

@MainActor
final class TranslationPanelContent: NSView {
    static let width: CGFloat = 380
    let kindLabel = NSTextField(labelWithString: L10n.text("Translate", "翻译"))
    let wordLabel = NSTextField(wrappingLabelWithString: "")
    let sourceLabel = NSTextField(wrappingLabelWithString: "")
    let targetLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let sourceText = NSTextView()
    let output = NSTextView()
    let dictionaryText = NSTextView()
    let reverseButton = NSButton()
    let closeButton = NSButton()
    let sourceSpeechButton = NSButton()
    let targetSpeechButton = NSButton()
    let copyButton = NSButton()
    let addButton = NSButton()
    let retryButton = NSButton()
    let dictionaryButton = NSButton()
    private(set) var sourceSpeechLanguageIdentifier = "en-US"

    private let kindIcon = NSImageView()
    private let accentLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private let body = NSStackView()
    private let sourceHeader = NSStackView()
    private let targetHeader = NSStackView()
    private let sourceScroll = NSScrollView()
    private let outputScroll = NSScrollView()
    private let outputHost = NSView()
    private let dictionaryScroll = NSScrollView()
    private let footerDivider = NSView()
    private let translationDivider = NSView()
    private var sourceHeight: NSLayoutConstraint!
    private var outputHeight: NSLayoutConstraint!
    private var dictionaryHeight: NSLayoutConstraint!
    private var isWord = false
    private var wordClass: String?
    private var resultText = ""
    private var hasResult = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        for label in [kindLabel, sourceLabel, targetLabel, statusLabel] {
            label.font = .systemFont(ofSize: 11)
        }
        wordLabel.font = NSFont(name: "Georgia", size: 28)
        wordLabel.maximumNumberOfLines = 2
        wordLabel.isSelectable = true
        sourceLabel.isSelectable = true
        sourceLabel.maximumNumberOfLines = 2
        accentLabel.font = .systemFont(ofSize: 13)
        statusLabel.maximumNumberOfLines = 3
        kindIcon.image = NSImage(systemSymbolName: "book", accessibilityDescription: nil)
        kindIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        kindIcon.setAccessibilityElement(false)
        kindIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        kindIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        configureButton(reverseButton, title: "", symbol: "", help: L10n.text("Reverse translation direction", "切换翻译方向"))
        configureButton(closeButton, title: "", symbol: "xmark", help: L10n.text("Close", "关闭"))
        configureButton(sourceSpeechButton, title: "", symbol: "speaker.wave.2", help: L10n.text("Read original aloud", "朗读原文"))
        configureButton(targetSpeechButton, title: "", symbol: "speaker.wave.2", help: L10n.text("Read translation aloud", "朗读译文"))
        configureButton(copyButton, title: L10n.text("Copy Translation", "复制译文"), symbol: "doc.on.doc", help: L10n.text("Copy Translation", "复制译文"))
        configureButton(addButton, title: L10n.text("Annotate", "加入批注"), symbol: "highlighter", help: L10n.text("Annotate", "加入批注"))
        configureButton(retryButton, title: L10n.text("Retry", "重试"), symbol: "arrow.clockwise", help: L10n.text("Retry translation", "重试翻译"))
        configureButton(dictionaryButton, title: L10n.text("Open in Dictionary", "在系统词典中查看"), symbol: "arrow.up.right", help: L10n.text("Open in Dictionary", "在系统词典中查看"))
        dictionaryButton.imagePosition = .imageTrailing
        dictionaryButton.font = .systemFont(ofSize: 11)
        dictionaryButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        reverseButton.font = .systemFont(ofSize: 11)
        retryButton.isHidden = true
        statusLabel.isHidden = true

        sourceHeight = configureText(sourceText, scroll: sourceScroll, label: L10n.text("Original", "原文"), fontSize: 14, lineHeight: 24.5)
        let scrollHeight = configureText(output, scroll: outputScroll, label: L10n.text("Translation", "译文"), fontSize: 16, lineHeight: 28)
        scrollHeight.isActive = false
        outputHeight = outputHost.heightAnchor.constraint(equalToConstant: 28)
        outputHeight.isActive = true
        outputScroll.autoresizingMask = [.width, .height]
        dictionaryHeight = configureText(dictionaryText, scroll: dictionaryScroll, label: L10n.text("Dictionary summary", "词典摘要"), fontSize: 13, lineHeight: 21.5)
        dictionaryScroll.hasVerticalScroller = false
        dictionaryText.textContainer?.maximumNumberOfLines = 2
        dictionaryText.textContainer?.lineBreakMode = .byTruncatingTail
        let top = row([kindIcon, kindLabel, spacer(), reverseButton, closeButton], spacing: 6)
        top.heightAnchor.constraint(equalToConstant: 24).isActive = true
        configureRow(sourceHeader, views: [sourceLabel, spacer(), sourceSpeechButton], spacing: 8)
        configureRow(targetHeader, views: [targetLabel, spacer(), targetSpeechButton], spacing: 8)
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceLabel.setContentHuggingPriority(.required, for: .horizontal)

        configureColumn(body, views: [wordLabel, sourceHeader, sourceScroll, translationDivider,
                                     targetHeader, outputHost, dictionaryScroll, dictionaryButton])
        for view in [sourceHeader, sourceScroll, translationDivider, targetHeader, outputHost, dictionaryScroll] {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        wordLabel.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        for divider in [footerDivider, translationDivider] {
            divider.wantsLayer = true
            divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
        let footer = row([copyButton, spacer(), retryButton, addButton], spacing: 8)
        footer.heightAnchor.constraint(equalToConstant: 27).isActive = true
        configureColumn(stack, views: [inset(top, horizontal: 14, top: 10),
                                       inset(body, horizontal: 16, top: 8, bottom: 13), footerDivider,
                                       inset(footer, horizontal: 10, top: 7, bottom: 7),
                                       inset(statusLabel, horizontal: 16, bottom: 8)])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        stack.arrangedSubviews.last?.isHidden = true
    }

    private func configureButton(_ button: NSButton, title: String, symbol: String, help: String) {
        button.title = title
        button.image = symbol.isEmpty ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        button.imagePosition = symbol.isEmpty ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        button.isBordered = false
        button.bezelStyle = .recessed
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12)
        button.toolTip = help
        button.setAccessibilityLabel(help)
        if title.isEmpty, !symbol.isEmpty {
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureText(_ text: NSTextView, scroll: NSScrollView, label: String,
                               fontSize: CGFloat, lineHeight: CGFloat) -> NSLayoutConstraint {
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        text.defaultParagraphStyle = paragraph
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.autoresizingMask = [.width]
        text.setAccessibilityLabel(label)
        scroll.documentView = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        let height = scroll.heightAnchor.constraint(equalToConstant: lineHeight)
        height.isActive = true
        return height
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let result = NSStackView()
        configureRow(result, views: views, spacing: spacing)
        return result
    }

    private func configureRow(_ row: NSStackView, views: [NSView], spacing: CGFloat) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        row.setViews(views, in: .leading)
    }

    private func configureColumn(_ column: NSStackView, views: [NSView]) {
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        for view in views { column.addArrangedSubview(view) }
    }

    private func inset(_ child: NSView, horizontal: CGFloat, top: CGFloat = 0, bottom: CGFloat = 0) -> NSView {
        let view = NSView()
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontal),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontal),
            child.topAnchor.constraint(equalTo: view.topAnchor, constant: top),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottom),
        ])
        return view
    }

    func prepare(for translation: SelectionTranslation) {
        let word = translation.englishWord
        isWord = word != nil
        outputScroll.documentView = nil
        output.isVerticallyResizable = !isWord
        if isWord {
            outputScroll.removeFromSuperview()
            outputHost.addSubview(output)
            output.setFrameOrigin(.zero)
        } else {
            output.removeFromSuperview()
            outputHost.addSubview(outputScroll)
            outputScroll.frame = outputHost.bounds
            outputScroll.documentView = output
        }
        let chinese = translation.request.sourceLanguage?.languageCode?.identifier == "zh"
        kindLabel.stringValue = isWord ? L10n.text("Dictionary", "词典") : L10n.text("Translate", "翻译")
        kindIcon.image = NSImage(systemSymbolName: isWord ? "book" : "character.bubble", accessibilityDescription: nil)
        reverseButton.title = chinese ? L10n.text("ZH → EN", "中文 → EN") : L10n.text("EN → ZH", "EN → 中文")
        reverseButton.isHidden = translation.request.sourceLanguage == nil
        reverseButton.isEnabled = translation.request.sourceLanguage != nil
        wordLabel.stringValue = word ?? ""
        wordLabel.isHidden = !isWord
        accentLabel.stringValue = ""
        accentLabel.isHidden = true
        sourceLabel.stringValue = chinese ? L10n.text("Chinese", "中文") : L10n.text("English", "英文")
        sourceLabel.font = isWord ? NSFont(name: "Georgia", size: 15) : .systemFont(ofSize: 11)
        sourceLabel.setAccessibilityLabel(isWord ? L10n.text("Pronunciation", "音标") : L10n.text("Source language", "原文语言"))
        sourceSpeechLanguageIdentifier = chinese ? "zh-CN" : "en-US"
        let sourceViews: [NSView] = isWord
            ? [accentLabel, sourceLabel, sourceSpeechButton, spacer()]
            : [sourceLabel, spacer(), sourceSpeechButton]
        configureRow(sourceHeader, views: sourceViews, spacing: 8)
        targetLabel.stringValue = chinese ? L10n.text("English", "英文") : L10n.text("Chinese", "中文")
        sourceText.string = translation.request.text
        sourceScroll.isHidden = isWord
        targetHeader.isHidden = isWord
        translationDivider.isHidden = isWord
        wordClass = nil
        hasResult = false
        dictionaryScroll.isHidden = !isWord
        dictionaryButton.isHidden = !isWord
        dictionaryText.string = isWord ? L10n.text("Looking up…", "正在查询词典…") : ""
        sourceSpeechButton.isEnabled = translation.request.sourceLanguage != nil
        targetSpeechButton.isEnabled = false
        copyButton.title = isWord ? L10n.text("Copy Definition", "复制释义") : L10n.text("Copy Translation", "复制译文")
        copyButton.setAccessibilityLabel(copyButton.title)
        copyButton.toolTip = copyButton.title
        output.setAccessibilityLabel(isWord ? L10n.text("Chinese definition", "中文释义") : L10n.text("Translation", "译文"))
        body.setCustomSpacing(7, after: wordLabel)
        body.setCustomSpacing(3, after: sourceHeader)
        body.setCustomSpacing(13, after: sourceScroll)
        body.setCustomSpacing(9, after: translationDivider)
        body.setCustomSpacing(3, after: targetHeader)
        body.setCustomSpacing(isWord ? 8 : 0, after: outputHost)
        body.setCustomSpacing(13, after: dictionaryScroll)
        setSpeaking(nil)
        refreshThemeAppearance()
    }

    func display(dictionary: EnglishDictionary?) {
        if let phonetics = dictionary?.displayPronunciation {
            accentLabel.stringValue = phonetics.region == "美" ? L10n.text("US", "美") : (phonetics.region == "英" ? L10n.text("UK", "英") : phonetics.region)
            accentLabel.isHidden = phonetics.region.isEmpty
            sourceLabel.stringValue = "/\(phonetics.text)/"
            sourceSpeechLanguageIdentifier = phonetics.voice
        } else {
            sourceLabel.stringValue = L10n.text("English", "英文")
            accentLabel.isHidden = true
            sourceSpeechLanguageIdentifier = "en-US"
        }
        wordClass = dictionary?.partOfSpeech
        renderOutput()
        dictionaryText.string = dictionary?.summary ?? L10n.text("No entry found. Check enabled dictionaries in Dictionary.", "未找到词条，可在系统词典中检查已启用的词典。")
        dictionaryText.toolTip = dictionary?.definition
        dictionaryText.scrollToBeginningOfDocument(nil)
        setSpeaking(nil)
    }

    func display(_ translation: SelectionTranslation) {
        retryButton.isHidden = true
        addButton.isEnabled = false
        copyButton.isEnabled = false
        targetSpeechButton.isEnabled = false
        showStatus("")
        addButton.title = translation.addedGroupID == nil ? L10n.text("Annotate", "加入批注") : L10n.text("Annotated", "已加入批注")
        addButton.setAccessibilityLabel(addButton.title)
        addButton.image = NSImage(systemSymbolName: translation.addedGroupID == nil ? "highlighter" : "checkmark",
                                  accessibilityDescription: addButton.title)
        hasResult = false
        switch translation.state {
        case .translating: resultText = L10n.text("Translating…", "正在翻译…")
        case let .translated(text):
            resultText = text
            hasResult = true
            addButton.isEnabled = translation.addedGroupID == nil
            copyButton.isEnabled = true
            targetSpeechButton.isEnabled = true
        case let .failed(message):
            resultText = message
            retryButton.isHidden = translation.request.sourceLanguage == nil
        case .cancelled: break
        }
        renderOutput()
        if !isWord { output.scrollToBeginningOfDocument(nil) }
        refreshThemeAppearance()
    }

    /// Word class and translation share one TextKit line, including its typographic baseline.
    private func renderOutput() {
        let prefix = isWord && hasResult ? wordClass.map { $0 + "\t" } ?? "" : ""
        output.string = prefix + resultText
        styleOutput()
    }

    private func styleOutput() {
        guard let storage = output.textStorage else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = isWord ? 22 : 28
        paragraph.maximumLineHeight = isWord ? 22 : 28
        let font = NSFont.systemFont(ofSize: 16)
        let wordClassFont = NSFont(name: "Georgia-Italic", size: 13)!
        let prefix = isWord && hasResult ? wordClass.map { $0 + "\t" } ?? "" : ""
        if !prefix.isEmpty {
            let width = (wordClass! as NSString).size(withAttributes: [.font: wordClassFont]).width + 10
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: width)]
            paragraph.headIndent = width
        }
        storage.setAttributes([
            .font: font, .foregroundColor: NightModeStyle.primaryTextColor, .paragraphStyle: paragraph,
        ], range: NSRange(location: 0, length: storage.length))
        if !prefix.isEmpty, storage.string.hasPrefix(prefix) {
            storage.addAttributes([
                .font: wordClassFont, .foregroundColor: NightModeStyle.secondaryTextColor,
            ], range: NSRange(location: 0, length: (prefix as NSString).length))
        }
    }

    func showStatus(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.toolTip = message.isEmpty ? nil : message
        statusLabel.isHidden = message.isEmpty
        stack.arrangedSubviews.last?.isHidden = message.isEmpty
    }

    func setSpeaking(_ button: NSButton?) {
        for control in [sourceSpeechButton, targetSpeechButton] {
            let speaking = control === button
            let accent = sourceSpeechLanguageIdentifier == "en-GB" ? L10n.text("British", "英式") : L10n.text("American", "美式")
            let sourceTitle = isWord ? L10n.text("Read word aloud (\(accent))", "朗读单词（\(accent)）") : L10n.text("Read original aloud", "朗读原文")
            let label = speaking ? L10n.text("Stop reading", "停止朗读") : (control === sourceSpeechButton ? sourceTitle : L10n.text("Read translation aloud", "朗读译文"))
            control.image = NSImage(systemSymbolName: speaking ? "stop.fill" : "speaker.wave.2", accessibilityDescription: label)
            control.toolTip = label
            control.setAccessibilityLabel(label)
        }
    }

    func fittedHeight() -> CGFloat {
        measure(sourceText, scroll: sourceScroll, height: sourceHeight, maximum: 100, width: Self.width - 32)
        measure(output, scroll: outputScroll, height: outputHeight,
                maximum: isWord ? .greatestFiniteMagnitude : 160, width: Self.width - 32)
        measure(dictionaryText, scroll: dictionaryScroll, height: dictionaryHeight, maximum: 43, width: Self.width - 32)
        layoutSubtreeIfNeeded()
        return ceil(stack.fittingSize.height)
    }

    private func measure(_ text: NSTextView, scroll: NSScrollView, height: NSLayoutConstraint,
                         maximum: CGFloat, width: CGFloat) {
        guard !scroll.isHidden, let container = text.textContainer, let layout = text.layoutManager else { return }
        text.setFrameSize(NSSize(width: width, height: 20))
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let measured = max(20, ceil(layout.usedRect(for: container).height))
        height.constant = min(measured, maximum)
        text.setFrameSize(NSSize(width: width, height: measured))
        if text === output, isWord { text.setFrameOrigin(.zero) }
    }

    func refreshThemeAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let primary = NightModeStyle.primaryTextColor
            let secondary = NightModeStyle.secondaryTextColor
            let background = NightModeStyle.paneBackgroundColor
            let accent = annotationAccent(on: background, text: primary)
            layer?.backgroundColor = background.cgColor
            layer?.borderColor = secondary.withAlphaComponent(0.16).cgColor
            for divider in [footerDivider, translationDivider] {
                divider.layer?.backgroundColor = secondary.withAlphaComponent(0.16).cgColor
            }
            wordLabel.textColor = primary
            kindIcon.contentTintColor = secondary
            for label in [kindLabel, sourceLabel, accentLabel, targetLabel, statusLabel] {
                label.textColor = secondary
            }
            for text in [sourceText, output, dictionaryText] {
                let color = text === dictionaryText ? secondary : primary
                text.textColor = color
                text.insertionPointColor = color
                text.selectedTextAttributes = [
                    .foregroundColor: primary,
                    .backgroundColor: NightModeStyle.selectedChromeBackgroundColor,
                ]
            }
            styleOutput()
            for label in [wordLabel, sourceLabel] {
                if let editor = label.currentEditor() as? NSTextView {
                    editor.textColor = label.textColor
                    editor.selectedTextAttributes = output.selectedTextAttributes
                }
            }
            for button in [reverseButton, closeButton, sourceSpeechButton, targetSpeechButton,
                           copyButton, addButton, retryButton, dictionaryButton] {
                let color = button === addButton ? accent : secondary
                button.contentTintColor = color
                button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                    .font: button.font!, .foregroundColor: color,
                ])
            }
        }
    }

    private func annotationAccent(on background: NSColor, text: NSColor) -> NSColor {
        let pink = NightModeStyle.highlightColor(for: .pink, appearance: effectiveAppearance).withAlphaComponent(1)
        let mixed = pink.blended(withFraction: 0.5, of: text)!
        let foreground = ThemeHexColor(color: mixed)!.components
        let surface = ThemeHexColor(color: background)!.components
        let contrast = (max(foreground.luminance, surface.luminance) + 0.05)
            / (min(foreground.luminance, surface.luminance) + 0.05)
        return contrast >= 4.5 ? mixed : text
    }
}
