import AppKit

/// Compact editor for highlight comments, shown next to the reader highlight.
final class AnnotationCommentEditorViewController: NSViewController, NSTextViewDelegate {
    private static let minimumEditorHeight: CGFloat = 20
    private static let maximumEditorHeight: CGFloat = 180
    private static let footerHeight: CGFloat = 18

    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onContentSizeChanged: ((NSSize) -> Void)?

    let cardView = AnnotationPreviewView()
    private(set) var isEditing = true
    private let editorBody = NSView()
    private let editorScrollView = NSScrollView()
    private let textView = AnnotationCommentEditorTextView()
    private let shortcutLabel = NSTextField(labelWithString: "⌘↩")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var editorHeightConstraint: NSLayoutConstraint!

    private let group: DocumentHighlightGroup

    var maximumContentSize: NSSize {
        cardView.preferredSize(editorHeight: Self.maximumEditorHeight + Self.footerHeight)
    }

    init(group: DocumentHighlightGroup) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        cardView.configure(with: group)
        let container = editorBody
        container.frame = NSRect(x: 0, y: 0, width: AnnotationPreviewView.textWidth,
                                 height: Self.minimumEditorHeight + Self.footerHeight)

        textView.isRichText = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 11.5)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.delegate = self
        textView.string = group.comment
        textView.textContainerInset = NSSize(width: 2, height: 0)
        textView.frame = NSRect(x: 0, y: 0, width: AnnotationPreviewView.textWidth, height: Self.minimumEditorHeight)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: AnnotationPreviewView.textWidth - 4, height: CGFloat.greatestFiniteMagnitude)
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
        shortcutLabel.toolTip = "Save comment (⌘↩)"
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        saveButton.bezelStyle = .recessed
        saveButton.isBordered = false
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: 10.5, weight: .medium)
        saveButton.target = self
        saveButton.action = #selector(handleSave(_:))
        saveButton.toolTip = "Save comment (⌘↩)"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(editorScrollView)
        container.addSubview(shortcutLabel)
        container.addSubview(saveButton)

        editorHeightConstraint = editorScrollView.heightAnchor.constraint(equalToConstant: Self.minimumEditorHeight)
        NSLayoutConstraint.activate([
            editorScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorScrollView.topAnchor.constraint(equalTo: container.topAnchor),
            editorHeightConstraint,

            shortcutLabel.trailingAnchor.constraint(equalTo: editorScrollView.trailingAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: editorScrollView.bottomAnchor, constant: 4),
            shortcutLabel.heightAnchor.constraint(equalToConstant: 12),
            shortcutLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),

            saveButton.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -6),
            saveButton.firstBaselineAnchor.constraint(equalTo: shortcutLabel.firstBaselineAnchor),
        ])

        view = cardView
        refreshColors()
        updateEditorHeight()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshColors()
        if isEditing { focusComment() }
    }

    func setEditing(_ editing: Bool) {
        loadViewIfNeeded()
        isEditing = editing
        updateEditorHeight()
    }

    func focusComment() {
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
        cardView.setEditorView(isEditing ? editorBody : nil, height: editorHeight + Self.footerHeight)
        preferredContentSize = cardView.preferredSize(maxWidth: AnnotationPreviewView.contentWidth)
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
            cardView.refreshColors()
            textView.textColor = NightModeStyle.primaryTextColor
            textView.insertionPointColor = NightModeStyle.primaryTextColor
            shortcutLabel.textColor = NightModeStyle.tertiaryTextColor
            saveButton.contentTintColor = NightModeStyle.primaryTextColor
        }
    }
}

final class AnnotationCommentPanel: NSPanel, NSWindowDelegate {
    let editor: AnnotationCommentEditorViewController
    var onHoverChanged: ((Bool) -> Void)?
    var onBeginEditing: (() -> Void)?
    var onClose: (() -> Void)?
    private weak var anchorView: NSView?
    private var anchorRect = NSRect.zero
    private var placement: AnnotationCommentPlacement?
    private var placementAnchor = NSRect.zero
    private var placementAvailable = NSRect.zero

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
        editor.cardView.onPress = { [weak self] in self?.beginEditing() }
        editor.cardView.onHoverChanged = { [weak self] hovered in self?.onHoverChanged?(hovered) }
        delegate = self
    }

    override var canBecomeKey: Bool { editor.isEditing }
    override var canBecomeMain: Bool { false }

    func show(relativeTo rect: NSRect, of hostView: NSView, editing: Bool = true) {
        guard let owner = hostView.window else { return }
        anchorView = hostView
        anchorRect = rect
        editor.setEditing(editing)
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
        if editing {
            makeKeyAndOrderFront(nil)
            editor.focusComment()
        } else {
            orderFront(nil)
        }
    }

    func beginEditing() {
        guard editor.isEditing == false else { return }
        onBeginEditing?()
        editor.setEditing(true)
        makeKeyAndOrderFront(nil)
        editor.focusComment()
    }

    func updateAnchor(_ rect: NSRect) {
        anchorRect = rect
        positionPanel()
    }

    func refreshThemeAppearance() {
        appearance = anchorView?.effectiveAppearance
        editor.refreshColors()
    }

    private func positionPanel() {
        guard let hostView = anchorView, let owner = hostView.window, let screen = owner.screen else { return }
        let anchor = owner.convertToScreen(hostView.convert(anchorRect, to: nil))
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        if placement == nil || placementAnchor != anchor || placementAvailable != available {
            placement = AnnotationCommentPlacement(anchor: anchor, available: available,
                                                   reservedSize: editor.maximumContentSize)
            placementAnchor = anchor
            placementAvailable = available
        }
        var frame = placement!.frame(for: editor.preferredContentSize)
        // Window ordering and resizing round fractional screen origins differently.
        frame.origin.x = frame.origin.x.rounded()
        frame.origin.y = frame.origin.y.rounded()
        setFrame(frame, display: true)
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
        editor.cardView.onPress = nil
        editor.cardView.onHoverChanged = nil
        NotificationCenter.default.removeObserver(self)
        owner?.removeChildWindow(self)
        super.close()
        if restoreFocus, owner?.isVisible == true { owner?.makeKey() }
        let didClose = onClose
        onClose = nil
        didClose?()
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
