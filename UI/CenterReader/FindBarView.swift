import AppKit

@MainActor
protocol FindBarDelegate: AnyObject {
    func findBar(_ view: FindBarView, didSubmitQuery query: String, scope: SearchScope)
    func findBarRequestsSelectNext(_ view: FindBarView)
    func findBarRequestsSelectPrevious(_ view: FindBarView)
    func findBarRequestsActivateSelection(_ view: FindBarView)
    func findBarRequestsNext(_ view: FindBarView)
    func findBarRequestsPrevious(_ view: FindBarView)
    func findBarRequestsClose(_ view: FindBarView)
}

final class FindBarView: NSView, NSTextFieldDelegate {
    weak var delegate: FindBarDelegate?

    private let queryField = NSTextField()
    private let scopeControl = NSSegmentedControl(labels: ["This Document", "All Open"], trackingMode: .selectOne, target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "↑", target: nil, action: nil)
    private let nextButton = NSButton(title: "↓", target: nil, action: nil)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let divider = NSBox()

    var query: String {
        queryField.stringValue
    }

    var scope: SearchScope {
        scopeControl.selectedSegment == 1 ? .allOpen : .currentDocument
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        queryField.placeholderString = SearchScope.currentDocument.placeholder
        queryField.focusRingType = .none
        queryField.bezelStyle = .roundedBezel
        queryField.delegate = self
        queryField.font = .systemFont(ofSize: 12, weight: .regular)
        queryField.translatesAutoresizingMaskIntoConstraints = false

        scopeControl.segmentStyle = .capsule
        scopeControl.controlSize = .small
        scopeControl.selectedSegment = 0
        scopeControl.target = self
        scopeControl.action = #selector(handleScopeChanged)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        for button in [previousButton, nextButton, closeButton] {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.focusRingType = .none
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.contentTintColor = .secondaryLabelColor
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        previousButton.target = self
        previousButton.action = #selector(handlePrevious)
        nextButton.target = self
        nextButton.action = #selector(handleNext)
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.font = .systemFont(ofSize: 15, weight: .medium)

        divider.boxType = .custom
        divider.isTransparent = false
        divider.fillColor = SplitViewController.dividerBackgroundColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scopeControl)
        addSubview(queryField)
        addSubview(statusLabel)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(closeButton)
        addSubview(divider)

        NSLayoutConstraint.activate([
            scopeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scopeControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            scopeControl.widthAnchor.constraint(equalToConstant: 188),

            queryField.leadingAnchor.constraint(equalTo: scopeControl.trailingAnchor, constant: 8),
            queryField.centerYAnchor.constraint(equalTo: centerYAnchor),
            queryField.widthAnchor.constraint(equalToConstant: 220),

            statusLabel.leadingAnchor.constraint(equalTo: queryField.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            previousButton.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 8),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 22),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 22),

            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])

        setStatus(matchIndex: nil, totalMatches: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focusQueryField() {
        window?.makeFirstResponder(queryField)
        queryField.currentEditor()?.selectAll(nil)
    }

    func setQuery(_ text: String) {
        queryField.stringValue = text
    }

    func setScope(_ scope: SearchScope) {
        scopeControl.selectedSegment = scope == .allOpen ? 1 : 0
        queryField.placeholderString = scope.placeholder
    }

    func setStatus(matchIndex: Int?, totalMatches: Int) {
        if queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusLabel.stringValue = ""
        } else if totalMatches == 0 {
            statusLabel.stringValue = "No matches"
        } else if let index = matchIndex {
            statusLabel.stringValue = "\(index + 1) / \(totalMatches)"
        } else {
            statusLabel.stringValue = "\(totalMatches) matches"
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        statusLabel.stringValue = ""
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            delegate?.findBarRequestsSelectPrevious(self)
            return true
        case #selector(NSResponder.moveDown(_:)):
            delegate?.findBarRequestsSelectNext(self)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            delegate?.findBar(self, didSubmitQuery: queryField.stringValue, scope: scope)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.findBarRequestsClose(self)
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    @objc
    private func handlePrevious() {
        delegate?.findBarRequestsPrevious(self)
    }

    @objc
    private func handleNext() {
        delegate?.findBarRequestsNext(self)
    }

    @objc
    private func handleClose() {
        delegate?.findBarRequestsClose(self)
    }

    @objc
    private func handleScopeChanged() {
        let scope = scope
        queryField.placeholderString = scope.placeholder
        let trimmed = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            statusLabel.stringValue = ""
            return
        }
        delegate?.findBar(self, didSubmitQuery: queryField.stringValue, scope: scope)
    }
}
