import AppKit

enum ReaderPaneDirection: Equatable {
    case left, down, up, right
}

/// Geometry is shared by split admission, spatial focus, and the AppKit hosts.
enum ReaderPaneGeometry {
    static let minimumSize = NSSize(width: 320, height: 160)

    static func minimumSize(for node: ReaderLayoutNode, divider: CGFloat = 1) -> NSSize {
        switch node {
        case .pane:
            return minimumSize
        case let .split(_, layout, _, first, second):
            let a = minimumSize(for: first, divider: divider)
            let b = minimumSize(for: second, divider: divider)
            return layout == .sideBySide
                ? NSSize(width: a.width + divider + b.width, height: max(a.height, b.height))
                : NSSize(width: max(a.width, b.width), height: a.height + divider + b.height)
        }
    }

    static func canSplit(_ size: NSSize, layout: ReaderSplitLayout, divider: CGFloat = 1) -> Bool {
        switch layout {
        case .sideBySide:
            return size.width >= minimumSize.width * 2 + divider && size.height >= minimumSize.height
        case .stacked:
            return size.width >= minimumSize.width && size.height >= minimumSize.height * 2 + divider
        }
    }

    static func firstLength(
        available: CGFloat, ratio: Double, firstMinimum: CGFloat, secondMinimum: CGFloat
    ) -> CGFloat {
        guard available > 0 else { return 0 }
        let totalMinimum = firstMinimum + secondMinimum
        let compression = min(1, available / max(totalMinimum, 1))
        let minimum = firstMinimum * compression
        let maximum = available - secondMinimum * compression
        return min(max(available * CGFloat(ratio), minimum), maximum)
    }

    /// Coordinates are flipped: the first stacked child is above the second.
    static func frames(
        for node: ReaderLayoutNode, in bounds: NSRect, divider: CGFloat = 1
    ) -> [ReaderPane: NSRect] {
        switch node {
        case let .pane(pane):
            return [pane: bounds]
        case let .split(_, layout, ratio, first, second):
            let a = minimumSize(for: first, divider: divider)
            let b = minimumSize(for: second, divider: divider)
            let horizontal = layout == .sideBySide
            let available = max((horizontal ? bounds.width : bounds.height) - divider, 0)
            let length = firstLength(
                available: available, ratio: ratio,
                firstMinimum: horizontal ? a.width : a.height,
                secondMinimum: horizontal ? b.width : b.height
            )
            var firstBounds = bounds
            var secondBounds = bounds
            if horizontal {
                firstBounds.size.width = length
                secondBounds.origin.x += length + divider
                secondBounds.size.width = max(available - length, 0)
            } else {
                firstBounds.size.height = length
                secondBounds.origin.y += length + divider
                secondBounds.size.height = max(available - length, 0)
            }
            return frames(for: first, in: firstBounds, divider: divider).merging(
                frames(for: second, in: secondBounds, divider: divider), uniquingKeysWith: { a, _ in a }
            )
        }
    }

    /// Prefer an aligned neighbour, then the nearest edge; recent focus breaks ties.
    static func neighbour(
        from pane: ReaderPane, direction: ReaderPaneDirection,
        frames: [ReaderPane: NSRect], recentFocus: [ReaderPane]
    ) -> ReaderPane? {
        guard let origin = frames[pane] else { return nil }
        let horizontal = direction == .left || direction == .right
        let forward = direction == .right || direction == .down
        let candidates = frames.compactMap { candidate, rect -> (ReaderPane, Bool, CGFloat, CGFloat, Int)? in
            guard candidate != pane else { return nil }
            let originCenter = horizontal ? origin.midX : origin.midY
            let candidateCenter = horizontal ? rect.midX : rect.midY
            guard forward ? candidateCenter > originCenter : candidateCenter < originCenter else { return nil }
            let overlap = horizontal
                ? min(origin.maxY, rect.maxY) - max(origin.minY, rect.minY)
                : min(origin.maxX, rect.maxX) - max(origin.minX, rect.minX)
            let edgeDistance: CGFloat
            if horizontal {
                edgeDistance = forward ? rect.minX - origin.maxX : origin.minX - rect.maxX
            } else {
                edgeDistance = forward ? rect.minY - origin.maxY : origin.minY - rect.maxY
            }
            guard overlap > 0, edgeDistance >= -0.5 else { return nil }
            let perpendicular = horizontal ? abs(rect.midY - origin.midY) : abs(rect.midX - origin.midX)
            let recency = recentFocus.firstIndex(of: candidate) ?? Int.max
            return (candidate, overlap > 0, max(edgeDistance, 0), perpendicular, recency)
        }
        return candidates.sorted { a, b in
            if a.1 != b.1 { return a.1 }
            if abs(a.2 - b.2) > 0.5 { return a.2 < b.2 }
            if abs(a.3 - b.3) > 0.5 { return a.3 < b.3 }
            if a.4 != b.4 { return a.4 < b.4 }
            return a.0.rawValue < b.0.rawValue
        }.first?.0
    }
}

/// Each branch owns its divider and persists only its own split ratio.
final class ReaderSplitHostView: NSSplitView, NSSplitViewDelegate {
    var splitID: UUID
    var ratio: Double
    var firstMinimumSize: NSSize = ReaderPaneGeometry.minimumSize
    var secondMinimumSize: NSSize = ReaderPaneGeometry.minimumSize
    var paneIDs: [ReaderPane] = []
    var onWillResize: (([ReaderPane]) -> Void)?
    var onDidResize: (([ReaderPane]) -> Void)?
    var onRatioChanged: ((UUID, Double) -> Void)?
    private var isDraggingDivider = false

    override var isFlipped: Bool { true }
    override var dividerColor: NSColor { SplitViewController.chromeStrokeColor }

    init(id: UUID, layout: ReaderSplitLayout, ratio: Double) {
        self.splitID = id
        self.ratio = ratio
        super.init(frame: .zero)
        isVertical = layout == .sideBySide
        dividerStyle = .thin
        delegate = self
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(first: NSView, second: NSView) {
        guard subviews.count != 2 || subviews[0] !== first || subviews[1] !== second else { return }
        subviews.forEach { $0.removeFromSuperview() }
        for child in [first, second] {
            // This split owns its children's frames. Their internal Auto Layout
            // constraints must not resize the arranged panes to fittingSize.
            child.translatesAutoresizingMaskIntoConstraints = true
            child.autoresizingMask = []
            addSubview(child)
        }
        resizeSubviews(withOldSize: bounds.size)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        if subviews.count == 1 {
            subviews[0].frame = bounds
            return
        }
        guard subviews.count == 2 else { return }
        if isDraggingDivider {
            super.resizeSubviews(withOldSize: oldSize)
            return
        }
        let available = max((isVertical ? bounds.width : bounds.height) - dividerThickness, 0)
        let length = ReaderPaneGeometry.firstLength(
            available: available, ratio: ratio,
            firstMinimum: isVertical ? firstMinimumSize.width : firstMinimumSize.height,
            secondMinimum: isVertical ? secondMinimumSize.width : secondMinimumSize.height
        )
        let firstFrame: NSRect
        let secondFrame: NSRect
        if isVertical {
            firstFrame = NSRect(x: 0, y: 0, width: length, height: bounds.height)
            secondFrame = NSRect(x: length + dividerThickness, y: 0,
                                 width: max(available - length, 0), height: bounds.height)
        } else {
            firstFrame = NSRect(x: 0, y: 0, width: bounds.width, height: length)
            secondFrame = NSRect(x: 0, y: length + dividerThickness,
                                 width: bounds.width, height: max(available - length, 0))
        }
        subviews[0].frame = firstFrame
        subviews[1].frame = secondFrame
    }

    override func mouseDown(with event: NSEvent) {
        onWillResize?(paneIDs)
        isDraggingDivider = true
        super.mouseDown(with: event)
        isDraggingDivider = false
        let available = (isVertical ? bounds.width : bounds.height) - dividerThickness
        if available > 0, let first = subviews.first {
            ratio = Double((isVertical ? first.frame.width : first.frame.height) / available)
            onRatioChanged?(splitID, ratio)
        }
        onDidResize?(paneIDs)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let available = max((isVertical ? bounds.width : bounds.height) - dividerThickness, 0)
        let a = isVertical ? firstMinimumSize.width : firstMinimumSize.height
        let b = isVertical ? secondMinimumSize.width : secondMinimumSize.height
        return ReaderPaneGeometry.firstLength(available: available, ratio: 0, firstMinimum: a, secondMinimum: b)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let available = max((isVertical ? bounds.width : bounds.height) - dividerThickness, 0)
        let a = isVertical ? firstMinimumSize.width : firstMinimumSize.height
        let b = isVertical ? secondMinimumSize.width : secondMinimumSize.height
        return ReaderPaneGeometry.firstLength(available: available, ratio: 1, firstMinimum: a, secondMinimum: b)
    }
}
