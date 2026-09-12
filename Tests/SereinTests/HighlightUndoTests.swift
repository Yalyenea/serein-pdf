import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class HighlightUndoTests: XCTestCase {
    func testUndoAddRemovesAnnotation() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.pageIndex, 0)
        XCTAssertEqual(records.first?.annotation.type, "Highlight")
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
        let document = try store.pdfDocument(for: session.id)
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
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor)
        XCTAssertFalse(records.isEmpty)

        // noteHighlightsAdded rejects empty records; cap must use real entries.
        for _ in 0..<(DocumentStore.undoStackLimit + 5) {
            store.noteHighlightsAdded(records, for: session.id)
        }

        let updated = try XCTUnwrap(store.session(for: session.id))
        XCTAssertEqual(updated.undoStack.count, DocumentStore.undoStackLimit)
    }

    func testUndoIsIsolatedPerSession() throws {
        let store = makeStore()
        let first = try store.open(documentAt: makeTextFile(text: "alpha"))
        let second = try store.open(documentAt: makeTextFile(text: "beta"))
        let firstDocument = try store.pdfDocument(for: first.id)
        let selection = try XCTUnwrap(firstDocument.findString("alpha", withOptions: []).first)
        let records = HighlightService.applyHighlight(to: selection)
        store.noteHighlightsAdded(records, for: first.id)

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

    func testRedoReappliesUndoneHighlight() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)

        let records = HighlightService.applyHighlight(to: selection)
        store.recordHighlightUndo(.added(records), for: session.id)
        store.setDirty(true, for: session.id)

        XCTAssertTrue(store.undoLastHighlight(for: session.id))
        XCTAssertEqual(annotationCount(in: document), 0)
        XCTAssertFalse(store.hasUndoableHighlight(for: session.id))
        XCTAssertTrue(store.hasRedoableHighlight(for: session.id))

        XCTAssertTrue(store.redoLastHighlight(for: session.id))
        XCTAssertEqual(annotationCount(in: document), 1)
        XCTAssertTrue(store.hasUndoableHighlight(for: session.id))
        XCTAssertFalse(store.hasRedoableHighlight(for: session.id))
    }

    func testRedoReturnsFalseWhenStackEmpty() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha"))

        XCTAssertFalse(store.hasRedoableHighlight(for: session.id))
        XCTAssertFalse(store.redoLastHighlight(for: session.id))
    }

    func testNewHighlightClearsRedoStack() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTextFile(text: "alpha beta"))
        let document = try store.pdfDocument(for: session.id)

        let selection1 = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let records1 = HighlightService.applyHighlight(to: selection1)
        store.recordHighlightUndo(.added(records1), for: session.id)

        let selection2 = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        let records2 = HighlightService.applyHighlight(to: selection2)
        store.recordHighlightUndo(.added(records2), for: session.id)

        XCTAssertTrue(store.undoLastHighlight(for: session.id))
        XCTAssertTrue(store.hasRedoableHighlight(for: session.id))

        let selection3 = try XCTUnwrap(document.findString("alpha beta", withOptions: []).first)
        let records3 = HighlightService.applyHighlight(to: selection3)
        store.recordHighlightUndo(.added(records3), for: session.id)

        XCTAssertFalse(store.hasRedoableHighlight(for: session.id))
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
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
        try TestPDFFixtures.makeSearchablePDF(named: "undo-text", pages: [text])
    }
}
