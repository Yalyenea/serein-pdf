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
    func outlineColumnShrinksWithSidebarAndLocksHorizontalPanning() throws {
        let store = DocumentStore(appConfiguration: .default)
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "narrow-outline"))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 140, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let column = outlineView.tableColumns.first else {
            Issue.record("Failed to locate outline sidebar views")
            return
        }

        scrollView.contentView.scroll(to: NSPoint(x: 80, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(abs(column.width - scrollView.contentSize.width) < 0.5)
        #expect(column.width <= scrollView.contentSize.width + 0.5)
        #expect(scrollView.contentView.bounds.origin.x == 0)
        #expect(hasPinnedEdgeConstraint(for: scrollView, in: controller.view, attribute: .leading))
        #expect(hasPinnedEdgeConstraint(for: scrollView, in: controller.view, attribute: .trailing))
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
        #expect(textField.lineBreakMode == .byCharWrapping)
        #expect(textField.maximumNumberOfLines == 0)
        #expect(textField.font?.pointSize == 13)
        #expect(textField.preferredMaxLayoutWidth <= column.width)
        let paragraphStyle = textField.attributedStringValue.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraphStyle?.lineBreakMode == .byCharWrapping)
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
    func outlinePaneEmbedsDirectlyOnTransparentSidebarSurface() {
        let store = DocumentStore(appConfiguration: .default)
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView else {
            Issue.record("Failed to locate outline scroll view")
            return
        }

        let rowView = controller.outlineView(
            outlineView,
            rowViewForItem: OutlineNode(title: "Row", pageIndex: 0, children: [])
        )

        #expect(scrollView.drawsBackground == false)
        #expect(scrollView.contentView.drawsBackground == false)
        #expect(scrollView.contentView.backgroundColor == .clear)
        #expect(outlineView.backgroundColor == .clear)
        #expect(outlineView.usesAlternatingRowBackgroundColors == false)
        #expect(rowView != nil)
    }

    @Test
    func outlineExpansionToggleCollapsesAndExpandsTree() throws {
        let store = DocumentStore(appConfiguration: .default)
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "nested-outline", includeChild: true))
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let toggleButton = findView(
                identifier: "outlineExpansionToggleButton",
                in: controller.view
              ) as? NSButton else {
            Issue.record("Failed to locate outline tree views")
            return
        }

        #expect(outlineView.numberOfRows == 3)

        toggleButton.performClick(nil)
        #expect(outlineView.numberOfRows == 2)
        #expect(toggleButton.toolTip == "Expand outline")

        toggleButton.performClick(nil)
        #expect(outlineView.numberOfRows == 3)
        #expect(toggleButton.toolTip == "Collapse outline")
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
private func makeTemporaryPDFWithOutline(
    named name: String,
    outlineTitles: [String] = [],
    includeChild: Bool = false
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    let pageCount = includeChild ? 3 : 2
    for index in 0..<pageCount {
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
        if includeChild, index == 0 {
            let child = PDFOutline()
            child.label = "\(name) child"
            child.destination = PDFDestination(page: document.page(at: 2)!, at: .zero)
            item.insertChild(child, at: 0)
        }
        root.insertChild(item, at: index)
    }
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func findView(identifier: String, in root: NSView) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }
    for subview in root.subviews {
        if let match = findView(identifier: identifier, in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private func hasPinnedEdgeConstraint(
    for view: NSView,
    in container: NSView,
    attribute: NSLayoutConstraint.Attribute
) -> Bool {
    container.constraints.contains { constraint in
        constraint.firstItem as? NSView === view &&
            constraint.firstAttribute == attribute &&
            constraint.secondItem as? NSView === container &&
            constraint.secondAttribute == attribute &&
            abs(constraint.constant) < 0.5
    }
}
