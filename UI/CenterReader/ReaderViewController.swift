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

final class ReaderViewController: NSViewController {
    let documentStore: DocumentStore
    let windowID: UUID
    let pdfView = PDFView()
    var onFocusRequested: (() -> Void)?
    var onFindActionRequested: ((FindNavigationAction) -> Void)?
    private let pdfContainerView = PDFContainerView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF to start reading.")
    private let highlightModeBanner = NSTextField(labelWithString: "Highlight Mode · Esc to exit")
    private let overviewThumbnailView = PDFThumbnailView()
    private let findBarView = FindBarView()
    private var findBarTopConstraint: NSLayoutConstraint?
    private var pdfContainerTopConstraint: NSLayoutConstraint?
    private var overviewLeadingConstraint: NSLayoutConstraint?
    private var overviewTrailingConstraint: NSLayoutConstraint?
    private var overviewTopConstraint: NSLayoutConstraint?
    private var overviewBottomConstraint: NSLayoutConstraint?
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
    private var pendingFitWidthSessionID: UUID?
    private var lastAppliedFitBoundsWidth: CGFloat = 0
    private var lastSubmittedSearchKey: SubmittedSearchKey?
    private var pendingAnnotationFocusToken: Int = 0
    var targetSessionID: UUID? {
        didSet {
            guard oldValue != targetSessionID else { return }
            refreshDisplayedDocument()
        }
    }

    init(documentStore: DocumentStore, windowID: UUID) {
        self.documentStore = documentStore
        self.windowID = windowID
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
        refreshDisplayedDocument()
        applyReaderAppearance()
    }

    private func syncNightModeFromSystem() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        themeManager.setNightModeEnabled(isDark)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyOverviewInsets()

        guard let session = targetSession(),
              displayedSessionID == session.id,
              pdfView.bounds.width > 0 else { return }

        guard session.scaleMode == .fitWidth else {
            recenterDocumentViewIfNeeded()
            return
        }

        let isPending = pendingFitWidthSessionID == session.id
        let boundsChanged = abs(pdfView.bounds.width - lastAppliedFitBoundsWidth) > 0.5
        guard isPending || boundsChanged else {
            recenterDocumentViewIfNeeded()
            return
        }

        pendingFitWidthSessionID = nil
        lastAppliedFitBoundsWidth = pdfView.bounds.width
        applyFitWidth(for: session)
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
    }

    override func loadView() {
        let container = NSView()
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

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor

        highlightModeBanner.translatesAutoresizingMaskIntoConstraints = false
        highlightModeBanner.font = .systemFont(ofSize: 11, weight: .medium)
        highlightModeBanner.textColor = .secondaryLabelColor
        highlightModeBanner.alignment = .center
        highlightModeBanner.wantsLayer = true
        highlightModeBanner.layer?.cornerRadius = 4
        highlightModeBanner.layer?.backgroundColor = NSColor(
            calibratedRed: 0.97, green: 0.79, blue: 0.86, alpha: 0.75
        ).cgColor
        highlightModeBanner.drawsBackground = false
        highlightModeBanner.isHidden = true
        highlightModeBanner.isEditable = false
        highlightModeBanner.isBordered = false

        overviewThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        overviewThumbnailView.thumbnailSize = NSSize(width: 140, height: 180)
        overviewThumbnailView.backgroundColor = NSColor.windowBackgroundColor
        overviewThumbnailView.pdfView = pdfView
        overviewThumbnailView.isHidden = true

        findBarView.translatesAutoresizingMaskIntoConstraints = false
        findBarView.delegate = self
        findBarView.isHidden = true

        pdfContainerView.embedPDFView(pdfView)
        container.addSubview(pdfContainerView)
        container.addSubview(emptyStateLabel)
        container.addSubview(highlightModeBanner)
        container.addSubview(overviewThumbnailView)
        container.addSubview(findBarView)

        let findBarTop = findBarView.topAnchor.constraint(equalTo: container.topAnchor)
        let pdfTop = pdfContainerView.topAnchor.constraint(equalTo: container.topAnchor)
        findBarTopConstraint = findBarTop
        pdfContainerTopConstraint = pdfTop

        let overviewLeading = overviewThumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let overviewTrailing = overviewThumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        let overviewTop = overviewThumbnailView.topAnchor.constraint(equalTo: container.topAnchor)
        let overviewBottom = overviewThumbnailView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        overviewLeadingConstraint = overviewLeading
        overviewTrailingConstraint = overviewTrailing
        overviewTopConstraint = overviewTop
        overviewBottomConstraint = overviewBottom

        NSLayoutConstraint.activate([
            pdfContainerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfContainerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfTop,
            pdfContainerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainerView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainerView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: pdfContainerView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainerView.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            highlightModeBanner.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            highlightModeBanner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            highlightModeBanner.heightAnchor.constraint(equalToConstant: 22),
            highlightModeBanner.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            overviewLeading,
            overviewTrailing,
            overviewTop,
            overviewBottom,
            findBarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBarTop,
            findBarView.heightAnchor.constraint(equalToConstant: 36),
        ])

        view = container
    }

    func fitToWidth() {
        guard let session = targetSession() else { return }
        applyFitWidth(for: session)
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
        documentStore.setScaleMode(.manual, scaleFactor: nextScale, for: session.id)
    }

    func goToNextPage() {
        pdfView.goToNextPage(nil)
    }

    func goToPreviousPage() {
        pdfView.goToPreviousPage(nil)
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
        guard let document = pdfView.document,
              pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return false }
        pdfView.go(to: PDFDestination(page: page, at: .zero))
        return true
    }

    var currentPageCount: Int { pdfView.document?.pageCount ?? 0 }

    var isAllPagesOverviewActive: Bool {
        !overviewThumbnailView.isHidden
    }

    private var overviewSavedLeftSidebar: Bool?
    private var overviewSavedRightSidebar: Bool?
    private var overviewThumbnailWidth: CGFloat = 140

    func setAllPagesOverviewActive(_ active: Bool) {
        guard active != isAllPagesOverviewActive else { return }

        if active {
            overviewSavedLeftSidebar = documentStore.isLeftSidebarVisible(in: windowID)
            overviewSavedRightSidebar = documentStore.isRightSidebarVisible(in: windowID)
            documentStore.setLeftSidebarVisible(false, in: windowID)
            documentStore.setRightSidebarVisible(false, in: windowID)
            configureOverviewGrid()
            overviewThumbnailView.isHidden = false
            pdfContainerView.isHidden = true
            emptyStateLabel.isHidden = true
        } else {
            overviewThumbnailView.isHidden = true
            pdfContainerView.isHidden = false
            emptyStateLabel.isHidden = targetSession() != nil
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
        overviewThumbnailWidth = min(max(overviewThumbnailWidth * scale, 80), 360)
        overviewThumbnailView.thumbnailSize = NSSize(
            width: overviewThumbnailWidth,
            height: overviewThumbnailWidth * 1.414
        )
    }

    private func configureOverviewGrid() {
        let pageCount = pdfView.document?.pageCount ?? 0
        let columns = max(3, Int(ceil(sqrt(Double(max(pageCount, 1))))))
        overviewThumbnailView.maximumNumberOfColumns = columns
        overviewThumbnailView.thumbnailSize = NSSize(
            width: overviewThumbnailWidth,
            height: overviewThumbnailWidth * 1.414
        )
        applyOverviewInsets()
    }

    private func applyOverviewInsets() {
        let width = view.bounds.width
        let height = view.bounds.height
        let horizontal = max(width * 0.02, 8)
        let vertical = max(height * 0.02, 8)
        overviewLeadingConstraint?.constant = horizontal
        overviewTrailingConstraint?.constant = -horizontal
        overviewTopConstraint?.constant = vertical
        overviewBottomConstraint?.constant = -vertical
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
        updateHighlightModeBanner()
        return false
    }

    func exitHighlightMode() {
        themeManager.setHighlightModeEnabled(false)
        updateHighlightModeBanner()
    }

    func setHighlightColor(_ color: HighlightColor) {
        themeManager.setHighlightColor(color)
        updateHighlightModeBanner()
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

    func toggleNightMode() {
        themeManager.toggleNightMode()
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

    func showFindBar() {
        guard let container = view as NSView? else { return }
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
        refreshDisplayedDocument()
        syncFindBarStatus()
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

    private func refreshDisplayedDocument() {
        guard isViewLoaded else { return }

        guard let session = targetSession() else {
            pdfView.document = nil
            pdfView.isHidden = true
            emptyStateLabel.isHidden = false
            displayedSessionID = nil
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
            pdfView.highlightedSelections = nil
            pdfView.currentSelection = nil
            return
        }

        let isNewSession = displayedSessionID != session.id

        isApplyingStoreState = true
        defer { isApplyingStoreState = false }

        if isNewSession {
            pdfView.document = session.pdfDocument
            displayedSessionID = session.id
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
        }

        applyDisplayModeIfNeeded(session)
        applyScaleIfNeeded(session)
        applyReadingPositionIfNeeded(session, isNewSession: isNewSession)
        applyReaderAppearance()

        pdfView.isHidden = false
        emptyStateLabel.isHidden = true
    }

    func applySearchResults(_ matches: [DocumentSearchMatch], selectedMatchIndex: Int?) {
        pdfView.highlightedSelections = matches.map(\.selection)
        if isFindBarVisible {
            findBarView.setStatus(matchIndex: selectedMatchIndex, totalMatches: matches.count)
        }
        guard let selectedMatchIndex,
              matches.indices.contains(selectedMatchIndex) else {
            pdfView.currentSelection = nil
            return
        }
        pdfView.setCurrentSelection(matches[selectedMatchIndex].selection, animate: false)
    }

    func clearSearchResults() {
        pdfView.highlightedSelections = nil
        pdfView.currentSelection = nil
    }

    func go(to selection: PDFSelection) {
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
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
        pdfView.go(to: page)
    }

    private func applyDisplayModeIfNeeded(_ session: DocumentSession) {
        guard displayedDisplayMode != session.displayMode else { return }

        pdfView.displayDirection = .vertical
        pdfView.displayMode = session.displayMode.pdfDisplayMode
        pdfView.displaysAsBook = false
        displayedDisplayMode = session.displayMode
    }

    private func applyScaleIfNeeded(_ session: DocumentSession) {
        switch session.scaleMode {
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
            lastAppliedFitBoundsWidth = 0
            guard displayedScaleMode != .manual || abs(pdfView.scaleFactor - session.zoomScale) > 0.001 else { return }
            applyProgrammaticScale(
                session.zoomScale,
                preserveViewportCenter: displayedSessionID == session.id
            )
        }

        displayedScaleMode = session.scaleMode
    }

    private func applyReadingPositionIfNeeded(_ session: DocumentSession, isNewSession: Bool) {
        guard isNewSession || displayedReadingPosition != session.lastReadPosition else { return }
        guard let document = pdfView.document,
              let page = document.page(at: session.lastReadPosition.pageIndex) else { return }

        if !isNewSession,
           let currentPage = pdfView.currentPage,
           document.index(for: currentPage) == session.lastReadPosition.pageIndex {
            displayedReadingPosition = session.lastReadPosition
            return
        }

        let destination = PDFDestination(page: page, at: session.lastReadPosition.point)
        pdfView.go(to: destination)
        displayedReadingPosition = session.lastReadPosition
    }

    private func applyFitWidth(for session: DocumentSession) {
        guard let scaleFactor = fitWidthScaleFactor(for: session) else { return }
        applyProgrammaticScale(scaleFactor, preserveViewportCenter: true)
        documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
    }

    private func applyProgrammaticScale(_ scaleFactor: CGFloat, preserveViewportCenter: Bool = false) {
        let viewportAnchor = preserveViewportCenter ? captureViewportAnchor() : nil
        isApplyingProgrammaticScale = true
        defer { isApplyingProgrammaticScale = false }
        pdfView.scaleFactor = scaleFactor
        pdfView.layoutSubtreeIfNeeded()
        recenterDocumentViewIfNeeded()
        if let viewportAnchor {
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

    private func targetSession() -> DocumentSession? {
        guard let targetSessionID else { return nil }
        return documentStore.session(for: targetSessionID)
    }

    private func pdfScrollView() -> NSScrollView? {
        pdfView.subviews.first { $0 is NSScrollView } as? NSScrollView
    }

    private func pdfClipView() -> NSClipView? {
        pdfScrollView()?.contentView
    }

    private func pdfDocumentView() -> NSView? {
        pdfClipView()?.documentView
    }

    private func recenterDocumentViewIfNeeded() {
        guard let scrollView = pdfScrollView(),
              let clipView = pdfClipView(),
              let documentView = pdfDocumentView() else { return }

        let targetMinX: CGFloat
        if displayedDisplayMode == .singlePage {
            targetMinX = max((clipView.bounds.width - documentView.frame.width) * 0.5, 0)
        } else {
            targetMinX = 0
        }

        if abs(documentView.frame.minX - targetMinX) > 0.5 {
            var frame = documentView.frame
            frame.origin.x = targetMinX
            documentView.frame = frame
        }

        if targetMinX > 0, abs(clipView.bounds.origin.x) > 0.5 {
            let targetBounds = clipView.constrainBoundsRect(
                NSRect(origin: NSPoint(x: 0, y: clipView.bounds.origin.y), size: clipView.bounds.size)
            )
            clipView.scroll(to: targetBounds.origin)
            scrollView.reflectScrolledClipView(clipView)
        }
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
        clipView.scroll(to: targetBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
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
            color: themeManager.readerState.highlightColor.nsColor
        )
        guard appliedRecords.isEmpty == false else { return false }

        documentStore.noteHighlightsAdded(appliedRecords, for: session.id)
        pdfView.currentSelection = nil
        return true
    }

    private func applyReaderAppearance() {
        let isNightModeEnabled = themeManager.readerState.isNightModeEnabled
        let nightBackground = NSColor(calibratedWhite: 0.07, alpha: 1.0)
        view.layer?.backgroundColor = (isNightModeEnabled ? nightBackground : NSColor.white).cgColor
        pdfView.backgroundColor = .white
        pdfView.isHidden = false
        pdfContainerView.setNightModeEnabled(isNightModeEnabled)
        emptyStateLabel.textColor = isNightModeEnabled ? .tertiaryLabelColor : .secondaryLabelColor
        applyNightModeFilter(isEnabled: isNightModeEnabled)
        updateHighlightModeBanner()
    }

    private func updateHighlightModeBanner() {
        let isEnabled = themeManager.readerState.isHighlightModeEnabled
        highlightModeBanner.isHidden = !isEnabled
        let color = themeManager.readerState.highlightColor
        highlightModeBanner.stringValue = "Highlight Mode · \(color.menuTitle) · Esc to exit"
        highlightModeBanner.layer?.backgroundColor = color.nsColor.withAlphaComponent(0.7).cgColor
    }

    private func applyNightModeFilter(isEnabled: Bool) {
        guard isEnabled, let filter = CIFilter(name: "CIColorMatrix") else {
            pdfView.contentFilters = []
            return
        }
        let scale: CGFloat = -1.0
        let bias: CGFloat = 0.95
        filter.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
        pdfView.contentFilters = [filter]
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
