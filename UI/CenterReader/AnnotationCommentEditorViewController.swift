import AppKit

/// Compact editor for highlight comments, shown next to the reader highlight.
final class AnnotationCommentEditorViewController: NSViewController, NSTextViewDelegate {
    private static let contentWidth: CGFloat = 300
    private static let minimumEditorHeight: CGFloat = 54
    private static let maximumEditorHeight: CGFloat = 180

    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onContentSizeChanged: ((NSSize) -> Void)?

    private let colorBar = NSView()
    private let editorScrollView = NSScrollView()
    private let textView = AnnotationCommentEditorTextView()
    private let shortcutLabel = NSTextField(labelWithString: "⌘↩ · Esc")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var editorHeightConstraint: NSLayoutConstraint!

    private let initialComment: String
    private let color: HighlightColor

    init(group: DocumentHighlightGroup) {
        self.initialComment = group.comment
        self.color = group.color
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 86))
        container.wantsLayer = true

        colorBar.wantsLayer = true
        colorBar.translatesAutoresizingMaskIntoConstraints = false

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
        textView.drawsBackground = false
        textView.delegate = self
        textView.string = initialComment
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.frame = NSRect(x: 0, y: 0, width: Self.contentWidth - 35, height: Self.minimumEditorHeight)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: Self.contentWidth - 35, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.onCommit = { [weak self] in self?.commit() }
        textView.onCancel = { [weak self] in self?.cancel() }

        editorScrollView.drawsBackground = false
        editorScrollView.borderType = .noBorder
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.hasVerticalScroller = true
        editorScrollView.autohidesScrollers = true
        editorScrollView.scrollerStyle = .overlay
        editorScrollView.horizontalScrollElasticity = .none
        editorScrollView.documentView = textView
        editorScrollView.wantsLayer = true
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.font = .systemFont(ofSize: 9.5)
        shortcutLabel.toolTip = "⌘↩ Save · Esc Cancel"
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        saveButton.bezelStyle = .recessed
        saveButton.isBordered = false
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        saveButton.target = self
        saveButton.action = #selector(handleSave(_:))
        saveButton.toolTip = "Save comment (⌘↩)"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(colorBar)
        container.addSubview(editorScrollView)
        container.addSubview(shortcutLabel)
        container.addSubview(saveButton)

        editorHeightConstraint = editorScrollView.heightAnchor.constraint(equalToConstant: Self.minimumEditorHeight)
        NSLayoutConstraint.activate([
            colorBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            colorBar.topAnchor.constraint(equalTo: editorScrollView.topAnchor),
            colorBar.bottomAnchor.constraint(equalTo: editorScrollView.bottomAnchor),
            colorBar.widthAnchor.constraint(equalToConstant: 3),

            editorScrollView.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 10),
            editorScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            editorScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            editorHeightConstraint,

            shortcutLabel.leadingAnchor.constraint(equalTo: editorScrollView.leadingAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: editorScrollView.bottomAnchor, constant: 6),
            shortcutLabel.heightAnchor.constraint(equalToConstant: 12),
            shortcutLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            saveButton.trailingAnchor.constraint(equalTo: editorScrollView.trailingAnchor),
            saveButton.firstBaselineAnchor.constraint(equalTo: shortcutLabel.firstBaselineAnchor),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -6),

            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])

        view = container
        refreshColors()
        updateEditorHeight()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshColors()
        view.window?.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        updateEditorHeight()
    }

    private func updateEditorHeight() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = ceil(layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2)
        let editorHeight = min(max(textHeight, Self.minimumEditorHeight), Self.maximumEditorHeight)
        editorHeightConstraint.constant = editorHeight
        preferredContentSize = NSSize(width: Self.contentWidth, height: editorHeight + 32)
        onContentSizeChanged?(preferredContentSize)
        view.setFrameSize(preferredContentSize)
        view.layoutSubtreeIfNeeded()
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

    func refreshColors() {
        guard isViewLoaded else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NightModeStyle.paneBackgroundColor.cgColor
            colorBar.layer?.backgroundColor = NightModeStyle.highlightColor(for: color, appearance: view.effectiveAppearance).cgColor
            textView.textColor = NightModeStyle.primaryTextColor
            textView.insertionPointColor = NightModeStyle.primaryTextColor
            shortcutLabel.textColor = NightModeStyle.tertiaryTextColor
            saveButton.contentTintColor = NightModeStyle.primaryTextColor
        }
    }
}

final class AnnotationCommentPanel: NSPanel, NSWindowDelegate {
    let editor: AnnotationCommentEditorViewController
    private weak var anchorView: NSView?
    private var anchorRect = NSRect.zero

    init(editor: AnnotationCommentEditorViewController) {
        self.editor = editor
        editor.loadViewIfNeeded()
        super.init(
            contentRect: NSRect(origin: .zero, size: editor.preferredContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isRestorable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        collectionBehavior = .fullScreenAuxiliary
        contentViewController = editor
        editor.view.layer?.cornerRadius = 6
        editor.view.layer?.masksToBounds = true
        editor.onContentSizeChanged = { [weak self] _ in
            self?.positionPanel()
        }
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(relativeTo rect: NSRect, of hostView: NSView) {
        guard let owner = hostView.window else { return }
        anchorView = hostView
        anchorRect = rect
        refreshThemeAppearance()
        positionPanel()
        owner.addChildWindow(self, ordered: .above)
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: owner
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification, object: NSApp
        )
        makeKeyAndOrderFront(nil)
    }

    func refreshThemeAppearance() {
        appearance = anchorView?.effectiveAppearance
        editor.refreshColors()
    }

    private func positionPanel() {
        guard let hostView = anchorView, let owner = hostView.window, let screen = owner.screen else { return }
        let anchor = owner.convertToScreen(hostView.convert(anchorRect, to: nil))
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = editor.preferredContentSize
        let x = min(max(anchor.midX - size.width / 2, available.minX), available.maxX - size.width)
        let y = anchor.maxY + 6 + size.height <= available.maxY
            ? anchor.maxY + 6
            : anchor.minY - 6 - size.height
        setFrame(NSRect(
            x: x, y: min(max(y, available.minY), available.maxY - size.height),
            width: size.width, height: size.height
        ), display: true)
        invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        if isVisible { close() }
    }

    @objc private func hostWindowWillClose(_ notification: Notification) {
        parent?.removeChildWindow(self)
        close()
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        close()
    }

    override func close() {
        let owner = parent
        let restoreFocus = isKeyWindow
        delegate = nil
        editor.onContentSizeChanged = nil
        NotificationCenter.default.removeObserver(self)
        owner?.removeChildWindow(self)
        super.close()
        if restoreFocus, owner?.isVisible == true { owner?.makeKey() }
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
