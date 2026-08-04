import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class AnnotationsViewControllerTests: XCTestCase {
    func testApplyCommentPersistsFromSidebarEditor() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-comment"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        let applyButton = try XCTUnwrap(findButton(titled: "Apply", in: controller.view))

        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(textView.allowsUndo)
        XCTAssertFalse(textView.isRichText)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, true)

        textView.string = "Sidebar comment"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertTrue(applyButton.isEnabled)

        applyButton.performClick(nil)

        XCTAssertEqual(store.annotationGroups(for: session.id).first?.comment, "Sidebar comment")
    }

    func testApplyCommentSurvivesMomentarySelectionLoss() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-selection"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let applyButton = try XCTUnwrap(findButton(titled: "Apply", in: controller.view))

        textView.string = "Selection-safe comment"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertTrue(applyButton.isEnabled)

        tableView.allowsEmptySelection = true
        tableView.deselectAll(nil)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        XCTAssertTrue(applyButton.isEnabled)

        applyButton.performClick(nil)

        XCTAssertEqual(store.annotationGroups(for: session.id).first?.comment, "Selection-safe comment")
    }

    func testLongSnippetRowsExpandAndDoNotStaySingleLine() throws {
        let group = DocumentHighlightGroup(
            groupID: "long-snippet",
            pageIndex: 0,
            snippet: "Compressed Sparse Attention keeps long highlight snippets readable in the sidebar list.",
            color: .pink,
            createdAt: nil,
            comment: "",
            primarySelection: nil,
            records: []
        )
        let rowHeight = AnnotationHighlightCellView.preferredHeight(for: group, width: 240)
        XCTAssertGreaterThan(rowHeight, 46)

        let cell = AnnotationHighlightCellView(frame: NSRect(x: 0, y: 0, width: 240, height: rowHeight))
        cell.configure(with: group)
        let snippetLabel = try XCTUnwrap(
            findTextField(
                matching: "Compressed Sparse Attention keeps long highlight snippets readable in the sidebar list.",
                in: cell
            )
        )
        XCTAssertEqual(snippetLabel.maximumNumberOfLines, 0)
        XCTAssertEqual(snippetLabel.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(snippetLabel.cell?.wraps, true)
        XCTAssertEqual(snippetLabel.cell?.usesSingleLineMode, false)
        XCTAssertNil(findTextField(matching: "No comment", in: cell))
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
        XCTAssertEqual(column.width, scrollView.contentSize.width, accuracy: 0.5)

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

    func testSingleClickActivatesHighlightOnceAndHasNoDoubleAction() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "single-click-highlight"))
        let record = try makeHighlightRecord(in: store.pdfDocument(for: session.id))
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
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
    }

    func testAnnotationActivationThroughMainWindowFocusesExactSelection() throws {
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
        let actualSelection = try XCTUnwrap(reader.pdfView.currentSelection)
        let actualPage = try XCTUnwrap(actualSelection.pages.first)
        let actualBounds = actualSelection.bounds(for: actualPage)
        XCTAssertEqual(reader.pdfView.document?.index(for: actualPage), sourcePageIndex)
        XCTAssertEqual(actualSelection.string, expectedSelection.string)
        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 0.5)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.5)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 0.5)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 0.5)
        let currentPage = try XCTUnwrap(reader.pdfView.currentPage)
        XCTAssertEqual(reader.pdfView.document?.index(for: currentPage), sourcePageIndex)
        XCTAssertEqual(
            store.session(for: session.id)?.lastReadPosition,
            ReadingPosition(
                pageIndex: sourcePageIndex,
                point: NSPoint(x: expectedBounds.minX, y: expectedBounds.maxY)
            )
        )
        XCTAssertTrue(reader.pdfView.bounds.intersects(reader.pdfView.convert(actualBounds, from: actualPage)))
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
    }
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
