import AppKit

final class AnnotationPreviewView: NSView {
    private let colorBar = NSView()
    private let metadataLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let commentLabel = NSTextField(wrappingLabelWithString: "")
    private var highlightColor: HighlightColor = .default

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 8
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
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    /// Returns `false` when the group has no comment and should not show a hover card.
    @discardableResult
    func configure(with group: DocumentHighlightGroup) -> Bool {
        let comment = group.normalizedComment
        guard comment.isEmpty == false else { return false }

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
        return true
    }

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let width = min(max(maxWidth, 1), 360)
        let textWidth = max(width - 27, 1)
        let metadataHeight: CGFloat = 14
        let snippetHeight = measuredHeight(
            snippetLabel.stringValue,
            font: snippetLabel.font,
            width: textWidth,
            maximumLines: 3
        )
        let commentHeight = measuredHeight(
            commentLabel.stringValue,
            font: commentLabel.font,
            width: textWidth,
            maximumLines: 5
        )
        return NSSize(width: width, height: 10 + metadataHeight + 5 + snippetHeight + 7 + commentHeight + 11)
    }

    override func layout() {
        super.layout()
        colorBar.frame = NSRect(x: 0, y: 0, width: 3, height: bounds.height)

        let x: CGFloat = 14
        let width = max(bounds.width - x - 13, 1)
        var top = bounds.height - 10

        metadataLabel.frame = NSRect(x: x, y: top - 14, width: width, height: 14)
        top -= 19

        let snippetHeight = measuredHeight(
            snippetLabel.stringValue,
            font: snippetLabel.font,
            width: width,
            maximumLines: 3
        )
        snippetLabel.frame = NSRect(x: x, y: top - snippetHeight, width: width, height: snippetHeight)
        top -= snippetHeight + 7

        let commentHeight = measuredHeight(
            commentLabel.stringValue,
            font: commentLabel.font,
            width: width,
            maximumLines: 5
        )
        commentLabel.frame = NSRect(x: x, y: top - commentHeight, width: width, height: commentHeight)
    }

    private func measuredHeight(
        _ text: String,
        font: NSFont?,
        width: CGFloat,
        maximumLines: Int
    ) -> CGFloat {
        guard text.isEmpty == false, let font else { return 14 }
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return min(ceil(bounds.height), lineHeight * CGFloat(maximumLines))
    }

    func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            colorBar.layer?.backgroundColor = NightModeStyle.highlightColor(for: highlightColor, appearance: effectiveAppearance).cgColor
            layer?.backgroundColor = NightModeStyle.paneBackgroundColor.withAlphaComponent(0.98).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NightModeStyle.secondaryTextColor.withAlphaComponent(0.16).cgColor
            metadataLabel.textColor = NightModeStyle.secondaryTextColor
            snippetLabel.textColor = NightModeStyle.primaryTextColor
            commentLabel.textColor = NightModeStyle.primaryTextColor
        }
    }
}
