import AppKit
import QuartzCore

final class ReadingFocusOverlayView: NSView {
    static let focusCornerRadius: CGFloat = 6

    private(set) var focusLocation: NSPoint?
    private(set) var focusBandRect: NSRect?
    private(set) var isFocusEnabled = false
    private(set) var shadeAlpha: CGFloat = 0.16
    private(set) var edgeShadowOpacity: Float = 0.18
    private(set) var settings: ReadingFocusSettings = .default
    var pageBoundsProvider: ((NSPoint) -> NSRect?)?

    private let shadeLayer = CAShapeLayer()
    private let focusEdgeLayer = CAShapeLayer()
    private var focusTrackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isFocusPinned = false
    nonisolated(unsafe) private var pointerMotionMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        alphaValue = 0
        setAccessibilityElement(false)
        configureShadeLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let focusTrackingArea {
            removeTrackingArea(focusTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        focusTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMotionMonitor {
            NSEvent.removeMonitor(pointerMotionMonitor)
            self.pointerMotionMonitor = nil
        }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            pointerMotionMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDragged, .scrollWheel]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handlePointerMotion(event)
                }
                return event
            }
        }
    }

    override func layout() {
        super.layout()
        resolveFocusRect()
        updateShadeLayers()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateFocus(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateFocus(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        guard isFocusPinned == false else { return }
        clearFocus(animated: true)
    }

    func setFocusEnabled(_ enabled: Bool) {
        guard enabled != isFocusEnabled else { return }
        isFocusEnabled = enabled
        if enabled == false {
            isPointerInside = false
            clearFocus(animated: false)
        }
    }

    func setFocusPinned(_ pinned: Bool, at point: NSPoint? = nil) {
        isFocusPinned = pinned
        if let point {
            updateFocus(at: point)
        } else if pinned == false, isPointerInside == false {
            clearFocus(animated: false)
        }
    }

    func setNightModeEnabled(_ isEnabled: Bool) {
        let nextShadeAlpha: CGFloat = isEnabled ? 0.24 : 0.16
        let nextEdgeShadowOpacity: Float = isEnabled ? 0.26 : 0.18
        guard nextShadeAlpha != shadeAlpha
                || nextEdgeShadowOpacity != edgeShadowOpacity else {
            return
        }
        shadeAlpha = nextShadeAlpha
        edgeShadowOpacity = nextEdgeShadowOpacity
        updateShadeColors()
    }

    func setSettings(_ settings: ReadingFocusSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        refreshFocusGeometry()
    }

    func refreshFocusGeometry() {
        resolveFocusRect()
        updateShadeLayers()
    }

    func updateFocus(at point: NSPoint) {
        guard isFocusEnabled,
              bounds.contains(point),
              let pageBounds = pageBoundsProvider?(point),
              let focusRect = Self.focusRect(
                at: point,
                in: pageBounds,
                clippedTo: bounds,
                settings: settings
              ) else {
            clearFocus(animated: false)
            return
        }
        focusLocation = point
        focusBandRect = focusRect
        alphaValue = 1
        updateShadeLayers()
    }

    func clearFocus(animated: Bool) {
        guard focusLocation != nil else { return }
        guard animated else {
            focusLocation = nil
            focusBandRect = nil
            alphaValue = 0
            updateShadeLayers()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPointerInside == false else { return }
                self.focusLocation = nil
                self.focusBandRect = nil
                self.updateShadeLayers()
            }
        }
    }

    func handlePointerDrag(at point: NSPoint) {
        guard isFocusEnabled else { return }
        if bounds.contains(point) {
            isPointerInside = true
            updateFocus(at: point)
        } else {
            isPointerInside = false
            clearFocus(animated: false)
        }
    }

    deinit {
        if let pointerMotionMonitor {
            NSEvent.removeMonitor(pointerMotionMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleWindowDidResignKey(_ notification: Notification) {
        isPointerInside = false
        guard isFocusPinned == false else { return }
        clearFocus(animated: false)
    }

    private func handlePointerMotion(_ event: NSEvent) {
        guard event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.type == .scrollWheel {
            DispatchQueue.main.async { [weak self] in
                self?.handlePointerDrag(at: point)
            }
        } else {
            handlePointerDrag(at: point)
        }
    }

    private func configureShadeLayers() {
        shadeLayer.fillRule = .evenOdd
        shadeLayer.isHidden = true
        shadeLayer.allowsEdgeAntialiasing = true
        layer?.addSublayer(shadeLayer)

        focusEdgeLayer.fillColor = NSColor.clear.cgColor
        focusEdgeLayer.lineWidth = 1
        focusEdgeLayer.lineJoin = .round
        focusEdgeLayer.shadowColor = NSColor.black.cgColor
        focusEdgeLayer.shadowOffset = .zero
        focusEdgeLayer.shadowRadius = 6
        focusEdgeLayer.isHidden = true
        focusEdgeLayer.allowsEdgeAntialiasing = true
        layer?.addSublayer(focusEdgeLayer)

        updateShadeColors()
    }

    private func updateShadeColors() {
        shadeLayer.fillColor = NSColor.black.withAlphaComponent(shadeAlpha).cgColor
        focusEdgeLayer.strokeColor = NSColor.black
            .withAlphaComponent(shadeAlpha * 0.75)
            .cgColor
        focusEdgeLayer.shadowOpacity = edgeShadowOpacity
    }

    private func updateShadeLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard isFocusEnabled, let focusBandRect else {
            shadeLayer.isHidden = true
            shadeLayer.path = nil
            focusEdgeLayer.isHidden = true
            focusEdgeLayer.path = nil
            return
        }

        let cornerRadius = min(
            Self.focusCornerRadius,
            focusBandRect.width / 2,
            focusBandRect.height / 2
        )
        let focusPath = CGPath(
            roundedRect: focusBandRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let shadePath = CGMutablePath()
        shadePath.addRect(bounds)
        shadePath.addPath(focusPath)

        shadeLayer.frame = bounds
        shadeLayer.path = shadePath
        shadeLayer.isHidden = false

        focusEdgeLayer.frame = bounds
        focusEdgeLayer.path = focusPath
        focusEdgeLayer.isHidden = false
    }

    private func resolveFocusRect() {
        guard let focusLocation,
              let pageBounds = pageBoundsProvider?(focusLocation) else {
            focusBandRect = nil
            return
        }
        focusBandRect = Self.focusRect(
            at: focusLocation,
            in: pageBounds,
            clippedTo: bounds,
            settings: settings
        )
    }

    static func focusRect(
        at point: NSPoint,
        in pageBounds: NSRect,
        clippedTo viewportBounds: NSRect,
        settings: ReadingFocusSettings
    ) -> NSRect? {
        guard pageBounds.width > 0,
              pageBounds.height > 0,
              pageBounds.contains(point) else { return nil }

        let horizontalRange: (minX: CGFloat, width: CGFloat)
        switch settings.widthMode {
        case .page:
            horizontalRange = (pageBounds.minX, pageBounds.width)
        case .column:
            let width = pageBounds.width / 2
            horizontalRange = (
                point.x < pageBounds.midX ? pageBounds.minX : pageBounds.midX,
                width
            )
        case .custom:
            let width = pageBounds.width * settings.customWidthRatio
            let minX = min(
                max(point.x - width / 2, pageBounds.minX),
                pageBounds.maxX - width
            )
            horizontalRange = (minX, width)
        }

        let focusRect = NSRect(
            x: horizontalRange.minX,
            y: point.y - settings.height / 2,
            width: horizontalRange.width,
            height: settings.height
        )
        let clippedRect = focusRect.intersection(pageBounds).intersection(viewportBounds)
        return clippedRect.isNull ? nil : clippedRect
    }

}
