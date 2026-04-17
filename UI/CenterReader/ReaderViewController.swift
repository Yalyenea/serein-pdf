import AppKit
import PDFKit

final class ReaderViewController: NSViewController {
    let documentStore: DocumentStore
    let pdfView = PDFView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a PDF to start reading.")
    private var displayedSessionID: UUID?
    private var displayedReadingPosition: ReadingPosition?
    private var displayedDisplayMode: ReaderDisplayMode?
    private var displayedScaleMode: ReaderScaleMode?
    private var isApplyingStoreState = false
    private var isApplyingProgrammaticScale = false

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
        refreshDisplayedDocument()
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
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.white
        pdfView.isHidden = true
        pdfView.displaysPageBreaks = true

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor

        container.addSubview(pdfView)
        container.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        view = container
    }

    func fitToWidth() {
        guard let session = documentStore.activeSession else { return }
        applyFitWidth(for: session)
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
        guard let page = session.pdfDocument.page(at: session.lastReadPosition.pageIndex) else { return }

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
}
