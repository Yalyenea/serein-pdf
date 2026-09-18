import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class DocumentLifecycleTests: XCTestCase {
    func testRestoredSameURLSessionsKeepComparisonBoundToItsSource() throws {
        let url = try fixture("restored-same-url")
        let firstID = UUID()
        let secondID = UUID()
        let windowID = UUID()
        let persistence = TestInMemoryDocumentStorePersistence()
        persistence.state = PersistedDocumentStoreState(
            sessions: [.init(id: firstID, url: url), .init(id: secondID, url: url)],
            windows: [.init(
                id: windowID,
                sessionIDs: [firstID, secondID],
                tabPresentationMode: .verticalSidebar,
                isLeftSidebarVisible: true,
                isRightSidebarVisible: true,
                rightSidebarMode: .outline,
                searchQuery: "",
                searchScope: .currentDocument,
                splitState: .init(
                    isEnabled: false,
                    primarySessionID: firstID,
                    primarySessionURL: url,
                    secondarySessionURL: nil,
                    focusedPane: .primary
                ),
                recentlyClosedURLs: []
            )]
        )
        let store = makeIsolatedDocumentStore(persistence: persistence)
        try store.restorePersistedState()
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [firstID, secondID])

        let firstComparisonID = try compare(firstID, in: store, windowID: windowID)
        store.activate(sessionID: secondID, in: windowID, targetPane: .primary)
        store.activate(sessionID: secondID, in: windowID, targetPane: .secondary)
        let secondComparisonID = try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
        XCTAssertNotEqual(secondComparisonID, firstComparisonID)
        let secondDocument = try store.pdfDocument(for: secondID)
        XCTAssertTrue(try store.pdfDocument(for: secondComparisonID) === secondDocument)
        XCTAssertFalse(try store.pdfDocument(for: firstID) === secondDocument)

        try addHighlight(to: secondComparisonID, in: store)
        XCTAssertTrue(store.session(for: secondID)?.isDirty == true)
        XCTAssertFalse(store.session(for: firstID)?.isDirty ?? true)
        XCTAssertTrue(store.annotationGroups(for: firstID).isEmpty)
        XCTAssertEqual(store.annotationGroups(for: secondID).count, 1)
        XCTAssertFalse(store.undoLastHighlight(for: firstID))
        XCTAssertTrue(store.undoLastHighlight(for: secondID))
        XCTAssertTrue(secondDocument.page(at: 0)?.annotations.isEmpty == true)

        store.close(sessionID: firstID, from: windowID)
        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), secondComparisonID)
        XCTAssertTrue(try store.pdfDocument(for: secondComparisonID) === secondDocument)
    }

    func testComparisonSharesAnnotationsAndUndoButKeepsIndependentReadingPosition() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("comparison", pageCount: 3))
        let comparisonID = try compare(source.id, in: store)
        let document = try store.pdfDocument(for: source.id)
        XCTAssertTrue(try store.pdfDocument(for: comparisonID) === document)

        store.updateCurrentPage(index: 2, for: comparisonID)
        XCTAssertEqual(store.session(for: source.id)?.currentPageIndex, 0)
        XCTAssertEqual(store.session(for: comparisonID)?.currentPageIndex, 2)
        try addHighlight(to: comparisonID, in: store)
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        XCTAssertTrue(store.session(for: comparisonID)?.isDirty == true)
        XCTAssertEqual(store.annotationGroups(for: source.id).count, 1)
        XCTAssertEqual(store.annotationSections(in: store.defaultWindowID).count, 1)
        XCTAssertTrue(store.undoLastHighlight(for: source.id))
        XCTAssertTrue(document.page(at: 0)?.annotations.isEmpty == true)
        XCTAssertTrue(store.redoLastHighlight(for: comparisonID))
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 1)

        try store.saveAnnotations(for: comparisonID)
        XCTAssertFalse(store.session(for: source.id)?.isDirty ?? true)
        XCTAssertFalse(store.session(for: comparisonID)?.isDirty ?? true)
        XCTAssertEqual(PDFDocument(url: source.url)?.page(at: 0)?.annotations.count, 1)
        store.refreshExternallyChangedFile(at: source.url)
        XCTAssertTrue(store.loadedPDFDocument(for: source.id) === document)
        XCTAssertTrue(store.hasUndoableHighlight(for: comparisonID))
    }

    func testComparisonAutoSaveDoesNotTriggerExternalReload() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("comparison-autosave"))
        let comparisonID = try compare(source.id, in: store)
        try addHighlight(to: comparisonID, in: store)
        let document = try store.pdfDocument(for: comparisonID)
        XCTAssertTrue(store.autoSaveDirtySessions(now: Date(timeIntervalSinceReferenceDate: 1_000)).isEmpty)

        store.refreshExternallyChangedFile(at: source.url)
        XCTAssertTrue(store.loadedPDFDocument(for: source.id) === document)
        XCTAssertTrue(store.hasUndoableHighlight(for: comparisonID))
        XCTAssertFalse(store.session(for: comparisonID)?.isDirty ?? true)
    }

    func testClosingComparisonKeepsUnsavedChangesAndOneAutoSaveJob() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("comparison-close"))
        let comparisonID = try compare(source.id, in: store)
        try addHighlight(to: comparisonID, in: store)
        let jobs = store.prepareAutoSaveJobs(now: Date(timeIntervalSinceReferenceDate: 1_000)).jobs
        XCTAssertEqual(jobs.map(\.sessionID), [source.id])

        store.setSplitEnabled(false, in: store.defaultWindowID)
        XCTAssertNil(store.session(for: comparisonID))
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        XCTAssertEqual(store.annotationGroups(for: source.id).count, 1)
        try store.saveAnnotations(for: source.id)
        XCTAssertEqual(PDFDocument(url: source.url)?.page(at: 0)?.annotations.count, 1)
    }

    func testClosingSourceAlsoClosesItsComparison() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("source-close"))
        _ = try compare(source.id, in: store)
        store.close(sessionID: source.id)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.activeSession)
        XCTAssertFalse(store.isSplitEnabled(in: store.defaultWindowID))
    }

    func testMovingSourceReleasesComparisonInPrimaryPane() throws {
        let store = makeIsolatedDocumentStore()
        let sourceWindowID = store.defaultWindowID
        let source = try store.open(documentAt: fixture("move-primary"))
        let other = try store.open(documentAt: fixture("remaining"))
        store.activate(sessionID: source.id, in: sourceWindowID, targetPane: .secondary)
        store.activate(sessionID: source.id, in: sourceWindowID, targetPane: .primary)
        let comparisonID = try XCTUnwrap(store.displayedSessionID(for: .primary, in: sourceWindowID))
        XCTAssertNotEqual(comparisonID, source.id)
        try addHighlight(to: comparisonID, in: store)

        let destinationID = try XCTUnwrap(store.moveActiveSessionToNewWindow(from: sourceWindowID))
        XCTAssertNil(store.session(for: comparisonID))
        XCTAssertEqual(store.activeSessionID(in: sourceWindowID), other.id)
        XCTAssertEqual(store.activeSessionID(in: destinationID), source.id)
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        XCTAssertEqual(store.annotationGroups(for: source.id).count, 1)
    }

    func testMergeReleasesComparisonAndRetainsItsUnsavedAnnotations() throws {
        let store = makeIsolatedDocumentStore()
        let targetWindowID = store.defaultWindowID
        let sourceWindowID = store.createWindow()
        let source = try store.open(documentAt: fixture("merge-comparison"), in: sourceWindowID)
        let comparisonID = try compare(source.id, in: store, windowID: sourceWindowID)
        try addHighlight(to: comparisonID, in: store)

        store.mergeAllWindows(into: targetWindowID)
        XCTAssertEqual(store.sessions.map(\.id), [source.id])
        XCTAssertNil(store.session(for: comparisonID))
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        XCTAssertEqual(store.annotationGroups(for: source.id).count, 1)
    }

    func testEvictionReleasesUndoRecordsForOldDocumentInstances() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("eviction"))
        try addHighlight(to: source.id, in: store)
        try store.saveAnnotations(for: source.id)
        XCTAssertTrue(store.hasUndoableHighlight(for: source.id))
        for index in 0..<5 {
            let other = try store.open(documentAt: fixture("other-\(index)"))
            _ = try store.pdfDocument(for: other.id)
        }
        XCTAssertFalse(store.isPDFDocumentLoaded(for: source.id))
        XCTAssertFalse(store.hasUndoableHighlight(for: source.id))
        XCTAssertFalse(store.undoLastHighlight(for: source.id))
        XCTAssertEqual(try store.pdfDocument(for: source.id).page(at: 0)?.annotations.count, 1)
    }

    func testMemoryPressureReleasesRedoRecordsForOldDocumentInstances() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("pressure"))
        try addHighlight(to: source.id, in: store)
        XCTAssertTrue(store.undoLastHighlight(for: source.id))
        try store.saveAnnotations(for: source.id)
        _ = try store.open(documentAt: fixture("foreground"))
        store.discardCleanBackgroundDocuments()
        XCTAssertFalse(store.isPDFDocumentLoaded(for: source.id))
        XCTAssertFalse(store.hasRedoableHighlight(for: source.id))
    }

    func testRenameUpdatesComparisonAndRejectsStaleAutoSave() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("before-rename"))
        let comparisonID = try compare(source.id, in: store)
        try addHighlight(to: comparisonID, in: store)
        let jobs = store.prepareAutoSaveJobs(now: Date(timeIntervalSinceReferenceDate: 1_000)).jobs
        let results = DocumentStore.performAutoSaveJobs(jobs)
        store.renameSession("after-rename", for: source.id)
        let renamed = try XCTUnwrap(store.session(for: source.id))
        XCTAssertEqual(store.session(for: comparisonID)?.url, renamed.url)
        XCTAssertEqual(store.session(for: comparisonID)?.title, "after-rename")

        // Another file may occupy the old path while background staging finishes.
        let replacement = Data("unrelated replacement".utf8)
        try replacement.write(to: source.url)
        XCTAssertTrue(store.completeAutoSave(results).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source.url), replacement)
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        for result in results {
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(result.stagedURL).path))
        }
        try store.saveAnnotations(for: comparisonID)
        XCTAssertEqual(PDFDocument(url: renamed.url)?.page(at: 0)?.annotations.count, 1)
    }

    func testFailedRenamePreservesOriginalTitleAndURL() throws {
        let store = makeIsolatedDocumentStore()
        let source = try store.open(documentAt: fixture("original"))
        let occupiedURL = source.url.deletingLastPathComponent().appendingPathComponent("occupied.pdf")
        try Data("existing file".utf8).write(to: occupiedURL)
        store.renameSession("occupied", for: source.id)
        XCTAssertEqual(store.session(for: source.id)?.url, source.url)
        XCTAssertEqual(store.session(for: source.id)?.title, source.title)
    }

    private func compare(_ sessionID: UUID, in store: DocumentStore, windowID: UUID? = nil) throws -> UUID {
        let windowID = windowID ?? store.defaultWindowID
        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: sessionID, in: windowID, targetPane: .secondary)
        return try XCTUnwrap(store.displayedSessionID(for: .secondary, in: windowID))
    }

    private func addHighlight(to sessionID: UUID, in store: DocumentStore) throws {
        let page = try XCTUnwrap(store.pdfDocument(for: sessionID).page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 60, height: 16), forType: .highlight, withProperties: nil)
        annotation.userName = UUID().uuidString
        page.addAnnotation(annotation)
        store.noteHighlightsAdded([HighlightAnnotationRecord(pageIndex: 0, annotation: annotation)], for: sessionID, now: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func fixture(_ name: String, pageCount: Int = 1) throws -> URL {
        let url = try TestPDFFixtures.makeBlankPDF(named: name, pageCount: pageCount)
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return url
    }
}
