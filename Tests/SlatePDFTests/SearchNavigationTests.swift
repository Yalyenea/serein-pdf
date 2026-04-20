import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

private final class SearchNavInMemoryDocumentStorePersistence: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?

    func loadState() throws -> PersistedDocumentStoreState? {
        state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        self.state = state
    }
}

private final class SearchNavInMemoryReadingStateStore: ReadingStateStore {
    func loadState(for url: URL) throws -> PersistedReadingState? {
        nil
    }

    func saveState(_ state: PersistedReadingState) throws {}
}

private final class SearchNavInMemoryRecentFilesStore: RecentFilesStore {
    private var recentFiles: [URL] = []

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
final class SearchNavigationTests: XCTestCase {
    func testRepeatedSubmitOnSameQueryAdvancesToNextMatch() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "repeat-submit",
            pages: ["needle alpha needle beta needle"]
        )
        let session = try store.open(documentAt: url)
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.showFindBar()

        var actions: [FindNavigationAction] = []
        reader.onFindActionRequested = { actions.append($0) }

        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)
        reader.findBar(FindBarView(), didSubmitQuery: "needle", scope: .currentDocument)

        XCTAssertEqual(actions, [.activateSelected, .activateNext])
    }

    func testSearchSelectionSurvivesStoreRefreshAndContinuesNavigation() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "selection-refresh",
            pages: ["needle alpha needle beta needle"]
        )
        let session = try store.open(documentAt: url)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.selectedMatch()?.matchIndex, 0)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 1)

        store.activate(sessionID: session.id, in: store.defaultWindowID, targetPane: .primary)

        XCTAssertEqual(controller.selectedMatch()?.matchIndex, 1)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 2)
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(
            persistence: SearchNavInMemoryDocumentStorePersistence(),
            readingStateStore: SearchNavInMemoryReadingStateStore(),
            recentFilesStore: SearchNavInMemoryRecentFilesStore()
        )
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
