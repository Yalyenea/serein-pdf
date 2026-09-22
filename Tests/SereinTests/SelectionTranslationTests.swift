import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class SelectionTranslationTests: XCTestCase {
    func testTranslationKeepsOriginalSelectionAfterChangingPageAndDocument() async throws {
        let store = makeIsolatedDocumentStore()
        let first = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "translation-source", pages: ["Translate this passage", "Next page"]
        ))
        let document = try store.pdfDocument(for: first.id)
        let original = try XCTUnwrap(document.findString("Translate this passage", withOptions: []).first)
        let translation = try SelectionTranslation(selection: original, sessionID: first.id, documentStore: store)

        await translation.translate(translation.request) { text, target in
            XCTAssertEqual(text, "Translate this passage")
            XCTAssertEqual(target.languageCode?.identifier, "zh")
            // The reader's live selection may change while the translation is in flight.
            original.add(try XCTUnwrap(document.findString("Next page", withOptions: []).first))
            store.updateCurrentPage(index: 1, for: first.id)
            _ = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
                named: "other-document", pages: ["Different document"]
            ))
            return "翻译这段文字"
        }
        let other = try XCTUnwrap(store.activeSession)
        XCTAssertNotEqual(other.id, first.id)

        let groupID = try translation.addAnnotation()
        let group = try XCTUnwrap(store.annotationGroups(for: first.id).first { $0.groupID == groupID })
        XCTAssertEqual(group.comment, "翻译这段文字")
        XCTAssertEqual(group.snippet, "Translate this passage")
        XCTAssertEqual(Set(group.records.map(\.pageIndex)), [0])
        XCTAssertTrue(store.annotationGroups(for: other.id).isEmpty)
        XCTAssertEqual(store.session(for: first.id)?.isDirty, true)
        XCTAssertEqual(document.page(at: 1)?.annotations.count, 0)
    }

    func testAddingTranslationPreservesExistingCommentAndIsIdempotentWithSharedUndo() async throws {
        let fixture = try makeFixture(named: "translation-existing-comment")
        let existingRecords = HighlightService.applyHighlight(to: fixture.selection)
        _ = HighlightService.updateComment("Existing note", for: existingRecords)
        fixture.store.noteHighlightsAdded(existingRecords, for: fixture.session.id)
        let existingID = try XCTUnwrap(existingRecords.first?.annotation.userName)
        await fixture.translation.translate(fixture.translation.request) { _, _ in "系统译文" }

        let addedID = try fixture.translation.addAnnotation()
        XCTAssertEqual(try fixture.translation.addAnnotation(), addedID)
        let groups = fixture.store.annotationGroups(for: fixture.session.id)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first(where: { $0.groupID == existingID })?.comment, "Existing note")
        XCTAssertEqual(groups.first(where: { $0.groupID == addedID })?.comment, "系统译文")
        XCTAssertEqual(fixture.store.session(for: fixture.session.id)?.undoStack.count, 2)

        XCTAssertTrue(fixture.store.undoLastHighlight(for: fixture.session.id))
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.session.id).map(\.groupID), [existingID])
        XCTAssertTrue(fixture.store.redoLastHighlight(for: fixture.session.id))
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.session.id)
            .first(where: { $0.groupID == addedID })?.comment, "系统译文")
    }

    func testLateResultDoesNotReplaceNewLanguageOrSurviveCancellation() async throws {
        let fixture = try makeFixture(named: "translation-late-result")
        let originalRequest = fixture.translation.request
        await fixture.translation.translate(originalRequest) { _, _ in
            _ = fixture.translation.selectTargetLanguage(Locale.Language(identifier: "ja"))
            return "Stale result"
        }
        XCTAssertEqual(fixture.translation.state, .translating)
        XCTAssertEqual(fixture.translation.request.targetLanguage.languageCode?.identifier, "ja")
        XCTAssertThrowsError(try fixture.translation.addAnnotation())

        await fixture.translation.translate(fixture.translation.request) { _, _ in
            fixture.translation.cancel()
            return "Cancelled result"
        }
        XCTAssertEqual(fixture.translation.state, .cancelled)
        XCTAssertThrowsError(try fixture.translation.addAnnotation())
        XCTAssertTrue(fixture.store.annotationGroups(for: fixture.session.id).isEmpty)
    }

    func testClosedSourceCannotWriteIntoAnotherDocument() async throws {
        let fixture = try makeFixture(named: "translation-closed-source")
        await fixture.translation.translate(fixture.translation.request) { _, _ in "译文" }
        fixture.store.close(sessionID: fixture.session.id)
        let other = try fixture.store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "translation-new-source", pages: ["Translate this passage"]
        ))

        XCTAssertThrowsError(try fixture.translation.addAnnotation()) { error in
            guard case SelectionTranslationError.sourceDocumentChanged = error else {
                return XCTFail("Expected a closed-source error, got \(error)")
            }
        }
        XCTAssertTrue(fixture.store.annotationGroups(for: other.id).isEmpty)
        XCTAssertEqual(fixture.document.page(at: 0)?.annotations.count, 0)
    }

    func testReloadedSourceRejectsTheOldSelection() async throws {
        let fixture = try makeFixture(named: "translation-reloaded-source")
        await fixture.translation.translate(fixture.translation.request) { _, _ in "译文" }
        _ = try fixture.store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "translation-background", pages: ["Another PDF"]
        ))
        fixture.store.discardCleanBackgroundDocuments()
        let reloaded = try fixture.store.pdfDocument(for: fixture.session.id)
        XCTAssertFalse(reloaded === fixture.document)

        XCTAssertThrowsError(try fixture.translation.addAnnotation()) { error in
            guard case SelectionTranslationError.sourceDocumentChanged = error else {
                return XCTFail("Expected a changed-source error, got \(error)")
            }
        }
        XCTAssertTrue(fixture.store.annotationGroups(for: fixture.session.id).isEmpty)
    }

    func testAnnotationUsesNormalSavePipelineAndEmptyResultsCannotWrite() async throws {
        let fixture = try makeFixture(named: "translation-save")
        await fixture.translation.translate(fixture.translation.request) { _, _ in "  \n" }
        guard case .failed = fixture.translation.state else { return XCTFail("Expected an empty-result error") }
        XCTAssertThrowsError(try fixture.translation.addAnnotation())

        let request = fixture.translation.selectTargetLanguage(Locale.Language(identifier: "zh-Hans"))
        await fixture.translation.translate(request) { _, _ in "保存后的译文" }
        _ = try fixture.translation.addAnnotation()
        XCTAssertEqual(PDFDocument(url: fixture.session.url)?.page(at: 0)?.annotations.count, 0)
        try fixture.store.saveAnnotations(for: fixture.session.id)
        let savedDocument = try XCTUnwrap(PDFDocument(url: fixture.session.url))
        XCTAssertEqual(HighlightService.buildHighlightGroups(in: savedDocument).first?.comment, "保存后的译文")
        XCTAssertEqual(fixture.store.session(for: fixture.session.id)?.isDirty, false)
    }

    private func makeFixture(named name: String) throws -> (
        store: DocumentStore, session: DocumentSession, document: PDFDocument,
        selection: PDFSelection, translation: SelectionTranslation
    ) {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: name, pages: ["Translate this passage"]
        ))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("Translate this passage", withOptions: []).first)
        let translation = try SelectionTranslation(selection: selection, sessionID: session.id, documentStore: store)
        return (store, session, document, selection, translation)
    }
}
