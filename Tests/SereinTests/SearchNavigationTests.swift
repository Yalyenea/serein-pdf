import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class SearchNavigationTests: XCTestCase {
    func testFirstSubmitOnlySearchesAndSecondSubmitStartsNavigation() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "repeat-submit",
            pages: ["needle alpha needle beta needle"]
        )
        let session = try store.open(documentAt: url)
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.showFindBar()

        var actions: [FindNavigationAction] = []
        reader.onFindActionRequested = { actions.append($0) }

        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)
        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)

        XCTAssertEqual(actions, [.activateNext])
    }

    func testFirstBrowseStepSelectsFirstMatchWithoutSkipping() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "first-browse-step",
            pages: ["needle alpha needle beta needle"]
        )
        _ = try store.open(documentAt: url)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.selectedMatch())
        XCTAssertEqual(controller.selectionSummary().selectedIndex, nil)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 0)
        XCTAssertEqual(controller.selectionSummary().selectedIndex, 0)
    }

    func testSingleClickActivatesSelectedMatchAndHasNoDoubleAction() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "single-click-activation",
            pages: ["needle alpha needle"]
        )
        _ = try store.open(documentAt: url)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let matchRow = try XCTUnwrap((0..<tableView.numberOfRows).first {
            controller.tableView(tableView, shouldSelectRow: $0)
        })
        var activatedMatches: [SearchSidebarMatch] = []
        controller.onActivateMatch = { activatedMatches.append($0) }

        tableView.selectRowIndexes(IndexSet(integer: matchRow), byExtendingSelection: false)
        XCTAssertTrue(activatedMatches.isEmpty)
        let target = try XCTUnwrap(tableView.target as? NSObject)
        let action = try XCTUnwrap(tableView.action)
        _ = target.perform(action, with: tableView)
        let doubleAction = try XCTUnwrap(tableView.doubleAction)
        _ = target.perform(doubleAction, with: tableView)

        XCTAssertEqual(activatedMatches.map(\.matchIndex), [0])
        XCTAssertNotEqual(doubleAction, action)
    }

    func testSearchSelectionSurvivesStoreRefreshAndContinuesNavigation() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "selection-refresh",
            pages: ["needle alpha needle beta needle"]
        )
        let session = try store.open(documentAt: url)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.selectedMatch())
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 0)

        store.activate(sessionID: session.id, in: store.defaultWindowID, targetPane: .primary)

        XCTAssertEqual(controller.selectedMatch()?.matchIndex, 0)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 1)
    }

    func testShowFindBarCanForceAllOpenScopeAndRequery() throws {
        let store = makeStore()
        let first = try makeSearchableTemporaryPDF(
            named: "scope-primary",
            pages: ["needle alpha beta"]
        )
        let second = try makeSearchableTemporaryPDF(
            named: "scope-secondary",
            pages: ["needle gamma delta"]
        )
        let session = try store.open(documentAt: first)
        _ = try store.open(documentAt: second)

        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()

        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .currentDocument)
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 1)

        reader.showFindBar(scope: .allOpen)

        XCTAssertTrue(reader.isFindBarVisible)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .allOpen)
        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "needle")
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 2)
    }

    func testShowFindBarPrefillsSearchFromCurrentPDFSelection() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "selection-prefill-current",
            pages: ["alpha selected phrase beta selected phrase"]
        )
        let session = try store.open(documentAt: url)
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.pdfView.currentSelection = try XCTUnwrap(
            reader.pdfView.document?.findString("selected phrase", withOptions: []).first
        )

        reader.showFindBar(scope: .currentDocument)

        XCTAssertTrue(reader.isFindBarVisible)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .currentDocument)
        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "selected phrase")
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 2)
    }

    func testEmptyStateUsesSameContentBandAsResultsList() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "empty-state-inset",
            pages: ["needle alpha beta"]
        )
        _ = try store.open(documentAt: url)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: controller.view))
        let emptyLabel = try XCTUnwrap(
            controller.view.subviews.first { $0.identifier?.rawValue == "searchEmptyStateLabel" } as? NSTextField
        )

        XCTAssertFalse(emptyLabel.isHidden)
        XCTAssertFalse(scrollView.isHidden)
        let layoutConstraints = controller.view.constraints + emptyLabel.constraints + scrollView.constraints
        XCTAssertTrue(
            layoutConstraints.contains {
                ($0.firstItem as? NSView) === emptyLabel &&
                    $0.firstAttribute == .leading &&
                    ($0.secondItem as? NSView) === scrollView &&
                    $0.secondAttribute == .leading
            }
        )
        XCTAssertTrue(
            layoutConstraints.contains {
                ($0.firstItem as? NSView) === emptyLabel &&
                    $0.firstAttribute == .trailing &&
                    ($0.secondItem as? NSView) === scrollView &&
                    $0.secondAttribute == .trailing
            }
        )

        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(emptyLabel.isHidden)
        XCTAssertFalse(scrollView.isHidden)
        XCTAssertGreaterThan(controller.selectionSummary().totalMatches, 0)
    }

    func testShowFindBarPrefillsSelectionForAllOpenSearch() throws {
        let store = makeStore()
        let first = try makeSearchableTemporaryPDF(
            named: "selection-prefill-all-open-first",
            pages: ["alpha shared needle beta"]
        )
        let second = try makeSearchableTemporaryPDF(
            named: "selection-prefill-all-open-second",
            pages: ["gamma shared needle delta"]
        )
        let session = try store.open(documentAt: first)
        _ = try store.open(documentAt: second)

        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.pdfView.currentSelection = try XCTUnwrap(
            reader.pdfView.document?.findString("shared needle", withOptions: []).first
        )

        reader.showFindBar(scope: .allOpen)

        XCTAssertTrue(reader.isFindBarVisible)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .allOpen)
        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "shared needle")
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 2)
    }

    func testSplitControllerFindNextAdvancesSelectionWithActivate() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "split-find-next",
            pages: ["needle alpha needle beta needle"]
        )
        _ = try store.open(documentAt: url)

        let split = SplitViewController(documentStore: store, windowID: store.defaultWindowID)
        split.loadViewIfNeeded()
        split.rightSidebarViewController.loadViewIfNeeded()
        split.rightSidebarViewController.searchResultsViewController.loadViewIfNeeded()
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let searchVC = split.rightSidebarViewController.searchResultsViewController
        XCTAssertTrue(split.findNextMatch())
        XCTAssertEqual(searchVC.selectionSummary().selectedIndex, 0)
        XCTAssertTrue(split.findNextMatch())
        XCTAssertEqual(searchVC.selectionSummary().selectedIndex, 1)
        XCTAssertTrue(split.findNextMatch())
        XCTAssertEqual(searchVC.selectionSummary().selectedIndex, 2)
    }

    func testRepeatedSubmitNavigatesThroughSplitWiring() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "submit-navigate-wired",
            pages: ["needle alpha needle beta"]
        )
        let session = try store.open(documentAt: url)

        let split = SplitViewController(documentStore: store, windowID: store.defaultWindowID)
        split.loadViewIfNeeded()
        split.rightSidebarViewController.loadViewIfNeeded()
        split.rightSidebarViewController.searchResultsViewController.loadViewIfNeeded()
        let reader = split.readerViewController
        reader.targetSessionID = session.id
        reader.showFindBar()

        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)
        XCTAssertNil(
            split.rightSidebarViewController.searchResultsViewController.selectionSummary().selectedIndex
        )

        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)
        XCTAssertEqual(
            split.rightSidebarViewController.searchResultsViewController.selectionSummary().selectedIndex,
            0
        )

        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)
        XCTAssertEqual(
            split.rightSidebarViewController.searchResultsViewController.selectionSummary().selectedIndex,
            1
        )
    }

    func testSearchActivationThroughMainWindowDisplaysExactSelection() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "window-search-selection",
            pages: ["intro page", "needle target on second page"]
        )
        let session = try store.open(documentAt: url)
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushSearchNavigationLayout(windowController.window)

        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        flushSearchNavigationLayout(windowController.window)
        let match = try XCTUnwrap(
            store.searchSections(in: store.defaultWindowID).flatMap(\.matches).first
        )

        XCTAssertTrue(split.findNextMatch())
        flushSearchNavigationLayout(windowController.window)

        try assertReader(
            split.readerViewController,
            displays: match,
            in: session.id,
            store: store
        )
    }

    func testAllOpenSearchSwitchesDocumentAndBackRestoresPreviousReaderPosition() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let firstURL = try makeSearchableTemporaryPDF(
            named: "all-open-navigation-first",
            pages: ["intro page", "needle first document"]
        )
        let secondURL = try makeSearchableTemporaryPDF(
            named: "all-open-navigation-second",
            pages: ["needle second document"]
        )
        let firstSession = try store.open(documentAt: firstURL)
        let secondSession = try store.open(documentAt: secondURL)
        store.activate(sessionID: firstSession.id, in: store.defaultWindowID)

        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        flushSearchNavigationLayout(windowController.window)

        let split = try XCTUnwrap(
            windowController.window?.contentViewController as? SplitViewController
        )
        let reader = split.readerViewController
        store.updateSearch(query: "needle", scope: .allOpen, in: store.defaultWindowID)
        flushSearchNavigationLayout(windowController.window)
        let matches = store.searchSections(in: store.defaultWindowID).flatMap(\.matches)
        XCTAssertEqual(matches.map(\.sessionID), [firstSession.id, secondSession.id])
        let firstMatch = try XCTUnwrap(matches.first)
        let secondMatch = try XCTUnwrap(matches.dropFirst().first)

        XCTAssertTrue(split.findNextMatch())
        flushSearchNavigationLayout(windowController.window)
        try assertReader(reader, displays: firstMatch, in: firstSession.id, store: store)

        XCTAssertTrue(split.findNextMatch())
        flushSearchNavigationLayout(windowController.window)
        try assertReader(reader, displays: secondMatch, in: secondSession.id, store: store)
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), secondSession.id)

        let backSessionID = try XCTUnwrap(reader.testingNavigationBackSessionIDs.last)
        let backPosition = try XCTUnwrap(reader.testingNavigationBackPositions.last)
        XCTAssertEqual(backSessionID, firstSession.id)

        windowController.navigateBack()
        flushSearchNavigationLayout(windowController.window)

        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), firstSession.id)
        XCTAssertEqual(reader.displayedSessionID, firstSession.id)
        XCTAssertTrue(reader.pdfView.document === (try store.pdfDocument(for: firstSession.id)))
        let currentPage = try XCTUnwrap(reader.pdfView.currentPage)
        XCTAssertEqual(reader.pdfView.document?.index(for: currentPage), backPosition.pageIndex)
        XCTAssertEqual(store.session(for: firstSession.id)?.lastReadPosition, backPosition)
        let livePosition = try XCTUnwrap(reader.testingCurrentReadingPosition)
        XCTAssertEqual(livePosition.pageIndex, backPosition.pageIndex)
        let backTargetPage = try XCTUnwrap(firstMatch.selection.pages.first)
        let backTargetBounds = firstMatch.selection.bounds(for: backTargetPage)
        XCTAssertTrue(
            reader.pdfView.bounds.intersects(
                reader.pdfView.convert(backTargetBounds, from: backTargetPage)
            )
        )
    }

    func testSelectionSurvivesActivateUnderSplitObservers() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "split-activate-survive",
            pages: ["needle alpha needle beta needle"]
        )
        let session = try store.open(documentAt: url)

        let split = SplitViewController(documentStore: store, windowID: store.defaultWindowID)
        split.loadViewIfNeeded()
        split.rightSidebarViewController.loadViewIfNeeded()
        let searchVC = split.rightSidebarViewController.searchResultsViewController
        searchVC.loadViewIfNeeded()
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        XCTAssertEqual(searchVC.selectNextMatch()?.matchIndex, 0)
        store.activate(sessionID: session.id, in: store.defaultWindowID, targetPane: nil)
        XCTAssertEqual(searchVC.selectedMatch()?.matchIndex, 0)
        XCTAssertEqual(searchVC.selectNextMatch()?.matchIndex, 1)
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
    }

    private func makeSearchableTemporaryPDF(named name: String, pages: [String]) throws -> URL {
        try TestPDFFixtures.makeSearchablePDF(named: name, pages: pages)
    }

    private func assertReader(
        _ reader: ReaderViewController,
        displays match: SearchSidebarMatch,
        in sessionID: UUID,
        store: DocumentStore
    ) throws {
        XCTAssertEqual(reader.displayedSessionID, sessionID)
        XCTAssertTrue(reader.pdfView.document === (try store.pdfDocument(for: sessionID)))

        let expectedPage = try XCTUnwrap(match.selection.pages.first)
        let expectedBounds = match.selection.bounds(for: expectedPage)
        let actualSelection = try XCTUnwrap(reader.pdfView.currentSelection)
        let actualPage = try XCTUnwrap(actualSelection.pages.first)
        XCTAssertEqual(reader.pdfView.document?.index(for: actualPage), match.pageIndex)
        XCTAssertEqual(actualSelection.string, match.selection.string)
        let actualBounds = actualSelection.bounds(for: actualPage)
        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 0.5)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.5)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 0.5)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 0.5)

        let currentPage = try XCTUnwrap(reader.pdfView.currentPage)
        XCTAssertEqual(reader.pdfView.document?.index(for: currentPage), match.pageIndex)
        let expectedPosition = ReadingPosition(
            pageIndex: match.pageIndex,
            point: NSPoint(x: expectedBounds.minX, y: expectedBounds.maxY)
        )
        XCTAssertEqual(store.session(for: sessionID)?.lastReadPosition, expectedPosition)
        XCTAssertTrue(reader.pdfView.bounds.intersects(reader.pdfView.convert(actualBounds, from: actualPage)))
    }
}

@MainActor
private func flushSearchNavigationLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}
