import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class NavigationHistoryTests: XCTestCase {
    func testMultiStepBackAndForwardAcrossPageJumps() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-multi", pageCount: 6)
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToPage(3))
        XCTAssertTrue(reader.goToPage(5))
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 1, 3])
        XCTAssertTrue(reader.canGoBack)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        XCTAssertEqual(reader.testingNavigationForwardPageIndices, [5])
        XCTAssertTrue(reader.canGoBack)
        XCTAssertTrue(reader.canGoForward)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertEqual(reader.testingNavigationForwardPageIndices, [5, 3])
        XCTAssertTrue(reader.canGoBack)
        XCTAssertTrue(reader.canGoForward)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 0)
        XCTAssertEqual(reader.testingNavigationForwardPageIndices, [5, 3, 1])
        XCTAssertTrue(reader.canGoForward)

        reader.navigateForward()
        XCTAssertEqual(
            storePageIndex(store, session.id),
            1,
            "forward stack was \(reader.testingNavigationForwardPageIndices)"
        )
        reader.navigateForward()
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        reader.navigateForward()
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertTrue(reader.canGoBack)
    }

    func testNewJumpAfterBackClearsForwardStack() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-branch", pageCount: 5)
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToPage(2))
        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(reader.canGoForward)

        XCTAssertTrue(reader.goToPage(4))
        XCTAssertEqual(storePageIndex(store, session.id), 4)
        XCTAssertFalse(reader.canGoForward)
        XCTAssertTrue(reader.canGoBack)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
    }

    func testRepeatedBackDoesNotGetStuckAfterStoreWriteback() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-store-writeback", pageCount: 5)
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToPage(2))
        XCTAssertTrue(reader.goToPage(3))

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 2)
        XCTAssertTrue(reader.canGoBack)
        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(reader.canGoBack)
        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 0)
    }

    func testSessionSwitchClearsNavigationHistory() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-first", pageCount: 4)
        )
        let second = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-second", pageCount: 4)
        )
        let reader = makeReader(store: store, sessionID: first.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToPage(2))
        XCTAssertTrue(reader.canGoBack)

        reader.targetSessionID = second.id
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(reader.canGoBack)
        XCTAssertFalse(reader.canGoForward)
    }

    func testSequentialPageTurnsDoNotRecordHistory() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-seq-turns", pageCount: 6)
        )
        store.setDisplayMode(.singlePage, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(2))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0])

        // goToNextPage uses sequential turnPage — must not push history.
        XCTAssertTrue(reader.goToNextPage(), "next from page 2")
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        XCTAssertTrue(reader.goToNextPage(), "next from page 3")
        XCTAssertEqual(storePageIndex(store, session.id), 4)
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0])
        XCTAssertFalse(reader.canGoForward)

        // Non-adjacent jump still records.
        XCTAssertTrue(reader.goToPage(1))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 4])
    }

    func testAdjacentPageChangeFromScrollDoesNotRecordHistory() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-scroll", pageCount: 5)
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(2))
        let backBefore = reader.testingNavigationBackPageIndices

        // Simulate continuous-scroll page step: only update via page-change path.
        let document = try XCTUnwrap(reader.pdfView.document)
        let page = try XCTUnwrap(document.page(at: 3))
        reader.pdfView.go(to: page)
        // Allow PDFViewPageChanged to run.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(reader.testingNavigationBackPageIndices, backBefore)
    }

    func testNonAdjacentPageChangeRecordsHistory() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-skip", pageCount: 8)
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0])

        // Simulate thumbnail / link skip (delta > 1) via raw PDFView navigation.
        let document = try XCTUnwrap(reader.pdfView.document)
        let page = try XCTUnwrap(document.page(at: 5))
        reader.pdfView.go(to: page)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 1])
    }

    private func makeReader(store: DocumentStore, sessionID: UUID) -> ReaderViewController {
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = sessionID
        reader.loadViewIfNeeded()
        reader.view.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        reader.view.layoutSubtreeIfNeeded()
        return reader
    }

    private func storePageIndex(_ store: DocumentStore, _ sessionID: UUID) -> Int? {
        store.session(for: sessionID)?.currentPageIndex
    }
}
