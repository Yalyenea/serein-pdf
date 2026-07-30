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

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
    }

    private func makeSearchableTemporaryPDF(named name: String, pages: [String]) throws -> URL {
        try TestPDFFixtures.makeSearchablePDF(named: name, pages: pages)
    }
}
