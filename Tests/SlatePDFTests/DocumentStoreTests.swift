import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

@MainActor
final class DocumentStoreTests: XCTestCase {
    func testOpenDocumentCreatesActiveSession() throws {
        let store = DocumentStore()
        let url = try makeTemporaryPDF(named: "single")

        let session = try store.open(documentAt: url)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessionID, session.id)
        XCTAssertEqual(store.activeSession?.title, "single")
    }

    func testOpenMultipleDocumentsKeepsAllSessionsAndActivatesLast() throws {
        let store = DocumentStore()
        let firstURL = try makeTemporaryPDF(named: "first")
        let secondURL = try makeTemporaryPDF(named: "second")

        let firstSession = try store.open(documentAt: firstURL)
        let secondSession = try store.open(documentAt: secondURL)

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions.map(\.id), [firstSession.id, secondSession.id])
        XCTAssertEqual(store.activeSession?.url, secondURL)
    }

    func testCloseActiveSessionFallsBackToPreviousSession() throws {
        let store = DocumentStore()
        let first = try store.open(documentAt: makeTemporaryPDF(named: "alpha"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "beta"))

        XCTAssertEqual(store.activeSessionID, second.id)

        store.close(sessionID: second.id)

        XCTAssertEqual(store.activeSessionID, first.id)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testDefaultTabPresentationModeIsVerticalSidebar() {
        XCTAssertEqual(DocumentStore().tabPresentationMode, .verticalSidebar)
    }

    func testSetTabPresentationModeUpdatesStore() {
        let store = DocumentStore()

        store.setTabPresentationMode(.horizontalTitlebar)

        XCTAssertEqual(store.tabPresentationMode, .horizontalTitlebar)
    }

    func testCloseUnknownSessionDoesNotCrashOrMutateMode() {
        let store = DocumentStore()
        let unknownSessionID = UUID()

        store.close(sessionID: unknownSessionID)

        XCTAssertNil(store.activeSession)
        XCTAssertEqual(store.tabPresentationMode, .verticalSidebar)
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
