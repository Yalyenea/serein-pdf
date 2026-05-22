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
    func outlineRowsWrapLongTitlesWithLargerText() throws {
        let store = DocumentStore(appConfiguration: .default)
        _ = try store.open(
            documentAt: makeTemporaryPDFWithOutline(
                named: "wrapped-outline",
                outlineTitles: [
                    "A deliberately long outline title that should wrap cleanly inside the right sidebar instead of being truncated"
                ]
            )
        )
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 180, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let column = outlineView.tableColumns.first,
              let item = outlineView.item(atRow: 0) as? OutlineNode,
              let cell = controller.outlineView(outlineView, viewFor: column, item: item) as? NSTableCellView,
              let textField = cell.textField else {
            Issue.record("Failed to locate outline row views")
            return
        }

        #expect(controller.outlineView(outlineView, heightOfRowByItem: item) > 40)
        #expect(textField.lineBreakMode == .byWordWrapping)
        #expect(textField.maximumNumberOfLines == 0)
        #expect(textField.font?.pointSize == 13)
        let paragraphStyle = textField.attributedStringValue.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraphStyle?.lineBreakMode == .byWordWrapping)
        #expect(paragraphStyle?.minimumLineHeight == 14)
        #expect(paragraphStyle?.maximumLineHeight == 14)
    }

    @Test
    func outlineRowsKeepSingleLineTitlesCompact() throws {
        let store = DocumentStore(appConfiguration: .default)
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "compact-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 260, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let item = outlineView.item(atRow: 0) as? OutlineNode else {
            Issue.record("Failed to locate outline row")
            return
        }

        #expect(controller.outlineView(outlineView, heightOfRowByItem: item) <= 25)
    }

    @Test
    func outlinePaneHidesScrollersAndDisablesHorizontalScroll() {
        let store = DocumentStore(appConfiguration: .default)
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first else {
            Issue.record("Failed to locate outline scroll view")
            return
        }

        #expect(scrollView.hasVerticalScroller == false)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.horizontalScrollElasticity == .none)
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
private func makeTemporaryPDFWithOutline(named name: String, outlineTitles: [String] = []) throws -> URL {
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
        item.label = index < outlineTitles.count ? outlineTitles[index] : "\(name) \(index + 1)"
        item.destination = PDFDestination(page: document.page(at: index)!, at: .zero)
        root.insertChild(item, at: index)
    }
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}
