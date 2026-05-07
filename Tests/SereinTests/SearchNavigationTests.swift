import AppKit
import PDFKit
import XCTest
@testable import Serein

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

    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL] {
        if let index = recentFiles.firstIndex(of: oldURL) { recentFiles[index] = newURL }
        return recentFiles
    }
}

@MainActor
final class SearchNavigationTests: XCTestCase {
    func testFirstSubmitOnlySearchesAndSecondSubmitStartsNavigation() throws {
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

        XCTAssertEqual(actions, [.activateNext])
    }

    func testFirstBrowseStepSelectsFirstMatchWithoutSkipping() throws {
        let store = makeStore()
        let url = try makeSearchableTemporaryPDF(
            named: "first-browse-step",
            pages: ["needle alpha needle beta needle"]
        )
        _ = try store.open(documentAt: url)
        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)

        let controller = SearchResultsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.selectedMatch())
        XCTAssertEqual(controller.selectionSummary().selectedIndex, nil)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 0)
        XCTAssertEqual(controller.selectionSummary().selectedIndex, 0)
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

        XCTAssertNil(controller.selectedMatch())
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 0)

        store.activate(sessionID: session.id, in: store.defaultWindowID, targetPane: .primary)

        XCTAssertEqual(controller.selectedMatch()?.matchIndex, 0)
        XCTAssertEqual(controller.selectNextMatch()?.matchIndex, 1)
    }

    func testShowFindBarCanForceAllOpenScopeAndRequery() throws {
        let store = makeStore()
        let first = try makeSearchableTemporaryPDF(
            named: "scope-primary",
            pages: ["needle alpha beta"]
        )
        let second = try makeSearchableTemporaryPDF(
            named: "scope-secondary",
            pages: ["needle gamma delta"]
        )
        let session = try store.open(documentAt: first)
        _ = try store.open(documentAt: second)

        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()

        store.updateSearch(query: "needle", scope: .currentDocument, in: store.defaultWindowID)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .currentDocument)
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 1)

        reader.showFindBar(scope: .allOpen)

        XCTAssertTrue(reader.isFindBarVisible)
        XCTAssertEqual(store.searchScope(in: store.defaultWindowID), .allOpen)
        XCTAssertEqual(store.searchQuery(in: store.defaultWindowID), "needle")
        XCTAssertEqual(store.totalSearchMatches(in: store.defaultWindowID), 2)
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
