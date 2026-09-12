import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class AnnotationsViewControllerTests: XCTestCase {
    func testReaderContextMenuKeepsNativePDFKitItems() throws {
        let custom = NSMenu(title: "Serein")
        custom.addItem(NSMenuItem(title: "Highlight Selection", action: nil, keyEquivalent: ""))
        let native = NSMenu(title: "PDFKit")
        native.addItem(NSMenuItem(title: "Translate", action: nil, keyEquivalent: ""))
        native.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))

        let menu = try XCTUnwrap(ReaderPDFView.mergeContextMenus(custom: custom, native: native))

        XCTAssertEqual(menu.items.map(\.title), ["Highlight Selection", "", "Translate", "Look Up"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
    }

    func testMultipleCommentsShareOneFullHeightScrollableFeed() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-comment-feed"))
        let document = try store.pdfDocument(for: session.id)
        let records = try (0..<3).map { index in
            try makeHighlightRecord(
                in: document,
                bounds: NSRect(x: 24, y: 110 + CGFloat(index * 30), width: 120, height: 18)
            )
        }
        store.noteHighlightsAdded(records, for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let groups = store.annotationGroups(for: session.id)
        XCTAssertEqual(groups.count, 3)
        for (index, group) in groups.enumerated() {
            XCTAssertTrue(
                store.updateComment(
                    "Comment \(index + 1)",
                    forHighlightGroup: group.groupID,
                    in: session.id
                )
            )
        }

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 280, height: 520)
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? NSScrollView }.first)
        let tableView = try XCTUnwrap(scrollView.documentView as? NSTableView)
        let highlightRows = (0..<tableView.numberOfRows).filter {
            controller.tableView(tableView, shouldSelectRow: $0)
        }
        XCTAssertEqual(highlightRows.count, 3)
        XCTAssertEqual(scrollView.frame.minY, controller.view.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(scrollView.frame.maxY, controller.view.bounds.maxY, accuracy: 0.5)
        XCTAssertEqual(controller.view.subviews.compactMap { $0 as? NSScrollView }.count, 1)

        let visibleComments = highlightRows.compactMap { row -> String? in
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) else { return nil }
            return findAllDescendants(of: NSTextField.self, in: cell)
                .map(\.stringValue)
                .first { $0.hasPrefix("Comment ") }
        }
        XCTAssertEqual(Set(visibleComments), Set(["Comment 1", "Comment 2", "Comment 3"]))
    }

    func testRowPreviewsShowFullSnippetAndTrackWidthConsistently() throws {
        let snippet = "special tokens define hard segmentation boundaries"
        let group = DocumentHighlightGroup(
            groupID: "long-snippet",
            pageIndex: 0,
            snippet: snippet,
            color: .pink,
            createdAt: nil,
            comment: "",
            primarySelection: nil,
            records: []
        )

        let narrowWidth: CGFloat = 140
        let wideWidth: CGFloat = 420
        let narrowHeight = AnnotationHighlightCellView.preferredHeight(for: group, width: narrowWidth)
        let wideHeight = AnnotationHighlightCellView.preferredHeight(for: group, width: wideWidth)

        // Narrow wrap needs more vertical space than a single wide line.
        XCTAssertGreaterThan(narrowHeight, wideHeight)

        let narrowTextW = narrowWidth - 12 - 6
        let wideTextW = wideWidth - 12 - 6
        let narrowSnippetH = AnnotationHighlightCellView.measuredHeight(
            for: snippet,
            font: .systemFont(ofSize: 11.5, weight: .medium),
            width: narrowTextW,
            maximumLines: 0
        )
        let wideSnippetH = AnnotationHighlightCellView.measuredHeight(
            for: snippet,
            font: .systemFont(ofSize: 11.5, weight: .medium),
            width: wideTextW,
            maximumLines: 0
        )
        XCTAssertEqual(narrowHeight, ceil(12 + narrowSnippetH), accuracy: 0.5)
        XCTAssertEqual(wideHeight, ceil(12 + wideSnippetH), accuracy: 0.5)
        // Wide enough that the whole phrase is one line.
        XCTAssertEqual(
            wideSnippetH,
            ceil(
                NSFont.systemFont(ofSize: 11.5, weight: .medium).ascender
                    - NSFont.systemFont(ofSize: 11.5, weight: .medium).descender
                    + NSFont.systemFont(ofSize: 11.5, weight: .medium).leading
            ),
            accuracy: 1.5
        )

        let cell = AnnotationHighlightCellView(
            frame: NSRect(x: 0, y: 0, width: narrowWidth, height: narrowHeight)
        )
        cell.configure(with: group)
        cell.layoutSubtreeIfNeeded()
        let snippetLabel = try XCTUnwrap(findTextField(matching: snippet, in: cell))
        XCTAssertEqual(snippetLabel.stringValue, snippet)
        XCTAssertEqual(snippetLabel.frame.width, narrowTextW, accuracy: 0.5)
        XCTAssertEqual(snippetLabel.frame.height, narrowSnippetH, accuracy: 0.5)
        XCTAssertEqual(snippetLabel.preferredMaxLayoutWidth, narrowTextW, accuracy: 0.5)
        XCTAssertEqual(cell.toolTip?.contains("segmentation boundaries"), true)

        // Grow the cell: full text must remain, height shrinks to one line, width tracks.
        cell.frame = NSRect(x: 0, y: 0, width: wideWidth, height: wideHeight)
        cell.layoutSubtreeIfNeeded()
        XCTAssertEqual(snippetLabel.stringValue, snippet)
        XCTAssertEqual(snippetLabel.frame.width, wideTextW, accuracy: 0.5)
        XCTAssertEqual(snippetLabel.frame.height, wideSnippetH, accuracy: 0.5)
        XCTAssertEqual(snippetLabel.preferredMaxLayoutWidth, wideTextW, accuracy: 0.5)
    }

    func testRevealSelectsScrollsAndFocusesInlineEditor() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-reveal"))
        let document = try store.pdfDocument(for: session.id)
        let records = try (0..<4).map { index in
            try makeHighlightRecord(
                in: document,
                bounds: NSRect(x: 24, y: 80 + CGFloat(index * 30), width: 120, height: 18)
            )
        }
        store.noteHighlightsAdded(records, for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let targetGroup = try XCTUnwrap(store.annotationGroups(for: session.id).last)
        XCTAssertTrue(
            store.updateComment("Existing note", forHighlightGroup: targetGroup.groupID, in: session.id)
        )

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 280, height: 240)
        controller.view.layoutSubtreeIfNeeded()

        controller.reveal(groupID: targetGroup.groupID, focusEditor: true)

        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        XCTAssertGreaterThanOrEqual(tableView.selectedRow, 0)
        let cell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: tableView.selectedRow, makeIfNecessary: true)
                as? AnnotationHighlightCellView
        )
        let editor = try XCTUnwrap(findDescendant(of: NSTextView.self, in: cell))
        XCTAssertEqual(editor.string, "Existing note")
        XCTAssertTrue(window.firstResponder === editor)
        let clipBounds = try XCTUnwrap(tableView.enclosingScrollView?.contentView.bounds)
        XCTAssertTrue(clipBounds.intersects(tableView.rect(ofRow: tableView.selectedRow)))
    }

    func testCommandReturnSavesInlineComment() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-inline-save"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller

        controller.reveal(groupID: group.groupID, focusEditor: true)
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let cell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: tableView.selectedRow, makeIfNecessary: true)
                as? AnnotationHighlightCellView
        )
        let editor = try XCTUnwrap(findDescendant(of: NSTextView.self, in: cell))
        editor.string = "Saved inline"
        editor.keyDown(with: makeReturnKeyEvent(in: window, modifiers: [.command]))

        XCTAssertEqual(
            store.annotationGroups(for: session.id).first(where: { $0.groupID == group.groupID })?.comment,
            "Saved inline"
        )
    }

    func testSwitchingRowsCommitsInlineComment() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-switch-save"))
        let document = try store.pdfDocument(for: session.id)
        let records = try [
            makeHighlightRecord(in: document, bounds: NSRect(x: 24, y: 80, width: 120, height: 18)),
            makeHighlightRecord(in: document, bounds: NSRect(x: 24, y: 120, width: 120, height: 18)),
        ]
        store.noteHighlightsAdded(records, for: session.id)
        let groups = store.annotationSections(in: store.defaultWindowID).flatMap(\.highlights)
        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller

        controller.reveal(groupID: groups[0].groupID, focusEditor: true)
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let editor = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        editor.string = "Keep this draft"
        controller.reveal(groupID: groups[1].groupID, focusEditor: false)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        XCTAssertEqual(
            store.annotationGroups(for: session.id).first(where: { $0.groupID == groups[0].groupID })?.comment,
            "Keep this draft"
        )
    }

    func testSwitchingSplitPaneCommitsCommentToEditingSession() throws {
        let store = makeStore()
        let primarySession = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-primary-draft"))
        let secondarySession = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-secondary-draft"))
        let primaryRecord = try makeHighlightRecord(in: store.pdfDocument(for: primarySession.id))
        store.noteHighlightsAdded([primaryRecord], for: primarySession.id)
        let primaryGroup = try XCTUnwrap(store.annotationGroups(for: primarySession.id).first)

        store.activate(sessionID: primarySession.id, in: store.defaultWindowID, targetPane: .primary)
        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: secondarySession.id, in: store.defaultWindowID, targetPane: .secondary)
        store.setFocusedPane(.primary, in: store.defaultWindowID)

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.reveal(groupID: primaryGroup.groupID, focusEditor: true)
        let editor = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        editor.string = "Primary pane draft"

        store.setFocusedPane(.secondary, in: store.defaultWindowID)

        XCTAssertEqual(
            store.annotationGroups(for: primarySession.id)
                .first(where: { $0.groupID == primaryGroup.groupID })?.comment,
            "Primary pane draft"
        )
    }

    func testArrowKeysSelectHighlightsAndActivateExactlyOnce() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-keyboard"))
        let document = try store.pdfDocument(for: session.id)
        let records = try (0..<3).map { index in
            try makeHighlightRecord(
                in: document,
                bounds: NSRect(x: 24, y: 80 + CGFloat(index * 30), width: 120, height: 18)
            )
        }
        store.noteHighlightsAdded(records, for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let groups = store.annotationSections(in: store.defaultWindowID).flatMap(\.highlights)
        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.reveal(groupID: groups[0].groupID, focusEditor: false)
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        var activatedGroupIDs: [String] = []
        controller.onActivateHighlight = { activatedGroupIDs.append($0.groupID) }

        tableView.keyDown(with: makeKeyEvent(characters: "\u{F701}", keyCode: 125))
        XCTAssertEqual(activatedGroupIDs, [groups[1].groupID])

        tableView.keyDown(with: makeKeyEvent(characters: "\u{F700}", keyCode: 126))
        XCTAssertEqual(activatedGroupIDs, [groups[1].groupID, groups[0].groupID])
    }

    func testAnnotationsColumnTracksSidebarWidthAndCellsStayVisible() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-width-visibility"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: controller.view))
        let tableView = try XCTUnwrap(scrollView.documentView as? NSTableView)
        let column = try XCTUnwrap(tableView.tableColumns.first)
        XCTAssertGreaterThan(column.width, 200)
        XCTAssertEqual(column.width, scrollView.bounds.width, accuracy: 1.5)

        let highlightRow = try XCTUnwrap((0..<tableView.numberOfRows).first { row in
            controller.tableView(tableView, shouldSelectRow: row)
        })
        let rowHeight = controller.tableView(tableView, heightOfRow: highlightRow)
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: highlightRow, makeIfNecessary: true))
        cell.frame = NSRect(x: 0, y: 0, width: column.width, height: rowHeight)
        cell.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(findDescendant(of: NSTextField.self, in: cell))
        XCTAssertGreaterThan(textField.frame.width, 100)
    }

    func testSingleClickActivatesHighlightAndDoubleClickOpensEditor() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "single-click-highlight"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.loadViewIfNeeded()
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let highlightRow = try XCTUnwrap((0..<tableView.numberOfRows).first {
            controller.tableView(tableView, shouldSelectRow: $0)
        })
        var activatedGroupIDs: [String] = []
        controller.onActivateHighlight = { activatedGroupIDs.append($0.groupID) }

        tableView.selectRowIndexes(IndexSet(integer: highlightRow), byExtendingSelection: false)
        XCTAssertTrue(activatedGroupIDs.isEmpty)
        let target = try XCTUnwrap(tableView.target as? NSObject)
        let action = try XCTUnwrap(tableView.action)
        _ = target.perform(action, with: tableView)
        let doubleAction = try XCTUnwrap(tableView.doubleAction)
        _ = target.perform(doubleAction, with: tableView)

        XCTAssertEqual(activatedGroupIDs.count, 1)
        XCTAssertNotEqual(doubleAction, action)
        let editor = findDescendant(of: NSTextView.self, in: controller.view)
        XCTAssertNotNil(editor)
        XCTAssertTrue(window.firstResponder === editor)
    }

    func testAnnotationActivationThroughMainWindowJumpsWithoutLeavingSelection() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let url = try TestPDFFixtures.makeSearchablePDF(
            named: "window-annotation-navigation",
            pages: ["intro page", "annotation target on second page"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let sourceSelection = try XCTUnwrap(
            document.findString("annotation target", withOptions: []).first
        )
        let sourcePage = try XCTUnwrap(sourceSelection.pages.first)
        let sourcePageIndex = document.index(for: sourcePage)
        let sourceBounds = sourceSelection.bounds(for: sourcePage)
        let record = try makeHighlightRecord(
            in: document,
            pageIndex: sourcePageIndex,
            bounds: sourceBounds
        )
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        store.setRightSidebarMode(.annotations, in: store.defaultWindowID)

        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushAnnotationNavigationLayout(windowController.window)

        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let controller = split.rightSidebarViewController.annotationsViewController
        controller.loadViewIfNeeded()
        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        let expectedSelection = try XCTUnwrap(group.primarySelection)
        let expectedPage = try XCTUnwrap(expectedSelection.pages.first)
        let expectedBounds = expectedSelection.bounds(for: expectedPage)
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let highlightRow = try XCTUnwrap((0..<tableView.numberOfRows).first {
            controller.tableView(tableView, shouldSelectRow: $0)
        })

        tableView.selectRowIndexes(IndexSet(integer: highlightRow), byExtendingSelection: false)
        let target = try XCTUnwrap(tableView.target as? NSObject)
        let action = try XCTUnwrap(tableView.action)
        _ = target.perform(action, with: tableView)
        flushAnnotationNavigationLayout(windowController.window)

        let reader = split.readerViewController
        XCTAssertEqual(reader.displayedSessionID, session.id)
        XCTAssertTrue(reader.pdfView.document === document)
        // Focus uses a pulse overlay instead of leaving a dashed PDFSelection.
        XCTAssertNil(reader.pdfView.currentSelection)
        let currentPage = try XCTUnwrap(reader.pdfView.currentPage)
        XCTAssertEqual(reader.pdfView.document?.index(for: currentPage), sourcePageIndex)
        XCTAssertEqual(
            store.session(for: session.id)?.lastReadPosition,
            ReadingPosition(
                pageIndex: sourcePageIndex,
                point: NSPoint(x: expectedBounds.minX, y: expectedBounds.maxY)
            )
        )
        XCTAssertTrue(reader.pdfView.bounds.intersects(reader.pdfView.convert(expectedBounds, from: expectedPage)))
    }

    func testReaderContextMenuPrefersClickedHighlightOverStaleSelection() throws {
        let store = makeStore()
        let url = try TestPDFFixtures.makeSearchablePDF(
            named: "reader-comment-context",
            pages: ["stale selection and comment target"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let targetSelection = try XCTUnwrap(document.findString("comment target", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: targetSelection)
        store.noteHighlightsAdded(records, for: session.id)

        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushAnnotationNavigationLayout(windowController.window)
        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let reader = split.readerViewController
        reader.pdfView.currentSelection = try XCTUnwrap(
            document.findString("stale selection", withOptions: []).first
        )

        let annotation = records[0].annotation
        let page = try XCTUnwrap(annotation.page)
        let annotationBounds = reader.pdfView.convert(annotation.bounds, from: page)
        let pointInWindow = reader.pdfView.convert(
            NSPoint(x: annotationBounds.midX, y: annotationBounds.midY),
            to: nil
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: try XCTUnwrap(windowController.window).windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        let menu = try XCTUnwrap(reader.pdfView.menu(for: event))
        let editItem = try XCTUnwrap(menu.item(withTitle: "Edit Comment"))
        XCTAssertEqual(editItem.keyEquivalent, "m")
        XCTAssertEqual(editItem.keyEquivalentModifierMask, [.command, .option])
        XCTAssertTrue(menu.item(withTitle: "Remove Annotation")?.isEnabled == true)

        let previousMode = store.rightSidebarMode(in: store.defaultWindowID)
        let target = try XCTUnwrap(editItem.target as? NSObject)
        let action = try XCTUnwrap(editItem.action)
        _ = target.perform(action, with: editItem)

        XCTAssertEqual(store.annotationGroups(for: session.id).count, 1)
        // Reader comment edit uses a local popover; it must not force the Annotations pane.
        XCTAssertEqual(store.rightSidebarMode(in: store.defaultWindowID), previousMode)
        XCTAssertNotEqual(previousMode, .annotations)
    }

    func testDoubleClickHighlightOpensOwnCommentPanel() throws {
        let store = makeStore()
        let url = try TestPDFFixtures.makeSearchablePDF(
            named: "reader-reveal-annotation",
            pages: ["double click annotation target"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("annotation target", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection)
        store.noteHighlightsAdded(records, for: session.id)
        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        store.setRightSidebarVisible(false, in: store.defaultWindowID)

        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushAnnotationNavigationLayout(windowController.window)
        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let reader = split.readerViewController
        let annotation = try XCTUnwrap(records.first?.annotation)
        let page = try XCTUnwrap(annotation.page)
        let annotationBounds = reader.pdfView.convert(annotation.bounds, from: page)
        let pointInWindow = reader.pdfView.convert(
            NSPoint(x: annotationBounds.midX, y: annotationBounds.midY),
            to: nil
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: try XCTUnwrap(windowController.window).windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 2,
                pressure: 1
            )
        )

        reader.pdfView.mouseDown(with: event)

        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
        let panel = try XCTUnwrap(windowController.window?.childWindows?.compactMap { $0 as? AnnotationCommentPanel }.first)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(store.annotationGroups(for: session.id).first?.groupID, group.groupID)
    }

    func testSidebarContextMenuCanRecolorAndDelete() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-context-actions"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.reveal(groupID: group.groupID, focusEditor: false)

        var deleted: DocumentHighlightGroup?
        var recolored: (DocumentHighlightGroup, HighlightColor)?
        controller.onDeleteHighlight = { deleted = $0 }
        controller.onChangeHighlightColor = { recolored = ($0, $1) }

        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let menu = try XCTUnwrap(tableView.menu(for: makeRightClickEvent(in: tableView)))
        XCTAssertNotNil(menu.item(withTitle: "Edit Comment"))
        XCTAssertNotNil(menu.item(withTitle: "Copy Snippet"))
        XCTAssertNotNil(menu.item(withTitle: "Delete"))
        let colorItem = try XCTUnwrap(menu.item(withTitle: "Color"))
        let yellow = try XCTUnwrap(colorItem.submenu?.item(withTitle: "Yellow"))
        let yellowTarget = try XCTUnwrap(yellow.target as? NSObject)
        let yellowAction = try XCTUnwrap(yellow.action)
        _ = yellowTarget.perform(yellowAction, with: yellow)
        XCTAssertEqual(recolored?.0.groupID, group.groupID)
        XCTAssertEqual(recolored?.1, .yellow)

        let delete = try XCTUnwrap(menu.item(withTitle: "Delete"))
        let deleteTarget = try XCTUnwrap(delete.target as? NSObject)
        let deleteAction = try XCTUnwrap(delete.action)
        _ = deleteTarget.perform(deleteAction, with: delete)
        XCTAssertEqual(deleted?.groupID, group.groupID)
    }

    func testEmptyStateShowsShortcutHint() throws {
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-annotations-hint"))
        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let emptyLabel = try XCTUnwrap(
            findAllDescendants(of: NSTextField.self, in: controller.view)
                .first { $0.stringValue.contains("⌘⌥M") }
        )
        XCTAssertTrue(emptyLabel.stringValue.contains("No annotations"))
        XCTAssertFalse(emptyLabel.isHidden)
    }

    func testRowShowsSnippetAndCommentWithoutTimestamp() {
        let group = DocumentHighlightGroup(
            groupID: "no-time",
            pageIndex: 2,
            snippet: "snippet text",
            color: .pink,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            comment: "note",
            primarySelection: nil,
            records: []
        )
        let cell = AnnotationHighlightCellView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        cell.configure(with: group)
        let labels = findAllDescendants(of: NSTextField.self, in: cell).map(\.stringValue)
        XCTAssertTrue(labels.contains("snippet text"))
        XCTAssertTrue(labels.contains("note"))
        XCTAssertFalse(labels.contains { $0.contains("Page") })
        XCTAssertFalse(labels.contains { $0.contains("202") || $0.contains(":") })
    }

    func testAnnotationsListDisablesHorizontalScrolling() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "annotations-no-hscroll"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id)

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 220, height: 400)
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: controller.view))
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(scrollView.horizontalScrollElasticity, .none)
        let tableView = try XCTUnwrap(scrollView.documentView as? NSTableView)
        let column = try XCTUnwrap(tableView.tableColumns.first)
        XCTAssertEqual(column.width, scrollView.bounds.width, accuracy: 1.5)
        XCTAssertEqual(column.minWidth, column.width, accuracy: 0.5)
        XCTAssertEqual(column.maxWidth, column.width, accuracy: 0.5)
        XCTAssertEqual(tableView.frame.width, column.width, accuracy: 1.5)
    }

    func testPreviewConfigureRejectsCommentlessHighlights() {
        let preview = AnnotationPreviewView(frame: .zero)
        let withoutComment = DocumentHighlightGroup(
            groupID: "bare",
            pageIndex: 0,
            snippet: "only highlight",
            color: .yellow,
            createdAt: nil,
            comment: "  ",
            primarySelection: nil,
            records: []
        )
        XCTAssertFalse(preview.configure(with: withoutComment))

        let withComment = DocumentHighlightGroup(
            groupID: "noted",
            pageIndex: 0,
            snippet: "snippet",
            color: .pink,
            createdAt: nil,
            comment: "memo",
            primarySelection: nil,
            records: []
        )
        XCTAssertTrue(preview.configure(with: withComment))
        let size = preview.preferredSize(maxWidth: 400)
        XCTAssertGreaterThanOrEqual(size.width, 220)
        XCTAssertLessThanOrEqual(size.width, 360)
        XCTAssertEqual(preview.preferredSize(maxWidth: 120).width, 120)
    }

    func testPreviewLaysOutWrappedAndExplicitCommentLines() throws {
        _ = NSApplication.shared
        let preview = AnnotationPreviewView(frame: .zero)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = preview
        defer { window.close() }

        for (index, comment) in [
            "第一行评论\n第二行评论\n第三行评论",
            "这是一段较长的评论，用于检查预览中的文字能否自动换行。缩窄卡片后，评论应该显示为多行，并且每一行都有足够的高度。",
        ].enumerated() {
            XCTAssertTrue(preview.configure(with: DocumentHighlightGroup(
                groupID: "multiline-preview", pageIndex: 0, snippet: "Original passage",
                color: .pink, createdAt: nil, comment: comment, primarySelection: nil, records: []
            )))
            window.setContentSize(preview.preferredSize(maxWidth: 240))
            preview.needsLayout = true
            preview.layoutSubtreeIfNeeded()
            let label = try XCTUnwrap(preview.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == comment })
            let requiredHeight = try XCTUnwrap(label.cell).cellSize(forBounds:
                NSRect(x: 0, y: 0, width: label.frame.width, height: 1_000)).height
            XCTAssertGreaterThan(label.frame.height, 28)
            XCTAssertGreaterThanOrEqual(label.frame.height, requiredHeight)
            XCTAssertGreaterThanOrEqual(label.frame.minY, 10)

            if let path = ProcessInfo.processInfo.environment["SEREIN_PREVIEW_SNAPSHOTS"] {
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("preview-\(index).png"))
            }
        }
    }

    func testReaderContextMenuFocusesItsSourceSplitPane() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "reader-context-pane"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )

        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: session.id, in: store.defaultWindowID, targetPane: .secondary)
        store.setFocusedPane(.primary, in: store.defaultWindowID)
        flushAnnotationNavigationLayout(windowController.window)
        let secondaryReader = split.readerWorkspaceViewController.secondaryReaderViewController
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: try XCTUnwrap(windowController.window).windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        _ = secondaryReader.pdfView.menu(for: event)

        XCTAssertEqual(store.focusedPane(in: store.defaultWindowID), .secondary)
    }

    func testReaderContextMenuIncludesCopyPageAsImage() throws {
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "copy-page-menu"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushAnnotationNavigationLayout(windowController.window)

        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let reader = split.readerViewController
        let event = makeRightClickEvent(in: reader.pdfView)
        let menu = try XCTUnwrap(reader.pdfView.menu(for: event))
        let item = try XCTUnwrap(menu.item(withTitle: ShortcutCommand.copyCurrentPageAsImage.menuTitle))

        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.keyEquivalent, "c")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])
    }

    func testReaderContextMenuSendsSelectionAndPageImageToCodexHandlers() throws {
        let store = makeStore()
        let url = try TestPDFFixtures.makeSearchablePDF(
            named: "codex-context-menu",
            pages: ["selected text for Codex"]
        )
        _ = try store.open(documentAt: url)
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushAnnotationNavigationLayout(windowController.window)

        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let reader = split.readerViewController
        reader.pdfView.currentSelection = try XCTUnwrap(
            reader.pdfView.document?.findString("selected text", withOptions: []).first
        )
        var sentText: String?
        var sentPageNumber: Int?
        var sentImage: NSImage?
        reader.onSendSelectionToCodexRequested = { sentText = $0 }
        reader.onSendPageImageToCodexRequested = { image, pageNumber in
            sentImage = image
            sentPageNumber = pageNumber
        }

        let selectionMenu = try XCTUnwrap(
            reader.pdfView.menu(for: makeRightClickEvent(in: reader.pdfView))
        )
        let selectionItem = try XCTUnwrap(
            selectionMenu.item(withTitle: "Send Selection to Codex")
        )

        selectionMenu.performActionForItem(at: selectionMenu.index(of: selectionItem))
        XCTAssertEqual(sentText, "selected text")
        XCTAssertNil(sentImage)

        reader.pdfView.currentSelection = nil
        let pageMenu = try XCTUnwrap(reader.pdfView.menu(for: makeRightClickEvent(in: reader.pdfView)))
        let pageItem = try XCTUnwrap(pageMenu.item(withTitle: "Send Page Image to Codex"))
        pageMenu.performActionForItem(at: pageMenu.index(of: pageItem))

        XCTAssertEqual(sentPageNumber, 1)
        XCTAssertNotNil(sentImage)

        var configuration = store.appConfiguration
        configuration.integrations.codexEnabled = false
        store.updateAppConfiguration(configuration)
        let disabledMenu = try XCTUnwrap(
            reader.pdfView.menu(for: makeRightClickEvent(in: reader.pdfView))
        )
        XCTAssertNil(disabledMenu.item(withTitle: "Send Selection to Codex"))
        XCTAssertNil(disabledMenu.item(withTitle: "Send Page Image to Codex"))
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
    }
}

@MainActor
private func makeRightClickEvent(in view: NSView) -> NSEvent {
    let location = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
    let pointInWindow = view.convert(location, to: nil)
    return NSEvent.mouseEvent(
        with: .rightMouseDown,
        location: pointInWindow,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: view.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
    )!
}

@MainActor
private func makeHighlightRecord(
    in document: PDFDocument,
    pageIndex: Int = 0,
    bounds: NSRect = NSRect(x: 24, y: 110, width: 120, height: 18)
) throws -> HighlightAnnotationRecord {
    guard let page = document.page(at: pageIndex) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let annotation = PDFAnnotation(
        bounds: bounds,
        forType: .highlight,
        withProperties: nil
    )
    annotation.color = HighlightColor.default.nsColor
    annotation.userName = UUID().uuidString
    annotation.modificationDate = Date(timeIntervalSinceReferenceDate: 1)
    page.addAnnotation(annotation)

    return HighlightAnnotationRecord(pageIndex: pageIndex, annotation: annotation)
}


@MainActor
private func makeTemporaryPDF(named name: String) throws -> URL {
    try TestPDFFixtures.makeLabeledPDF(named: name)
}

@MainActor
private func flushAnnotationNavigationLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}

@MainActor
private func findAllDescendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
    var matches: [T] = []
    if let root = root as? T {
        matches.append(root)
    }
    for subview in root.subviews {
        matches.append(contentsOf: findAllDescendants(of: type, in: subview))
    }
    return matches
}
