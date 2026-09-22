import AppKit
import PDFKit
import Testing
@testable import Serein

@MainActor
struct OutlineViewControllerTests {
    @Test
    func currentHeadingFollowsSamePageScrollWithoutReloading() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDFWithOutline(
            named: "same-page-follow",
            outlinePoints: [CGPoint(x: 0, y: 280), CGPoint(x: 0, y: 120)],
            outlinePageIndices: [0, 0]
        ))
        let controller = OutlineViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let reloadCount = controller.outlineReloadCount
        let pdfView = PDFView()
        controller.bind(to: pdfView)

        publishOutlinePosition(ReadingPosition(pageIndex: 0, point: CGPoint(x: 0, y: 240)), sessionID: session.id, pdfView: pdfView)
        #expect(controller.testingSelectedPath == [0])
        publishOutlinePosition(ReadingPosition(pageIndex: 0, point: CGPoint(x: 0, y: 100)), sessionID: session.id, pdfView: PDFView())
        #expect(controller.testingSelectedPath == [0])
        publishOutlinePosition(ReadingPosition(pageIndex: 0, point: CGPoint(x: 0, y: 100)), sessionID: session.id, pdfView: pdfView)
        #expect(controller.testingSelectedPath == [1])
        #expect(controller.outlineReloadCount == reloadCount)
    }

    @Test
    func followingExpandsAncestorsAndResumesAfterManualBrowsingEnds() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDFWithOutline(
            named: "outline-follow-pause", topLevelCount: 1, includeChild: true
        ))
        let controller = OutlineViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 240, height: 360)
        controller.view.layoutSubtreeIfNeeded()
        let pdfView = PDFView()
        controller.bind(to: pdfView)
        let toggle = try #require(findView(identifier: "outlineExpansionToggleButton", in: controller.view) as? NSButton)
        controller.testingSetPointerInside(true)
        toggle.performClick(nil)
        #expect(outlineRows(in: controller.view).count == 1)

        store.updateReadingPosition(ReadingPosition(pageIndex: 1, point: .zero), scaleFactor: 1, for: session.id)
        #expect(controller.testingActivePath == [0, 0])
        #expect(outlineRows(in: controller.view).count == 1)

        controller.testingSetPointerInside(false)
        #expect(outlineRows(in: controller.view).count == 1)
        publishOutlinePosition(ReadingPosition(pageIndex: 1, point: CGPoint(x: 0, y: -1)), sessionID: session.id, pdfView: pdfView)
        #expect(outlineRows(in: controller.view).count == 2)
        #expect(controller.testingSelectedPath == [0, 0])
    }

    @Test
    func readingFollowScrollsOnlyEnoughToRevealCurrentHeading() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "outline-reveal", topLevelCount: 30))
        let controller = OutlineViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 260, height: 320)
        controller.view.layoutSubtreeIfNeeded()
        let pdfView = PDFView()
        controller.bind(to: pdfView)
        let scroll = try #require(outlineScrollView(in: controller.view))
        store.updateReadingPosition(ReadingPosition(pageIndex: 20, point: .zero), scaleFactor: 1, for: session.id)
        let target = try #require(outlineRows(in: controller.view).first { $0.path == [20] })
        #expect(abs(scroll.contentView.bounds.maxY - target.frame.maxY) < 1)
        let followedY = scroll.contentView.bounds.minY

        publishOutlinePosition(ReadingPosition(pageIndex: 20, point: CGPoint(x: 0, y: -1)), sessionID: session.id, pdfView: pdfView)
        #expect(abs(scroll.contentView.bounds.minY - followedY) < 0.5)
    }

    @Test
    func keyboardFilterSelectionRequestsExactDestinationAndEscapeDoesNotNavigate() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDFWithOutline(
            named: "outline-keyboard",
            outlineTitles: ["Methods A", "Methods B", "Results"],
            topLevelCount: 3,
            outlinePoints: [CGPoint(x: 24, y: 260), CGPoint(x: 48, y: 180), CGPoint(x: 0, y: 300)]
        ))
        let controller = OutlineViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let field = try #require(findView(identifier: "outlineFilterField", in: controller.view) as? NSSearchField)
        var requests: [OutlineNavigationRequest] = []
        var completionCount = 0
        controller.onNavigationRequested = { requests.append($0) }
        controller.onQuickNavigationEnded = { completionCount += 1 }
        controller.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        field.stringValue = "methods"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(controller.testingSelectedPath == [0])
        let editor = NSTextView()
        #expect(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.testingSelectedPath == [1])
        #expect(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(requests == [OutlineNavigationRequest(
            sessionID: session.id,
            position: ReadingPosition(pageIndex: 1, point: CGPoint(x: 48, y: 180))
        )])
        #expect(field.stringValue.isEmpty)
        #expect(completionCount == 1)

        controller.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        #expect(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(requests.count == 1)
        #expect(completionCount == 2)
    }

    @Test
    func comparisonOutlineUsesFocusedSessionForCurrentHeadingAndNavigation() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "outline-comparison"))
        _ = store.outlineTree(for: source.id)
        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: source.id, in: store.defaultWindowID, targetPane: .secondary)
        let comparisonID = try #require(store.activeSessionID(in: store.defaultWindowID))
        #expect(comparisonID != source.id)
        let controller = OutlineViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        var request: OutlineNavigationRequest?
        controller.onNavigationRequested = { request = $0 }

        store.updateReadingPosition(ReadingPosition(pageIndex: 1, point: .zero), scaleFactor: 1, for: comparisonID)
        #expect(controller.testingSelectedPath == [1])
        let target = try #require(outlineRows(in: controller.view).first { $0.path == [1] })
        target.performPrimaryAction()
        #expect(request?.sessionID == comparisonID)
        #expect(store.session(for: source.id)?.currentPageIndex == 0)
    }

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
private func publishOutlinePosition(_ position: ReadingPosition, sessionID: UUID, pdfView: PDFView) {
    NotificationCenter.default.post(
        name: .readerViewportDidChange,
        object: pdfView,
        userInfo: ["position": position, "sessionID": sessionID]
    )
}

@MainActor
private func makeTemporaryPDFWithOutline(
    named name: String,
    outlineTitles: [String] = [],
    topLevelCount: Int = 2,
    childrenPerTopLevel: Int = 0,
    includeChild: Bool = false,
    outlinePoints: [CGPoint] = [],
    outlinePageIndices: [Int] = []
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
        let outlinePageIndex = outlinePageIndices.indices.contains(index) ? outlinePageIndices[index] : index
        item.destination = PDFDestination(
            page: document.page(at: min(outlinePageIndex, pageCount - 1))!,
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
