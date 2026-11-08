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
            let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier == .titlebarTabs })
            XCTAssertFalse(item.isBordered)
            XCTAssertEqual(item.view?.fittingSize.width ?? 0, tabs.preferredContentSize.width, accuracy: 0.5)
        }
        _ = store.newBlankTab()
        settle(window)
        XCTAssertTrue(tabs.view.window === window)
    }

    func testToolbarButtonTogglesDocumentSidebarInEitherPositionAndKeepsWindowLayoutStable() throws {
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            defer { controller.close() }
            controller.showWindow(nil)
            let window = try XCTUnwrap(controller.window)
            let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
            window.setContentSize(NSSize(width: 560, height: 500))
            settle(window)
            let toolbar = try XCTUnwrap(window.toolbar)
            let item = try XCTUnwrap(toolbar.items.first)
            XCTAssertEqual(item.itemIdentifier.rawValue, "local.yfff.Serein.toggleDocumentSidebar")
            let button = try XCTUnwrap(item.view as? NSButton)
            XCTAssertEqual(button.identifier?.rawValue, "toggleDocumentSidebar")
            XCTAssertEqual(button.frame.size.width, 28, accuracy: 0.5)
            // AppKit constraints measure content alignment, excluding button ornamentation.
            XCTAssertEqual(button.alignmentRect(forFrame: button.frame).height, 26, accuracy: 0.5)
            XCTAssertTrue(toolbar.visibleItems?.contains(where: { $0 === item }) == true)
            let buttonFrame = button.convert(button.bounds, to: nil)
            let contentHeight = window.contentLayoutRect.height
            let windowID = controller.windowID
            let initiallyVisible = swapped
                ? store.isRightSidebarVisible(in: windowID)
                : store.isLeftSidebarVisible(in: windowID)

            for expectedVisible in [!initiallyVisible, initiallyVisible] {
                button.performClick(nil)
                settle(window, duration: 0.25)
                XCTAssertEqual(swapped
                    ? store.isRightSidebarVisible(in: windowID)
                    : store.isLeftSidebarVisible(in: windowID), expectedVisible)
                XCTAssertEqual(store.tabPresentationMode(in: windowID),
                               expectedVisible ? .verticalSidebar : .horizontalTitlebar)
                XCTAssertEqual(button.convert(button.bounds, to: nil).minX, buttonFrame.minX, accuracy: 0.5)
                XCTAssertEqual(button.convert(button.bounds, to: nil).minY, buttonFrame.minY, accuracy: 0.5)
                XCTAssertEqual(window.contentLayoutRect.height, contentHeight, accuracy: 0.5)
                let contentTop = split.splitView.convert(split.splitView.bounds, to: nil).maxY
                if expectedVisible {
                    XCTAssertEqual(contentTop, window.contentView?.bounds.maxY ?? 0, accuracy: 0.5)
                } else {
                    XCTAssertEqual(contentTop, window.contentLayoutRect.maxY, accuracy: 0.5)
                }
                XCTAssertTrue(toolbar.visibleItems?.contains(where: { $0 === item }) == true)
            }
        }
    }


    func testHiddenWindowAppliesDocumentSidebarVisibilityImmediately() throws {
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            defer { controller.close() }
            let window = try XCTUnwrap(controller.window)
            let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
            let tabsItem = try XCTUnwrap(split.splitViewItems.first {
                $0.viewController === split.verticalTabsViewController
            })
            XCTAssertFalse(window.isVisible)

            for visible in [false, true] {
                if swapped { store.setRightSidebarVisible(visible, in: controller.windowID) }
                else { store.setLeftSidebarVisible(visible, in: controller.windowID) }
                XCTAssertEqual(tabsItem.isCollapsed, !visible)
            }
        }
    }

    func testRepeatedDocumentSidebarClicksSettleAtLatestStateWithoutChangingPreferredWidths() throws {
        for swapped in [false, true] {
            let (store, controller) = try makeWindow(swapped: swapped)
            defer { controller.close() }
            let window = try XCTUnwrap(controller.window)
            window.setContentSize(NSSize(width: 1200, height: 700))
            controller.showWindow(nil)
            settle(window)
            let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
            let item = try XCTUnwrap(window.toolbar?.items.first)
            let button = try XCTUnwrap(item.view as? NSButton)
            let buttonFrame = button.convert(button.bounds, to: nil)
            let widths = store.sidebarWidths(in: controller.windowID)
            let tabsItem = try XCTUnwrap(split.splitViewItems.first {
                $0.viewController === split.verticalTabsViewController
            })

            button.performClick(nil)
            settle(window, duration: 0.03)
            let pdfID = "pdf:" + (try XCTUnwrap(store.sessions(in: controller.windowID).first)).id.uuidString
            let oldTarget = try XCTUnwrap(controller.testingTabTransferTargetFrames[pdfID])
            // These requests arrive before the first collapse completes. The last
            // request must survive rather than being dropped by the layout guard.
            button.performClick(nil)
            let reversedSource = try XCTUnwrap(controller.testingTabTransferSourceFrames[pdfID])
            XCTAssertGreaterThan(hypot(reversedSource.midX - oldTarget.midX, reversedSource.midY - oldTarget.midY), 4)
            for _ in 0..<2 { button.performClick(nil) }
            XCTAssertEqual(store.sidebarWidths(in: controller.windowID).left, widths.left)
            XCTAssertEqual(store.sidebarWidths(in: controller.windowID).right, widths.right)
            settle(window, duration: 0.5)

            XCTAssertFalse(tabsItem.isCollapsed)
            XCTAssertEqual(store.tabPresentationMode(in: controller.windowID), .verticalSidebar)
            XCTAssertEqual(store.sidebarWidths(in: controller.windowID).left, widths.left)
            XCTAssertEqual(store.sidebarWidths(in: controller.windowID).right, widths.right)
            XCTAssertEqual(button.convert(button.bounds, to: nil).minX, buttonFrame.minX, accuracy: 0.5)
            XCTAssertEqual(button.convert(button.bounds, to: nil).minY, buttonFrame.minY, accuracy: 0.5)
            let tabsFrame = split.verticalTabsViewController.view.convert(
                split.verticalTabsViewController.view.bounds, to: split.view
            )
            let readerFrame = split.readerWorkspaceViewController.view.convert(
                split.readerWorkspaceViewController.view.bounds, to: split.view
            )
            XCTAssertLessThanOrEqual(tabsFrame.intersection(readerFrame).width, 1)
        }
    }

    func testToolbarButtonOnlyChangesItsOwnWindow() throws {
        let (store, first) = try makeWindow(swapped: false)
        let secondID = store.createWindow(copyingFrom: first.windowID)
        let second = MainWindowController(documentStore: store, windowID: secondID)
        defer { second.close(); first.close() }
        let firstVisible = store.isLeftSidebarVisible(in: first.windowID)
        let secondVisible = store.isLeftSidebarVisible(in: secondID)
        let item = try XCTUnwrap(first.window?.toolbar?.items.first)
        let button = try XCTUnwrap(item.view as? NSButton)

        button.performClick(nil)

        XCTAssertNotEqual(store.isLeftSidebarVisible(in: first.windowID), firstVisible)
        XCTAssertEqual(store.isLeftSidebarVisible(in: secondID), secondVisible)
    }

    func testAllPDFsAndSpaceTransferToPrecomputedPositionsWithoutTakingFocus() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("Tab transfer is disabled when Reduce Motion is enabled")
        }
        let (store, controller) = try makeWindow(swapped: false)
        defer { controller.close() }
        let spaceID = try XCTUnwrap(store.activeWorkspaceID(in: controller.windowID))
        for index in 1...2 {
            _ = try store.open(documentAt: TestPDFFixtures.makeLabeledPDF(named: "transfer-pdf-\(index)"))
        }
        _ = store.createWorkspace(name: "Other", in: controller.windowID)
        store.activateWorkspace(spaceID, in: controller.windowID)
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1200, height: 700))
        controller.showWindow(nil)
        settle(window)
        let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
        let sessionID = try XCTUnwrap(store.activeSessionID(in: controller.windowID))
        let button = try XCTUnwrap(window.toolbar?.items.first?.view as? NSButton)

        for mode in [TabPresentationMode.horizontalTitlebar, .verticalSidebar] {
            XCTAssertTrue(window.makeFirstResponder(split.readerViewController.pdfView))
            let keyWindow = NSApp.keyWindow
            let responder = window.firstResponder
            button.performClick(nil)
            let overlay = try XCTUnwrap(window.childWindows?.first {
                $0.identifier?.rawValue == "tabPresentationTransfer"
            })
            XCTAssertTrue(overlay.ignoresMouseEvents)
            XCTAssertFalse(overlay.isKeyWindow)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
            let planned = controller.testingTabTransferTargetFrames
            let pdfIDs = Set(store.sessions(in: controller.windowID).map { "pdf:" + $0.id.uuidString })
            XCTAssertEqual(Set(planned.keys.filter { $0.hasPrefix("pdf:") }), pdfIDs)
            XCTAssertNotNil(planned["space:" + spaceID.uuidString])
            let rendered = Set(overlay.contentView?.subviews.compactMap { $0.identifier?.rawValue } ?? [])
            XCTAssertTrue(pdfIDs.isSubset(of: rendered))
            XCTAssertTrue(rendered.contains("space:" + spaceID.uuidString))
            settle(window, duration: 0.5)

            XCTAssertEqual(store.tabPresentationMode(in: controller.windowID), mode)
            XCTAssertEqual(store.activeSessionID(in: controller.windowID), sessionID)
            XCTAssertTrue(window.firstResponder === responder)
            XCTAssertNil(overlay.parent)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertEqual(split.verticalTabsViewController.view.alphaValue, 1)
            XCTAssertEqual(split.titlebarTabsController.view.alphaValue, 1)
            let selected = mode == .verticalSidebar
                ? split.verticalTabsViewController.tabItemView(for: sessionID)
                : split.titlebarTabsController.tabItemView(for: sessionID)
            XCTAssertEqual(try XCTUnwrap(selected).alphaValue, 1)
            for _ in 0..<2 {
                let actualItems = mode == .verticalSidebar
                    ? split.verticalTabsViewController.presentationItems()
                    : split.titlebarTabsController.presentationItems()
                for (id, target) in planned {
                    let item = try XCTUnwrap(actualItems.first { $0.id == id }?.view)
                    let visible = item.visibleRect.intersection(item.bounds)
                    let frame = overlay.convertFromScreen(window.convertToScreen(item.convert(visible, to: nil)))
                    XCTAssertEqual(frame.minX, target.minX, accuracy: 0.5)
                    XCTAssertEqual(frame.minY, target.minY, accuracy: 0.5)
                    XCTAssertEqual(frame.width, target.width, accuracy: 0.5)
                    XCTAssertEqual(frame.height, target.height, accuracy: 0.5)
                }
                settle(window, duration: 0.06)
            }
        }

        // Divider gestures can finish their native layout before notifying the
        // store. That synchronous entry point must also complete the handoff.
        button.performClick(nil)
        settle(window, duration: 0.5)
        let tabsItem = try XCTUnwrap(split.splitViewItems.first {
            $0.viewController === split.verticalTabsViewController
        })
        tabsItem.isCollapsed = false
        store.setLeftSidebarVisible(true, in: controller.windowID)
        settle(window, duration: 0.4)
        XCTAssertFalse(window.childWindows?.contains {
            $0.identifier?.rawValue == "tabPresentationTransfer"
        } == true)
        XCTAssertEqual(split.verticalTabsViewController.view.alphaValue, 1)
        XCTAssertEqual(split.titlebarTabsController.view.alphaValue, 1)
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

    func testAnimatedChromeResizeDefersFitAndPositionWritebackUntilFinalReflow() throws {
        for mode in [ReaderScaleMode.manual, .fitWidth, .fitHeight, .fitTextWidth] {
            _ = NSApplication.shared
            let store = makeIsolatedDocumentStore()
            let session = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
                named: "animated-chrome-\(mode.rawValue)",
                pages: Array(repeating: "Sidebar animation preserves the current reading position.", count: 3)
            ))
            store.setDisplayMode(.singlePageContinuous, for: session.id)
            store.setScaleMode(mode, scaleFactor: 1.25, for: session.id)
            let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
            reader.targetSessionID = session.id
            reader.loadViewIfNeeded()
            reader.view.frame = NSRect(x: 0, y: 0, width: 800, height: 650)
            reader.view.layoutSubtreeIfNeeded()
            _ = reader.go(to: ReadingPosition(pageIndex: 1, point: NSPoint(x: 0, y: 650)))
            reader.testingFlushReadingPositionWriteback()
            let document = try XCTUnwrap(reader.pdfView.document)
            let page = try XCTUnwrap(document.page(at: 1))
            let anchor = reader.pdfView.convert(
                NSPoint(x: reader.pdfView.bounds.midX, y: reader.pdfView.bounds.midY), to: page
            )
            let position = store.session(for: session.id)?.lastReadPosition
            let scale = reader.pdfView.scaleFactor

            reader.prepareForChromeSizeChange(animated: true)
            reader.view.frame.size.width = 650
            reader.view.layoutSubtreeIfNeeded()
            reader.reflowForContainerSizeChange()
            reader.testingFlushReadingPositionWriteback()
            XCTAssertTrue(reader.testingIsAnimatingChromeSizeChange)
            XCTAssertEqual(store.session(for: session.id)?.lastReadPosition, position)
            XCTAssertEqual(reader.pdfView.scaleFactor, scale, accuracy: 0.001)
            reader.view.frame.size.width = 800
            reader.reflowForContainerSizeChange(completesChromeAnimation: true)
            XCTAssertFalse(reader.testingIsAnimatingChromeSizeChange)

            let restoredAnchor = reader.pdfView.convert(
                NSPoint(x: reader.pdfView.bounds.midX, y: reader.pdfView.bounds.midY), to: page
            )
            XCTAssertEqual(store.session(for: session.id)?.scaleMode, mode)
            XCTAssertEqual(reader.pdfView.scaleFactor, scale, accuracy: 0.001)
            XCTAssertEqual(restoredAnchor.x, anchor.x, accuracy: 2)
            XCTAssertEqual(restoredAnchor.y, anchor.y, accuracy: 2)
        }
    }

    func testSwitchingToSplitSpaceDuringSidebarAnimationPreservesBothDocuments() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Requires sidebar animation to exercise the overlapping Space transition")
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let original = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "chrome-original-space", pageCount: 5
        ))
        let originalSpace = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let splitSpace = try XCTUnwrap(store.createWorkspace(name: "Compare", in: windowID))
        let first = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "chrome-split-first", pageCount: 5
        ), in: windowID)
        let secondURL = try TestPDFFixtures.makeBlankPDF(named: "chrome-split-second", pageCount: 5)
        let secondPane = try XCTUnwrap(store.splitPane(
            from: .primary, layout: .sideBySide, documentAt: secondURL, in: windowID
        ))
        let secondID = try XCTUnwrap(store.displayedSessionID(for: secondPane, in: windowID))
        for (sessionID, pageIndex, mode) in [
            (first.id, 1, ReaderScaleMode.fitWidth), (secondID, 3, .manual),
        ] {
            store.setDisplayMode(.singlePage, for: sessionID)
            store.setScaleMode(mode, scaleFactor: 1.4, for: sessionID)
            store.updateReadingPosition(
                ReadingPosition(pageIndex: pageIndex, point: NSPoint(x: 0, y: 260)),
                scaleFactor: 1.4, for: sessionID
            )
        }
        let splitLayout = store.readerLayout(in: windowID)
        store.activateWorkspace(originalSpace, in: windowID)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1200, height: 700))
        controller.showWindow(nil)
        settle(window)
        let split = try XCTUnwrap(window.contentViewController as? SplitViewController)
        let workspace = split.readerWorkspaceViewController
        let originalReader = try XCTUnwrap(workspace.readerViewController(for: .primary))
        let button = try XCTUnwrap(window.toolbar?.items.first?.view as? NSButton)
        controller.flushPendingReadingPositions()
        let originalPosition = store.session(for: original.id)?.lastReadPosition

        button.performClick(nil)
        XCTAssertTrue(split.testingIsApplyingChromeLayout)
        store.activateWorkspace(splitSpace, in: windowID)
        XCTAssertTrue(originalReader.testingIsAnimatingChromeSizeChange)
        XCTAssertTrue(waitForChromeLayout(in: window))

        XCTAssertEqual(store.readerLayout(in: windowID), splitLayout)
        XCTAssertEqual(workspace.allReaderViewControllers.count, 2)
        for (pane, sessionID, pageIndex, mode) in [
            (ReaderPane.primary, first.id, 1, ReaderScaleMode.fitWidth),
            (secondPane, secondID, 3, .manual),
        ] {
            let reader = try XCTUnwrap(workspace.readerViewController(for: pane))
            let document = try XCTUnwrap(reader.pdfView.document)
            XCTAssertEqual(reader.targetSessionID, sessionID)
            XCTAssertEqual(reader.pdfView.currentPage.map { document.index(for: $0) }, pageIndex)
            XCTAssertEqual(store.session(for: sessionID)?.scaleMode, mode)
            XCTAssertFalse(reader.testingIsAnimatingChromeSizeChange)
            XCTAssertGreaterThan(reader.pdfView.bounds.width, 100)
        }
        XCTAssertEqual(store.session(for: original.id)?.lastReadPosition, originalPosition)

        // A second complete toggle verifies that the reused and newly created
        // readers still accept geometry changes after the Space transition.
        button.performClick(nil)
        XCTAssertTrue(waitForChromeLayout(in: window))
        XCTAssertEqual(store.readerLayout(in: windowID), splitLayout)
        XCTAssertEqual(store.session(for: first.id)?.scaleMode, .fitWidth)
        XCTAssertEqual(store.session(for: secondID)?.scaleMode, .manual)
        XCTAssertTrue(workspace.allReaderViewControllers.allSatisfy {
            !$0.testingIsAnimatingChromeSizeChange
        })
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

    private func settle(_ window: NSWindow, duration: TimeInterval = 0.05) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
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
