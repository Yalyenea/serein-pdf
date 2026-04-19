import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

private final class InMemoryDocumentStorePersistenceUndo: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?
    func loadState() throws -> PersistedDocumentStoreState? { state }
    func saveState(_ state: PersistedDocumentStoreState) throws { self.state = state }
}

private final class InMemoryReadingStateStoreUndo: ReadingStateStore {
    var states: [URL: PersistedReadingState] = [:]
    func loadState(for url: URL) throws -> PersistedReadingState? { states[url] }
    func saveState(_ state: PersistedReadingState) throws { states[state.url] = state }
}

private final class InMemoryRecentFilesStoreUndo: RecentFilesStore {
    var recentFiles: [URL] = []
    func loadRecentFiles() throws -> [URL] { recentFiles }
    func recordOpen(for url: URL) throws -> [URL] {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        return recentFiles
    }
}

@MainActor
final class HighlightUndoTests: XCTestCase {
    func testApplyHighlightReturnsRecordForEveryLine() throws {
        let document = try makeTextPDF(text: "alpha beta")
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.pageIndex, 0)
        XCTAssertEqual(records.first?.annotation.type, "Highlight")
    }

    func testUndoAddRemovesAnnotation() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))
        let document = session.pdfDocument
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection)
        store.recordHighlightUndo(.added(records), for: session.id)
        store.setDirty(true, for: session.id)

        XCTAssertTrue(store.hasUndoableHighlight(for: session.id))
        XCTAssertEqual(annotationCount(in: document), 1)

        XCTAssertTrue(store.undoLastHighlight(for: session.id))
        XCTAssertEqual(annotationCount(in: document), 0)
        XCTAssertFalse(store.hasUndoableHighlight(for: session.id))
        XCTAssertTrue(store.activeSession?.isDirty == true)
    }

    func testUndoRemoveRestoresGroup() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha beta gamma"))
        let document = session.pdfDocument
        let selection = try XCTUnwrap(document.findString("alpha beta gamma", withOptions: []).first)

        let added = HighlightService.applyHighlight(to: selection)
        XCTAssertGreaterThanOrEqual(added.count, 1)

        let page = try XCTUnwrap(document.page(at: 0))
        let target = try XCTUnwrap(page.annotations.first { $0.type == "Highlight" })

        let removed = HighlightService.removeHighlightGroup(containing: target, in: document)
        store.recordHighlightUndo(.removed(removed), for: session.id)
        store.setDirty(true, for: session.id)
        XCTAssertEqual(annotationCount(in: document), 0)

        XCTAssertTrue(store.undoLastHighlight(for: session.id))
        XCTAssertEqual(annotationCount(in: document), removed.count)
        XCTAssertTrue(store.activeSession?.isDirty == true)
    }

    func testUndoStackCapsAtFifty() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))

        for _ in 0..<(DocumentStore.undoStackLimit + 5) {
            store.recordHighlightUndo(.added([]), for: session.id)
        }

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.undoStack.count, DocumentStore.undoStackLimit)
    }

    func testUndoIsIsolatedPerSession() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTextFile(text: "alpha"))
        let second = try store.open(documentAt: makeTextFile(text: "beta"))

        store.recordHighlightUndo(.added([]), for: first.id)

        XCTAssertTrue(store.hasUndoableHighlight(for: first.id))
        XCTAssertFalse(store.hasUndoableHighlight(for: second.id))

        XCTAssertTrue(store.undoLastHighlight(for: first.id))
        XCTAssertFalse(store.undoLastHighlight(for: second.id))
    }

    func testUndoReturnsFalseWhenStackEmpty() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))

        XCTAssertFalse(store.hasUndoableHighlight(for: session.id))
        XCTAssertFalse(store.undoLastHighlight(for: session.id))
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(
            persistence: InMemoryDocumentStorePersistenceUndo(),
            readingStateStore: InMemoryReadingStateStoreUndo(),
            recentFilesStore: InMemoryRecentFilesStoreUndo()
        )
    }

    private func annotationCount(in document: PDFDocument) -> Int {
        var count = 0
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            count += page.annotations.filter { $0.type == "Highlight" }.count
        }
        return count
    }

    private func makeTextFile(text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("undo-text.pdf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        writeTextPDF(text: text, to: url)
        return url
    }

    private func makeTextPDF(text: String) throws -> PDFDocument {
        let url = try makeTextFile(text: text)
        return try XCTUnwrap(PDFDocument(url: url))
    }

    private func writeTextPDF(text: String, to url: URL) {
        var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 220)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create PDF context")
            return
        }

        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.white.setFill()
        NSBezierPath(rect: mediaBox).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        NSString(string: text).draw(at: NSPoint(x: 48, y: 112), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        data.write(to: url, atomically: true)
    }
}
