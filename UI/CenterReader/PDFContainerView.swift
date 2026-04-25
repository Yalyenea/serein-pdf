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
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor = isEnabled ? NightModeStyle.pageBackgroundColor : NightModeStyle.readerBackdropColor
            layer?.backgroundColor = backgroundColor.cgColor
        }
    }
}
