import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class AnnotationSaveTests: XCTestCase {
    func testCommandSSavesNewEditsWithoutOpeningFileMenu() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        let previousWindowsMenu = app.windowsMenu
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "command-s-live-menu"))
        let controller = MainWindowController(documentStore: store)
        let delegate = AppDelegate()
        delegate.installMenuForTesting(documentStore: store, controllers: [controller])
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        defer {
            NotificationCenter.default.removeObserver(delegate)
            window.orderOut(nil)
            app.mainMenu = previousMenu
            app.windowsMenu = previousWindowsMenu
        }
        let menu = try XCTUnwrap(app.mainMenu)
        func findSave(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.representedObject as? ShortcutCommand == .saveAnnotations { return item }
                if let submenu = item.submenu, let match = findSave(in: submenu) { return match }
            }
            return nil
        }
        let save = try XCTUnwrap(findSave(in: menu))
        XCTAssertFalse(save.isEnabled)
        for count in 1...2 {
            try addHighlightAnnotation(to: session, in: store)
            store.setDirty(true, for: session.id)
            XCTAssertTrue(save.isEnabled)
            XCTAssertTrue(menu.performKeyEquivalent(with: makeKeyEvent(characters: "s", modifierFlags: [.command], window: window)))
            XCTAssertFalse(session.isDirty)
            XCTAssertFalse(save.isEnabled)
            XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count, count)
        }
    }

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
        // Must not write to disk either — dirty alone could false-green a buggy save.
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count ?? 0, 0)
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
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count ?? 0, 0)
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

    func testCompletedAutoSaveDoesNotClearNewerAnnotationChanges() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "autosave-generation"))
        let document = try store.pdfDocument(for: session.id)
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = PDFAnnotation(
            bounds: NSRect(x: 10, y: 10, width: 60, height: 16),
            forType: .highlight,
            withProperties: nil
        )
        page.addAnnotation(annotation)
        store.noteHighlightsAdded(
            [HighlightAnnotationRecord(pageIndex: 0, annotation: annotation)],
            for: session.id,
            now: Date(timeIntervalSinceReferenceDate: 1)
        )
        let prepared = store.prepareAutoSaveJobs(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let group = try XCTUnwrap(store.annotationGroups(for: session.id).first)
        XCTAssertTrue(store.updateComment("newer", forHighlightGroup: group.groupID, in: session.id))

        let results = DocumentStore.performAutoSaveJobs(prepared.jobs)
        XCTAssertTrue(store.completeAutoSave(results).isEmpty)

        XCTAssertTrue(store.session(for: session.id)?.isDirty == true)
    }

    func testCompletedAutoSaveDoesNotReplaceNewerManualSave() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "autosave-stale-manual"))
        try addHighlightAnnotation(to: session, in: store)
        store.setDirty(true, for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        let prepared = store.prepareAutoSaveJobs(now: Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertEqual(prepared.jobs.count, 1)

        try addHighlightAnnotation(to: session, in: store)
        try store.saveAnnotations(for: session.id)

        let results = DocumentStore.performAutoSaveJobs(prepared.jobs)
        XCTAssertTrue(store.completeAutoSave(results).isEmpty)
        XCTAssertEqual(store.session(for: session.id)?.isDirty, false)
        XCTAssertEqual(PDFDocument(url: session.url)?.page(at: 0)?.annotations.count, 2)
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
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
        try TestPDFFixtures.makeBlankPDF(named: name)
    }
}
