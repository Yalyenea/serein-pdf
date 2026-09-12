import AppKit
import PDFKit
import Testing
@testable import Serein

@MainActor
struct OutlineViewControllerTests {
    @Test
    func readingPositionChangeDoesNotReloadOutlineTree() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "stable-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        let reloadCount = controller.outlineReloadCount

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 1, point: CGPoint(x: 0, y: 100)),
            scaleFactor: 1,
            for: session.id
        )

        #expect(controller.outlineReloadCount == reloadCount)
    }

    @Test
    func outlineContentTracksSidebarWidth() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "width-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = outlineScrollView(in: controller.view),
              let documentView = scrollView.documentView else {
            Issue.record("Failed to locate outline sidebar views")
            return
        }

        #expect(documentView is NSOutlineView == false)
        #expect(abs(documentView.frame.width - scrollView.contentSize.width) < 0.5)
    }

    @Test
    func outlineContentShrinksWithSidebarAndLocksHorizontalPanning() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "narrow-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 140, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = outlineScrollView(in: controller.view),
              let documentView = scrollView.documentView else {
            Issue.record("Failed to locate outline sidebar views")
            return
        }

        scrollView.contentView.scroll(to: NSPoint(x: 80, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(abs(documentView.frame.width - scrollView.contentSize.width) < 0.5)
        #expect(documentView.frame.width <= scrollView.contentSize.width + 0.5)
        #expect(scrollView.contentView.bounds.origin.x == 0)
        #expect(hasPinnedEdgeConstraint(for: scrollView, in: controller.view, attribute: .leading))
        #expect(hasPinnedEdgeConstraint(for: scrollView, in: controller.view, attribute: .trailing))
    }

    @Test
    func outlineRowsWrapLongTitlesWithLargerText() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "wrapped-outline",
                outlineTitles: [
                    "A deliberately long outline title that should wrap cleanly inside the right sidebar instead of being truncated"
                ]
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 180, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let row = outlineRows(in: controller.view).first else {
            Issue.record("Failed to locate outline row views")
            return
        }

        #expect(row.frame.height > 40)
        #expect(row.textField.lineBreakMode == .byCharWrapping)
        #expect(row.textField.maximumNumberOfLines == 0)
        #expect(row.textField.font?.pointSize == 13)
        #expect(row.textField.preferredMaxLayoutWidth <= row.frame.width)
        let paragraphStyle = row.textField.attributedStringValue.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraphStyle?.lineBreakMode == .byCharWrapping)
        #expect(paragraphStyle?.minimumLineHeight == 14)
        #expect(paragraphStyle?.maximumLineHeight == 14)
    }

    @Test
    func outlineRowsKeepSingleLineTitlesCompact() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "compact-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 260, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let row = outlineRows(in: controller.view).first else {
            Issue.record("Failed to locate outline row")
            return
        }

        #expect(row.frame.height <= 25)
    }

    @Test
    func outlineRowsRequestExactDestinationsForSameAndDifferentPages() throws {
        let samePagePoint = CGPoint(x: 24, y: 220)
        let differentPagePoint = CGPoint(x: 52, y: 140)
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "exact-outline-navigation",
                topLevelCount: 2,
                outlinePoints: [samePagePoint, differentPagePoint]
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        var requests: [OutlineNavigationRequest] = []
        controller.onNavigationRequested = { requests.append($0) }
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 260, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        let positionBeforeClicks = store.session(for: session.id)?.lastReadPosition

        let rows = outlineRows(in: controller.view)
        #expect(rows.count == 2)
        rows[0].performPrimaryAction()
        rows[1].performPrimaryAction()

        #expect(requests == [
            OutlineNavigationRequest(
                sessionID: session.id,
                position: ReadingPosition(pageIndex: 0, point: samePagePoint)
            ),
            OutlineNavigationRequest(
                sessionID: session.id,
                position: ReadingPosition(pageIndex: 1, point: differentPagePoint)
            ),
        ])
        #expect(store.session(for: session.id)?.lastReadPosition == positionBeforeClicks)
    }

    @Test
    func outlinePaneHidesScrollersAndDisablesHorizontalScroll() {
        let store = makeIsolatedDocumentStore()
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = outlineScrollView(in: controller.view) else {
            Issue.record("Failed to locate outline scroll view")
            return
        }

        #expect(scrollView.hasVerticalScroller == false)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.horizontalScrollElasticity == .none)
    }

    @Test
    func outlinePaneEmbedsDirectlyOnTransparentSidebarSurface() {
        let store = makeIsolatedDocumentStore()
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = outlineScrollView(in: controller.view),
              let documentView = scrollView.documentView else {
            Issue.record("Failed to locate outline scroll view")
            return
        }

        #expect(scrollView.drawsBackground == false)
        #expect(scrollView.contentView.drawsBackground == false)
        #expect(scrollView.contentView.backgroundColor == .clear)
        #expect(documentView.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(documentView is NSOutlineView == false)
    }

    @Test
    func outlineExpansionToggleCollapsesAndExpandsTree() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "nested-outline", includeChild: true))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let toggleButton = findView(
            identifier: "outlineExpansionToggleButton",
            in: controller.view
        ) as? NSButton else {
            Issue.record("Failed to locate outline tree views")
            return
        }

        let initialRows = outlineRows(in: controller.view)
        #expect(initialRows.count == 3)
        let firstRow = initialRows[0]

        toggleButton.performClick(nil)
        let collapsedRows = outlineRows(in: controller.view)
        #expect(collapsedRows.count == 2)
        #expect(collapsedRows[0] === firstRow)
        #expect(toggleButton.toolTip == "Expand outline")

        toggleButton.performClick(nil)
        let expandedRows = outlineRows(in: controller.view)
        #expect(expandedRows.count == 3)
        #expect(expandedRows[0] === firstRow)
        #expect(toggleButton.toolTip == "Collapse outline")
    }

    @Test
    func outlineFilterShowsCaseInsensitiveMatchesAndAncestorPathsOnly() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "filter-outline",
                outlineTitles: ["Overview", "Appendix"],
                includeChild: true
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        setOutlineFilter("CHILD", in: controller)
        #expect(outlineRows(in: controller.view).map(\.node.title) == [
            "Overview",
            "filter-outline child",
        ])

        setOutlineFilter("overview", in: controller)
        #expect(outlineRows(in: controller.view).map(\.node.title) == ["Overview"])
    }

    @Test
    func outlineFilterIgnoresCollapseAndClearingRestoresIt() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "filter-collapse",
                includeChild: true
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        let toggleButton = try #require(
            findView(identifier: "outlineExpansionToggleButton", in: controller.view) as? NSButton
        )

        toggleButton.performClick(nil)
        #expect(outlineRows(in: controller.view).count == 2)

        setOutlineFilter("child", in: controller)
        #expect(outlineRows(in: controller.view).map(\.node.title) == [
            "filter-collapse 1",
            "filter-collapse child",
        ])
        #expect(toggleButton.isEnabled == false)

        setOutlineFilter("", in: controller)
        #expect(outlineRows(in: controller.view).count == 2)
        #expect(toggleButton.isEnabled)
        #expect(toggleButton.toolTip == "Expand outline")
    }

    @Test
    func outlineFilterShowsNoMatchingHeadingsState() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "filter-empty"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        setOutlineFilter("missing heading", in: controller)

        let emptyLabel = try #require(
            findView(identifier: "outlineEmptyStateLabel", in: controller.view) as? NSTextField
        )
        let scrollView = try #require(outlineScrollView(in: controller.view))
        #expect(outlineRows(in: controller.view).isEmpty)
        #expect(emptyLabel.stringValue == "No matching headings.")
        #expect(emptyLabel.isHidden == false)
        #expect(scrollView.isHidden)
    }

    @Test
    func collapsedOutlineStaysTopAnchoredWhenContentShrinks() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "top-anchored-outline",
                topLevelCount: 6,
                childrenPerTopLevel: 8
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 220, height: 360)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = outlineScrollView(in: controller.view),
              let documentView = scrollView.documentView,
              let toggleButton = findView(
                  identifier: "outlineExpansionToggleButton",
                  in: controller.view
              ) as? NSButton else {
            Issue.record("Failed to locate outline scroll views")
            return
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        toggleButton.performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        let rows = outlineRows(in: controller.view)
        #expect(rows.count == 6)
        #expect(documentView.frame.height < scrollView.contentSize.height)
        #expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)
        #expect(abs(rows[0].frame.minY) < 0.5)
    }

    @Test
    func switchingPDFClearsOldRowsWithMatchingPaths() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "switch-first",
                outlineTitles: ["First root", "First other"]
            )
        )
        let second = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "switch-second",
                outlineTitles: ["Second root", "Second other"]
            )
        )
        store.activate(sessionID: first.id)

        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 220, height: 360)
        controller.view.layoutSubtreeIfNeeded()

        #expect(outlineRows(in: controller.view).map(\.node.title) == ["First root", "First other"])

        store.activate(sessionID: second.id)
        controller.view.layoutSubtreeIfNeeded()

        let rows = outlineRows(in: controller.view)
        #expect(rows.map(\.node.title) == ["Second root", "Second other"])
        #expect(Set(rows.map { NSValue(rect: $0.frame) }).count == rows.count)
    }

    @Test
    func continuousReadingOutlineGroupsDocuments() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDFWithOutline(named: "continuous-outline-first"),
                makeTemporaryPDFWithOutline(named: "continuous-outline-second"),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))

        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        let rows = outlineRows(in: controller.view)
        guard rows.count >= 6 else {
            Issue.record("Failed to locate continuous outline roots")
            return
        }

        #expect(rows.count == 6)
        #expect(rows[0].node.isDocumentRoot)
        #expect(rows[0].node.sourceSessionID == sessions[0].id)
        #expect(rows[3].node.isDocumentRoot)
        #expect(rows[3].node.sourceSessionID == sessions[1].id)
    }

    @Test
    func continuousReadingOutlineRequestKeepsSourceSessionAndExactPoint() throws {
        let targetPoint = CGPoint(x: 42, y: 156)
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDFWithOutline(named: "continuous-request-first"),
                makeTemporaryPDFWithOutline(
                    named: "continuous-request-second",
                    outlinePoints: [targetPoint]
                ),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        var request: OutlineNavigationRequest?
        controller.onNavigationRequested = { request = $0 }
        controller.loadViewIfNeeded()

        let targetRow = try #require(
            outlineRows(in: controller.view).first {
                $0.node.sourceSessionID == sessions[1].id && $0.node.isDocumentRoot == false
            }
        )
        targetRow.performPrimaryAction()

        #expect(request == OutlineNavigationRequest(
            sessionID: sessions[1].id,
            position: ReadingPosition(pageIndex: 0, point: targetPoint)
        ))
    }
}

@MainActor
private func makeTemporaryPDFWithOutline(
    named name: String,
    outlineTitles: [String] = [],
    topLevelCount: Int = 2,
    childrenPerTopLevel: Int = 0,
    includeChild: Bool = false,
    outlinePoints: [CGPoint] = []
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    let pageCount = max(topLevelCount + childrenPerTopLevel * topLevelCount + (includeChild ? 1 : 0), 1)
    for index in 0..<pageCount {
        let image = NSImage(size: NSSize(width: 240, height: 320))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 240, height: 320)).fill()
        image.unlockFocus()
        guard let page = PDFPage(image: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        document.insert(page, at: index)
    }

    let root = PDFOutline()
    var childPageIndex = topLevelCount
    for index in 0..<topLevelCount {
        let item = PDFOutline()
        item.label = index < outlineTitles.count ? outlineTitles[index] : "\(name) \(index + 1)"
        let destinationPoint = outlinePoints.indices.contains(index) ? outlinePoints[index] : .zero
        item.destination = PDFDestination(
            page: document.page(at: min(index, pageCount - 1))!,
            at: destinationPoint
        )
        if includeChild, index == 0 {
            let child = PDFOutline()
            child.label = "\(name) child"
            child.destination = PDFDestination(page: document.page(at: min(childPageIndex, pageCount - 1))!, at: .zero)
            item.insertChild(child, at: 0)
            childPageIndex += 1
        }
        for childIndex in 0..<childrenPerTopLevel {
            let child = PDFOutline()
            child.label = "\(name) \(index + 1).\(childIndex + 1)"
            child.destination = PDFDestination(page: document.page(at: min(childPageIndex, pageCount - 1))!, at: .zero)
            item.insertChild(child, at: item.numberOfChildren)
            childPageIndex += 1
        }
        root.insertChild(item, at: index)
    }
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func outlineScrollView(in root: NSView) -> NSScrollView? {
    findView(identifier: "outlineScrollView", in: root) as? NSScrollView
}

@MainActor
private func outlineRows(in root: NSView) -> [OutlineRowView] {
    guard let rowsContainer = findView(identifier: "outlineRowsStack", in: root) else {
        return []
    }
    return rowsContainer.subviews
        .compactMap { $0 as? OutlineRowView }
        .sorted { $0.frame.minY < $1.frame.minY }
}

@MainActor
private func setOutlineFilter(_ query: String, in controller: OutlineViewController) {
    guard let field = findView(identifier: "outlineFilterField", in: controller.view) as? NSSearchField else {
        Issue.record("Failed to locate outline filter field")
        return
    }
    field.stringValue = query
    controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: field)
    )
}

@MainActor
private func hasPinnedEdgeConstraint(
    for view: NSView,
    in container: NSView,
    attribute: NSLayoutConstraint.Attribute
) -> Bool {
    container.constraints.contains { constraint in
        constraint.firstItem as? NSView === view &&
            constraint.firstAttribute == attribute &&
            constraint.secondItem as? NSView === container &&
            constraint.secondAttribute == attribute &&
            abs(constraint.constant) < 0.5
    }
}
