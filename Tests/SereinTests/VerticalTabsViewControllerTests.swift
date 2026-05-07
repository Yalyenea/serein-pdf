import AppKit
import PDFKit
import XCTest
@testable import Serein

private final class VTInMemoryDocumentStorePersistence: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?

    func loadState() throws -> PersistedDocumentStoreState? {
        state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        self.state = state
    }
}

private final class VTInMemoryReadingStateStore: ReadingStateStore {
    func loadState(for url: URL) throws -> PersistedReadingState? {
        nil
    }

    func saveState(_ state: PersistedReadingState) throws {}
}

private final class VTInMemoryRecentFilesStore: RecentFilesStore {
    private(set) var recentFiles: [URL] = []

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
final class VerticalTabsViewControllerTests: XCTestCase {
    func testRecentFooterShowsAndOpensMostRecentURL() throws {
        _ = NSApplication.shared
        let store = DocumentStore(
            persistence: VTInMemoryDocumentStorePersistence(),
            readingStateStore: VTInMemoryReadingStateStore(),
            recentFilesStore: VTInMemoryRecentFilesStore()
        )
        let firstURL = try makeTemporaryPDF(named: "recent-sidebar-first")
        let secondURL = try makeTemporaryPDF(named: "recent-sidebar-second")
        _ = try store.open(documentAt: firstURL)
        _ = try store.open(documentAt: secondURL)

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        var openedURL: URL?
        controller.onOpenRecentURLRequested = { openedURL = $0 }
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.testingRecentSectionVisible)
        XCTAssertEqual(controller.testingRecentFileTitles, ["recent-sidebar-second", "recent-sidebar-first"])

        controller.testingTriggerOpenRecent(at: 0)
        XCTAssertEqual(openedURL, secondURL)
    }

    func testRecentFooterRespectsSettingsToggle() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.showRecentFilesInSidebar = false
        let store = DocumentStore(
            persistence: VTInMemoryDocumentStorePersistence(),
            readingStateStore: VTInMemoryReadingStateStore(),
            recentFilesStore: VTInMemoryRecentFilesStore(),
            appConfiguration: configuration
        )
        _ = try store.open(documentAt: makeTemporaryPDF(named: "recent-sidebar-hidden"))

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertFalse(controller.testingRecentSectionVisible)
        XCTAssertTrue(controller.testingRecentFileTitles.isEmpty)
    }

    func testRecentFooterAdaptsToSidebarWidthChanges() throws {
        _ = NSApplication.shared
        let store = DocumentStore(
            persistence: VTInMemoryDocumentStorePersistence(),
            readingStateStore: VTInMemoryReadingStateStore(),
            recentFilesStore: VTInMemoryRecentFilesStore()
        )
        _ = try store.open(documentAt: makeTemporaryPDF(named: "recent-sidebar-width"))

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.testingRecentSectionVisible)

        controller.view.frame = NSRect(x: 0, y: 0, width: 180, height: 460)
        controller.view.layoutSubtreeIfNeeded()
        let narrowListWidth = controller.testingRecentListWidth
        let narrowButtonWidth = controller.testingRecentButtonWidths.first ?? 0

        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 460)
        controller.view.layoutSubtreeIfNeeded()
        let wideListWidth = controller.testingRecentListWidth
        let wideButtonWidth = controller.testingRecentButtonWidths.first ?? 0

        XCTAssertGreaterThan(wideListWidth, narrowListWidth)
        XCTAssertGreaterThan(wideButtonWidth, narrowButtonWidth)
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
        let page = PDFPage(image: image)
        document.insert(page!, at: 0)
        XCTAssertTrue(document.write(to: url))
        return url
    }
}
