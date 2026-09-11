import AppKit

final class PDFContainerView: NSView {
    let readingFocusOverlay = ReadingFocusOverlayView()
    let presentationOverlay = PresentationAnnotationOverlayView()

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
        readingFocusOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(readingFocusOverlay)
        NSLayoutConstraint.activate([
            readingFocusOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            readingFocusOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            readingFocusOverlay.topAnchor.constraint(equalTo: topAnchor),
            readingFocusOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        presentationOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(presentationOverlay)
        NSLayoutConstraint.activate([
            presentationOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            presentationOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            presentationOverlay.topAnchor.constraint(equalTo: topAnchor),
            presentationOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setReadingFocusEnabled(_ isEnabled: Bool) {
        readingFocusOverlay.setFocusEnabled(isEnabled)
    }

    func setReadingFocusSettings(_ settings: ReadingFocusSettings) {
        readingFocusOverlay.setSettings(settings)
    }

    func setNightModeEnabled(_ isEnabled: Bool) {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor = isEnabled ? NightModeStyle.pageBackgroundColor : NightModeStyle.readerBackdropColor
            layer?.backgroundColor = backgroundColor.cgColor
        }
        readingFocusOverlay.setNightModeEnabled(isEnabled)
    }
}
