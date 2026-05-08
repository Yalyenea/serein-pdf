import AppKit
import PDFKit
import Testing
@testable import Serein

@MainActor
struct OutlineViewControllerTests {
    @Test
    func outlineColumnTracksSidebarWidth() {
        let store = DocumentStore(appConfiguration: .default)
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let column = outlineView.tableColumns.first else {
            Issue.record("Failed to locate outline sidebar views")
            return
        }

        #expect(abs(column.width - scrollView.contentSize.width) < 0.5)
    }

    @Test
    func continuousReadingOutlineGroupsDocuments() throws {
        let store = DocumentStore(appConfiguration: .default)
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDFWithOutline(named: "continuous-outline-first"),
                makeTemporaryPDFWithOutline(named: "continuous-outline-second"),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))

        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let firstRoot = outlineView.item(atRow: 0) as? OutlineNode,
              let secondRoot = outlineView.item(atRow: 3) as? OutlineNode else {
            Issue.record("Failed to locate continuous outline roots")
            return
        }

        #expect(outlineView.numberOfRows == 6)
        #expect(firstRoot.isDocumentRoot)
        #expect(firstRoot.sourceSessionID == sessions[0].id)
        #expect(secondRoot.isDocumentRoot)
        #expect(secondRoot.sourceSessionID == sessions[1].id)
    }
}

@MainActor
private func makeTemporaryPDFWithOutline(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    for index in 0..<2 {
        let image = NSImage(size: NSSize(width: 240, height: 320))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 240, height: 320)).fill()
        image.unlockFocus()
        guard let page = PDFPage(image: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        document.insert(page, at: index)
    }

    let root = PDFOutline()
    for index in 0..<2 {
        let item = PDFOutline()
        item.label = "\(name) \(index + 1)"
        item.destination = PDFDestination(page: document.page(at: index)!, at: .zero)
        root.insertChild(item, at: index)
    }
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}
