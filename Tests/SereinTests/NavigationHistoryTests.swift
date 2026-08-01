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

        XCTAssertFalse(reader.canGoBack)
        XCTAssertFalse(reader.canGoForward)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToPage(3))
        XCTAssertTrue(reader.goToPage(5))
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertTrue(reader.canGoBack)
        XCTAssertFalse(reader.canGoForward)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        XCTAssertTrue(reader.canGoBack)
        XCTAssertTrue(reader.canGoForward)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(reader.canGoBack)
        XCTAssertTrue(reader.canGoForward)

        reader.navigateBack()
        XCTAssertEqual(storePageIndex(store, session.id), 0)
        XCTAssertFalse(reader.canGoBack)
        XCTAssertTrue(reader.canGoForward)

        reader.navigateForward()
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        reader.navigateForward()
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        reader.navigateForward()
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertTrue(reader.canGoBack)
        XCTAssertFalse(reader.canGoForward)
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
