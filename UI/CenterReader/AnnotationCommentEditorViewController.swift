import AppKit

/// Lightweight popover editor for highlight comments, shown next to the reader highlight.
final class AnnotationCommentEditorViewController: NSViewController {
    private static let contentWidth: CGFloat = 300
    private static let editorHeight: CGFloat = 88

    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let colorBar = NSView()
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let editorScrollView = NSScrollView()
    private let textView = AnnotationCommentEditorTextView()
    private let shortcutLabel = NSTextField(labelWithString: "⌘↩ Save  ·  Esc Cancel")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private let initialComment: String
    private let snippet: String
    private let color: HighlightColor

    init(group: DocumentHighlightGroup) {
        self.initialComment = group.comment
        self.snippet = group.snippet
        self.color = group.color
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 160))
        container.wantsLayer = true

        colorBar.wantsLayer = true
        colorBar.translatesAutoresizingMaskIntoConstraints = false

        snippetLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        snippetLabel.maximumNumberOfLines = 2
        snippetLabel.lineBreakMode = .byWordWrapping
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 12)
        textView.backgroundColor = .clear
        textView.string = initialComment
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.onCommit = { [weak self] in self?.commit() }
        textView.onCancel = { [weak self] in self?.cancel() }

        editorScrollView.drawsBackground = true
        editorScrollView.borderType = .noBorder
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.hasVerticalScroller = true
        editorScrollView.autohidesScrollers = true
        editorScrollView.documentView = textView
        editorScrollView.wantsLayer = true
        editorScrollView.layer?.cornerRadius = 6
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.font = .systemFont(ofSize: 9.5)
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        saveButton.bezelStyle = .recessed
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        saveButton.target = self
        saveButton.action = #selector(handleSave(_:))
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(colorBar)
        container.addSubview(snippetLabel)
        container.addSubview(editorScrollView)
        container.addSubview(shortcutLabel)
        container.addSubview(saveButton)

        NSLayoutConstraint.activate([
            colorBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            colorBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            colorBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            colorBar.widthAnchor.constraint(equalToConstant: 3),

            snippetLabel.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 10),
            snippetLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            snippetLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            editorScrollView.leadingAnchor.constraint(equalTo: snippetLabel.leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: snippetLabel.trailingAnchor),
            editorScrollView.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 8),
            editorScrollView.heightAnchor.constraint(equalToConstant: Self.editorHeight),

            shortcutLabel.leadingAnchor.constraint(equalTo: snippetLabel.leadingAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: editorScrollView.bottomAnchor, constant: 8),
            shortcutLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            saveButton.trailingAnchor.constraint(equalTo: snippetLabel.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: shortcutLabel.centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -6),

            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])

        view = container
        applyColors()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    @objc
    private func handleSave(_ sender: Any?) {
        commit()
    }

    private func commit() {
        onSave?(textView.string)
    }

    private func cancel() {
        onCancel?()
    }

    private func applyColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.cgColor
            colorBar.layer?.backgroundColor = color.nsColor.cgColor
            snippetLabel.textColor = NightModeStyle.primaryTextColor
            editorScrollView.backgroundColor = NightModeStyle.primaryTextColor.withAlphaComponent(0.04)
            textView.textColor = NightModeStyle.primaryTextColor
            textView.insertionPointColor = NightModeStyle.primaryTextColor
            shortcutLabel.textColor = NightModeStyle.tertiaryTextColor
        }
    }
}

private final class AnnotationCommentEditorTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return
        }
        if modifiers.isEmpty, event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}
