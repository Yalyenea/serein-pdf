import AppKit
import PDFKit
import XCTest
@testable import SlatePDF

private final class SidebarInMemoryDocumentStorePersistence: DocumentStorePersistence {
    var state: PersistedDocumentStoreState?

    func loadState() throws -> PersistedDocumentStoreState? {
        state
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        self.state = state
    }
}

private final class SidebarInMemoryReadingStateStore: ReadingStateStore {
    var states: [URL: PersistedReadingState] = [:]

    func loadState(for url: URL) throws -> PersistedReadingState? {
        states[url]
    }

    func saveState(_ state: PersistedReadingState) throws {
        states[state.url] = state
    }
}

private final class SidebarInMemoryRecentFilesStore: RecentFilesStore {
    var recentFiles: [URL] = []

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
final class AnnotationsViewControllerTests: XCTestCase {
    func testApplyCommentPersistsFromSidebarEditor() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-comment"))
        let record = try makeHighlightRecord(in: session.pdfDocument)
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        let applyButton = try XCTUnwrap(findButton(titled: "Apply", in: controller.view))

        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(textView.allowsUndo)
        XCTAssertFalse(textView.isRichText)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, true)

        textView.string = "Sidebar comment"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertTrue(applyButton.isEnabled)

        applyButton.performClick(nil)

        XCTAssertEqual(store.annotationGroups(for: session.id).first?.comment, "Sidebar comment")
    }

    func testApplyCommentSurvivesMomentarySelectionLoss() throws {
        let store = makeStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-selection"))
        let record = try makeHighlightRecord(in: session.pdfDocument)
        store.noteHighlightsAdded([record], for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))

        let controller = AnnotationsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findDescendant(of: NSTextView.self, in: controller.view))
        let tableView = try XCTUnwrap(findDescendant(of: NSTableView.self, in: controller.view))
        let applyButton = try XCTUnwrap(findButton(titled: "Apply", in: controller.view))

        textView.string = "Selection-safe comment"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertTrue(applyButton.isEnabled)

        tableView.allowsEmptySelection = true
        tableView.deselectAll(nil)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        XCTAssertTrue(applyButton.isEnabled)

        applyButton.performClick(nil)

        XCTAssertEqual(store.annotationGroups(for: session.id).first?.comment, "Selection-safe comment")
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(
            persistence: SidebarInMemoryDocumentStorePersistence(),
            readingStateStore: SidebarInMemoryReadingStateStore(),
            recentFilesStore: SidebarInMemoryRecentFilesStore()
        )
    }
}

@MainActor
private func makeHighlightRecord(in document: PDFDocument) throws -> HighlightAnnotationRecord {
    guard let page = document.page(at: 0) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let annotation = PDFAnnotation(
        bounds: NSRect(x: 24, y: 110, width: 120, height: 18),
        forType: .highlight,
        withProperties: nil
    )
    annotation.color = HighlightColor.default.nsColor
    annotation.userName = UUID().uuidString
    annotation.modificationDate = Date(timeIntervalSinceReferenceDate: 1)
    page.addAnnotation(annotation)

    return HighlightAnnotationRecord(pageIndex: 0, annotation: annotation)
}

@MainActor
private func makeTemporaryPDF(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    let image = NSImage(size: NSSize(width: 200, height: 260))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
    NSString(string: name).draw(
        in: NSRect(x: 24, y: 110, width: 152, height: 40),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
    )
    image.unlockFocus()

    guard let page = PDFPage(image: image) else {
        throw CocoaError(.fileWriteUnknown)
    }
    document.insert(page, at: 0)

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func findButton(titled title: String, in root: NSView) -> NSButton? {
    if let button = root as? NSButton, button.title == title {
        return button
    }

    for subview in root.subviews {
        if let button = findButton(titled: title, in: subview) {
            return button
        }
    }

    return nil
}

@MainActor
private func findDescendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
    if let match = root as? T {
        return match
    }

    for subview in root.subviews {
        if let match = findDescendant(of: type, in: subview) {
            return match
        }
    }

    return nil
}
