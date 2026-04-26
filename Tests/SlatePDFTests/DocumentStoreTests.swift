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

private final class NotificationCounterObserver: NSObject {
    private(set) var count = 0

    @objc
    func handleDocumentStoreDidChange(_ notification: Notification) {
        count += 1
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

    func testCloseSessionPushesURLOntoRecentlyClosedStack() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
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

    func testConfiguredLayoutWidthsOverrideRestoredSidebarWidths() throws {
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

        XCTAssertEqual(session.leftSidebarWidth, 320)
        XCTAssertEqual(session.rightSidebarWidth, 320)
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

    func testUpdateReadingPositionSamePagePointDoesNotNotifyGlobalObservers() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore
        )
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

    func testAnnotationSectionsExposeSnippetColorAndPageGrouping() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore()
        )
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-sections",
            pages: ["alpha beta gamma", "delta epsilon"]
        )
        let session = try store.open(documentAt: url)
        let selection = try XCTUnwrap(session.pdfDocument.findString("beta", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.yellow.nsColor)
        store.noteHighlightsAdded(records, for: session.id)

        let sections = store.annotationSections(in: store.defaultWindowID)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Page 1")
        XCTAssertEqual(sections.first?.highlights.count, 1)
        XCTAssertEqual(sections.first?.highlights.first?.color, .yellow)
        XCTAssertTrue(sections.first?.highlights.first?.snippet.contains("beta") == true)
    }

    func testUpdateCommentPersistsAcrossHighlightGroupAndMarksSessionDirty() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore()
        )
        let url = try makeSearchableTemporaryPDF(
            named: "annotation-comment",
            pages: ["alpha beta gamma"]
        )
        let session = try store.open(documentAt: url)
        let selection = try XCTUnwrap(session.pdfDocument.findString("alpha", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor)
        store.noteHighlightsAdded(records, for: session.id)

        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        XCTAssertTrue(store.updateComment("Important note", forHighlightGroup: group.groupID, in: session.id))

        let updatedGroup = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        XCTAssertEqual(updatedGroup.comment, "Important note")
        XCTAssertTrue(store.session(for: session.id)?.isDirty == true)
        XCTAssertEqual(
            session.pdfDocument.page(at: 0)?.annotations.first(where: { $0.type == "Highlight" })?.contents,
            "Important note"
        )
    }

    func testUpdateAppConfigurationAppliesNewDefaultsToFutureSessions() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore()
        )
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

    func testUpdateAppConfigurationAppliesLayoutWidthsToExistingSessions() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore()
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "settings-layout-widths"))
        store.updateSidebarWidths(left: 180, right: 260, for: session.id)

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

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.leftSidebarWidth, 310)
        XCTAssertEqual(updated.rightSidebarWidth, 410)
    }

    func testUpdateAppConfigurationDisablingFitWidthFlipsExistingSessionsToManual() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            appConfiguration: AppConfiguration(
                reader: .init(defaultDisplayMode: .singlePageContinuous, fitWidthOnOpen: true),
                annotations: .default,
                shortcuts: .default,
                layout: .default
            )
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "zoom-pins-manual"))
        XCTAssertEqual(session.scaleMode, .fitWidth)

        // User zoom gesture: handlePDFViewScaleChanged calls setScaleMode(.manual, ...).
        store.setScaleMode(.manual, scaleFactor: 2.3, for: session.id)

        // Page turn fires updateReadingPosition, which must not resurrect fitWidth.
        store.updateReadingPosition(
            ReadingPosition(pageIndex: 2, point: .zero),
            scaleFactor: 2.3,
            for: session.id
        )

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.scaleMode, .manual)
        XCTAssertEqual(updated.zoomScale, 2.3)
        XCTAssertEqual(readingStateStore.states[session.url]?.scaleMode, .manual)
    }

    func testUpdateAppConfigurationSwapsPerSessionWidthsAndVisibilities() throws {
        let readingStateStore = InMemoryReadingStateStore()
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: readingStateStore,
            recentFilesStore: InMemoryRecentFilesStore()
        )

        let session = try store.open(documentAt: makeTemporaryPDF(named: "swap-widths"))
        store.updateSidebarWidths(left: 40, right: 320, for: session.id)
        store.setLeftSidebarVisible(true)
        store.setRightSidebarVisible(false)

        var swappedConfig = store.appConfiguration
        swappedConfig.layout.sidebarsSwapped = true
        store.updateAppConfiguration(swappedConfig)

        let swapped = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(swapped.leftSidebarWidth, 320)
        XCTAssertEqual(swapped.rightSidebarWidth, 40)
        XCTAssertFalse(store.isLeftSidebarVisible)
        XCTAssertTrue(store.isRightSidebarVisible)

        var unswappedConfig = store.appConfiguration
        unswappedConfig.layout.sidebarsSwapped = false
        store.updateAppConfiguration(unswappedConfig)

        let restored = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(restored.leftSidebarWidth, 40)
        XCTAssertEqual(restored.rightSidebarWidth, 320)
        XCTAssertTrue(store.isLeftSidebarVisible)
        XCTAssertFalse(store.isRightSidebarVisible)
    }

    func testSplitWorkspaceRoutesActiveSessionByFocusedPane() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-second"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)

        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), second.id)
        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), first.id)
        XCTAssertEqual(store.activeSessionID(in: windowID), second.id)

        store.setFocusedPane(.secondary, in: windowID)
        XCTAssertEqual(store.activeSessionID(in: windowID), first.id)

        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)
        let duplicatedSecondID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(duplicatedSecondID, second.id)
        XCTAssertEqual(store.session(for: duplicatedSecondID)?.url, second.url)
        XCTAssertEqual(store.activeSessionID(in: windowID), duplicatedSecondID)
    }

    func testSplitWithSingleSessionCreatesIndependentComparisonSession() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-single-duplicate"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)

        let primaryID = try XCTUnwrap(store.displayedSessionID(for: .primary, in: windowID))
        let secondaryID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(primaryID, secondaryID)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.session(for: primaryID)?.url, session.url)
        XCTAssertEqual(store.session(for: secondaryID)?.url, session.url)

        store.setScaleMode(.manual, scaleFactor: 2.0, for: primaryID)
        XCTAssertEqual(store.session(for: primaryID)?.zoomScale, 2.0)
        XCTAssertEqual(store.session(for: secondaryID)?.zoomScale, session.zoomScale)
    }

    func testActivatingSameSessionIntoOtherPaneReusesExistingComparisonSession() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-reuse-duplicate"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)
        let primaryID = try XCTUnwrap(store.displayedSessionID(for: .primary, in: windowID))
        let initialSecondaryID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))

        store.activate(sessionID: primaryID, in: windowID, targetPane: .secondary)

        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), initialSecondaryID)
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testDisablingSplitRemovesAutoCreatedComparisonSession() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-disable-cleans-clone"))
        let windowID = store.defaultWindowID

        store.setSplitEnabled(true, in: windowID)
        XCTAssertEqual(store.sessions.count, 2)

        store.setSplitEnabled(false, in: windowID)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, session.id)
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), session.id)
        XCTAssertNil(store.displayedSessionID(for: .secondary, in: windowID))
    }

    func testCreateWindowStartsEmptyButKeepsIndependentUIState() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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

    func testAllOpenSearchBuildsSectionsAcrossSessions() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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

        let sections = store.searchSections(in: store.defaultWindowID)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 3)
        XCTAssertEqual(Set(sections.map(\.title)), ["alpha-search", "beta-search"])
        XCTAssertTrue(sections.allSatisfy { $0.matches.isEmpty == false })
    }

    func testClearSearchResetsCachesAndSidebarMode() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
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
        XCTAssertEqual(store.rightSidebarMode(in: store.defaultWindowID), .search)
        XCTAssertTrue(store.sessions.contains { $0.searchCache.matches.isEmpty == false })

        store.clearSearch(in: store.defaultWindowID)

        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "")
        XCTAssertEqual(store.rightSidebarMode(in: store.defaultWindowID), .outline)
        XCTAssertTrue(store.sessions.allSatisfy { $0.searchCache.query.isEmpty && $0.searchCache.matches.isEmpty })
    }

    func testCurrentDocumentSearchOnTwoHundredPagesStaysUnderHalfSecond() throws {
        let store = DocumentStore(
            persistence: InMemoryDocumentStorePersistence(),
            readingStateStore: InMemoryReadingStateStore(),
            recentFilesStore: InMemoryRecentFilesStore()
        )
        let pages = (0..<220).map { index in
            "performance needle page \(index) repeated needle"
        }
        let url = try makeSearchableTemporaryPDF(named: "search-perf", pages: pages)
        _ = try store.open(documentAt: url)

        let start = CFAbsoluteTimeGetCurrent()
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 440)
        XCTAssertLessThan(duration, 0.5, "search took \(duration)s")
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

    private func makeSearchableTemporaryPDF(named name: String, pages: [String]) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let url = temporaryDirectory.appendingPathComponent("\(name).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create PDF context")
            throw CocoaError(.fileWriteUnknown)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]

        for pageText in pages {
            context.beginPDFPage(nil)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            NSColor.white.setFill()
            NSBezierPath(rect: mediaBox).fill()
            NSString(string: pageText).draw(
                in: NSRect(x: 72, y: 520, width: 468, height: 160),
                withAttributes: attributes
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        guard let document = PDFDocument(url: url), document.pageCount == pages.count else {
            XCTFail("Failed to read generated searchable PDF")
            throw CocoaError(.fileReadCorruptFile)
        }
        return url
    }
}
