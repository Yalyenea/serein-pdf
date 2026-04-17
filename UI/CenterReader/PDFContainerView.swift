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
        let night = NSColor(calibratedWhite: 0.07, alpha: 1.0)
        layer?.backgroundColor = (isEnabled ? night : NSColor.white).cgColor
    }
}
