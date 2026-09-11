import AppKit
import PDFKit

/// Presentation marks live in page coordinates and never become PDF annotations.
final class PresentationAnnotationOverlayView: NSView {
    enum Tool: Int { case pointer, pen, laser }

    struct Stroke {
        let page: PDFPage
        var segments: [[NSPoint]]
    }

    struct LaserSample {
        let point: NSPoint
        let time: TimeInterval
    }

    weak var pdfView: PDFView?
    var onInteraction: (() -> Void)?
    private(set) var isPresentationEnabled = false
    private(set) var tool: Tool = .pointer
    private(set) var strokes: [Stroke] = []
    private(set) var laserSamples: [LaserSample] = []
    private(set) var laserLocation: NSPoint?
    private(set) var isToolbarPinned = true
    var isToolbarVisible: Bool { !toolbar.isHidden && !isHiddenOrHasHiddenAncestor }
    var isLaserTimerRunning: Bool { laserTimer?.isValid == true }

    static let laserLifetime: TimeInterval = 0.45
    private let toolbar = NSView()
    private let toolbarPinButton = NSButton()
    private let toolbarRevealButton = NSButton()
    private var isToolbarRevealed = false
    private var buttons: [NSButton] = []
    private var tracking: NSTrackingArea?
    private var activeStrokeIndex: Int?
    private var needsNewSegment = false
    private weak var geometryPage: PDFPage?
    private var pageFrame: NSRect?
    nonisolated(unsafe) private var laserTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
        configureToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        laserTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool { isPresentationEnabled }

    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: (bounds.width - 244) / 2, y: 12, width: 244, height: 44)
        toolbarRevealButton.frame = NSRect(x: bounds.midX - 18, y: 8, width: 36, height: 16)
        refreshGeometry()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey),
                                                  name: NSWindow.didResignKeyNotification, object: window)
        }
        if window == nil {
            clearLaser()
            updateToolbarVisibility(at: nil)
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        endStroke()
        clearLaser()
        updateToolbarVisibility(at: nil)
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                      .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPresentationEnabled, !isHidden else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if !toolbar.isHidden, toolbar.frame.contains(local) {
            return super.hitTest(point)
        }
        if !toolbarRevealButton.isHidden, toolbarRevealButton.frame.contains(local) {
            return toolbarRevealButton
        }
        return tool != .pointer && pageLocation(at: local) != nil ? self : nil
    }

    override func resetCursorRects() {
        guard isPresentationEnabled, tool != .pointer, let pageFrame else { return }
        let page = pageFrame.intersection(bounds)
        let controls = toolbar.isHidden ? toolbarRevealButton : toolbar
        let excluded = controls.isHidden ? NSRect.null : controls.frame.intersection(page)
        if excluded.isNull {
            addCursorRect(page, cursor: .crosshair)
        } else {
            let regions = [
                NSRect(x: page.minX, y: page.minY, width: page.width, height: excluded.minY - page.minY),
                NSRect(x: page.minX, y: excluded.maxY, width: page.width, height: page.maxY - excluded.maxY),
                NSRect(x: page.minX, y: excluded.minY, width: excluded.minX - page.minX, height: excluded.height),
                NSRect(x: excluded.maxX, y: excluded.minY, width: page.maxX - excluded.maxX, height: excluded.height),
            ]
            for region in regions where !region.isEmpty { addCursorRect(region, cursor: .crosshair) }
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyEvent(event) { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        focusInteraction()
        let point = convert(event.locationInWindow, from: nil)
        updateToolbarVisibility(at: point)
        if tool == .pen { beginStroke(at: point) }
        if tool == .laser { updateLaser(at: point) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateToolbarVisibility(at: point)
        if tool == .pen { continueStroke(at: point) }
        if tool == .laser { updateLaser(at: point) }
    }

    override func mouseUp(with event: NSEvent) {
        if tool == .pen {
            continueStroke(at: convert(event.locationInWindow, from: nil))
            endStroke()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateToolbarVisibility(at: point)
        if tool == .laser { updateLaser(at: point) }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        clearLaser()
        updateToolbarVisibility(at: nil)
    }

    override func scrollWheel(with event: NSEvent) {
        pdfView?.documentView?.enclosingScrollView?.scrollWheel(with: event)
    }

    func setPresentationEnabled(_ enabled: Bool) {
        guard enabled != isPresentationEnabled else { return }
        isPresentationEnabled = enabled
        isHidden = !enabled
        isToolbarRevealed = false
        if !enabled { resetDocument() }
        refreshGeometry()
    }

    func resetDocument() {
        endStroke()
        strokes.removeAll()
        isToolbarRevealed = false
        selectTool(.pointer)
        clearLaser()
        refreshGeometry()
    }

    func refreshGeometry() {
        guard isPresentationEnabled else {
            toolbar.isHidden = true
            toolbarRevealButton.isHidden = true
            return
        }
        let page = pdfView?.currentPage
        let nextFrame = page.flatMap { page in
            pdfView.map { convert($0.convert(page.bounds(for: $0.displayBox), from: page), from: $0) }
        }
        if geometryPage !== page || pageFrame != nextFrame || isHiddenOrHasHiddenAncestor {
            endStroke()
            clearLaser()
            window?.invalidateCursorRects(for: self)
        }
        if isHiddenOrHasHiddenAncestor || page == nil { isToolbarRevealed = false }
        geometryPage = page
        pageFrame = nextFrame
        applyToolbarVisibility()
        toolbar.layer?.backgroundColor = NightModeStyle.paneBackgroundColor
            .withAlphaComponent(0.58).cgColor
        toolbar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        toolbarRevealButton.layer?.backgroundColor = NightModeStyle.paneBackgroundColor
            .withAlphaComponent(0.36).cgColor
        updateButtons()
        needsDisplay = true
    }

    func setToolbarPinned(_ pinned: Bool) {
        isToolbarPinned = pinned
        isToolbarRevealed = false
        applyToolbarVisibility()
        updateButtons()
    }

    func updateToolbarVisibility(at point: NSPoint?) {
        if let point, activeStrokeIndex == nil {
            let revealArea = NSRect(x: bounds.midX - 38, y: bounds.minY, width: 76, height: 32)
            isToolbarRevealed = revealArea.contains(point)
                || (isToolbarRevealed && toolbar.frame.insetBy(dx: -8, dy: -8).contains(point))
        } else {
            isToolbarRevealed = false
        }
        applyToolbarVisibility()
    }

    private func applyToolbarVisibility() {
        let available = isPresentationEnabled && pdfView?.currentPage != nil
        let wasHidden = toolbar.isHidden
        toolbar.isHidden = !available || (!isToolbarPinned && !isToolbarRevealed)
        toolbarRevealButton.isHidden = !available || !toolbar.isHidden
        if wasHidden != toolbar.isHidden { window?.invalidateCursorRects(for: self) }
    }

    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isPresentationEnabled,
              pdfView?.currentPage != nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "z" {
            undoCurrentPage()
            return true
        }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 53 {
            guard tool != .pointer else { return false }
            selectTool(.pointer)
            return true
        }
        switch key {
        case "p": selectTool(tool == .pen ? .pointer : .pen)
        case "r": selectTool(tool == .laser ? .pointer : .laser)
        case "v": selectTool(.pointer)
        case "e": clearCurrentPage()
        default: return false
        }
        return true
    }

    func selectTool(_ selected: Tool) {
        guard selected == .pointer || (isPresentationEnabled && pdfView?.currentPage != nil) else { return }
        endStroke()
        tool = selected
        clearLaser()
        updateButtons()
        window?.invalidateCursorRects(for: self)
    }

    func undoCurrentPage() {
        guard let page = pdfView?.currentPage,
              let index = strokes.lastIndex(where: { $0.page === page }) else { return }
        endStroke()
        strokes.remove(at: index)
        refreshGeometry()
    }

    func clearCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        endStroke()
        strokes.removeAll { $0.page === page }
        clearLaser()
        refreshGeometry()
    }

    func pageLocation(at point: NSPoint) -> (page: PDFPage, point: NSPoint)? {
        guard bounds.contains(point), let pdfView,
              (toolbar.isHidden || !toolbar.frame.contains(point)),
              (toolbarRevealButton.isHidden || !toolbarRevealButton.frame.contains(point)) else { return nil }
        let pdfPoint = pdfView.convert(point, from: self)
        guard let page = pdfView.page(for: pdfPoint, nearest: false) else { return nil }
        let pagePoint = pdfView.convert(pdfPoint, to: page)
        guard page.bounds(for: pdfView.displayBox).contains(pagePoint) else { return nil }
        return (page, pagePoint)
    }

    func overlayPoint(_ point: NSPoint, on page: PDFPage) -> NSPoint? {
        guard let pdfView, page.document === pdfView.document else { return nil }
        return convert(pdfView.convert(point, from: page), from: pdfView)
    }

    func beginStroke(at point: NSPoint) {
        guard isPresentationEnabled, tool == .pen, let location = pageLocation(at: point) else { return }
        strokes.append(Stroke(page: location.page, segments: [[location.point]]))
        activeStrokeIndex = strokes.count - 1
        needsNewSegment = false
        refreshGeometry()
    }

    func continueStroke(at point: NSPoint) {
        guard let index = activeStrokeIndex else { return }
        guard let location = pageLocation(at: point), strokes[index].page === location.page else {
            needsNewSegment = true
            return
        }
        if needsNewSegment {
            strokes[index].segments.append([location.point])
            needsNewSegment = false
        } else {
            let segment = strokes[index].segments.count - 1
            let previous = strokes[index].segments[segment].last!
            if hypot(location.point.x - previous.x, location.point.y - previous.y) < 0.25 { return }
            strokes[index].segments[segment].append(location.point)
        }
        needsDisplay = true
    }

    func endStroke() {
        activeStrokeIndex = nil
        needsNewSegment = false
    }

    func updateLaser(at point: NSPoint, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isPresentationEnabled, !isHiddenOrHasHiddenAncestor,
              tool == .laser, pageLocation(at: point) != nil else {
            clearLaser()
            return
        }
        laserSamples.append(LaserSample(point: point, time: time))
        laserLocation = point
        expireLaser(at: time)
        if laserTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.expireLaser(at: ProcessInfo.processInfo.systemUptime)
                }
            }
            laserTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        needsDisplay = true
    }

    func expireLaser(at time: TimeInterval) {
        laserSamples.removeAll { time - $0.time >= Self.laserLifetime }
        if laserSamples.isEmpty {
            laserTimer?.invalidate()
            laserTimer = nil
        }
        needsDisplay = true
    }

    private func clearLaser() {
        laserLocation = nil
        laserSamples.removeAll()
        laserTimer?.invalidate()
        laserTimer = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isPresentationEnabled, let pdfView else { return }
        let visiblePages = pdfView.visiblePages
        let penColor = NSColor(srgbRed: 0.87, green: 0.30, blue: 0.46, alpha: 0.9)
        for stroke in strokes where visiblePages.contains(where: { $0 === stroke.page }) {
            NSGraphicsContext.saveGraphicsState()
            let pageRect = convert(pdfView.convert(stroke.page.bounds(for: pdfView.displayBox),
                                                   from: stroke.page), from: pdfView)
            NSBezierPath(rect: pageRect.intersection(bounds)).addClip()
            penColor.setStroke()
            penColor.setFill()
            for segment in stroke.segments {
                let points = segment.compactMap { overlayPoint($0, on: stroke.page) }
                guard let first = points.first else { continue }
                if points.count == 1 {
                    NSBezierPath(ovalIn: NSRect(x: first.x - 1.75, y: first.y - 1.75,
                                               width: 3.5, height: 3.5)).fill()
                } else {
                    let path = NSBezierPath()
                    path.lineWidth = 3.5
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.move(to: first)
                    for point in points.dropFirst() { path.line(to: point) }
                    path.stroke()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        drawLaser()
    }

    private func drawLaser() {
        let now = ProcessInfo.processInfo.systemUptime
        for (index, sample) in laserSamples.enumerated() {
            let alpha = max(0, 1 - (now - sample.time) / Self.laserLifetime)
            if index > 0 {
                let path = NSBezierPath()
                path.lineWidth = 3
                path.lineCapStyle = .round
                path.move(to: laserSamples[index - 1].point)
                path.line(to: sample.point)
                NSColor.systemRed.withAlphaComponent(alpha * 0.7).setStroke()
                path.stroke()
            }
        }
        guard let laserLocation else { return }
        for (radius, opacity) in [(CGFloat(11), 0.10), (CGFloat(7), 0.22), (CGFloat(3.5), 1.0)] {
            NSColor.systemRed.withAlphaComponent(opacity).setFill()
            NSBezierPath(ovalIn: NSRect(x: laserLocation.x - radius, y: laserLocation.y - radius,
                                       width: radius * 2, height: radius * 2)).fill()
        }
    }

    private func configureToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 7
        toolbar.layer?.borderWidth = 0.5
        addSubview(toolbar)
        let items = [("cursorarrow", "Pointer (V)", "V"), ("pencil.tip", "Temporary Pen (P)", "P"),
                     ("scope", "Laser Pointer (R)", "R"), ("arrow.uturn.backward", "Undo Stroke (⌘Z)", "⌘Z"),
                     ("trash", "Clear Page (E)", "E")]
        for (index, item) in items.enumerated() {
            let button = NSButton(frame: NSRect(x: 6 + index * 40, y: 4, width: 38, height: 36))
            button.image = NSImage(systemSymbolName: item.0, accessibilityDescription: item.1)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
            button.title = item.2
            button.font = .systemFont(ofSize: 9, weight: .medium)
            button.imagePosition = .imageAbove
            button.bezelStyle = .recessed
            button.setButtonType(index < 3 ? .toggle : .momentaryPushIn)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.toolTip = item.1
            button.setAccessibilityLabel(item.1)
            button.identifier = NSUserInterfaceItemIdentifier("presentation-\(index)")
            button.tag = index
            button.target = self
            button.action = #selector(toolbarAction(_:))
            toolbar.addSubview(button)
            buttons.append(button)
        }
        toolbarPinButton.frame = NSRect(x: 210, y: 8, width: 28, height: 28)
        toolbarPinButton.imagePosition = .imageOnly
        toolbarPinButton.isBordered = false
        toolbarPinButton.identifier = NSUserInterfaceItemIdentifier("presentation-toolbar-pin")
        toolbarPinButton.target = self
        toolbarPinButton.action = #selector(toggleToolbarPin(_:))
        toolbar.addSubview(toolbarPinButton)

        toolbarRevealButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Show presentation tools")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .medium))
        toolbarRevealButton.imagePosition = .imageOnly
        toolbarRevealButton.isBordered = false
        toolbarRevealButton.contentTintColor = .tertiaryLabelColor
        toolbarRevealButton.wantsLayer = true
        toolbarRevealButton.layer?.cornerRadius = 4
        toolbarRevealButton.toolTip = "Show presentation tools"
        toolbarRevealButton.setAccessibilityLabel("Show presentation tools")
        toolbarRevealButton.identifier = NSUserInterfaceItemIdentifier("presentation-toolbar-reveal")
        toolbarRevealButton.target = self
        toolbarRevealButton.action = #selector(revealToolbar(_:))
        toolbarRevealButton.isHidden = true
        addSubview(toolbarRevealButton)
    }

    private func updateButtons() {
        let page = pdfView?.currentPage
        let hasMarks = page.map { current in strokes.contains { $0.page === current } } == true
        for (index, button) in buttons.enumerated() {
            button.state = index == tool.rawValue ? .on : .off
            button.isEnabled = isPresentationEnabled && page != nil && (index < 3 || hasMarks)
            button.contentTintColor = index == tool.rawValue ? .systemPink : .secondaryLabelColor
            button.layer?.backgroundColor = index == tool.rawValue
                ? NSColor.systemPink.withAlphaComponent(0.09).cgColor
                : NSColor.clear.cgColor
        }
        let pinLabel = isToolbarPinned ? "Auto-hide toolbar" : "Keep toolbar visible"
        toolbarPinButton.image = NSImage(systemSymbolName: isToolbarPinned ? "pin.fill" : "pin", accessibilityDescription: pinLabel)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        toolbarPinButton.contentTintColor = .secondaryLabelColor
        toolbarPinButton.toolTip = pinLabel
        toolbarPinButton.setAccessibilityLabel(pinLabel)
    }

    private func focusInteraction() {
        onInteraction?()
        window?.makeFirstResponder(pdfView)
    }

    @objc private func toolbarAction(_ sender: NSButton) {
        focusInteraction()
        if let selected = Tool(rawValue: sender.tag) { selectTool(selected) }
        else if sender.tag == 3 { undoCurrentPage() }
        else if sender.tag == 4 { clearCurrentPage() }
    }

    @objc private func toggleToolbarPin(_ sender: NSButton) {
        focusInteraction()
        setToolbarPinned(!isToolbarPinned)
    }

    @objc private func revealToolbar(_ sender: NSButton) {
        focusInteraction()
        isToolbarRevealed = true
        applyToolbarVisibility()
    }
}
