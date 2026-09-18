import AppKit
import CoreImage
import PDFKit

enum FindNavigationAction: Equatable {
    case selectNext
    case selectPrevious
    case activateSelected
    case activateNext
    case activatePrevious
}

private struct SubmittedSearchKey: Equatable {
    let query: String
    let scope: SearchScope
    let options: SearchOptions
}

private struct PDFViewportAnchor {
    let page: PDFPage
    let pagePoint: NSPoint
}

private struct NavigationHistoryEntry: Equatable {
    let sessionID: UUID
    let position: ReadingPosition
}

private struct PendingExternalNavigation {
    let token: Int
    let origin: NavigationHistoryEntry
}

private enum BookScrollAxis {
    case undecided
    case horizontal
    case vertical
}

private final class SereinWordmarkView: NSView {
    var textColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let familyFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 100), toFamily: "Baskerville")
        let font = NSFontManager.shared.convert(familyFont, toHaveTrait: .italicFontMask)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let text = "Serein" as NSString
        let size = text.size(withAttributes: attributes)
        let scale = min(bounds.width * 0.82 / size.width, bounds.height * 0.65 / size.height)
        guard scale > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(
            by: bounds.midX - size.width * scale / 2,
            yBy: bounds.midY + bounds.height * 0.04 - size.height * scale / 2
        )
        transform.scale(by: scale)
        transform.concat()
        text.draw(at: .zero, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class ReaderSurfaceView: NSView {
    var onOpenURLs: (([URL]) -> Void)?

    private let dropHighlightView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        configureDropHighlight()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite else {
            dropHighlightView.frame = .zero
            return
        }
        dropHighlightView.frame = NSRect(
            x: bounds.minX + 12,
            y: bounds.minY + 12,
            width: max(bounds.width - 24, 0),
            height: max(bounds.height - 24, 0)
        )
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggingContainsOpenableURLs(sender) else { return [] }
        setDropHighlightVisible(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingContainsOpenableURLs(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlightVisible(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingContainsOpenableURLs(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDropHighlightVisible(false) }
        let urls = draggedFileURLs(from: sender)
        guard urls.isEmpty == false else { return false }
        onOpenURLs?(urls)
        return true
    }

    private func configureDropHighlight() {
        dropHighlightView.wantsLayer = true
        dropHighlightView.isHidden = true
        dropHighlightView.layer?.cornerRadius = 10
        dropHighlightView.layer?.backgroundColor = NSColor.clear.cgColor
        dropHighlightView.layer?.borderWidth = 1.5
        addSubview(dropHighlightView)
    }

    private func setDropHighlightVisible(_ visible: Bool) {
        guard dropHighlightView.isHidden == visible else { return }
        dropHighlightView.isHidden = !visible
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dropHighlightView.layer?.borderColor = NightModeStyle.secondaryTextColor.withAlphaComponent(0.45).cgColor
        }
    }

    private func draggingContainsOpenableURLs(_ sender: NSDraggingInfo) -> Bool {
        draggedFileURLs(from: sender).isEmpty == false
    }

    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else {
            return []
        }
        return urls
    }
}

/// Strips horizontal trackpad/mouse-wheel deltas before AppKit applies them.
private enum ScrollWheelHorizontalStripper {
    static func hasHorizontalComponent(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaX) > 0.001 || abs(event.deltaX) > 0.001
    }

    static func isHorizontalOnly(_ event: NSEvent) -> Bool {
        hasHorizontalComponent(event)
            && abs(event.scrollingDeltaY) < 0.1
            && abs(event.deltaY) < 0.1
    }

    static func verticalOnly(from event: NSEvent) -> NSEvent? {
        guard hasHorizontalComponent(event),
              let cgEvent = event.cgEvent?.copy() else { return event }
        // Axis2 is horizontal on macOS scroll-wheel CGEvents.
        cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        return NSEvent(cgEvent: cgEvent)
    }
}

/// Constrains scrolling before bounds change, preserving centered page margins.
private final class PDFReaderClipView: NSClipView {
    // The reader maintains centered margins and scroll limits on the main
    // thread. Concurrent scrolling can display a different position before
    // those constraints run, then visibly snap back when bounds synchronize.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    /// When non-nil, every horizontal scroll/bounds change is forced to this X.
    var forcedOriginX: CGFloat?

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        // AppKit pins origin to documentView.frame.min when content is smaller
        // than the clip, which cancels centering done via frame.origin. Keep
        // origin at zero so those frame offsets stay visible as margins.
        guard let documentView else { return bounds }
        if documentView.frame.width <= bounds.width + 0.5 {
            bounds.origin.x = 0
        }
        if documentView.frame.height <= bounds.height + 0.5 {
            bounds.origin.y = 0
        }
        if let forcedOriginX {
            bounds.origin.x = forcedOriginX
        }
        return bounds
    }

    override func scroll(to newOrigin: NSPoint) {
        applyConstrainedOrigin(clampedOrigin(for: newOrigin), proposed: newOrigin) { origin in
            super.scroll(to: origin)
        }
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        // PDFKit also sets bounds while rebuilding page geometry. Constrain
        // scrolling in scroll(to:), without clipping those layout adjustments.
        let origin = NSPoint(x: forcedOriginX ?? newOrigin.x, y: newOrigin.y)
        applyConstrainedOrigin(origin, proposed: newOrigin) { origin in
            super.setBoundsOrigin(origin)
        }
    }

    private func clampedOrigin(for origin: NSPoint) -> NSPoint {
        constrainBoundsRect(NSRect(origin: origin, size: bounds.size)).origin
    }

    private func applyConstrainedOrigin(
        _ origin: NSPoint,
        proposed: NSPoint,
        apply: (NSPoint) -> Void
    ) {
        // Reject boundary overscroll before observers or layer actions can
        // display it; correcting it in boundsDidChange causes a visible jitter.
        guard origin != proposed else {
            apply(origin)
            return
        }
        // PDFKit's scaled page edges can differ by floating-point roundoff.
        guard abs(origin.x - bounds.origin.x) > 0.000001
            || abs(origin.y - bounds.origin.y) > 0.000001 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(origin)
        CATransaction.commit()
    }
}

final class ReaderPDFView: PDFView {
    let commentIcons = CommentIconPlacement()
    // PDFKit reads its native document getter from the form-filling queue.
    // Clear our UI cache explicitly without overriding that getter in Swift.
    func setReaderDocument(_ document: PDFDocument?) {
        commentIcons.retainPages([])
        textSelectionAnchor = nil
        self.document = document
    }
    var onLayoutCompleted: (() -> Void)?
    var onInternalLinkNavigationRequested: ((PDFDestination) -> Bool)?
    var onInternalLinkPreviewRequested: ((PDFDestination, NSRect) -> Bool)?
    var onAnnotationActivationRequested: ((NSEvent) -> Bool)?
    var onUserMagnificationRequested: (() -> Void)?
    var onZoomInRequested: (() -> Void)?
    var onZoomOutRequested: (() -> Void)?
    var shouldAllowUserMagnification: (() -> Bool)?
    var onPointerMoved: ((NSEvent?) -> Void)?
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?

    private var pointerTrackingArea: NSTrackingArea?
    private var textSelectionAnchor: (page: PDFPage, point: NSPoint)?
    nonisolated(unsafe) private var textSelectionMouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let textSelectionMouseMonitor {
            NSEvent.removeMonitor(textSelectionMouseMonitor)
            self.textSelectionMouseMonitor = nil
        }
        textSelectionAnchor = nil
        guard window != nil else { return }
        textSelectionMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      !self.isHiddenOrHasHiddenAncestor else { return false }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.visibleRect.contains(point),
                      let hit = self.window?.contentView?.hitTest(event.locationInWindow),
                      hit === self || hit.isDescendant(of: self) else { return false }
                return self.handleTextSelectionMouseDown(event)
            }
            return handled ? nil : event
        }
    }

    deinit {
        if let textSelectionMouseMonitor {
            NSEvent.removeMonitor(textSelectionMouseMonitor)
        }
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        nil
    }

    override func layout() {
        super.layout()
        onLayoutCompleted?()
    }

    override func layoutDocumentView() {
        super.layoutDocumentView()
        onLayoutCompleted?()
    }

    override func layoutSubtreeIfNeeded() {
        super.layoutSubtreeIfNeeded()
        onLayoutCompleted?()
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerMoved?(event)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerMoved?(nil)
        super.mouseExited(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let custom = contextMenuProvider?(event)
        if managedAnnotation(at: convert(event.locationInWindow, from: nil)) != nil {
            return custom
        }
        return Self.mergeContextMenus(
            custom: custom,
            native: super.menu(for: event)
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent,
           event.type != .leftMouseDown, event.type != .rightMouseDown {
            return super.hitTest(point)
        }
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint), managedAnnotation(at: localPoint) != nil {
            return self
        }
        return super.hitTest(point)
    }

    private func managedAnnotation(at point: NSPoint) -> PDFAnnotation? {
        guard let page = page(for: point, nearest: false) else { return nil }
        let pagePoint = convert(point, to: page)
        return commentIcons.annotation(at: pagePoint, on: page)
            ?? HighlightService.highlightAnnotation(at: pagePoint, on: page)
    }

    static func mergeContextMenus(custom: NSMenu?, native: NSMenu?) -> NSMenu? {
        guard let custom else { return native }
        guard let native else { return custom }
        let customItems = custom.items
        guard customItems.isEmpty == false else { return native }

        customItems.forEach(custom.removeItem)
        for (index, item) in customItems.enumerated() {
            native.insertItem(item, at: index)
        }
        native.insertItem(.separator(), at: customItems.count)
        return native
    }

    private func handleTextSelectionMouseDown(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let endpoint = textEndpoint(at: point)
        if event.modifierFlags.intersection([.shift, .command, .option, .control]) == .shift,
           let anchor = textSelectionAnchor, let endpoint,
           let document, anchor.page.document === document {
            let forward = document.index(for: anchor.page) <= document.index(for: endpoint.page)
            let start = forward ? anchor : endpoint
            let end = forward ? endpoint : anchor
            if let selection = document.selection(from: start.page, at: start.point,
                                                  to: end.page, at: end.point) {
                window?.makeFirstResponder(self)
                setCurrentSelection(selection, animate: false)
                return true
            }
        }
        textSelectionAnchor = internalLink(at: event) == nil && managedAnnotation(at: point) == nil ? endpoint : nil
        return false
    }

    override func mouseDown(with event: NSEvent) {
        if let link = internalLink(at: event) {
            if !event.modifierFlags.contains(.option),
               onInternalLinkPreviewRequested?(link.destination, link.rect) == true {
                return
            }
            if onInternalLinkNavigationRequested?(link.destination) == true {
                return
            }
        }
        if onAnnotationActivationRequested?(event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    private func textEndpoint(at point: NSPoint) -> (page: PDFPage, point: NSPoint)? {
        guard let page = page(for: point, nearest: false) else { return nil }
        // PDFKit resolves insertion points in whitespace as well as inside glyphs.
        return (page, convert(point, to: page))
    }

    override func magnify(with event: NSEvent) {
        guard allowsUserMagnification else { return }
        onUserMagnificationRequested?()
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        guard allowsUserMagnification else { return }
        onUserMagnificationRequested?()
        super.smartMagnify(with: event)
    }

    override func zoomIn(_ sender: Any?) {
        onZoomInRequested?()
    }

    override func zoomOut(_ sender: Any?) {
        onZoomOutRequested?()
    }

    private var allowsUserMagnification: Bool {
        shouldAllowUserMagnification?() ?? true
    }

    private func internalLink(at event: NSEvent) -> (destination: PDFDestination, rect: NSRect)? {
        let pointInView = convert(event.locationInWindow, from: nil)
        guard let page = page(for: pointInView, nearest: false) else { return nil }
        let pointOnPage = convert(pointInView, to: page)
        guard let annotation = page.annotations.first(where: {
            $0.type == "Link" && $0.bounds.contains(pointOnPage)
        }), let destination = (annotation.action as? PDFActionGoTo)?.destination ?? annotation.destination,
              let targetPage = destination.page,
              targetPage.document === document else { return nil }
        return (destination, convert(annotation.bounds, from: page))
    }
}

final class ReaderViewController: NSViewController {
    private static let bookFitHorizontalInset: CGFloat = 32
    private static let bookFitVerticalInset: CGFloat = 24
    private static let bookSpreadGap: CGFloat = 14

    let documentStore: DocumentStore
    let windowID: UUID
    let pdfView = ReaderPDFView()
    var onFocusRequested: (() -> Void)?
    var onFindActionRequested: ((FindNavigationAction) -> Void)?
    var onOpenURLsRequested: (([URL]) -> Void)?
    var onOverviewPresentationDidChange: ((Bool) -> Void)?
    var onHistorySessionNavigationRequested: ((UUID) -> UUID?)?
    var onPageBoundaryRequested: (Int) -> Bool = { _ in false }
    var onSendSelectionToCodexRequested: ((String) -> Void)?
    var onSendPageImageToCodexRequested: ((NSImage, Int) -> Void)?
    /// When true for a groupID, hover preview is suppressed (e.g. same row selected in Annotations sidebar).
    var shouldSuppressAnnotationPreview: ((String) -> Bool)?
    private let pdfContainerView = PDFContainerView()
    var presentationOverlay: PresentationAnnotationOverlayView { pdfContainerView.presentationOverlay }
    private let emptyStateContainer = NSStackView()
    private let emptyStateWordmark = SereinWordmarkView()
    private let emptyStateErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let highlightModeIndicator = NSStackView()
    private let highlightModeColorDot = NSView()
    private let highlightModeLabel = NSTextField(labelWithString: "Highlight · Esc")
    private let panLockIndicator = NSTextField(labelWithString: "H-lock · L")
    private let switchTitleToastView = NSView()
    private let switchTitleToastLabel = NSTextField(labelWithString: "")
    private lazy var annotationInteraction = ReaderAnnotationInteractionController(
        documentStore: documentStore,
        pdfView: pdfView
    )
    private let overviewGridView = OverviewGridView()
    private let referencePreview = ReaderReferencePreviewController()
    private let findBarView = FindBarView()
    private var pdfContainerTopConstraint: NSLayoutConstraint?
    private var readerState = ReaderState()
    private(set) var displayedSessionID: UUID?
    private var displayedReadingPosition: ReadingPosition?
    private var displayedDisplayMode: ReaderDisplayMode?
    private var displayedScaleMode: ReaderScaleMode?
    private var isApplyingStoreState = false
    private var isApplyingProgrammaticScale = false
    private var isApplyingHighlightSelection = false
    /// Owned Cmd+[ / ] history. PDFKit's stack is wiped by store re-`go(to:)` and
    /// misses some paths; we record intentional jumps and external page changes.
    private var navigationBackStack: [NavigationHistoryEntry] = []
    private var navigationForwardStack: [NavigationHistoryEntry] = []
    private var historyNavigationEpoch = 0
    private var isNavigatingHistory: Bool { historyNavigationEpoch != 0 }
    private var pendingExternalNavigation: PendingExternalNavigation?
    private var externalNavigationToken = 0
    private var appearanceObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var leftMouseDownMonitor: Any?
    nonisolated(unsafe) private var leftMouseUpMonitor: Any?
    nonisolated(unsafe) private var panLockScrollMonitor: Any?
    nonisolated(unsafe) private var magnificationMonitor: Any?
    private var wantsLocalEventMonitoring = true
    private var bookPageTurnScrollAccumulator: CGFloat = 0
    private var lastBookPageTurnScrollTimestamp: TimeInterval?
    private var lastBookPageTurnTimestamp: TimeInterval?
    private var bookScrollAxis = BookScrollAxis.undecided
    private var bookScrollGestureOwnedByReader = false
    private var consumeBookDirectScrollUntilEnd = false
    private var consumeBookMomentumUntilEnd = false
    private var ownsVerticalPageGesture = false
    private var verticalPageTurnAccumulator: CGFloat = 0
    private var didTurnPageInVerticalGesture = false
    private var pendingFitWidthSessionID: UUID?
    private var pendingFitHeightSessionID: UUID?
    private var lastAppliedFitBoundsWidth: CGFloat = 0
    private var lastAppliedFitBoundsHeight: CGFloat = 0
    private var isDocumentRecenteringScheduled = false
    private var isPDFLayoutMaintenanceScheduled = false
    private weak var cachedPDFScrollView: NSScrollView?
    private weak var cachedPDFDocumentView: NSView?
    private var cachedPDFScrollBackgroundViews: [NSView] = []
    private var cachedPDFPageViews: [NSView] = []
    private var needsPDFPrivateViewDiscovery = true
    private var pdfPrivateViewDiscoveryPassesRemaining = 2
    private var pdfPrivateViewGeneration = 0
    private var lastThemeFilterSignature: String?
    private weak var observedPDFClipView: NSClipView?
    private var lastObservedPDFClipBounds: NSRect?
    private var isApplyingScrollClamp = false
    private var lastSubmittedSearchKey: SubmittedSearchKey?
    private var pendingFindNavigationAfterSearch: SubmittedSearchKey?
    private struct PendingReadingPositionWriteback {
        let sessionID: UUID
        let position: ReadingPosition
        let scaleFactor: CGFloat
    }
    private var pendingReadingPositionWriteback: PendingReadingPositionWriteback?
    private var readingPositionWritebackWorkItem: DispatchWorkItem?
    private static let readingPositionWritebackDelay: TimeInterval = 0.08
    private var switchTitleToastHideWorkItem: DispatchWorkItem?
    private(set) var isReadingFocusModeEnabled = false
    private(set) var isHorizontalPanLocked = false
    private(set) var readingFocusSettings: ReadingFocusSettings = .default
    var targetSessionID: UUID? {
        didSet {
            guard oldValue != targetSessionID else { return }
            pendingFindNavigationAfterSearch = nil
            flushPendingReadingPositionWriteback()
            refreshDisplayedDocument()
        }
    }

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
        self.readingFocusSettings = documentStore.appConfiguration.reader.readingFocus
        super.init(nibName: nil, bundle: nil)
        title = "Reader"
    }

    convenience init(documentStore: DocumentStore) {
        self.init(documentStore: documentStore, windowID: documentStore.defaultWindowID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pdfView.onLayoutCompleted = { [weak self] in
            self?.syncPDFMarginBackgroundAfterPDFKitLayout()
            self?.annotationInteraction.scheduleOverlayRefresh()
        }
        pdfView.onInternalLinkNavigationRequested = { [weak self] destination in
            self?.referencePreview.close()
            return self?.navigate(toInternalLink: destination) ?? false
        }
        pdfView.onInternalLinkPreviewRequested = { [weak self] destination, rect in
            guard let self else { return false }
            self.onFocusRequested?()
            self.annotationInteraction.clearPreview()
            self.annotationInteraction.dismissCommentEditor()
            return self.referencePreview.show(destination: destination, anchor: rect, in: self.pdfView)
        }
        referencePreview.onNavigate = { [weak self] destination in
            _ = self?.navigate(toInternalLink: destination)
        }
        pdfView.onUserMagnificationRequested = { [weak self] in
            self?.beginUserMagnification()
        }
        pdfView.onZoomInRequested = { [weak self] in self?.zoomIn() }
        pdfView.onZoomOutRequested = { [weak self] in self?.zoomOut() }
        pdfView.shouldAllowUserMagnification = { [weak self] in
            self?.shouldLockHorizontalPan == false
        }
        pdfView.onPointerMoved = { [weak self] event in
            guard let self, self.presentationOverlay.isPresentationEnabled == false else { return }
            self.annotationInteraction.handlePointerMoved(event)
        }
        pdfView.contextMenuProvider = { [weak self] event in
            self?.annotationInteraction.makeContextMenu(for: event)
        }
        pdfView.onAnnotationActivationRequested = { [weak self] event in
            self?.annotationInteraction.activateAnnotation(at: event) ?? false
        }
        annotationInteraction.onFocusRequested = { [weak self] in
            self?.onFocusRequested?()
        }
        annotationInteraction.onCreateMarkupRequested = { [weak self] type in
            self?.createHighlightFromCurrentSelection(type: type)
        }
        annotationInteraction.onNavigateRequested = { [weak self] group in
            self?.focus(on: group, showPulse: false)
        }
        annotationInteraction.onSendSelectionToCodexRequested = { [weak self] text in
            self?.onSendSelectionToCodexRequested?(text)
        }
        annotationInteraction.onSendPageImageToCodexRequested = { [weak self] image, pageNumber in
            self?.onSendPageImageToCodexRequested?(image, pageNumber)
        }
        annotationInteraction.shouldSuppressPreview = { [weak self] groupID in
            self?.shouldSuppressAnnotationPreview?(groupID) ?? false
        }
        pdfContainerView.readingFocusOverlay.pageBoundsProvider = { [weak self] point in
            self?.readingFocusPageBounds(at: point)
        }
        pdfContainerView.setReadingFocusSettings(readingFocusSettings)
        presentationOverlay.pdfView = pdfView
        presentationOverlay.onInteraction = { [weak self] in
            self?.onFocusRequested?()
            self?.exitHighlightMode()
            self?.annotationInteraction.clearPreview()
            self?.annotationInteraction.dismissCommentEditor()
            self?.referencePreview.close()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: documentStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewPageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewScaleChanged),
            name: Notification.Name.PDFViewScaleChanged,
            object: pdfView
        )
        syncNightModeFromSystem()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncNightModeFromSystem()
                self.applyReaderAppearance()
            }
        }
        syncLocalEventMonitoring()
        refreshDisplayedDocument()
        configurePDFScrollBehaviorIfNeeded()
        applyReaderAppearance()
    }

    private func syncNightModeFromSystem() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        readerState.isNightModeEnabled = isDark
    }

    /// Hidden secondary readers do not need four app-wide event taps. The
    /// workspace toggles this with pane visibility; calls are idempotent.
    func setLocalEventMonitoringEnabled(_ isEnabled: Bool) {
        guard wantsLocalEventMonitoring != isEnabled else { return }
        wantsLocalEventMonitoring = isEnabled
        guard isViewLoaded else { return }
        syncLocalEventMonitoring()
    }

    private func syncLocalEventMonitoring() {
        if wantsLocalEventMonitoring {
            installLocalEventMonitoringIfNeeded()
        } else {
            referencePreview.close()
            removeLocalEventMonitoring()
        }
    }

    private func installLocalEventMonitoringIfNeeded() {
        if leftMouseDownMonitor == nil {
            leftMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.requestFocusIfNeeded(event: event)
                }
                return event
            }
        }
        if leftMouseUpMonitor == nil {
            leftMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.applyHighlightOnMouseUpIfNeeded(event: event)
                }
                return event
            }
        }
        if panLockScrollMonitor == nil {
            // Strip horizontal deltas before PDFKit's scroll view sees them.
            panLockScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                var rewritten: NSEvent? = event
                MainActor.assumeIsolated {
                    rewritten = self.rewriteScrollEventIfNeeded(event)
                }
                return rewritten
            }
        }
        if magnificationMonitor == nil {
            // PDFKit delivers trackpad pinch to its private document view.
            magnificationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .smartMagnify]) { [weak self] event in
                guard let self else { return event }
                var rewritten: NSEvent? = event
                MainActor.assumeIsolated {
                    rewritten = self.rewriteMagnificationEventIfPanLocked(event)
                    if rewritten != nil {
                        self.handleMagnificationEventIfNeeded(event)
                    }
                }
                return rewritten
            }
        }
    }

    nonisolated private func removeLocalEventMonitoring() {
        if let monitor = leftMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseDownMonitor = nil
        }
        if let monitor = leftMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseUpMonitor = nil
        }
        if let monitor = panLockScrollMonitor {
            NSEvent.removeMonitor(monitor)
            panLockScrollMonitor = nil
        }
        if let monitor = magnificationMonitor {
            NSEvent.removeMonitor(monitor)
            magnificationMonitor = nil
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        presentationOverlay.refreshGeometry()
        if isAllPagesOverviewActive {
            reflowOverviewGrid()
        }
        syncPDFMarginBackgroundAfterPDFKitLayout()

        guard let session = targetSession(),
              displayedSessionID == session.id,
              pdfView.bounds.width > 0,
              pdfView.bounds.height > 0 else { return }

        guard session.scaleMode == .fitWidth || session.scaleMode == .fitHeight else {
            recenterDocumentViewIfNeeded()
            return
        }

        let isPending: Bool
        let boundsChanged: Bool
        switch session.scaleMode {
        case .fitWidth:
            isPending = pendingFitWidthSessionID == session.id
            boundsChanged = abs(pdfView.bounds.width - lastAppliedFitBoundsWidth) > 0.5
                || session.displayMode.usesBookLayout
                    && abs(pdfView.bounds.height - lastAppliedFitBoundsHeight) > 0.5
        case .fitHeight:
            isPending = pendingFitHeightSessionID == session.id
            boundsChanged = abs(pdfView.bounds.height - lastAppliedFitBoundsHeight) > 0.5
        case .manual:
            isPending = false
            boundsChanged = false
        }
        guard isPending || boundsChanged else {
            recenterDocumentViewIfNeeded()
            return
        }

        // The outer PDFView can receive its final split-pane width before its
        // internal clip/document views do. Fit against the settled clip width.
        pdfView.layoutSubtreeIfNeeded()
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()

        switch session.scaleMode {
        case .fitWidth:
            pendingFitWidthSessionID = nil
            applyFitWidth(for: session)
        case .fitHeight:
            pendingFitHeightSessionID = nil
            lastAppliedFitBoundsHeight = pdfView.bounds.height
            applyFitHeight(for: session)
        case .manual:
            break
        }
        recenterDocumentViewIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeLocalEventMonitoring()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        referencePreview.close()
        flushPendingReadingPositionWriteback()
    }

    func flushPendingReadingPosition() {
        flushPendingReadingPositionWriteback()
    }

    override func loadView() {
        let container = ReaderSurfaceView()
        container.onOpenURLs = { [weak self] urls in
            self?.onOpenURLsRequested?(urls)
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor

        pdfContainerView.translatesAutoresizingMaskIntoConstraints = false

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.wantsLayer = true
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.white
        pdfView.isHidden = true
        // Page spacing is geometry; keep it identical across appearance changes.
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = false

        emptyStateErrorLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyStateErrorLabel.textColor = NightModeStyle.secondaryTextColor
        emptyStateErrorLabel.alignment = .center
        emptyStateErrorLabel.maximumNumberOfLines = 0
        emptyStateErrorLabel.isHidden = true
        emptyStateErrorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        emptyStateContainer.orientation = .vertical
        emptyStateContainer.alignment = .centerX
        emptyStateContainer.spacing = 8
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addArrangedSubview(emptyStateErrorLabel)

        highlightModeIndicator.translatesAutoresizingMaskIntoConstraints = false
        highlightModeIndicator.orientation = .horizontal
        highlightModeIndicator.alignment = .centerY
        highlightModeIndicator.spacing = 6
        highlightModeIndicator.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        highlightModeIndicator.isHidden = true

        highlightModeColorDot.translatesAutoresizingMaskIntoConstraints = false
        highlightModeColorDot.wantsLayer = true
        highlightModeColorDot.layer?.cornerRadius = 3.5

        highlightModeLabel.translatesAutoresizingMaskIntoConstraints = false
        highlightModeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        highlightModeLabel.textColor = NightModeStyle.secondaryTextColor
        highlightModeLabel.alignment = .left
        highlightModeLabel.isEditable = false
        highlightModeLabel.isBordered = false
        highlightModeLabel.drawsBackground = false

        highlightModeIndicator.addArrangedSubview(highlightModeColorDot)
        highlightModeIndicator.addArrangedSubview(highlightModeLabel)

        panLockIndicator.translatesAutoresizingMaskIntoConstraints = false
        panLockIndicator.font = .systemFont(ofSize: 11, weight: .medium)
        panLockIndicator.textColor = NightModeStyle.secondaryTextColor
        panLockIndicator.alignment = .right
        panLockIndicator.isEditable = false
        panLockIndicator.isBordered = false
        panLockIndicator.drawsBackground = false
        panLockIndicator.isHidden = true

        switchTitleToastView.translatesAutoresizingMaskIntoConstraints = false
        switchTitleToastView.wantsLayer = true
        switchTitleToastView.layer?.cornerRadius = 8
        switchTitleToastView.layer?.masksToBounds = true
        switchTitleToastView.alphaValue = 0
        switchTitleToastView.isHidden = true

        switchTitleToastLabel.translatesAutoresizingMaskIntoConstraints = false
        switchTitleToastLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        switchTitleToastLabel.alignment = .center
        switchTitleToastLabel.lineBreakMode = .byTruncatingMiddle
        switchTitleToastLabel.isEditable = false
        switchTitleToastLabel.isBordered = false
        switchTitleToastLabel.drawsBackground = false
        switchTitleToastView.addSubview(switchTitleToastLabel)

        overviewGridView.translatesAutoresizingMaskIntoConstraints = false
        overviewGridView.isHidden = true
        overviewGridView.onPageSelected = { [weak self] pageIndex in
            self?.handleOverviewPageSelected(pageIndex)
        }

        findBarView.translatesAutoresizingMaskIntoConstraints = false
        findBarView.delegate = self
        findBarView.isHidden = true

        pdfContainerView.embedPDFView(pdfView)
        container.addSubview(pdfContainerView)
        annotationInteraction.install(in: container)
        container.addSubview(emptyStateContainer)
        emptyStateWordmark.translatesAutoresizingMaskIntoConstraints = false
        emptyStateWordmark.setAccessibilityElement(false)
        container.addSubview(emptyStateWordmark)
        container.addSubview(highlightModeIndicator)
        container.addSubview(panLockIndicator)
        container.addSubview(switchTitleToastView)
        container.addSubview(overviewGridView)
        container.addSubview(findBarView)

        let pdfTop = pdfContainerView.topAnchor.constraint(equalTo: container.topAnchor)
        pdfContainerTopConstraint = pdfTop

        NSLayoutConstraint.activate([
            emptyStateWordmark.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emptyStateWordmark.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyStateWordmark.topAnchor.constraint(equalTo: container.topAnchor),
            emptyStateWordmark.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfContainerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfContainerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfTop,
            pdfContainerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainerView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainerView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: pdfContainerView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainerView.bottomAnchor),
            emptyStateContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyStateContainer.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            emptyStateContainer.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            highlightModeIndicator.topAnchor.constraint(equalTo: pdfContainerView.topAnchor, constant: 8),
            highlightModeIndicator.leadingAnchor.constraint(equalTo: pdfContainerView.leadingAnchor, constant: 12),
            highlightModeColorDot.widthAnchor.constraint(equalToConstant: 7),
            highlightModeColorDot.heightAnchor.constraint(equalToConstant: 7),
            panLockIndicator.topAnchor.constraint(equalTo: pdfContainerView.topAnchor, constant: 8),
            panLockIndicator.trailingAnchor.constraint(equalTo: pdfContainerView.trailingAnchor, constant: -12),
            switchTitleToastView.topAnchor.constraint(equalTo: pdfContainerView.topAnchor, constant: 10),
            switchTitleToastView.centerXAnchor.constraint(equalTo: pdfContainerView.centerXAnchor),
            switchTitleToastView.widthAnchor.constraint(lessThanOrEqualTo: pdfContainerView.widthAnchor, multiplier: 0.62),
            switchTitleToastLabel.leadingAnchor.constraint(equalTo: switchTitleToastView.leadingAnchor, constant: 12),
            switchTitleToastLabel.trailingAnchor.constraint(equalTo: switchTitleToastView.trailingAnchor, constant: -12),
            switchTitleToastLabel.topAnchor.constraint(equalTo: switchTitleToastView.topAnchor, constant: 5),
            switchTitleToastLabel.bottomAnchor.constraint(equalTo: switchTitleToastView.bottomAnchor, constant: -5),
            overviewGridView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overviewGridView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overviewGridView.topAnchor.constraint(equalTo: container.topAnchor),
            overviewGridView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            findBarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBarView.topAnchor.constraint(equalTo: container.topAnchor),
            findBarView.heightAnchor.constraint(equalToConstant: 36),
        ])

        view = container
    }

    func fitToWidth() {
        guard let session = targetSession() else { return }
        if pdfView.bounds.width > 0 {
            pendingFitWidthSessionID = nil
        }
        applyFitWidth(for: session)
    }

    /// Fit the current page or spread's text once, keeping its vertical reading position.
    func fitToTextWidth() {
        guard !isAllPagesOverviewActive,
              !presentationOverlay.isPresentationEnabled,
              let session = targetSession(), session.id == displayedSessionID,
              let document = pdfView.document, let clipView = pdfClipView() else { return }
        let pages = spreadPages(for: session, in: document)
        guard let anchorPage = pages.first else { return }
        var textRect = NSRect.null
        for page in pages {
            let pageBounds = page.bounds(for: pdfView.displayBox)
            guard let text = page.string else { return }
            let characters = Array(text.utf16)
            var bounds = NSRect.null
            for index in 0..<min(characters.count, page.numberOfCharacters) {
                if let scalar = UnicodeScalar(characters[index]), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    continue
                }
                let glyph = page.characterBounds(at: index).intersection(pageBounds)
                if !glyph.isEmpty, !glyph.isNull, !glyph.isInfinite {
                    bounds = bounds.union(glyph)
                }
            }
            guard !bounds.isEmpty, !bounds.isNull, !bounds.isInfinite else { return }
            textRect = textRect.union(pdfView.convert(bounds, from: page))
        }
        let viewport = pdfView.convert(clipView.bounds, from: clipView)
        let availableWidth = viewport.width - 24
        guard textRect.width > 0, availableWidth > 0 else { return }
        let scale = min(max(pdfView.scaleFactor * availableWidth / textRect.width,
                            pdfView.minScaleFactor), pdfView.maxScaleFactor)
        let anchor = PDFViewportAnchor(
            page: anchorPage,
            pagePoint: pdfView.convert(NSPoint(x: textRect.midX, y: viewport.midY), to: anchorPage)
        )

        flushPendingReadingPositionWriteback()
        let wasApplying = isApplyingStoreState
        isApplyingStoreState = true
        defer { isApplyingStoreState = wasApplying }
        pendingFitWidthSessionID = nil
        pendingFitHeightSessionID = nil
        applyProgrammaticScale(scale, viewportAnchor: anchor)
        // A legacy vertical scroller can disappear when the fitted page becomes
        // shorter than the viewport. Fit against the resulting content width.
        let fittedWidth = pdfView.convert(clipView.bounds, from: clipView).width - 24
        if fittedWidth > 0, abs(fittedWidth - availableWidth) > 0.5 {
            let adjustedScale = min(max(pdfView.scaleFactor * fittedWidth / availableWidth,
                                        pdfView.minScaleFactor), pdfView.maxScaleFactor)
            applyProgrammaticScale(adjustedScale, viewportAnchor: anchor)
        }
        displayedScaleMode = .manual
        documentStore.setScaleMode(.manual, scaleFactor: pdfView.scaleFactor, for: session.id)
        if let position = currentReadingPosition() {
            displayedReadingPosition = position
            documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        }
    }

    /// Called after split chrome changes so fit modes track the new reader width
    /// instead of leaving the previous scale (which looks like a sidebar overlay).
    func reflowForContainerSizeChange() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        pdfView.layoutSubtreeIfNeeded()
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        guard let session = targetSession(),
              displayedSessionID == session.id,
              pdfView.bounds.width > 0,
              pdfView.bounds.height > 0 else { return }

        switch session.scaleMode {
        case .fitWidth:
            pendingFitWidthSessionID = nil
            // Invalidate so applyFitWidth always recomputes against the settled clip.
            lastAppliedFitBoundsWidth = -1
            applyFitWidth(for: session)
        case .fitHeight:
            pendingFitHeightSessionID = nil
            lastAppliedFitBoundsHeight = -1
            applyFitHeight(for: session)
        case .manual:
            break
        }
        recenterDocumentViewIfNeeded()
    }

    func fitToHeight() {
        guard let session = targetSession() else { return }
        if pdfView.bounds.height > 0 {
            pendingFitHeightSessionID = nil
            lastAppliedFitBoundsHeight = pdfView.bounds.height
        }
        applyFitHeight(for: session)
    }

    func fitToPage() {
        guard let session = targetSession(),
              let scaleFactor = fitPageScaleFactor() else { return }
        pendingFitWidthSessionID = nil
        pendingFitHeightSessionID = nil
        lastAppliedFitBoundsWidth = 0
        lastAppliedFitBoundsHeight = 0
        applyProgrammaticScale(scaleFactor, preserveViewportCenter: false)
        displayedScaleMode = .manual
        documentStore.setScaleMode(.manual, scaleFactor: scaleFactor, for: session.id)
    }

    func zoomIn() {
        if isAllPagesOverviewActive {
            adjustOverviewZoom(scale: 1.1)
            return
        }
        guard let session = targetSession(),
              session.id == displayedSessionID else { return }
        flushPendingReadingPositionWriteback()
        let nextScale = min(pdfView.scaleFactor * 1.1, pdfView.maxScaleFactor)
        applyProgrammaticScale(nextScale, preserveViewportCenter: true)
        // Pin before store writeback so the notification does not re-apply scale.
        displayedScaleMode = .manual
        // PDFKit emits intermediate bounds while scaling. Persist the restored
        // viewport, replacing any writeback queued before anchor restoration.
        if let position = currentReadingPosition() {
            displayedReadingPosition = position
            scheduleReadingPositionWriteback(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        }
        flushPendingReadingPositionWriteback()
        documentStore.setScaleMode(.manual, scaleFactor: nextScale, for: session.id)
    }

    func zoomOut() {
        if isAllPagesOverviewActive {
            adjustOverviewZoom(scale: 1 / 1.1)
            return
        }
        guard let session = targetSession(),
              session.id == displayedSessionID else { return }
        flushPendingReadingPositionWriteback()
        let nextScale = max(pdfView.scaleFactor / 1.1, pdfView.minScaleFactor)
        applyProgrammaticScale(nextScale, preserveViewportCenter: true)
        // Pin before store writeback so the notification does not re-apply scale.
        displayedScaleMode = .manual
        // PDFKit emits intermediate bounds while scaling. Persist the restored
        // viewport, replacing any writeback queued before anchor restoration.
        if let position = currentReadingPosition() {
            displayedReadingPosition = position
            scheduleReadingPositionWriteback(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        }
        flushPendingReadingPositionWriteback()
        documentStore.setScaleMode(.manual, scaleFactor: nextScale, for: session.id)
    }

    @discardableResult
    func goToNextPage() -> Bool {
        turnPage(by: 1)
    }

    @discardableResult
    func goToPreviousPage() -> Bool {
        turnPage(by: -1)
    }

    @discardableResult
    func goToPreviousPageBottom() -> Bool {
        guard isAllPagesOverviewActive == false,
              let session = targetSession(),
              session.id == displayedSessionID,
              let document = pdfView.document,
              let currentPageIndex = currentPageIndexForNavigation(in: document) else { return false }

        let currentStop = session.displayMode.usesTwoUpLayout
            ? normalizedSpreadLead(
                currentPageIndex,
                pageCount: document.pageCount,
                displayMode: session.displayMode
            )
            : currentPageIndex
        let targetPageIndex = session.displayMode.usesTwoUpLayout
            ? adjacentSpreadLead(from: currentStop, direction: -1, displayMode: session.displayMode)
            : max(currentStop - 1, 0)
        guard targetPageIndex != currentStop else { return false }
        let pageIndex = session.displayMode.usesBookLayout
            ? trailingPageIndex(forSpreadLead: targetPageIndex, pageCount: document.pageCount)
            : targetPageIndex
        guard let page = document.page(at: pageIndex) else { return false }
        let pageBounds = page.bounds(for: pdfView.displayBox)
        return go(
            to: ReadingPosition(
                pageIndex: pageIndex,
                point: NSPoint(
                    x: session.displayMode.usesBookLayout ? pageBounds.maxX : pageBounds.minX,
                    y: pageBounds.minY
                )
            ),
            recordHistory: false
        )
    }

    @discardableResult
    func scrollHalfPageDown() -> Bool {
        scrollByViewportFraction(0.5)
    }

    @discardableResult
    func scrollHalfPageUp() -> Bool {
        scrollByViewportFraction(-0.5)
    }

    func goToFirstPage() {
        _ = goToPage(0)
    }

    func goToLastPage() {
        guard let document = pdfView.document,
              document.pageCount > 0,
              let page = document.page(at: document.pageCount - 1) else { return }
        let bounds = page.bounds(for: pdfView.displayBox)
        _ = go(
            to: ReadingPosition(
                pageIndex: document.pageCount - 1,
                point: NSPoint(x: bounds.minX, y: bounds.minY)
            )
        )
        scrollToDocumentEnd()
    }

    func navigateBack() {
        while let target = navigationBackStack.last {
            guard isHistoryEntryAvailable(target) else {
                navigationBackStack.removeLast()
                continue
            }
            let current = currentHistoryEntry()
            guard playOwnedHistory(to: target) else { return }
            navigationBackStack.removeLast()
            if let current, navigationForwardStack.last != current {
                navigationForwardStack.append(current)
            }
            return
        }
    }

    func navigateForward() {
        while let target = navigationForwardStack.last {
            guard isHistoryEntryAvailable(target) else {
                navigationForwardStack.removeLast()
                continue
            }
            let current = currentHistoryEntry()
            guard playOwnedHistory(to: target) else { return }
            navigationForwardStack.removeLast()
            if let current {
                pushBackHistory(current)
            }
            return
        }
    }

    var canGoBack: Bool {
        navigationBackStack.contains(where: isHistoryEntryAvailable)
    }
    var canGoForward: Bool {
        navigationForwardStack.contains(where: isHistoryEntryAvailable)
    }

    /// Test seam: owned history page indices (back stack, oldest → newest).
    var testingNavigationBackPageIndices: [Int] { navigationBackStack.map(\.position.pageIndex) }
    var testingReferencePreviewContent: ReferencePreviewViewController? { referencePreview.content }
    /// Test seam: owned history positions (back stack, oldest → newest).
    var testingNavigationBackPositions: [ReadingPosition] { navigationBackStack.map(\.position) }
    /// Test seam: owned history session IDs (back stack, oldest → newest).
    var testingNavigationBackSessionIDs: [UUID] { navigationBackStack.map(\.sessionID) }
    /// Test seam: owned history page indices (forward stack, nearest → furthest).
    var testingNavigationForwardPageIndices: [Int] { navigationForwardStack.map(\.position.pageIndex) }
    /// Test seam: live PDFKit viewport anchor.
    var testingCurrentReadingPosition: ReadingPosition? { currentReadingPosition() }
    var testingHasPendingReadingPositionWriteback: Bool {
        pendingReadingPositionWriteback != nil
    }

    func testingScheduleReadingPositionWriteback(
        _ position: ReadingPosition,
        for sessionID: UUID
    ) {
        scheduleReadingPositionWriteback(
            position,
            scaleFactor: pdfView.scaleFactor,
            for: sessionID
        )
    }

    func testingFlushReadingPositionWriteback() {
        flushPendingReadingPosition()
    }

    var testingFindBarStatusText: String {
        findBarView.testingStatusText
    }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        jumpToPage(pageIndex, recordHistory: true)
    }

    /// Exact navigation entry point for Outline and other page-point targets.
    @discardableResult
    func go(to position: ReadingPosition, recordHistory: Bool = true) -> Bool {
        guard let document = pdfView.document,
              position.pageIndex >= 0,
              position.pageIndex < document.pageCount,
              let page = document.page(at: position.pageIndex) else { return false }

        if let current = historyAnchorPosition(), current == position {
            return true
        }
        if recordHistory {
            recordNavigationHistoryBeforeJump()
        }
        applyProgrammaticDestination(page: page, point: position.point, storePosition: position)
        return true
    }

    private func navigate(toInternalLink destination: PDFDestination) -> Bool {
        guard let document = pdfView.document,
              let page = destination.page else { return false }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0, pageIndex < document.pageCount else { return false }
        return go(
            to: ReadingPosition(pageIndex: pageIndex, point: destination.point),
            recordHistory: true
        )
    }

    @discardableResult
    private func jumpToPage(_ pageIndex: Int, recordHistory: Bool) -> Bool {
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return false }

        let bounds = page.bounds(for: pdfView.displayBox)
        let target = ReadingPosition(
            pageIndex: pageIndex,
            point: NSPoint(x: bounds.minX, y: bounds.maxY)
        )
        return go(to: target, recordHistory: recordHistory)
    }

    private func historyAnchorPosition() -> ReadingPosition? {
        // Clip-bounds tracking keeps this exact for user scrolling, while
        // programmatic navigation pins the intentional point before PDFKit settles.
        if let displayed = displayedReadingPosition {
            return displayed
        }
        if let live = currentReadingPosition() {
            return live
        }
        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return nil }
        let bounds = page.bounds(for: pdfView.displayBox)
        return ReadingPosition(
            pageIndex: document.index(for: page),
            point: NSPoint(x: bounds.minX, y: bounds.maxY)
        )
    }

    private func recordNavigationHistoryBeforeJump() {
        // Always record intentional jumps (even while a prior history epoch is
        // still open for deferred PDFKit page-change events).
        guard let current = currentHistoryEntry() else { return }
        pushBackHistory(current)
        navigationForwardStack.removeAll(keepingCapacity: true)
    }

    /// Records the current session + exact viewport before a known cross-session
    /// destination replaces this pane.
    func recordCurrentPositionForNavigation() {
        recordNavigationHistoryBeforeJump()
    }

    /// Begins a native Pages / PDF link navigation. The origin is committed only
    /// after PDFKit reports a genuinely different page-point target.
    func beginExternalNavigation() {
        guard isNavigatingHistory == false,
              let origin = currentHistoryEntry() else { return }
        externalNavigationToken += 1
        pendingExternalNavigation = PendingExternalNavigation(
            token: externalNavigationToken,
            origin: origin
        )
    }

    /// Completes the native navigation after `super.mouseDown`; defer one turn so
    /// PDFKit can settle same-page destinations before comparing exact points.
    func commitExternalNavigation() {
        guard let pendingExternalNavigation else { return }
        let token = pendingExternalNavigation.token
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.completeExternalNavigation(token: token, target: self.liveHistoryEntry())
        }
    }

    private func completeExternalNavigation(
        token: Int? = nil,
        target: NavigationHistoryEntry?
    ) {
        guard let pending = pendingExternalNavigation,
              token == nil || pending.token == token else { return }
        pendingExternalNavigation = nil
        guard let target, target != pending.origin else { return }
        pushBackHistory(pending.origin)
        navigationForwardStack.removeAll(keepingCapacity: true)
    }

    private func currentHistoryEntry() -> NavigationHistoryEntry? {
        guard let sessionID = displayedSessionID,
              let position = historyAnchorPosition() else { return nil }
        return NavigationHistoryEntry(
            sessionID: historySessionID(for: sessionID),
            position: position
        )
    }

    private func liveHistoryEntry() -> NavigationHistoryEntry? {
        guard let sessionID = displayedSessionID,
              let position = currentReadingPosition() else { return nil }
        return NavigationHistoryEntry(
            sessionID: historySessionID(for: sessionID),
            position: position
        )
    }

    private func historySessionID(for displayedSessionID: UUID) -> UUID {
        guard let displayedSession = documentStore.session(for: displayedSessionID),
              let workspace = documentStore.windowWorkspace(for: windowID) else {
            return displayedSessionID
        }
        return workspace.sessionIDs.first { sessionID in
            documentStore.session(for: sessionID)?.url == displayedSession.url
        } ?? displayedSessionID
    }

    private func pushBackHistory(_ entry: NavigationHistoryEntry) {
        // Same-page points are distinct history stops; only an exact entry is duplicate.
        guard navigationBackStack.last != entry else { return }
        navigationBackStack.append(entry)
        if navigationBackStack.count > 100 {
            navigationBackStack.removeFirst()
        }
    }

    private func isHistoryEntryAvailable(_ entry: NavigationHistoryEntry) -> Bool {
        guard documentStore.session(for: entry.sessionID) != nil,
              let workspace = documentStore.windowWorkspace(for: windowID) else { return false }
        return workspace.sessionIDs.contains(entry.sessionID)
            || workspace.primarySessionID == entry.sessionID
            || workspace.secondarySessionID == entry.sessionID
    }

    @discardableResult
    private func playOwnedHistory(to entry: NavigationHistoryEntry) -> Bool {
        guard isHistoryEntryAvailable(entry) else { return false }
        let epoch = beginHistoryNavigation()
        defer { endHistoryNavigation(epoch) }

        var playbackSessionID = entry.sessionID
        if displayedSessionID != entry.sessionID {
            guard let resolvedSessionID = onHistorySessionNavigationRequested?(entry.sessionID),
                  displayedSessionID == resolvedSessionID else { return false }
            playbackSessionID = resolvedSessionID
        }
        guard documentStore.session(for: playbackSessionID) != nil,
              let document = pdfView.document,
              entry.position.pageIndex >= 0,
              entry.position.pageIndex < document.pageCount,
              let page = document.page(at: entry.position.pageIndex) else { return false }
        applyProgrammaticDestination(
            page: page,
            point: entry.position.point,
            storePosition: entry.position
        )
        return true
    }

    private func beginHistoryNavigation() -> Int {
        historyNavigationEpoch += 1
        return historyNavigationEpoch
    }

    /// Hold the epoch through deferred PDFKit page-change notifications so they
    /// cannot clear the forward stack right after Cmd+[.
    private func endHistoryNavigation(_ epoch: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.historyNavigationEpoch == epoch else { return }
            self.historyNavigationEpoch = 0
        }
    }

    private func applyProgrammaticDestination(
        page: PDFPage,
        point: NSPoint,
        storePosition: ReadingPosition
    ) {
        flushPendingReadingPositionWriteback()
        let destination = PDFDestination(page: page, at: point)
        // Suppress PDFViewPageChanged during jump: at go(to:) time the clipView
        // hasn't updated yet, so currentReadingPosition() would capture stale
        // coordinates and write them back to the store, causing a rollback.
        let wasApplying = isApplyingStoreState
        isApplyingStoreState = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            pdfView.go(to: destination)
        }
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        syncPDFMarginBackgroundAfterPDFKitLayout()
        recenterDocumentViewIfNeeded()
        restoreTopLeadingReadingPosition(page: page, point: point)
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        recenterDocumentViewIfNeeded()
        restoreTopLeadingReadingPosition(page: page, point: point)
        stabilizePDFScrollPosition()
        isApplyingStoreState = wasApplying

        displayedReadingPosition = storePosition
        if wasApplying == false,
           let session = targetSession(),
           session.id == displayedSessionID {
            switch session.scaleMode {
            case .fitWidth:
                pendingFitWidthSessionID = session.id
                lastAppliedFitBoundsWidth = -1
                view.needsLayout = true
            case .fitHeight:
                pendingFitHeightSessionID = session.id
                lastAppliedFitBoundsHeight = -1
                view.needsLayout = true
            case .manual:
                break
            }
            documentStore.updateReadingPosition(
                storePosition,
                scaleFactor: pdfView.scaleFactor,
                for: session.id
            )
        }
    }

    @discardableResult
    private func turnPage(by direction: Int) -> Bool {
        guard direction != 0,
              isAllPagesOverviewActive == false,
              let session = targetSession(),
              session.id == displayedSessionID,
              let document = pdfView.document,
              let currentPageIndex = currentPageIndexForNavigation(in: document) else { return false }

        let currentStop: Int
        let targetPageIndex: Int
        if session.displayMode.usesTwoUpLayout {
            currentStop = normalizedSpreadLead(
                currentPageIndex,
                pageCount: document.pageCount,
                displayMode: session.displayMode
            )
            let lastSpreadLead = normalizedSpreadLead(
                document.pageCount - 1,
                pageCount: document.pageCount,
                displayMode: session.displayMode
            )
            let adjacentLead = adjacentSpreadLead(
                from: currentStop,
                direction: direction,
                displayMode: session.displayMode
            )
            targetPageIndex = min(max(adjacentLead, 0), lastSpreadLead)
        } else {
            currentStop = currentPageIndex
            targetPageIndex = min(max(currentPageIndex + direction, 0), document.pageCount - 1)
        }
        guard targetPageIndex != currentStop else { return false }

        // Sequential page-turn is not a history stop (same as continuous scroll).
        if session.displayMode.usesBookLayout, direction < 0 {
            let pageIndex = trailingPageIndex(
                forSpreadLead: targetPageIndex,
                pageCount: document.pageCount
            )
            guard let page = document.page(at: pageIndex) else { return false }
            let bounds = page.bounds(for: pdfView.displayBox)
            return go(
                to: ReadingPosition(
                    pageIndex: pageIndex,
                    point: NSPoint(x: bounds.maxX, y: bounds.maxY)
                ),
                recordHistory: false
            )
        }
        return jumpToPage(targetPageIndex, recordHistory: false)
    }

    private func normalizedSpreadLead(
        _ pageIndex: Int,
        pageCount: Int,
        displayMode: ReaderDisplayMode
    ) -> Int {
        guard pageCount > 0 else { return 0 }
        let clamped = min(max(pageIndex, 0), pageCount - 1)
        if displayMode.usesBookLayout {
            guard clamped > 0 else { return 0 }
            return clamped.isMultiple(of: 2) ? clamped - 1 : clamped
        }
        return clamped.isMultiple(of: 2) ? clamped : clamped - 1
    }

    private func adjacentSpreadLead(
        from currentLead: Int,
        direction: Int,
        displayMode: ReaderDisplayMode
    ) -> Int {
        guard displayMode.usesBookLayout else { return currentLead + direction * 2 }
        if direction > 0 {
            return currentLead == 0 ? 1 : currentLead + 2
        }
        return currentLead <= 1 ? 0 : currentLead - 2
    }

    private func trailingPageIndex(forSpreadLead lead: Int, pageCount: Int) -> Int {
        guard lead > 0, lead + 1 < pageCount else { return lead }
        return lead + 1
    }

    private func currentPageIndexForNavigation(in document: PDFDocument) -> Int? {
        // Prefer the intentional displayed page over viewport sampling (can lag
        // right after a jump, especially in headless tests).
        if let displayed = displayedReadingPosition,
           displayed.pageIndex >= 0,
           displayed.pageIndex < document.pageCount {
            return displayed.pageIndex
        }
        if let position = currentReadingPosition(),
           position.pageIndex >= 0,
           position.pageIndex < document.pageCount {
            return position.pageIndex
        }

        guard let currentPage = pdfView.currentPage else { return nil }
        return document.index(for: currentPage)
    }

    var currentPageCount: Int { pdfView.document?.pageCount ?? 0 }

    var usesContinuousScrolling: Bool {
        guard let mode = targetSession()?.displayMode else { return false }
        return mode == .singlePageContinuous || mode == .twoUpContinuous
    }

    var usesBookLayout: Bool {
        targetSession()?.displayMode.usesBookLayout == true
    }

    var isAllPagesOverviewActive: Bool {
        !overviewGridView.isHidden
    }

    private var overviewSavedLeftSidebar: Bool?
    private var overviewSavedRightSidebar: Bool?
    /// `nil` = auto fit-all; otherwise manual cell width from zoom.
    private var overviewManualCellWidth: CGFloat?
    private var lastOverviewAppliedCellWidth: CGFloat = 140
    private var lastOverviewLayoutSignature: String = ""

    func setAllPagesOverviewActive(_ active: Bool) {
        guard active != isAllPagesOverviewActive else { return }
        guard !active || pdfView.document != nil else { return }

        if active {
            referencePreview.close()
            flushPendingReadingPositionWriteback()
            onOverviewPresentationDidChange?(true)
            overviewSavedLeftSidebar = documentStore.isLeftSidebarVisible(in: windowID)
            overviewSavedRightSidebar = documentStore.isRightSidebarVisible(in: windowID)
            documentStore.setLeftSidebarVisible(false, in: windowID)
            documentStore.setRightSidebarVisible(false, in: windowID)
            overviewManualCellWidth = nil
            lastOverviewLayoutSignature = ""
            overviewGridView.configure(document: pdfView.document)
            overviewGridView.isHidden = false
            pdfContainerView.isHidden = true
            syncReadingFocusAvailability()
            setEmptyStateVisible(false)
            applyOverviewSurfaceAppearance()
            reflowOverviewGrid(force: true)
        } else {
            overviewGridView.isHidden = true
            overviewGridView.releaseDocument()
            pdfContainerView.isHidden = false
            syncReadingFocusAvailability()
            overviewManualCellWidth = nil
            lastOverviewLayoutSignature = ""
            if targetSession()?.isBlank == false {
                setEmptyStateVisible(false)
            } else {
                showDefaultEmptyState()
            }
            if let left = overviewSavedLeftSidebar {
                documentStore.setLeftSidebarVisible(left, in: windowID)
            }
            if let right = overviewSavedRightSidebar {
                documentStore.setRightSidebarVisible(right, in: windowID)
            }
            overviewSavedLeftSidebar = nil
            overviewSavedRightSidebar = nil
            onOverviewPresentationDidChange?(false)
        }
    }

    @discardableResult
    func toggleAllPagesOverview() -> Bool {
        setAllPagesOverviewActive(!isAllPagesOverviewActive)
        return isAllPagesOverviewActive
    }

    func adjustOverviewZoom(scale: CGFloat) {
        guard isAllPagesOverviewActive else { return }
        let currentWidth = overviewManualCellWidth ?? lastOverviewAppliedCellWidth
        let nextWidth = min(
            max(currentWidth * scale, OverviewGridLayout.defaultMinCellWidth),
            OverviewGridLayout.defaultMaxCellWidth
        )
        overviewManualCellWidth = nextWidth
        lastOverviewLayoutSignature = ""
        reflowOverviewGrid(force: true)
    }

    private func reflowOverviewGrid(force: Bool = false) {
        guard isAllPagesOverviewActive else { return }

        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let edge = OverviewGridLayout.defaultEdgeInset
        let spacing = OverviewGridLayout.defaultCellSpacing
        let available = CGSize(
            width: max(bounds.width - edge * 2, 1),
            height: max(bounds.height - edge * 2, 1)
        )
        let pageCount = pdfView.document?.pageCount ?? 0
        let pageAspect = overviewPageAspect()

        let columns: Int
        let cellSize: CGSize

        if let manualWidth = overviewManualCellWidth {
            columns = OverviewGridLayout.columnsForManualWidth(
                pageCount: pageCount,
                availableWidth: available.width,
                cellWidth: manualWidth,
                cellSpacing: spacing
            )
            cellSize = CGSize(width: manualWidth, height: manualWidth * pageAspect)
        } else {
            let layout = OverviewGridLayout.computeFitAll(
                .init(
                    pageCount: pageCount,
                    availableSize: available,
                    pageAspect: pageAspect,
                    cellSpacing: spacing,
                    maxCellWidth: nil
                )
            )
            columns = layout.columns
            cellSize = layout.cellSize
        }

        let signature =
            "\(pageCount)|\(columns)|\(cellSize.width.rounded())|\(cellSize.height.rounded())|\(available.width.rounded())|\(available.height.rounded())"
        guard force || signature != lastOverviewLayoutSignature else { return }
        lastOverviewLayoutSignature = signature
        lastOverviewAppliedCellWidth = cellSize.width

        overviewGridView.configure(document: pdfView.document)
        overviewGridView.applyLayout(
            columns: columns,
            cellSize: cellSize,
            spacing: spacing,
            edgeInset: edge
        )
    }

    private func overviewPageAspect() -> CGFloat {
        guard let page = pdfView.document?.page(at: 0) else {
            return OverviewGridLayout.defaultPageAspect
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1 else {
            return OverviewGridLayout.defaultPageAspect
        }
        return max(bounds.height / bounds.width, 0.1)
    }

    private func applyOverviewSurfaceAppearance() {
        let isNightModeEnabled = readerState.isNightModeEnabled
        let pageBackground = isNightModeEnabled
            ? NightModeStyle.pageBackgroundColor
            : NightModeStyle.readerBackdropColor
        overviewGridView.applySurfaceBackground(pageBackground)
    }

    private func handleOverviewPageSelected(_ pageIndex: Int) {
        guard pdfView.document?.page(at: pageIndex) != nil else { return }
        _ = jumpToPage(pageIndex, recordHistory: true)
        setAllPagesOverviewActive(false)
    }

    var isNightModeEnabled: Bool {
        readerState.isNightModeEnabled
    }

    var isAnnotationModeEnabled: Bool {
        readerState.isAnnotationModeEnabled
    }

    var currentHighlightColor: HighlightColor {
        readerState.highlightColor
    }

    @discardableResult
    func triggerAnnotationShortcut(_ type: AnnotationMarkupType) -> Bool {
        guard presentationOverlay.isPresentationEnabled == false else { return false }
        if highlightCurrentSelection(type: type) {
            return true
        }

        readerState.annotationMode = type
        updateHighlightModeIndicator()
        return false
    }

    func exitHighlightMode() {
        readerState.annotationMode = nil
        updateHighlightModeIndicator()
    }

    func setPresentationEnabled(_ enabled: Bool) {
        loadViewIfNeeded()
        if enabled {
            exitHighlightMode()
            annotationInteraction.clearPreview()
            annotationInteraction.dismissCommentEditor()
            referencePreview.close()
        }
        presentationOverlay.setPresentationEnabled(enabled)
        syncReadingFocusAvailability()
    }

    func handlePresentationShortcut(_ event: NSEvent) -> Bool {
        guard isAllPagesOverviewActive == false, pdfView.isHidden == false else { return false }
        return presentationOverlay.handleKeyEvent(event)
    }

    func exitPresentationTool() -> Bool {
        guard presentationOverlay.isPresentationEnabled,
              presentationOverlay.tool != .pointer else { return false }
        presentationOverlay.selectTool(.pointer)
        return true
    }

    func setHighlightColor(_ color: HighlightColor) {
        readerState.highlightColor = color
        updateHighlightModeIndicator()
    }

    func setReadingFocusModeEnabled(_ enabled: Bool) {
        guard enabled != isReadingFocusModeEnabled else { return }
        isReadingFocusModeEnabled = enabled
        guard isViewLoaded else { return }
        syncReadingFocusAvailability()
    }

    @discardableResult
    func toggleHorizontalPanLock() -> Bool {
        setHorizontalPanLockEnabled(!isHorizontalPanLocked)
        return isHorizontalPanLocked
    }

    func setHorizontalPanLockEnabled(_ enabled: Bool) {
        guard let session = targetSession(), !session.isBlank else { return }
        documentStore.setHorizontalPanLocked(enabled, for: session.id)
    }

    private func applyHorizontalPanLock(_ enabled: Bool) {
        guard enabled != isHorizontalPanLocked else { return }
        isHorizontalPanLocked = enabled
        guard isViewLoaded else { return }
        (pdfClipView() as? PDFReaderClipView)?.forcedOriginX = nil
        configurePDFScrollBehaviorIfNeeded()
        if enabled { recenterDocumentViewIfNeeded() }
        updatePanLockIndicator()
    }

    private func rewriteScrollEventIfNeeded(_ event: NSEvent) -> NSEvent? {
        if handleVerticalPageScroll(event, pointerIsOverPDF: pointerEventIsOverPDFContent(event)) {
            return nil
        }
        let phase = event.phase
        let momentumPhase = event.momentumPhase
        let startsGesture = phase.contains(.mayBegin) || phase.contains(.began)
        let endsGesture = phase.contains(.ended) || phase.contains(.cancelled)
        let endsMomentum = momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled)
        let pointerIsOverPDF = pointerEventIsOverPDFContent(event)
        let displayMode = targetSession()?.displayMode

        if startsGesture {
            resetBookPageTurnState()
            bookScrollGestureOwnedByReader = pointerIsOverPDF && displayMode?.usesBookLayout == true
        }

        let isPhaseLessBookInput = phase.isEmpty
            && momentumPhase.isEmpty
            && pointerIsOverPDF
            && displayMode?.usesBookLayout == true
        let isGestureLifecycleEvent = phase.isEmpty == false || momentumPhase.isEmpty == false
        let handlesOwnedGesture = isGestureLifecycleEvent
            && bookScrollGestureOwnedByReader
            && (displayMode?.usesBookLayout == true
                || consumeBookDirectScrollUntilEnd
                || consumeBookMomentumUntilEnd)
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        var consumedBookScroll = false
        if handlesOwnedGesture || isPhaseLessBookInput {
            if event.modifierFlags.intersection(blockedModifiers).isEmpty {
                consumedBookScroll = handleBookScroll(
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                    hasScrollPhase: isGestureLifecycleEvent,
                    isMomentum: momentumPhase.isEmpty == false,
                    timestamp: event.timestamp
                )
            } else {
                resetBookPageTurnInput()
            }
        }

        if phase.contains(.cancelled) {
            resetBookPageTurnState()
        } else if endsGesture {
            consumeBookDirectScrollUntilEnd = false
        }
        if endsMomentum {
            resetBookPageTurnState()
        }
        if consumedBookScroll {
            return nil
        }

        guard shouldLockHorizontalPan else { return event }
        guard pointerEventIsOverPDFContent(event) else { return event }

        // Preview-style Option/Command+scroll zoom would scale around the
        // cursor and shift the locked X. Drop it with pinch.
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            return nil
        }

        // Horizontal-dominant or pure-horizontal: discard entirely so PDFKit never pans on X.
        let horizontal = abs(event.scrollingDeltaX)
        let vertical = abs(event.scrollingDeltaY)
        if ScrollWheelHorizontalStripper.isHorizontalOnly(event) || horizontal > vertical {
            return nil
        }
        guard ScrollWheelHorizontalStripper.hasHorizontalComponent(event) else { return event }
        return ScrollWheelHorizontalStripper.verticalOnly(from: event) ?? event
    }

    /// Keep PDFKit's wheel-driven page transition out of discrete layouts.
    /// Page changes use the same destination route as J/K; remaining momentum
    /// belongs to the old page and must not move the new one.
    private func handleVerticalPageScroll(_ event: NSEvent, pointerIsOverPDF: Bool) -> Bool {
        let phase = event.phase
        let momentum = event.momentumPhase
        let mode = targetSession()?.displayMode
        if phase.contains(.mayBegin) || phase.contains(.began) {
            resetVerticalPageGesture()
            ownsVerticalPageGesture = pointerIsOverPDF && (mode == .singlePage || mode == .twoUp)
                && event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        }
        guard ownsVerticalPageGesture, !phase.isEmpty || !momentum.isEmpty else { return false }
        defer {
            if phase.contains(.cancelled) || momentum.contains(.ended) || momentum.contains(.cancelled) {
                resetVerticalPageGesture()
            }
        }
        if didTurnPageInVerticalGesture { return true }
        guard mode == .singlePage || mode == .twoUp,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            resetVerticalPageGesture()
            return false
        }
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return false }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return true }
        onFocusRequested?()
        if scrollVertically(by: -delta) {
            verticalPageTurnAccumulator = 0
            return true
        }

        // Inertia may finish scrolling within a page, but never starts a turn.
        guard momentum.isEmpty, !phase.contains(.ended), !phase.contains(.cancelled) else { return true }
        if (verticalPageTurnAccumulator < 0) != (delta < 0) {
            verticalPageTurnAccumulator = 0
        }
        verticalPageTurnAccumulator += delta
        guard abs(verticalPageTurnAccumulator) >= 48 else { return true }
        let direction = delta < 0 ? 1 : -1
        let didTurn = turnPage(by: direction)
        if !didTurn { _ = onPageBoundaryRequested(direction) }
        // A boundary navigation can replace the session and reset input state.
        ownsVerticalPageGesture = true
        didTurnPageInVerticalGesture = true
        verticalPageTurnAccumulator = 0
        return true
    }

    private func resetVerticalPageGesture() {
        ownsVerticalPageGesture = false
        verticalPageTurnAccumulator = 0
        didTurnPageInVerticalGesture = false
    }

    @discardableResult
    private func handleBookScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        hasScrollPhase: Bool,
        isMomentum: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        if hasPreciseScrollingDeltas == false,
           isMomentum == false,
           lastBookPageTurnScrollTimestamp.map({ timestamp - $0 > 0.3 }) == true {
            resetBookPageTurnState()
        }
        if hasScrollPhase, isMomentum, consumeBookMomentumUntilEnd {
            return true
        }
        if hasScrollPhase, isMomentum == false, consumeBookDirectScrollUntilEnd {
            return true
        }

        guard let displayMode = targetSession()?.displayMode,
              displayMode.usesBookLayout else { return false }

        let horizontal = abs(deltaX)
        let vertical = abs(deltaY)
        if hasScrollPhase == false {
            bookScrollAxis = .undecided
        }
        if bookScrollAxis == .undecided, max(horizontal, vertical) > 0.5 {
            if horizontal > vertical * 1.2 {
                bookScrollAxis = .horizontal
            } else if vertical > horizontal * 1.2 {
                bookScrollAxis = .vertical
            }
        }
        guard bookScrollAxis == .horizontal else {
            if hasScrollPhase == false {
                resetBookPageTurnInput()
                bookScrollAxis = .undecided
            }
            return false
        }
        guard horizontal > 0.01 else { return true }

        let direction = deltaX < 0 ? 1 : -1
        guard canTurnBookPageAfterHorizontalPan(direction: direction) else {
            resetBookPageTurnInput()
            return false
        }

        let normalizedDelta = hasPreciseScrollingDeltas ? deltaX : deltaX * 48
        let directionChanged = bookPageTurnScrollAccumulator != 0
            && (bookPageTurnScrollAccumulator < 0) != (normalizedDelta < 0)
        if directionChanged {
            bookPageTurnScrollAccumulator = 0
        }
        lastBookPageTurnScrollTimestamp = timestamp
        bookPageTurnScrollAccumulator += normalizedDelta

        let threshold: CGFloat = 48
        guard abs(bookPageTurnScrollAccumulator) >= threshold else { return true }
        if hasScrollPhase,
           let lastBookPageTurnTimestamp,
           timestamp - lastBookPageTurnTimestamp < 0.18 {
            bookPageTurnScrollAccumulator = 0
            return true
        }
        onFocusRequested?()
        let didTurnLocally = turnPage(by: direction)
        let didCrossDocument = didTurnLocally == false && onPageBoundaryRequested(direction)
        bookPageTurnScrollAccumulator = 0
        if didTurnLocally || didCrossDocument {
            lastBookPageTurnScrollTimestamp = timestamp
            lastBookPageTurnTimestamp = timestamp
            if hasScrollPhase {
                consumeBookMomentumUntilEnd = true
                if displayMode.allowsContinuousBookPageTurn == false || didCrossDocument {
                    consumeBookDirectScrollUntilEnd = true
                }
                if didCrossDocument {
                    bookScrollGestureOwnedByReader = true
                }
            }
        }
        return true
    }

    private func canTurnBookPageAfterHorizontalPan(direction: Int) -> Bool {
        guard let clipView = pdfClipView(), let documentView = pdfDocumentView() else { return true }
        let overflowX = max(documentView.frame.width - clipView.bounds.width, 0)
        guard overflowX > 1 else { return true }
        return direction > 0
            ? clipView.bounds.origin.x >= overflowX - 1
            : clipView.bounds.origin.x <= 1
    }

    private func resetBookPageTurnInput() {
        bookPageTurnScrollAccumulator = 0
        lastBookPageTurnScrollTimestamp = nil
    }

    private func resetBookPageTurnState() {
        resetBookPageTurnInput()
        lastBookPageTurnTimestamp = nil
        bookScrollAxis = .undecided
        bookScrollGestureOwnedByReader = false
        consumeBookDirectScrollUntilEnd = false
        consumeBookMomentumUntilEnd = false
    }

    private func rewriteMagnificationEventIfPanLocked(_ event: NSEvent) -> NSEvent? {
        guard shouldLockHorizontalPan else { return event }
        guard pointerEventIsOverPDFContent(event) else { return event }
        return nil
    }

    private func pointerEventIsOverPDFContent(_ event: NSEvent) -> Bool {
        guard isAllPagesOverviewActive == false,
              pdfContainerView.isHidden == false,
              pdfView.isHidden == false,
              let window = event.window,
              window === view.window else { return false }
        let pointInPDF = pdfView.convert(event.locationInWindow, from: nil)
        return pdfView.bounds.contains(pointInPDF)
    }

    func setReadingFocusSettings(_ settings: ReadingFocusSettings) {
        guard settings != readingFocusSettings else { return }
        readingFocusSettings = settings
        guard isViewLoaded else { return }
        pdfContainerView.setReadingFocusSettings(settings)
    }

    func setReadingFocusControlsPresented(_ isPresented: Bool, anchorPointInView: NSPoint? = nil) {
        let overlay = pdfContainerView.readingFocusOverlay
        let preferredPoint = anchorPointInView.map {
            pdfContainerView.readingFocusOverlay.convert($0, from: view)
        }
        let focusPoint: NSPoint?
        if isPresented {
            focusPoint = overlay.focusLocation
                ?? preferredPoint.flatMap { readingFocusPageBounds(at: $0) == nil ? nil : $0 }
                ?? visibleReadingFocusPageCenter()
        } else {
            focusPoint = nil
        }
        overlay.setFocusPinned(isPresented, at: focusPoint)
    }

    @discardableResult
    func addOrEditComment() -> Bool {
        annotationInteraction.addOrEditComment()
    }

    func presentCommentEditor(for group: DocumentHighlightGroup) {
        annotationInteraction.presentCommentEditor(for: group)
    }

    func dismissCommentEditor() {
        annotationInteraction.dismissCommentEditor()
    }

    @discardableResult
    func removeHighlightUnderCursor() -> Bool {
        annotationInteraction.removeHighlightUnderCursor()
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        if presentationOverlay.isPresentationEnabled {
            presentationOverlay.undoCurrentPage()
            return true
        }
        guard let session = targetSession(),
              session.id == displayedSessionID else { return false }
        let didUndo = documentStore.undoLastHighlight(for: session.id)
        if didUndo {
            pdfView.needsDisplay = true
        }
        return didUndo
    }

    var hasUndoableHighlight: Bool {
        if presentationOverlay.isPresentationEnabled {
            return presentationOverlay.strokes.contains { $0.page === pdfView.currentPage }
        }
        guard let sessionID = targetSessionID else { return false }
        return documentStore.hasUndoableHighlight(for: sessionID)
    }

    var hasRedoableHighlight: Bool {
        guard presentationOverlay.isPresentationEnabled == false else { return false }
        guard let sessionID = targetSessionID else { return false }
        return documentStore.hasRedoableHighlight(for: sessionID)
    }

    @discardableResult
    func redoLastHighlight() -> Bool {
        guard presentationOverlay.isPresentationEnabled == false else { return false }
        guard let session = targetSession(),
              session.id == displayedSessionID else { return false }
        let didRedo = documentStore.redoLastHighlight(for: session.id)
        if didRedo {
            pdfView.needsDisplay = true
        }
        return didRedo
    }

    func toggleNightMode() {
        readerState.isNightModeEnabled.toggle()
        applyReaderAppearance()
    }

    func refreshThemeAppearance() {
        syncNightModeFromSystem()
        lastThemeFilterSignature = nil
        applyReaderAppearance()
    }

    func saveAnnotations() throws {
        guard let sessionID = targetSessionID else { return }
        try documentStore.saveAnnotations(for: sessionID)
    }

    @discardableResult
    func search(for query: String) -> Bool {
        documentStore.updateSearch(
            query: query,
            scope: findBarView.scope,
            options: findBarView.searchOptions,
            in: windowID
        )
        return documentStore.searchSnapshot(in: windowID).totalMatches > 0
    }

    var isFindBarVisible: Bool {
        findBarView.isHidden == false
    }

    func showFindBar(scope: SearchScope? = nil) {
        guard let container = view as NSView? else { return }
        let targetScope = scope ?? documentStore.searchScope(in: windowID)
        let targetOptions = documentStore.searchOptions(in: windowID)
        let selectedQuery = selectedSearchQuery()
        let query = selectedQuery ?? documentStore.searchQuery(in: windowID)
        documentStore.updateSearch(
            query: query,
            scope: targetScope,
            options: targetOptions,
            in: windowID
        )
        if let selectedQuery {
            lastSubmittedSearchKey = SubmittedSearchKey(
                query: selectedQuery,
                scope: targetScope,
                options: targetOptions
            )
        } else if query.isEmpty == false,
                  documentStore.searchSnapshot(in: windowID).totalMatches > 0 {
            // Re-opening Find with an existing query should treat Enter as "next".
            lastSubmittedSearchKey = SubmittedSearchKey(
                query: query,
                scope: targetScope,
                options: targetOptions
            )
        }
        onFocusRequested?()
        if findBarView.isHidden {
            findBarView.isHidden = false
            pdfContainerTopConstraint?.isActive = false
            pdfContainerTopConstraint = pdfContainerView.topAnchor.constraint(equalTo: findBarView.bottomAnchor)
            pdfContainerTopConstraint?.isActive = true
            container.layoutSubtreeIfNeeded()
        }
        findBarView.setScope(documentStore.searchScope(in: windowID))
        findBarView.setSearchOptions(documentStore.searchOptions(in: windowID))
        findBarView.setQuery(documentStore.searchQuery(in: windowID))
        syncFindBarStatus()
        findBarView.focusQueryField()
    }

    var selectedText: String? {
        guard let text = pdfView.currentSelection?.string.map(PDFTextSanitizer.sanitize),
              text.isEmpty == false else { return nil }
        return text
    }

    private func selectedSearchQuery() -> String? {
        selectedText
    }

    func hideFindBar() {
        guard let container = view as NSView? else { return }
        guard findBarView.isHidden == false else { return }
        findBarView.isHidden = true
        pdfContainerTopConstraint?.isActive = false
        pdfContainerTopConstraint = pdfContainerView.topAnchor.constraint(equalTo: container.topAnchor)
        pdfContainerTopConstraint?.isActive = true
        container.layoutSubtreeIfNeeded()
        documentStore.clearSearch(in: windowID)
        clearSearchResults()
        lastSubmittedSearchKey = nil
        pendingFindNavigationAfterSearch = nil
        pdfView.window?.makeFirstResponder(pdfView)
    }

    @discardableResult
    func findNextMatch() -> Bool {
        guard documentStore.searchSnapshot(in: windowID).totalMatches > 0 else { return false }
        onFindActionRequested?(.activateNext)
        return true
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        guard documentStore.searchSnapshot(in: windowID).totalMatches > 0 else { return false }
        onFindActionRequested?(.activatePrevious)
        return true
    }

    func updateFindStatus(matchIndex: Int?, totalMatches: Int) {
        guard isFindBarVisible else { return }
        findBarView.setStatus(matchIndex: matchIndex, totalMatches: totalMatches)
    }

    private func syncFindBarStatus() {
        guard isFindBarVisible else { return }
        findBarView.setQuery(documentStore.searchQuery(in: windowID))
        findBarView.setScope(documentStore.searchScope(in: windowID))
        findBarView.setStatus(
            matchIndex: nil,
            totalMatches: documentStore.searchSnapshot(in: windowID).totalMatches
        )
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.affects(windowID: windowID) else { return }
        if notification.documentStoreChange.containsOnly(.search) {
            syncFindBarStatus()
            completePendingFindNavigationIfNeeded()
            return
        }
        guard notification.isOnlySidebarChromeChange == false else { return }
        // Store notifications are synchronous; do not sample PDFKit while a
        // programmatic document/viewport restore is still settling.
        guard isApplyingStoreState == false else { return }
        // Cmd+[ / ] already moved the view and set displayedReadingPosition to the
        // intentional target. Do not sample lagging live geometry over that target.
        if isNavigatingHistory {
            if notification.isOnlyReadingPositionChange == false {
                syncFindBarStatus()
            }
            return
        }
        if syncDisplayedStateWithoutRefreshIfPossible() == false {
            refreshDisplayedDocument()
        }
        if notification.documentStoreChange.contains(.annotations) {
            for page in pdfView.visiblePages {
                pdfView.annotationsChanged(on: page)
            }
            annotationInteraction.scheduleOverlayRefresh()
        }
        // Page/zoom writeback does not change find results; skip search recompute.
        if notification.isOnlyReadingPositionChange == false {
            syncFindBarStatus()
        }
        if notification.documentStoreChange.contains(.search) {
            completePendingFindNavigationIfNeeded()
        }
    }

    private func completePendingFindNavigationIfNeeded() {
        guard let pendingKey = pendingFindNavigationAfterSearch else { return }
        let snapshot = documentStore.searchSnapshot(in: windowID)
        guard snapshot.isSearching == false,
              snapshot.query == pendingKey.query,
              snapshot.scope == pendingKey.scope,
              snapshot.options == pendingKey.options else { return }
        pendingFindNavigationAfterSearch = nil
        guard snapshot.totalMatches > 0 else { return }
        onFindActionRequested?(.activateNext)
    }

    @objc
    private func handlePDFViewPageChanged(_ notification: Notification) {
        annotationInteraction.scheduleOverlayRefresh()
        presentationOverlay.refreshGeometry()
        referencePreview.close()
        annotationInteraction.clearPreview()
        markPDFPrivateViewTreeDirty()
        guard isApplyingStoreState == false,
              isNavigatingHistory == false,
              let session = targetSession(),
              session.id == displayedSessionID else { return }

        // A page boundary is a durable navigation stop. Commit any trailing
        // scroll sample from the previous page before recording the new page.
        flushPendingReadingPositionWriteback()

        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return }
        let pageIndex = document.index(for: page)
        // Keep mid-page scroll in continuous mode (page taller than viewport).
        let position: ReadingPosition
        if let live = currentReadingPosition(), live.pageIndex == pageIndex {
            position = live
        } else {
            let bounds = page.bounds(for: pdfView.displayBox)
            position = ReadingPosition(
                pageIndex: pageIndex,
                point: NSPoint(x: bounds.minX, y: bounds.maxY)
            )
        }

        displayedReadingPosition = position
        documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        completeExternalNavigation(
            target: NavigationHistoryEntry(sessionID: session.id, position: position)
        )
    }

    @objc
    private func handlePDFViewScaleChanged(_ notification: Notification) {
        annotationInteraction.scheduleOverlayRefresh()
        presentationOverlay.refreshGeometry()
        markPDFPrivateViewTreeDirty()
        guard isApplyingProgrammaticScale == false,
              isApplyingStoreState == false,
              let session = targetSession(),
              session.id == displayedSessionID else { return }

        flushPendingReadingPositionWriteback()

        // PDFKit uses the same notification for user zoom and layout-driven scale
        // changes. Trackpad pinch is pinned to manual by the magnification
        // monitor / currentEvent; geometry changes keep the requested fit mode.
        if isUserMagnificationEvent(NSApp.currentEvent) {
            guard shouldLockHorizontalPan == false else { return }
            beginUserMagnification()
        } else {
            switch session.scaleMode {
            case .fitWidth:
                pendingFitWidthSessionID = session.id
                lastAppliedFitBoundsWidth = -1
                view.needsLayout = true
                return
            case .fitHeight:
                pendingFitHeightSessionID = session.id
                lastAppliedFitBoundsHeight = -1
                view.needsLayout = true
                return
            case .manual:
                break
            }
        }

        documentStore.setScaleMode(.manual, scaleFactor: pdfView.scaleFactor, for: session.id)

        if let position = currentReadingPosition() {
            documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        }
    }

    private func handleMagnificationEventIfNeeded(_ event: NSEvent) {
        guard shouldLockHorizontalPan == false,
              isAllPagesOverviewActive == false,
              pdfView.isHidden == false,
              let window = pdfView.window,
              event.window === window else { return }
        let point = pdfView.convert(event.locationInWindow, from: nil)
        guard pdfView.bounds.contains(point) else { return }
        beginUserMagnification()
    }

    private func isUserMagnificationEvent(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .magnify, .smartMagnify:
            return true
        case .scrollWheel:
            // Preview-style Option/Command+scroll zoom. Only consulted when
            // PDFKit has already changed scaleFactor.
            return event.modifierFlags.contains(.option)
                || event.modifierFlags.contains(.command)
        default:
            return false
        }
    }

    private func beginUserMagnification() {
        guard shouldLockHorizontalPan == false,
              let session = targetSession(),
              session.id == displayedSessionID else { return }
        pendingFitWidthSessionID = nil
        pendingFitHeightSessionID = nil
        lastAppliedFitBoundsWidth = 0
        lastAppliedFitBoundsHeight = 0
        displayedScaleMode = .manual
        guard session.scaleMode != .manual else { return }
        documentStore.setScaleMode(.manual, scaleFactor: pdfView.scaleFactor, for: session.id)
    }

    private func applyHighlightOnMouseUpIfNeeded(event: NSEvent) {
        guard presentationOverlay.isPresentationEnabled == false,
              readerState.isAnnotationModeEnabled,
              isApplyingHighlightSelection == false,
              let window = pdfView.window,
              event.window === window else { return }

        let locationInPDF = pdfView.convert(event.locationInWindow, from: nil)
        guard pdfView.bounds.contains(locationInPDF) else { return }
        guard let annotationMode = readerState.annotationMode else { return }
        _ = highlightCurrentSelection(type: annotationMode)
    }

    private func requestFocusIfNeeded(event: NSEvent) {
        guard let window = view.window,
              event.window === window else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        guard view.bounds.contains(location) else { return }
        onFocusRequested?()
    }

    private func showDefaultEmptyState() {
        emptyStateWordmark.isHidden = false
        emptyStateErrorLabel.stringValue = ""
        emptyStateErrorLabel.isHidden = true
        emptyStateContainer.isHidden = true
        pdfView.isHidden = true
    }

    private func showErrorEmptyState(_ message: String) {
        emptyStateErrorLabel.stringValue = message
        emptyStateErrorLabel.isHidden = false
        setEmptyStateVisible(true)
    }

    private func setEmptyStateVisible(_ visible: Bool) {
        emptyStateWordmark.isHidden = true
        emptyStateContainer.isHidden = !visible
        if visible {
            pdfView.isHidden = true
        }
    }

    private func refreshDisplayedDocument() {
        guard isViewLoaded else { return }
        defer {
            annotationInteraction.activeSessionID = displayedSessionID
            presentationOverlay.refreshGeometry()
            annotationInteraction.scheduleOverlayRefresh()
        }

        if displayedSessionID != targetSessionID {
            resetVerticalPageGesture()
            applyHorizontalPanLock(false)
            presentationOverlay.resetDocument()
            referencePreview.close()
            annotationInteraction.sessionDidChange()
            resetBookPageTurnState()
        }

        guard let session = targetSession() else {
            setAllPagesOverviewActive(false)
            referencePreview.close()
            pdfView.setReaderDocument(nil)
            markPDFPrivateViewTreeDirty(resetRoots: true)
            pdfView.isHidden = true
            syncReadingFocusAvailability()
            showDefaultEmptyState()
            displayedSessionID = nil
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
            pdfView.highlightedSelections = nil
            pdfView.currentSelection = nil
            hideSwitchTitleToast(immediately: true)
            return
        }

        if session.isBlank {
            setAllPagesOverviewActive(false)
            referencePreview.close()
            pdfView.setReaderDocument(nil)
            markPDFPrivateViewTreeDirty(resetRoots: true)
            pdfView.isHidden = true
            syncReadingFocusAvailability()
            showDefaultEmptyState()
            displayedSessionID = session.id
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
            pdfView.highlightedSelections = nil
            pdfView.currentSelection = nil
            hideSwitchTitleToast(immediately: true)
            return
        }

        let previousSessionID = displayedSessionID
        let isNewSession = displayedSessionID != session.id
        let liveReadingPosition = isNewSession ? nil : liveReadingPositionForReload()
        let document: PDFDocument
        do {
            document = try documentStore.pdfDocument(for: session.id)
        } catch {
            setAllPagesOverviewActive(false)
            referencePreview.close()
            pdfView.setReaderDocument(nil)
            markPDFPrivateViewTreeDirty(resetRoots: true)
            pdfView.isHidden = true
            syncReadingFocusAvailability()
            showErrorEmptyState(error.localizedDescription)
            displayedSessionID = session.id
            return
        }
        let refreshedSession = targetSession() ?? session
        let documentChanged = isNewSession || pdfView.document !== document
        let reloadedLivePosition = documentChanged && !isNewSession
            ? liveReadingPosition.flatMap { clampedReadingPosition($0, in: document) }
            : nil
        let targetReadingPosition = reloadedLivePosition ?? refreshedSession.lastReadPosition

        isApplyingStoreState = true
        defer { isApplyingStoreState = false }

        if documentChanged {
            applyHorizontalPanLock(false)
            presentationOverlay.resetDocument()
            referencePreview.close()
            resetBookPageTurnState()
            pdfView.setReaderDocument(document)
            markPDFPrivateViewTreeDirty(resetRoots: true)
            displayedSessionID = refreshedSession.id
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
        }

        let displayModeChanged = applyDisplayModeIfNeeded(refreshedSession)
        applyScaleIfNeeded(refreshedSession)
        applyReadingPositionIfNeeded(
            targetReadingPosition,
            force: documentChanged || displayModeChanged
        )
        applyHorizontalPanLock(refreshedSession.isHorizontalPanLocked)
        if let reloadedLivePosition,
           reloadedLivePosition != refreshedSession.lastReadPosition {
            documentStore.updateReadingPosition(
                reloadedLivePosition,
                scaleFactor: pdfView.scaleFactor,
                for: refreshedSession.id
            )
        }
        configurePDFScrollBehaviorIfNeeded()
        applyReaderAppearance()

        if isAllPagesOverviewActive {
            overviewGridView.configure(document: document)
            reflowOverviewGrid(force: isNewSession)
            pdfContainerView.isHidden = true
            syncReadingFocusAvailability()
            setEmptyStateVisible(false)
        } else {
            pdfView.isHidden = false
            syncReadingFocusAvailability()
            setEmptyStateVisible(false)
        }
        if isNewSession, previousSessionID != nil {
            showSwitchTitleToast(refreshedSession.title)
        }
    }

    private func syncDisplayedStateWithoutRefreshIfPossible() -> Bool {
        guard let session = targetSession(),
              session.id == displayedSessionID,
              let document = documentStore.loadedPDFDocument(for: session.id),
              pdfView.document === document,
              displayedDisplayMode == session.displayMode else { return false }

        if isHorizontalPanLocked != session.isHorizontalPanLocked {
            applyHorizontalPanLock(session.isHorizontalPanLocked)
            return true
        }

        guard let livePosition = currentReadingPosition() else { return false }

        if let displayedReadingPosition,
           readingPosition(displayedReadingPosition, differsFrom: session.lastReadPosition),
           readingPosition(livePosition, differsFrom: session.lastReadPosition) {
            return false
        }

        guard let liveScaleMode = liveScaleMode(for: session, liveScale: pdfView.scaleFactor) else { return false }

        if syncLiveViewportStateToStoreIfNeeded(for: session, livePosition: livePosition, liveScaleMode: liveScaleMode) {
            return true
        }

        displayedScaleMode = liveScaleMode
        displayedReadingPosition = livePosition
        return true
    }

    private func liveScaleMode(for session: DocumentSession, liveScale: CGFloat) -> ReaderScaleMode? {
        switch session.scaleMode {
        case .manual:
            return .manual
        case .fitHeight:
            guard let targetScaleFactor = fitHeightScaleFactor(for: session) else { return nil }
            if abs(liveScale - targetScaleFactor) <= 0.001 {
                return .fitHeight
            }
            return nil
        case .fitWidth:
            guard let targetScaleFactor = fitWidthScaleFactor(for: session) else { return nil }
            if abs(liveScale - targetScaleFactor) <= 0.001 {
                return .fitWidth
            }
            return nil
        }
    }

    private func syncLiveViewportStateToStoreIfNeeded(
        for session: DocumentSession,
        livePosition: ReadingPosition,
        liveScaleMode: ReaderScaleMode
    ) -> Bool {
        let liveScale = pdfView.scaleFactor
        let needsModeSync = session.scaleMode != liveScaleMode
        let needsScaleSync = abs(session.zoomScale - liveScale) > 0.001

        // After programmatic jump / history navigate, displayed + store already agree
        // on the intentional target while the clip view can still report the previous
        // page for a beat. Block only that lagging position writeback; scale may still sync.
        let livePositionIsLagging =
            displayedReadingPosition.map {
                readingPosition($0, differsFrom: session.lastReadPosition) == false
                    && readingPosition(livePosition, differsFrom: session.lastReadPosition)
            } ?? false
        let needsPositionSync =
            livePositionIsLagging == false
            && readingPosition(session.lastReadPosition, differsFrom: livePosition)

        guard needsModeSync || needsScaleSync || needsPositionSync else {
            return livePositionIsLagging
        }

        displayedScaleMode = liveScaleMode
        if needsPositionSync {
            displayedReadingPosition = livePosition
        }

        if needsModeSync {
            documentStore.setScaleMode(liveScaleMode, scaleFactor: liveScale, for: session.id)
        }
        if needsScaleSync || needsPositionSync {
            let position = needsPositionSync ? livePosition : session.lastReadPosition
            documentStore.updateReadingPosition(position, scaleFactor: liveScale, for: session.id)
        }
        return true
    }

    private func readingPosition(_ lhs: ReadingPosition, differsFrom rhs: ReadingPosition) -> Bool {
        guard lhs.pageIndex == rhs.pageIndex else { return true }
        return abs(lhs.point.x - rhs.point.x) > 0.5 || abs(lhs.point.y - rhs.point.y) > 0.5
    }

    func applySearchResults(_ selections: [PDFSelection], selectedMatchIndex: Int?) {
        pdfView.highlightedSelections = selections
        guard let selectedMatchIndex,
              selections.indices.contains(selectedMatchIndex) else {
            // Leave currentSelection alone when no explicit index — find-next may
            // have just called go(to:) and a store refresh must not wipe it.
            return
        }
        pdfView.setCurrentSelection(selections[selectedMatchIndex], animate: false)
    }

    func clearSearchResults() {
        pdfView.highlightedSelections = nil
        pdfView.currentSelection = nil
    }

    func go(to selection: PDFSelection, recordHistory: Bool = true, setSelection: Bool = true) {
        let targetPosition: ReadingPosition?
        if let page = selection.pages.first, let document = pdfView.document {
            let bounds = selection.bounds(for: page)
            targetPosition = ReadingPosition(
                pageIndex: document.index(for: page),
                point: NSPoint(x: bounds.minX, y: bounds.maxY)
            )
        } else {
            targetPosition = nil
        }
        if let targetPosition, displayedReadingPosition == targetPosition {
            if setSelection {
                pdfView.setCurrentSelection(selection, animate: false)
            } else {
                pdfView.currentSelection = nil
            }
            return
        }
        if recordHistory {
            recordNavigationHistoryBeforeJump()
        }
        isApplyingStoreState = true
        if setSelection {
            pdfView.setCurrentSelection(selection, animate: true)
        } else {
            pdfView.currentSelection = nil
        }
        pdfView.go(to: selection)
        if setSelection == false {
            pdfView.currentSelection = nil
        }
        isApplyingStoreState = false
        if let position = targetPosition {
            displayedReadingPosition = position
            if let session = targetSession(), session.id == displayedSessionID {
                documentStore.updateReadingPosition(
                    position,
                    scaleFactor: pdfView.scaleFactor,
                    for: session.id
                )
            }
        } else if let session = targetSession(),
                  session.id == displayedSessionID,
                  let position = currentReadingPosition() {
            documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
            displayedReadingPosition = position
        }
    }

    func focus(on highlight: DocumentHighlightGroup, showPulse: Bool = true) {
        if let selection = highlight.primarySelection {
            go(to: selection, setSelection: false)
            if showPulse {
                annotationInteraction.showFocusPulse(for: highlight)
            }
            return
        }

        guard pdfView.document?.page(at: highlight.pageIndex) != nil else { return }
        _ = jumpToPage(highlight.pageIndex, recordHistory: true)
        if showPulse {
            annotationInteraction.showFocusPulse(for: highlight)
        }
    }

    @discardableResult
    private func applyDisplayModeIfNeeded(_ session: DocumentSession) -> Bool {
        guard displayedDisplayMode != session.displayMode else { return false }

        resetBookPageTurnState()
        markPDFPrivateViewTreeDirty()
        resetVerticalPageGesture()
        if session.displayMode.usesBookLayout, isHorizontalPanLocked {
            applyHorizontalPanLock(false)
        }
        pdfView.displayDirection = session.displayMode.displayDirection
        pdfView.displaysAsBook = session.displayMode.displaysAsBook
        pdfView.displayMode = session.displayMode.pdfDisplayMode
        displayedDisplayMode = session.displayMode
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        recenterDocumentViewIfNeeded()
        return true
    }

    private func applyScaleIfNeeded(_ session: DocumentSession) {
        switch session.scaleMode {
        case .fitHeight:
            if pdfView.bounds.height > 0 {
                pendingFitHeightSessionID = nil
                lastAppliedFitBoundsHeight = pdfView.bounds.height
                applyFitHeight(for: session)
            } else {
                pendingFitHeightSessionID = session.id
            }
        case .fitWidth:
            if pdfView.bounds.width > 0 {
                pendingFitWidthSessionID = nil
                lastAppliedFitBoundsWidth = pdfView.bounds.width
                applyFitWidth(for: session)
            } else {
                pendingFitWidthSessionID = session.id
            }
        case .manual:
            pendingFitWidthSessionID = nil
            pendingFitHeightSessionID = nil
            lastAppliedFitBoundsWidth = 0
            lastAppliedFitBoundsHeight = 0
            guard displayedScaleMode != .manual || abs(pdfView.scaleFactor - session.zoomScale) > 0.001 else { return }
            applyProgrammaticScale(
                session.zoomScale,
                preserveViewportCenter: displayedSessionID == session.id
            )
        }

        displayedScaleMode = session.scaleMode
    }

    private func applyReadingPositionIfNeeded(_ readingPosition: ReadingPosition, force: Bool) {
        guard force || displayedReadingPosition != readingPosition else { return }
        guard let document = pdfView.document,
              let page = document.page(at: readingPosition.pageIndex) else { return }

        applyProgrammaticDestination(
            page: page,
            point: readingPosition.point,
            storePosition: readingPosition
        )
    }

    private func clampedReadingPosition(
        _ readingPosition: ReadingPosition,
        in document: PDFDocument
    ) -> ReadingPosition? {
        guard document.pageCount > 0 else { return nil }
        let pageIndex = min(max(readingPosition.pageIndex, 0), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else { return nil }
        if pageIndex == readingPosition.pageIndex {
            return ReadingPosition(pageIndex: pageIndex, point: readingPosition.point)
        }
        return .pageTop(
            pageIndex: pageIndex,
            pageBounds: page.bounds(for: pdfView.displayBox)
        )
    }

    private func liveReadingPositionForReload() -> ReadingPosition? {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return currentReadingPosition() }
        let pageIndex = document.index(for: page)
        guard document.pageCount > 0, (0..<document.pageCount).contains(pageIndex) else {
            return currentReadingPosition()
        }
        if let position = currentReadingPosition(),
           let session = targetSession(),
           positionBelongsToCurrentSpread(
               position,
               currentPageIndex: pageIndex,
               session: session,
               document: document
           ) {
            return position
        }
        let bounds = page.bounds(for: pdfView.displayBox)
        return ReadingPosition(
            pageIndex: pageIndex,
            point: NSPoint(x: bounds.minX, y: bounds.maxY)
        )
    }

    private func applyFitWidth(for session: DocumentSession) {
        guard let scaleFactor = fitWidthScaleFactor(for: session) else {
            pendingFitWidthSessionID = session.id
            displayedScaleMode = .fitWidth
            documentStore.setScaleMode(.fitWidth, scaleFactor: session.zoomScale, for: session.id)
            return
        }
        guard shouldApplyFitWidth(scaleFactor, for: session) else {
            recordFitWidthBounds()
            displayedScaleMode = .fitWidth
            documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
            return
        }
        applyProgrammaticScale(scaleFactor, preserveViewportCenter: true)
        recordFitWidthBounds()
        displayedScaleMode = .fitWidth
        documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
    }

    private func recordFitWidthBounds() {
        lastAppliedFitBoundsWidth = pdfView.bounds.width
        lastAppliedFitBoundsHeight = pdfView.bounds.height
    }

    private func applyFitHeight(for session: DocumentSession) {
        guard let scaleFactor = fitHeightScaleFactor(for: session) else {
            pendingFitHeightSessionID = session.id
            displayedScaleMode = .fitHeight
            documentStore.setScaleMode(.fitHeight, scaleFactor: session.zoomScale, for: session.id)
            return
        }
        applyProgrammaticScale(scaleFactor, preserveViewportCenter: true)
        lastAppliedFitBoundsHeight = pdfView.bounds.height
        displayedScaleMode = .fitHeight
        documentStore.setScaleMode(.fitHeight, scaleFactor: scaleFactor, for: session.id)
    }

    func shouldApplyFitWidth(_ targetScaleFactor: CGFloat, for session: DocumentSession) -> Bool {
        guard displayedSessionID == session.id, displayedScaleMode == .fitWidth else { return true }

        // Avoid re-running viewport-anchor restoration on plain reading-position
        // updates when the fit-width target scale is already in effect.
        return abs(pdfView.scaleFactor - targetScaleFactor) > 0.001
    }

    private func applyProgrammaticScale(
        _ scaleFactor: CGFloat,
        preserveViewportCenter: Bool = false,
        viewportAnchor: PDFViewportAnchor? = nil
    ) {
        let viewportAnchor = viewportAnchor ?? (preserveViewportCenter ? captureViewportAnchor() : nil)
        isApplyingProgrammaticScale = true
        // Explicit zoom may reposition the viewport; lock the resulting X afterward.
        syncHorizontalPanLockConstraint()
        defer {
            isApplyingProgrammaticScale = false
            syncHorizontalPanLockConstraint()
        }
        pdfView.scaleFactor = scaleFactor
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        syncPDFMarginBackgroundAfterPDFKitLayout()
        recenterDocumentViewIfNeeded()
        if let viewportAnchor {
            // PDFKit may reshuffle frames after the first scroll; one settle pass.
            restoreViewportAnchor(viewportAnchor)
            pdfView.layoutDocumentView()
            pdfView.layoutSubtreeIfNeeded()
            recenterDocumentViewIfNeeded()
            restoreViewportAnchor(viewportAnchor)
        }
    }

    private func fitWidthScaleFactor(for session: DocumentSession) -> CGFloat? {
        guard let document = pdfView.document else { return nil }
        let pages = spreadPages(for: session, in: document)
        guard let leadPage = pages.first else { return nil }
        if session.displayMode.usesBookLayout {
            return bookSpreadScaleFactor(for: pages)
        }

        let currentScale = max(pdfView.scaleFactor, 0.001)
        let normalizedRowWidth = pdfView.rowSize(for: leadPage).width / currentScale
        guard normalizedRowWidth > 0 else { return nil }

        let availableWidth = max(pdfClipView()?.frame.width ?? pdfView.bounds.width, 1)
        let unclamped = availableWidth / normalizedRowWidth
        return min(max(unclamped, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    }

    private func bookSpreadScaleFactor(for pages: [PDFPage]) -> CGFloat? {
        let pageSizes = pages.map { $0.bounds(for: pdfView.displayBox).size }
        guard let firstSize = pageSizes.first,
              firstSize.width > 0,
              firstSize.height > 0 else { return nil }

        let spreadWidth: CGFloat
        let spreadHeight: CGFloat
        if pageSizes.count == 1 {
            // Reserve the missing slot for the cover and an unpaired final page.
            spreadWidth = firstSize.width * 2 + Self.bookSpreadGap
            spreadHeight = firstSize.height
        } else {
            spreadWidth = pageSizes.reduce(0) { $0 + $1.width } + Self.bookSpreadGap
            spreadHeight = pageSizes.map(\.height).max() ?? firstSize.height
        }
        guard spreadWidth > 0, spreadHeight > 0 else { return nil }

        let clipFrame = pdfClipView()?.frame ?? pdfView.bounds
        let availableWidth = max(clipFrame.width - Self.bookFitHorizontalInset * 2, 1)
        let availableHeight = max(clipFrame.height - Self.bookFitVerticalInset * 2, 1)
        let unclamped = min(
            availableWidth / spreadWidth,
            availableHeight / spreadHeight
        )
        return min(max(unclamped, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    }

    private func fitHeightScaleFactor(for session: DocumentSession) -> CGFloat? {
        guard let document = pdfView.document else { return nil }
        let pages = spreadPages(for: session, in: document)
        guard let leadPage = pages.first else { return nil }
        let currentScale = max(pdfView.scaleFactor, 0.001)
        let normalizedRowHeight = pdfView.rowSize(for: leadPage).height / currentScale
        guard normalizedRowHeight > 0 else { return nil }

        let availableHeight = max(pdfClipView()?.frame.height ?? pdfView.bounds.height, 1)
        let unclamped = availableHeight / normalizedRowHeight
        return min(max(unclamped, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    }

    private func fitPageScaleFactor() -> CGFloat? {
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) else { return nil }
        let currentScale = max(pdfView.scaleFactor, 0.001)
        let normalizedRowSize = NSSize(
            width: pdfView.rowSize(for: page).width / currentScale,
            height: pdfView.rowSize(for: page).height / currentScale
        )
        guard normalizedRowSize.width > 0, normalizedRowSize.height > 0 else { return nil }

        let clipFrame = pdfClipView()?.frame ?? pdfView.bounds
        let availableWidth = max(clipFrame.width, 1)
        let availableHeight = max(clipFrame.height, 1)
        let unclamped = min(
            availableWidth / normalizedRowSize.width,
            availableHeight / normalizedRowSize.height
        )
        return min(max(unclamped, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    }

    private func spreadPages(for session: DocumentSession, in document: PDFDocument) -> [PDFPage] {
        guard session.displayMode.usesTwoUpLayout else {
            guard let page = document.page(at: session.currentPageIndex) else { return [] }
            return [page]
        }

        let startIndex = normalizedSpreadLead(
            session.currentPageIndex,
            pageCount: document.pageCount,
            displayMode: session.displayMode
        )
        let firstPage = document.page(at: startIndex)
        let secondPage = session.displayMode.usesBookLayout && startIndex == 0
            ? nil
            : document.page(at: startIndex + 1)
        return [firstPage, secondPage].compactMap { $0 }
    }

    private func currentReadingPosition() -> ReadingPosition? {
        if let visiblePosition = visibleReadingPosition() {
            return visiblePosition
        }

        if let destination = pdfView.currentDestination,
           let page = destination.page,
           let document = pdfView.document {
            return ReadingPosition(
                pageIndex: document.index(for: page),
                point: destination.point
            )
        }

        guard let page = pdfView.currentPage,
              let document = pdfView.document else { return nil }
        return .pageTop(
            pageIndex: document.index(for: page),
            pageBounds: page.bounds(for: pdfView.displayBox)
        )
    }

    private func visibleReadingPosition() -> ReadingPosition? {
        guard let clipView = pdfClipView(),
              let documentView = pdfDocumentView(),
              let document = pdfView.document,
              clipView.bounds.width > 0,
              clipView.bounds.height > 0 else { return nil }

        let visibleTopLeadingInDocument = NSPoint(
            x: clipView.bounds.minX + 1,
            y: clipView.bounds.maxY - 1
        )
        let visibleTopLeadingInPDF = pdfView.convert(visibleTopLeadingInDocument, from: documentView)
        guard let page = pdfView.page(for: visibleTopLeadingInPDF, nearest: true) else { return nil }
        let pointOnPage = pdfView.convert(visibleTopLeadingInPDF, to: page)
        return ReadingPosition(pageIndex: document.index(for: page), point: pointOnPage)
    }

    @discardableResult
    private func scrollByViewportFraction(_ fraction: CGFloat) -> Bool {
        guard isAllPagesOverviewActive == false,
              let clipView = pdfClipView() else { return false }

        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        syncPDFMarginBackgroundAfterPDFKitLayout()
        return scrollVertically(by: clipView.bounds.height * fraction)
    }

    private func scrollVertically(by delta: CGFloat) -> Bool {
        guard let scrollView = pdfScrollView(), let clipView = pdfClipView() else { return false }
        var targetBounds = clipView.bounds
        targetBounds.origin.y += delta
        targetBounds = clipView.constrainBoundsRect(targetBounds)
        guard abs(targetBounds.origin.y - clipView.bounds.origin.y) > 0.5 else { return false }

        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func targetSession() -> DocumentSession? {
        guard let targetSessionID else { return nil }
        return documentStore.session(for: targetSessionID)
    }

    private func pdfScrollView() -> NSScrollView? {
        if let cachedPDFScrollView, cachedPDFScrollView.superview != nil {
            return cachedPDFScrollView
        }
        let scrollView = pdfView.subviews.first { $0 is NSScrollView } as? NSScrollView
        cachedPDFScrollView = scrollView
        return scrollView
    }

    private func pdfScrollBackgroundViews() -> [NSView] {
        guard let scrollView = pdfScrollView() else { return [] }
        let documentView = pdfDocumentView()
        var matches: [NSView] = []
        var pending = scrollView.subviews
        while let view = pending.popLast() {
            if String(describing: type(of: view)).contains("ContentBackgroundView") {
                matches.append(view)
            }
            // Background tiles live in scroll chrome. Excluding PDFKit's
            // document subtree makes this walk tiny and independent of pages.
            guard view !== documentView else { continue }
            pending.append(contentsOf: view.subviews.filter { $0 !== documentView })
        }
        cachedPDFScrollBackgroundViews = matches
        return matches
    }

    private func configurePDFScrollBehaviorIfNeeded() {
        guard let scrollView = pdfScrollView() else { return }
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        installReaderClipViewIfNeeded(in: scrollView)
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        if observedPDFClipView !== clipView {
            if let observedPDFClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedPDFClipView
                )
            }
            observedPDFClipView = clipView
            lastObservedPDFClipBounds = clipView.bounds
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePDFClipViewBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
        syncHorizontalPanLockConstraint()
        syncPDFMarginBackgroundAfterPDFKitLayout()
    }

    private func installReaderClipViewIfNeeded(in scrollView: NSScrollView) {
        if scrollView.contentView is PDFReaderClipView { return }

        let previousClip = scrollView.contentView
        let documentView = previousClip.documentView
        let replacement = PDFReaderClipView(frame: previousClip.bounds)
        replacement.drawsBackground = previousClip.drawsBackground
        replacement.backgroundColor = previousClip.backgroundColor
        replacement.postsBoundsChangedNotifications = true
        scrollView.contentView = replacement
        if let documentView {
            scrollView.documentView = documentView
        }
        markPDFPrivateViewTreeDirty(resetRoots: true)
    }

    private func syncHorizontalPanLockConstraint() {
        guard let clipView = pdfClipView() as? PDFReaderClipView else { return }
        guard shouldLockHorizontalPan, !isApplyingProgrammaticScale,
              let documentView = pdfDocumentView() else {
            clipView.forcedOriginX = nil
            return
        }

        let overflowX = max(documentView.frame.width - clipView.bounds.width, 0)
        let currentOriginX = clipView.forcedOriginX ?? clipView.bounds.origin.x
        let clampedX = min(max(currentOriginX, 0), overflowX)
        // Ignore subpixel overflow flicker from PDFKit layout so the locked
        // X does not chatter by a fraction of a point.
        if clipView.forcedOriginX == nil || abs(clampedX - currentOriginX) > 0.5 {
            clipView.forcedOriginX = clampedX
        }
    }

    @objc
    private func handlePDFClipViewBoundsDidChange(_ notification: Notification) {
        annotationInteraction.scheduleOverlayRefresh()
        presentationOverlay.refreshGeometry()
        guard let clipView = notification.object as? NSClipView else { return }
        referencePreview.close()
        annotationInteraction.clearPreview()
        let previousBounds = lastObservedPDFClipBounds
        lastObservedPDFClipBounds = clipView.bounds
        guard isApplyingScrollClamp == false else { return }
        recenterDocumentViewIfNeeded()
        pdfContainerView.readingFocusOverlay.refreshFocusGeometry()

        guard isApplyingStoreState == false,
              isNavigatingHistory == false,
              let previousBounds,
              abs(previousBounds.width - clipView.bounds.width) <= 0.5,
              abs(previousBounds.height - clipView.bounds.height) <= 0.5,
              abs(previousBounds.origin.x - clipView.bounds.origin.x) > 0.5
                || abs(previousBounds.origin.y - clipView.bounds.origin.y) > 0.5,
              let session = targetSession(),
              session.id == displayedSessionID,
              let currentPage = pdfView.currentPage,
              let document = pdfView.document,
              let position = currentReadingPosition() else { return }
        guard positionBelongsToCurrentSpread(
            position,
            currentPageIndex: document.index(for: currentPage),
            session: session,
            document: document
        ) else { return }
        displayedReadingPosition = position
        scheduleReadingPositionWriteback(
            position,
            scaleFactor: pdfView.scaleFactor,
            for: session.id
        )
        // Navigation history reflects the live viewport immediately even though
        // persistence is trailing-throttled.
        completeExternalNavigation(
            target: NavigationHistoryEntry(sessionID: session.id, position: position)
        )
    }

    private func scheduleReadingPositionWriteback(
        _ position: ReadingPosition,
        scaleFactor: CGFloat,
        for sessionID: UUID
    ) {
        pendingReadingPositionWriteback = PendingReadingPositionWriteback(
            sessionID: sessionID,
            position: position,
            scaleFactor: scaleFactor
        )
        readingPositionWritebackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingReadingPositionWriteback()
            }
        }
        readingPositionWritebackWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.readingPositionWritebackDelay,
            execute: workItem
        )
    }

    private func flushPendingReadingPositionWriteback() {
        readingPositionWritebackWorkItem?.cancel()
        readingPositionWritebackWorkItem = nil
        guard let pending = pendingReadingPositionWriteback else { return }
        pendingReadingPositionWriteback = nil
        guard documentStore.session(for: pending.sessionID) != nil else { return }
        let wasApplyingStoreState = isApplyingStoreState
        isApplyingStoreState = true
        documentStore.updateReadingPosition(
            pending.position,
            scaleFactor: pending.scaleFactor,
            for: pending.sessionID
        )
        isApplyingStoreState = wasApplyingStoreState
        completeExternalNavigation(
            target: NavigationHistoryEntry(
                sessionID: pending.sessionID,
                position: pending.position
            )
        )
    }

    private func positionBelongsToCurrentSpread(
        _ position: ReadingPosition,
        currentPageIndex: Int,
        session: DocumentSession,
        document: PDFDocument
    ) -> Bool {
        guard session.displayMode.usesTwoUpLayout else {
            return position.pageIndex == currentPageIndex
        }
        return normalizedSpreadLead(
            position.pageIndex,
            pageCount: document.pageCount,
            displayMode: session.displayMode
        ) == normalizedSpreadLead(
            currentPageIndex,
            pageCount: document.pageCount,
            displayMode: session.displayMode
        )
    }

    private func pdfClipView() -> NSClipView? {
        pdfScrollView()?.contentView
    }

    private func pdfDocumentView() -> NSView? {
        let documentView = pdfClipView()?.documentView
        if cachedPDFDocumentView !== documentView {
            cachedPDFDocumentView = documentView
            needsPDFPrivateViewDiscovery = true
            lastThemeFilterSignature = nil
        }
        return documentView
    }

    private func pdfPageViews() -> [NSView] {
        discoverPDFPrivateViewsIfNeeded()
        return cachedPDFPageViews
    }

    private func discoverPDFPrivateViewsIfNeeded() {
        guard needsPDFPrivateViewDiscovery else { return }
        needsPDFPrivateViewDiscovery = false

        cachedPDFScrollBackgroundViews.removeAll(keepingCapacity: true)
        cachedPDFPageViews.removeAll(keepingCapacity: true)
        guard let scrollView = pdfScrollView() else {
            pdfPrivateViewGeneration += 1
            return
        }

        var pending = scrollView.subviews
        while let view = pending.popLast() {
            let typeName = String(describing: type(of: view))
            if typeName.contains("ContentBackgroundView") {
                cachedPDFScrollBackgroundViews.append(view)
            }
            if typeName.contains("PDFPageView") {
                cachedPDFPageViews.append(view)
            }
            pending.append(contentsOf: view.subviews)
        }
        pdfPrivateViewGeneration += 1
    }

    private func markPDFPrivateViewTreeDirty(resetRoots: Bool = false) {
        needsPDFPrivateViewDiscovery = true
        pdfPrivateViewDiscoveryPassesRemaining = 2
        cachedPDFScrollBackgroundViews.removeAll(keepingCapacity: true)
        cachedPDFPageViews.removeAll(keepingCapacity: true)
        lastThemeFilterSignature = nil
        if resetRoots {
            cachedPDFScrollView = nil
            cachedPDFDocumentView = nil
        }
    }

    private func syncPDFMarginBackground() {
        let appearance = NSApp.effectiveAppearance
        discoverPDFPrivateViewsIfNeeded()
        appearance.performAsCurrentDrawingAppearance {
            let backgroundColor = NightModeStyle.pageBackgroundColor.usingColorSpace(.sRGB)
                ?? NightModeStyle.pageBackgroundColor

            if let scrollView = pdfScrollView() {
                scrollView.wantsLayer = true
                scrollView.drawsBackground = false
                scrollView.backgroundColor = backgroundColor
                scrollView.layer?.backgroundColor = NSColor.clear.cgColor
            }

            for backgroundView in pdfScrollBackgroundViews() {
                backgroundView.isHidden = true
                backgroundView.wantsLayer = true
                backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            }

            if let clipView = pdfClipView() {
                clipView.wantsLayer = true
                clipView.drawsBackground = false
                clipView.backgroundColor = backgroundColor
                clipView.layer?.backgroundColor = NSColor.clear.cgColor
            }

            if let documentView = pdfDocumentView() {
                documentView.wantsLayer = true
                documentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    private func syncPDFMarginBackgroundAfterPDFKitLayout() {
        if pdfPrivateViewDiscoveryPassesRemaining > 0 {
            pdfPrivateViewDiscoveryPassesRemaining -= 1
            needsPDFPrivateViewDiscovery = true
        }
        syncPDFMarginBackground()
        schedulePDFLayoutMaintenance()
    }

    private func schedulePDFLayoutMaintenance() {
        guard isPDFLayoutMaintenanceScheduled == false else { return }
        isPDFLayoutMaintenanceScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPDFLayoutMaintenanceScheduled = false
            self.applyThemeFilter()
            self.pdfContainerView.readingFocusOverlay.refreshFocusGeometry()
            self.presentationOverlay.refreshGeometry()
            self.scheduleDocumentRecentering()
            self.syncPDFMarginBackground()
        }
    }

    private func recenterDocumentViewIfNeeded() {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView() else { return }

        // Horizontal: center whenever the document is narrower than the viewport.
        // Vertical: center single pages and Book spreads whenever they fit.
        let isSinglePage = displayedDisplayMode == .singlePage
        let centersBookSpread = displayedDisplayMode?.usesBookLayout == true
        let centersVertically = isSinglePage || centersBookSpread
        let fitsHorizontally = documentView.frame.width <= clipView.bounds.width + 0.5
        let fitsVertically = centersVertically
            && documentView.frame.height <= clipView.bounds.height + 0.5
        let bookChromeOffset: CGFloat
        if centersBookSpread, let window = view.window {
            let standardContentHeight = window.contentRect(forFrameRect: window.frame).height
            bookChromeOffset = max(window.frame.height - standardContentHeight, 0) * 0.5
        } else {
            bookChromeOffset = 0
        }
        let targetMinX = fitsHorizontally
            ? (clipView.bounds.width - documentView.frame.width) * 0.5
            : 0
        // Oversized single-page docs stay top-aligned (origin Y = 0); continuous
        // modes leave PDFKit's Y alone so vertical scrolling is undisturbed.
        let targetMinY: CGFloat
        if fitsVertically {
            targetMinY = (clipView.bounds.height - documentView.frame.height) * 0.5
                - bookChromeOffset
        } else if centersVertically {
            targetMinY = 0
        } else {
            targetMinY = documentView.frame.minY
        }

        var frame = documentView.frame
        var shouldUpdateFrame = false
        if abs(frame.minX - targetMinX) > 0.5 {
            frame.origin.x = targetMinX
            shouldUpdateFrame = true
        }
        if centersVertically, abs(frame.minY - targetMinY) > 0.5 {
            frame.origin.y = targetMinY
            shouldUpdateFrame = true
        }
        if shouldUpdateFrame {
            documentView.frame = frame
        }
        // Keep forced X in sync with current geometry before any clamp scroll.
        syncHorizontalPanLockConstraint()

        var targetOrigin = clipView.bounds.origin
        if fitsHorizontally {
            targetOrigin.x = 0
        } else if shouldLockHorizontalPan,
                  let forcedOriginX = (clipView as? PDFReaderClipView)?.forcedOriginX {
            targetOrigin.x = forcedOriginX
        }
        if fitsVertically {
            targetOrigin.y = 0
        }
        let clampThreshold: CGFloat = shouldLockHorizontalPan ? 0.01 : 0.5
        let targetBounds = clipView.constrainBoundsRect(NSRect(origin: targetOrigin, size: clipView.bounds.size))
        guard abs(targetBounds.origin.x - clipView.bounds.origin.x) > clampThreshold ||
                abs(targetBounds.origin.y - clipView.bounds.origin.y) > clampThreshold else { return }

        isApplyingScrollClamp = true
        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
        isApplyingScrollClamp = false
    }

    private func scheduleDocumentRecentering() {
        guard isDocumentRecenteringScheduled == false,
              displayedDisplayMode == .singlePage
                || displayedDisplayMode?.usesBookLayout == true else { return }
        isDocumentRecenteringScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDocumentRecenteringScheduled = false
            self.recenterDocumentViewIfNeeded()
        }
    }

    private var shouldLockHorizontalPan: Bool {
        isHorizontalPanLocked && isAllPagesOverviewActive == false
    }

    private func stabilizePDFScrollPosition() {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView() else { return }

        let backingScale = max(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
        let alignedOrigin = NSPoint(
            x: (clipView.bounds.origin.x * backingScale).rounded() / backingScale,
            y: (clipView.bounds.origin.y * backingScale).rounded() / backingScale
        )
        let targetBounds = clipView.constrainBoundsRect(
            NSRect(origin: alignedOrigin, size: clipView.bounds.size)
        )

        guard abs(targetBounds.origin.x - clipView.bounds.origin.x) > 0.001 ||
                abs(targetBounds.origin.y - clipView.bounds.origin.y) > 0.001 else { return }
        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func scrollToDocumentEnd() {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView(),
              let session = targetSession(),
              let document = pdfView.document,
              document.pageCount > 0,
              let page = document.page(at: document.pageCount - 1) else { return }
        let bounds = page.bounds(for: pdfView.displayBox)
        let position = ReadingPosition.pageBottom(
            pageIndex: document.pageCount - 1,
            pageBounds: bounds
        )
        let proposed = NSRect(
            x: clipView.bounds.origin.x,
            y: documentView.bounds.maxY,
            width: clipView.bounds.width,
            height: clipView.bounds.height
        )
        let target = clipView.constrainBoundsRect(proposed)
        let wasApplying = isApplyingStoreState
        isApplyingStoreState = true
        clipView.scroll(to: target.origin)
        scrollView.reflectScrolledClipView(clipView)
        isApplyingStoreState = wasApplying
        displayedReadingPosition = position
        documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
    }

    private func captureViewportAnchor() -> PDFViewportAnchor? {
        guard pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return nil }
        let viewportCenter = NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        guard let page = pdfView.page(for: viewportCenter, nearest: true) else { return nil }
        let pagePoint = pdfView.convert(viewportCenter, to: page)
        return PDFViewportAnchor(page: page, pagePoint: pagePoint)
    }

    private func restoreViewportAnchor(_ anchor: PDFViewportAnchor) {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView() else { return }

        let pointInView = pdfView.convert(anchor.pagePoint, from: anchor.page)
        let pointInDoc = documentView.convert(pointInView, from: pdfView)
        let desiredOrigin = NSPoint(
            x: pointInDoc.x - clipView.bounds.width * 0.5,
            y: pointInDoc.y - clipView.bounds.height * 0.5
        )
        let targetBounds = clipView.constrainBoundsRect(
            NSRect(origin: desiredOrigin, size: clipView.bounds.size)
        )
        guard abs(targetBounds.origin.x - clipView.bounds.origin.x) > 0.5 ||
                abs(targetBounds.origin.y - clipView.bounds.origin.y) > 0.5 else { return }
        isApplyingScrollClamp = true
        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
        isApplyingScrollClamp = false
    }

    private func restoreTopLeadingReadingPosition(page: PDFPage, point: NSPoint) {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView() else { return }

        let pointInPDF = pdfView.convert(point, from: page)
        let pointInDocument = documentView.convert(pointInPDF, from: pdfView)
        let desiredOrigin = NSPoint(
            x: pointInDocument.x - 1,
            y: pointInDocument.y - clipView.bounds.height + 1
        )
        let targetBounds = clipView.constrainBoundsRect(
            NSRect(origin: desiredOrigin, size: clipView.bounds.size)
        )
        guard abs(targetBounds.origin.x - clipView.bounds.origin.x) > 0.5
                || abs(targetBounds.origin.y - clipView.bounds.origin.y) > 0.5 else { return }
        isApplyingScrollClamp = true
        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
        isApplyingScrollClamp = false
    }


    @discardableResult
    private func highlightCurrentSelection(type: AnnotationMarkupType = .highlight) -> Bool {
        createHighlightFromCurrentSelection(type: type) != nil
    }

    private func createHighlightFromCurrentSelection(
        type: AnnotationMarkupType = .highlight
    ) -> DocumentHighlightGroup? {
        guard let session = targetSession(),
              session.id == displayedSessionID,
              let selection = pdfView.currentSelection,
              HighlightService.selectionContainsText(selection) else { return nil }

        isApplyingHighlightSelection = true
        defer { isApplyingHighlightSelection = false }

        let appliedRecords = HighlightService.applyHighlight(
            to: selection,
            color: NightModeStyle.highlightColor(
                for: readerState.highlightColor,
                appearance: NSApp.effectiveAppearance
            ),
            type: type
        )
        guard appliedRecords.isEmpty == false else { return nil }

        flushPendingReadingPositionWriteback()
        documentStore.noteHighlightsAdded(appliedRecords, for: session.id)
        pdfView.currentSelection = nil
        return HighlightService.buildHighlightGroups(from: appliedRecords).first
    }

    private func applyReaderAppearance() {
        annotationInteraction.refreshThemeAppearance()
        presentationOverlay.refreshThemeAppearance()
        let isNightModeEnabled = readerState.isNightModeEnabled
        let appearance = NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let pageBackground = isNightModeEnabled ? NightModeStyle.pageBackgroundColor : NightModeStyle.readerBackdropColor
            let usesFlatPDFChrome = NightModeStyle.prefersFlatPDFChrome(for: appearance)
            let showsPageShadows = !isNightModeEnabled && !usesFlatPDFChrome
            if pdfView.pageShadowsEnabled != showsPageShadows {
                pdfView.pageShadowsEnabled = showsPageShadows
            }
            view.layer?.backgroundColor = pageBackground.cgColor
            pdfView.backgroundColor = .clear
            pdfView.layer?.backgroundColor = NSColor.clear.cgColor
            highlightModeLabel.textColor = NightModeStyle.secondaryTextColor
            emptyStateErrorLabel.textColor = NightModeStyle.secondaryTextColor
            emptyStateWordmark.textColor = NightModeStyle.secondaryTextColor.withAlphaComponent(0.14)
        }
        applyOverviewSurfaceAppearance()
        if emptyStateContainer.isHidden, pdfView.document != nil {
            pdfView.isHidden = false
        }
        pdfContainerView.setNightModeEnabled(isNightModeEnabled)
        findBarView.refreshChromeColors()
        updateSwitchTitleToastAppearance()
        applyThemeFilter()
        syncPDFMarginBackgroundAfterPDFKitLayout()
        updateHighlightModeIndicator()
        updatePanLockIndicator()
    }

    private func syncReadingFocusAvailability() {
        presentationOverlay.refreshGeometry()
        let isAvailable = isAllPagesOverviewActive == false
            && presentationOverlay.isPresentationEnabled == false
            && isReadingFocusModeEnabled
            && pdfContainerView.isHidden == false
            && pdfView.isHidden == false
            && pdfView.document != nil
        pdfContainerView.setReadingFocusEnabled(isAvailable)
    }

    private func readingFocusPageBounds(at point: NSPoint) -> NSRect? {
        let overlay = pdfContainerView.readingFocusOverlay
        let pointInPDF = pdfView.convert(point, from: overlay)
        guard pdfView.bounds.contains(pointInPDF),
              let page = pdfView.page(for: pointInPDF, nearest: false) else { return nil }
        let pageBoundsInPDF = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        return overlay.convert(pageBoundsInPDF, from: pdfView)
    }

    private func visibleReadingFocusPageCenter() -> NSPoint? {
        let overlay = pdfContainerView.readingFocusOverlay
        let page = pdfView.currentPage
            ?? pdfView.page(
                for: NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY),
                nearest: true
            )
        guard let page else { return nil }
        let pageBoundsInPDF = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        let pageBounds = overlay.convert(pageBoundsInPDF, from: pdfView)
        let visibleBounds = pageBounds.intersection(overlay.bounds)
        guard visibleBounds.isNull == false,
              visibleBounds.width > 0,
              visibleBounds.height > 0 else { return nil }
        return NSPoint(x: visibleBounds.midX, y: visibleBounds.midY)
    }

    private func showSwitchTitleToast(_ title: String) {
        switchTitleToastHideWorkItem?.cancel()
        switchTitleToastLabel.stringValue = title
        updateSwitchTitleToastAppearance()
        switchTitleToastView.isHidden = false
        switchTitleToastView.alphaValue = 1

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.hideSwitchTitleToast(immediately: false)
            }
        }
        switchTitleToastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: workItem)
    }

    private func hideSwitchTitleToast(immediately: Bool) {
        switchTitleToastHideWorkItem?.cancel()
        switchTitleToastHideWorkItem = nil

        guard immediately == false else {
            switchTitleToastView.alphaValue = 0
            switchTitleToastView.isHidden = true
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            switchTitleToastView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.switchTitleToastView.isHidden = true
            }
        }
    }

    private func updateSwitchTitleToastAppearance() {
        let appearance = switchTitleToastView.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switchTitleToastView.layer?.backgroundColor = NightModeStyle.paneBackgroundColor
                .withAlphaComponent(isDark ? 0.86 : 0.92).cgColor
            switchTitleToastLabel.textColor = NightModeStyle.primaryTextColor
        }
    }

    private func updateHighlightModeIndicator() {
        let isEnabled = readerState.isAnnotationModeEnabled
        highlightModeIndicator.isHidden = !isEnabled
        let color = readerState.highlightColor
        highlightModeLabel.stringValue = "\(readerState.annotationMode?.modeTitle ?? "Highlight") · Esc"
        highlightModeColorDot.layer?.backgroundColor = NightModeStyle.highlightColor(
            for: color,
            appearance: NSApp.effectiveAppearance
        ).withAlphaComponent(0.85).cgColor
    }

    private func updatePanLockIndicator() {
        panLockIndicator.isHidden = !isHorizontalPanLocked
        panLockIndicator.stringValue = "H-lock · L"
        panLockIndicator.textColor = NightModeStyle.secondaryTextColor
    }

    private func applyThemeFilter() {
        referencePreview.applyTheme()
        discoverPDFPrivateViewsIfNeeded()
        let appearance = NSApp.effectiveAppearance
        let signature = "\(appearance.name.rawValue)|\(readerState.isNightModeEnabled)|\(pdfPrivateViewGeneration)"
        guard signature != lastThemeFilterSignature else { return }
        lastThemeFilterSignature = signature
        let filters = NightModeStyle.makePDFContentFilters(for: NSApp.effectiveAppearance)
        pdfView.contentFilters = filters
        pdfDocumentView()?.contentFilters = []
        for pageView in pdfPageViews() {
            pageView.contentFilters = []
            pageView.layer?.filters = []
        }
    }

}

extension ReaderViewController {
    var testingSwitchTitleToastTitle: String {
        switchTitleToastLabel.stringValue
    }

    var testingSwitchTitleToastIsVisible: Bool {
        switchTitleToastView.isHidden == false && switchTitleToastView.alphaValue > 0
    }

    var testingEmptyStateIsVisible: Bool {
        emptyStateContainer.isHidden == false
    }

    var testingEmptyStateError: String? {
        emptyStateErrorLabel.isHidden ? nil : emptyStateErrorLabel.stringValue
    }

    var testingPDFViewIsHidden: Bool {
        pdfView.isHidden
    }

    var testingOverviewRetainsDocument: Bool {
        overviewGridView.testingHasDocument
    }

    var testingLocalEventMonitoringIsInstalled: Bool {
        leftMouseDownMonitor != nil
            && leftMouseUpMonitor != nil
            && panLockScrollMonitor != nil
            && magnificationMonitor != nil
    }

    func testingBeginUserMagnification() {
        beginUserMagnification()
    }

    var testingReadingFocusIsEnabled: Bool {
        pdfContainerView.readingFocusOverlay.isFocusEnabled
    }

    var testingReadingFocusModeIsEnabled: Bool {
        isReadingFocusModeEnabled
    }

    var testingHorizontalPanLockIsEnabled: Bool {
        isHorizontalPanLocked
    }

    var testingPanLockIndicatorIsVisible: Bool {
        panLockIndicator.isHidden == false
    }

    @discardableResult
    func testingHandleContinuousBookScroll(
        deltaX: CGFloat,
        deltaY: CGFloat = 0,
        hasPreciseScrollingDeltas: Bool = true,
        hasScrollPhase: Bool = true,
        isMomentum: Bool = false,
        timestamp: TimeInterval
    ) -> Bool {
        handleBookScroll(
            deltaX: deltaX,
            deltaY: deltaY,
            hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
            hasScrollPhase: hasScrollPhase,
            isMomentum: isMomentum,
            timestamp: timestamp
        )
    }

    func testingInterruptContinuousBookScrollInput() {
        resetBookPageTurnInput()
    }

    func testingResetBookScrollGesture() {
        resetBookPageTurnState()
    }

    func testingHandleVerticalPageScroll(_ event: NSEvent, pointerIsOverPDF: Bool = true) -> Bool {
        handleVerticalPageScroll(event, pointerIsOverPDF: pointerIsOverPDF)
    }

    func testingPositionBelongsToCurrentSpread(
        positionPageIndex: Int,
        currentPageIndex: Int
    ) -> Bool {
        guard let session = targetSession(), let document = pdfView.document else { return false }
        return positionBelongsToCurrentSpread(
            ReadingPosition(pageIndex: positionPageIndex, point: .zero),
            currentPageIndex: currentPageIndex,
            session: session,
            document: document
        )
    }
}

extension ReaderViewController: FindBarDelegate {
    func findBar(_ view: FindBarView, didSubmitQuery query: String, scope: SearchScope) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = view.searchOptions
        let submittedKey = SubmittedSearchKey(query: trimmed, scope: scope, options: options)
        let currentQuery = documentStore.searchQuery(in: windowID)
        let currentScope = documentStore.searchScope(in: windowID)
        let currentOptions = documentStore.searchOptions(in: windowID)

        if trimmed.isEmpty {
            lastSubmittedSearchKey = nil
            pendingFindNavigationAfterSearch = nil
            if currentQuery.isEmpty == false || currentScope != scope || currentOptions != options {
                documentStore.updateSearch(
                    query: "",
                    scope: scope,
                    options: options,
                    in: windowID
                )
            }
            syncFindBarStatus()
            return
        }

        if lastSubmittedSearchKey == submittedKey,
           currentQuery == trimmed,
           currentScope == scope,
           currentOptions == options {
            let snapshot = documentStore.searchSnapshot(in: windowID)
            if snapshot.isSearching {
                pendingFindNavigationAfterSearch = submittedKey
                syncFindBarStatus()
                return
            }
            if snapshot.totalMatches > 0 {
                pendingFindNavigationAfterSearch = nil
                onFindActionRequested?(.activateNext)
                return
            }
        }

        if trimmed != currentQuery || scope != currentScope || options != currentOptions {
            pendingFindNavigationAfterSearch = nil
            documentStore.updateSearch(
                query: trimmed,
                scope: scope,
                options: options,
                in: windowID
            )
        }

        lastSubmittedSearchKey = submittedKey
        syncFindBarStatus()
    }

    func findBarRequestsSelectNext(_ view: FindBarView) {
        onFindActionRequested?(.selectNext)
    }

    func findBarRequestsSelectPrevious(_ view: FindBarView) {
        onFindActionRequested?(.selectPrevious)
    }

    func findBarRequestsActivateSelection(_ view: FindBarView) {
        onFindActionRequested?(.activateSelected)
    }

    func findBarRequestsNext(_ view: FindBarView) {
        onFindActionRequested?(.activateNext)
    }

    func findBarRequestsPrevious(_ view: FindBarView) {
        onFindActionRequested?(.activatePrevious)
    }

    func findBarRequestsClose(_ view: FindBarView) {
        hideFindBar()
    }
}
