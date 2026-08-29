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

    func testPlainSessionSwitchDoesNotClearOrAddNavigationHistory() throws {
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
        XCTAssertTrue(reader.canGoBack)
        XCTAssertFalse(reader.canGoForward)
        XCTAssertEqual(reader.testingNavigationBackSessionIDs, [first.id, first.id])
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

    func testExplicitExternalNavigationRecordsButRawPageChangesDoNot() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-skip",
                pageCount: 8,
                pageSize: NSSize(width: 500, height: 1600)
            )
        )
        let reader = makeReader(
            store: store,
            sessionID: session.id,
            frame: NSRect(x: 0, y: 0, width: 520, height: 360)
        )

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0])

        // A raw page change is ordinary PDFKit state, not a navigation intent.
        let document = try XCTUnwrap(reader.pdfView.document)
        let page = try XCTUnwrap(document.page(at: 5))
        reader.pdfView.go(to: page)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0])
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertEqual(reader.pdfView.currentPage.map { document.index(for: $0) }, 5)

        // Pages / internal links explicitly begin navigation before PDFKit moves.
        let target = try XCTUnwrap(document.page(at: 6))
        reader.beginExternalNavigation()
        reader.pdfView.go(to: target)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 5])

        // Clicking the already-current destination must not create self-history.
        reader.beginExternalNavigation()
        reader.pdfView.go(to: target)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 5])

        // A same-page destination at another coordinate is a real history stop.
        let bounds = target.bounds(for: reader.pdfView.displayBox)
        reader.beginExternalNavigation()
        reader.pdfView.go(
            to: PDFDestination(
                page: target,
                at: NSPoint(x: bounds.minX, y: bounds.maxY - 180)
            )
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 5, 6])
        XCTAssertEqual(storePageIndex(store, session.id), 6)
        XCTAssertNotEqual(reader.testingNavigationBackPositions.last, reader.testingCurrentReadingPosition)
    }

    func testDelayedExternalNavigationKeepsOriginUntilPDFKitMoves() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-delayed-external",
                pageCount: 6
            )
        )
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        let origin = try XCTUnwrap(store.session(for: session.id)?.lastReadPosition)
        let backCount = reader.testingNavigationBackPositions.count

        reader.beginExternalNavigation()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(reader.testingNavigationBackPositions.count, backCount)

        let document = try XCTUnwrap(reader.pdfView.document)
        let target = try XCTUnwrap(document.page(at: 4))
        reader.pdfView.go(to: target)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(reader.testingNavigationBackPositions.count, backCount + 1)
        XCTAssertEqual(reader.testingNavigationBackPositions.last, origin)
    }

    func testSamePagePointsRemainDistinctHistoryStops() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-same-page-points",
                pageCount: 2,
                pageSize: NSSize(width: 500, height: 1600)
            )
        )
        store.setDisplayMode(.singlePageContinuous, for: session.id)
        let reader = makeReader(
            store: store,
            sessionID: session.id,
            frame: NSRect(x: 0, y: 0, width: 520, height: 360)
        )
        let page = try XCTUnwrap(reader.pdfView.document?.page(at: 0))
        let bounds = page.bounds(for: reader.pdfView.displayBox)
        let first = ReadingPosition(pageIndex: 0, point: NSPoint(x: bounds.minX, y: bounds.maxY - 180))
        let second = ReadingPosition(pageIndex: 0, point: NSPoint(x: bounds.minX, y: bounds.maxY - 520))
        let third = ReadingPosition(pageIndex: 0, point: NSPoint(x: bounds.minX, y: bounds.maxY - 860))

        XCTAssertTrue(reader.go(to: first, recordHistory: false))
        XCTAssertTrue(reader.go(to: second))
        XCTAssertTrue(reader.go(to: third))
        XCTAssertEqual(reader.testingNavigationBackPositions.count, 2)
        XCTAssertEqual(reader.testingNavigationBackPageIndices, [0, 0])
        XCTAssertNotEqual(
            reader.testingNavigationBackPositions[0],
            reader.testingNavigationBackPositions[1]
        )

        reader.navigateBack()
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, second)
        let liveSecond = try XCTUnwrap(reader.testingCurrentReadingPosition)
        XCTAssertEqual(liveSecond.pageIndex, 0)
        XCTAssertEqual(liveSecond.point.y, second.point.y, accuracy: 16)
        reader.navigateBack()
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, first)
    }

    func testCrossSessionBackForwardRestoresExactPanePositions() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-cross-first",
                pageCount: 4,
                pageSize: NSSize(width: 500, height: 1400)
            )
        )
        let second = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-cross-second",
                pageCount: 5,
                pageSize: NSSize(width: 500, height: 1400)
            )
        )
        store.activate(sessionID: first.id, in: store.defaultWindowID)
        let workspace = makeWorkspace(store: store)
        let reader = workspace.activeReaderViewController()
        let firstPage = try XCTUnwrap(reader.pdfView.document?.page(at: 1))
        let firstBounds = firstPage.bounds(for: reader.pdfView.displayBox)
        let firstPosition = ReadingPosition(
            pageIndex: 1,
            point: NSPoint(x: firstBounds.minX, y: firstBounds.maxY - 240)
        )
        XCTAssertTrue(reader.go(to: firstPosition, recordHistory: false))

        let secondDocument = try store.pdfDocument(for: second.id)
        let secondPage = try XCTUnwrap(secondDocument.page(at: 3))
        let secondBounds = secondPage.bounds(for: reader.pdfView.displayBox)
        let secondPosition = ReadingPosition(
            pageIndex: 3,
            point: NSPoint(x: secondBounds.minX, y: secondBounds.maxY - 360)
        )
        XCTAssertTrue(
            workspace.navigate(
                to: OutlineNavigationRequest(sessionID: second.id, position: secondPosition)
            )
        )
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), second.id)
        XCTAssertEqual(store.session(for: second.id)?.lastReadPosition, secondPosition)
        XCTAssertEqual(reader.testingNavigationBackSessionIDs.last, first.id)

        reader.navigateBack()
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), first.id)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition, firstPosition)
        XCTAssertEqual(reader.pdfView.currentPage.map { reader.pdfView.document?.index(for: $0) }, 1)

        reader.navigateForward()
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), second.id)
        XCTAssertEqual(store.session(for: second.id)?.lastReadPosition, secondPosition)
        XCTAssertEqual(reader.pdfView.currentPage.map { reader.pdfView.document?.index(for: $0) }, 3)
    }

    func testHistoryTargetMovedToAnotherWindowIsUnavailable() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-moved-first", pageCount: 4)
        )
        let second = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-moved-second", pageCount: 4)
        )
        store.activate(sessionID: first.id, in: store.defaultWindowID)
        let workspace = makeWorkspace(store: store)
        let reader = workspace.activeReaderViewController()
        let secondDocument = try store.pdfDocument(for: second.id)
        let secondPage = try XCTUnwrap(secondDocument.page(at: 2))
        let secondPosition = ReadingPosition.pageTop(
            pageIndex: 2,
            pageBounds: secondPage.bounds(for: reader.pdfView.displayBox)
        )

        XCTAssertTrue(workspace.navigate(to: secondPosition, in: second.id))
        XCTAssertTrue(reader.canGoBack)

        let destinationWindowID = store.createWindow(copyingFrom: store.defaultWindowID)
        XCTAssertTrue(
            store.moveSession(
                first.id,
                from: store.defaultWindowID,
                to: destinationWindowID
            )
        )

        XCTAssertFalse(reader.canGoBack)
        reader.navigateBack()
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), second.id)
    }

    func testSplitPaneHistoriesNavigateIndependently() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-split-first", pageCount: 5)
        )
        let second = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-split-second", pageCount: 5)
        )
        let workspace = makeWorkspace(store: store)
        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: first.id, in: store.defaultWindowID, targetPane: .secondary)
        workspace.view.layoutSubtreeIfNeeded()

        let primary = workspace.primaryReaderViewController
        let secondary = workspace.secondaryReaderViewController
        XCTAssertEqual(primary.displayedSessionID, second.id)
        XCTAssertEqual(secondary.displayedSessionID, first.id)
        XCTAssertTrue(primary.goToPage(2))
        XCTAssertTrue(secondary.goToPage(3))
        let secondaryPosition = try XCTUnwrap(store.session(for: first.id)?.lastReadPosition)

        store.setFocusedPane(.primary, in: store.defaultWindowID)
        workspace.navigateBack()
        XCTAssertEqual(store.session(for: second.id)?.currentPageIndex, 0)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition, secondaryPosition)
        XCTAssertEqual(secondary.pdfView.currentPage.map { secondary.pdfView.document?.index(for: $0) }, 3)

        store.setFocusedPane(.secondary, in: store.defaultWindowID)
        workspace.navigateBack()
        XCTAssertEqual(store.session(for: first.id)?.currentPageIndex, 0)
        XCTAssertEqual(store.session(for: second.id)?.currentPageIndex, 0)
        XCTAssertEqual(primary.pdfView.currentPage.map { primary.pdfView.document?.index(for: $0) }, 0)
    }

    func testSplitHistoryPlaybackAcceptsComparisonSessionIdentity() throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-clone-first", pageCount: 5)
        )
        let second = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-history-clone-second", pageCount: 5)
        )
        let workspace = makeWorkspace(store: store)
        let primary = workspace.primaryReaderViewController

        XCTAssertEqual(primary.displayedSessionID, second.id)
        XCTAssertTrue(primary.goToPage(1))
        XCTAssertTrue(primary.goToPage(2))
        let expectedTarget = try XCTUnwrap(primary.testingNavigationBackPositions.last)

        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: first.id, in: store.defaultWindowID, targetPane: .primary)
        store.activate(sessionID: second.id, in: store.defaultWindowID, targetPane: .secondary)
        store.setFocusedPane(.primary, in: store.defaultWindowID)
        workspace.view.layoutSubtreeIfNeeded()

        primary.navigateBack()

        let playbackSessionID = try XCTUnwrap(primary.displayedSessionID)
        XCTAssertNotEqual(playbackSessionID, second.id)
        XCTAssertEqual(store.session(for: playbackSessionID)?.url, second.url)
        XCTAssertEqual(store.session(for: playbackSessionID)?.lastReadPosition, expectedTarget)
        XCTAssertTrue(primary.canGoForward)

        primary.navigateForward()
        XCTAssertEqual(primary.displayedSessionID, first.id)
        primary.navigateBack()

        let replaySessionID = try XCTUnwrap(primary.displayedSessionID)
        XCTAssertEqual(store.session(for: replaySessionID)?.url, second.url)
        XCTAssertEqual(store.session(for: replaySessionID)?.lastReadPosition, expectedTarget)
        XCTAssertTrue(primary.canGoForward)
    }

    func testDisplayModeSwitchesRestoreExactAnchorInAllModes() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-history-mode-anchor",
                pageCount: 6,
                pageSize: NSSize(width: 500, height: 1600)
            )
        )
        let reader = makeReader(
            store: store,
            sessionID: session.id,
            frame: NSRect(x: 0, y: 0, width: 700, height: 420)
        )
        let page = try XCTUnwrap(reader.pdfView.document?.page(at: 2))
        let bounds = page.bounds(for: reader.pdfView.displayBox)
        let anchor = ReadingPosition(
            pageIndex: 2,
            point: NSPoint(x: bounds.minX, y: bounds.maxY - 420)
        )
        XCTAssertTrue(reader.go(to: anchor, recordHistory: false))
        let historyCount = reader.testingNavigationBackPositions.count

        for mode in ReaderDisplayMode.allCases {
            store.setDisplayMode(mode, for: session.id)
            reader.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(reader.pdfView.displayMode, mode.pdfDisplayMode)
            XCTAssertEqual(reader.pdfView.displayDirection, mode.displayDirection)
            XCTAssertEqual(reader.pdfView.displaysAsBook, mode.displaysAsBook)
            XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, anchor)
            let live = try XCTUnwrap(reader.testingCurrentReadingPosition)
            if mode.usesBookLayout {
                XCTAssertEqual(live.pageIndex, 1, "page 2 is the right page of book spread 1/2")
            } else {
                XCTAssertEqual(live.pageIndex, anchor.pageIndex)
                XCTAssertEqual(live.point.x, anchor.point.x, accuracy: 8)
                XCTAssertEqual(live.point.y, anchor.point.y, accuracy: 16)
            }
            XCTAssertEqual(reader.testingNavigationBackPositions.count, historyCount)
        }
    }

    func testBookTurnsUseCoverThenOddSpreadLeads() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-two-up-spreads", pageCount: 6)
        )
        store.setDisplayMode(.book, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToNextPage())
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(reader.goToNextPage())
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        XCTAssertTrue(reader.goToNextPage())
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertFalse(reader.goToNextPage(), "six-page book ends with page index 5 alone")
        XCTAssertTrue(reader.goToPreviousPage())
        XCTAssertEqual(storePageIndex(store, session.id), 4)
        XCTAssertTrue(reader.goToPreviousPage())
        XCTAssertEqual(storePageIndex(store, session.id), 2)
        XCTAssertTrue(reader.goToPreviousPage())
        XCTAssertEqual(storePageIndex(store, session.id), 0)
        XCTAssertFalse(reader.goToPreviousPage())
        XCTAssertTrue(reader.testingNavigationBackPageIndices.isEmpty)

        let odd = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-two-up-spreads-odd", pageCount: 5)
        )
        store.setDisplayMode(.book, for: odd.id)
        reader.targetSessionID = odd.id
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(reader.goToPage(3))
        XCTAssertFalse(reader.goToNextPage(), "five-page book ends with spread 3/4")
    }

    func testBookTrailingPagePositionBelongsToCurrentSpread() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-book-trailing-anchor", pageCount: 6)
        )
        store.setDisplayMode(.book, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(
            reader.testingPositionBelongsToCurrentSpread(
                positionPageIndex: 2,
                currentPageIndex: 1
            )
        )
        XCTAssertFalse(
            reader.testingPositionBelongsToCurrentSpread(
                positionPageIndex: 3,
                currentPageIndex: 1
            )
        )
    }

    func testTwoUpKeepsOriginalEvenSpreadLeads() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-two-up-original", pageCount: 6)
        )
        store.setDisplayMode(.twoUp, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)

        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.goToNextPage())
        XCTAssertEqual(storePageIndex(store, session.id), 2)
        XCTAssertTrue(reader.goToNextPage())
        XCTAssertEqual(storePageIndex(store, session.id), 4)
        XCTAssertFalse(reader.goToNextPage())
        XCTAssertTrue(reader.goToPreviousPage())
        XCTAssertEqual(storePageIndex(store, session.id), 2)
    }

    func testContinuousBookHorizontalScrollTurnsOneSpreadAfterThreshold() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-book-scroll", pageCount: 6)
        )
        store.setDisplayMode(.bookContinuous, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        reader.fitToWidth()
        reader.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -24, timestamp: 1.0))
        XCTAssertEqual(storePageIndex(store, session.id), 0)
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -25, timestamp: 1.05))
        XCTAssertEqual(storePageIndex(store, session.id), 1)

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: 2, deltaY: 30, timestamp: 1.1))
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.15))
        XCTAssertEqual(storePageIndex(store, session.id), 1, "axis jitter must not clear the page-turn cooldown")
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.3))
        XCTAssertEqual(storePageIndex(store, session.id), 3)

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -24, timestamp: 1.4))
        reader.testingInterruptContinuousBookScrollInput()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -25, timestamp: 1.45))
        XCTAssertEqual(storePageIndex(store, session.id), 3)
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -24, timestamp: 1.5))
        XCTAssertEqual(storePageIndex(store, session.id), 5, "modifier interruption must discard the pending delta")

        store.setDisplayMode(.book, for: session.id)
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 2.0))
        XCTAssertEqual(storePageIndex(store, session.id), 5)
    }

    func testBookHorizontalScrollTurnsOncePerGesture() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-book-single-turn", pageCount: 8)
        )
        store.setDisplayMode(.book, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        reader.fitToWidth()
        reader.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -24, timestamp: 1.0))
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -25, timestamp: 1.05))
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.1))
        XCTAssertEqual(storePageIndex(store, session.id), 1)

        reader.testingResetBookScrollGesture()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 2.0))
        XCTAssertEqual(storePageIndex(store, session.id), 3)

        reader.testingResetBookScrollGesture()
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -1,
                hasPreciseScrollingDeltas: false,
                hasScrollPhase: false,
                timestamp: 3.0
            )
        )
        XCTAssertEqual(storePageIndex(store, session.id), 5)
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -1,
                hasPreciseScrollingDeltas: false,
                hasScrollPhase: false,
                timestamp: 3.05
            )
        )
        XCTAssertEqual(storePageIndex(store, session.id), 7)

        XCTAssertTrue(reader.goToPage(0))
        reader.testingResetBookScrollGesture()
        XCTAssertFalse(
            reader.testingHandleContinuousBookScroll(
                deltaX: 0,
                deltaY: 1,
                hasPreciseScrollingDeltas: false,
                hasScrollPhase: false,
                timestamp: 4.0
            )
        )
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -1,
                hasPreciseScrollingDeltas: false,
                hasScrollPhase: false,
                timestamp: 4.05
            )
        )
        XCTAssertEqual(storePageIndex(store, session.id), 1)
    }

    func testContinuousBookMomentumCompletesOneTurnWithoutSkipping() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "nav-book-momentum", pageCount: 6)
        )
        store.setDisplayMode(.bookContinuous, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        reader.fitToWidth()
        reader.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -20, timestamp: 1.0))
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -30,
                isMomentum: true,
                timestamp: 1.05
            )
        )
        XCTAssertEqual(storePageIndex(store, session.id), 1)
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -80,
                isMomentum: true,
                timestamp: 1.1
            )
        )
        XCTAssertEqual(storePageIndex(store, session.id), 1)
    }

    func testContinuousBookScrollUsesWorkspaceBoundaryRouting() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                TestPDFFixtures.makeBlankPDF(named: "nav-book-group-first", pageCount: 3),
                TestPDFFixtures.makeBlankPDF(named: "nav-book-group-second", pageCount: 2),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        store.setDisplayMode(.bookContinuous, for: sessions[0].id)
        store.setDisplayMode(.singlePageContinuous, for: sessions[1].id)
        store.activate(sessionID: sessions[0].id, in: store.defaultWindowID)
        let workspace = makeWorkspace(store: store)
        let reader = workspace.primaryReaderViewController
        reader.fitToWidth()
        XCTAssertTrue(reader.goToPage(1))

        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.0))
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), sessions[1].id)
        XCTAssertEqual(storePageIndex(store, sessions[1].id), 0)
        XCTAssertTrue(
            reader.testingHandleContinuousBookScroll(
                deltaX: -80,
                isMomentum: true,
                timestamp: 1.05
            )
        )
        XCTAssertEqual(storePageIndex(store, sessions[1].id), 0)
    }

    func testContinuousBookBoundaryKeepsOtherPanePositionAndAcceptsCloneSource() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                TestPDFFixtures.makeBlankPDF(named: "nav-book-split-first", pageCount: 3),
                TestPDFFixtures.makeBlankPDF(named: "nav-book-split-second", pageCount: 4),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        for session in sessions {
            store.setDisplayMode(.bookContinuous, for: session.id)
        }
        store.setSplitEnabled(true, in: store.defaultWindowID)
        store.activate(sessionID: sessions[1].id, in: store.defaultWindowID, targetPane: .primary)
        let preservedPrimaryPosition = ReadingPosition(pageIndex: 2, point: NSPoint(x: 12, y: 34))
        store.updateReadingPosition(
            preservedPrimaryPosition,
            scaleFactor: sessions[1].zoomScale,
            for: sessions[1].id
        )
        store.activate(sessionID: sessions[0].id, in: store.defaultWindowID, targetPane: .secondary)
        store.setFocusedPane(.secondary, in: store.defaultWindowID)

        let workspace = makeWorkspace(store: store)
        let reader = workspace.secondaryReaderViewController
        reader.fitToWidth()
        XCTAssertTrue(reader.goToPage(1))
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.0))

        let comparisonID = try XCTUnwrap(
            store.displayedSessionID(for: .secondary, in: store.defaultWindowID)
        )
        XCTAssertNotEqual(comparisonID, sessions[1].id)
        XCTAssertEqual(
            store.publicSessionID(forDisplayedSessionID: comparisonID, in: store.defaultWindowID),
            sessions[1].id
        )
        XCTAssertEqual(store.session(for: sessions[1].id)?.lastReadPosition, preservedPrimaryPosition)
        XCTAssertEqual(storePageIndex(store, comparisonID), 0)
        XCTAssertEqual(store.sessions.count, 3)

        reader.testingResetBookScrollGesture()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: 60, timestamp: 2.0))
        XCTAssertEqual(
            store.displayedSessionID(for: .secondary, in: store.defaultWindowID),
            sessions[0].id
        )
        XCTAssertEqual(storePageIndex(store, sessions[0].id), 2)
        XCTAssertEqual(store.sessions.count, 2)

        reader.testingResetBookScrollGesture()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 3.0))
        XCTAssertEqual(store.sessions.count, 3)
        reader.testingResetBookScrollGesture()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: 60, timestamp: 4.0))
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testBookBoundaryKeepsGenericPreviousTargetForNonBookDocument() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                TestPDFFixtures.makeBlankPDF(named: "nav-book-mixed-first", pageCount: 5),
                TestPDFFixtures.makeBlankPDF(named: "nav-book-mixed-second", pageCount: 3),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        store.setDisplayMode(.singlePageContinuous, for: sessions[0].id)
        store.setDisplayMode(.bookContinuous, for: sessions[1].id)
        store.activate(sessionID: sessions[1].id, in: store.defaultWindowID)

        let workspace = makeWorkspace(store: store)
        let reader = workspace.primaryReaderViewController
        reader.fitToWidth()
        XCTAssertTrue(reader.testingHandleContinuousBookScroll(deltaX: 60, timestamp: 1.0))

        let targetDocument = try store.pdfDocument(for: sessions[0].id)
        let targetPage = try XCTUnwrap(targetDocument.page(at: 4))
        let targetPosition = try XCTUnwrap(store.session(for: sessions[0].id)?.lastReadPosition)
        XCTAssertEqual(store.activeSessionID(in: store.defaultWindowID), sessions[0].id)
        XCTAssertEqual(targetPosition.pageIndex, 4)
        XCTAssertEqual(
            targetPosition.point.y,
            targetPage.bounds(for: .cropBox).minY,
            accuracy: 0.01
        )
    }

    func testBookFitWidthKeepsCoverAndUnpairedPageScaleStable() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-book-fit-width",
                pageCount: 4,
                pageSize: NSSize(width: 500, height: 700)
            )
        )
        store.setDisplayMode(.book, for: session.id)
        let reader = makeReader(
            store: store,
            sessionID: session.id,
            frame: NSRect(x: 0, y: 0, width: 800, height: 700)
        )
        reader.fitToWidth()
        reader.view.layoutSubtreeIfNeeded()
        let coverScale = reader.pdfView.scaleFactor

        XCTAssertTrue(reader.goToNextPage())
        reader.view.layoutSubtreeIfNeeded()
        let spreadScale = reader.pdfView.scaleFactor
        XCTAssertEqual(spreadScale, coverScale, accuracy: 0.02)

        XCTAssertTrue(reader.goToNextPage())
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(reader.pdfView.scaleFactor, coverScale, accuracy: 0.02)

        XCTAssertTrue(reader.goToPreviousPage())
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(reader.pdfView.scaleFactor, coverScale, accuracy: 0.02)
        XCTAssertTrue(reader.goToPreviousPage())
        reader.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(reader.pdfView.scaleFactor, coverScale, accuracy: 0.02)
    }

    func testGoToLastPageUsesActualDocumentBottom() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(
                named: "nav-document-end",
                pageCount: 3,
                pageSize: NSSize(width: 500, height: 1600)
            )
        )
        let reader = makeReader(
            store: store,
            sessionID: session.id,
            frame: NSRect(x: 0, y: 0, width: 520, height: 360)
        )
        let lastPage = try XCTUnwrap(reader.pdfView.document?.page(at: 2))
        let lastBounds = lastPage.bounds(for: reader.pdfView.displayBox)

        reader.goToLastPage()

        XCTAssertEqual(storePageIndex(store, session.id), 2)
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition.point.y, lastBounds.minY)
        XCTAssertEqual(reader.pdfView.currentPage.map { reader.pdfView.document?.index(for: $0) }, 2)
        XCTAssertFalse(reader.scrollHalfPageDown(), "document end must not have more vertical content")
    }

    private func makeReader(
        store: DocumentStore,
        sessionID: UUID,
        frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 1000)
    ) -> ReaderViewController {
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = sessionID
        reader.loadViewIfNeeded()
        reader.view.frame = frame
        reader.view.layoutSubtreeIfNeeded()
        return reader
    }

    private func makeWorkspace(store: DocumentStore) -> ReaderWorkspaceViewController {
        let workspace = ReaderWorkspaceViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        workspace.loadViewIfNeeded()
        workspace.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        workspace.view.layoutSubtreeIfNeeded()
        return workspace
    }

    private func storePageIndex(_ store: DocumentStore, _ sessionID: UUID) -> Int? {
        store.session(for: sessionID)?.currentPageIndex
    }
}
