import AppKit

final class AnnotationPreviewView: NSView {
    static let contentWidth: CGFloat = 360
    static let textInset: CGFloat = 14
    static let textWidth: CGFloat = contentWidth - 27

    var onPress: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private let colorBar = NSView()
    private let metadataLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let commentLabel = NSTextField(wrappingLabelWithString: "")
    private var highlightColor: HighlightColor = .default
    private var editorView: NSView?
    private var editorHeight: CGFloat = 0
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        colorBar.wantsLayer = true

        metadataLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1

        snippetLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        snippetLabel.maximumNumberOfLines = 3
        snippetLabel.lineBreakMode = .byWordWrapping
        snippetLabel.cell?.wraps = true
        snippetLabel.cell?.usesSingleLineMode = false

        commentLabel.font = .systemFont(ofSize: 11.5)
        commentLabel.maximumNumberOfLines = 5
        commentLabel.lineBreakMode = .byWordWrapping
        commentLabel.cell?.wraps = true
        commentLabel.cell?.usesSingleLineMode = false

        addSubview(colorBar)
        addSubview(metadataLabel)
        addSubview(snippetLabel)
        addSubview(commentLabel)
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return editorView == nil ? self : hit
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if editorView == nil { onPress?() }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    func setEditorView(_ editorView: NSView?, height: CGFloat) {
        if self.editorView !== editorView {
            self.editorView?.removeFromSuperview()
            self.editorView = editorView
            if let editorView { addSubview(editorView) }
        }
        editorHeight = height
        commentLabel.isHidden = editorView != nil
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    /// Returns `false` when the group has no comment and should not show a hover card.
    @discardableResult
    func configure(with group: DocumentHighlightGroup) -> Bool {
        let comment = group.normalizedComment
        let page = "Page \(group.pageIndex + 1)"
        if let createdAt = group.createdAt {
            metadataLabel.stringValue = "\(page) · \(createdAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            metadataLabel.stringValue = page
        }
        snippetLabel.stringValue = group.snippet
        commentLabel.stringValue = comment
        highlightColor = group.color
        refreshColors()
        return comment.isEmpty == false
    }

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let width = min(max(maxWidth, 1), Self.contentWidth)
        let textWidth = max(width - 27, 1)
        let metadataHeight: CGFloat = 14
        let snippetHeight = measuredHeight(of: snippetLabel, width: textWidth)
        let commentHeight = editorView == nil ? measuredHeight(of: commentLabel, width: textWidth) : editorHeight
        let bottomInset: CGFloat = editorView == nil ? 11 : 6
        return NSSize(width: width, height: 10 + metadataHeight + 5 + snippetHeight + 7 + commentHeight + bottomInset)
    }

    func preferredSize(editorHeight: CGFloat) -> NSSize {
        let snippetHeight = measuredHeight(of: snippetLabel, width: Self.textWidth)
        return NSSize(width: Self.contentWidth, height: 10 + 14 + 5 + snippetHeight + 7 + editorHeight + 6)
    }

    override func layout() {
        super.layout()
        colorBar.frame = NSRect(x: 0, y: 0, width: 3, height: bounds.height)

        let x = Self.textInset
        let width = max(bounds.width - x - 13, 1)
        var top = bounds.height - 10

        metadataLabel.frame = NSRect(x: x, y: top - 14, width: width, height: 14)
        top -= 19

        let snippetHeight = measuredHeight(of: snippetLabel, width: width)
        snippetLabel.frame = NSRect(x: x, y: top - snippetHeight, width: width, height: snippetHeight)
        top -= snippetHeight + 7

        let commentHeight = measuredHeight(of: commentLabel, width: width)
        commentLabel.frame = NSRect(x: x, y: top - commentHeight, width: width, height: commentHeight)
        editorView?.frame = NSRect(x: x, y: top - editorHeight, width: width, height: editorHeight)
    }

    private func measuredHeight(of label: NSTextField, width: CGFloat) -> CGFloat {
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        return ceil(label.cell!.cellSize(forBounds: bounds).height)
    }

    func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            colorBar.layer?.backgroundColor = NightModeStyle.highlightColor(for: highlightColor, appearance: effectiveAppearance).cgColor
            layer?.backgroundColor = NightModeStyle.paneBackgroundColor.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NightModeStyle.secondaryTextColor.withAlphaComponent(0.16).cgColor
            metadataLabel.textColor = NightModeStyle.secondaryTextColor
            snippetLabel.textColor = NightModeStyle.primaryTextColor
            commentLabel.textColor = NightModeStyle.primaryTextColor
        }
    }
}
