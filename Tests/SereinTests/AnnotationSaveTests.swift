import AppKit
import PDFKit
import XCTest
@testable import Serein

private final class InMemoryDocumentStorePersistence2: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?
    func loadState() throws -> PersistedDocumentStoreState? { state }
    func saveState(_ state: PersistedDocumentStoreState) throws { self.state = state }
}

private final class InMemoryReadingStateStore2: ReadingStateStore {
    var states: [URL: PersistedReadingState] = [:]
    func loadState(for url: URL) throws -> PersistedReadingState? { states[url] }
    func saveState(_ state: PersistedReadingState) throws { states[state.url] = state }
}

@MainActor
final class AnnotationSaveTests: XCTestCase {
    func testAnnotationSavePolicyDefaultIsAfter10Minutes() {
        XCTAssertEqual(AnnotationSavePolicy.default, .after10Minutes)
        XCTAssertEqual(AnnotationSavePolicy.after10Minutes.autoSaveInterval, 600)
        XCTAssertNil(AnnotationSavePolicy.never.autoSaveInterval)
    }

    func testSetDirtyRecordsDirtySinceTimestamp() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "dirty-timestamp"))
        let now = Date()

        store.setDirty(true, for: session.id, now: now)

        XCTAssertEqual(store.session(for: session.id)?.isDirty, true)
        XCTAssertEqual(store.session(for: session.id)?.dirtySince, now)
    }

    func testAutoSaveSkipsSessionWhenIntervalHasNotElapsed() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "autosave-not-elapsed"))
        try addHighlightAnnotation(to: session, in: store)
        let dirtyAt = Date()
        store.setDirty(true, for: session.id, now: dirtyAt)

        let errors = store.autoSaveDirtySessions(now: dirtyAt.addingTimeInterval(60))

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(store.session(for: session.id)?.isDirty, true)
    }

    func testAutoSaveWritesWhenIntervalElapsed() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "autosave-elapsed"))
        try addHighlightAnnotation(to: session, in: store)
        let dirtyAt = Date()
        store.setDirty(true, for: session.id, now: dirtyAt)

        let errors = store.autoSaveDirtySessions(now: dirtyAt.addingTimeInterval(601))

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(store.session(for: session.id)?.isDirty, false)
        XCTAssertNil(store.session(for: session.id)?.dirtySince)
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count, 1)
    }

    func testAutoSaveNeverPolicyDoesNotWrite() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "autosave-never"))
        try addHighlightAnnotation(to: session, in: store)
        store.setAnnotationSavePolicy(.never, for: session.id)
        store.setDirty(true, for: session.id)

        let errors = store.autoSaveDirtySessions(now: Date().addingTimeInterval(3_600))

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(store.session(for: session.id)?.isDirty, true)
    }

    func testManualSaveClearsDirtyAndPersistsAnnotations() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "manual-save"))
        try addHighlightAnnotation(to: session, in: store)
        store.setDirty(true, for: session.id)

        try store.saveAnnotations(for: session.id)

        XCTAssertEqual(store.session(for: session.id)?.isDirty, false)
        XCTAssertNil(store.session(for: session.id)?.dirtySince)
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count, 1)
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(
            persistence: InMemoryDocumentStorePersistence2(),
            readingStateStore: InMemoryReadingStateStore2()
        )
    }

    private func addHighlightAnnotation(to session: DocumentSession, in store: DocumentStore) throws {
        let annotation = PDFAnnotation(
            bounds: NSRect(x: 10, y: 10, width: 60, height: 16),
            forType: .highlight,
            withProperties: nil
        )
        annotation.color = HighlightColor.pink.nsColor
        try store.pdfDocument(for: session.id).page(at: 0)?.addAnnotation(annotation)
    }

    private func makeTemporaryPDF(named name: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let url = temporaryDirectory.appendingPathComponent("\(name).pdf")

        let image = NSImage(size: NSSize(width: 200, height: 260))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
        image.unlockFocus()

        let document = PDFDocument()
        if let page = PDFPage(image: image) {
            document.insert(page, at: 0)
        }
        XCTAssertTrue(document.write(to: url))
        return url
    }
}
