import AppKit
import PDFKit
import XCTest
@testable import Serein

private typealias InMemoryDocumentStorePersistence = TestInMemoryDocumentStorePersistence
private typealias InMemoryReadingStateStore = TestInMemoryReadingStateStore
private typealias InMemoryRecentFilesStore = TestInMemoryRecentFilesStore

private final class NotificationCounterObserver: NSObject {
    private(set) var count = 0

    @objc
    func handleDocumentStoreDidChange(_ notification: Notification) {
        count += 1
    }
}

private final class DocumentStoreChangeRecorder: @unchecked Sendable {
    var observedChange: DocumentStoreChange?

    @objc
    func handleDocumentStoreDidChange(_ notification: Notification) {
        observedChange = notification.documentStoreChange
    }
}

@MainActor
final class DocumentStoreTests: XCTestCase {
    private func makeStore(
        persistence: DocumentStorePersistence = InMemoryDocumentStorePersistence(),
        readingStateStore: ReadingStateStore = InMemoryReadingStateStore(),
        recentFilesStore: RecentFilesStore = InMemoryRecentFilesStore(),
        appConfiguration: AppConfiguration = .default
    ) -> DocumentStore {
        DocumentStore(
            persistence: persistence,
            readingStateStore: readingStateStore,
            recentFilesStore: recentFilesStore,
            appConfiguration: appConfiguration
        )
    }

    func testOpenDocumentCreatesActiveSession() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "single")

        let session = try store.open(documentAt: url)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessionID, session.id)
        XCTAssertEqual(store.activeSession?.title, "single")
    }

    func testHorizontalPanLockIsIndependentAndRestoredPerDocument() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let readingStates = InMemoryReadingStateStore()
        let store = makeStore(persistence: persistence, readingStateStore: readingStates)
        let first = try store.open(documentAt: makeTemporaryPDF(named: "lock-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "lock-second"))
        store.setHorizontalPanLocked(true, for: first.id)
        XCTAssertTrue(try XCTUnwrap(store.session(for: first.id)).isHorizontalPanLocked)
        XCTAssertFalse(try XCTUnwrap(store.session(for: second.id)).isHorizontalPanLocked)

        let restored = makeStore(persistence: persistence, readingStateStore: readingStates)
        try restored.restorePersistedState()
        XCTAssertTrue(try XCTUnwrap(restored.sessions.first { $0.url == first.url }).isHorizontalPanLocked)
        XCTAssertFalse(try XCTUnwrap(restored.sessions.first { $0.url == second.url }).isHorizontalPanLocked)

        store.close(sessionID: first.id)
        let reopened = try store.open(documentAt: first.url)
        XCTAssertTrue(reopened.isHorizontalPanLocked)
        store.setDisplayMode(.book, for: reopened.id)
        store.setHorizontalPanLocked(true, for: reopened.id)
        XCTAssertFalse(try XCTUnwrap(store.session(for: reopened.id)).isHorizontalPanLocked)
    }

    func testReadingStateWithoutPanLockStillDecodes() throws {
        let state = PersistedReadingState(
            url: URL(fileURLWithPath: "/test.pdf"), displayMode: .singlePage,
            scaleMode: .fitHeight, scaleFactor: 1, readingPosition: .zero,
            isHorizontalPanLocked: true
        )
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(PersistedReadingState.self, from: data), state)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "isHorizontalPanLocked")
        let decoded = try JSONDecoder().decode(
            PersistedReadingState.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(decoded.isHorizontalPanLocked)
        XCTAssertEqual(decoded.scaleMode, .fitHeight)
    }

    func testLoadingNewDocumentResolvesInitialPositionToActualPageTop() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "initial-page-top"))
        let document = try store.pdfDocument(for: session.id)
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let expected = ReadingPosition.pageTop(
            pageIndex: 0,
            pageBounds: firstPage.bounds(for: .cropBox)
        )

        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, expected)
        XCTAssertNotEqual(expected.point, .zero)
    }

    func testNewBlankTabCreatesActiveUntitledSessionWithoutRecentFile() throws {
        let store = makeStore()

        let session = store.newBlankTab()

        XCTAssertTrue(session.isBlank)
        XCTAssertEqual(session.title, "Untitled")
        XCTAssertEqual(store.sessions.map(\.id), [session.id])
        XCTAssertEqual(store.activeSessionID, session.id)
        XCTAssertTrue(store.recentDocumentURLs.isEmpty)
        XCTAssertFalse(store.isPDFDocumentLoaded(for: session.id))
    }

    func testClosingBlankTabDoesNotPushRecentlyClosedURL() throws {
        let store = makeStore()
        let pdf = try store.open(documentAt: makeTemporaryPDF(named: "blank-close-anchor"))
        let blank = store.newBlankTab()

        store.close(sessionID: blank.id)

        XCTAssertEqual(store.recentlyClosedURLs, [])
        XCTAssertEqual(store.activeSessionID, pdf.id)
    }

    func testBlankTabsAreNotPersisted() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let pdf = try store.open(documentAt: makeTemporaryPDF(named: "blank-persisted-anchor"))
        _ = store.newBlankTab()

        let state = try XCTUnwrap(persistence.state)
        XCTAssertEqual(state.sessions.map(\.url), [pdf.url])
        XCTAssertEqual(state.windows.first?.sessionIDs, [pdf.id])
        XCTAssertEqual(state.windows.first?.splitState.primarySessionID, pdf.id)
    }

    func testOpenMultipleDocumentsKeepsAllSessionsAndActivatesLast() throws {
        let store = makeStore()
        let firstURL = try makeTemporaryPDF(named: "first")
        let secondURL = try makeTemporaryPDF(named: "second")
        let thirdURL = try makeTemporaryPDF(named: "third")

        let firstSession = try store.open(documentAt: firstURL)
        let secondSession = try store.open(documentAt: secondURL)
        let thirdSession = try store.open(documentAt: thirdURL)

        XCTAssertEqual(store.sessions.count, 3)
        XCTAssertEqual(store.sessions.map(\.id), [firstSession.id, secondSession.id, thirdSession.id])
        XCTAssertEqual(store.activeSession?.url, thirdURL)
    }

    func testActivateOpenDocumentFocusesExistingSessionWithoutDuplicating() throws {
        let store = makeStore()
        let firstURL = try makeTemporaryPDF(named: "reuse-open-first")
        let secondURL = try makeTemporaryPDF(named: "reuse-open-second")
        let firstSession = try store.open(documentAt: firstURL)
        let defaultWindowID = store.defaultWindowID
        let secondWindowID = store.createWindow(copyingFrom: defaultWindowID)
        let secondSession = try store.open(documentAt: secondURL, in: secondWindowID)

        let location = store.activateOpenDocument(at: firstURL)

        XCTAssertEqual(location, DocumentOpenLocation(windowID: defaultWindowID, sessionID: firstSession.id))
        XCTAssertEqual(store.sessions.map(\.id), [firstSession.id, secondSession.id])
        XCTAssertEqual(store.activeSessionID(in: defaultWindowID), firstSession.id)
        XCTAssertEqual(store.activeSessionID(in: secondWindowID), secondSession.id)
        XCTAssertEqual(store.selectedSessionIDs(in: defaultWindowID), Set([firstSession.id]))
    }

    func testOpenDocumentsNotesSystemRecentURLs() throws {
        let store = makeStore()
        let urls = try (0..<3).map { try makeTemporaryPDF(named: "system-recent-\($0)") }
        var notedURLs: [URL] = []
        store.noteRecentDocumentURL = { notedURLs.append($0) }

        _ = try store.open(documentsAt: urls, in: store.defaultWindowID)

        XCTAssertEqual(notedURLs, urls)
    }

    func testBlankTabDoesNotNoteSystemRecentURL() {
        let store = makeStore()
        var notedURLs: [URL] = []
        store.noteRecentDocumentURL = { notedURLs.append($0) }

        _ = store.newBlankTab()

        XCTAssertTrue(notedURLs.isEmpty)
    }

    func testBatchOpenCreatesLightweightSessionsWithoutLoadingPDFDocuments() throws {
        let store = makeStore()
        let urls = try (0..<3).map { try makeTemporaryPDF(named: "lazy-open-\($0)") }

        let sessions = try store.open(documentsAt: urls, in: store.defaultWindowID)

        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(store.activeSessionID, sessions.last?.id)
        XCTAssertTrue(sessions.allSatisfy { store.isPDFDocumentLoaded(for: $0.id) == false })

        _ = try store.pdfDocument(for: sessions[1].id)

        XCTAssertFalse(store.isPDFDocumentLoaded(for: sessions[0].id))
        XCTAssertTrue(store.isPDFDocumentLoaded(for: sessions[1].id))
        XCTAssertFalse(store.isPDFDocumentLoaded(for: sessions[2].id))
    }

    func testBatchOpenPostsSingleStoreChangeNotification() throws {
        let store = makeStore()
        let observer = NotificationCounterObserver()
        NotificationCenter.default.addObserver(
            observer,
            selector: #selector(NotificationCounterObserver.handleDocumentStoreDidChange),
            name: .documentStoreDidChange,
            object: store
        )
        defer { NotificationCenter.default.removeObserver(observer) }
        let urls = try (0..<4).map { try makeTemporaryPDF(named: "batch-notify-\($0)") }

        _ = try store.open(documentsAt: urls, in: store.defaultWindowID)

        XCTAssertEqual(observer.count, 1)
    }

    func testBatchOpenSelectsNewTabsForContinuousReadingEntry() throws {
        let store = makeStore()
        let urls = try (0..<3).map { try makeTemporaryPDF(named: "continuous-open-\($0)") }

        let sessions = try store.open(documentsAt: urls, in: store.defaultWindowID)

        XCTAssertEqual(store.selectedSessionIDs(in: store.defaultWindowID), Set(sessions.map(\.id)))
        XCTAssertFalse(store.isContinuousReadingEnabled(in: store.defaultWindowID))
    }

    func testContinuousReadingStartsFromSelectedTabsInWindowOrder() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-first"),
                makeTemporaryPDF(named: "continuous-second"),
                makeTemporaryPDF(named: "continuous-third"),
            ],
            in: store.defaultWindowID
        )

        store.selectSessions([sessions[2].id, sessions[0].id], in: store.defaultWindowID)

        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        XCTAssertEqual(store.continuousReadingSessionIDs(in: store.defaultWindowID), [sessions[0].id, sessions[2].id])
    }

    func testSelectedSessionIDsExposeWindowOrderForBatchTabCommands() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "batch-close-order-first"),
                makeTemporaryPDF(named: "batch-close-order-second"),
                makeTemporaryPDF(named: "batch-close-order-third"),
            ],
            in: store.defaultWindowID
        )

        store.selectSessions([sessions[2].id, sessions[0].id], in: store.defaultWindowID)

        XCTAssertEqual(store.selectedSessionIDsInWindowOrder(in: store.defaultWindowID), [sessions[0].id, sessions[2].id])
    }

    func testOpeningNewBatchClearsPriorContinuousReadingGroup() throws {
        let store = makeStore()
        _ = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-clear-first"),
                makeTemporaryPDF(named: "continuous-clear-second"),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))

        _ = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-clear-new-first"),
                makeTemporaryPDF(named: "continuous-clear-new-second"),
            ],
            in: store.defaultWindowID
        )

        XCTAssertFalse(store.isContinuousReadingEnabled(in: store.defaultWindowID))
    }

    func testContinuousReadingTargetsNeighborDocumentsAtBoundaries() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-boundary-first", pageCount: 2),
                makeTemporaryPDF(named: "continuous-boundary-second", pageCount: 3),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))

        let firstDocument = try store.pdfDocument(for: sessions[0].id)
        let secondDocument = try store.pdfDocument(for: sessions[1].id)
        let firstLastPage = try XCTUnwrap(firstDocument.page(at: 1))
        let secondFirstPage = try XCTUnwrap(secondDocument.page(at: 0))
        let forwardPosition = ReadingPosition.pageTop(
            pageIndex: 0,
            pageBounds: secondFirstPage.bounds(for: .cropBox)
        )
        let backwardPosition = ReadingPosition.pageBottom(
            pageIndex: 1,
            pageBounds: firstLastPage.bounds(for: .cropBox)
        )

        XCTAssertEqual(
            store.continuousReadingTarget(from: sessions[0].id, direction: 1, in: store.defaultWindowID),
            ContinuousReadingTarget(sessionID: sessions[1].id, readingPosition: forwardPosition)
        )
        XCTAssertEqual(
            store.continuousReadingTarget(from: sessions[1].id, direction: -1, in: store.defaultWindowID),
            ContinuousReadingTarget(sessionID: sessions[0].id, readingPosition: backwardPosition)
        )
        XCTAssertNil(store.continuousReadingTarget(from: sessions[0].id, direction: -1, in: store.defaultWindowID))
        XCTAssertNil(store.continuousReadingTarget(from: sessions[1].id, direction: 1, in: store.defaultWindowID))

        let roots = store.outlineTreeForSidebar(in: store.defaultWindowID)
        XCTAssertEqual(roots.map(\.destinationPoint), [
            firstDocument.page(at: 0).map {
                ReadingPosition.pageTop(pageIndex: 0, pageBounds: $0.bounds(for: .cropBox)).point
            },
            forwardPosition.point,
        ])
    }

    func testContinuousOutlineSnapshotDoesNotReloadEvictedGroupDocuments() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: (0..<6).map { try makeTemporaryPDF(named: "outline-cache-\($0)") },
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        XCTAssertEqual(store.outlineTreeForSidebar(in: store.defaultWindowID).count, 6)
        store.discardCleanBackgroundDocuments()
        let loadedBefore = Set(sessions.filter { store.isPDFDocumentLoaded(for: $0.id) }.map(\.id))

        XCTAssertEqual(store.outlineTreeForSidebar(in: store.defaultWindowID).count, 6)

        let loadedAfter = Set(sessions.filter { store.isPDFDocumentLoaded(for: $0.id) }.map(\.id))
        XCTAssertEqual(loadedAfter, loadedBefore)
    }

    func testPDFDocumentCacheEvictsCleanBackgroundDocumentsButKeepsDirtyOnes() throws {
        let store = makeStore()
        let urls = try (0..<5).map { try makeTemporaryPDF(named: "lru-\($0)") }
        let sessions = try store.open(documentsAt: urls, in: store.defaultWindowID)

        for session in sessions.prefix(4) {
            _ = try store.pdfDocument(for: session.id)
        }
        store.setDirty(true, for: sessions[0].id)
        _ = try store.pdfDocument(for: sessions[4].id)

        XCTAssertTrue(store.isPDFDocumentLoaded(for: sessions[0].id))
        XCTAssertFalse(store.isPDFDocumentLoaded(for: sessions[1].id))
        XCTAssertTrue(store.isPDFDocumentLoaded(for: sessions[4].id))
    }

    func testExternalPDFChangeInvalidatesCleanLoadedDocumentAndDerivedCaches() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(named: "hot-reload-clean", pages: ["old needle"])
        let session = try store.open(documentAt: url)
        let oldDocument = try store.pdfDocument(for: session.id)
        XCTAssertEqual(oldDocument.pageCount, 1)

        _ = store.outlineTree(for: session.id)
        _ = store.annotationSections(in: store.defaultWindowID)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)
        XCTAssertEqual(store.session(for: session.id)?.isOutlineLoaded, true)
        XCTAssertEqual(store.session(for: session.id)?.isAnnotationCacheLoaded, true)
        XCTAssertEqual(store.session(for: session.id)?.searchCache.matches.count, 1)

        try writeTemporaryPDF(to: url, pageCount: 2)
        store.refreshExternallyChangedFile(at: url)

        let invalidatedSession = try XCTUnwrap(store.session(for: session.id))
        XCTAssertFalse(store.isPDFDocumentLoaded(for: session.id))
        XCTAssertNil(invalidatedSession.pageCount)
        XCTAssertFalse(invalidatedSession.isOutlineLoaded)
        XCTAssertTrue(invalidatedSession.outlineTree.isEmpty)
        XCTAssertFalse(invalidatedSession.isAnnotationCacheLoaded)
        XCTAssertTrue(invalidatedSession.annotationCache.groups.isEmpty)
        XCTAssertTrue(invalidatedSession.searchCache.matches.isEmpty)

        let reloadedDocument = try store.pdfDocument(for: session.id)
        XCTAssertFalse(oldDocument === reloadedDocument)
        XCTAssertEqual(reloadedDocument.pageCount, 2)
    }

    func testExternalPDFChangeReloadsEveryCleanSessionForSameURL() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-duplicates", pageCount: 1)
        let first = try store.open(documentAt: url)
        let second = try store.open(documentAt: url)
        _ = try store.pdfDocument(for: first.id)
        _ = try store.pdfDocument(for: second.id)

        try writeTemporaryPDF(to: url, pageCount: 3)
        store.refreshExternallyChangedFile(at: url)

        XCTAssertFalse(store.isPDFDocumentLoaded(for: first.id))
        XCTAssertFalse(store.isPDFDocumentLoaded(for: second.id))
        XCTAssertEqual(try store.pdfDocument(for: first.id).pageCount, 3)
        XCTAssertEqual(try store.pdfDocument(for: second.id).pageCount, 3)
    }

    func testExternalPDFChangeDoesNotReloadDirtySession() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-dirty", pageCount: 1)
        let session = try store.open(documentAt: url)
        _ = try store.pdfDocument(for: session.id)
        let dirtyDate = Date(timeIntervalSince1970: 100)
        store.setDirty(true, for: session.id, now: dirtyDate)

        try writeTemporaryPDF(to: url, pageCount: 2)
        store.refreshExternallyChangedFile(at: url)

        let dirtySession = try XCTUnwrap(store.session(for: session.id))
        XCTAssertTrue(store.isPDFDocumentLoaded(for: session.id))
        XCTAssertTrue(dirtySession.isDirty)
        XCTAssertEqual(dirtySession.dirtySince, dirtyDate)
        XCTAssertEqual(try store.pdfDocument(for: session.id).pageCount, 1)
    }

    func testExternalPDFInPlaceWriteEventReloadsCleanSession() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-in-place", pageCount: 1)
        let session = try store.open(documentAt: url)
        let oldDocument = try store.pdfDocument(for: session.id)

        try overwriteFileInPlace(at: url, withPDFPageCount: 2)

        XCTAssertTrue(waitForMainRunLoop(until: {
            store.isPDFDocumentLoaded(for: session.id) == false
        }))
        let reloadedDocument = try store.pdfDocument(for: session.id)
        XCTAssertFalse(oldDocument === reloadedDocument)
        XCTAssertEqual(reloadedDocument.pageCount, 2)
    }

    func testExternalPDFAtomicReplaceEventReloadsCleanSession() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-replace", pageCount: 1)
        let session = try store.open(documentAt: url)
        let oldDocument = try store.pdfDocument(for: session.id)

        let replacementURL = url.deletingLastPathComponent().appendingPathComponent("replacement.pdf")
        try writeTemporaryPDF(to: replacementURL, pageCount: 3)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacementURL)

        XCTAssertTrue(waitForMainRunLoop(until: {
            store.isPDFDocumentLoaded(for: session.id) == false
        }))
        let reloadedDocument = try store.pdfDocument(for: session.id)
        XCTAssertFalse(oldDocument === reloadedDocument)
        XCTAssertEqual(reloadedDocument.pageCount, 3)
    }

    func testExternalPDFInPlaceWriteEventReloadsEveryCleanSessionForSameURL() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-event-duplicates", pageCount: 1)
        let first = try store.open(documentAt: url)
        let second = try store.open(documentAt: url)
        _ = try store.pdfDocument(for: first.id)
        _ = try store.pdfDocument(for: second.id)

        try overwriteFileInPlace(at: url, withPDFPageCount: 4)

        XCTAssertTrue(waitForMainRunLoop(until: {
            store.isPDFDocumentLoaded(for: first.id) == false &&
                store.isPDFDocumentLoaded(for: second.id) == false
        }))
        XCTAssertEqual(try store.pdfDocument(for: first.id).pageCount, 4)
        XCTAssertEqual(try store.pdfDocument(for: second.id).pageCount, 4)
    }

    func testExternalPDFInPlaceWriteEventDoesNotReloadDirtySession() throws {
        let store = makeStore()
        let url = try makeTemporaryPDF(named: "hot-reload-in-place-dirty", pageCount: 1)
        let session = try store.open(documentAt: url)
        _ = try store.pdfDocument(for: session.id)
        let dirtyDate = Date(timeIntervalSince1970: 100)
        store.setDirty(true, for: session.id, now: dirtyDate)

        try overwriteFileInPlace(at: url, withPDFPageCount: 2)
        // Drive the same path as the file monitor callback; a timed wait that
        // always fails cannot distinguish "dirty guard worked" from "event never ran".
        store.refreshExternallyChangedFile(at: url)

        let dirtySession = try XCTUnwrap(store.session(for: session.id))
        XCTAssertTrue(store.isPDFDocumentLoaded(for: session.id))
        XCTAssertTrue(dirtySession.isDirty)
        XCTAssertEqual(dirtySession.dirtySince, dirtyDate)
        XCTAssertEqual(try store.pdfDocument(for: session.id).pageCount, 1)
    }

    func testCloseActiveSessionFallsBackToPreviousSession() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.close(sessionID: second.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testClosingContinuousReadingTabCleansGroup() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-close-first"),
                makeTemporaryPDF(named: "continuous-close-second"),
                makeTemporaryPDF(named: "continuous-close-third"),
            ],
            in: store.defaultWindowID
        )
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))

        store.close(sessionID: sessions[1].id, from: store.defaultWindowID)

        XCTAssertTrue(store.isContinuousReadingEnabled(in: store.defaultWindowID))
        XCTAssertEqual(store.continuousReadingSessionIDs(in: store.defaultWindowID), [sessions[0].id, sessions[2].id])

        store.close(sessionID: sessions[2].id, from: store.defaultWindowID)

        XCTAssertFalse(store.isContinuousReadingEnabled(in: store.defaultWindowID))
        XCTAssertTrue(store.continuousReadingSessionIDs(in: store.defaultWindowID).isEmpty)
    }

    func testCloseSessionPushesURLOntoRecentlyClosedStack() throws {
        let store = makeStore()
        let firstURL = try makeTemporaryPDF(named: "closed-alpha")
        let secondURL = try makeTemporaryPDF(named: "closed-beta")
        let first = try store.open(documentAt: firstURL)
        let second = try store.open(documentAt: secondURL)

        store.close(sessionID: first.id)
        store.close(sessionID: second.id)

        XCTAssertEqual(store.recentlyClosedURLs, [firstURL, secondURL])
        XCTAssertEqual(store.popRecentlyClosed(), secondURL)
        XCTAssertEqual(store.recentlyClosedURLs, [firstURL])
        XCTAssertEqual(store.popRecentlyClosed(), firstURL)
        XCTAssertNil(store.popRecentlyClosed())
    }

    func testRecentlyClosedStackCapsAtTenEntriesWithoutDuplicates() throws {
        let store = makeStore()
        var urls: [URL] = []
        for index in 0..<12 {
            let url = try makeTemporaryPDF(named: "stack-\(index)")
            urls.append(url)
            let session = try store.open(documentAt: url)
            store.close(sessionID: session.id)
        }

        XCTAssertEqual(store.recentlyClosedURLs.count, 10)
        XCTAssertEqual(store.recentlyClosedURLs, Array(urls.suffix(10)))

        // Closing an already-tracked URL moves it to the top rather than duplicating.
        let reopened = try store.open(documentAt: urls[0])
        store.close(sessionID: reopened.id)
        XCTAssertEqual(store.recentlyClosedURLs.last, urls[0])
        XCTAssertEqual(store.recentlyClosedURLs.count, 10)
        XCTAssertEqual(store.recentlyClosedURLs.filter { $0 == urls[0] }.count, 1)
    }

    func testCloseActiveSessionConvenienceUsesCurrentSelection() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "close-active-alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "close-active-beta"))

        XCTAssertEqual(store.activeSessionID, second.id)
        store.closeActiveSession()

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testActivateSessionSwitchesActiveDocument() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.activate(sessionID: first.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.activeSession?.url, first.url)
    }

    func testActivatePreviousSessionWrapsAround() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "prev-alpha"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "prev-beta"))
        let third = try store.open(documentAt: makeTemporaryPDF(named: "prev-gamma"))

        XCTAssertEqual(store.activeSessionID, third.id)
        store.activatePreviousSession()
        XCTAssertNotEqual(store.activeSessionID, third.id)
        store.activatePreviousSession()
        XCTAssertEqual(store.activeSessionID, first.id)
        store.activatePreviousSession()
        XCTAssertEqual(store.activeSessionID, third.id)
    }

    func testActivateNextSessionWrapsAround() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "next-alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "next-beta"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "next-gamma"))

        store.activate(sessionID: first.id)
        store.activateNextSession()
        XCTAssertEqual(store.activeSessionID, second.id)
        store.activateNextSession()
        XCTAssertNotEqual(store.activeSessionID, second.id)
        store.activateNextSession()
        XCTAssertEqual(store.activeSessionID, first.id)
    }

    func testUpdateCurrentPageMutatesOnlyTargetSession() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha", pageCount: 4))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 0, point: CGPoint(x: 31, y: 47)),
            scaleFactor: 1,
            for: first.id
        )

        store.updateCurrentPage(index: 3, for: first.id)

        let page = try XCTUnwrap(try store.pdfDocument(for: first.id).page(at: 3))
        let expectedPosition = ReadingPosition.pageTop(
            pageIndex: 3,
            pageBounds: page.bounds(for: .cropBox)
        )

        XCTAssertEqual(store.session(for: first.id)?.currentPageIndex, 3)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition, expectedPosition)
        XCTAssertEqual(store.session(for: second.id)?.currentPageIndex, 0)
    }

    func testUpdateCurrentPageResetsSamePageToActualPageTop() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "same-page-top"))
        store.updateReadingPosition(
            ReadingPosition(pageIndex: 0, point: CGPoint(x: 20, y: 30)),
            scaleFactor: 1,
            for: session.id
        )

        store.updateCurrentPage(index: 0, for: session.id)

        let page = try XCTUnwrap(try store.pdfDocument(for: session.id).page(at: 0))
        XCTAssertEqual(
            store.session(for: session.id)?.lastReadPosition,
            ReadingPosition.pageTop(pageIndex: 0, pageBounds: page.bounds(for: .cropBox))
        )
    }

    func testDefaultTabPresentationModeIsVerticalSidebar() {
        XCTAssertEqual(
            makeStore().tabPresentationMode,
            .verticalSidebar
        )
    }

    func testSetTabPresentationModeUpdatesStore() {
        let store = makeStore()

        store.setTabPresentationMode(.horizontalTitlebar)

        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
    }

    func testCloseUnknownSessionDoesNotCrashOrMutateMode() {
        let store = makeStore()
        let unknownSessionID = UUID()

        store.close(sessionID: unknownSessionID)

        XCTAssertNil(store.activeSession)
        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
    }

    func testSetTabPresentationModeAdjustsLeftSidebarVisibility() {
        let store = makeStore()

        store.setTabPresentationMode(.horizontalTitlebar)
        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
        XCTAssertFalse(store.isLeftSidebarVisible)

        store.setTabPresentationMode(.verticalSidebar)
        XCTAssertTrue(store.isLeftSidebarVisible)
    }

    func testSidebarVisibilityUpdatesPersistedState() {
        let persistence = InMemoryDocumentStorePersistence()
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        store.setLeftSidebarVisible(false)
        store.setRightSidebarVisible(false)

        XCTAssertEqual(persistence.state?.isLeftSidebarVisible, false)
        XCTAssertEqual(persistence.state?.isRightSidebarVisible, false)
    }

    func testSidebarVisibilityChangePostsLightweightNotification() {
        let store = makeStore()
        let recorder = DocumentStoreChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .documentStoreDidChange,
            object: store,
            queue: nil
        ) { notification in
            recorder.observedChange = notification.documentStoreChange
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setLeftSidebarVisible(false)

        XCTAssertEqual(recorder.observedChange, .sidebarVisibility)
    }

    func testFreshStoreStartsWithOutlinePaneCollapsed() {
        // M12-010: an empty window has nothing for the outline pane to answer.
        let store = makeStore()
        XCTAssertTrue(store.sessions(in: store.defaultWindowID).isEmpty)
        XCTAssertTrue(store.isLeftSidebarVisible(in: store.defaultWindowID))
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testClosingLastSessionHidesOutlinePane() throws {
        // M12-010: closing every session in a window auto-collapses the outline
        // pane; the tabs pane stays because it hosts the recent quick entry.
        let store = makeStore()
        store.setRightSidebarVisible(true, in: store.defaultWindowID)
        let first = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-second"))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))

        store.close(sessionID: second.id, from: store.defaultWindowID)
        XCTAssertFalse(store.sessions(in: store.defaultWindowID).isEmpty)
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))

        store.close(sessionID: first.id, from: store.defaultWindowID)
        XCTAssertTrue(store.sessions(in: store.defaultWindowID).isEmpty)
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
        XCTAssertTrue(store.isLeftSidebarVisible(in: store.defaultWindowID))

        // Re-opening a document into the auto-collapsed window restores the pane.
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-reopen"))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testOpeningFirstPDFIntoAutoCollapsedWindowRestoresOutlinePane() throws {
        // Auto-collapse only describes the empty window: the first document
        // restores the outline pane so the TOC is immediately available.
        let store = makeStore()
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))

        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-open"))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))

        store.setRightSidebarVisible(false, in: store.defaultWindowID)
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testExplicitOutlineToggleDuringEmptyWindowWins() throws {
        // The user's own toggle while empty hands visibility back to them;
        // opening a document must not resurrect the auto-collapsed state.
        let store = makeStore()
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))

        store.setRightSidebarVisible(true, in: store.defaultWindowID)
        store.setRightSidebarVisible(false, in: store.defaultWindowID)

        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-user"))
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testSwappedEmptyWindowCollapsesAndRestoresOutlinePane() throws {
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = true
        let store = makeStore(appConfiguration: configuration)

        XCTAssertFalse(store.isLeftSidebarVisible(in: store.defaultWindowID))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))

        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-swapped"))

        XCTAssertTrue(store.isLeftSidebarVisible(in: store.defaultWindowID))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testExplicitSwappedOutlineToggleDuringEmptyWindowWins() throws {
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = true
        let store = makeStore(appConfiguration: configuration)

        store.setLeftSidebarVisible(true, in: store.defaultWindowID)
        store.setLeftSidebarVisible(false, in: store.defaultWindowID)
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-swapped-user"))

        XCTAssertFalse(store.isLeftSidebarVisible(in: store.defaultWindowID))
        XCTAssertTrue(store.isRightSidebarVisible(in: store.defaultWindowID))
    }

    func testMovingLastSessionToNewWindowHidesSourceOutlinePane() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-move"))
        store.setRightSidebarVisible(true, in: store.defaultWindowID)
        let newWindowID = try XCTUnwrap(store.moveActiveSessionToNewWindow(from: store.defaultWindowID))

        XCTAssertTrue(store.sessions(in: store.defaultWindowID).isEmpty)
        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
        XCTAssertEqual(store.sessions(in: newWindowID).map(\.id), [session.id])
        XCTAssertTrue(store.isRightSidebarVisible(in: newWindowID))
    }

    func testRestoredEmptyWindowHidesOutlinePane() throws {
        let windowID = UUID()
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [],
            windows: [
                .init(
                    id: windowID,
                    tabPresentationMode: .verticalSidebar,
                    isLeftSidebarVisible: true,
                    isRightSidebarVisible: true,
                    rightSidebarMode: .outline,
                    searchQuery: "",
                    searchScope: .currentDocument,
                    splitState: .init(
                        isEnabled: false,
                        primarySessionID: nil,
                        secondarySessionID: nil,
                        primarySessionURL: nil,
                        secondarySessionURL: nil,
                        focusedPane: .primary
                    ),
                    recentlyClosedURLs: []
                ),
            ]
        )
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertTrue(store.sessions(in: windowID).isEmpty)
        XCTAssertFalse(store.isRightSidebarVisible(in: windowID))
        XCTAssertTrue(store.isLeftSidebarVisible(in: windowID))
    }

    func testPersistedAutoCollapsedWindowRestoresOutlineOnFirstOpen() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let store = makeStore(persistence: persistence)
        let session = try store.open(documentAt: makeTemporaryPDF(named: "empty-policy-persist"))
        store.close(sessionID: session.id, from: store.defaultWindowID)

        XCTAssertFalse(store.isRightSidebarVisible(in: store.defaultWindowID))
        XCTAssertEqual(persistence.state?.windows.first?.isRightSidebarVisible, true)

        let restoredStore = makeStore(persistence: persistence)
        try restoredStore.restorePersistedState()
        let restoredWindowID = restoredStore.defaultWindowID
        XCTAssertFalse(restoredStore.isRightSidebarVisible(in: restoredWindowID))

        _ = try restoredStore.open(
            documentAt: makeTemporaryPDF(named: "empty-policy-persist-reopen"),
            in: restoredWindowID
        )

        XCTAssertTrue(restoredStore.isRightSidebarVisible(in: restoredWindowID))
    }

    func testCopiedAutoCollapsedWindowRestoresOutlineOnFirstOpen() throws {
        let store = makeStore()
        let copiedWindowID = store.createWindow(copyingFrom: store.defaultWindowID)

        XCTAssertFalse(store.isRightSidebarVisible(in: copiedWindowID))

        _ = try store.open(
            documentAt: makeTemporaryPDF(named: "empty-policy-copy"),
            in: copiedWindowID
        )

        XCTAssertTrue(store.isRightSidebarVisible(in: copiedWindowID))
    }

    func testRightSidebarModeChangePostsLightweightNotification() {
        let store = makeStore()
        let recorder = DocumentStoreChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .documentStoreDidChange,
            object: store,
            queue: nil
        ) { notification in
            recorder.observedChange = notification.documentStoreChange
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setRightSidebarMode(.pages, in: store.defaultWindowID)

        XCTAssertEqual(recorder.observedChange, .rightSidebarMode)
    }

    func testRestorePersistedStateReopensSessionsAndMode() throws {
        let firstURL = try makeTemporaryPDF(named: "restore-first")
        let secondURL = try makeTemporaryPDF(named: "restore-second")
        let persistence = InMemoryDocumentStorePersistence()
        let readingStateStore = InMemoryReadingStateStore()
        persistence.state = PersistedDocumentStoreState(
            sessions: [
                .init(url: firstURL),
                .init(url: secondURL),
            ],
            activeSessionURL: firstURL,
            tabPresentationMode: .horizontalTitlebar,
            isLeftSidebarVisible: false,
            isRightSidebarVisible: true
        )
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertEqual(store.sessions.map(\.url), [firstURL, secondURL])
        XCTAssertEqual(store.activeSession?.url, firstURL)
        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
        XCTAssertFalse(store.isLeftSidebarVisible)
        XCTAssertTrue(store.isRightSidebarVisible)
    }

    func testRestorePersistedStateDoesNotNoteSystemRecentURLs() throws {
        let url = try makeTemporaryPDF(named: "restore-system-recent")
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [.init(url: url)],
            activeSessionURL: url,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: true,
            isRightSidebarVisible: true
        )
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        var notedURLs: [URL] = []
        store.noteRecentDocumentURL = { notedURLs.append($0) }

        try store.restorePersistedState()

        XCTAssertTrue(notedURLs.isEmpty)
    }

    func testRestorePersistedVerticalModePreservesCollapsedLeftSidebar() throws {
        // restorePersistedState keeps the saved left-sidebar flag; live
        // setTabPresentationMode(.verticalSidebar) is what forces it visible.
        let url = try makeTemporaryPDF(named: "restore-vertical")
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [.init(url: url)],
            activeSessionURL: url,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: false,
            isRightSidebarVisible: true
        )
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
        XCTAssertFalse(store.isLeftSidebarVisible)
    }

    func testOpenDocumentUsesPersistedReadingStateAndConfiguredDefaults() throws {
        let url = try makeTemporaryPDF(named: "persisted-reading")
        let readingStateStore = InMemoryReadingStateStore()
        readingStateStore.states[url] = PersistedReadingState(
            url: url,
            displayMode: .twoUpContinuous,
            scaleMode: .manual,
            scaleFactor: 1.75,
            readingPosition: ReadingPosition(pageIndex: 2, point: CGPoint(x: 14, y: 28))
        )
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore(),
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePage, fitWidthOnOpen: false),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )

        let session = try store.open(documentAt: url)

        XCTAssertEqual(session.displayMode, .twoUpContinuous)
        XCTAssertEqual(session.scaleMode, .manual)
        XCTAssertEqual(session.zoomScale, 1.75)
        XCTAssertEqual(session.lastReadPosition, ReadingPosition(pageIndex: 2, point: CGPoint(x: 14, y: 28)))
    }

    func testLoadingDocumentClampsOutOfRangePositionToActualLastPageTop() throws {
        let url = try makeTemporaryPDF(named: "clamped-page-top", pageCount: 2)
        let readingStateStore = InMemoryReadingStateStore()
        readingStateStore.states[url] = PersistedReadingState(
            url: url,
            displayMode: .singlePageContinuous,
            scaleMode: .manual,
            scaleFactor: 1,
            readingPosition: ReadingPosition(pageIndex: 99, point: CGPoint(x: 41, y: 53))
        )
        let store = makeStore(readingStateStore: readingStateStore)
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let lastPage = try XCTUnwrap(document.page(at: 1))
        let expected = ReadingPosition.pageTop(
            pageIndex: 1,
            pageBounds: lastPage.bounds(for: .cropBox)
        )

        XCTAssertEqual(store.session(for: session.id)?.currentPageIndex, 1)
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, expected)
        XCTAssertEqual(readingStateStore.states[url]?.readingPosition, expected)
        XCTAssertNotEqual(expected.point, .zero)
    }

    func testDisabledFitWidthConfigOverridesPersistedFitWidthMode() throws {
        let url = try makeTemporaryPDF(named: "disabled-fit-width")
        let readingStateStore = InMemoryReadingStateStore()
        readingStateStore.states[url] = PersistedReadingState(
            url: url,
            displayMode: .singlePageContinuous,
            scaleMode: .fitWidth,
            scaleFactor: 1.4,
            readingPosition: ReadingPosition(pageIndex: 0, point: CGPoint(x: 0, y: 0))
        )
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore(),
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePageContinuous, fitWidthOnOpen: false),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )

        let session = try store.open(documentAt: url)

        XCTAssertEqual(session.scaleMode, .manual)
        XCTAssertEqual(session.zoomScale, 1.4)
    }

    func testOpenDocumentUpdatesRecentFilesOrdering() throws {
        let recentFilesStore = InMemoryRecentFilesStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: recentFilesStore
        )
        let firstURL = try makeTemporaryPDF(named: "recent-first")
        let secondURL = try makeTemporaryPDF(named: "recent-second")

        _ = try store.open(documentAt: firstURL)
        _ = try store.open(documentAt: secondURL)
        _ = try store.open(documentAt: firstURL)

        XCTAssertEqual(store.recentDocumentURLs, [firstURL, secondURL])
        XCTAssertEqual(recentFilesStore.recentFiles, [firstURL, secondURL])
    }

    func testRefreshRecentDocumentURLsFromStoreUsesLatestStoreState() throws {
        let recentFilesStore = InMemoryRecentFilesStore()
        let firstURL = try makeTemporaryPDF(named: "refresh-recent-first")
        let secondURL = try makeTemporaryPDF(named: "refresh-recent-second")
        recentFilesStore.recentFiles = [firstURL]
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: recentFilesStore
        )
        XCTAssertEqual(store.recentDocumentURLs, [firstURL])

        recentFilesStore.recentFiles = [secondURL, firstURL]
        store.refreshRecentDocumentURLsFromStore()

        XCTAssertEqual(store.recentDocumentURLs, [secondURL, firstURL])
    }

    func testOpenDocumentUsesConfiguredDefaultsWhenNoPersistedReadingStateExists() throws {
        let store = makeStore(
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .twoUp, fitWidthOnOpen: false),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )

        let session = try store.open(documentAt: makeTemporaryPDF(named: "config-defaults"))

        XCTAssertEqual(session.displayMode, .twoUp)
        XCTAssertEqual(session.scaleMode, .manual)
    }

    func testConfiguredLayoutWidthsIgnoreRestoredPerPDFSidebarWidths() throws {
        let url = try makeTemporaryPDF(named: "restored-layout-widths")
        let readingStateStore = InMemoryReadingStateStore()
        readingStateStore.states[url] = PersistedReadingState(
            url: url,
            displayMode: .singlePageContinuous,
            scaleMode: .manual,
            scaleFactor: 1.0,
            readingPosition: .zero,
            leftSidebarWidth: 59,
            rightSidebarWidth: 161
        )
        let configuration = AppConfiguration(
            reader: .default,
            annotations: .default,
            shortcuts: .default,
            layout: .init(
                leftSidebarWidth: 320,
                leftSidebarMinWidth: 36,
                leftSidebarMaxWidth: 520,
                rightSidebarWidth: 320,
                rightSidebarMinWidth: 120,
                rightSidebarMaxWidth: 720,
                sidebarsSwapped: false
            )
        )
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore(),
            appConfiguration: configuration
        )

        let session = try store.open(documentAt: url)

        XCTAssertEqual(session.url, url)
        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).left, 320)
        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).right, 320)
    }

    func testUpdateReadingPositionPersistsScaleAndPoint() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = makeStore(readingStateStore: readingStateStore)
        let session = try store.open(
            documentAt: makeTemporaryPDF(named: "reading-state", pageCount: 5)
        )

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 4, point: CGPoint(x: 33, y: 77)),
            scaleFactor: 1.5,
            for: session.id
        )
        store.setDisplayMode(.twoUp, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1.5, for: session.id)

        XCTAssertEqual(readingStateStore.states[session.url]?.readingPosition.pageIndex, 4)
        XCTAssertEqual(readingStateStore.states[session.url]?.readingPosition.point, CGPoint(x: 33, y: 77))
        XCTAssertEqual(readingStateStore.states[session.url]?.scaleFactor, 1.5)
        XCTAssertEqual(readingStateStore.states[session.url]?.displayMode, .twoUp)
        XCTAssertEqual(readingStateStore.states[session.url]?.scaleMode, .manual)
    }

    func testUpdateReadingPositionSamePagePointDoesNotNotifyGlobalObservers() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = makeStore(readingStateStore: readingStateStore)
        let session = try store.open(documentAt: makeTemporaryPDF(named: "reading-position-notify"))

        let counter = NotificationCounterObserver()
        NotificationCenter.default.addObserver(
            counter,
            selector: #selector(NotificationCounterObserver.handleDocumentStoreDidChange(_:)),
            name: .documentStoreDidChange,
            object: store
        )
        defer { NotificationCenter.default.removeObserver(counter) }

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 0, point: CGPoint(x: 33, y: 77)),
            scaleFactor: 1.0,
            for: session.id
        )

        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(readingStateStore.states[session.url]?.readingPosition.point, CGPoint(x: 33, y: 77))

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 1, point: CGPoint(x: 5, y: 9)),
            scaleFactor: 1.0,
            for: session.id
        )

        XCTAssertEqual(counter.count, 1)
    }

    func testPageTurnNotifiesReadingPositionWithoutRewritingWorkspacePersistence() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let readingStateStore = InMemoryReadingStateStore()
        let store = makeStore(persistence: persistence, readingStateStore: readingStateStore)
        let session = try store.open(documentAt: makeTemporaryPDF(named: "reading-position-mask", pageCount: 2))
        let snapshotAfterOpen = try XCTUnwrap(persistence.state)

        let recorder = DocumentStoreChangeRecorder()
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(DocumentStoreChangeRecorder.handleDocumentStoreDidChange(_:)),
            name: .documentStoreDidChange,
            object: store
        )
        defer { NotificationCenter.default.removeObserver(recorder) }

        // Mutate a field that would be rewritten if notifyChange(.all) ran.
        persistence.state?.windows[0].searchQuery = "should-not-be-clobbered"

        store.updateCurrentPage(index: 1, for: session.id)

        XCTAssertEqual(recorder.observedChange, .readingPosition)
        XCTAssertEqual(persistence.state?.windows.first?.searchQuery, "should-not-be-clobbered")
        XCTAssertEqual(persistence.state?.sessions.map(\.id), snapshotAfterOpen.sessions.map(\.id))
        XCTAssertEqual(readingStateStore.states[session.url]?.readingPosition.pageIndex, 1)
    }

    func testReadingStateRemainsIndependentAcrossSessions() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = makeStore(readingStateStore: readingStateStore)
        let first = try store.open(
            documentAt: makeTemporaryPDF(named: "first-reading-state", pageCount: 2)
        )
        let second = try store.open(
            documentAt: makeTemporaryPDF(named: "second-reading-state", pageCount: 7)
        )

        store.setDisplayMode(.singlePage, for: first.id)
        store.updateReadingPosition(
            ReadingPosition(pageIndex: 1, point: CGPoint(x: 10, y: 20)),
            scaleFactor: 1.2,
            for: first.id
        )
        store.setDisplayMode(.twoUpContinuous, for: second.id)
        store.updateReadingPosition(
            ReadingPosition(pageIndex: 6, point: CGPoint(x: 30, y: 40)),
            scaleFactor: 1.8,
            for: second.id
        )

        XCTAssertEqual(readingStateStore.states[first.url]?.displayMode, .singlePage)
        XCTAssertEqual(readingStateStore.states[first.url]?.readingPosition.pageIndex, 1)
        XCTAssertEqual(readingStateStore.states[second.url]?.displayMode, .twoUpContinuous)
        XCTAssertEqual(readingStateStore.states[second.url]?.readingPosition.pageIndex, 6)
    }

    func testToggleDisplayModeContinuityPreservesPageLayout() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "toggle-single-page-continuous"))

        store.setDisplayMode(.singlePage, for: session.id)
        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .singlePageContinuous)

        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .singlePage)

        store.setDisplayMode(.twoUp, for: session.id)
        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .twoUpContinuous)

        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .twoUp)

        store.setDisplayMode(.book, for: session.id)
        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .bookContinuous)

        store.toggleDisplayModeContinuity(for: session.id)
        XCTAssertEqual(store.session(for: session.id)?.displayMode, .book)
    }

    func testSaveAnnotationsWritesPDFAndClearsDirtyState() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "save-annotations"))
        let annotation = PDFAnnotation(
            bounds: NSRect(x: 20, y: 20, width: 60, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        annotation.color = .systemPink

        try store.pdfDocument(for: session.id).page(at: 0)?.addAnnotation(annotation)
        store.setDirty(true, for: session.id)
        try store.saveAnnotations(for: session.id)

        XCTAssertFalse(store.session(for: session.id)?.isDirty ?? true)

        let reopenedDocument = PDFDocument(url: session.url)
        XCTAssertEqual(reopenedDocument?.page(at: 0)?.annotations.count, 1)
    }

    func testCleanCopyDataDoesNotMutateSessionDocumentOrDirtyState() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "clean-copy-data"))
        let document = try store.pdfDocument(for: session.id)
        let page = try XCTUnwrap(document.page(at: 0))
        let highlight = PDFAnnotation(
            bounds: NSRect(x: 20, y: 20, width: 60, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        let link = PDFAnnotation(
            bounds: NSRect(x: 20, y: 50, width: 60, height: 18),
            forType: .link,
            withProperties: nil
        )
        page.addAnnotation(highlight)
        page.addAnnotation(link)
        store.setDirty(true, for: session.id)

        let cleanData = try store.cleanCopyData(for: session.id)
        let cleanDocument = try XCTUnwrap(PDFDocument(data: cleanData))
        let cleanTypes = try XCTUnwrap(cleanDocument.page(at: 0)?.annotations.compactMap(\.type).sorted())

        XCTAssertEqual(cleanTypes, ["Link"])
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 2)
        XCTAssertTrue(store.session(for: session.id)?.isDirty == true)
        XCTAssertTrue(store.isPDFDocumentLoaded(for: session.id))
    }

    func testWriteCleanCopyDoesNotOverwriteSourcePDF() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "write-clean-copy"))
        let document = try store.pdfDocument(for: session.id)
        let page = try XCTUnwrap(document.page(at: 0))
        page.addAnnotation(
            PDFAnnotation(
                bounds: NSRect(x: 20, y: 20, width: 60, height: 18),
                forType: .highlight,
                withProperties: nil
            )
        )
        store.setDirty(true, for: session.id)

        let cleanURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try store.writeCleanCopy(for: session.id, to: cleanURL)

        XCTAssertTrue(store.session(for: session.id)?.isDirty == true)
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count, 0)
        XCTAssertEqual(PDFDocument(url: cleanURL)?.page(at: 0)?.annotations.count, 0)
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 1)
    }

    func testCurrentPageImageUsesSessionPageAndRejectsBlankTabs() throws {
        let store = makeStore()
        let url = try TestPDFFixtures.makeLabeledPDF(
            named: "current-page-image",
            pageSizes: [
                NSSize(width: 200, height: 260),
                NSSize(width: 300, height: 400),
            ]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let secondPage = try XCTUnwrap(document.page(at: 1))

        let firstImage = try store.currentPageImage(for: session.id)
        XCTAssertEqual(
            firstImage.size.width,
            firstPage.bounds(for: .mediaBox).width * PDFPageImageService.renderScale,
            accuracy: 0.5
        )
        XCTAssertEqual(
            firstImage.size.height,
            firstPage.bounds(for: .mediaBox).height * PDFPageImageService.renderScale,
            accuracy: 0.5
        )

        store.updateCurrentPage(index: 1, for: session.id)
        let secondImage = try store.currentPageImage(for: session.id)
        XCTAssertEqual(
            secondImage.size.width,
            secondPage.bounds(for: .mediaBox).width * PDFPageImageService.renderScale,
            accuracy: 0.5
        )
        XCTAssertEqual(
            secondImage.size.height,
            secondPage.bounds(for: .mediaBox).height * PDFPageImageService.renderScale,
            accuracy: 0.5
        )

        let blank = store.newBlankTab()
        XCTAssertThrowsError(try store.currentPageImage(for: blank.id)) { error in
            guard case DocumentStoreError.blankSession = error else {
                XCTFail("expected blankSession, got \(error)")
                return
            }
        }
    }

    func testAnnotationSectionsExposeSnippetColorAndPageGrouping() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-sections",
            pages: ["alpha beta gamma", "delta epsilon"]
        )
        let session = try store.open(documentAt: url)
        let selection = try XCTUnwrap(store.pdfDocument(for: session.id).findString("beta", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.yellow.nsColor)
        store.noteHighlightsAdded(records, for: session.id)

        let sections = store.annotationSections(in: store.defaultWindowID)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Page 1")
        XCTAssertEqual(sections.first?.highlights.count, 1)
        XCTAssertEqual(sections.first?.highlights.first?.color, .yellow)
        XCTAssertTrue(sections.first?.highlights.first?.snippet.contains("beta") == true)
    }

    func testAddingHighlightDoesNotBuildAnnotationCacheBeforeAnnotationsPaneLoads() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-cache-stays-lazy",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let selection = try XCTUnwrap(store.pdfDocument(for: session.id).findString("beta", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.yellow.nsColor)
        store.noteHighlightsAdded(records, for: session.id)

        XCTAssertEqual(store.session(for: session.id)?.isDirty, true)
        XCTAssertEqual(store.session(for: session.id)?.isAnnotationCacheLoaded, false)
    }

    func testAnnotationHitBuildsIndexedCacheOnceAndReusesItForRemoval() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-hover-target",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection)
        store.noteHighlightsAdded(records, for: session.id)

        let group = try XCTUnwrap(
            store.annotationGroup(containing: records[0].annotation, for: session.id)
        )

        XCTAssertEqual(group.records.count, records.count)
        XCTAssertTrue(store.session(for: session.id)?.isAnnotationCacheLoaded == true)
        XCTAssertTrue(store.removeHighlightGroup(group, in: session.id))
        XCTAssertTrue(store.session(for: session.id)?.isAnnotationCacheLoaded == true)
        XCTAssertTrue(store.annotationGroups(for: session.id).isEmpty)
        XCTAssertTrue(document.page(at: 0)?.annotations.filter { $0.type == "Highlight" }.isEmpty == true)
    }

    func testLoadedAnnotationCacheUpdatesIncrementallyForAddedAndRemovedHighlights() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-cache-incremental",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)

        let alphaRecords = HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor)
        store.noteHighlightsAdded(alphaRecords, for: session.id)
        XCTAssertEqual(store.annotationGroups(for: session.id).count, 1)

        let betaRecords = HighlightService.applyHighlight(to: betaSelection, color: HighlightColor.green.nsColor)
        store.noteHighlightsAdded(betaRecords, for: session.id)
        XCTAssertEqual(store.annotationGroups(for: session.id).map(\.snippet).sorted(), ["alpha", "beta"])

        HighlightService.removeHighlights(betaRecords, in: document)
        store.noteHighlightsRemoved(betaRecords, for: session.id)

        let groups = store.annotationGroups(for: session.id)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.snippet, "alpha")
    }

    func testLoadedAnnotationCacheTracksUndoAndRedo() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-cache-undo-redo",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let selection = try XCTUnwrap(store.pdfDocument(for: session.id).findString("alpha", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor)
        store.noteHighlightsAdded(records, for: session.id)
        XCTAssertEqual(store.annotationGroups(for: session.id).count, 1)

        XCTAssertTrue(store.undoLastHighlight(for: session.id))
        XCTAssertEqual(store.annotationGroups(for: session.id).count, 0)

        XCTAssertTrue(store.redoLastHighlight(for: session.id))
        XCTAssertEqual(store.annotationGroups(for: session.id).first?.snippet, "alpha")
    }

    func testHasHighlightsRecognizesTextMarkupAndCachesTheScan() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "highlight-menu-validation"))
        let annotation = PDFAnnotation(
            bounds: NSRect(x: 20, y: 20, width: 60, height: 18),
            forType: .strikeOut,
            withProperties: nil
        )

        try store.pdfDocument(for: session.id).page(at: 0)?.addAnnotation(annotation)

        XCTAssertTrue(store.hasHighlights(for: session.id))
        XCTAssertTrue(store.session(for: session.id)?.isAnnotationCacheLoaded == true)
    }

    func testUpdateCommentPersistsAcrossHighlightGroupAndMarksSessionDirty() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-comment",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor)
        store.noteHighlightsAdded(records, for: session.id)

        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        XCTAssertTrue(store.updateComment("Important note", forHighlightGroup: group.groupID, in: session.id))

        let updatedGroup = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        XCTAssertEqual(updatedGroup.comment, "Important note")
        XCTAssertTrue(store.session(for: session.id)?.isDirty == true)
        XCTAssertEqual(
            document.page(at: 0)?.annotations.first(where: { $0.type == "Highlight" })?.contents,
            "Important note"
        )
    }

    func testUpdateAppConfigurationAppliesNewDefaultsToFutureSessions() throws {
        let store = makeStore()
        let firstSession = try store.open(documentAt: makeTemporaryPDF(named: "settings-first"))

        store.updateAppConfiguration(
            AppConfiguration(
                reader: .init(defaultDisplayMode: .twoUp, fitWidthOnOpen: true),
                annotations: .init(autoSavePolicy: .never),
                shortcuts: .default,
                layout: .default
            )
        )

        let secondSession = try store.open(documentAt: makeTemporaryPDF(named: "settings-second"))

        XCTAssertEqual(store.session(for: firstSession.id)?.annotationSavePolicy, .never)
        XCTAssertEqual(store.session(for: firstSession.id)?.displayMode, .singlePageContinuous)
        XCTAssertEqual(store.session(for: firstSession.id)?.scaleMode, .fitWidth)
        XCTAssertEqual(secondSession.displayMode, .twoUp)
        XCTAssertEqual(secondSession.scaleMode, .fitWidth)
        XCTAssertEqual(secondSession.annotationSavePolicy, .never)
    }

    func testUpdateAppConfigurationAppliesLayoutWidthsToWindowRuntimeState() throws {
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "settings-layout-widths"))
        store.updateSidebarWidths(left: 180, right: 260, in: store.defaultWindowID)

        store.updateAppConfiguration(
            AppConfiguration(
                reader: .default,
                annotations: .default,
                shortcuts: .default,
                layout: .init(
                    leftSidebarWidth: 310,
                    leftSidebarMinWidth: 36,
                    leftSidebarMaxWidth: 520,
                    rightSidebarWidth: 410,
                    rightSidebarMinWidth: 120,
                    rightSidebarMaxWidth: 720,
                    sidebarsSwapped: false
                )
            )
        )

        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).left, 310)
        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).right, 410)
    }

    func testUpdateAppConfigurationDisablingFitWidthFlipsExistingSessionsToManual() throws {
        let store = makeStore(
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePageContinuous, fitWidthOnOpen: true),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "fit-width-off"))
        XCTAssertEqual(session.scaleMode, .fitWidth)

        store.setScaleMode(.fitWidth, scaleFactor: 1.75, for: session.id)

        store.updateAppConfiguration(
            AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePageContinuous, fitWidthOnOpen: false),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.scaleMode, .manual)
        XCTAssertEqual(updated.zoomScale, 1.75)
    }

    func testUserZoomAfterFitWidthOnOpenPinsManualScale() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = makeStore(
            readingStateStore: readingStateStore,
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePageContinuous, fitWidthOnOpen: true),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )
        let session = try store.open(
            documentAt: makeTemporaryPDF(named: "zoom-pins-manual", pageCount: 3)
        )
        XCTAssertEqual(session.scaleMode, .fitWidth)

        // User zoom gesture: handlePDFViewScaleChanged calls setScaleMode(.manual, ...).
        store.setScaleMode(.manual, scaleFactor: 2.3, for: session.id)

        // Page turn fires updateReadingPosition, which must not resurrect fitWidth.
        let page = try XCTUnwrap(try store.pdfDocument(for: session.id).page(at: 2))
        store.updateReadingPosition(
            .pageTop(pageIndex: 2, pageBounds: page.bounds(for: .cropBox)),
            scaleFactor: 2.3,
            for: session.id
        )

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.scaleMode, .manual)
        XCTAssertEqual(updated.zoomScale, 2.3)
        XCTAssertEqual(readingStateStore.states[session.url]?.scaleMode, .manual)
    }

    func testUpdateAppConfigurationSwapsWindowSidebarWidthsAndVisibilities() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore()
        )

        _ = try store.open(documentAt: makeTemporaryPDF(named: "swap-widths"))
        store.updateSidebarWidths(left: 40, right: 320, in: store.defaultWindowID)
        store.setLeftSidebarVisible(true)
        store.setRightSidebarVisible(false)
        store.setRightSidebarMode(.outline, in: store.defaultWindowID)
        XCTAssertFalse(store.isOutlineSidebarVisible(in: store.defaultWindowID))

        // Right pane open but not Outline → outline content is not visible.
        store.setRightSidebarVisible(true)
        store.setRightSidebarMode(.annotations, in: store.defaultWindowID)
        XCTAssertFalse(store.isOutlineSidebarVisible(in: store.defaultWindowID))
        store.setRightSidebarMode(.outline, in: store.defaultWindowID)
        XCTAssertTrue(store.isOutlineSidebarVisible(in: store.defaultWindowID))
        store.setRightSidebarVisible(false)

        var swappedConfig = store.appConfiguration
        swappedConfig.layout.sidebarsSwapped = true
        store.updateAppConfiguration(swappedConfig)

        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).left, 320)
        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).right, 40)
        XCTAssertFalse(store.isLeftSidebarVisible)
        XCTAssertTrue(store.isRightSidebarVisible)
        XCTAssertFalse(store.isOutlineSidebarVisible(in: store.defaultWindowID))

        store.setLeftSidebarVisible(true)
        store.setRightSidebarMode(.outline, in: store.defaultWindowID)
        XCTAssertTrue(store.isOutlineSidebarVisible(in: store.defaultWindowID))
        store.setLeftSidebarVisible(false)

        var unswappedConfig = store.appConfiguration
        unswappedConfig.layout.sidebarsSwapped = false
        store.updateAppConfiguration(unswappedConfig)

        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).left, 40)
        XCTAssertEqual(store.sidebarWidths(in: store.defaultWindowID).right, 320)
        XCTAssertTrue(store.isLeftSidebarVisible)
        XCTAssertFalse(store.isRightSidebarVisible)
        XCTAssertFalse(store.isOutlineSidebarVisible(in: store.defaultWindowID))
    }

    func testSplitWorkspaceRoutesActiveSessionByFocusedPane() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-second"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)

        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), second.id)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertEqual(store.activeSessionID(in: windowID), second.id)

        store.activate(sessionID: first.id, in: windowID, targetPane: .secondary)
        store.setFocusedPane(.secondary, in: windowID)
        XCTAssertEqual(store.activeSessionID(in: windowID), first.id)

        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)
        let duplicatedSecondID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(duplicatedSecondID, second.id)
        XCTAssertEqual(store.session(for: duplicatedSecondID)?.url, second.url)
        XCTAssertEqual(store.activeSessionID(in: windowID), duplicatedSecondID)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [first.id, second.id])
    }

    func testBrowserSplitPairHidesAndRestoresAroundOtherTabs() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-pair-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-pair-second"))
        let third = try store.open(documentAt: makeTemporaryPDF(named: "split-pair-third"))
        let windowID = store.defaultWindowID

        store.activate(sessionID: first.id, in: windowID)
        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)

        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.splitPair(in: windowID), ReaderSplitPair(primarySessionID: first.id, secondarySessionID: second.id))

        store.activate(sessionID: third.id, in: windowID)

        XCTAssertFalse(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), third.id)
        XCTAssertEqual(store.splitPair(in: windowID), ReaderSplitPair(primarySessionID: first.id, secondarySessionID: second.id))

        store.activate(sessionID: second.id, in: windowID)

        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), first.id)
        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), second.id)
        XCTAssertEqual(store.focusedPane(in: windowID), .secondary)
    }

    func testOptionActivationReplacesFocusedSplitPane() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-option-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-option-second"))
        let third = try store.open(documentAt: makeTemporaryPDF(named: "split-option-third"))
        let windowID = store.defaultWindowID

        store.activate(sessionID: first.id, in: windowID)
        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)
        store.activate(sessionID: third.id, in: windowID, targetPane: .secondary)

        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), first.id)
        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), third.id)
        XCTAssertEqual(store.splitPair(in: windowID), ReaderSplitPair(primarySessionID: first.id, secondarySessionID: third.id))
    }

    func testSplitWithSingleSessionCreatesIndependentComparisonSession() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-single-duplicate"))
        let windowID = store.defaultWindowID

        _ = store.annotationGroups(for: session.id)
        XCTAssertTrue(store.session(for: session.id)?.isAnnotationCacheLoaded == true)

        store.setSplitEnabled(true, in: windowID)
        XCTAssertEqual(store.splitCandidateSessions(in: windowID).map(\.id), [session.id])
        store.activate(sessionID: session.id, in: windowID, targetPane: .secondary)

        let primaryID = try XCTUnwrap(store.displayedSessionID(for: .primary, in: windowID))
        let secondaryID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(primaryID, secondaryID)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [session.id])
        XCTAssertEqual(store.session(for: primaryID)?.url, session.url)
        XCTAssertEqual(store.session(for: secondaryID)?.url, session.url)
        XCTAssertTrue(store.session(for: secondaryID)?.isAnnotationCacheLoaded == true)
        XCTAssertTrue(try store.pdfDocument(for: primaryID) === store.pdfDocument(for: secondaryID))

        store.setScaleMode(.manual, scaleFactor: 2.0, for: primaryID)
        XCTAssertEqual(store.session(for: primaryID)?.zoomScale, 2.0)
        XCTAssertEqual(store.session(for: secondaryID)?.zoomScale, session.zoomScale)
    }

    func testComparisonSessionStaysOutOfTabsAndPersistence() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let session = try store.open(
            documentAt: makeTemporaryPDF(named: "split-internal-comparison", pageCount: 3)
        )
        let windowID = store.defaultWindowID
        var notedURLs: [URL] = []
        store.noteRecentDocumentURL = { notedURLs.append($0) }

        store.updateReadingPosition(
            ReadingPosition(pageIndex: 1, point: CGPoint(x: 23, y: 47)),
            scaleFactor: 1.4,
            for: session.id
        )
        store.setDisplayMode(.singlePage, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1.4, for: session.id)
        let expectedPrimaryState = try XCTUnwrap(readingStateStore.states[session.url])
        let primarySaveCount = readingStateStore.savedStates.count

        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: session.id, in: windowID, targetPane: .secondary)

        let comparisonID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(comparisonID, session.id)
        XCTAssertEqual(
            store.publicSessionID(forDisplayedSessionID: comparisonID, in: windowID),
            session.id
        )
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [session.id])
        XCTAssertEqual(persistence.state?.sessions.map(\.id), [session.id])
        XCTAssertEqual(persistence.state?.windows.first?.sessionIDs, [session.id])
        XCTAssertNil(persistence.state?.windows.first?.splitState.secondarySessionID)
        XCTAssertTrue(notedURLs.isEmpty)

        store.updateCurrentPage(index: 2, for: comparisonID)
        store.setDisplayMode(.twoUp, for: comparisonID)
        store.setScaleMode(.manual, scaleFactor: 1.8, for: comparisonID)
        store.updateReadingPosition(
            ReadingPosition(pageIndex: 1, point: CGPoint(x: 17, y: 29)),
            scaleFactor: 1.8,
            for: comparisonID
        )

        XCTAssertEqual(readingStateStore.states[session.url], expectedPrimaryState)
        XCTAssertEqual(readingStateStore.savedStates.count, primarySaveCount)
    }

    func testActivatingSameSessionIntoOtherPaneReusesExistingComparisonSession() throws {
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-reuse-duplicate"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)
        let primaryID = try XCTUnwrap(store.displayedSessionID(for: .primary, in: windowID))

        store.activate(sessionID: primaryID, in: windowID, targetPane: .secondary)
        let initialSecondaryID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        store.activate(sessionID: primaryID, in: windowID)
        store.activate(sessionID: primaryID, in: windowID, targetPane: .secondary)

        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), initialSecondaryID)
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testDisablingSplitRemovesAutoCreatedComparisonSession() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-disable-cleans-clone"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: session.id, in: windowID, targetPane: .secondary)
        XCTAssertEqual(store.sessions.count, 2)

        store.setSplitEnabled(false, in: windowID)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, session.id)
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), session.id)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowID))
    }

    func testCreateWindowStartsEmptyButKeepsIndependentUIState() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "window-copy-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "window-copy-second"))
        let sourceWindowID = store.defaultWindowID

        store.setSplitEnabled(true, in: sourceWindowID)
        store.activate(sessionID: first.id, in: sourceWindowID, targetPane: .secondary)
        store.setFocusedPane(.secondary, in: sourceWindowID)
        store.setTabPresentationMode(.horizontalTitlebar, in: sourceWindowID)
        store.setLeftSidebarVisible(false, in: sourceWindowID)

        let copiedWindowID = store.createWindow(copyingFrom: sourceWindowID)

        XCTAssertFalse(store.isSplitEnabled(in: copiedWindowID))
        XCTAssertNil(store.displayedSessionID(for: .primary, in: copiedWindowID))
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: copiedWindowID))
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)
        XCTAssertEqual(store.focusedPane(in: copiedWindowID), .primary)
        XCTAssertEqual(store.tabPresentationMode(in: copiedWindowID), .horizontalTitlebar)
        XCTAssertFalse(store.isLeftSidebarVisible(in: copiedWindowID))
        XCTAssertTrue(store.recentlyClosedURLs(in: copiedWindowID).isEmpty)

        store.setLeftSidebarVisible(true, in: copiedWindowID)
        store.setFocusedPane(.primary, in: copiedWindowID)

        XCTAssertFalse(store.isLeftSidebarVisible(in: sourceWindowID))
        XCTAssertEqual(store.focusedPane(in: sourceWindowID), .secondary)
    }

    func testOpeningAndClosingSessionsStayScopedToTheirWindow() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "window-scope-first"))
        let sourceWindowID = store.defaultWindowID
        let copiedWindowID = store.createWindow(copyingFrom: sourceWindowID)

        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [first.id])
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)

        let second = try store.open(documentAt: makeTemporaryPDF(named: "window-scope-second"), in: sourceWindowID)
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [first.id, second.id])
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)

        store.close(sessionID: second.id, from: sourceWindowID)
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [first.id])
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)

        store.close(sessionID: first.id, from: sourceWindowID)
        XCTAssertTrue(store.sessions(in: sourceWindowID).isEmpty)
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)
        XCTAssertNil(store.session(for: first.id))
    }

    func testClosingEmptyWindowKeepsOtherWindowSessionsIntact() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "window-close-source"))
        let sourceWindowID = store.defaultWindowID
        let copiedWindowID = store.createWindow(copyingFrom: sourceWindowID)
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [session.id])
        XCTAssertTrue(store.sessions(in: copiedWindowID).isEmpty)

        store.closeWindow(id: copiedWindowID)

        XCTAssertEqual(store.windowIDs(), [sourceWindowID])
        XCTAssertEqual(store.sessions.map(\.id), [session.id])
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [session.id])
    }

    func testMergeAllWindowsMovesSessionsIntoTargetWindow() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "merge-window-first"))
        let targetWindowID = store.defaultWindowID
        let secondWindowID = store.createWindow(copyingFrom: targetWindowID)
        let second = try store.open(documentAt: makeTemporaryPDF(named: "merge-window-second"), in: secondWindowID)

        store.mergeAllWindows(into: targetWindowID)

        XCTAssertEqual(store.windowIDs(), [targetWindowID])
        XCTAssertEqual(store.sessions(in: targetWindowID).map(\.id), [first.id, second.id])
        XCTAssertEqual(store.activeSessionID(in: targetWindowID), first.id)
    }

    func testCloseWindowCancelsInFlightSearch() throws {
        let store = makeStore()
        let firstWindowID = store.defaultWindowID
        _ = try store.open(
            documentAt: makeSearchableTemporaryPDF(named: "close-search-keep", pages: ["alpha"])
        )
        let secondWindowID = store.createWindow(copyingFrom: firstWindowID)
        _ = try store.open(
            documentAt: makeSearchableTemporaryPDF(
                named: "close-search-drop",
                pages: (0..<40).map { "needle \($0)" }
            ),
            in: secondWindowID
        )

        store.updateSearch(query: "needle", scope: .currentDocument, in: secondWindowID)
        XCTAssertTrue(store.testingIsSearchInFlight(in: secondWindowID))

        store.closeWindow(id: secondWindowID)

        XCTAssertFalse(store.testingIsSearchInFlight(in: secondWindowID))
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).totalMatches, 0)
        XCTAssertFalse(store.searchSnapshot(in: secondWindowID).isSearching)
    }

    func testMergeAllWindowsCancelsDiscardedWindowSearch() throws {
        let store = makeStore()
        let targetWindowID = store.defaultWindowID
        _ = try store.open(
            documentAt: makeSearchableTemporaryPDF(named: "merge-search-keep", pages: ["alpha"])
        )
        let secondWindowID = store.createWindow(copyingFrom: targetWindowID)
        _ = try store.open(
            documentAt: makeSearchableTemporaryPDF(
                named: "merge-search-drop",
                pages: (0..<40).map { "needle \($0)" }
            ),
            in: secondWindowID
        )

        store.updateSearch(query: "needle", scope: .currentDocument, in: secondWindowID)
        XCTAssertTrue(store.testingIsSearchInFlight(in: secondWindowID))

        store.mergeAllWindows(into: targetWindowID)

        XCTAssertFalse(store.testingIsSearchInFlight(in: secondWindowID))
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).totalMatches, 0)
    }

    func testMoveActiveSessionToNewWindowDetachesOnlyCurrentPDF() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "detach-window-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "detach-window-second"))
        let sourceWindowID = store.defaultWindowID

        let newWindowID = try XCTUnwrap(store.moveActiveSessionToNewWindow(from: sourceWindowID))

        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [first.id])
        XCTAssertEqual(store.sessions(in: newWindowID).map(\.id), [second.id])
        XCTAssertEqual(store.activeSessionID(in: newWindowID), second.id)
        XCTAssertEqual(Set(store.windowIDs()), [sourceWindowID, newWindowID])
    }

    func testMoveActiveComparisonSessionToNewWindowMovesPublicPDF() throws {
        let store = makeStore()
        let pdf = try store.open(documentAt: makeTemporaryPDF(named: "move-comparison-new-window"))
        let sourceWindowID = store.defaultWindowID
        store.activate(sessionID: pdf.id, in: sourceWindowID, targetPane: .secondary)
        let comparisonSessionID = try XCTUnwrap(
            store.displayedSessionID(for: .secondary, in: sourceWindowID)
        )
        XCTAssertNotEqual(comparisonSessionID, pdf.id)
        XCTAssertEqual(store.activeSessionID(in: sourceWindowID), comparisonSessionID)

        let destinationWindowID = try XCTUnwrap(
            store.moveActiveSessionToNewWindow(from: sourceWindowID)
        )

        XCTAssertTrue(store.sessions(in: sourceWindowID).isEmpty)
        XCTAssertEqual(store.sessions(in: destinationWindowID).map(\.id), [pdf.id])
        XCTAssertNil(store.session(for: comparisonSessionID))
    }

    func testMoveComparisonSessionToExistingWindowMovesPublicPDF() throws {
        let store = makeStore()
        let pdf = try store.open(documentAt: makeTemporaryPDF(named: "move-comparison-existing-window"))
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)
        store.activate(sessionID: pdf.id, in: sourceWindowID, targetPane: .secondary)
        let comparisonSessionID = try XCTUnwrap(
            store.displayedSessionID(for: .secondary, in: sourceWindowID)
        )

        XCTAssertTrue(
            store.moveSession(
                comparisonSessionID,
                from: sourceWindowID,
                to: destinationWindowID
            )
        )

        XCTAssertTrue(store.sessions(in: sourceWindowID).isEmpty)
        XCTAssertEqual(store.sessions(in: destinationWindowID).map(\.id), [pdf.id])
        XCTAssertNil(store.session(for: comparisonSessionID))
    }

    func testMoveSessionToExistingWindowPreservesDocumentStateAndAppendsIt() throws {
        let persistence = InMemoryDocumentStorePersistence()
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let sourceAnchor = try store.open(documentAt: makeTemporaryPDF(named: "move-existing-source"))
        let moved = try store.open(documentAt: makeTemporaryPDF(named: "move-existing-current", pageCount: 4))
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)
        let destinationAnchor = try store.open(
            documentAt: makeTemporaryPDF(named: "move-existing-destination"),
            in: destinationWindowID
        )
        store.updateCurrentPage(index: 2, for: moved.id)
        store.setDirty(true, for: moved.id)
        let loadedDocument = try store.pdfDocument(for: moved.id)

        XCTAssertTrue(store.moveSession(moved.id, from: sourceWindowID, to: destinationWindowID))

        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [sourceAnchor.id])
        XCTAssertEqual(store.activeSessionID(in: sourceWindowID), sourceAnchor.id)
        XCTAssertEqual(
            store.sessions(in: destinationWindowID).map(\.id),
            [destinationAnchor.id, moved.id]
        )
        XCTAssertEqual(store.activeSessionID(in: destinationWindowID), moved.id)
        XCTAssertEqual(store.selectedSessionIDs(in: destinationWindowID), [moved.id])
        XCTAssertEqual(store.openLocation(for: moved.url), DocumentOpenLocation(windowID: destinationWindowID, sessionID: moved.id))
        XCTAssertEqual(store.session(for: moved.id)?.currentPageIndex, 2)
        XCTAssertTrue(store.session(for: moved.id)?.isDirty == true)
        XCTAssertTrue(try store.pdfDocument(for: moved.id) === loadedDocument)
        XCTAssertTrue(store.recentlyClosedURLs(in: sourceWindowID).isEmpty)
        XCTAssertTrue(store.recentlyClosedURLs(in: destinationWindowID).isEmpty)

        let persistedState = try XCTUnwrap(persistence.state)
        XCTAssertEqual(
            persistedState.windows.first(where: { $0.id == sourceWindowID })?.sessionIDs,
            [sourceAnchor.id]
        )
        XCTAssertEqual(
            persistedState.windows.first(where: { $0.id == destinationWindowID })?.sessionIDs,
            [destinationAnchor.id, moved.id]
        )
    }

    func testMoveSessionRepairsSourceSelectionContinuousReadingAndSplitPair() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "move-state-first"))
        let moved = try store.open(documentAt: makeTemporaryPDF(named: "move-state-current"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "move-state-third"))
        let sourceWindowID = store.defaultWindowID
        store.selectSessions([first.id, moved.id], in: sourceWindowID)
        XCTAssertTrue(store.startContinuousReadingFromSelectedSessions(in: sourceWindowID))
        store.activate(sessionID: first.id, in: sourceWindowID)
        store.activate(sessionID: moved.id, in: sourceWindowID, targetPane: .secondary)
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)

        XCTAssertTrue(store.moveSession(moved.id, from: sourceWindowID, to: destinationWindowID))

        XCTAssertFalse(store.isSplitEnabled(in: sourceWindowID))
        XCTAssertNil(store.splitPair(in: sourceWindowID))
        XCTAssertEqual(store.activeSessionID(in: sourceWindowID), first.id)
        XCTAssertEqual(store.selectedSessionIDs(in: sourceWindowID), [first.id])
        XCTAssertFalse(store.isContinuousReadingEnabled(in: sourceWindowID))
        XCTAssertTrue(store.continuousReadingSessionIDs(in: sourceWindowID).isEmpty)
        XCTAssertEqual(store.sessions(in: destinationWindowID).map(\.id), [moved.id])
        XCTAssertEqual(store.activeSessionID(in: destinationWindowID), moved.id)
    }

    func testMoveSessionRejectsBlankSameWindowAndUnknownTargets() throws {
        let store = makeStore()
        let pdf = try store.open(documentAt: makeTemporaryPDF(named: "move-invalid-pdf"))
        let blank = store.newBlankTab()
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)

        XCTAssertFalse(store.moveSession(blank.id, from: sourceWindowID, to: destinationWindowID))
        XCTAssertFalse(store.moveSession(pdf.id, from: sourceWindowID, to: sourceWindowID))
        XCTAssertFalse(store.moveSession(pdf.id, from: sourceWindowID, to: UUID()))
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [pdf.id, blank.id])
        XCTAssertTrue(store.sessions(in: destinationWindowID).isEmpty)
    }

    func testMoveLastSessionKeepsSourceWindowEmpty() throws {
        let store = makeStore()
        let moved = try store.open(documentAt: makeTemporaryPDF(named: "move-last-session"))
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)

        XCTAssertTrue(store.moveSession(moved.id, from: sourceWindowID, to: destinationWindowID))

        XCTAssertEqual(Set(store.windowIDs()), [sourceWindowID, destinationWindowID])
        XCTAssertTrue(store.sessions(in: sourceWindowID).isEmpty)
        XCTAssertNil(store.activeSessionID(in: sourceWindowID))
        XCTAssertEqual(store.sessions(in: destinationWindowID).map(\.id), [moved.id])
    }

    func testAllOpenSearchBuildsSectionsAcrossSessions() throws {
        let store = makeStore()
        let alphaURL = try makeSearchableTemporaryPDF(
            named: "alpha-search",
            pages: ["alpha needle one", "shared beta needle"]
        )
        let betaURL = try makeSearchableTemporaryPDF(
            named: "beta-search",
            pages: ["shared beta needle", "gamma"]
        )

        _ = try store.open(documentAt: alphaURL)
        _ = try store.open(documentAt: betaURL)

        store.updateSearch(query: "needle", scope: .allOpen, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)

        let snapshot = store.searchSnapshot(in: store.defaultWindowID)
        let sections = snapshot.sections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(snapshot.totalMatches, 3)
        XCTAssertEqual(Set(sections.map(\.title)), ["alpha-search", "beta-search"])
        XCTAssertTrue(sections.allSatisfy { $0.matches.isEmpty == false })
    }

    func testClearSearchResetsCachesAndSidebarMode() throws {
        let store = makeStore()
        let firstURL = try makeSearchableTemporaryPDF(
            named: "clear-search-first",
            pages: ["clearable token", "second token"]
        )
        let secondURL = try makeSearchableTemporaryPDF(
            named: "clear-search-second",
            pages: ["clearable token too"]
        )
        _ = try store.open(documentAt: firstURL)
        _ = try store.open(documentAt: secondURL)

        store.updateSearch(query: "token", scope: .allOpen, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)
        XCTAssertEqual(store.rightSidebarMode(in: store.defaultWindowID), .search)
        XCTAssertGreaterThan(store.searchSnapshot(in: store.defaultWindowID).totalMatches, 0)

        store.clearSearch(in: store.defaultWindowID)

        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "")
        XCTAssertEqual(store.rightSidebarMode(in: store.defaultWindowID), .outline)
        XCTAssertEqual(store.searchSnapshot(in: store.defaultWindowID).totalMatches, 0)
        XCTAssertTrue(store.searchSnapshot(in: store.defaultWindowID).sections.isEmpty)
    }

    func testWindowSearchSnapshotsKeepQueriesAndClearStateIsolated() throws {
        let store = makeStore()
        let firstWindowID = store.defaultWindowID
        let secondWindowID = store.createWindow(copyingFrom: firstWindowID)
        let firstURL = try makeSearchableTemporaryPDF(
            named: "window-search-first",
            pages: ["alpha token"]
        )
        let secondURL = try makeSearchableTemporaryPDF(
            named: "window-search-second",
            pages: ["beta token"]
        )
        _ = try store.open(documentAt: firstURL, in: firstWindowID)
        _ = try store.open(documentAt: secondURL, in: secondWindowID)

        store.updateSearch(query: "alpha", scope: .currentDocument, in: firstWindowID)
        store.updateSearch(query: "beta", scope: .currentDocument, in: secondWindowID)
        waitForDocumentSearch(in: store, windowID: firstWindowID)
        waitForDocumentSearch(in: store, windowID: secondWindowID)

        XCTAssertEqual(store.searchSnapshot(in: firstWindowID).query, "alpha")
        XCTAssertEqual(store.searchSnapshot(in: firstWindowID).totalMatches, 1)
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).query, "beta")
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).totalMatches, 1)

        store.clearSearch(in: firstWindowID)

        XCTAssertEqual(store.searchSnapshot(in: firstWindowID).query, "")
        XCTAssertEqual(store.searchSnapshot(in: firstWindowID).totalMatches, 0)
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).query, "beta")
        XCTAssertEqual(store.searchSnapshot(in: secondWindowID).totalMatches, 1)
    }

    func testCurrentDocumentSearchOnManyPagesFindsAllMatches() throws {
        let store = makeStore()
        // Correctness over strict wall-clock: CI load makes sub-0.5s flaky.
        let pages = (0..<80).map { index in
            "performance needle page \(index) repeated needle"
        }
        let url = try makeSearchableTemporaryPDF(named: "search-perf", pages: pages)
        _ = try store.open(documentAt: url)

        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)

        XCTAssertEqual(store.searchSnapshot(in: store.defaultWindowID).totalMatches, 160)
    }

    func testAllOpenSearchDoesNotLoadOrPinReaderPDFDocuments() throws {
        let store = makeStore()
        let urls = try (0..<6).map { index in
            try makeSearchableTemporaryPDF(
                named: "search-memory-\(index)",
                pages: ["shared needle \(index)"]
            )
        }
        let sessions = try store.open(documentsAt: urls, in: store.defaultWindowID)

        store.updateSearch(query: "needle", scope: .allOpen, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)

        XCTAssertEqual(store.searchSnapshot(in: store.defaultWindowID).totalMatches, 6)
        XCTAssertTrue(sessions.allSatisfy { store.isPDFDocumentLoaded(for: $0.id) == false })
    }

    func testNewSearchCancelsPreviousGeneration() throws {
        let store = makeStore()
        let pages = (0..<80).map { _ in "oldterm oldterm newterm" }
        _ = try store.open(
            documentAt: makeSearchableTemporaryPDF(named: "search-cancel", pages: pages)
        )

        store.updateSearch(query: "oldterm", scope: .currentDocument, in: store.defaultWindowID)
        store.updateSearch(query: "newterm", scope: .currentDocument, in: store.defaultWindowID)
        waitForDocumentSearch(in: store)

        let snapshot = store.searchSnapshot(in: store.defaultWindowID)
        XCTAssertEqual(snapshot.query, "newterm")
        XCTAssertEqual(snapshot.totalMatches, 80)
        XCTAssertTrue(snapshot.sections.flatMap(\.matches).allSatisfy { $0.matchedText == "newterm" })
    }

    func testMemoryPressureDiscardsOnlyCleanBackgroundDocuments() throws {
        let store = makeStore()
        let sessions = try store.open(
            documentsAt: (0..<3).map { try makeTemporaryPDF(named: "pressure-\($0)") },
            in: store.defaultWindowID
        )
        for session in sessions {
            _ = try store.pdfDocument(for: session.id)
        }
        store.setDirty(true, for: sessions[0].id)

        store.discardCleanBackgroundDocuments()

        XCTAssertTrue(store.isPDFDocumentLoaded(for: sessions[0].id))
        XCTAssertFalse(store.isPDFDocumentLoaded(for: sessions[1].id))
        XCTAssertTrue(store.isPDFDocumentLoaded(for: sessions[2].id))
    }

    func testRestorePersistedStateDefaultsWindowsBackToSinglePane() throws {
        let firstURL = try makeTemporaryPDF(named: "restore-window-first")
        let secondURL = try makeTemporaryPDF(named: "restore-window-second")
        let windowA = UUID()
        let windowB = UUID()
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [
                .init(url: firstURL),
                .init(url: secondURL),
            ],
            windows: [
                .init(
                    id: windowA,
                    tabPresentationMode: .horizontalTitlebar,
                    isLeftSidebarVisible: false,
                    isRightSidebarVisible: true,
                    rightSidebarMode: .search,
                    searchQuery: "needle",
                    searchScope: .allOpen,
                    splitState: .init(
                        isEnabled: true,
                        primarySessionURL: firstURL,
                        secondarySessionURL: secondURL,
                        focusedPane: .secondary
                    ),
                    recentlyClosedURLs: [secondURL]
                ),
                .init(
                    id: windowB,
                    tabPresentationMode: .verticalSidebar,
                    isLeftSidebarVisible: true,
                    isRightSidebarVisible: false,
                    rightSidebarMode: .pages,
                    searchQuery: "",
                    searchScope: .currentDocument,
                    splitState: .init(
                        isEnabled: false,
                        primarySessionURL: secondURL,
                        secondarySessionURL: nil,
                        focusedPane: .primary
                    ),
                    recentlyClosedURLs: []
                ),
            ]
        )

        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        let secondSessionID = try XCTUnwrap(store.sessions.first(where: { $0.url == secondURL })?.id)

        XCTAssertEqual(Set(store.windowIDs()), [windowA, windowB])
        XCTAssertEqual(store.tabPresentationMode(in: windowA), .horizontalTitlebar)
        XCTAssertEqual(store.rightSidebarMode(in: windowA), .search)
        XCTAssertEqual(store.searchQuery(in: windowA), "needle")
        XCTAssertEqual(store.searchScope(in: windowA), .allOpen)
        XCTAssertFalse(store.isSplitEnabled(in: windowA))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowA), secondSessionID)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowA))
        XCTAssertEqual(store.focusedPane(in: windowA), .primary)
        XCTAssertEqual(store.recentlyClosedURLs(in: windowA), [secondURL])

        XCTAssertEqual(store.tabPresentationMode(in: windowB), .verticalSidebar)
        XCTAssertEqual(store.rightSidebarMode(in: windowB), .pages)
        XCTAssertFalse(store.isSplitEnabled(in: windowB))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowB), secondSessionID)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowB))
    }

    func testRestorePersistedStateAllowsDuplicateURLsWithDistinctSessionIDs() throws {
        let duplicateURL = try makeTemporaryPDF(named: "restore-duplicate-url")
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let windowID = UUID()
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [
                .init(id: firstSessionID, url: duplicateURL),
                .init(id: secondSessionID, url: duplicateURL),
            ],
            windows: [
                .init(
                    id: windowID,
                    tabPresentationMode: .verticalSidebar,
                    isLeftSidebarVisible: true,
                    isRightSidebarVisible: true,
                    rightSidebarMode: .outline,
                    searchQuery: "",
                    searchScope: .currentDocument,
                    splitState: .init(
                        isEnabled: true,
                        primarySessionID: firstSessionID,
                        secondarySessionID: secondSessionID,
                        primarySessionURL: duplicateURL,
                        secondarySessionURL: duplicateURL,
                        focusedPane: .secondary
                    ),
                    recentlyClosedURLs: []
                ),
            ]
        )

        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions.map(\.url), [duplicateURL, duplicateURL])
        XCTAssertFalse(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), secondSessionID)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowID))
    }

    func testRestorePersistedContinuousReadingState() throws {
        let firstURL = try makeTemporaryPDF(named: "restore-continuous-first")
        let secondURL = try makeTemporaryPDF(named: "restore-continuous-second")
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let windowID = UUID()
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [
                .init(id: firstSessionID, url: firstURL),
                .init(id: secondSessionID, url: secondURL),
            ],
            windows: [
                .init(
                    id: windowID,
                    sessionIDs: [firstSessionID, secondSessionID],
                    continuousReadingSessionIDs: [firstSessionID, secondSessionID],
                    tabPresentationMode: .verticalSidebar,
                    isLeftSidebarVisible: true,
                    isRightSidebarVisible: true,
                    rightSidebarMode: .outline,
                    searchQuery: "",
                    searchScope: .currentDocument,
                    splitState: .init(
                        isEnabled: false,
                        primarySessionID: secondSessionID,
                        primarySessionURL: secondURL,
                        secondarySessionURL: nil,
                        focusedPane: .primary
                    ),
                    recentlyClosedURLs: []
                ),
            ]
        )
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertEqual(store.continuousReadingSessionIDs(in: windowID), [firstSessionID, secondSessionID])
        XCTAssertTrue(store.isContinuousReadingEnabled(in: windowID))
    }

    private func makeTemporaryPDF(named name: String, pageCount: Int = 1) throws -> URL {
        try TestPDFFixtures.makeBlankPDF(named: name, pageCount: pageCount)
    }

    private func writeTemporaryPDF(to url: URL, pageCount: Int) throws {
        let document = TestPDFFixtures.makeBlankDocument(pageCount: pageCount)
        XCTAssertTrue(document.write(to: url))
    }

    private func overwriteFileInPlace(at url: URL, withPDFPageCount pageCount: Int) throws {
        let data = try TestPDFFixtures.blankPDFData(pageCount: pageCount)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func waitForMainRunLoop(timeout: TimeInterval = 2, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func testRenameSessionUpdatesFileURLAndMigratesState() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let originalURL = temporaryDirectory.appendingPathComponent("original.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(originalURL as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create PDF context")
            return
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        let readingStateStore = InMemoryReadingStateStore()
        let recentFilesStore = InMemoryRecentFilesStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: recentFilesStore
        )
        let windowID = store.defaultWindowID
        let session = try store.open(documentAt: originalURL, in: windowID)
        let oldURL = session.url
        var notedURLs: [URL] = []
        store.noteRecentDocumentURL = { notedURLs.append($0) }

        readingStateStore.states[oldURL] = PersistedReadingState(
            url: oldURL,
            displayMode: .singlePageContinuous,
            scaleMode: .fitWidth,
            scaleFactor: 1.5,
            readingPosition: .zero
        )
        recentFilesStore.recentFiles = [oldURL]

        store.renameSession("renamed", for: session.id)

        let updatedSession = store.session(for: session.id)
        XCTAssertNotNil(updatedSession)
        XCTAssertEqual(updatedSession?.title, "renamed")
        XCTAssertEqual(updatedSession?.url.lastPathComponent, "renamed.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: updatedSession!.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

        let migratedState = try readingStateStore.loadState(for: updatedSession!.url)
        XCTAssertNotNil(migratedState)
        XCTAssertEqual(migratedState?.scaleFactor, 1.5)

        XCTAssertTrue(recentFilesStore.recentFiles.contains(updatedSession!.url))
        XCTAssertFalse(recentFilesStore.recentFiles.contains(oldURL))
        XCTAssertEqual(notedURLs, [updatedSession!.url])
    }

    private func makeSearchableTemporaryPDF(named name: String, pages: [String]) throws -> URL {
        try TestPDFFixtures.makeSearchablePDF(named: name, pages: pages)
    }
}
