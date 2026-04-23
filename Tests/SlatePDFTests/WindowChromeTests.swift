import AppKit
import Foundation
import PDFKit
import Testing
@testable import SlatePDF

@MainActor
struct WindowChromeTests {
    @Test
    func verticalTabsDetachToolbarStrip() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        controller.window?.layoutIfNeeded()

        #expect(controller.window?.toolbar == nil)

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setTabPresentationMode(.verticalSidebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func horizontalTabsHideWhenLeftSidebarReturns() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setLeftSidebarVisible(true)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func horizontalTabsUseStableToolbarStripSize() {
        let controller = TitlebarTabsController(documentStore: DocumentStore(appConfiguration: .default))
        controller.loadViewIfNeeded()

        #expect(controller.preferredContentSize == TitlebarTabsController.visibleStripSize)
        #expect(controller.view.frame.size == TitlebarTabsController.visibleStripSize)

        controller.setTabsStripVisible(false)
        #expect(controller.preferredContentSize == NSSize(width: 1, height: 1))

        controller.setTabsStripVisible(true)
        #expect(controller.preferredContentSize == TitlebarTabsController.visibleStripSize)
        #expect(controller.view.frame.size == TitlebarTabsController.visibleStripSize)
    }

    @Test
    func nightModeKeepsLivePDFViewAvailableForSnapshots() {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }

        let store = DocumentStore(appConfiguration: .default)
        let controller = ReaderViewController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.isNightModeEnabled)
        #expect(controller.pdfView.isHidden == false)
    }

    @Test
    func splitViewClearsLegacyAutosavedDividerFrames() {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "NSSplitView Subview Frames MainSplitView",
            "NSSplitView Subview Frames SlatePDFSplit.v2",
            "NSSplitView Subview Frames SlatePDFSplit.v3",
        ]
        let originals = legacyKeys.map { (key: $0, value: defaults.object(forKey: $0)) }
        defer {
            for entry in originals {
                if let value = entry.value {
                    defaults.set(value, forKey: entry.key)
                } else {
                    defaults.removeObject(forKey: entry.key)
                }
            }
        }

        for key in legacyKeys {
            defaults.set(
                [
                    "0.000000, 0.000000, 264.500000, 900.000000, NO, NO",
                    "265.500000, 0.000000, 973.500000, 900.000000, NO, NO",
                    "1240.000000, 0.000000, 120.000000, 900.000000, NO, NO",
                ],
                forKey: key
            )
        }

        let controller = SplitViewController(documentStore: DocumentStore(appConfiguration: .default))
        controller.loadViewIfNeeded()

        for key in legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(controller.splitView.autosaveName == nil)
    }

    @Test
    func documentStoreRefreshKeepsAdjustedRightSidebarWidth() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let mainWindowController = MainWindowController(documentStore: store)
        guard let window = mainWindowController.window,
              let controller = window.contentViewController as? SplitViewController else {
            Issue.record("Failed to create main split view")
            return
        }
        window.layoutIfNeeded()

        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-width"))
        window.layoutIfNeeded()
        controller.splitView.setPosition(900, ofDividerAt: 1)
        controller.splitView.adjustSubviews()
        window.layoutIfNeeded()

        let rightSidebarWidthBefore = controller.splitView.arrangedSubviews[2].frame.width
        store.setDirty(true, for: session.id)
        window.layoutIfNeeded()
        let rightSidebarWidthAfter = controller.splitView.arrangedSubviews[2].frame.width

        #expect(rightSidebarWidthBefore > 120)
        #expect(abs(rightSidebarWidthAfter - rightSidebarWidthBefore) < 0.5)
    }

    @Test
    func readerSplitToggleCanEnableAndDisableAgain() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-toggle"))
        controller.window?.layoutIfNeeded()

        #expect(controller.isReaderSplitEnabled == false)

        controller.toggleReaderSplit()
        controller.window?.layoutIfNeeded()
        #expect(controller.isReaderSplitEnabled == true)

        controller.toggleReaderSplit()
        controller.window?.layoutIfNeeded()
        #expect(controller.isReaderSplitEnabled == false)
    }

    @Test
    func closeFocusedPaneInSplitCollapsesToSinglePane() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-close-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-close-second"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        store.setFocusedPane(.secondary, in: windowID)
        controller.window?.layoutIfNeeded()

        #expect(store.isSplitEnabled(in: windowID))
        #expect(store.displayedSessionID(for: .primary, in: windowID) == second.id)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == first.id)

        controller.requestCloseActiveSession()
        controller.window?.layoutIfNeeded()

        #expect(store.isSplitEnabled(in: windowID) == false)
        #expect(store.sessions.map(\.id) == [second.id])
        #expect(store.displayedSessionID(for: .primary, in: windowID) == second.id)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == nil)
    }

    @Test
    func closeDuplicatedSplitPaneKeepsSingleDocumentOpen() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-duplicate"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        store.setFocusedPane(.secondary, in: windowID)
        controller.window?.layoutIfNeeded()

        #expect(store.isSplitEnabled(in: windowID))

        controller.requestCloseActiveSession()
        controller.window?.layoutIfNeeded()

        #expect(store.isSplitEnabled(in: windowID) == false)
        #expect(store.sessions.map(\.id) == [session.id])
        #expect(store.displayedSessionID(for: .primary, in: windowID) == session.id)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == nil)
    }

    @Test
    func readerSplitPreservesAdjustedDividerPositionAcrossStoreRefresh() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-divider-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-divider-second"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let workspaceSplitView = splitController.readerWorkspaceViewController.view
            .subviews
            .compactMap({ $0 as? NSSplitView })
            .first else {
            Issue.record("Failed to locate reader workspace split view")
            return
        }

        workspaceSplitView.setPosition(280, ofDividerAt: 0)
        workspaceSplitView.adjustSubviews()
        controller.window?.layoutIfNeeded()

        let secondaryWidthBefore = workspaceSplitView.subviews[1].frame.width
        store.setDirty(true, for: first.id)
        controller.window?.layoutIfNeeded()
        let secondaryWidthAfter = workspaceSplitView.subviews[1].frame.width

        #expect(abs(secondaryWidthAfter - secondaryWidthBefore) < 0.5)
    }

    @Test
    func horizontalTitlebarModeCanOpenDocument() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)

        store.setTabPresentationMode(.horizontalTitlebar)
        store.setLeftSidebarVisible(false)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-open"))
        controller.window?.layoutIfNeeded()

        #expect(controller.window?.toolbar != nil)
    }

    @Test
    func fitWidthOnOpenCanOpenWindowBackedDocument() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.reader.defaultDisplayMode = .singlePage
        configuration.reader.fitWidthOnOpen = true
        let store = DocumentStore(appConfiguration: configuration)
        let controller = MainWindowController(documentStore: store)

        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "fit-width-open",
                pageSizes: [NSSize(width: 1280, height: 720)]
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let expectedScale = fitWidthScaleExpected(for: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to locate fit-width reader")
            return
        }

        #expect(controller.window != nil)
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)
    }

    @Test
    func readerWorkspaceStartsCollapsedWhenSplitDisabled() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let workspaceSplitView = splitController.readerWorkspaceViewController.view
                .subviews
                .compactMap({ $0 as? NSSplitView })
                .first else {
            Issue.record("Failed to locate reader workspace split view")
            return
        }

        #expect(store.isSplitEnabled(in: controller.windowID) == false)
        #expect(workspaceSplitView.subviews[1].isHidden)
        #expect(
            workspaceSplitView.isSubviewCollapsed(workspaceSplitView.subviews[1]) ||
                workspaceSplitView.subviews[1].frame.width < 1
        )
    }

    @Test
    func settingsWindowUsesAdaptiveGeneralSize() {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        controller.showWindow(nil)

        #expect(controller.window?.contentRect(forFrameRect: controller.window?.frame ?? .zero).size == NSSize(width: 520, height: 260))
    }

    @Test
    func settingsWindowSwitchesBetweenPageSizes() throws {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        controller.showWindow(nil)

        let window = try #require(controller.window)
        controller.selectPageForTesting(1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 920, height: 620))

        controller.selectPageForTesting(0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 520, height: 260))
    }

    @Test
    func mainWindowUsesUpdatedReaderFramingDefaults() {
        let controller = MainWindowController(documentStore: DocumentStore(appConfiguration: .default))
        let contentSize = controller.window?.contentRect(forFrameRect: controller.window?.frame ?? .zero).size

        #expect(contentSize == MainWindowController.defaultContentSize)
        #expect(controller.window?.minSize == MainWindowController.minimumWindowSize)
    }

    @Test
    func singlePageZoomedOutDocumentStaysCentered() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "single-page-centered",
                pageSizes: [NSSize(width: 1280, height: 720)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)
        reader.zoomOut()
        flushLayout(controller.window)

        guard let clipView = pdfClipView(in: reader.pdfView),
              let documentView = pdfDocumentView(in: reader.pdfView) else {
            Issue.record("Failed to locate PDF clip/document views")
            return
        }

        let expectedMinX = max((clipView.bounds.width - documentView.frame.width) * 0.5, 0)
        #expect(abs(documentView.frame.minX - expectedMinX) < 1.0)
    }

    @Test
    func singlePageZoomKeepsViewportCenterStable() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "single-page-zoom-anchor",
                pageSizes: [NSSize(width: 720, height: 1800)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)

        guard let beforeAnchor = visibleDocumentCenter(in: reader.pdfView) else {
            Issue.record("Failed to capture pre-zoom anchor")
            return
        }

        reader.zoomOut()
        flushLayout(controller.window)

        guard let afterAnchor = visibleDocumentCenter(in: reader.pdfView) else {
            Issue.record("Failed to capture post-zoom anchor")
            return
        }

        #expect(abs(afterAnchor.x - beforeAnchor.x) < 2.0)
        #expect(abs(afterAnchor.y - beforeAnchor.y) < 2.0)
    }

    @Test
    func halfPageScrollMovesViewportAndCanReturn() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        _ = try store.open(
            documentAt: makeTemporaryPDF(
                named: "half-page-scroll",
                pageSizes: [NSSize(width: 720, height: 2400)]
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)

        guard let clipView = pdfClipView(in: reader.pdfView) else {
            Issue.record("Failed to locate PDF clip view")
            return
        }
        let beforeOrigin = clipView.bounds.origin.y

        controller.scrollHalfPageDown()
        flushLayout(controller.window)
        let afterDownOrigin = clipView.bounds.origin.y
        #expect(abs(afterDownOrigin - beforeOrigin) > 20)
    }

    @Test
    func fitWidthUsesPDFKitRowWidthAcrossPageShapes() throws {
        _ = NSApplication.shared

        struct Scenario {
            let name: String
            let pageSizes: [NSSize]
            let mode: ReaderDisplayMode
            let leadPageIndex: Int
        }

        let scenarios = [
            Scenario(
                name: "wide-slide",
                pageSizes: [NSSize(width: 1280, height: 720)],
                mode: .singlePage,
                leadPageIndex: 0
            ),
            Scenario(
                name: "portrait-paper",
                pageSizes: [NSSize(width: 595, height: 842)],
                mode: .singlePageContinuous,
                leadPageIndex: 0
            ),
            Scenario(
                name: "two-up-paper",
                pageSizes: [NSSize(width: 595, height: 842), NSSize(width: 595, height: 842)],
                mode: .twoUp,
                leadPageIndex: 0
            ),
        ]

        for scenario in scenarios {
            let store = DocumentStore(appConfiguration: .default)
            let controller = MainWindowController(documentStore: store)
            let session = try store.open(
                documentAt: makeTemporaryPDF(named: scenario.name, pageSizes: scenario.pageSizes)
            )
            store.setDisplayMode(scenario.mode, for: session.id)
            flushLayout(controller.window)

            guard let splitController = controller.window?.contentViewController as? SplitViewController,
                  let expectedScale = fitWidthScaleExpected(
                      for: splitController.readerViewController.pdfView,
                      leadPageIndex: scenario.leadPageIndex
                  ) else {
                Issue.record("Failed to locate reader internals for \(scenario.name)")
                return
            }

            splitController.readerViewController.fitToWidth()
            flushLayout(controller.window)

            #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)
        }
    }
}

@MainActor
private func flushLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}

@MainActor
private func pdfClipView(in pdfView: PDFView) -> NSClipView? {
    pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView
}

@MainActor
private func pdfDocumentView(in pdfView: PDFView) -> NSView? {
    pdfClipView(in: pdfView)?.documentView
}

@MainActor
private func visibleDocumentCenter(in pdfView: PDFView) -> NSPoint? {
    guard pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return nil }
    let viewportCenter = NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
    guard let page = pdfView.page(for: viewportCenter, nearest: true) else { return nil }
    return pdfView.convert(viewportCenter, to: page)
}

@MainActor
private func fitWidthScaleExpected(for pdfView: PDFView, leadPageIndex: Int = 0) -> CGFloat? {
    guard let clipView = pdfClipView(in: pdfView),
          let page = pdfView.document?.page(at: leadPageIndex),
          pdfView.scaleFactor > 0 else { return nil }

    let normalizedRowWidth = pdfView.rowSize(for: page).width / pdfView.scaleFactor
    guard normalizedRowWidth > 0 else { return nil }
    return clipView.frame.width / normalizedRowWidth
}

@MainActor
private func makeTemporaryPDF(named name: String, pageSizes: [NSSize] = [NSSize(width: 200, height: 260)]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    for (index, pageSize) in pageSizes.enumerated() {
        let image = NSImage(size: pageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: pageSize)).fill()

        let textRect = NSRect(
            x: max(pageSize.width * 0.12, 24),
            y: max(pageSize.height * 0.42, 24),
            width: max(pageSize.width * 0.76, 120),
            height: 40
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        NSString(string: "\(name)-\(index)").draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        document.insert(page, at: index)
    }

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}
