import AppKit
import PDFKit

/// Seamless all-pages overview: pages sit on the reader surface with no chrome panel.
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
    private var thumbnailGeneration: Int = 0

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
        self.document = document
        if previousID != nextID {
            rebuildItems()
        }
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
        regenerateThumbnailsIfNeeded()
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
        regenerateThumbnailsIfNeeded()
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

        for (index, item) in itemViews.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = originX + CGFloat(col) * (cellSize.width + spacing)
            let y = originY + CGFloat(row) * (cellSize.height + spacing)
            item.frame = NSRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
        }
    }

    private func regenerateThumbnailsIfNeeded() {
        guard let document, cellSize.width > 1, cellSize.height > 1 else { return }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        let targetSize = cellSize
        // Retina-quality bitmaps.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = NSSize(
            width: max(targetSize.width * scale, 1),
            height: max(targetSize.height * scale, 1)
        )

        // PDFKit thumbnail generation is main-thread bound; chunk so first paint stays responsive.
        let pageCount = document.pageCount
        let chunkSize = 6
        var nextIndex = 0

        func renderChunk() {
            guard self.thumbnailGeneration == generation else { return }
            let end = min(nextIndex + chunkSize, pageCount)
            while nextIndex < end {
                let index = nextIndex
                nextIndex += 1
                guard index < self.itemViews.count,
                      let page = document.page(at: index) else { continue }
                let image = page.thumbnail(of: pixelSize, for: .mediaBox)
                image.size = targetSize
                self.itemViews[index].setThumbnail(image)
            }
            if nextIndex < pageCount {
                DispatchQueue.main.async(execute: renderChunk)
            }
        }

        DispatchQueue.main.async(execute: renderChunk)
    }

    override func layout() {
        super.layout()
        layoutItems()
    }
}

// MARK: - Item

private final class OverviewPageItemView: NSView {
    var pageIndex: Int = 0
    var onSelect: ((Int) -> Void)?

    private let imageView = NSImageView()
    private let pageLabel = NSTextField(labelWithString: "")

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
