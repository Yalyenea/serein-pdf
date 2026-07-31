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
}

private struct PDFViewportAnchor {
    let page: PDFPage
    let pagePoint: NSPoint
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
        dropHighlightView.frame = bounds.insetBy(dx: 12, dy: 12)
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

/// Clip view that hard-locks horizontal origin (belt after event stripping) and
/// preserves margin centering when the document is smaller than the viewport.
private final class PDFReaderClipView: NSClipView {
    /// When non-nil, every horizontal scroll/bounds change is forced to this X.
    var forcedOriginX: CGFloat?

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        if let forcedOriginX {
            bounds.origin.x = forcedOriginX
            return bounds
        }
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
        return bounds
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: clampedOrigin(for: newOrigin))
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(clampedOrigin(for: newOrigin))
    }

    private func clampedOrigin(for origin: NSPoint) -> NSPoint {
        guard let forcedOriginX else { return origin }
        return NSPoint(x: forcedOriginX, y: origin.y)
    }
}

final class ReaderPDFView: PDFView {
    var onLayoutCompleted: (() -> Void)?

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
}

final class ReaderViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    let pdfView = ReaderPDFView()
    var onFocusRequested: (() -> Void)?
    var onFindActionRequested: ((FindNavigationAction) -> Void)?
    var onOpenURLsRequested: (([URL]) -> Void)?
    private let pdfContainerView = PDFContainerView()
    private let emptyStateContainer = NSStackView()
    private let emptyStateTitleLabel = NSTextField(labelWithString: "Open a PDF to start reading.")
    private let emptyStateHintLabel = NSTextField(labelWithString: "")
    private let highlightModeIndicator = NSStackView()
    private let highlightModeColorDot = NSView()
    private let highlightModeLabel = NSTextField(labelWithString: "Highlight · Esc")
    private let panLockIndicator = NSTextField(labelWithString: "H-lock · L")
    private let switchTitleToastView = NSView()
    private let switchTitleToastLabel = NSTextField(labelWithString: "")
    private let overviewGridView = OverviewGridView()
    private let findBarView = FindBarView()
    private var findBarTopConstraint: NSLayoutConstraint?
    private var pdfContainerTopConstraint: NSLayoutConstraint?
    private let themeManager = ThemeManager()
    private(set) var displayedSessionID: UUID?
    private var displayedReadingPosition: ReadingPosition?
    private var displayedDisplayMode: ReaderDisplayMode?
    private var displayedScaleMode: ReaderScaleMode?
    private var isApplyingStoreState = false
    private var isApplyingProgrammaticScale = false
    private var isApplyingHighlightSelection = false
    private var appearanceObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var leftMouseDownMonitor: Any?
    nonisolated(unsafe) private var leftMouseUpMonitor: Any?
    nonisolated(unsafe) private var panLockScrollMonitor: Any?
    private var pendingFitWidthSessionID: UUID?
    private var pendingFitHeightSessionID: UUID?
    private var lastAppliedFitBoundsWidth: CGFloat = 0
    private var lastAppliedFitBoundsHeight: CGFloat = 0
    private weak var observedPDFClipView: NSClipView?
    private var isApplyingScrollClamp = false
    private var lastSubmittedSearchKey: SubmittedSearchKey?
    private var pendingAnnotationFocusToken: Int = 0
    private var switchTitleToastHideWorkItem: DispatchWorkItem?
    private(set) var isReadingFocusModeEnabled = false
    private(set) var isHorizontalPanLocked = false
    private(set) var readingFocusSettings: ReadingFocusSettings = .default
    var targetSessionID: UUID? {
        didSet {
            guard oldValue != targetSessionID else { return }
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
            self?.syncPDFMarginBackground()
            self?.applyThemeFilter()
            self?.pdfContainerView.readingFocusOverlay.refreshFocusGeometry()
        }
        pdfContainerView.readingFocusOverlay.pageBoundsProvider = { [weak self] point in
            self?.readingFocusPageBounds(at: point)
        }
        pdfContainerView.setReadingFocusSettings(readingFocusSettings)

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
        leftMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.requestFocusIfNeeded(event: event)
            }
            return event
        }
        leftMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated {
                self?.applyHighlightOnMouseUpIfNeeded(event: event)
            }
            return event
        }
        // Strip horizontal deltas before any view (including PDFKit's scroll view) sees them.
        panLockScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            var rewritten: NSEvent? = event
            MainActor.assumeIsolated {
                rewritten = self.rewriteScrollEventIfPanLocked(event)
            }
            return rewritten
        }
        refreshDisplayedDocument()
        configurePDFScrollBehaviorIfNeeded()
        applyReaderAppearance()
    }

    private func syncNightModeFromSystem() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        themeManager.setNightModeEnabled(isDark)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
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

        switch session.scaleMode {
        case .fitWidth:
            pendingFitWidthSessionID = nil
            lastAppliedFitBoundsWidth = pdfView.bounds.width
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
        if let monitor = leftMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = leftMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = panLockScrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = false

        emptyStateTitleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateTitleLabel.textColor = NightModeStyle.secondaryTextColor
        emptyStateTitleLabel.alignment = .center
        emptyStateTitleLabel.maximumNumberOfLines = 0
        emptyStateTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        emptyStateHintLabel.font = .systemFont(ofSize: 12)
        emptyStateHintLabel.textColor = NightModeStyle.tertiaryTextColor
        emptyStateHintLabel.alignment = .center
        emptyStateHintLabel.maximumNumberOfLines = 0
        emptyStateHintLabel.stringValue = emptyStateHintText()
        emptyStateHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        emptyStateContainer.orientation = .vertical
        emptyStateContainer.alignment = .centerX
        emptyStateContainer.spacing = 8
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addArrangedSubview(emptyStateTitleLabel)
        emptyStateContainer.addArrangedSubview(emptyStateHintLabel)

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
        container.addSubview(emptyStateContainer)
        container.addSubview(highlightModeIndicator)
        container.addSubview(panLockIndicator)
        container.addSubview(switchTitleToastView)
        container.addSubview(overviewGridView)
        container.addSubview(findBarView)

        let findBarTop = findBarView.topAnchor.constraint(equalTo: container.topAnchor)
        let pdfTop = pdfContainerView.topAnchor.constraint(equalTo: container.topAnchor)
        findBarTopConstraint = findBarTop
        pdfContainerTopConstraint = pdfTop

        NSLayoutConstraint.activate([
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
            findBarTop,
            findBarView.heightAnchor.constraint(equalToConstant: 36),
        ])

        view = container
    }

    func fitToWidth() {
        guard let session = targetSession() else { return }
        if pdfView.bounds.width > 0 {
            pendingFitWidthSessionID = nil
            lastAppliedFitBoundsWidth = pdfView.bounds.width
        }
        applyFitWidth(for: session)
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
        let nextScale = min(pdfView.scaleFactor * 1.1, pdfView.maxScaleFactor)
        applyProgrammaticScale(nextScale, preserveViewportCenter: true)
        // Pin before store writeback so the notification does not re-apply scale.
        displayedScaleMode = .manual
        documentStore.setScaleMode(.manual, scaleFactor: nextScale, for: session.id)
    }

    func zoomOut() {
        if isAllPagesOverviewActive {
            adjustOverviewZoom(scale: 1 / 1.1)
            return
        }
        guard let session = targetSession(),
              session.id == displayedSessionID else { return }
        let nextScale = max(pdfView.scaleFactor / 1.1, pdfView.minScaleFactor)
        applyProgrammaticScale(nextScale, preserveViewportCenter: true)
        // Pin before store writeback so the notification does not re-apply scale.
        displayedScaleMode = .manual
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
        guard let pageCount = pdfView.document?.pageCount, pageCount > 0 else { return }
        _ = goToPage(pageCount - 1)
    }

    func navigateBack() {
        guard pdfView.canGoBack else { return }
        pdfView.goBack(nil)
    }

    func navigateForward() {
        guard pdfView.canGoForward else { return }
        pdfView.goForward(nil)
    }

    var canGoBack: Bool { pdfView.canGoBack }
    var canGoForward: Bool { pdfView.canGoForward }

    @discardableResult
    func goToPage(_ pageIndex: Int) -> Bool {
        jumpToPage(pageIndex)
    }

    @discardableResult
    private func jumpToPage(_ pageIndex: Int) -> Bool {
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return false }
        let bounds = page.bounds(for: pdfView.displayBox)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: bounds.minX, y: bounds.maxY)
        )
        // Suppress PDFViewPageChanged during jump: at go(to:) time the clipView
        // hasn't updated yet, so currentReadingPosition() would capture stale
        // coordinates and write them back to the store, causing a rollback.
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
        stabilizePDFScrollPosition()
        isApplyingStoreState = false
        // Now the layout is complete; update the store with the correct position.
        if let session = targetSession(),
           session.id == displayedSessionID,
           let position = currentReadingPosition() {
            documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
            displayedReadingPosition = position
        }
        return true
    }

    @discardableResult
    private func turnPage(by direction: Int) -> Bool {
        guard direction != 0,
              isAllPagesOverviewActive == false,
              let session = targetSession(),
              session.id == displayedSessionID,
              let document = pdfView.document,
              let currentPageIndex = currentPageIndexForNavigation(in: document) else { return false }

        let step = session.displayMode.usesTwoUpLayout ? 2 : 1
        let targetPageIndex = min(max(currentPageIndex + direction * step, 0), document.pageCount - 1)
        guard targetPageIndex != currentPageIndex else { return false }

        return jumpToPage(targetPageIndex)
    }

    private func currentPageIndexForNavigation(in document: PDFDocument) -> Int? {
        if let position = currentReadingPosition(),
           position.pageIndex >= 0,
           position.pageIndex < document.pageCount {
            return position.pageIndex
        }

        guard let currentPage = pdfView.currentPage else { return nil }
        return document.index(for: currentPage)
    }

    var currentPageCount: Int { pdfView.document?.pageCount ?? 0 }

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

        if active {
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
        let isNightModeEnabled = themeManager.readerState.isNightModeEnabled
        let pageBackground = isNightModeEnabled
            ? NightModeStyle.pageBackgroundColor
            : NightModeStyle.readerBackdropColor
        overviewGridView.applySurfaceBackground(pageBackground)
    }

    private func handleOverviewPageSelected(_ pageIndex: Int) {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }
        pdfView.go(to: page)
        setAllPagesOverviewActive(false)
    }

    var isNightModeEnabled: Bool {
        themeManager.readerState.isNightModeEnabled
    }

    var isHighlightModeEnabled: Bool {
        themeManager.readerState.isHighlightModeEnabled
    }

    var currentHighlightColor: HighlightColor {
        themeManager.readerState.highlightColor
    }

    @discardableResult
    func triggerHighlightShortcut() -> Bool {
        if highlightCurrentSelection() {
            return true
        }

        themeManager.setHighlightModeEnabled(true)
        updateHighlightModeIndicator()
        return false
    }

    func exitHighlightMode() {
        themeManager.setHighlightModeEnabled(false)
        updateHighlightModeIndicator()
    }

    func setHighlightColor(_ color: HighlightColor) {
        themeManager.setHighlightColor(color)
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
        guard enabled != isHorizontalPanLocked else {
            guard isViewLoaded else { return }
            updatePanLockIndicator()
            configurePDFScrollBehaviorIfNeeded()
            return
        }
        isHorizontalPanLocked = enabled
        guard isViewLoaded else { return }
        updatePanLockIndicator()
        configurePDFScrollBehaviorIfNeeded()
        if isHorizontalPanLocked {
            recenterDocumentViewIfNeeded()
        } else {
            (pdfClipView() as? PDFReaderClipView)?.forcedOriginX = nil
        }
    }

    private func rewriteScrollEventIfPanLocked(_ event: NSEvent) -> NSEvent? {
        guard shouldLockHorizontalPan else { return event }
        guard scrollEventIsOverPDFContent(event) else { return event }

        // Horizontal-dominant or pure-horizontal: discard entirely so PDFKit never pans on X.
        let horizontal = abs(event.scrollingDeltaX)
        let vertical = abs(event.scrollingDeltaY)
        if ScrollWheelHorizontalStripper.isHorizontalOnly(event) || horizontal > vertical {
            return nil
        }
        guard ScrollWheelHorizontalStripper.hasHorizontalComponent(event) else { return event }
        return ScrollWheelHorizontalStripper.verticalOnly(from: event) ?? event
    }

    private func scrollEventIsOverPDFContent(_ event: NSEvent) -> Bool {
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
    func removeHighlightUnderCursor() -> Bool {
        guard let session = targetSession(),
              session.id == displayedSessionID,
              let window = pdfView.window,
              let document = pdfView.document else { return false }

        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInPDF = pdfView.convert(mouseInWindow, from: nil)
        guard pdfView.bounds.contains(mouseInPDF),
              let page = pdfView.page(for: mouseInPDF, nearest: false) else { return false }

        let pointOnPage = pdfView.convert(mouseInPDF, to: page)
        guard let target = HighlightService.highlightAnnotation(at: pointOnPage, on: page) else { return false }

        let records = HighlightService.removeHighlightGroup(containing: target, in: document)
        guard records.isEmpty == false else { return false }

        documentStore.noteHighlightsRemoved(records, for: session.id)
        return true
    }

    @discardableResult
    func undoLastHighlight() -> Bool {
        guard let session = targetSession(),
              session.id == displayedSessionID else { return false }
        let didUndo = documentStore.undoLastHighlight(for: session.id)
        if didUndo {
            pdfView.needsDisplay = true
        }
        return didUndo
    }

    var hasUndoableHighlight: Bool {
        guard let sessionID = targetSessionID else { return false }
        return documentStore.hasUndoableHighlight(for: sessionID)
    }

    var hasRedoableHighlight: Bool {
        guard let sessionID = targetSessionID else { return false }
        return documentStore.hasRedoableHighlight(for: sessionID)
    }

    @discardableResult
    func redoLastHighlight() -> Bool {
        guard let session = targetSession(),
              session.id == displayedSessionID else { return false }
        let didRedo = documentStore.redoLastHighlight(for: session.id)
        if didRedo {
            pdfView.needsDisplay = true
        }
        return didRedo
    }

    func toggleNightMode() {
        themeManager.toggleNightMode()
        applyReaderAppearance()
    }

    func refreshThemeAppearance() {
        syncNightModeFromSystem()
        applyReaderAppearance()
    }

    func saveAnnotations() throws {
        guard let sessionID = targetSessionID else { return }
        try documentStore.saveAnnotations(for: sessionID)
    }

    @discardableResult
    func search(for query: String) -> Bool {
        documentStore.updateSearch(query: query, scope: findBarView.scope, in: windowID)
        return documentStore.totalSearchMatches(in: windowID) > 0
    }

    var isFindBarVisible: Bool {
        findBarView.isHidden == false
    }

    func showFindBar(scope: SearchScope? = nil) {
        guard let container = view as NSView? else { return }
        let targetScope = scope ?? documentStore.searchScope(in: windowID)
        let selectedQuery = selectedSearchQuery()
        let query = selectedQuery ?? documentStore.searchQuery(in: windowID)
        documentStore.updateSearch(
            query: query,
            scope: targetScope,
            in: windowID
        )
        if let selectedQuery {
            lastSubmittedSearchKey = SubmittedSearchKey(query: selectedQuery, scope: targetScope)
        } else if query.isEmpty == false,
                  documentStore.totalSearchMatches(in: windowID) > 0 {
            // Re-opening Find with an existing query should treat Enter as "next".
            lastSubmittedSearchKey = SubmittedSearchKey(query: query, scope: targetScope)
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
        findBarView.setQuery(documentStore.searchQuery(in: windowID))
        syncFindBarStatus()
        findBarView.focusQueryField()
    }

    private func selectedSearchQuery() -> String? {
        guard let text = pdfView.currentSelection?.string.map(PDFTextSanitizer.sanitize),
              text.isEmpty == false else { return nil }
        return text
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
        pdfView.window?.makeFirstResponder(pdfView)
    }

    @discardableResult
    func findNextMatch() -> Bool {
        guard documentStore.totalSearchMatches(in: windowID) > 0 else { return false }
        onFindActionRequested?(.activateNext)
        return true
    }

    @discardableResult
    func findPreviousMatch() -> Bool {
        guard documentStore.totalSearchMatches(in: windowID) > 0 else { return false }
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
        findBarView.setStatus(matchIndex: nil, totalMatches: documentStore.totalSearchMatches(in: windowID))
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        guard notification.isOnlySidebarChromeChange == false else { return }
        // Store notifications are synchronous; do not sample PDFKit while a
        // programmatic document/viewport restore is still settling.
        guard isApplyingStoreState == false else { return }
        if syncDisplayedStateWithoutRefreshIfPossible() == false {
            refreshDisplayedDocument()
        }
        // Page/zoom writeback does not change find results; skip search recompute.
        if notification.isOnlyReadingPositionChange == false {
            syncFindBarStatus()
        }
    }

    @objc
    private func handlePDFViewPageChanged(_ notification: Notification) {
        guard isApplyingStoreState == false,
              let session = targetSession(),
              session.id == displayedSessionID,
              let position = currentReadingPosition() else { return }

        documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
    }

    @objc
    private func handlePDFViewScaleChanged(_ notification: Notification) {
        guard isApplyingProgrammaticScale == false,
              let session = targetSession(),
              session.id == displayedSessionID else { return }

        // User-driven zoom always exits fit-width and pins the chosen scale.
        documentStore.setScaleMode(.manual, scaleFactor: pdfView.scaleFactor, for: session.id)

        if let position = currentReadingPosition() {
            documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
        }
    }

    @objc
    private func handlePDFViewSelectionChanged(_ notification: Notification) {
        // Auto-highlight has moved to the local mouseUp monitor; selection changes
        // during an active drag are ignored to avoid stacking highlights.
    }

    private func applyHighlightOnMouseUpIfNeeded(event: NSEvent) {
        guard themeManager.readerState.isHighlightModeEnabled,
              isApplyingHighlightSelection == false,
              let window = pdfView.window,
              event.window === window else { return }

        let locationInPDF = pdfView.convert(event.locationInWindow, from: nil)
        guard pdfView.bounds.contains(locationInPDF) else { return }
        _ = highlightCurrentSelection()
    }

    private func requestFocusIfNeeded(event: NSEvent) {
        guard let window = view.window,
              event.window === window else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        guard view.bounds.contains(location) else { return }
        onFocusRequested?()
    }

    private func emptyStateHintText() -> String {
        let recentShortcut = documentStore.appConfiguration.shortcuts.bindings[.showRecentFilesPalette]?.displayString
            ?? "⌘⇧Space"
        return "⌘O to open · \(recentShortcut) for recent · drop PDF here"
    }

    private func showDefaultEmptyState() {
        emptyStateTitleLabel.stringValue = "Open a PDF to start reading."
        emptyStateHintLabel.stringValue = emptyStateHintText()
        emptyStateHintLabel.isHidden = false
        setEmptyStateVisible(true)
    }

    private func showErrorEmptyState(_ message: String) {
        emptyStateTitleLabel.stringValue = message
        emptyStateHintLabel.isHidden = true
        setEmptyStateVisible(true)
    }

    private func setEmptyStateVisible(_ visible: Bool) {
        emptyStateContainer.isHidden = !visible
    }

    private func refreshDisplayedDocument() {
        guard isViewLoaded else { return }

        guard let session = targetSession() else {
            pdfView.document = nil
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
            pdfView.document = nil
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
            pdfView.document = nil
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
            pdfView.document = document
            displayedSessionID = refreshedSession.id
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
        }

        applyDisplayModeIfNeeded(refreshedSession)
        applyScaleIfNeeded(refreshedSession)
        applyReadingPositionIfNeeded(targetReadingPosition, force: documentChanged)
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

            let fitHeightLayoutIsStable =
                pendingFitHeightSessionID != session.id &&
                abs(pdfView.bounds.height - lastAppliedFitBoundsHeight) <= 0.5
            return fitHeightLayoutIsStable ? .manual : nil
        case .fitWidth:
            guard let targetScaleFactor = fitWidthScaleFactor(for: session) else { return nil }
            if abs(liveScale - targetScaleFactor) <= 0.001 {
                return .fitWidth
            }

            let fitWidthLayoutIsStable =
                pendingFitWidthSessionID != session.id &&
                abs(pdfView.bounds.width - lastAppliedFitBoundsWidth) <= 0.5
            return fitWidthLayoutIsStable ? .manual : nil
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
        let needsPositionSync = readingPosition(session.lastReadPosition, differsFrom: livePosition)
        guard needsModeSync || needsScaleSync || needsPositionSync else { return false }

        displayedScaleMode = liveScaleMode
        displayedReadingPosition = livePosition

        if needsModeSync {
            documentStore.setScaleMode(liveScaleMode, scaleFactor: liveScale, for: session.id)
        }
        if needsScaleSync || needsPositionSync {
            documentStore.updateReadingPosition(livePosition, scaleFactor: liveScale, for: session.id)
        }
        return true
    }

    private func readingPosition(_ lhs: ReadingPosition, differsFrom rhs: ReadingPosition) -> Bool {
        guard lhs.pageIndex == rhs.pageIndex else { return true }
        return abs(lhs.point.x - rhs.point.x) > 0.5 || abs(lhs.point.y - rhs.point.y) > 0.5
    }

    func applySearchResults(_ matches: [DocumentSearchMatch], selectedMatchIndex: Int?) {
        pdfView.highlightedSelections = matches.map(\.selection)
        if isFindBarVisible {
            findBarView.setStatus(matchIndex: selectedMatchIndex, totalMatches: matches.count)
        }
        guard let selectedMatchIndex,
              matches.indices.contains(selectedMatchIndex) else {
            // Leave currentSelection alone when no explicit index — find-next may
            // have just called go(to:) and a store refresh must not wipe it.
            return
        }
        pdfView.setCurrentSelection(matches[selectedMatchIndex].selection, animate: false)
    }

    func clearSearchResults() {
        pdfView.highlightedSelections = nil
        pdfView.currentSelection = nil
    }

    func go(to selection: PDFSelection) {
        isApplyingStoreState = true
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
        isApplyingStoreState = false
    }

    func focus(on highlight: DocumentHighlightGroup) {
        if let selection = highlight.primarySelection {
            go(to: selection)
            pendingAnnotationFocusToken += 1
            let token = pendingAnnotationFocusToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.pendingAnnotationFocusToken == token else { return }
                    self.pdfView.currentSelection = nil
                }
            }
            return
        }

        guard let page = pdfView.document?.page(at: highlight.pageIndex) else { return }
        isApplyingStoreState = true
        pdfView.go(to: page)
        isApplyingStoreState = false
    }

    private func applyDisplayModeIfNeeded(_ session: DocumentSession) {
        guard displayedDisplayMode != session.displayMode else { return }

        pdfView.displayDirection = .vertical
        pdfView.displayMode = session.displayMode.pdfDisplayMode
        pdfView.displaysAsBook = false
        displayedDisplayMode = session.displayMode
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        recenterDocumentViewIfNeeded()
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

        if !force,
           let currentPage = pdfView.currentPage,
           document.index(for: currentPage) == readingPosition.pageIndex {
            displayedReadingPosition = readingPosition
            return
        }

        let destination = PDFDestination(page: page, at: readingPosition.point)
        pdfView.go(to: destination)
        displayedReadingPosition = readingPosition
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        recenterDocumentViewIfNeeded()
    }

    private func clampedReadingPosition(
        _ readingPosition: ReadingPosition,
        in document: PDFDocument
    ) -> ReadingPosition? {
        guard document.pageCount > 0 else { return nil }
        let pageIndex = min(max(readingPosition.pageIndex, 0), document.pageCount - 1)
        return ReadingPosition(
            pageIndex: pageIndex,
            point: pageIndex == readingPosition.pageIndex ? readingPosition.point : .zero
        )
    }

    private func liveReadingPositionForReload() -> ReadingPosition? {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else { return currentReadingPosition() }
        let pageIndex = document.index(for: page)
        guard document.pageCount > 0, (0..<document.pageCount).contains(pageIndex) else {
            return currentReadingPosition()
        }
        if let position = currentReadingPosition(), position.pageIndex == pageIndex {
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
            lastAppliedFitBoundsWidth = pdfView.bounds.width
            displayedScaleMode = .fitWidth
            documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
            return
        }
        applyProgrammaticScale(scaleFactor, preserveViewportCenter: true)
        lastAppliedFitBoundsWidth = pdfView.bounds.width
        displayedScaleMode = .fitWidth
        documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
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

    private func applyProgrammaticScale(_ scaleFactor: CGFloat, preserveViewportCenter: Bool = false) {
        let viewportAnchor = preserveViewportCenter ? captureViewportAnchor() : nil
        isApplyingProgrammaticScale = true
        defer { isApplyingProgrammaticScale = false }
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
        let currentScale = max(pdfView.scaleFactor, 0.001)
        let normalizedRowWidth = pdfView.rowSize(for: leadPage).width / currentScale
        guard normalizedRowWidth > 0 else { return nil }

        let availableWidth = max(pdfClipView()?.frame.width ?? pdfView.bounds.width, 1)
        let unclamped = availableWidth / normalizedRowWidth
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

        let startIndex = session.currentPageIndex.isMultiple(of: 2)
            ? session.currentPageIndex
            : max(session.currentPageIndex - 1, 0)
        let firstPage = document.page(at: startIndex)
        let secondPage = document.page(at: startIndex + 1)
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

        return ReadingPosition(pageIndex: document.index(for: page), point: .zero)
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
              let scrollView = pdfScrollView(),
              let clipView = pdfClipView() else { return false }

        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        syncPDFMarginBackgroundAfterPDFKitLayout()

        var targetBounds = clipView.bounds
        targetBounds.origin.y -= clipView.bounds.height * fraction
        targetBounds = clipView.constrainBoundsRect(targetBounds)
        guard abs(targetBounds.origin.y - clipView.bounds.origin.y) > 0.5 else { return false }

        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)

        guard let session = targetSession(),
              session.id == displayedSessionID,
              let document = pdfView.document,
              let anchor = captureViewportAnchor() else { return true }

        documentStore.updateReadingPosition(
            ReadingPosition(pageIndex: document.index(for: anchor.page), point: anchor.pagePoint),
            scaleFactor: pdfView.scaleFactor,
            for: session.id
        )
        return true
    }

    private func targetSession() -> DocumentSession? {
        guard let targetSessionID else { return nil }
        return documentStore.session(for: targetSessionID)
    }

    private func pdfScrollView() -> NSScrollView? {
        pdfView.subviews.first { $0 is NSScrollView } as? NSScrollView
    }

    private func pdfScrollBackgroundViews() -> [NSView] {
        guard let scrollView = pdfScrollView() else { return [] }
        var matches: [NSView] = []
        var pending = scrollView.subviews
        while let view = pending.popLast() {
            if String(describing: type(of: view)).contains("ContentBackgroundView") {
                matches.append(view)
            }
            pending.append(contentsOf: view.subviews)
        }
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
    }

    private func syncHorizontalPanLockConstraint() {
        guard let clipView = pdfClipView() as? PDFReaderClipView else { return }
        guard shouldLockHorizontalPan, let documentView = pdfDocumentView() else {
            clipView.forcedOriginX = nil
            return
        }

        let overflowX = max(documentView.frame.width - clipView.bounds.width, 0)
        clipView.forcedOriginX = overflowX <= 0.5 ? 0 : overflowX * 0.5
    }

    @objc
    private func handlePDFClipViewBoundsDidChange(_ notification: Notification) {
        guard isApplyingScrollClamp == false else { return }
        recenterDocumentViewIfNeeded()
        pdfContainerView.readingFocusOverlay.refreshFocusGeometry()
    }

    private func pdfClipView() -> NSClipView? {
        pdfScrollView()?.contentView
    }

    private func pdfDocumentView() -> NSView? {
        pdfClipView()?.documentView
    }

    private func pdfPageViews() -> [NSView] {
        guard let documentView = pdfDocumentView() else { return [] }
        var matches: [NSView] = []
        var pending = documentView.subviews
        while let view = pending.popLast() {
            if String(describing: type(of: view)).contains("PDFPageView") {
                matches.append(view)
            }
            pending.append(contentsOf: view.subviews)
        }
        return matches
    }

    private func syncPDFMarginBackground() {
        let appearance = NSApp.effectiveAppearance
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
        syncPDFMarginBackground()
        DispatchQueue.main.async { [weak self] in
            self?.syncPDFMarginBackground()
        }
    }

    private func recenterDocumentViewIfNeeded() {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView() else { return }

        // Horizontal: center whenever the document is narrower than the viewport
        // (all display modes). Vertical: only single-page, where blank margin
        // should sit evenly around a fully visible slide.
        let isSinglePage = displayedDisplayMode == .singlePage
        let fitsHorizontally = documentView.frame.width <= clipView.bounds.width + 0.5
        let fitsVertically = isSinglePage && documentView.frame.height <= clipView.bounds.height + 0.5
        let targetMinX = fitsHorizontally
            ? (clipView.bounds.width - documentView.frame.width) * 0.5
            : 0
        // Oversized single-page docs stay top-aligned (origin Y = 0); continuous
        // modes leave PDFKit's Y alone so vertical scrolling is undisturbed.
        let targetMinY: CGFloat
        if fitsVertically {
            targetMinY = (clipView.bounds.height - documentView.frame.height) * 0.5
        } else if isSinglePage {
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
        if isSinglePage, abs(frame.minY - targetMinY) > 0.5 {
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
        } else if shouldLockHorizontalPan {
            let overflowX = max(documentView.frame.width - clipView.bounds.width, 0)
            targetOrigin.x = overflowX * 0.5
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


    @discardableResult
    private func highlightCurrentSelection() -> Bool {
        guard let session = targetSession(),
              session.id == displayedSessionID,
              let selection = pdfView.currentSelection,
              HighlightService.selectionContainsText(selection) else { return false }

        isApplyingHighlightSelection = true
        defer { isApplyingHighlightSelection = false }

        let appliedRecords = HighlightService.applyHighlight(
            to: selection,
            color: NightModeStyle.highlightColor(
                for: themeManager.readerState.highlightColor,
                appearance: NSApp.effectiveAppearance
            )
        )
        guard appliedRecords.isEmpty == false else { return false }

        documentStore.noteHighlightsAdded(appliedRecords, for: session.id)
        pdfView.currentSelection = nil
        return true
    }

    private func applyReaderAppearance() {
        let isNightModeEnabled = themeManager.readerState.isNightModeEnabled
        let appearance = NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let pageBackground = isNightModeEnabled ? NightModeStyle.pageBackgroundColor : NightModeStyle.readerBackdropColor
            let usesFlatPDFChrome = NightModeStyle.prefersFlatPDFChrome(for: appearance)
            pdfView.displaysPageBreaks = !isNightModeEnabled
            pdfView.pageShadowsEnabled = !isNightModeEnabled && !usesFlatPDFChrome
            view.layer?.backgroundColor = pageBackground.cgColor
            pdfView.backgroundColor = .clear
            pdfView.layer?.backgroundColor = NSColor.clear.cgColor
            emptyStateTitleLabel.textColor = NightModeStyle.secondaryTextColor
            emptyStateHintLabel.textColor = NightModeStyle.tertiaryTextColor
            highlightModeLabel.textColor = NightModeStyle.secondaryTextColor
        }
        applyOverviewSurfaceAppearance()
        if emptyStateContainer.isHidden {
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
        let isAvailable = isAllPagesOverviewActive == false
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
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switchTitleToastView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(isDark ? 0.86 : 0.92).cgColor
        switchTitleToastLabel.textColor = NightModeStyle.primaryTextColor
    }

    private func updateHighlightModeIndicator() {
        let isEnabled = themeManager.readerState.isHighlightModeEnabled
        highlightModeIndicator.isHidden = !isEnabled
        let color = themeManager.readerState.highlightColor
        highlightModeLabel.stringValue = "Highlight · Esc"
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

    var testingEmptyStateTitle: String {
        emptyStateTitleLabel.stringValue
    }

    var testingEmptyStateHint: String {
        emptyStateHintLabel.stringValue
    }

    var testingEmptyStateHintIsVisible: Bool {
        emptyStateHintLabel.isHidden == false
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
}

extension ReaderViewController: FindBarDelegate {
    func findBar(_ view: FindBarView, didSubmitQuery query: String, scope: SearchScope) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedKey = SubmittedSearchKey(query: trimmed, scope: scope)
        let currentQuery = documentStore.searchQuery(in: windowID)
        let currentScope = documentStore.searchScope(in: windowID)

        if trimmed.isEmpty {
            lastSubmittedSearchKey = nil
            if currentQuery.isEmpty == false || currentScope != scope {
                documentStore.updateSearch(query: "", scope: scope, in: windowID)
            }
            syncFindBarStatus()
            return
        }

        if lastSubmittedSearchKey == submittedKey,
           currentQuery == trimmed,
           currentScope == scope,
           documentStore.totalSearchMatches(in: windowID) > 0 {
            onFindActionRequested?(.activateNext)
            return
        }

        if trimmed != currentQuery || scope != currentScope {
            documentStore.updateSearch(query: trimmed, scope: scope, in: windowID)
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
