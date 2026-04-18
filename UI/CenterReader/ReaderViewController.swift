import AppKit
import CoreImage
import PDFKit

final class ReaderViewController: NSViewController {
    let documentStore: DocumentStore
    let pdfView = PDFView()
    private let pdfContainerView = PDFContainerView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF to start reading.")
    private let highlightModeBanner = NSTextField(labelWithString: "Highlight Mode · Esc to exit")
    private let themeManager = ThemeManager()
    private var displayedSessionID: UUID?
    private var displayedReadingPosition: ReadingPosition?
    private var displayedDisplayMode: ReaderDisplayMode?
    private var displayedScaleMode: ReaderScaleMode?
    private var isApplyingStoreState = false
    private var isApplyingProgrammaticScale = false
    private var isApplyingHighlightSelection = false
    private var appearanceObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var leftMouseUpMonitor: Any?

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        super.init(nibName: nil, bundle: nil)
        title = "Reader"
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

        guard let session = documentStore.activeSession,
              session.scaleMode == .fitWidth,
              displayedSessionID == session.id else { return }

        applyFitWidth(for: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        pdfContainerView.embedPDFView(pdfView)
        container.addSubview(pdfContainerView)
        container.addSubview(emptyStateLabel)
        container.addSubview(highlightModeBanner)

        NSLayoutConstraint.activate([
            pdfContainerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfContainerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfContainerView.topAnchor.constraint(equalTo: container.topAnchor),
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
        ])

        view = container
    }

    func fitToWidth() {
        guard let session = documentStore.activeSession else { return }
        applyFitWidth(for: session)
    }

    func zoomIn() {
        guard let session = documentStore.activeSession,
              session.id == displayedSessionID else { return }
        let nextScale = min(pdfView.scaleFactor * 1.1, pdfView.maxScaleFactor)
        applyProgrammaticScale(nextScale)
        documentStore.setScaleMode(.manual, scaleFactor: nextScale, for: session.id)
    }

    func zoomOut() {
        guard let session = documentStore.activeSession,
              session.id == displayedSessionID else { return }
        let nextScale = max(pdfView.scaleFactor / 1.1, pdfView.minScaleFactor)
        applyProgrammaticScale(nextScale)
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
    func removeHighlightInSelection() -> Bool {
        guard let session = documentStore.activeSession,
              session.id == displayedSessionID,
              let selection = pdfView.currentSelection,
              HighlightService.selectionContainsText(selection) else { return false }

        let removed = HighlightService.removeHighlights(in: selection)
        guard removed > 0 else { return false }

        documentStore.setDirty(true, for: session.id)
        pdfView.currentSelection = nil
        return true
    }

    func toggleNightMode() {
        themeManager.toggleNightMode()
        applyReaderAppearance()
    }

    func saveAnnotations() throws {
        guard let sessionID = documentStore.activeSessionID else { return }
        try documentStore.saveAnnotations(for: sessionID)
    }

    @discardableResult
    func search(for query: String) -> Bool {
        guard let document = pdfView.document else { return false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false,
              let selection = document.findString(trimmedQuery, withOptions: .caseInsensitive).first else {
            return false
        }

        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
        return true
    }

    @objc
    private func handleDocumentStoreDidChange(_ notification: Notification) {
        refreshDisplayedDocument()
    }

    @objc
    private func handlePDFViewPageChanged(_ notification: Notification) {
        guard isApplyingStoreState == false,
              let session = documentStore.activeSession,
              session.id == displayedSessionID,
              let position = currentReadingPosition() else { return }

        documentStore.updateReadingPosition(position, scaleFactor: pdfView.scaleFactor, for: session.id)
    }

    @objc
    private func handlePDFViewScaleChanged(_ notification: Notification) {
        guard isApplyingStoreState == false,
              let session = documentStore.activeSession,
              session.id == displayedSessionID else { return }

        guard isApplyingProgrammaticScale == false else { return }

        // Any user-driven zoom exits fit-width and preserves the chosen scale.
        let nextScaleMode: ReaderScaleMode = .manual
        documentStore.setScaleMode(nextScaleMode, scaleFactor: pdfView.scaleFactor, for: session.id)

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

    private func refreshDisplayedDocument() {
        guard isViewLoaded else { return }

        guard let session = documentStore.activeSession else {
            pdfView.document = nil
            pdfView.isHidden = true
            emptyStateLabel.isHidden = false
            displayedSessionID = nil
            displayedReadingPosition = nil
            displayedDisplayMode = nil
            displayedScaleMode = nil
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
            applyFitWidth(for: session)
        case .manual:
            guard displayedScaleMode != .manual || abs(pdfView.scaleFactor - session.zoomScale) > 0.001 else { return }
            applyProgrammaticScale(session.zoomScale)
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
        applyProgrammaticScale(scaleFactor)
        documentStore.setScaleMode(.fitWidth, scaleFactor: scaleFactor, for: session.id)
    }

    private func applyProgrammaticScale(_ scaleFactor: CGFloat) {
        isApplyingProgrammaticScale = true
        defer { isApplyingProgrammaticScale = false }
        pdfView.scaleFactor = scaleFactor
    }

    private func fitWidthScaleFactor(for session: DocumentSession) -> CGFloat? {
        guard let document = pdfView.document else { return nil }
        let pages = spreadPages(for: session, in: document)
        guard pages.isEmpty == false else { return nil }

        let pageWidths = pages.map { $0.bounds(for: pdfView.displayBox).width }
        let interPageSpacing: CGFloat = session.displayMode.usesTwoUpLayout && pages.count > 1 ? 12 : 0
        let horizontalInset: CGFloat = 24
        let availableWidth = max(pdfView.bounds.width - horizontalInset, 1)
        let totalWidth = pageWidths.reduce(0, +) + interPageSpacing
        guard totalWidth > 0 else { return nil }

        let unclamped = availableWidth / totalWidth
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

    @discardableResult
    private func highlightCurrentSelection() -> Bool {
        guard let session = documentStore.activeSession,
              session.id == displayedSessionID,
              let selection = pdfView.currentSelection,
              HighlightService.selectionContainsText(selection) else { return false }

        isApplyingHighlightSelection = true
        defer { isApplyingHighlightSelection = false }

        let appliedAnnotations = HighlightService.applyHighlight(
            to: selection,
            color: themeManager.readerState.highlightColor.nsColor
        )
        guard appliedAnnotations > 0 else { return false }

        documentStore.setDirty(true, for: session.id)
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
