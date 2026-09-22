import AppKit

/// A pane-local physical page counter with an inline jump field.
final class ReaderPageCounterView: NSView, NSTextFieldDelegate {
    var onBeginEditing: (() -> Void)?
    var onGoToPage: ((Int) -> Bool)?
    var onReturnFocus: (() -> Void)?

    private let button = NSButton(title: "", target: nil, action: nil)
    private let field = NSTextField(string: "")
    private var pageIndex = 0
    private var pageCount = 0
    private(set) var isEditing = false
    private(set) var displayText = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("readerPageCounter")
        wantsLayer = true
        layer?.cornerRadius = 5
        isHidden = true

        button.isBordered = false
        button.alignment = .center
        button.target = self
        button.action = #selector(beginEditing)
        button.toolTip = "Go to page"
        button.setAccessibilityLabel("Current page. Click to go to a page.")
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .center
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.isHidden = true
        field.setAccessibilityLabel("Page number")

        for control in [button, field] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                control.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        refreshThemeAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let width = NSString(string: displayText).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        ]).width
        return NSSize(width: max(60, ceil(width) + 16), height: 24)
    }

    func update(pageIndex: Int, pageCount: Int, displayMode: ReaderDisplayMode) {
        guard pageCount > 0 else {
            cancelEditing(restoreFocus: false)
            self.pageCount = 0
            isHidden = true
            return
        }
        self.pageIndex = min(max(pageIndex, 0), pageCount - 1)
        self.pageCount = pageCount
        let range = Self.pageRange(pageIndex: self.pageIndex, pageCount: pageCount, displayMode: displayMode)
        let pages = range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
        let text = "\(pages) / \(pageCount)"
        guard displayText != text else { return }
        displayText = text
        button.setAccessibilityValue(displayText)
        field.placeholderString = "1–\(pageCount)"
        field.toolTip = "Enter a page from 1 to \(pageCount). Return to go, Escape to cancel."
        invalidateIntrinsicContentSize()
        refreshThemeAppearance()
    }

    static func pageRange(pageIndex: Int, pageCount: Int, displayMode: ReaderDisplayMode) -> ClosedRange<Int> {
        let index = min(max(pageIndex, 0), max(pageCount - 1, 0))
        guard displayMode.usesTwoUpLayout, pageCount > 1 else { return (index + 1)...(index + 1) }
        if displayMode.usesBookLayout, index == 0 { return 1...1 }
        let lead = displayMode.usesBookLayout ? (index - 1) / 2 * 2 + 1 : index / 2 * 2
        return (lead + 1)...min(lead + 2, pageCount)
    }

    func refreshThemeAppearance() {
        layer?.backgroundColor = NightModeStyle.readerBackdropColor.withAlphaComponent(0.92).cgColor
        field.textColor = NightModeStyle.primaryTextColor
        button.attributedTitle = NSAttributedString(string: displayText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NightModeStyle.secondaryTextColor,
        ])
    }

    @objc func beginEditing() {
        guard pageCount > 0, !isEditing else { return }
        onBeginEditing?()
        isEditing = true
        field.stringValue = "\(pageIndex + 1)"
        button.isHidden = true
        field.isHidden = false
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    @discardableResult
    func submitPageNumber(_ value: String) -> Bool {
        guard isEditing,
              let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...pageCount).contains(number),
              onGoToPage?(number - 1) == true else { return false }
        cancelEditing(restoreFocus: true)
        return true
    }

    func cancelEditing(restoreFocus: Bool = false) {
        guard isEditing else { return }
        isEditing = false
        field.isHidden = true
        button.isHidden = false
        if restoreFocus { onReturnFocus?() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if !submitPageNumber(field.stringValue) {
                NSSound.beep()
                field.selectText(nil)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEditing(restoreFocus: true)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        cancelEditing()
    }
}
