import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

private final class InMemoryDocumentStorePersistence: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?

    func loadState() throws -> PersistedDocumentStoreState? {
        state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        self.state = state
    }
}

@MainActor
final class DocumentStoreTests: XCTestCase {
    func testOpenDocumentCreatesActiveSession() throws {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
        let url = try makeTemporaryPDF(named: "single")

        let session = try store.open(documentAt: url)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessionID, session.id)
        XCTAssertEqual(store.activeSession?.title, "single")
    }

    func testOpenMultipleDocumentsKeepsAllSessionsAndActivatesLast() throws {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
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

    func testCloseActiveSessionFallsBackToPreviousSession() throws {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.close(sessionID: second.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testActivateSessionSwitchesActiveDocument() throws {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.activate(sessionID: first.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.activeSession?.url, first.url)
    }

    func testUpdateCurrentPageMutatesOnlyTargetSession() throws {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        store.updateCurrentPage(index: 3, for: first.id)

        XCTAssertEqual(store.session(for: first.id)?.currentPageIndex, 3)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition.pageIndex, 3)
        XCTAssertEqual(store.session(for: second.id)?.currentPageIndex, 0)
    }

    func testDefaultTabPresentationModeIsVerticalSidebar() {
        XCTAssertEqual(
            DocumentStore(persistence: InMemoryDocumentStorePersistence()).tabPresentationMode,
            .verticalSidebar
        )
    }

    func testSetTabPresentationModeUpdatesStore() {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())

        store.setTabPresentationMode(.horizontalTitlebar)

        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
    }

    func testCloseUnknownSessionDoesNotCrashOrMutateMode() {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())
        let unknownSessionID = UUID()

        store.close(sessionID: unknownSessionID)

        XCTAssertNil(store.activeSession)
        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
    }

    func testSetTabPresentationModeAdjustsLeftSidebarVisibility() {
        let store = DocumentStore(persistence: InMemoryDocumentStorePersistence())

        store.setTabPresentationMode(.horizontalTitlebar)
        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
        XCTAssertFalse(store.isLeftSidebarVisible)

        store.setTabPresentationMode(.verticalSidebar)
        XCTAssertTrue(store.isLeftSidebarVisible)
    }

    func testSidebarVisibilityUpdatesPersistedState() {
        let persistence = InMemoryDocumentStorePersistence()
        let store = DocumentStore(persistence: persistence)

        store.setLeftSidebarVisible(false)
        store.setRightSidebarVisible(false)

        XCTAssertEqual(persistence.state?.isLeftSidebarVisible, false)
        XCTAssertEqual(persistence.state?.isRightSidebarVisible, false)
    }

    func testRestorePersistedStateReopensSessionsAndMode() throws {
        let firstURL = try makeTemporaryPDF(named: "restore-first")
        let secondURL = try makeTemporaryPDF(named: "restore-second")
        let persistence = InMemoryDocumentStorePersistence()
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
        let store = DocumentStore(persistence: persistence)

        try store.restorePersistedState()

        XCTAssertEqual(store.sessions.map(\.url), [firstURL, secondURL])
        XCTAssertEqual(store.activeSession?.url, firstURL)
        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
        XCTAssertFalse(store.isLeftSidebarVisible)
        XCTAssertTrue(store.isRightSidebarVisible)
    }

    func testRestorePersistedVerticalModeForcesLeftSidebarVisible() throws {
        let url = try makeTemporaryPDF(named: "restore-vertical")
        let persistence = InMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [.init(url: url)],
            activeSessionURL: url,
            tabPresentationMode: .verticalSidebar,
            isLeftSidebarVisible: false,
            isRightSidebarVisible: true
        )
        let store = DocumentStore(persistence: persistence)

        try store.restorePersistedState()

        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
        XCTAssertTrue(store.isLeftSidebarVisible)
    }

    private func makeTemporaryPDF(named name: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let url = temporaryDirectory.appendingPathComponent("\(name).pdf")
        let image = NSImage(size: NSSize(width: 200, height: 260))

        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
        image.unlockFocus()

        let document = PDFDocument()
        let page = PDFPage(image: image)
        document.insert(page!, at: 0)

        XCTAssertTrue(document.write(to: url))
        return url
    }
}
