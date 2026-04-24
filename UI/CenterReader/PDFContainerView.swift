import AppKit

final class PDFContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embedPDFView(_ view: NSView) {
        addSubview(view)
    }

    func setNightModeEnabled(_ isEnabled: Bool) {
        layer?.backgroundColor = (isEnabled ? NightModeStyle.pageBackgroundColor : NSColor.white).cgColor
    }
}
