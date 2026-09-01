import AppKit
import os
import PDFKit

/// Seamless all-pages overview: pages sit on the reader surface with no chrome panel.
///
/// Thumbnails rasterize lazily: only cells inside (or one screen near) the
/// viewport render, off the main thread, at a pixel size capped for memory.
/// A cost-bounded cache recycles recently visited pages, far-offscreen cells
/// drop their bitmaps, and leaving overview releases everything immediately.
final class OverviewGridView: NSView {
    var onPageSelected: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let pagesContainer = FlippedClipContainer()
    private var itemViews: [OverviewPageItemView] = []
    private var document: PDFDocument?
    private var columns: Int = 1
    private var cellSize: CGSize = .zero
    private var spacing: CGFloat = OverviewGridLayout.defaultCellSpacing
    private var edgeInset: CGFloat = OverviewGridLayout.defaultEdgeInset
    private var gridOrigin: CGPoint = .zero
    private var thumbnailGeneration = 0
    private var lastRenderedPixelSize: CGSize = .zero
    private var pendingRenderTickets: [Int: OverviewRenderTicket] = [:]

    /// Long-side pixel cap so fit-all cells on huge displays cannot allocate giant bitmaps.
    private static let maxThumbnailPixelLongSide: CGFloat = 1200
    /// Byte budget for recycled offscreen thumbnails; live cells are extra.
    private static let thumbnailCacheCostLimit = 48 * 1024 * 1024
    private static let maxConcurrentRenders = 2

    private let thumbnailCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.totalCostLimit = thumbnailCacheCostLimit
        return cache
    }()

    private let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentRenders
        queue.qualityOfService = .userInteractive
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(document: PDFDocument?) {
        let previousID = self.document.map { ObjectIdentifier($0) }
        let nextID = document.map { ObjectIdentifier($0) }
        guard previousID != nextID else {
            self.document = document
            return
        }
        self.document = document
        invalidateThumbnails(clearDisplayedImages: false)
        rebuildItems()
        refreshVisibleThumbnails()
    }

    func applyLayout(
        columns: Int,
        cellSize: CGSize,
        spacing: CGFloat = OverviewGridLayout.defaultCellSpacing,
        edgeInset: CGFloat = OverviewGridLayout.defaultEdgeInset
    ) {
        self.columns = max(columns, 1)
        self.cellSize = CGSize(width: max(cellSize.width, 1), height: max(cellSize.height, 1))
        self.spacing = max(spacing, 0)
        self.edgeInset = max(edgeInset, 0)
        layoutItems()
        refreshVisibleThumbnails()
    }

    func applySurfaceBackground(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        scrollView.backgroundColor = color
        scrollView.drawsBackground = true
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = color
        pagesContainer.wantsLayer = true
        pagesContainer.layer?.backgroundColor = color.cgColor
        itemViews.forEach { $0.applyBorderAppearance() }
    }

    override var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            if isHidden {
                invalidateThumbnails(clearDisplayedImages: true)
            } else {
                refreshVisibleThumbnails()
            }
        }
    }

    private func configureHierarchy() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .clear
        scrollView.documentView = pagesContainer

        pagesContainer.wantsLayer = true
        pagesContainer.layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func rebuildItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll(keepingCapacity: true)

        let pageCount = document?.pageCount ?? 0
        for index in 0..<pageCount {
            let item = OverviewPageItemView()
            item.pageIndex = index
            item.onSelect = { [weak self] pageIndex in
                self?.onPageSelected?(pageIndex)
            }
            pagesContainer.addSubview(item)
            itemViews.append(item)
        }
        layoutItems()
    }

    private func layoutItems() {
        let pageCount = itemViews.count
        guard pageCount > 0, cellSize.width > 1, cellSize.height > 1 else {
            pagesContainer.frame = .zero
            return
        }

        let cols = max(columns, 1)
        let rows = Int(ceil(Double(pageCount) / Double(cols)))
        let contentWidth =
            CGFloat(cols) * cellSize.width + CGFloat(max(cols - 1, 0)) * spacing + edgeInset * 2
        let contentHeight =
            CGFloat(rows) * cellSize.height + CGFloat(max(rows - 1, 0)) * spacing + edgeInset * 2

        // At least fill the clip so the surface color is continuous (no nested card).
        let viewport = scrollView.contentView.bounds.size
        let width = max(contentWidth, viewport.width)
        let height = max(contentHeight, viewport.height)
        pagesContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let gridWidth =
            CGFloat(cols) * cellSize.width + CGFloat(max(cols - 1, 0)) * spacing
        let gridHeight =
            CGFloat(rows) * cellSize.height + CGFloat(max(rows - 1, 0)) * spacing
        let originX = max((width - gridWidth) / 2, edgeInset)
        let originY = max((height - gridHeight) / 2, edgeInset)
        gridOrigin = CGPoint(x: originX, y: originY)

        for (index, item) in itemViews.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = originX + CGFloat(col) * (cellSize.width + spacing)
            let y = originY + CGFloat(row) * (cellSize.height + spacing)
            item.frame = NSRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
        }
    }

    // MARK: - Lazy thumbnail pipeline

    private func refreshVisibleThumbnails() {
        guard isHidden == false,
              let document,
              document.pageCount > 0,
              itemViews.isEmpty == false,
              cellSize.width > 1, cellSize.height > 1 else { return }

        let pixelSize = thumbnailPixelSize()
        if pixelSize != lastRenderedPixelSize {
            // Raster scale changed (zoom / resize): drop recycled bitmaps and stop
            // in-flight renders. Displayed stale thumbnails stay until replaced,
            // and only cells near the viewport re-render — not the whole document.
            lastRenderedPixelSize = pixelSize
            cancelPendingRenders()
            thumbnailCache.removeAllObjects()
        }

        let visibleRect = scrollView.contentView.documentVisibleRect
        guard visibleRect.width > 1, visibleRect.height > 1 else { return }
        // Prefetch roughly one screen around the viewport.
        let bufferedRect = visibleRect.insetBy(dx: -visibleRect.width, dy: -visibleRect.height)
        let wantedIndices = Set(
            OverviewGridLayout.visibleCellIndices(
                pageCount: document.pageCount,
                columns: columns,
                cellSize: cellSize,
                spacing: spacing,
                origin: gridOrigin,
                viewport: bufferedRect
            )
        )

        // Far-offscreen bitmaps are the unbounded-memory surface; drop them. The
        // cache brings recent ones back instantly when they scroll in again.
        for (index, item) in itemViews.enumerated() where wantedIndices.contains(index) == false {
            if pendingRenderTickets[index] == nil {
                item.clearThumbnail()
            }
        }

        guard wantedIndices.isEmpty == false else { return }
        let centerIndex = centerVisibleIndex(viewport: visibleRect, pageCount: document.pageCount)
        for index in wantedIndices.sorted(by: { abs($0 - centerIndex) < abs($1 - centerIndex) }) {
            guard index < itemViews.count,
                  pendingRenderTickets[index] == nil,
                  itemNeedsRender(itemViews[index]) else { continue }
            // Recently visited pages come back from the cache without rasterizing.
            if let cached = thumbnailCache.object(forKey: NSNumber(value: index)) {
                itemViews[index].setThumbnail(cached)
                continue
            }
            enqueueThumbnailRender(index: index, pixelSize: pixelSize)
        }
    }

    private func thumbnailPixelSize() -> NSSize {
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let longSide = max(cellSize.width, cellSize.height)
        let scale = min(backingScale, Self.maxThumbnailPixelLongSide / max(longSide, 1))
        return NSSize(
            width: max(cellSize.width * scale, 1),
            height: max(cellSize.height * scale, 1)
        )
    }

    private func centerVisibleIndex(viewport: CGRect, pageCount: Int) -> Int {
        let strideX = max(cellSize.width + spacing, 1)
        let strideY = max(cellSize.height + spacing, 1)
        let row = max(0, Int(floor((viewport.midY - gridOrigin.y) / strideY)))
        let col = max(0, Int(floor((viewport.midX - gridOrigin.x) / strideX)))
        return min(row * columns + col, max(pageCount - 1, 0))
    }

    /// Stale bitmaps (rendered for a previous cell size) stay displayed until
    /// the replacement arrives, so zoom never blanks the grid.
    private func itemNeedsRender(_ item: OverviewPageItemView) -> Bool {
        guard let image = item.thumbnailImage else { return true }
        return abs(image.size.width - cellSize.width) > 0.5
            || abs(image.size.height - cellSize.height) > 0.5
    }

    private func enqueueThumbnailRender(index: Int, pixelSize: NSSize) {
        guard let document else { return }
        let ticket = OverviewRenderTicket(
            document: document,
            pageIndex: index,
            pixelSize: pixelSize,
            pointSize: cellSize,
            generation: thumbnailGeneration
        )
        pendingRenderTickets[index] = ticket

        // PDFKit reads on a stable document are safe off-main (PDFThumbnailView
        // rasterizes the same way); only the result hops back to the main thread.
        renderQueue.addOperation { [weak self, ticket] in
            guard ticket.isCancelled == false,
                  let page = ticket.document.page(at: ticket.pageIndex) else { return }
            let image = page.thumbnail(of: ticket.pixelSize, for: .mediaBox)
            guard ticket.isCancelled == false else { return }
            image.size = ticket.pointSize
            ticket.storeResult(image)

            DispatchQueue.main.async { [weak self, ticket] in
                guard let self else { return }
                if self.pendingRenderTickets[ticket.pageIndex] === ticket {
                    self.pendingRenderTickets[ticket.pageIndex] = nil
                }
                guard self.thumbnailGeneration == ticket.generation,
                      ticket.pageIndex < self.itemViews.count,
                      let image = ticket.takeResult() else { return }
                self.thumbnailCache.setObject(
                    image,
                    forKey: NSNumber(value: ticket.pageIndex),
                    cost: ticket.costBytes
                )
                self.itemViews[ticket.pageIndex].setThumbnail(image)
            }
        }
    }

    private func cancelPendingRenders() {
        thumbnailGeneration += 1
        pendingRenderTickets.values.forEach { $0.cancel() }
        pendingRenderTickets.removeAll()
    }

    private func invalidateThumbnails(clearDisplayedImages: Bool) {
        cancelPendingRenders()
        thumbnailCache.removeAllObjects()
        if clearDisplayedImages {
            itemViews.forEach { $0.clearThumbnail() }
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        refreshVisibleThumbnails()
    }

    override func layout() {
        super.layout()
        layoutItems()
        refreshVisibleThumbnails()
    }
}

// MARK: - Testing support

extension OverviewGridView {
    var testingThumbnailImageIndices: Set<Int> {
        Set(itemViews.indices.filter { itemViews[$0].thumbnailImage != nil })
    }

    var testingPendingRenderIndices: Set<Int> {
        Set(pendingRenderTickets.keys)
    }

    func testingThumbnailPointSize(at index: Int) -> CGSize? {
        guard itemViews.indices.contains(index) else { return nil }
        return itemViews[index].thumbnailImage?.size
    }

    /// Moves the viewport without going through the scroll machinery, then
    /// runs the same refresh a real scroll would trigger.
    func testingScroll(to rect: CGRect) {
        scrollView.contentView.bounds.origin = rect.origin
        refreshVisibleThumbnails()
    }

    /// Blocks until queued rasterizations have been applied on the main thread.
    func testingFlushRenders() {
        renderQueue.waitUntilAllOperationsAreFinished()
        let deadline = Date().addingTimeInterval(5)
        while pendingRenderTickets.isEmpty == false && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

// MARK: - Item

private final class OverviewPageItemView: NSView {
    var pageIndex: Int = 0
    var onSelect: ((Int) -> Void)?

    private let imageView = NSImageView()
    private let pageLabel = NSTextField(labelWithString: "")

    var thumbnailImage: NSImage? { imageView.image }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 3
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.white.cgColor
        applyBorderAppearance()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor

        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .systemFont(ofSize: 10, weight: .medium)
        pageLabel.textColor = NightModeStyle.secondaryTextColor
        pageLabel.alignment = .center
        pageLabel.drawsBackground = false
        pageLabel.isBezeled = false
        pageLabel.isEditable = false
        pageLabel.alphaValue = 0.85

        addSubview(imageView)
        addSubview(pageLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setThumbnail(_ image: NSImage?) {
        imageView.image = image
        pageLabel.stringValue = "\(pageIndex + 1)"
        applyBorderAppearance()
    }

    func clearThumbnail() {
        imageView.image = nil
    }

    func applyBorderAppearance() {
        // Hairline stroke: soft enough not to compete with page content.
        let stroke = NightModeStyle.chromeStrokeColor.withAlphaComponent(0.55)
        layer?.borderColor = stroke.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(pageIndex)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class FlippedClipContainer: NSView {
    override var isFlipped: Bool { true }
}

/// One off-main rasterization request plus its result slot.
/// `@unchecked Sendable` crosses only the render queue boundary.
private final class OverviewRenderTicket: @unchecked Sendable {
    let document: PDFDocument
    let pageIndex: Int
    let pixelSize: NSSize
    let pointSize: CGSize
    let generation: Int
    let costBytes: Int

    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    private let result = OSAllocatedUnfairLock<NSImage?>(initialState: nil)

    init(
        document: PDFDocument,
        pageIndex: Int,
        pixelSize: NSSize,
        pointSize: CGSize,
        generation: Int
    ) {
        self.document = document
        self.pageIndex = pageIndex
        self.pixelSize = pixelSize
        self.pointSize = pointSize
        self.generation = generation
        self.costBytes = Int(pixelSize.width * pixelSize.height) * 4
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    var isCancelled: Bool {
        cancelled.withLock { $0 }
    }

    func storeResult(_ image: NSImage) {
        result.withLock { $0 = image }
    }

    func takeResult() -> NSImage? {
        result.withLock { $0 }
    }
}
