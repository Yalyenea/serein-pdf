import AppKit

class SidebarMaterialView: NSVisualEffectView {
    private let tintView = NSView()

    var tintAlpha: CGFloat {
        tintView.layer?.backgroundColor?.alpha ?? 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTint(opacity: CGFloat) {
        let clampedOpacity = min(max(opacity, 0), 1)
        tintView.layer?.backgroundColor = PlaceholderViewController.paneBackgroundColor(
            opacity: clampedOpacity
        ).cgColor
    }

    private func configureMaterial() {
        material = .sidebar
        blendingMode = .behindWindow
        state = .active
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
    }
}
