import AppKit

private final class SidebarBackgroundView: NSView {
    var allowsWindowDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        allowsWindowDrag
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsWindowDrag,
              event.clickCount == 1,
              let window,
              window.isMovable,
              window.styleMask.contains(.fullScreen) == false else {
            super.mouseDown(with: event)
            return
        }

        window.performDrag(with: event)
    }
}

class SidebarMaterialView: NSVisualEffectView {
    private let tintView = SidebarBackgroundView()

    var tintAlpha: CGFloat {
        tintView.layer?.backgroundColor?.alpha ?? 0
    }

    var allowsWindowDragFromBackground: Bool {
        get { tintView.allowsWindowDrag }
        set { tintView.allowsWindowDrag = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySurface()
    }

    /// Paints a solid reader-matched surface so left/center/right read as one plane.
    func applySurface() {
        // contentBackground + full opaque fill suppresses sidebar vibrancy seams.
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let surface = NightModeStyle.readerBackdropColor
            layer?.backgroundColor = surface.cgColor
            tintView.layer?.backgroundColor = surface.cgColor
        }
    }

    private func configureMaterial() {
        wantsLayer = true
        layer?.masksToBounds = true

        tintView.wantsLayer = true
        tintView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tintView, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applySurface()
    }
}

#if DEBUG
extension SidebarMaterialView {
    var testingBackgroundView: NSView {
        tintView
    }
}
#endif
