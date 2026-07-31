import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct FloatingOutlineViewControllerTests {
    @Test
    func floatingOutlineAppearsAsRailAndExpandsOnHover() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-rail"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        #expect(controller.testingIsPresented == false)

        store.setRightSidebarVisible(false)

        #expect(controller.testingIsPresented)
        #expect(controller.testingItemCount == 3)
        #expect(controller.testingIsExpanded == false)
        #expect(controller.preferredSize.width == 28)

        controller.testingSetHovered(true)

        #expect(controller.testingIsExpanded)
        #expect(controller.preferredSize.width == 300)
        #expect(controller.testingOutlineViewController.isViewLoaded)

        controller.testingSetHovered(false)
        #expect(controller.testingIsExpanded == false)

        store.setRightSidebarVisible(true)
        #expect(controller.testingIsPresented == false)
    }

    @Test
    func floatingOutlineUsesConfiguredHeightUntilWindowOverridesIt() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.floatingOutlineHeight = 340
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-height"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(700)
        controller.testingSetHovered(true)

        #expect(controller.preferredSize.height == 340)

        configuration.layout.floatingOutlineHeight = 410
        store.updateAppConfiguration(configuration)
        #expect(controller.preferredSize.height == 410)

        controller.testingResizeFromTop(by: 25)
        #expect(controller.preferredSize.height == 460)

        configuration.layout.floatingOutlineHeight = 300
        store.updateAppConfiguration(configuration)
        #expect(controller.preferredSize.height == 460)

        controller.testingSetHovered(false)
        controller.testingSetHovered(true)
        #expect(controller.preferredSize.height == 460)

        let otherWindowController = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        otherWindowController.loadViewIfNeeded()
        otherWindowController.setMaximumAvailableHeight(700)
        otherWindowController.testingSetHovered(true)
        #expect(otherWindowController.preferredSize.height == 300)
    }

    @Test
    func floatingOutlineResizesFromEitherEdgeWithinLimits() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-edges"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(500)
        controller.testingSetHovered(true)

        controller.testingResizeFromTop(by: 40)
        #expect(controller.preferredSize.height == 440)

        controller.testingResizeFromBottom(by: -20)
        #expect(controller.preferredSize.height == 480)

        controller.testingResizeFromTop(by: 100)
        #expect(controller.preferredSize.height == 500)

        controller.testingResizeFromBottom(by: 250)
        #expect(controller.preferredSize.height == 180)
    }

    @Test
    func floatingOutlineUsesSemanticOutlinePaneWhenSidebarsAreSwapped() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = true
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-swapped"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setLeftSidebarVisible(false)
        store.setRightSidebarVisible(true)
        #expect(controller.testingIsPresented)

        store.setLeftSidebarVisible(true)
        store.setRightSidebarVisible(false)
        #expect(controller.testingIsPresented == false)
    }

    @Test
    func floatingOutlineStaysHiddenForPDFWithoutOutline() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "floating-empty"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setRightSidebarVisible(false)

        #expect(controller.testingIsPresented == false)
        #expect(controller.testingItemCount == 0)
    }

    @Test
    func expandedFloatingOutlineNavigatesWithoutResizingReader() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-navigation"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let workspace = splitController.readerWorkspaceViewController
        let floatingOutline = workspace.floatingOutlineViewController
        #expect(floatingOutline.testingIsPresented)
        let centerWidthBefore = splitController.splitView.arrangedSubviews[1].frame.width
        let scaleBefore = splitController.readerViewController.pdfView.scaleFactor

        floatingOutline.testingSetHovered(true)
        flushFloatingOutlineLayout(windowController.window)

        #expect(floatingOutline.view.frame.width > 250)
        #expect(abs(splitController.splitView.arrangedSubviews[1].frame.width - centerWidthBefore) < 0.5)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - scaleBefore) < 0.001)

        let outlineController = floatingOutline.testingOutlineViewController
        outlineController.view.frame = NSRect(x: 0, y: 0, width: 292, height: 360)
        outlineController.view.layoutSubtreeIfNeeded()
        let rows = floatingOutlineRows(in: outlineController.view)
        #expect(rows.count == 3)

        rows[2].performPrimaryAction()
        #expect(store.session(for: session.id)?.currentPageIndex == 2)
    }

    @Test
    func resizingFloatingOutlineIsSymmetricAndKeepsReaderGeometryStable() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-window-resize"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        windowController.window?.setContentSize(NSSize(width: 1_200, height: 900))
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let workspace = splitController.readerWorkspaceViewController
        let floatingOutline = workspace.floatingOutlineViewController
        floatingOutline.testingSetHovered(true)
        flushFloatingOutlineLayout(windowController.window)

        let centerWidthBefore = splitController.splitView.arrangedSubviews[1].frame.width
        let scaleBefore = splitController.readerViewController.pdfView.scaleFactor
        let initialFrame = floatingOutline.view.frame

        floatingOutline.testingResizeFromTop(by: 40)
        flushFloatingOutlineLayout(windowController.window)
        let topResizedFrame = floatingOutline.view.frame
        #expect(abs(topResizedFrame.midY - initialFrame.midY) < 0.5)
        #expect(abs(topResizedFrame.minY - initialFrame.minY + 40) < 0.5)
        #expect(abs(topResizedFrame.maxY - initialFrame.maxY - 40) < 0.5)
        #expect(abs(topResizedFrame.height - initialFrame.height - 80) < 0.5)

        floatingOutline.testingResizeFromBottom(by: -30)
        flushFloatingOutlineLayout(windowController.window)
        let bottomResizedFrame = floatingOutline.view.frame
        #expect(abs(bottomResizedFrame.midY - topResizedFrame.midY) < 0.5)
        #expect(abs(bottomResizedFrame.minY - topResizedFrame.minY + 30) < 0.5)
        #expect(abs(bottomResizedFrame.maxY - topResizedFrame.maxY - 30) < 0.5)
        #expect(abs(bottomResizedFrame.height - topResizedFrame.height - 60) < 0.5)
        #expect(abs(splitController.splitView.arrangedSubviews[1].frame.width - centerWidthBefore) < 0.5)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - scaleBefore) < 0.001)
    }

    @Test
    func allPagesOverviewSuppressesAndRestoresFloatingOutline() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-overview"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let floatingOutline = splitController.readerWorkspaceViewController.floatingOutlineViewController
        let reader = splitController.readerViewController
        #expect(floatingOutline.testingIsPresented)

        reader.setAllPagesOverviewActive(true)
        flushFloatingOutlineLayout(windowController.window)
        #expect(reader.isAllPagesOverviewActive)
        #expect(floatingOutline.testingIsPresented == false)

        reader.setAllPagesOverviewActive(false)
        flushFloatingOutlineLayout(windowController.window)
        #expect(reader.isAllPagesOverviewActive == false)
        #expect(floatingOutline.testingIsPresented)
    }

    @Test
    func continuousReadingFloatingOutlineNavigatesAcrossDocuments() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                makeFloatingOutlinePDF(named: "floating-continuous-first"),
                makeFloatingOutlinePDF(named: "floating-continuous-second"),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.testingSetHovered(true)

        let outlineController = controller.testingOutlineViewController
        outlineController.view.frame = NSRect(x: 0, y: 0, width: 292, height: 420)
        outlineController.view.layoutSubtreeIfNeeded()
        let rows = floatingOutlineRows(in: outlineController.view)
        #expect(rows.count == 8)

        rows[6].performPrimaryAction()

        #expect(store.activeSessionID(in: store.defaultWindowID) == sessions[1].id)
        #expect(store.session(for: sessions[1].id)?.currentPageIndex == 1)
    }
}

@MainActor
private func makeFloatingOutlinePDF(named name: String) throws -> URL {
    let rootDirectory = try TestPDFFixtures.makeRootDirectory(prefix: "serein-floating-outline")
    let url = rootDirectory.appendingPathComponent("\(name).pdf")
    let document = TestPDFFixtures.makeBlankDocument(pageCount: 3)

    let root = PDFOutline()
    let first = PDFOutline()
    first.label = "Introduction"
    first.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
    let child = PDFOutline()
    child.label = "Background"
    child.destination = PDFDestination(page: document.page(at: 1)!, at: .zero)
    first.insertChild(child, at: 0)
    let second = PDFOutline()
    second.label = "Conclusion"
    second.destination = PDFDestination(page: document.page(at: 2)!, at: .zero)
    root.insertChild(first, at: 0)
    root.insertChild(second, at: 1)
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func floatingOutlineRows(in root: NSView) -> [OutlineRowView] {
    var rows: [OutlineRowView] = []
    if let row = root as? OutlineRowView {
        rows.append(row)
    }
    for subview in root.subviews {
        rows.append(contentsOf: floatingOutlineRows(in: subview))
    }
    return rows.sorted { $0.frame.minY < $1.frame.minY }
}

@MainActor
private func flushFloatingOutlineLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}
