import AppKit

final class PDFContainerView: NSView {
    let readingFocusOverlay = ReadingFocusOverlayView()
    let presentationOverlay = PresentationAnnotationOverlayView()
    let pageCounterView = ReaderPageCounterView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The parent refresh runs before this child inherits its new appearance.
        setNightModeEnabled(effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
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
        pageCounterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageCounterView)
        NSLayoutConstraint.activate([
            pageCounterView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pageCounterView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    func setReadingFocusEnabled(_ isEnabled: Bool) {
        readingFocusOverlay.setFocusEnabled(isEnabled)
    }

    func setReadingFocusSettings(_ settings: ReadingFocusSettings) {
        readingFocusOverlay.setSettings(settings)
    }

    func setNightModeEnabled(_ isEnabled: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor = NightModeStyle.readerBackdropColor
            layer?.backgroundColor = backgroundColor.cgColor
        }
        readingFocusOverlay.setNightModeEnabled(isEnabled)
        pageCounterView.refreshThemeAppearance()
    }
}
