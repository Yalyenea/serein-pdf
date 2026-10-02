import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class SidebarChromeRegressionTests: XCTestCase {
    func testQuickOutlineClosesTheOutlinePaneAfterSwapping() throws {
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            defer { controller.close() }
            let windowID = controller.windowID
            let tabsWereVisible = swapped
                ? store.isRightSidebarVisible(in: windowID)
                : store.isLeftSidebarVisible(in: windowID)
            XCTAssertTrue(store.isOutlinePaneVisible(in: windowID))

            controller.showQuickOutline()

            XCTAssertFalse(store.isOutlinePaneVisible(in: windowID))
            XCTAssertEqual(swapped
                ? store.isRightSidebarVisible(in: windowID)
                : store.isLeftSidebarVisible(in: windowID), tabsWereVisible)
        }
    }

    func testSidebarModeMenuUsesOutlinePaneVisibilityInBothPositions() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        let previousWindowsMenu = app.windowsMenu
        defer {
            app.mainMenu = previousMenu
            app.windowsMenu = previousWindowsMenu
        }
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            let delegate = AppDelegate()
            defer {
                NotificationCenter.default.removeObserver(delegate)
                controller.close()
            }
            controller.window?.makeKeyAndOrderFront(nil)
            delegate.installMenuForTesting(documentStore: store, controllers: [controller])
            let item = try XCTUnwrap(findMenuItem(.toggleRightSidebarMode, in: try XCTUnwrap(app.mainMenu)))
            store.setTabPresentationMode(.horizontalTitlebar, in: controller.windowID)
            XCTAssertTrue(delegate.validateMenuItem(item))

            store.setOutlinePaneVisible(false, in: controller.windowID)
            XCTAssertFalse(delegate.validateMenuItem(item))
            if swapped { store.setRightSidebarVisible(true, in: controller.windowID) }
            else { store.setLeftSidebarVisible(true, in: controller.windowID) }
            XCTAssertFalse(delegate.validateMenuItem(item))
        }
    }

    func testAnnotationPreviewSuppressionUsesTheVisibleAnnotationsPane() throws {
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            defer { controller.close() }
            let sessionID = try XCTUnwrap(store.activeSessionID(in: controller.windowID))
            let document = try store.pdfDocument(for: sessionID)
            let page = try XCTUnwrap(document.page(at: 0))
            let annotation = PDFAnnotation(bounds: NSRect(x: 30, y: 100, width: 80, height: 18),
                                           forType: .highlight, withProperties: nil)
            annotation.userName = UUID().uuidString
            annotation.color = HighlightColor.pink.nsColor
            annotation.contents = "Comment"
            page.addAnnotation(annotation)
            store.noteHighlightsAdded([HighlightAnnotationRecord(pageIndex: 0, annotation: annotation)],
                                      for: sessionID)
            store.setRightSidebarMode(.annotations, in: controller.windowID)
            let split = try XCTUnwrap(controller.window?.contentViewController as? SplitViewController)
            let groupID = try XCTUnwrap(store.annotationGroups(for: sessionID).first?.groupID)
            split.rightSidebarViewController.annotationsViewController.reveal(groupID: groupID, focusEditor: false)

            if swapped { store.setRightSidebarVisible(false, in: controller.windowID) }
            else { store.setLeftSidebarVisible(false, in: controller.windowID) }
            XCTAssertEqual(split.readerViewController.shouldSuppressAnnotationPreview?(groupID), true)

            store.setOutlinePaneVisible(false, in: controller.windowID)
            if swapped { store.setRightSidebarVisible(true, in: controller.windowID) }
            else { store.setLeftSidebarVisible(true, in: controller.windowID) }
            XCTAssertEqual(split.readerViewController.shouldSuppressAnnotationPreview?(groupID), false)
        }
    }

    func testHorizontalTabsRemainAttachedWhenWindowShrinksAndTabsChange() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        for index in 0..<12 {
            let session = store.newBlankTab()
            store.renameSession("Document \(index)", for: session.id)
        }
        store.setTabPresentationMode(.horizontalTitlebar)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
        let tabs = split.titlebarTabsController
        for width in [CGFloat(1100), 560, 800] {
            window.setContentSize(NSSize(width: width, height: 500))
            settle(window)
            XCTAssertTrue(tabs.view.window === window,
                          "Window width \(window.frame.width), strip \(tabs.preferredContentSize.width), visible toolbar items \(window.toolbar?.visibleItems?.count ?? 0)")
            XCTAssertLessThan(tabs.preferredContentSize.width, window.frame.width)
            XCTAssertNil(window.toolbar?.centeredItemIdentifier)
            if width == 1100 {
                XCTAssertGreaterThan(tabs.preferredContentSize.width, 760)
            }
            let stripFrame = tabs.view.convert(tabs.view.bounds, to: nil)
            let trafficLightEdge = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
                .map { $0.convert($0.bounds, to: nil).maxX }
                .max() ?? 0
            XCTAssertGreaterThan(stripFrame.minX, trafficLightEdge)
            XCTAssertLessThanOrEqual(stripFrame.maxX, window.frame.width)
            let item = try XCTUnwrap(window.toolbar?.items.first)
            XCTAssertFalse(item.isBordered)
            XCTAssertEqual(item.view?.fittingSize.width ?? 0, tabs.preferredContentSize.width, accuracy: 0.5)
        }
        _ = store.newBlankTab()
        settle(window)
        XCTAssertTrue(tabs.view.window === window)
    }

    func testSelectionNavigationSurvivesPendingChromeReflow() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.reader.fitWidthOnOpen = false
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let session = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "selection-after-chrome", pages: ["First page", "Second page target"]
        ))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("target", withOptions: []).first)
        let page = try XCTUnwrap(selection.pages.first)
        let bounds = selection.bounds(for: page)
        let expected = ReadingPosition(pageIndex: document.index(for: page),
                                       point: NSPoint(x: bounds.minX, y: bounds.maxY))
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.view.frame = NSRect(x: 0, y: 0, width: 800, height: 650)
        reader.view.layoutSubtreeIfNeeded()
        reader.prepareForChromeSizeChange()
        reader.view.frame.size.width = 650

        reader.go(to: selection, setSelection: false)
        reader.reflowForContainerSizeChange()
        reader.testingFlushReadingPositionWriteback()

        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, expected)
        XCTAssertEqual(reader.pdfView.currentPage.map { document.index(for: $0) }, expected.pageIndex)
        XCTAssertNil(reader.pdfView.currentSelection)
        XCTAssertTrue(reader.pdfView.bounds.intersects(reader.pdfView.convert(bounds, from: page)))
    }

    private func makeWindow(swapped: Bool) throws -> (DocumentStore, MainWindowController) {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = swapped
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: TestPDFFixtures.makeLabeledPDF(named: "sidebar-regression"))
        let controller = MainWindowController(documentStore: store)
        controller.window?.layoutIfNeeded()
        return (store, controller)
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        window.layoutIfNeeded()
    }

    private func findMenuItem(_ command: ShortcutCommand, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? ShortcutCommand == command { return item }
            if let submenu = item.submenu, let match = findMenuItem(command, in: submenu) { return match }
        }
        return nil
    }
}
