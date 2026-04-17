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

private final class InMemoryReadingStateStore: ReadingStateStore {
    var states: [URL: PersistedReadingState] = [:]

    func loadState(for url: URL) throws -> PersistedReadingState? {
        states[url]
    }

    func saveState(_ state: PersistedReadingState) throws {
        states[state.url] = state
    }
}

private final class InMemoryRecentFilesStore: RecentFilesStore {
    var recentFiles: [URL] = []

    func loadRecentFiles() throws -> [URL] {
        recentFiles
    }

    func recordOpen(for url: URL) throws -> [URL] {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        return recentFiles
    }
}

@MainActor
final class DocumentStoreTests: XCTestCase {
    func testOpenDocumentCreatesActiveSession() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let url = try makeTemporaryPDF(named: "single")

        let session = try store.open(documentAt: url)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessionID, session.id)
        XCTAssertEqual(store.activeSession?.title, "single")
    }

    func testOpenMultipleDocumentsKeepsAllSessionsAndActivatesLast() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.close(sessionID: second.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testCloseActiveSessionConvenienceUsesCurrentSelection() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "close-active-alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "close-active-beta"))

        XCTAssertEqual(store.activeSessionID, second.id)
        store.closeActiveSession()

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testActivateSessionSwitchesActiveDocument() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.activate(sessionID: first.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.activeSession?.url, first.url)
    }

    func testActivatePreviousSessionWrapsAround() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        store.updateCurrentPage(index: 3, for: first.id)

        XCTAssertEqual(store.session(for: first.id)?.currentPageIndex, 3)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition.pageIndex, 3)
        XCTAssertEqual(store.session(for: second.id)?.currentPageIndex, 0)
    }

    func testDefaultTabPresentationModeIsVerticalSidebar() {
        XCTAssertEqual(
            DocumentStore(
                persistence: InMemoryDocumentStorePersistence(),
                readingStateStore: InMemoryReadingStateStore(),
                recentFilesStore: InMemoryRecentFilesStore()
            ).tabPresentationMode,
            .verticalSidebar
        )
    }

    func testSetTabPresentationModeUpdatesStore() {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        store.setTabPresentationMode(.horizontalTitlebar)

        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
    }

    func testCloseUnknownSessionDoesNotCrashOrMutateMode() {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let unknownSessionID = UUID()

        store.close(sessionID: unknownSessionID)

        XCTAssertNil(store.activeSession)
        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
    }

    func testSetTabPresentationModeAdjustsLeftSidebarVisibility() {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

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
        let store = DocumentStore(
            persistence: persistence,
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )

        try store.restorePersistedState()

        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
        XCTAssertTrue(store.isLeftSidebarVisible)
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
                shortcuts: .default
            )
        )

        let session = try store.open(documentAt: url)

        XCTAssertEqual(session.displayMode, .twoUpContinuous)
        XCTAssertEqual(session.scaleMode, .manual)
        XCTAssertEqual(session.zoomScale, 1.75)
        XCTAssertEqual(session.lastReadPosition, ReadingPosition(pageIndex: 2, point: CGPoint(x: 14, y: 28)))
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
                shortcuts: .default
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

    func testOpenDocumentUsesConfiguredDefaultsWhenNoPersistedReadingStateExists() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .twoUp, fitWidthOnOpen: false),
                annotations: .default,
                shortcuts: .default
            )
        )

        let session = try store.open(documentAt: makeTemporaryPDF(named: "config-defaults"))

        XCTAssertEqual(session.displayMode, .twoUp)
        XCTAssertEqual(session.scaleMode, .manual)
    }

    func testUpdateReadingPositionPersistsScaleAndPoint() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "reading-state"))

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

    func testReadingStateRemainsIndependentAcrossSessions() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "first-reading-state"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "second-reading-state"))

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

    func testSaveAnnotationsWritesPDFAndClearsDirtyState() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore()
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "save-annotations"))
        let annotation = PDFAnnotation(
            bounds: NSRect(x: 20, y: 20, width: 60, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        annotation.color = .systemPink

        store.session(for: session.id)?.pdfDocument.page(at: 0)?.addAnnotation(annotation)
        store.setDirty(true, for: session.id)
        try store.saveAnnotations(for: session.id)

        XCTAssertFalse(store.session(for: session.id)?.isDirty ?? true)

        let reopenedDocument = PDFDocument(url: session.url)
        XCTAssertEqual(reopenedDocument?.page(at: 0)?.annotations.count, 1)
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
