import AppKit
import Foundation
import IOKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct WindowChromeTests {
    @Test
    func mainWindowDoesNotUseAppKitStateRestoration() {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: makeIsolatedDocumentStore())
        defer { controller.close() }

        #expect(controller.window?.isRestorable == false)
    }

    @Test
    func mainWindowTitleResetsForBlankTab() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "window-title-blank-anchor"))

        _ = store.newBlankTab()

        #expect(controller.window?.title == "Serein")
        #expect(controller.window?.representedURL == nil)
        #expect(controller.window?.representedFilename == "")
    }

    @Test
    func mainWindowTitleUpdatesWhenTabsSwitch() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "window-title-first"))
        #expect(controller.window?.title == first.title)
        #expect(controller.window?.representedURL == first.url)
        #expect(controller.window?.representedFilename == first.url.path)
        let second = try store.open(documentAt: makeTemporaryPDF(named: "window-title-second"))

        #expect(controller.window?.title == second.title)
        #expect(controller.window?.representedURL == second.url)
        #expect(controller.window?.representedFilename == second.url.path)
        store.activate(sessionID: first.id, in: store.defaultWindowID)
        #expect(controller.window?.title == first.title)
        #expect(controller.window?.representedURL == first.url)
        #expect(controller.window?.representedFilename == first.url.path)
        store.activate(sessionID: second.id, in: store.defaultWindowID)
        #expect(controller.window?.title == second.title)
        #expect(controller.window?.representedURL == second.url)
        #expect(controller.window?.representedFilename == second.url.path)
    }

    @Test
    func representedDocumentURLsStayIsolatedPerWindow() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let firstWindowID = store.defaultWindowID
        let first = try store.open(
            documentAt: makeTemporaryPDF(named: "represented-url-first-window"),
            in: firstWindowID
        )
        let secondWindowID = store.createWindow(copyingFrom: firstWindowID)
        let second = try store.open(
            documentAt: makeTemporaryPDF(named: "represented-url-second-window"),
            in: secondWindowID
        )
        let firstController = MainWindowController(documentStore: store, windowID: firstWindowID)
        let secondController = MainWindowController(documentStore: store, windowID: secondWindowID)
        defer {
            secondController.close()
            firstController.close()
        }

        #expect(firstController.window?.representedURL == first.url)
        #expect(firstController.window?.representedFilename == first.url.path)
        #expect(secondController.window?.representedURL == second.url)
        #expect(secondController.window?.representedFilename == second.url.path)

        _ = store.newBlankTab(in: secondWindowID)

        #expect(firstController.window?.representedURL == first.url)
        #expect(firstController.window?.representedFilename == first.url.path)
        #expect(secondController.window?.representedURL == nil)
        #expect(secondController.window?.representedFilename == "")
    }

    @Test
    func verticalTabsDetachToolbarStrip() {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        controller.window?.layoutIfNeeded()

        #expect(controller.window?.toolbar == nil)

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)

        _ = store.newBlankTab()
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setTabPresentationMode(.verticalSidebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func horizontalTabsHideWhenLeftSidebarReturns() {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = store.newBlankTab()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setLeftSidebarVisible(true)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func horizontalTabsUseAdaptiveToolbarStripSize() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "short"))
        let controller = TitlebarTabsController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.preferredContentSize.width < TitlebarTabsController.maximumVisibleStripSize.width)
        #expect(controller.preferredContentSize.height == TitlebarTabsController.maximumVisibleStripSize.height)
        #expect(controller.view.frame.size == controller.preferredContentSize)
        #expect(controller.view.layer?.cornerRadius == 3)
        #expect(controller.view.layer?.backgroundColor != NSColor.clear.cgColor)

        let selectedTab = try #require(findDescendant(of: TitlebarTabItemView.self, in: controller.view))
        #expect(selectedTab.layer?.cornerRadius == controller.view.layer?.cornerRadius)
        #expect(selectedTab.intrinsicContentSize.height == controller.view.frame.height)

        controller.setTabsStripVisible(false)
        #expect(controller.preferredContentSize == NSSize(width: 1, height: 1))

        controller.setTabsStripVisible(true)
        #expect(controller.preferredContentSize.width < TitlebarTabsController.maximumVisibleStripSize.width)
        #expect(controller.view.frame.size == controller.preferredContentSize)
    }

    @Test
    func titlebarTabsMoveDroppedPDFToExistingWindow() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let sourceAnchor = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-drag-source-anchor"))
        let moved = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-drag-moved"))
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)
        let destinationAnchor = try store.open(
            documentAt: makeTemporaryPDF(named: "titlebar-drag-destination-anchor"),
            in: destinationWindowID
        )
        let controller = TitlebarTabsController(
            documentStore: store,
            windowID: destinationWindowID
        )
        controller.loadViewIfNeeded()

        #expect(
            controller.testingMoveTab(
                TabDragPayload(sourceWindowID: sourceWindowID, sessionID: moved.id)
            )
        )
        #expect(store.sessions(in: sourceWindowID).map(\.id) == [sourceAnchor.id])
        #expect(
            store.sessions(in: destinationWindowID).map(\.id) ==
                [destinationAnchor.id, moved.id]
        )
        #expect(store.activeSessionID(in: destinationWindowID) == moved.id)
    }

    @Test
    func titlebarPDFTabUsesDragSourceAsPrimaryHitTarget() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-drag-hit-target"))
        let controller = TitlebarTabsController(documentStore: store)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.testingTabDragSourceHitTargets == [true])
    }

    @Test
    func stackedTitlebarTabsStayClickableAwayFromOrigin() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        store.setTabPresentationMode(.horizontalTitlebar)
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-hit-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-hit-second"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-hit-third"))
        let controller = TitlebarTabsController(documentStore: store)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 36)
        controller.view.layoutSubtreeIfNeeded()

        let tabItems = findAllDescendants(of: TitlebarTabItemView.self, in: controller.view)
        #expect(tabItems.count == 3)
        #expect((tabItems.map(\.frame.minX).max() ?? 0) > (tabItems.map(\.frame.minX).min() ?? 0))
        #expect(controller.testingTabDragSourceHitTargets == [true, true, true])

        for tabItem in tabItems {
            let pointInContainer = tabItem.convert(
                NSPoint(x: tabItem.bounds.midX, y: tabItem.bounds.midY),
                to: controller.view
            )
            #expect(
                controller.view.hitTest(pointInContainer) is TabDragSourceButton,
                "tab frame \(tabItem.frame) should hit the select button"
            )
        }
    }

    @Test
    func transparentTitlebarDragAreaIsReservedBeforePDFContent() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: makeIsolatedDocumentStore())
        defer { controller.close() }
        let window = try #require(controller.window as? ReaderShortcutWindow)
        let contentView = try #require(window.contentView)
        window.layoutIfNeeded()

        #expect(window.toolbar == nil)
        #expect(window.contentLayoutRect.maxY < contentView.bounds.maxY)

        let titlebarPoint = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 2)
        let readerPoint = NSPoint(x: contentView.bounds.midX, y: window.contentLayoutRect.maxY - 2)

        #expect(window.shouldHandleTransparentTitlebarDrag(with: mouseDownEvent(in: window, at: titlebarPoint)))
        #expect(window.shouldHandleTransparentTitlebarDrag(with: mouseDownEvent(in: window, at: readerPoint)) == false)
    }

    @Test
    func transparentTitlebarDragDoesNotStealWindowControlsOrTitlebarTabs() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = store.newBlankTab()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let window = try #require(controller.window as? ReaderShortcutWindow)
        let contentView = try #require(window.contentView)
        window.layoutIfNeeded()

        let closeButton = try #require(window.standardWindowButton(.closeButton))
        let closeButtonFrame = closeButton.convert(closeButton.bounds, to: nil)
        let closeButtonPoint = NSPoint(x: closeButtonFrame.midX, y: closeButtonFrame.midY)
        #expect(window.shouldHandleTransparentTitlebarDrag(with: mouseDownEvent(in: window, at: closeButtonPoint)) == false)

        store.setTabPresentationMode(.horizontalTitlebar)
        store.setLeftSidebarVisible(false)
        window.layoutIfNeeded()

        #expect(window.toolbar != nil)
        let titlebarPoint = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 2)
        #expect(window.shouldHandleTransparentTitlebarDrag(with: mouseDownEvent(in: window, at: titlebarPoint)) == false)
    }

    @Test
    func leftCommandNumberActivatesTabInOwningWindowOrderIncludingBlankTabs() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let firstWindowID = store.defaultWindowID
        let firstWindowSession = try store.open(
            documentAt: makeTemporaryPDF(named: "numbered-tab-first-window"),
            in: firstWindowID
        )
        let secondWindowID = store.createWindow(copyingFrom: firstWindowID)
        _ = try store.open(
            documentAt: makeTemporaryPDF(named: "numbered-tab-second-window-first"),
            in: secondWindowID
        )
        let blankSession = store.newBlankTab(in: secondWindowID)
        _ = try store.open(
            documentAt: makeTemporaryPDF(named: "numbered-tab-second-window-third"),
            in: secondWindowID
        )
        store.updateSearch(query: "query", scope: .currentDocument, in: secondWindowID)

        let firstController = MainWindowController(documentStore: store, windowID: firstWindowID)
        let secondController = MainWindowController(documentStore: store, windowID: secondWindowID)
        defer {
            secondController.close()
            firstController.close()
        }
        let secondWindow = try #require(secondController.window as? ReaderShortcutWindow)

        #expect(
            secondWindow.performKeyEquivalent(
                with: physicalCommandNumberEvent(2, in: secondWindow, left: true)
            )
        )
        #expect(store.activeSessionID(in: secondWindowID) == blankSession.id)
        #expect(store.selectedSessionIDs(in: secondWindowID) == [blankSession.id])
        #expect(store.searchQuery(in: secondWindowID).isEmpty)
        #expect(store.activeSessionID(in: firstWindowID) == firstWindowSession.id)
    }

    @Test
    func nightModeKeepsLivePDFViewAvailableForSnapshots() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }

        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeTemporaryPDF(named: "night-mode-live-pdf"))
        let controller = ReaderViewController(documentStore: store)
        controller.targetSessionID = session.id
        controller.loadViewIfNeeded()

        #expect(controller.isNightModeEnabled)
        #expect(controller.pdfView.isHidden == false)
    }

    @Test
    func nightModeShortcutUsesOnlyRuntimeAppearanceOverride() {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = previousAppearance }

        let delegate = AppDelegate()
        let persistentMode = delegate.persistentAppearanceMode

        #expect(delegate.temporaryAppearanceMode == nil)
        delegate.toggleNightMode(nil)
        #expect(delegate.temporaryAppearanceMode == .dark)
        #expect(delegate.persistentAppearanceMode == persistentMode)
        #expect(app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        delegate.toggleNightMode(nil)
        #expect(delegate.temporaryAppearanceMode == nil)
        #expect(delegate.persistentAppearanceMode == persistentMode)
    }

    @Test
    func readerHidesPDFKitDocumentTreeFromAccessibilityInspection() {
        _ = NSApplication.shared
        let controller = ReaderViewController(documentStore: makeIsolatedDocumentStore())
        controller.loadViewIfNeeded()

        #expect(controller.pdfView.isAccessibilityElement() == false)
        #expect(controller.pdfView.accessibilityChildren()?.isEmpty == true)
    }

    @Test
    func readingFocusOnlyRunsForLivePDFContent() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = ReaderViewController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.testingReadingFocusIsEnabled == false)

        let session = try store.open(
            documentAt: makeTemporaryPDF(named: "reading-focus-live-pdf")
        )
        controller.targetSessionID = session.id
        #expect(controller.testingReadingFocusIsEnabled == false)

        controller.setReadingFocusModeEnabled(true)
        #expect(controller.testingReadingFocusIsEnabled)

        controller.setAllPagesOverviewActive(true)
        #expect(controller.testingReadingFocusIsEnabled == false)
        #expect(controller.testingOverviewRetainsDocument)

        controller.setAllPagesOverviewActive(false)
        #expect(controller.testingReadingFocusIsEnabled)
        #expect(controller.testingOverviewRetainsDocument == false)

        controller.setReadingFocusModeEnabled(false)
        #expect(controller.testingReadingFocusIsEnabled == false)
    }

    @Test
    func readingFocusModeIsWindowLocalAndSynchronizesSplitReaders() {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let firstWorkspace = ReaderWorkspaceViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        firstWorkspace.loadViewIfNeeded()
        let secondWindowID = store.createWindow()
        let secondWorkspace = ReaderWorkspaceViewController(
            documentStore: store,
            windowID: secondWindowID
        )
        secondWorkspace.loadViewIfNeeded()

        #expect(firstWorkspace.isReadingFocusModeEnabled == false)
        #expect(secondWorkspace.isReadingFocusModeEnabled == false)

        #expect(firstWorkspace.toggleReadingFocusMode())
        #expect(firstWorkspace.primaryReaderViewController.testingReadingFocusModeIsEnabled)
        #expect(firstWorkspace.secondaryReaderViewController.testingReadingFocusModeIsEnabled)
        #expect(secondWorkspace.isReadingFocusModeEnabled == false)

        #expect(firstWorkspace.toggleReadingFocusMode() == false)
        #expect(firstWorkspace.primaryReaderViewController.testingReadingFocusModeIsEnabled == false)
        #expect(firstWorkspace.secondaryReaderViewController.testingReadingFocusModeIsEnabled == false)
    }

    @Test
    func readingFocusSizeUsesWindowOverrideAndCanResetToGlobalDefaults() {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.reader.readingFocus = ReadingFocusSettings(
            widthMode: .page,
            customWidthRatio: 0.72,
            height: 96
        )
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let workspace = ReaderWorkspaceViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        workspace.loadViewIfNeeded()

        let temporarySettings = ReadingFocusSettings(
            widthMode: .column,
            customWidthRatio: 0.6,
            height: 120
        )
        workspace.setReadingFocusSettings(temporarySettings)

        #expect(workspace.readingFocusSettings == temporarySettings)
        #expect(workspace.primaryReaderViewController.readingFocusSettings == temporarySettings)
        #expect(workspace.secondaryReaderViewController.readingFocusSettings == temporarySettings)

        configuration.reader.readingFocus = ReadingFocusSettings(
            widthMode: .custom,
            customWidthRatio: 0.8,
            height: 144
        )
        store.updateAppConfiguration(configuration)
        #expect(workspace.readingFocusSettings == temporarySettings)

        workspace.resetReadingFocusSettings()
        #expect(workspace.readingFocusSettings == configuration.reader.readingFocus)
        #expect(workspace.primaryReaderViewController.readingFocusSettings == configuration.reader.readingFocus)
        #expect(workspace.secondaryReaderViewController.readingFocusSettings == configuration.reader.readingFocus)
    }

    @Test
    func highlightModeUsesCompactInlineIndicator() {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = ReaderViewController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.triggerAnnotationShortcut(.highlight) == false)
        controller.view.layoutSubtreeIfNeeded()

        let highlightLabels = findAllDescendants(of: NSTextField.self, in: controller.view)
            .filter { $0.stringValue.contains("Highlight") }
            .map(\.stringValue)

        #expect(highlightLabels.contains("Highlight · Esc"))
        #expect(highlightLabels.contains { $0.contains("Highlight Mode") } == false)
    }

    @Test
    func switchingPDFShowsBriefFileNameToast() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }

        _ = try store.open(documentAt: makeTemporaryPDF(named: "switch-toast-first"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate reader internals")
            return
        }

        let reader = splitController.readerViewController
        #expect(reader.testingSwitchTitleToastIsVisible == false)

        let second = try store.open(documentAt: makeTemporaryPDF(named: "switch-toast-second"))
        flushLayout(controller.window)

        #expect(reader.testingSwitchTitleToastTitle == second.title)
        #expect(reader.testingSwitchTitleToastIsVisible)
    }

    @Test
    func nightModeUsesSidebarPDFBackgroundOutsideFilteredContent() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }

        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "night-mode-background"))
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to create split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.pdfView.layoutDocumentView()
        reader.pdfView.layoutSubtreeIfNeeded()
        flushLayout(controller.window)

        #expect(reader.pdfView.displaysPageBreaks)
        #expect(reader.pdfView.pageShadowsEnabled == false)
        let pageBackground = resolvedColor(NightModeStyle.pageBackgroundColor, in: app.effectiveAppearance)
        if let layerColor = reader.pdfView.layer?.backgroundColor,
           let layerBackground = NSColor(cgColor: layerColor) {
            assertTransparent(layerBackground)
        } else {
            Issue.record("Failed to read PDFView layer background")
        }
        if let scrollView = reader.pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
            #expect(scrollView.drawsBackground == false)
            assertColor(scrollView.backgroundColor, matches: pageBackground)
            let backgroundViews = pdfScrollBackgroundViews(in: scrollView)
            for backgroundView in backgroundViews {
                #expect(backgroundView.isHidden)
            }
        }
        guard let clipView = pdfClipView(in: reader.pdfView) else {
            Issue.record("Failed to locate PDF clip view")
            return
        }
        #expect(clipView.drawsBackground == false)
        assertColor(clipView.backgroundColor, matches: pageBackground)
        if let readerBackground = reader.view.layer?.backgroundColor,
           let readerBackgroundColor = NSColor(cgColor: readerBackground) {
            assertColor(readerBackgroundColor, matches: pageBackground)
        } else {
            Issue.record("Failed to read reader background")
        }
    }

    @Test
    func appearanceTogglePreservesPageGeometryAndZoom() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        defer { app.appearance = previousAppearance }

        for mode in ReaderDisplayMode.allCases {
            for fitsWidth in [false, true] {
                app.appearance = NSAppearance(named: .aqua)
                let store = makeIsolatedDocumentStore()
                let controller = MainWindowController(documentStore: store)
                defer { controller.close() }
                let session = try store.open(documentAt: makeTemporaryPDF(
                    named: "theme-position",
                    pageSizes: Array(repeating: NSSize(width: 595, height: 842), count: 6)
                ))
                store.setDisplayMode(mode, for: session.id)
                let split = try #require(controller.window?.contentViewController as? SplitViewController)
                let reader = split.readerViewController
                flushLayout(controller.window)
                if fitsWidth {
                    reader.fitToWidth()
                } else {
                    store.setScaleMode(.manual, scaleFactor: 1.37, for: session.id)
                }
                #expect(reader.goToPage(2))
                flushLayout(controller.window)
                let page = try #require(reader.pdfView.currentPage)
                let bounds = page.bounds(for: reader.pdfView.displayBox)
                let point = NSPoint(x: bounds.midX, y: bounds.midY)
                let originalPoint = reader.pdfView.convert(point, from: page)
                let originalScale = reader.pdfView.scaleFactor

                for appearance in [NSAppearance.Name.darkAqua, .aqua, .darkAqua, .aqua] {
                    app.appearance = NSAppearance(named: appearance)
                    controller.refreshThemeAppearance()
                    reader.pdfView.layoutDocumentView()
                    flushLayout(controller.window)
                    let currentPoint = reader.pdfView.convert(point, from: page)
                    #expect(abs(currentPoint.x - originalPoint.x) < 0.1,
                            "Horizontal drift in \(mode), fit width: \(fitsWidth)")
                    #expect(abs(currentPoint.y - originalPoint.y) < 0.1,
                            "Vertical drift in \(mode), fit width: \(fitsWidth)")
                    #expect(abs(reader.pdfView.scaleFactor - originalScale) < 0.0001)
                }
            }
        }
    }

    @Test
    func switchingFromLightToDarkRetintsPDFMargins() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = previousAppearance }

        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "night-mode-transition"))
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to create split view controller")
            return
        }

        let reader = splitController.readerViewController
        app.appearance = NSAppearance(named: .darkAqua)
        controller.refreshThemeAppearance()
        reader.pdfView.layoutDocumentView()
        reader.pdfView.layoutSubtreeIfNeeded()
        flushLayout(controller.window)

        reader.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let pageBackground = NightModeStyle.pageBackgroundColor
            if let layerColor = reader.pdfView.layer?.backgroundColor,
               let layerBackground = NSColor(cgColor: layerColor) {
                assertTransparent(layerBackground)
            } else {
                Issue.record("Failed to read PDFView layer background after appearance switch")
            }

            if let scrollView = reader.pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
                #expect(scrollView.drawsBackground == false)
                assertColor(scrollView.backgroundColor, matches: pageBackground)
                let backgroundViews = pdfScrollBackgroundViews(in: scrollView)
                for backgroundView in backgroundViews {
                    #expect(backgroundView.isHidden)
                }
            } else {
                Issue.record("Failed to locate PDF scroll view after appearance switch")
            }

            #expect(pdfDocumentView(in: reader.pdfView) != nil)
        }
    }

    @Test
    func themeRefreshUpdatesReaderEvenWhenAppearanceModeStaysLight() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "theme-refresh-light"))
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to create split view controller")
            return
        }

        let reader = splitController.readerViewController
        guard let originalBackground = reader.view.layer?.backgroundColor,
              let originalColor = NSColor(cgColor: originalBackground) else {
            Issue.record("Failed to inspect original reader background color")
            return
        }

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        controller.refreshThemeAppearance()
        flushLayout(controller.window)

        guard let updatedBackground = reader.view.layer?.backgroundColor,
              let updatedColor = NSColor(cgColor: updatedBackground) else {
            Issue.record("Failed to inspect reader background colors")
            return
        }

        let originalSRGB = originalColor.usingColorSpace(.sRGB) ?? originalColor
        let updatedSRGB = updatedColor.usingColorSpace(.sRGB) ?? updatedColor

        #expect(abs(updatedSRGB.redComponent - originalSRGB.redComponent) > 0.01)
        #expect(reader.pdfView.displaysPageBreaks)
        #expect(reader.pdfView.pageShadowsEnabled == false)
        let leftMaterial = try #require(splitController.verticalTabsViewController.view as? SidebarMaterialView)
        let rightMaterial = try #require(splitController.rightSidebarViewController.view as? SidebarMaterialView)
        #expect(leftMaterial.material == .contentBackground)
        #expect(rightMaterial.material == .contentBackground)
        #expect(leftMaterial.blendingMode == .withinWindow)
        #expect(rightMaterial.blendingMode == .withinWindow)
        #expect(abs(leftMaterial.tintAlpha - 1) < 0.01)
        #expect(abs(rightMaterial.tintAlpha - 1) < 0.01)
        reader.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            assertColor(updatedColor, matches: NightModeStyle.readerBackdropColor)
            let pageBackground = NightModeStyle.pageBackgroundColor
            if let layerColor = reader.pdfView.layer?.backgroundColor,
               let layerBackground = NSColor(cgColor: layerColor) {
                assertTransparent(layerBackground)
            } else {
                Issue.record("Failed to read PDFView layer background for dawn theme")
            }
            if let scrollView = reader.pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
                #expect(scrollView.drawsBackground == false)
                assertColor(scrollView.backgroundColor, matches: pageBackground)
                let backgroundViews = pdfScrollBackgroundViews(in: scrollView)
                for backgroundView in backgroundViews {
                    #expect(backgroundView.isHidden)
                }
            } else {
                Issue.record("Failed to locate PDF scroll view for dawn theme")
            }
        }
    }

    @Test
    func themeRefreshUpdatesOutlineColorsWhenAppearanceModeStaysLight() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "theme-refresh-outline"))
        controller.window?.layoutIfNeeded()

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let titleLabel = splitController.rightSidebarViewController.outlineViewController.view.subviews
                .compactMap({ $0 as? NSTextField })
                .first(where: { $0.stringValue == "Outline" }) else {
            Issue.record("Failed to locate outline title label")
            return
        }

        guard let originalTextColor = titleLabel.textColor else {
            Issue.record("Failed to inspect original outline title color")
            return
        }
        let originalColor = resolvedColor(originalTextColor, in: titleLabel.effectiveAppearance)

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        controller.refreshThemeAppearance()
        flushLayout(controller.window)

        guard let updatedTextColor = titleLabel.textColor else {
            Issue.record("Failed to inspect updated outline title color")
            return
        }
        let updatedColor = resolvedColor(updatedTextColor, in: titleLabel.effectiveAppearance)
        #expect(abs(updatedColor.redComponent - originalColor.redComponent) > 0.01)
        titleLabel.effectiveAppearance.performAsCurrentDrawingAppearance {
            assertColor(updatedColor, matches: NightModeStyle.primaryTextColor)
        }
    }

    @Test
    func splitViewClearsLegacyAutosavedDividerFrames() {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "NSSplitView Subview Frames MainSplitView",
            "NSSplitView Subview Frames SereinSplit.v2",
            "NSSplitView Subview Frames SereinSplit.v3",
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

        let controller = SplitViewController(documentStore: makeIsolatedDocumentStore())
        controller.loadViewIfNeeded()

        for key in legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(controller.splitView.autosaveName == nil)
    }

    @Test
    func documentStoreRefreshKeepsAdjustedRightSidebarWidth() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let mainWindowController = MainWindowController(documentStore: store)
        defer { mainWindowController.close() }
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
    func sidebarToggleKeepsStoreVisibilityInSyncWithoutFlipFlop() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let preferredBaseline = store.sidebarWidths(in: store.defaultWindowID)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-toggle-stable"))
        prepareMainWindowForLayoutTests(controller)
        flushLayout(controller.window)

        let windowID = controller.windowID
        let sequence: [(Bool, Bool)] = [
            (false, true),
            (false, false),
            (true, false),
            (true, true),
            (false, true),
            (true, true),
        ]
        for (left, right) in sequence {
            store.setLeftSidebarVisible(left, in: windowID)
            store.setRightSidebarVisible(right, in: windowID)
            let splitController = try #require(controller.window?.contentViewController as? SplitViewController)
            #expect(waitForLayout(controller.window) {
                splitController.splitViewItems[0].isCollapsed == !left &&
                    splitController.splitViewItems[2].isCollapsed == !right
            })

            #expect(store.isLeftSidebarVisible(in: windowID) == left)
            #expect(store.isRightSidebarVisible(in: windowID) == right)
            #expect(splitController.splitViewItems[0].isCollapsed == !left)
            #expect(splitController.splitViewItems[2].isCollapsed == !right)

            // Programmatic toggles must never clobber preferred widths.
            #expect(store.sidebarWidths(in: windowID).left == preferredBaseline.left)
            #expect(store.sidebarWidths(in: windowID).right == preferredBaseline.right)
        }
    }

    @Test
    func sidebarToggleReflowsFitWidthPDF() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-toggle-fit-width"))
        store.setScaleMode(.fitWidth, scaleFactor: 1, for: session.id)
        controller.showWindow(nil)
        flushLayout(controller.window)

        let splitController = try #require(controller.window?.contentViewController as? SplitViewController)
        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)
        let scaleBoth = reader.pdfView.scaleFactor
        let centerBoth = splitController.splitView.arrangedSubviews[1].frame.width

        store.setRightSidebarVisible(false, in: controller.windowID)
        flushLayout(controller.window)
        let scaleRightHidden = reader.pdfView.scaleFactor
        let centerRightHidden = splitController.splitView.arrangedSubviews[1].frame.width

        #expect(centerRightHidden > centerBoth + 50)
        #expect(scaleRightHidden > scaleBoth + 0.01)

        store.setRightSidebarVisible(true, in: controller.windowID)
        flushLayout(controller.window)
        #expect(abs(reader.pdfView.scaleFactor - scaleBoth) < 0.08)
    }

    @Test
    func collapsedRightSidebarStaysCollapsedAfterStoreRefresh() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(documentAt: makeTemporaryPDF(named: "collapsed-right-sidebar"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        splitController.splitViewItems[2].isCollapsed = true
        splitController.splitViewDidResizeSubviews(
            Notification(name: NSSplitView.didResizeSubviewsNotification, object: splitController.splitView)
        )
        flushLayout(controller.window)

        #expect(store.isRightSidebarVisible(in: controller.windowID) == false)

        store.setDirty(true, for: session.id)
        flushLayout(controller.window)

        #expect(splitController.splitViewItems[2].isCollapsed)
    }

    @Test
    func switchingRightSidebarModesKeepsUnifiedSidebarWidth() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "right-sidebar-mode-width"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        splitController.splitView.setPosition(860, ofDividerAt: 1)
        splitController.splitView.adjustSubviews()
        flushLayout(controller.window)

        let baselineWidth = splitController.splitView.arrangedSubviews[2].frame.width
        #expect(baselineWidth > 120)
        #expect(abs(store.sidebarWidths(in: controller.windowID).right - baselineWidth) < 0.5)

        for mode in RightSidebarMode.allCases {
            store.setRightSidebarMode(mode, in: controller.windowID)
            flushLayout(controller.window)

            let currentWidth = splitController.splitView.arrangedSubviews[2].frame.width
            #expect(
                abs(currentWidth - baselineWidth) < 0.5,
                "Mode \(mode) changed right sidebar width from \(baselineWidth) to \(currentWidth)"
            )
            #expect(
                abs(store.sidebarWidths(in: controller.windowID).right - baselineWidth) < 0.5,
                "Mode \(mode) mutated stored window sidebar width"
            )
        }
    }

    @Test
    func switchingBetweenSearchAndAnnotationsKeepsUnifiedWidthWithRealContent() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let windowID = controller.windowID
        let session = try store.open(
            documentAt: makeSelectableTemporaryPDF(
                named: "right-sidebar-real-content",
                text: "needle alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let page = try? store.pdfDocument(for: session.id).page(at: 0),
              let selection = page.selection(for: page.bounds(for: .mediaBox)) else {
            Issue.record("Failed to prepare debug sidebar content")
            return
        }

        let records = HighlightService.applyHighlight(
            to: selection,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        store.noteHighlightsAdded(records, for: session.id, now: Date(timeIntervalSinceReferenceDate: 1))
        guard let group = store.annotationGroups(for: session.id).first else {
            Issue.record("Failed to create annotation group")
            return
        }
        _ = store.updateComment(
            "Long sidebar comment for width debugging. Long sidebar comment for width debugging.",
            forHighlightGroup: group.groupID,
            in: session.id,
            now: Date(timeIntervalSinceReferenceDate: 2)
        )
        store.updateSearch(query: "needle", scope: .currentDocument, in: windowID)
        flushLayout(controller.window)

        store.setRightSidebarMode(.search, in: windowID)
        flushLayout(controller.window)
        let searchWidth = splitController.splitView.arrangedSubviews[2].frame.width

        store.setRightSidebarMode(.annotations, in: windowID)
        flushLayout(controller.window)
        let annotationsWidth = splitController.splitView.arrangedSubviews[2].frame.width

        #expect(
            abs(searchWidth - annotationsWidth) < 0.5,
            "search width \(searchWidth) != annotations width \(annotationsWidth)"
        )
    }

    @Test
    func switchingTabsKeepsWindowSidebarWidths() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }

        let first = try store.open(documentAt: makeTemporaryPDF(named: "window-sidebar-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "window-sidebar-second"))
        flushLayout(controller.window)

        let splitController = try #require(controller.window?.contentViewController as? SplitViewController)
        splitController.splitView.setPosition(860, ofDividerAt: 1)
        splitController.splitView.adjustSubviews()
        flushLayout(controller.window)

        let baselineRightWidth = splitController.splitView.arrangedSubviews[2].frame.width
        #expect(abs(store.sidebarWidths(in: controller.windowID).right - baselineRightWidth) < 0.5)

        store.activate(sessionID: first.id, in: controller.windowID)
        flushLayout(controller.window)

        let widthAfterSwitch = splitController.splitView.arrangedSubviews[2].frame.width
        #expect(abs(widthAfterSwitch - baselineRightWidth) < 0.5)
        #expect(abs(store.sidebarWidths(in: controller.windowID).right - baselineRightWidth) < 0.5)
    }

    @Test
    func hiddenVerticalTabsStayHiddenAcrossSessionActivation() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "hidden-tabs-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "hidden-tabs-second"))
        flushLayout(controller.window)

        store.setTabPresentationMode(.verticalSidebar, in: controller.windowID)
        store.setLeftSidebarVisible(false, in: controller.windowID)
        flushLayout(controller.window)

        store.activate(sessionID: first.id, in: controller.windowID)
        store.activate(sessionID: second.id, in: controller.windowID)
        flushLayout(controller.window)

        #expect(store.isLeftSidebarVisible(in: controller.windowID) == false)
        #expect((controller.window?.contentViewController as? SplitViewController)?.splitViewItems[0].isCollapsed == true)
    }

    @Test
    func readerPaneFocusStrokeIsOnlyDrawnWhileSplit() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "pane-stroke-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "pane-stroke-second"))
        let windowID = controller.windowID
        guard let workspace = (controller.window?.contentViewController as? SplitViewController)?
            .readerWorkspaceViewController else {
            Issue.record("Failed to locate reader workspace")
            return
        }
        flushLayout(controller.window)

        #expect(store.isSplitEnabled(in: windowID) == false)
        #expect(workspace.testingPrimaryPaneBorderWidth == 0)
        #expect(workspace.testingSecondaryPaneBorderWidth == 0)

        store.activate(sessionID: first.id, in: windowID)
        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)
        store.setFocusedPane(.primary, in: windowID)
        flushLayout(controller.window)

        #expect(store.isSplitEnabled(in: windowID))
        #expect(workspace.testingPrimaryPaneBorderWidth == 1)
        #expect(workspace.testingSecondaryPaneBorderWidth == 0)

        store.setFocusedPane(.secondary, in: windowID)
        flushLayout(controller.window)
        #expect(workspace.testingPrimaryPaneBorderWidth == 0)
        #expect(workspace.testingSecondaryPaneBorderWidth == 1)

        store.setSplitEnabled(false, in: windowID)
        flushLayout(controller.window)
        #expect(workspace.testingPrimaryPaneBorderWidth == 0)
        #expect(workspace.testingSecondaryPaneBorderWidth == 0)
    }

    @Test
    func readerSplitToggleCanEnableAndDisableAgain() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-toggle"))
        controller.window?.layoutIfNeeded()

        #expect(controller.isReaderSplitEnabled == false)

        controller.toggleReaderSplit()
        controller.window?.layoutIfNeeded()
        #expect(controller.isReaderSplitEnabled == true)
        #expect(store.splitCandidateSessions(in: controller.windowID).map(\.id).count == 1)

        controller.toggleReaderSplit()
        controller.window?.layoutIfNeeded()
        #expect(controller.isReaderSplitEnabled == false)
    }

    @Test
    func readerSplitSwitchesAxisWithoutChangingPaneSessions() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-axis-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-axis-second"))
        let windowID = controller.windowID

        store.setLeftSidebarVisible(false, in: windowID)
        store.setRightSidebarVisible(false, in: windowID)
        controller.window?.setContentSize(NSSize(width: 560, height: 640))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split controller")
            return
        }
        let workspace = splitController.readerWorkspaceViewController
        let splitView = workspace.testingSplitView
        #expect(workspace.testingActiveSplitMinimumConstraintCount == 0)

        store.activate(sessionID: first.id, in: windowID)
        store.activate(sessionID: second.id, in: windowID, targetPane: .secondary)
        store.setFocusedPane(.secondary, in: windowID)
        flushLayout(controller.window)
        let primarySessionID = store.displayedSessionID(for: .primary, in: windowID)
        let secondarySessionID = store.displayedSessionID(for: .secondary, in: windowID)

        store.setSplitLayout(.sideBySide, in: windowID)
        flushLayout(controller.window)

        let sideBySideFrames = splitView.subviews.map(\.frame)
        #expect(splitView.isVertical)
        #expect(workspace.testingActiveSplitMinimumConstraintCount == 2)
        #expect(sideBySideFrames.count == 2)
        if sideBySideFrames.count == 2 {
            #expect(sideBySideFrames.allSatisfy { $0.width > 0 })
            #expect(abs(sideBySideFrames[0].width - sideBySideFrames[1].width) < 2)
            #expect(abs(sideBySideFrames[0].midX - sideBySideFrames[1].midX) > 100)
            #expect(abs(sideBySideFrames[0].midY - sideBySideFrames[1].midY) < 2)
        }

        store.setSplitLayout(.stacked, in: windowID)
        flushLayout(controller.window)

        let stackedFrames = splitView.subviews.map(\.frame)
        #expect(splitView.isVertical == false)
        #expect(workspace.testingActiveSplitMinimumConstraintCount == 2)
        #expect(stackedFrames.count == 2)
        if stackedFrames.count == 2 {
            #expect(abs(stackedFrames[0].height - stackedFrames[1].height) < 2)
            #expect(abs(stackedFrames[0].midY - stackedFrames[1].midY) > 100)
            #expect(abs(stackedFrames[0].midX - stackedFrames[1].midX) < 2)
        }
        #expect(store.displayedSessionID(for: .primary, in: windowID) == primarySessionID)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == secondarySessionID)
        #expect(store.focusedPane(in: windowID) == .secondary)

        store.setSplitEnabled(false, in: windowID)
        flushLayout(controller.window)
        #expect(workspace.testingActiveSplitMinimumConstraintCount == 0)
    }

    @Test
    func alternateTabActivationUsesBrowserSplitEditSemantics() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-edit-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-edit-second"))
        let third = try store.open(documentAt: makeTemporaryPDF(named: "split-edit-third"))
        let windowID = controller.windowID
        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split controller")
            return
        }

        store.activate(sessionID: first.id, in: windowID)
        splitController.verticalTabsViewController.onAlternateSessionActivationRequested?(second.id)

        #expect(store.isSplitEnabled(in: windowID))
        #expect(store.displayedSessionID(for: .primary, in: windowID) == first.id)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == second.id)
        #expect(store.focusedPane(in: windowID) == .secondary)

        store.setFocusedPane(.primary, in: windowID)
        splitController.titlebarTabsController.onAlternateSessionActivationRequested?(third.id)

        #expect(store.displayedSessionID(for: .primary, in: windowID) == third.id)
        #expect(store.displayedSessionID(for: .secondary, in: windowID) == second.id)
        #expect(store.focusedPane(in: windowID) == .primary)
        #expect(store.splitPair(in: windowID) == ReaderSplitPair(primarySessionID: third.id, secondarySessionID: second.id))
    }

    @Test
    func immersiveShortcutClosesAnyVisibleSidebarAndOpensBothWhenNoneVisible() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let windowID = controller.windowID
        _ = try store.open(documentAt: makeTemporaryPDF(named: "immersive-toggle"))

        store.setTabPresentationMode(.horizontalTitlebar, in: windowID)
        let visibleStates = [(true, true), (true, false), (false, true)]
        for state in visibleStates {
            store.setLeftSidebarVisible(state.0, in: windowID)
            store.setRightSidebarVisible(state.1, in: windowID)
            flushLayout(controller.window)

            #expect(controller.isImmersiveModeEnabled == false)

            controller.toggleImmersiveMode()
            flushLayout(controller.window)

            #expect(controller.isImmersiveModeEnabled)
            #expect(controller.window?.toolbar == nil)
            #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
            #expect(store.isLeftSidebarVisible(in: windowID) == false)
            #expect(store.isRightSidebarVisible(in: windowID) == false)
        }

        controller.toggleImmersiveMode()
        flushLayout(controller.window)

        #expect(controller.isImmersiveModeEnabled == false)
        #expect(controller.window?.toolbar == nil)
        #expect(store.isLeftSidebarVisible(in: windowID))
        #expect(store.isRightSidebarVisible(in: windowID))
    }

    @Test
    func demoModeEntersImmersiveModeAndRestoresPreviousImmersiveState() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let windowID = controller.windowID
        _ = try store.open(documentAt: makeTemporaryPDF(named: "demo-mode"))

        store.setTabPresentationMode(.horizontalTitlebar, in: windowID)
        store.setLeftSidebarVisible(false, in: windowID)
        store.setRightSidebarVisible(true, in: windowID)
        flushLayout(controller.window)

        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(controller.isDemoModeEnabled)
        #expect(controller.isImmersiveModeEnabled)
        #expect(controller.window?.toolbar == nil)
        #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == false)

        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(controller.isDemoModeEnabled == false)
        #expect(controller.isImmersiveModeEnabled == false)
        #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == true)
    }

    @Test
    func demoModeFitsEntirePageAndRestoresReaderState() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "demo-fit-page",
                pageSizes: [NSSize(width: 1280, height: 720)]
            )
        )

        store.setDisplayMode(.singlePageContinuous, for: session.id)
        store.setScaleMode(.fitWidth, scaleFactor: 1.0, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate reader internals")
            return
        }

        controller.toggleDemoMode()
        flushLayout(controller.window)
        controller.windowDidEnterFullScreen(
            Notification(name: NSWindow.didEnterFullScreenNotification, object: controller.window)
        )
        flushLayout(controller.window)

        guard let expectedScale = fitPageScaleExpected(for: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to compute fit-page scale")
            return
        }

        #expect(store.session(for: session.id)?.displayMode == .singlePage)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)
        assertSinglePageDocumentCentered(in: splitController.readerViewController.pdfView)

        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.displayMode == .singlePageContinuous)
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
    }

    @Test
    func demoModeLeavesPreexistingImmersiveModeEnabledOnExit() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let windowID = controller.windowID
        _ = try store.open(documentAt: makeTemporaryPDF(named: "demo-from-immersive"))

        controller.toggleImmersiveMode()
        flushLayout(controller.window)

        controller.toggleDemoMode()
        flushLayout(controller.window)
        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(controller.isDemoModeEnabled == false)
        #expect(controller.isImmersiveModeEnabled)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == false)
    }

    @Test
    func escapeExitsDemoModeAndRestoresPreviousChromeState() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let windowID = controller.windowID
        _ = try store.open(documentAt: makeTemporaryPDF(named: "escape-demo-mode"))

        store.setTabPresentationMode(.horizontalTitlebar, in: windowID)
        store.setLeftSidebarVisible(false, in: windowID)
        store.setRightSidebarVisible(true, in: windowID)
        flushLayout(controller.window)

        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(controller.isDemoModeEnabled)
        #expect(controller.isImmersiveModeEnabled)

        #expect(controller.exitTransientReaderState())
        flushLayout(controller.window)

        #expect(controller.isDemoModeEnabled == false)
        #expect(controller.isImmersiveModeEnabled == false)
        #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == true)
    }

    @Test
    func closeFocusedPaneInSplitCollapsesToSinglePane() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-close-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "split-close-second"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: first.id, in: windowID, targetPane: .secondary)
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
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-duplicate"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: session.id, in: windowID, targetPane: .secondary)
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
    func closeCommandClosesMultipleSelectedTabs() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "batch-close-first"))
        let second = try store.open(documentAt: makeTemporaryPDF(named: "batch-close-second"))
        let third = try store.open(documentAt: makeTemporaryPDF(named: "batch-close-third"))
        let windowID = controller.windowID

        store.selectSessions([third.id, first.id], in: windowID)

        controller.requestCloseActiveSession()
        controller.window?.layoutIfNeeded()

        #expect(store.sessions(in: windowID).map(\.id) == [second.id])
        #expect(store.activeSessionID(in: windowID) == second.id)
        #expect(store.selectedSessionIDs(in: windowID).isEmpty)
        #expect(store.recentlyClosedURLs(in: windowID) == [first.url, third.url])
    }

    @Test
    func readerSplitPreservesAdjustedDividerPositionAcrossStoreRefresh() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "split-divider-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "split-divider-second"))
        let windowID = controller.windowID

        store.setSplitEnabled(true, in: windowID)
        store.activate(sessionID: first.id, in: windowID, targetPane: .secondary)
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
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }

        store.setTabPresentationMode(.horizontalTitlebar)
        store.setLeftSidebarVisible(false)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)

        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-open"))
        controller.window?.layoutIfNeeded()

        #expect(controller.window?.toolbar != nil)

        store.closeActiveSession()
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func outlineSelectionNavigatesToExactPointAndBack() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "outline-navigation"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let outlineRow = findView(
                identifier: OutlineRowView.identifier(for: [1]),
                in: splitController.rightSidebarViewController.outlineViewController.view
              ) as? OutlineRowView,
              let document = splitController.readerViewController.pdfView.document else {
            Issue.record("Failed to locate outline UI")
            return
        }
        let origin = try #require(store.activeSession?.lastReadPosition)
        let targetPoint = try #require(outlineRow.node.destinationPoint)

        outlineRow.performPrimaryAction()
        flushLayout(controller.window)

        let currentPageIndex = splitController.readerViewController.pdfView.currentPage.map { document.index(for: $0) }
        #expect(currentPageIndex == 1)
        let target = ReadingPosition(pageIndex: 1, point: targetPoint)
        #expect(store.activeSession?.lastReadPosition == target)
        let live = try #require(splitController.readerViewController.testingCurrentReadingPosition)
        #expect(live.pageIndex == 1)

        splitController.navigateBack()
        flushLayout(controller.window)
        #expect(store.activeSession?.lastReadPosition == origin)
        #expect(splitController.readerViewController.testingCurrentReadingPosition?.pageIndex == origin.pageIndex)
    }

    @Test
    func firstInternalLinkJumpStaysCenteredInEveryDisplayMode() throws {
        _ = NSApplication.shared
        for mode in ReaderDisplayMode.allCases {
            try assertInternalLinkNavigationStaysCentered(in: mode)
        }
    }

    @Test
    func referencePreviewClosesWhenReadingContextChanges() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        prepareMainWindowForLayoutTests(controller)
        let fixture = try makeTemporaryPDFWithInternalLink(named: "reference-preview-lifecycle")
        let session = try store.open(documentAt: fixture.url)
        flushLayout(controller.window)
        let window = try #require(controller.window)
        let split = try #require(window.contentViewController as? SplitViewController)
        let reader = split.readerViewController
        let targetPage = try #require(reader.pdfView.document?.page(at: fixture.targetPageIndex))
        let destination = PDFDestination(page: targetPage, at: fixture.targetPoint)
        let origin = session.lastReadPosition

        func showPreview() throws {
            let bounds = reader.pdfView.visibleRect
            let anchor = NSRect(x: bounds.midX, y: bounds.midY, width: 16, height: 12)
            #expect(reader.pdfView.onInternalLinkPreviewRequested?(destination, anchor) == true)
            #expect(reader.testingReferencePreviewContent != nil)
        }

        try showPreview()
        reader.testingReferencePreviewContent?.cancelOperation(nil)
        #expect(reader.testingReferencePreviewContent == nil)
        #expect(session.lastReadPosition == origin)
        #expect(reader.testingNavigationBackPositions.isEmpty)

        try showPreview()
        reader.setAllPagesOverviewActive(true)
        #expect(reader.testingReferencePreviewContent == nil)
        reader.setAllPagesOverviewActive(false)
        flushLayout(window)

        try showPreview()
        reader.setLocalEventMonitoringEnabled(false)
        #expect(reader.testingReferencePreviewContent == nil)
        reader.setLocalEventMonitoringEnabled(true)

        try showPreview()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "reference-preview-other"))
        flushLayout(window)
        #expect(reader.testingReferencePreviewContent == nil)
        #expect(session.lastReadPosition == origin)
        #expect(reader.testingNavigationBackPositions.isEmpty)
    }

    @Test
    func repeatedSelectionNavigationDoesNotCreateSelfHistory() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeSelectableTemporaryPDF(
                named: "selection-self-history",
                text: "alpha repeated target omega"
            )
        )
        flushLayout(controller.window)
        let splitController = try #require(
            controller.window?.contentViewController as? SplitViewController
        )
        let reader = splitController.readerViewController
        let selection = try #require(
            reader.pdfView.document?.findString("repeated target", withOptions: []).first
        )

        reader.go(to: selection)
        flushLayout(controller.window)
        let target = try #require(store.session(for: session.id)?.lastReadPosition)
        let historyCount = reader.testingNavigationBackPositions.count

        reader.go(to: selection)
        flushLayout(controller.window)

        #expect(reader.testingNavigationBackPositions.count == historyCount)
        #expect(store.session(for: session.id)?.lastReadPosition == target)
        #expect(reader.pdfView.currentSelection?.string == "repeated target")
    }

    @Test
    func continuousReadingNextPageActivatesNextPDF() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(named: "continuous-next-first", pageSizes: [NSSize(width: 320, height: 480)]),
                makeTemporaryPDF(named: "continuous-next-second", pageSizes: [NSSize(width: 320, height: 480)]),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        store.activate(sessionID: sessions[0].id, in: store.defaultWindowID)
        flushLayout(controller.window)
        let splitController = try #require(
            controller.window?.contentViewController as? SplitViewController
        )

        controller.goToNextPage()
        flushLayout(controller.window)

        #expect(store.activeSessionID == sessions[1].id)
        #expect(store.session(for: sessions[1].id)?.currentPageIndex == 0)
        let nextPosition = try #require(store.session(for: sessions[1].id)?.lastReadPosition)
        let nextDocument = try #require(splitController.readerViewController.pdfView.document)
        let nextPage = try #require(nextDocument.page(at: 0))
        #expect(nextPosition == .pageTop(pageIndex: 0, pageBounds: nextPage.bounds(for: PDFDisplayBox.cropBox)))
        #expect(splitController.readerViewController.pdfView.currentPage.map { nextDocument.index(for: $0) } == 0)
    }

    @Test
    func continuousReadingPreviousPageActivatesPreviousPDFLastPage() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(
                    named: "continuous-prev-first",
                    pageSizes: [
                        NSSize(width: 320, height: 480),
                        NSSize(width: 320, height: 480),
                    ]
                ),
                makeTemporaryPDF(named: "continuous-prev-second", pageSizes: [NSSize(width: 320, height: 480)]),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        flushLayout(controller.window)
        let splitController = try #require(
            controller.window?.contentViewController as? SplitViewController
        )

        controller.goToPreviousPage()
        flushLayout(controller.window)

        #expect(store.activeSessionID == sessions[0].id)
        #expect(store.session(for: sessions[0].id)?.currentPageIndex == 1)
        let previousPosition = try #require(store.session(for: sessions[0].id)?.lastReadPosition)
        let previousDocument = try #require(splitController.readerViewController.pdfView.document)
        let previousPage = try #require(previousDocument.page(at: 1))
        #expect(previousPosition == .pageBottom(pageIndex: 1, pageBounds: previousPage.bounds(for: PDFDisplayBox.cropBox)))
        #expect(splitController.readerViewController.pdfView.currentPage.map { previousDocument.index(for: $0) } == 1)
    }

    @Test
    func nonContinuousHalfPageTurnsCurrentPDFBeforeCrossingBoundary() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let sessions = try store.open(
            documentsAt: [
                makeTemporaryPDF(
                    named: "half-page-boundary-first",
                    pageSizes: [
                        NSSize(width: 320, height: 480),
                        NSSize(width: 320, height: 480),
                    ]
                ),
                makeTemporaryPDF(
                    named: "half-page-boundary-second",
                    pageSizes: [NSSize(width: 320, height: 480)]
                ),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        for session in sessions {
            store.setDisplayMode(.singlePage, for: session.id)
        }
        store.activate(sessionID: sessions[0].id, in: store.defaultWindowID)
        flushLayout(controller.window)
        controller.fitReaderToPage()
        flushLayout(controller.window)

        controller.scrollHalfPageDown()
        flushLayout(controller.window)
        #expect(store.activeSessionID == sessions[0].id)
        #expect(store.session(for: sessions[0].id)?.currentPageIndex == 1)

        controller.scrollHalfPageDown()
        flushLayout(controller.window)
        #expect(store.activeSessionID == sessions[1].id)
        #expect(store.session(for: sessions[1].id)?.currentPageIndex == 0)

        controller.scrollHalfPageUp()
        flushLayout(controller.window)
        #expect(store.activeSessionID == sessions[0].id)
        let firstDocument = try #require(
            (controller.window?.contentViewController as? SplitViewController)?
                .readerViewController.pdfView.document
        )
        let previousPage = try #require(firstDocument.page(at: 1))
        #expect(
            store.session(for: sessions[0].id)?.lastReadPosition
                == .pageBottom(pageIndex: 1, pageBounds: previousPage.bounds(for: .cropBox))
        )
    }

    @Test
    func fitWidthOnOpenCanOpenWindowBackedDocument() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.reader.defaultDisplayMode = .singlePage
        configuration.reader.fitWidthOnOpen = true
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }

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
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
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
        #expect(splitController.readerWorkspaceViewController.primaryReaderViewController.testingLocalEventMonitoringIsInstalled)
        #expect(splitController.readerWorkspaceViewController.secondaryReaderViewController.testingLocalEventMonitoringIsInstalled == false)
        #expect(
            workspaceSplitView.isSubviewCollapsed(workspaceSplitView.subviews[1]) ||
            workspaceSplitView.subviews[1].frame.width < 1
        )
    }

    @Test
    func enablingSplitFitsBothReadersToPaneWidth() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(
            documentAt: makeTemporaryPDF(
                named: "split-fit-first",
                pageSizes: [NSSize(width: 1280, height: 720)]
            )
        )
        let second = try store.open(
            documentAt: makeTemporaryPDF(
                named: "split-fit-second",
                pageSizes: [NSSize(width: 595, height: 842)]
            )
        )
        store.setScaleMode(.manual, scaleFactor: 2.0, for: first.id)
        store.setScaleMode(.manual, scaleFactor: 2.0, for: second.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate reader internals")
            return
        }

        splitController.readerWorkspaceViewController.toggleSplit()
        flushLayout(controller.window)
        #expect(store.splitCandidateSessions(in: controller.windowID).map(\.id) == [second.id, first.id])
        store.activate(sessionID: first.id, in: controller.windowID, targetPane: .secondary)
        flushLayout(controller.window)

        let primaryReader = splitController.readerWorkspaceViewController.primaryReaderViewController
        let secondaryReader = splitController.readerWorkspaceViewController.secondaryReaderViewController
        #expect(primaryReader.testingLocalEventMonitoringIsInstalled)
        #expect(secondaryReader.testingLocalEventMonitoringIsInstalled)
        guard let primarySessionID = store.displayedSessionID(for: .primary, in: controller.windowID),
              let secondarySessionID = store.displayedSessionID(for: .secondary, in: controller.windowID),
              let primaryExpectedScale = fitWidthScaleExpected(for: primaryReader.pdfView),
              let secondaryExpectedScale = fitWidthScaleExpected(for: secondaryReader.pdfView) else {
            Issue.record("Failed to compute split fit-width scale")
            return
        }

        #expect(store.session(for: primarySessionID)?.scaleMode == .fitWidth)
        #expect(store.session(for: secondarySessionID)?.scaleMode == .fitWidth)
        #expect(abs(primaryReader.pdfView.scaleFactor - primaryExpectedScale) < 0.05)
        #expect(abs(secondaryReader.pdfView.scaleFactor - secondaryExpectedScale) < 0.05)
    }

    @Test
    func settingsWindowPageTabsUseEqualWidths() throws {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let pageControl = try #require(
            findView(identifier: "settingsPageControl", in: contentView) as? NSSegmentedControl
        )
        let segmentWidths = (0..<pageControl.segmentCount).map { pageControl.width(forSegment: $0) }

        #expect(segmentWidths.count == 3)
        #expect(segmentWidths.allSatisfy { abs($0 - segmentWidths[0]) < 0.01 })
    }

    @Test
    func settingsWindowSwitchesPageHeightsWithoutChangingWidth() throws {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)

        let window = try #require(controller.window)
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 704))
        controller.selectPageForTesting(1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 484))

        controller.selectPageForTesting(2)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 620))

        controller.selectPageForTesting(0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 704))
    }

    @Test
    func settingsWindowCanDisableCodexIntegration() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let checkbox = try #require(
            findView(identifier: "codexIntegrationCheckbox", in: contentView) as? NSButton
        )
        #expect(checkbox.state == .on)

        checkbox.state = .off
        let action = try #require(checkbox.action)
        let target = try #require(checkbox.target)
        NSApp.sendAction(action, to: target, from: checkbox)

        #expect(publishedConfigurations.last?.integrations.codexEnabled == false)
    }

    @Test
    func settingsWindowPublishesBookAsDefaultDisplayMode() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let popUp = try #require(
            findView(identifier: "defaultDisplayModePopUp", in: contentView) as? NSPopUpButton
        )
        let bookItem = try #require(
            popUp.itemArray.first { ($0.representedObject as? String) == ReaderDisplayMode.book.rawValue }
        )
        popUp.select(bookItem)
        let action = try #require(popUp.action)
        let target = try #require(popUp.target)
        NSApp.sendAction(action, to: target, from: popUp)

        #expect(publishedConfigurations.last?.reader.defaultDisplayMode == .book)
    }

    @Test
    func settingsShortcutRowsFitCompactWindowWithoutHorizontalScrolling() throws {
        var configuration = AppConfiguration.default
        configuration.shortcuts.bindings[.sendCurrentPDFToCodex] = KeyboardShortcut(
            key: "space", modifiers: [.command, .control, .option, .shift]
        )
        let controller = SettingsWindowController(configuration: configuration) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)
        controller.selectPageForTesting(SettingsPage.shortcuts.rawValue)
        flushLayout(controller.window)

        let contentView = try #require(controller.window?.contentView)
        let scrollView = try #require(
            findView(identifier: "shortcutsScrollView", in: contentView) as? NSScrollView
        )
        #expect(scrollView.hasHorizontalScroller == false)
        for command in ShortcutCommand.allCases {
            let row = try #require(
                findView(identifier: "shortcutRow.\(command.rawValue)", in: contentView)
            )
            let capture = try #require(
                findView(identifier: "shortcutCapture.\(command.rawValue)", in: row) as? NSButton
            )
            #expect(row.frame.width <= scrollView.contentView.bounds.width + 1)
            for shortcutView in findAllDescendants(of: ShortcutSequenceView.self, in: row)
                where shortcutView.isHidden == false {
                let frame = shortcutView.convert(shortcutView.bounds, to: row)
                #expect(frame.minX >= -1)
                #expect(frame.maxX <= row.bounds.width + 1)
                #expect(shortcutView.frame.width + 1 >= shortcutView.fittingSize.width)
                if shortcutView.superview !== capture {
                    #expect(frame.maxX <= capture.frame.minX - 8)
                }
            }
            if configuration.shortcuts.bindings[command] != nil {
                #expect(capture.title.isEmpty)
                #expect(findAllDescendants(of: ShortcutSequenceView.self, in: capture).count == 1)
            }
        }
    }

    @Test
    func settingsShortcutPageShowsFilterAndTwoStageBuiltInShortcut() throws {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)
        controller.selectPageForTesting(SettingsPage.shortcuts.rawValue)
        flushLayout(controller.window)

        let contentView = try #require(controller.window?.contentView)
        let command = ShortcutCommand.openLibraryPDF
        let row = try #require(
            findView(identifier: "shortcutRow.\(command.rawValue)", in: contentView)
        )

        #expect(findView(identifier: "shortcutSearchField", in: contentView) is NSSearchField)
        #expect(findView(identifier: "shortcutBuiltIn.\(command.rawValue)", in: row) is ShortcutSequenceView)
        let labels = findAllDescendants(of: NSTextField.self, in: row).map(\.stringValue)
        #expect(labels.contains("Direct shortcut optional"))
        #expect(labels.contains("Default: None") == false)
    }

    @Test
    func settingsShortcutPageRejectsReservedCommandPaletteKey() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) {
            publishedConfigurations.append($0)
        }
        defer { controller.close() }
        controller.showWindow(nil)
        controller.selectPageForTesting(SettingsPage.shortcuts.rawValue)
        flushLayout(controller.window)

        let contentView = try #require(controller.window?.contentView)
        let captureButton = try #require(
            findView(
                identifier: "shortcutCapture.\(ShortcutCommand.openLibraryPDF.rawValue)",
                in: contentView
            ) as? NSButton
        )
        // Avoid AppKit's click animation pumping the async test runner's run loop.
        let action = try #require(captureButton.action)
        let target = try #require(captureButton.target)
        #expect(captureButton.sendAction(action, to: target))
        #expect(
            controller.window?.performKeyEquivalent(
                with: makeKeyEvent(
                    characters: "k",
                    modifierFlags: [.command],
                    window: controller.window
                )
            ) == true
        )

        #expect(publishedConfigurations.isEmpty)
        #expect(
            textField(identifier: "shortcutsErrorLabel", in: contentView)?.stringValue ==
                "⌘K is reserved for Command Palette."
        )
    }

    @Test
    func settingsShortcutFilterRefreshesAfterClearingMatchingBinding() throws {
        let command = ShortcutCommand.openLibraryPDF
        var configuration = AppConfiguration.default
        configuration.shortcuts.bindings[command] = KeyboardShortcut(key: "b", modifiers: [.command])
        var controller: SettingsWindowController!
        controller = SettingsWindowController(configuration: configuration) { updatedConfiguration in
            controller.sync(configuration: updatedConfiguration)
        }
        defer { controller.close() }
        controller.showWindow(nil)
        controller.selectPageForTesting(SettingsPage.shortcuts.rawValue)
        controller.setShortcutSearchForTesting("⌘B")

        let contentView = try #require(controller.window?.contentView)
        let rowIdentifier = "shortcutRow.\(command.rawValue)"
        let row = try #require(findView(identifier: rowIdentifier, in: contentView))
        let clearButton = try #require(
            findView(identifier: command.rawValue, in: row) as? NSButton
        )
        let action = try #require(clearButton.action)
        let target = try #require(clearButton.target)
        #expect(clearButton.sendAction(action, to: target))

        #expect(findView(identifier: rowIdentifier, in: contentView) == nil)
    }

    @Test
    func settingsWindowCanEditSidebarDefaultWidths() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let leftField = try #require(textField(identifier: "leftSidebarWidthField", in: contentView))
        let rightField = try #require(textField(identifier: "rightSidebarWidthField", in: contentView))
        leftField.integerValue = 260
        rightField.integerValue = 360

        let action = try #require(leftField.action)
        let target = try #require(leftField.target)
        NSApp.sendAction(action, to: target, from: leftField)

        let updatedConfiguration = try #require(publishedConfigurations.last)
        #expect(updatedConfiguration.layout.leftSidebarWidth == 260)
        #expect(updatedConfiguration.layout.rightSidebarWidth == 360)
    }

    @Test
    func settingsWindowDoesNotExposeLegacySidebarOpacity() throws {
        _ = NSApplication.shared
        let controller = SettingsWindowController(configuration: .default) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        #expect(slider(identifier: "sidebarOpacitySlider", in: contentView) == nil)
        #expect(textField(identifier: "sidebarOpacityValueLabel", in: contentView) == nil)
    }

    @Test
    func settingsWindowCanEditFloatingOutlineHeight() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let heightSlider = try #require(
            slider(identifier: "floatingOutlineHeightSlider", in: contentView)
        )
        #expect(heightSlider.minValue == Double(AppConfiguration.Layout.minimumFloatingOutlineHeight))
        #expect(heightSlider.maxValue == Double(AppConfiguration.Layout.maximumFloatingOutlineHeight))
        heightSlider.doubleValue = 486

        let action = try #require(heightSlider.action)
        let target = try #require(heightSlider.target)
        NSApp.sendAction(action, to: target, from: heightSlider)

        let updatedConfiguration = try #require(publishedConfigurations.last)
        #expect(updatedConfiguration.layout.floatingOutlineHeight == 486)
        #expect(
            textField(identifier: "floatingOutlineHeightValueLabel", in: contentView)?.stringValue == "486 pt"
        )
    }

    @Test
    func settingsWindowCanEditReadingFocusDefaults() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
        defer { controller.close() }
        controller.showWindow(nil)

        let contentView = try #require(controller.window?.contentView)
        let widthPopUp = try #require(
            findView(identifier: "readingFocusWidthPopUp", in: contentView) as? NSPopUpButton
        )
        let customWidthSlider = try #require(
            slider(identifier: "readingFocusCustomWidthSlider", in: contentView)
        )
        let heightSlider = try #require(
            slider(identifier: "readingFocusHeightSlider", in: contentView)
        )
        #expect(customWidthSlider.isEnabled == false)

        let customItem = try #require(
            widthPopUp.itemArray.first {
                ($0.representedObject as? String) == ReadingFocusWidthMode.custom.rawValue
            }
        )
        widthPopUp.select(customItem)
        customWidthSlider.doubleValue = 0.6
        heightSlider.doubleValue = 132

        let action = try #require(widthPopUp.action)
        let target = try #require(widthPopUp.target)
        NSApp.sendAction(action, to: target, from: widthPopUp)

        let updatedConfiguration = try #require(publishedConfigurations.last)
        #expect(updatedConfiguration.reader.readingFocus.widthMode == .custom)
        #expect(abs(updatedConfiguration.reader.readingFocus.customWidthRatio - 0.6) < 0.001)
        #expect(updatedConfiguration.reader.readingFocus.height == 132)
        #expect(customWidthSlider.isEnabled)
        #expect(
            textField(identifier: "readingFocusCustomWidthValueLabel", in: contentView)?.stringValue == "60%"
        )
        #expect(
            textField(identifier: "readingFocusHeightValueLabel", in: contentView)?.stringValue == "132 pt"
        )
    }

    @Test
    func legacySidebarOpacityDoesNotMakeSidebarSurfacesTranslucent() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        var configuration = AppConfiguration.default
        configuration.layout.sidebarOpacity = 0.44
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "sidebar-opacity"))
        flushLayout(controller.window)

        let splitController = try #require(controller.window?.contentViewController as? SplitViewController)
        let leftMaterial = try #require(splitController.verticalTabsViewController.view as? SidebarMaterialView)
        let rightMaterial = try #require(splitController.rightSidebarViewController.view as? SidebarMaterialView)
        // Seamless chrome: solid reader-matched surface (opacity no longer opens a glass seam).
        #expect(leftMaterial.material == .contentBackground)
        #expect(leftMaterial.blendingMode == .withinWindow)
        #expect(abs(leftMaterial.tintAlpha - 1) < 0.01)
        #expect(rightMaterial.material == .contentBackground)
        #expect(rightMaterial.blendingMode == .withinWindow)
        #expect(abs(rightMaterial.tintAlpha - 1) < 0.01)

        store.setRightSidebarMode(.search, in: controller.windowID)
        store.setRightSidebarMode(.annotations, in: controller.windowID)
        flushLayout(controller.window)
        let tableAlphas = findAllDescendants(of: NSTableView.self, in: splitController.rightSidebarViewController.view)
            .map(\.backgroundColor.alphaComponent)
        #expect(tableAlphas.isEmpty == false)
        #expect(tableAlphas.allSatisfy { abs($0) < 0.01 })

        configuration.layout.sidebarOpacity = 0.72
        store.updateAppConfiguration(configuration)
        flushLayout(controller.window)

        #expect(abs(leftMaterial.tintAlpha - 1) < 0.01)
        #expect(abs(rightMaterial.tintAlpha - 1) < 0.01)
        let refreshedTableAlphas = findAllDescendants(of: NSTableView.self, in: splitController.rightSidebarViewController.view)
            .map(\.backgroundColor.alphaComponent)
        #expect(refreshedTableAlphas.allSatisfy { abs($0) < 0.01 })
    }

    @Test
    func settingsWindowOpensWithConfiguredLibraryFolders() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("serein-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        var configuration = AppConfiguration.default
        configuration.library.folderURLs = [folderURL]
        let controller = SettingsWindowController(configuration: configuration) { _ in }
        defer { controller.close() }
        controller.showWindow(nil)

        let window = try #require(controller.window)
        controller.selectPageForTesting(1) // Library
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        window.layoutIfNeeded()

        #expect(window.title == "Settings")
        let labels = findAllDescendants(of: NSTextField.self, in: window.contentView ?? NSView())
            .map(\.stringValue)
        #expect(labels.contains(where: { $0.contains(folderURL.lastPathComponent) || $0 == folderURL.path }))
    }

    @Test
    func mainWindowUsesUpdatedReaderFramingDefaults() {
        let controller = MainWindowController(documentStore: makeIsolatedDocumentStore())
        defer { controller.close() }
        let contentSize = controller.window?.contentRect(forFrameRect: controller.window?.frame ?? .zero).size

        #expect(contentSize == MainWindowController.defaultContentSize)
        #expect(controller.window?.minSize == MainWindowController.minimumWindowSize)
    }

    @Test
    func mainWindowSupportsSystemGreenButtonTilingActions() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: makeIsolatedDocumentStore())
        defer { controller.close() }
        let window = try #require(controller.window)

        #expect(window.styleMask.contains(.resizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.collectionBehavior.contains(.fullScreenAllowsTiling))
        #expect(window.collectionBehavior.contains(.fullScreenDisallowsTiling) == false)
        #expect(window.contentMinSize == MainWindowController.minimumWindowSize)
        #expect(window.minFullScreenContentSize == MainWindowController.minimumWindowSize)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == false)
        #expect(MainWindowController.minimumWindowSize.width <= 640)
        #expect(MainWindowController.minimumWindowSize.height <= 420)
    }

    @Test
    func singlePageZoomedOutDocumentStaysCentered() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
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

        assertDocumentVisuallyCentered(in: reader.pdfView, axes: .both)
    }

    @Test
    func continuousZoomedOutDocumentStaysHorizontallyCentered() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "continuous-centered",
                pageSizes: [
                    NSSize(width: 720, height: 960),
                    NSSize(width: 720, height: 960),
                ]
            )
        )
        store.setDisplayMode(.singlePageContinuous, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)
        for _ in 0..<4 {
            reader.zoomOut()
        }
        flushLayout(controller.window)

        assertDocumentVisuallyCentered(in: reader.pdfView, axes: .horizontal)
    }

    @Test
    func singlePageFitPageCentersWideSlideOnBothAxes() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "single-page-fit-slide-centered",
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
        reader.fitToPage()
        flushLayout(controller.window)

        assertSinglePageDocumentCentered(in: reader.pdfView)
    }

    @Test
    func singlePageFullyVisibleSlideRejectsBlankAreaScroll() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "single-page-slide-scroll-clamp",
                pageSizes: [NSSize(width: 1280, height: 720)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView),
              let scrollView = splitController.readerViewController.pdfView.subviews
                .compactMap({ $0 as? NSScrollView })
                .first else {
            Issue.record("Failed to locate PDF clip/scroll views")
            return
        }

        splitController.readerViewController.fitToPage()
        flushLayout(controller.window)
        let stableOrigin = clipView.bounds.origin

        clipView.setBoundsOrigin(NSPoint(x: 45, y: 60))
        scrollView.reflectScrolledClipView(clipView)
        flushLayout(controller.window)

        #expect(abs(clipView.bounds.origin.x - stableOrigin.x) < 1.0)
        #expect(abs(clipView.bounds.origin.y - stableOrigin.y) < 1.0)
        assertSinglePageDocumentCentered(in: splitController.readerViewController.pdfView)
    }

    @Test
    func singlePageOversizedPageStillAllowsViewportScroll() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "single-page-large-page-scroll",
                pageSizes: [NSSize(width: 720, height: 2400)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to locate PDF clip view")
            return
        }

        splitController.readerViewController.fitToWidth()
        flushLayout(controller.window)
        let beforeOrigin = clipView.bounds.origin.y

        controller.scrollHalfPageDown()
        flushLayout(controller.window)

        #expect(abs(clipView.bounds.origin.y - beforeOrigin) > 20)
    }

    @Test
    func horizontalPanLockFollowsDocumentWhenSwitchingTabs() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let first = try store.open(documentAt: makeTemporaryPDF(named: "lock-tab-first"))
        flushLayout(controller.window)
        #expect(controller.toggleHorizontalPanLock())

        let second = try store.open(documentAt: makeTemporaryPDF(named: "lock-tab-second"))
        flushLayout(controller.window)
        #expect(!controller.isHorizontalPanLocked)
        store.activate(sessionID: first.id)
        flushLayout(controller.window)
        #expect(controller.isHorizontalPanLocked)
        store.activate(sessionID: second.id)
        flushLayout(controller.window)
        #expect(!controller.isHorizontalPanLocked)
        #expect(controller.toggleHorizontalPanLock())
        store.activate(sessionID: first.id)
        flushLayout(controller.window)
        #expect(!controller.toggleHorizontalPanLock())
        store.activate(sessionID: second.id)
        flushLayout(controller.window)
        #expect(controller.isHorizontalPanLocked)
    }

    @Test
    func horizontalPanLockPreservesPositionAndBlocksHorizontalScroll() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "horizontal-pan-lock",
                pageSizes: [NSSize(width: 1600, height: 900)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView),
              let scrollView = splitController.readerViewController.pdfView.subviews
                .compactMap({ $0 as? NSScrollView })
                .first,
              let documentView = clipView.documentView else {
            Issue.record("Failed to locate PDF scroll geometry")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)
        for _ in 0..<8 {
            reader.zoomIn()
        }
        flushLayout(controller.window)

        #expect(documentView.frame.width > clipView.bounds.width + 8)

        clipView.setBoundsOrigin(NSPoint(x: 40, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        flushLayout(controller.window)
        #expect(abs(clipView.bounds.origin.x - 40) < 1.5)
        let unlockedPosition = store.activeSession?.lastReadPosition

        #expect(controller.toggleHorizontalPanLock() == true)
        #expect(reader.testingHorizontalPanLockIsEnabled)
        #expect(reader.testingPanLockIndicatorIsVisible)
        flushLayout(controller.window)

        let lockedX = clipView.bounds.origin.x
        #expect(abs(lockedX - 40) < 1.5)
        #expect(store.activeSession?.lastReadPosition == unlockedPosition)

        let beforeY = clipView.bounds.origin.y
        clipView.setBoundsOrigin(NSPoint(x: lockedX + 55, y: beforeY))
        scrollView.reflectScrolledClipView(clipView)
        flushLayout(controller.window)
        #expect(abs(clipView.bounds.origin.x - lockedX) < 1.5)
        #expect(abs(clipView.bounds.origin.y - beforeY) < 1.5)

        let scaleBefore = reader.pdfView.scaleFactor
        reader.zoomOut()
        reader.pdfView.zoomOut(nil)
        flushLayout(controller.window)
        #expect(reader.pdfView.scaleFactor < scaleBefore - 0.01)
        #expect(store.session(for: session.id)?.isHorizontalPanLocked == true)
        let zoomedX = clipView.bounds.origin.x
        clipView.setBoundsOrigin(NSPoint(x: zoomedX + 55, y: clipView.bounds.origin.y))
        flushLayout(controller.window)
        #expect(abs(clipView.bounds.origin.x - zoomedX) < 0.1)

        #expect(controller.toggleHorizontalPanLock() == false)
        #expect(reader.testingHorizontalPanLockIsEnabled == false)
        #expect(reader.testingPanLockIndicatorIsVisible == false)

        reader.zoomOut()
        flushLayout(controller.window)
        #expect(reader.pdfView.scaleFactor < scaleBefore - 0.01)
    }

    @Test(arguments: [NSScroller.Style.overlay, .legacy])
    func singlePageZoomKeepsViewportCenterStable(scrollerStyle: NSScroller.Style) throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = previousAppearance }

        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        prepareMainWindowForLayoutTests(controller)
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
        let scroll = try #require(reader.pdfView.documentView?.enclosingScrollView)
        scroll.scrollerStyle = scrollerStyle
        flushLayout(controller.window)
        reader.fitToWidth()
        flushLayout(controller.window)

        // Start in the middle of the page. PDFKit's initial scroll position and
        // coordinate orientation vary by macOS version; neither edge can keep
        // its viewport center when zooming out because the scroll range shrinks.
        let page = try #require(reader.pdfView.document?.page(at: 0))
        let pageBounds = page.bounds(for: reader.pdfView.displayBox)
        let pageCenter = NSPoint(x: pageBounds.midX, y: pageBounds.midY)
        let clip = scroll.contentView
        let centerInClip = clip.convert(reader.pdfView.convert(pageCenter, from: page), from: reader.pdfView)
        clip.scroll(to: NSPoint(
            x: centerInClip.x - clip.bounds.width / 2,
            y: centerInClip.y - clip.bounds.height / 2
        ))
        scroll.reflectScrolledClipView(clip)
        reader.flushPendingReadingPosition()
        flushLayout(controller.window)

        guard let beforeAnchor = visibleDocumentCenter(in: reader.pdfView) else {
            Issue.record("Failed to capture pre-zoom anchor")
            return
        }
        #expect(abs(beforeAnchor.y - pageCenter.y) < 2)

        reader.zoomOut()
        for _ in 0..<6 {
            flushLayout(controller.window)
        }

        guard let afterAnchor = visibleDocumentCenter(in: reader.pdfView) else {
            Issue.record("Failed to capture post-zoom anchor")
            return
        }

        #expect(abs(afterAnchor.x - beforeAnchor.x) < 2.0)
        #expect(abs(afterAnchor.y - beforeAnchor.y) < 8.0,
                "Before: \(beforeAnchor), after: \(afterAnchor), clip: \(clip.bounds)")
        let storedPosition = try #require(store.session(for: session.id)?.lastReadPosition)
        let livePosition = try #require(reader.testingCurrentReadingPosition)
        #expect(storedPosition.pageIndex == livePosition.pageIndex)
        #expect(abs(storedPosition.point.x - livePosition.point.x) < 2)
        #expect(abs(storedPosition.point.y - livePosition.point.y) < 2)
    }

    @Test
    func halfPageScrollMovesViewportAndCanReturn() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
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
        reader.flushPendingReadingPosition()
        flushLayout(controller.window)
        let afterDownOrigin = clipView.bounds.origin.y
        let downDelta = afterDownOrigin - beforeOrigin
        #expect(downDelta > 20)
        let storedAfterDown = try #require(
            store.session(for: splitController.readerViewController.displayedSessionID ?? UUID())?.lastReadPosition
        )
        let liveAfterDown = try #require(reader.testingCurrentReadingPosition)
        #expect(storedAfterDown.pageIndex == liveAfterDown.pageIndex)
        #expect(abs(storedAfterDown.point.y - liveAfterDown.point.y) < 2)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        controller.window?.layoutIfNeeded()
        #expect(abs(clipView.bounds.origin.y - afterDownOrigin) < 1)

        controller.scrollHalfPageUp()
        flushLayout(controller.window)
        let afterUpOrigin = clipView.bounds.origin.y
        let upStep = afterUpOrigin - afterDownOrigin
        #expect(abs(upStep) > 20)
        #expect(upStep * downDelta < 0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        controller.window?.layoutIfNeeded()
        #expect(abs(clipView.bounds.origin.y - afterUpOrigin) < 1)
    }

    @Test
    func halfPageScrollDoesNotDriftAfterSettlingWithOutlineSidebarVisible() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        prepareMainWindowForLayoutTests(controller)
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "half-page-scroll-outline"))
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
        let settledDownOrigin = clipView.bounds.origin.y
        let downDelta = settledDownOrigin - beforeOrigin
        #expect(downDelta > 20)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        controller.window?.layoutIfNeeded()
        let settledAgainDownOrigin = clipView.bounds.origin.y
        #expect(abs(settledAgainDownOrigin - settledDownOrigin) < 1.0)
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
            let store = makeIsolatedDocumentStore()
            let controller = MainWindowController(documentStore: store)
            defer { controller.close() }
            let session = try store.open(
                documentAt: makeTemporaryPDF(named: scenario.name, pageSizes: scenario.pageSizes)
            )
            store.setDisplayMode(scenario.mode, for: session.id)
            flushLayout(controller.window)

            guard let splitController = controller.window?.contentViewController as? SplitViewController else {
                Issue.record("Failed to locate reader internals for \(scenario.name)")
                return
            }

            splitController.readerViewController.fitToWidth()
            flushLayout(controller.window)

            guard let expectedScale = fitWidthScaleExpected(
                for: splitController.readerViewController.pdfView,
                leadPageIndex: scenario.leadPageIndex
            ) else {
                Issue.record("Failed to calculate fit-width scale for \(scenario.name)")
                return
            }

            #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)
        }
    }

    @Test
    func bookFitWidthFitsActualSpreadWithinSafeInsetsAndTracksHeight() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "book-smart-fit-width",
                pageSizes: Array(repeating: NSSize(width: 595, height: 842), count: 4)
            )
        )
        store.setDisplayMode(.book, for: session.id)

        let reader = ReaderViewController(documentStore: store)
        reader.targetSessionID = session.id
        reader.loadViewIfNeeded()
        reader.view.frame = NSRect(x: 0, y: 0, width: 1450, height: 913)
        reader.view.layoutSubtreeIfNeeded()
        #expect(reader.goToNextPage())
        reader.fitToWidth()
        reader.view.layoutSubtreeIfNeeded()

        guard let clipView = pdfClipView(in: reader.pdfView),
              let leftPage = reader.pdfView.document?.page(at: 1),
              let rightPage = reader.pdfView.document?.page(at: 2) else {
            Issue.record("Failed to locate Book spread geometry")
            return
        }
        let leftSize = leftPage.bounds(for: reader.pdfView.displayBox).size
        let rightSize = rightPage.bounds(for: reader.pdfView.displayBox).size
        let expectedScale = min(
            (clipView.frame.width - 64) / (leftSize.width + rightSize.width + 14),
            (clipView.frame.height - 48) / max(leftSize.height, rightSize.height)
        )
        #expect(abs(reader.pdfView.scaleFactor - expectedScale) < 0.02)
        assertBookSpreadVerticallyCentered([leftPage, rightPage], in: reader.pdfView)

        let initialScale = reader.pdfView.scaleFactor
        reader.view.frame = NSRect(x: 0, y: 0, width: 1450, height: 700)
        reader.view.layoutSubtreeIfNeeded()
        let resizedExpectedScale = min(
            (clipView.frame.width - 64) / (leftSize.width + rightSize.width + 14),
            (clipView.frame.height - 48) / max(leftSize.height, rightSize.height)
        )
        #expect(reader.pdfView.scaleFactor < initialScale)
        #expect(abs(reader.pdfView.scaleFactor - resizedExpectedScale) < 0.02)
        assertBookSpreadVerticallyCentered([leftPage, rightPage], in: reader.pdfView)
    }

    @Test
    func bookManualZoomOutStaysCenteredAfterPDFKitSettles() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "book-manual-zoom-centering",
                pageSizes: Array(repeating: NSSize(width: 595, height: 842), count: 4)
            )
        )
        store.setDisplayMode(.book, for: session.id)
        let window = try #require(controller.window)
        flushLayout(window)

        let splitController = try #require(window.contentViewController as? SplitViewController)
        let reader = splitController.readerViewController
        #expect(reader.goToNextPage())
        reader.fitToWidth()
        flushLayout(window)

        let leftPage = try #require(reader.pdfView.document?.page(at: 1))
        let rightPage = try #require(reader.pdfView.document?.page(at: 2))
        reader.zoomOut()
        reader.zoomOut()
        flushLayout(window)
        flushLayout(window)

        #expect(store.session(for: session.id)?.scaleMode == .manual)
        assertBookSpreadVerticallyCentered([leftPage, rightPage], in: reader.pdfView)
    }

    @Test
    func fitHeightUsesPDFKitRowHeight() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "fit-height",
                pageSizes: [NSSize(width: 720, height: 1800)]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let expectedScale = fitHeightScaleExpected(for: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to locate reader internals")
            return
        }

        splitController.readerViewController.fitToHeight()
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .fitHeight)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)
    }

    @Test
    func pdfScrollViewDisablesElasticity() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(
            documentAt: makeTemporaryPDF(
                named: "scroll-elasticity",
                pageSizes: [NSSize(width: 720, height: 1800)]
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let scrollView = splitController.readerViewController.pdfView.subviews
                .compactMap({ $0 as? NSScrollView })
                .first else {
            Issue.record("Failed to locate PDF scroll view")
            return
        }

        #expect(scrollView.verticalScrollElasticity == .none)
        #expect(scrollView.horizontalScrollElasticity == .none)
    }

    @Test
    func highlightingAfterZoomKeepsManualScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let url = try makeSelectableTemporaryPDF(named: "highlight-zoom-stability", text: "Hello DeepSeek world")
        let session = try store.open(documentAt: url)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.zoomIn()
        flushLayout(controller.window)
        let zoomedScale = reader.pdfView.scaleFactor

        guard let selection = reader.pdfView.document?.findString("DeepSeek", withOptions: .caseInsensitive).first else {
            Issue.record("Failed to locate selectable text for highlighting")
            return
        }

        reader.pdfView.currentSelection = selection
        #expect(reader.triggerAnnotationShortcut(.highlight) == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - zoomedScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - zoomedScale) < 0.001)
    }

    @Test
    func highlightingAfterDirectPDFViewScaleChangeKeepsManualScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let url = try makeSelectableTemporaryPDF(named: "highlight-direct-scale-stability", text: "Hello DeepSeek world")
        let session = try store.open(documentAt: url)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        let targetScale = min(reader.pdfView.scaleFactor * 1.2, reader.pdfView.maxScaleFactor)
        reader.pdfView.scaleFactor = targetScale
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.001)

        guard let selection = reader.pdfView.document?.findString("DeepSeek", withOptions: .caseInsensitive).first else {
            Issue.record("Failed to locate selectable text for highlighting")
            return
        }

        reader.pdfView.currentSelection = selection
        #expect(reader.triggerAnnotationShortcut(.highlight) == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - targetScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.001)
    }

    @Test
    func userMagnificationLeavesFitWidthAndKeepsLiveScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "pinch-from-fit-width",
                pageSizes: [NSSize(width: 720, height: 900)]
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
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)

        let targetScale = min(reader.pdfView.scaleFactor * 1.2, reader.pdfView.maxScaleFactor)
        reader.testingBeginUserMagnification()
        reader.pdfView.scaleFactor = targetScale
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs(reader.pdfView.scaleFactor - targetScale) < 0.001)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.001)
    }

    @Test
    func layoutDrivenScaleChangeFromFitWidthReappliesFitWidth() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "layout-scale-from-fit-width",
                pageSizes: [NSSize(width: 720, height: 900)]
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
        let fitScale = reader.pdfView.scaleFactor
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)

        reader.pdfView.scaleFactor = min(fitScale * 1.2, reader.pdfView.maxScaleFactor)
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
        #expect(abs(reader.pdfView.scaleFactor - fitScale) < 0.05)
    }

    @Test
    func userMagnificationLeavesFitHeightAndKeepsLiveScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "pinch-from-fit-height",
                pageSizes: [NSSize(width: 720, height: 1800)]
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToHeight()
        flushLayout(controller.window)
        #expect(store.session(for: session.id)?.scaleMode == .fitHeight)

        let targetScale = min(reader.pdfView.scaleFactor * 1.2, reader.pdfView.maxScaleFactor)
        reader.testingBeginUserMagnification()
        reader.pdfView.scaleFactor = targetScale
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs(reader.pdfView.scaleFactor - targetScale) < 0.001)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.001)
    }

    @Test
    func pdfViewZoomInFromFitWidthPinsManualScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "pdfkit-zoom-in-from-fit-width",
                pageSizes: [NSSize(width: 720, height: 900)]
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
        let fitScale = reader.pdfView.scaleFactor
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
        #expect(reader.pdfView.canZoomIn)

        reader.pdfView.zoomIn(nil)
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(reader.pdfView.scaleFactor > fitScale + 0.01)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - reader.pdfView.scaleFactor) < 0.001)
    }

    @Test
    func pageTurnKeepsManualScale() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "page-turn-manual-scale",
                pageSizes: [
                    NSSize(width: 720, height: 900),
                    NSSize(width: 1280, height: 720),
                ]
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        let manualScale = min(reader.pdfView.scaleFactor * 1.2, reader.pdfView.maxScaleFactor)
        reader.pdfView.scaleFactor = manualScale
        flushLayout(controller.window)

        reader.goToNextPage()
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - manualScale) < 0.001)
        #expect(store.session(for: session.id)?.currentPageIndex == 1)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - manualScale) < 0.001)
    }

    @Test
    func pageTurnFromFitWidthKeepsLiveScaleWhenPageShapeChanges() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "page-turn-fit-width-scale",
                pageSizes: [
                    NSSize(width: 720, height: 900),
                    NSSize(width: 1280, height: 720),
                ]
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
        let originalScale = reader.pdfView.scaleFactor

        reader.goToNextPage()
        flushLayout(controller.window)

        let targetScale = try #require(fitWidthScaleExpected(for: reader.pdfView, leadPageIndex: 1))
        #expect(abs(reader.pdfView.scaleFactor - targetScale) < 0.05)
        #expect(abs(reader.pdfView.scaleFactor - originalScale) > 0.1)
        #expect(store.session(for: session.id)?.currentPageIndex == 1)
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.05)
    }

    @Test
    func rapidPageTurnsSettleWithoutResidualDrift() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "rapid-page-turn-settle",
                pageSizes: Array(repeating: NSSize(width: 720, height: 900), count: 5)
            )
        )
        store.setDisplayMode(.singlePage, for: session.id)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to locate reader internals")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)

        reader.goToNextPage()
        reader.goToNextPage()
        reader.goToNextPage()
        flushLayout(controller.window)

        let settledOrigin = clipView.bounds.origin
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        controller.window?.layoutIfNeeded()
        let afterWaitOrigin = clipView.bounds.origin
        let backingScale = controller.window?.backingScaleFactor ?? 1

        #expect(store.session(for: session.id)?.currentPageIndex == 3)
        let document = try #require(reader.pdfView.document)
        #expect(reader.pdfView.currentPage.map { document.index(for: $0) } == 3)
        #expect(reader.testingCurrentReadingPosition?.pageIndex == 3)
        #expect(abs(afterWaitOrigin.x - settledOrigin.x) < 0.5)
        #expect(abs(afterWaitOrigin.y - settledOrigin.y) < 0.5)
        #expect(abs(afterWaitOrigin.y * backingScale - (afterWaitOrigin.y * backingScale).rounded()) < 0.001)
    }

    @Test
    func highlightingKeepsLiveManualScaleWhenStoreMissedScaleChange() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let url = try makeSelectableTemporaryPDF(named: "highlight-stale-scale-store", text: "Hello DeepSeek world")
        let session = try store.open(documentAt: url)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        reader.fitToWidth()
        flushLayout(controller.window)

        reader.flushPendingReadingPosition()
        NotificationCenter.default.removeObserver(
            reader,
            name: Notification.Name.PDFViewScaleChanged,
            object: reader.pdfView
        )

        let fitScale = reader.pdfView.scaleFactor
        let manualScale = min(fitScale * 1.2, reader.pdfView.maxScaleFactor)
        reader.testingBeginUserMagnification()
        reader.pdfView.scaleFactor = manualScale
        flushLayout(controller.window)
        #expect(abs(reader.pdfView.scaleFactor - manualScale) < 0.001)

        guard let selection = reader.pdfView.document?.findString("DeepSeek", withOptions: .caseInsensitive).first else {
            Issue.record("Failed to locate selectable text for highlighting")
            return
        }

        reader.pdfView.currentSelection = selection
        #expect(reader.triggerAnnotationShortcut(.highlight) == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - manualScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - manualScale) < 0.001)
    }

    @Test
    func storeRefreshKeepsLivePageWhenStoreMissedPageChange() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "stale-page-store",
                pageSizes: [NSSize(width: 720, height: 900), NSSize(width: 720, height: 900)]
            )
        )
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView),
              let scrollView = splitController.readerViewController.pdfView.subviews
                .compactMap({ $0 as? NSScrollView })
                .first else {
            Issue.record("Failed to locate reader scroll view")
            return
        }

        let reader = splitController.readerViewController
        NotificationCenter.default.removeObserver(
            reader,
            name: Notification.Name.PDFViewPageChanged,
            object: reader.pdfView
        )

        guard let secondPage = reader.pdfView.document?.page(at: 1) else {
            Issue.record("Failed to locate second page")
            return
        }

        reader.pdfView.go(to: secondPage)
        scrollView.reflectScrolledClipView(clipView)
        flushLayout(controller.window)

        let originBeforeRefresh = clipView.bounds.origin.y
        let pageBeforeRefresh = reader.pdfView.document.flatMap { document in
            reader.pdfView.currentPage.map { document.index(for: $0) }
        }

        store.setDirty(true, for: session.id)
        flushLayout(controller.window)

        let originAfterRefresh = clipView.bounds.origin.y
        let pageAfterRefresh = reader.pdfView.document.flatMap { document in
            reader.pdfView.currentPage.map { document.index(for: $0) }
        }

        #expect(pageBeforeRefresh == 1)
        #expect(pageAfterRefresh == 1)
        #expect(abs(originAfterRefresh - originBeforeRefresh) < 1.0)
    }

    @Test
    func hotReloadKeepsLivePageWhenStoreMissedPageChange() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let pageSize = NSSize(width: 720, height: 900)
        let url = try makeTemporaryPDF(
            named: "hot-reload-live-page",
            pageSizes: Array(repeating: pageSize, count: 3)
        )
        let session = try store.open(documentAt: url)
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let clipView = pdfClipView(in: splitController.readerViewController.pdfView),
              let scrollView = splitController.readerViewController.pdfView.subviews
                .compactMap({ $0 as? NSScrollView })
                .first else {
            Issue.record("Failed to locate reader scroll view")
            return
        }

        let reader = splitController.readerViewController
        let originalDocument = try #require(reader.pdfView.document)
        NotificationCenter.default.removeObserver(
            reader,
            name: Notification.Name.PDFViewPageChanged,
            object: reader.pdfView
        )
        let secondPage = try #require(originalDocument.page(at: 1))
        reader.pdfView.go(to: secondPage)
        scrollView.reflectScrolledClipView(clipView)
        flushLayout(controller.window)

        let livePageIndex = reader.pdfView.currentPage.map { originalDocument.index(for: $0) }
        #expect(livePageIndex == 1)
        #expect(store.session(for: session.id)?.currentPageIndex == 0)
        try writeTemporaryPDF(
            to: url,
            named: "hot-reload-live-page-updated",
            pageSizes: Array(repeating: pageSize, count: 4)
        )
        store.refreshExternallyChangedFile(at: url)
        flushLayout(controller.window)

        let reloadedDocument = try #require(reader.pdfView.document)
        let reloadedPageIndex = reader.pdfView.currentPage.map { reloadedDocument.index(for: $0) }
        #expect(reloadedDocument !== originalDocument)
        #expect(reloadedPageIndex == 1)
        #expect(store.session(for: session.id)?.currentPageIndex == 1)
    }

    @Test
    func fitWidthSkipsProgrammaticReapplyWhenTargetScaleIsAlreadyActive() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(
            documentAt: makeTemporaryPDF(
                named: "fit-width-stable-refresh",
                pageSizes: [NSSize(width: 720, height: 1800)]
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

        let targetScale = reader.pdfView.scaleFactor
        #expect(reader.shouldApplyFitWidth(targetScale, for: session) == false)

        store.setScaleMode(.manual, scaleFactor: targetScale * 1.1, for: session.id)
        flushLayout(controller.window)
        #expect(reader.shouldApplyFitWidth(targetScale, for: session) == true)
    }

    @Test
    func emptyReaderStaysBlankWhenNoDocumentIsOpen() {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: makeIsolatedDocumentStore())
        defer { controller.close() }
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        #expect(reader.testingEmptyStateIsVisible == false)
        #expect(reader.testingEmptyStateError == nil)
        #expect(reader.testingPDFViewIsHidden)
    }

    @Test
    func emptyReaderShowsPDFWhenDocumentOpens() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-state-onboarding"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        #expect(reader.testingEmptyStateIsVisible == false)
        #expect(reader.testingPDFViewIsHidden == false)
    }

    @Test
    func blankTabStaysBlankWithoutErrorDetails() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        _ = store.newBlankTab()
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController else {
            Issue.record("Failed to locate split view controller")
            return
        }

        let reader = splitController.readerViewController
        #expect(reader.testingEmptyStateIsVisible == false)
        #expect(reader.testingEmptyStateError == nil)
        #expect(reader.testingPDFViewIsHidden)
    }
}

@MainActor
private func flushLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}

@MainActor
private func prepareMainWindowForLayoutTests(_ controller: MainWindowController) {
    guard let window = controller.window else { return }
    // Headless CI runners sometimes keep a undersized first frame after showWindow;
    // pin the default content size so preferred sidebar widths always fit.
    window.setContentSize(MainWindowController.defaultContentSize)
    window.setFrameOrigin(NSPoint(x: 80, y: 80))
    controller.showWindow(nil)
    window.layoutIfNeeded()
}

@MainActor
private func waitForLayout(
    _ window: NSWindow?,
    timeout: TimeInterval = 1.5,
    until condition: () -> Bool
) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    repeat {
        window?.layoutIfNeeded()
        if condition() { return true }
        RunLoop.current.run(until: min(Date(timeIntervalSinceNow: 0.02), deadline))
    } while Date() < deadline

    window?.layoutIfNeeded()
    return condition()
}

@MainActor
private func pdfClipView(in pdfView: PDFView) -> NSClipView? {
    pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView
}

@MainActor
private func pdfDocumentView(in pdfView: PDFView) -> NSView? {
    pdfClipView(in: pdfView)?.documentView
}

private struct DocumentCenterAxes: OptionSet {
    let rawValue: Int
    static let horizontal = DocumentCenterAxes(rawValue: 1 << 0)
    static let vertical = DocumentCenterAxes(rawValue: 1 << 1)
    static let both: DocumentCenterAxes = [.horizontal, .vertical]
}

@MainActor
private func assertSinglePageDocumentCentered(in pdfView: PDFView) {
    assertDocumentVisuallyCentered(in: pdfView, axes: .both)
}

@MainActor
private func assertBookSpreadVerticallyCentered(_ pages: [PDFPage], in pdfView: PDFView) {
    guard let clipView = pdfClipView(in: pdfView),
          let boundsInClip = bookSpreadBoundsInClip(pages, pdfView: pdfView) else {
        Issue.record("Failed to locate Book clip view or pages")
        return
    }
    #expect(
        abs(boundsInClip.midY - clipView.bounds.midY) < 1,
        "Book spread center \(boundsInClip.midY), viewport center \(clipView.bounds.midY)"
    )
}

@MainActor
private func bookSpreadBoundsInClip(_ pages: [PDFPage], pdfView: PDFView) -> NSRect? {
    guard let clipView = pdfClipView(in: pdfView),
          let firstPage = pages.first else { return nil }
    let firstBounds = pdfView.convert(firstPage.bounds(for: pdfView.displayBox), from: firstPage)
    let spreadBounds = pages.dropFirst().reduce(firstBounds) { bounds, page in
        bounds.union(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page))
    }
    return clipView.convert(spreadBounds, from: pdfView)
}

/// Verifies the document is centered in the clip view, not only that
/// `documentView.frame.origin` is offset (AppKit can cancel that offset by
/// pinning `clip.bounds.origin` to the same value).
@MainActor
private func assertDocumentVisuallyCentered(in pdfView: PDFView, axes: DocumentCenterAxes) {
    guard let clipView = pdfClipView(in: pdfView),
          let documentView = pdfDocumentView(in: pdfView) else {
        Issue.record("Failed to locate PDF clip/document views")
        return
    }

    if axes.contains(.horizontal) {
        #expect(documentView.frame.width <= clipView.bounds.width + 0.5)
        let expectedMinX = max((clipView.bounds.width - documentView.frame.width) * 0.5, 0)
        #expect(abs(documentView.frame.minX - expectedMinX) < 1.0)
        #expect(abs(clipView.bounds.origin.x) < 1.0)
    }
    if axes.contains(.vertical) {
        #expect(documentView.frame.height <= clipView.bounds.height + 0.5)
        let expectedMinY = max((clipView.bounds.height - documentView.frame.height) * 0.5, 0)
        #expect(abs(documentView.frame.minY - expectedMinY) < 1.0)
        #expect(abs(clipView.bounds.origin.y) < 1.0)
    }
}

@MainActor
private func mouseDownEvent(in window: NSWindow, at location: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
}

@MainActor
private func physicalCommandNumberEvent(
    _ number: Int,
    in window: NSWindow,
    left: Bool = false,
    right: Bool = false
) -> NSEvent {
    var rawModifiers = NSEvent.ModifierFlags.command.rawValue
    if left {
        rawModifiers |= UInt(NX_DEVICELCMDKEYMASK)
    }
    if right {
        rawModifiers |= UInt(NX_DEVICERCMDKEYMASK)
    }
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: rawModifiers),
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: String(number),
        charactersIgnoringModifiers: String(number),
        isARepeat: false,
        keyCode: UInt16(17 + number)
    )!
}

@MainActor
private func pdfScrollBackgroundViews(in scrollView: NSScrollView) -> [NSView] {
    var matches: [NSView] = []
    var pending = scrollView.subviews
    while let view = pending.popLast() {
        if String(describing: type(of: view)).contains("ContentBackgroundView") {
            matches.append(view)
        }
        pending.append(contentsOf: view.subviews)
    }
    return matches
}

@MainActor
private func textField(identifier: String, in root: NSView) -> NSTextField? {
    findView(identifier: identifier, in: root) as? NSTextField
}

@MainActor
private func slider(identifier: String, in root: NSView) -> NSSlider? {
    findView(identifier: identifier, in: root) as? NSSlider
}

@MainActor
private func visibleDocumentCenter(in pdfView: PDFView) -> NSPoint? {
    guard let clip = pdfClipView(in: pdfView),
          clip.bounds.width > 0, clip.bounds.height > 0 else { return nil }
    let viewportCenter = pdfView.convert(NSPoint(x: clip.bounds.midX, y: clip.bounds.midY), from: clip)
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
private func fitHeightScaleExpected(for pdfView: PDFView, leadPageIndex: Int = 0) -> CGFloat? {
    guard let clipView = pdfClipView(in: pdfView),
          let page = pdfView.document?.page(at: leadPageIndex),
          pdfView.scaleFactor > 0 else { return nil }

    let normalizedRowHeight = pdfView.rowSize(for: page).height / pdfView.scaleFactor
    guard normalizedRowHeight > 0 else { return nil }
    return clipView.frame.height / normalizedRowHeight
}

@MainActor
private func fitPageScaleExpected(for pdfView: PDFView, pageIndex: Int = 0) -> CGFloat? {
    guard let clipView = pdfClipView(in: pdfView),
          let page = pdfView.document?.page(at: pageIndex),
          pdfView.scaleFactor > 0 else { return nil }

    let rowSize = pdfView.rowSize(for: page)
    let normalizedRowSize = NSSize(
        width: rowSize.width / pdfView.scaleFactor,
        height: rowSize.height / pdfView.scaleFactor
    )
    guard normalizedRowSize.width > 0, normalizedRowSize.height > 0 else { return nil }
    return min(
        clipView.frame.width / normalizedRowSize.width,
        clipView.frame.height / normalizedRowSize.height
    )
}

@MainActor
private func assertColor(_ lhs: NSColor, matches rhs: NSColor, tolerance: CGFloat = 0.002) {
    let left = lhs.usingColorSpace(.sRGB) ?? lhs
    let right = rhs.usingColorSpace(.sRGB) ?? rhs

    #expect(abs(left.redComponent - right.redComponent) < tolerance)
    #expect(abs(left.greenComponent - right.greenComponent) < tolerance)
    #expect(abs(left.blueComponent - right.blueComponent) < tolerance)
    #expect(abs(left.alphaComponent - right.alphaComponent) < tolerance)
}

@MainActor
private func assertTransparent(_ color: NSColor, tolerance: CGFloat = 0.002) {
    let resolved = color.usingColorSpace(.sRGB) ?? color
    #expect(resolved.alphaComponent < tolerance)
}

@MainActor
private func resolvedColor(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
    var resolved = color
    appearance.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB) ?? color
    }
    return resolved
}

@MainActor
private func makeTemporaryPDF(named name: String, pageSizes: [NSSize] = [NSSize(width: 200, height: 260)]) throws -> URL {
    try TestPDFFixtures.makeLabeledPDF(named: name, pageSizes: pageSizes)
}

@MainActor
private func writeTemporaryPDF(to url: URL, named name: String, pageSizes: [NSSize]) throws {
    try TestPDFFixtures.writeLabeledPDF(to: url, named: name, pageSizes: pageSizes)
}

@MainActor
private func makeSelectableTemporaryPDF(named name: String, text: String) throws -> URL {
    try TestPDFFixtures.makeSelectablePDF(named: name, text: text)
}


@MainActor
private func makeTemporaryPDFWithOutline(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    for index in 0..<2 {
        let pageSize = NSSize(width: 320, height: 1200)
        let image = NSImage(size: pageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: pageSize)).fill()
        NSString(string: "Outline \(index + 1)").draw(
            in: NSRect(x: 36, y: 580, width: 200, height: 40),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        document.insert(page, at: index)
    }

    let root = PDFOutline()
    let first = PDFOutline()
    first.label = "Page 1"
    first.destination = PDFDestination(page: document.page(at: 0)!, at: NSPoint(x: 0, y: 1200))
    let second = PDFOutline()
    second.label = "Page 2"
    second.destination = PDFDestination(page: document.page(at: 1)!, at: NSPoint(x: 0, y: 850))
    root.insertChild(first, at: 0)
    root.insertChild(second, at: 1)
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

private struct InternalLinkPDFFixture {
    let url: URL
    let linkBounds: NSRect
    let targetPageIndex: Int
    let targetPoint: NSPoint
}

@MainActor
private func makeTemporaryPDFWithInternalLink(named name: String) throws -> InternalLinkPDFFixture {
    let root = try TestPDFFixtures.makeRootDirectory()
    let url = root.appendingPathComponent("\(name).pdf")
    let pageSize = NSSize(width: 600, height: 900)
    let document = TestPDFFixtures.makeBlankDocument(pageCount: 4, pageSize: pageSize)
    let linkBounds = NSRect(x: 72, y: 700, width: 180, height: 64)
    let targetPageIndex = 3
    let targetPoint = NSPoint(x: 48, y: 640)
    guard let sourcePage = document.page(at: 0),
          let targetPage = document.page(at: targetPageIndex) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let link = PDFAnnotation(bounds: linkBounds, forType: .link, withProperties: nil)
    link.action = PDFActionGoTo(destination: PDFDestination(page: targetPage, at: targetPoint))
    sourcePage.addAnnotation(link)
    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return InternalLinkPDFFixture(
        url: url,
        linkBounds: linkBounds,
        targetPageIndex: targetPageIndex,
        targetPoint: targetPoint
    )
}

@MainActor
private func assertInternalLinkNavigationStaysCentered(in mode: ReaderDisplayMode) throws {
    let store = makeIsolatedDocumentStore()
    let controller = MainWindowController(documentStore: store)
    defer { controller.close() }
    let fixture = try makeTemporaryPDFWithInternalLink(named: "internal-link-\(mode.rawValue)")
    let session = try store.open(documentAt: fixture.url)
    store.setDisplayMode(mode, for: session.id)
    prepareMainWindowForLayoutTests(controller)
    flushLayout(controller.window)

    let window = try #require(controller.window)
    let splitController = try #require(window.contentViewController as? SplitViewController)
    let reader = splitController.readerViewController
    reader.fitToWidth()
    flushLayout(window)
    for _ in 0..<4 {
        reader.zoomOut()
    }
    flushLayout(window)
    assertDocumentVisuallyCentered(in: reader.pdfView, axes: .horizontal)

    let sourcePosition = try #require(store.session(for: session.id)?.lastReadPosition)
    let sourcePage = try #require(reader.pdfView.document?.page(at: 0))
    let linkPointOnPage = NSPoint(x: fixture.linkBounds.midX, y: fixture.linkBounds.midY)
    let linkPointInView = reader.pdfView.convert(linkPointOnPage, from: sourcePage)
    let linkPointInWindow = reader.pdfView.convert(linkPointInView, to: nil)

    reader.pdfView.mouseDown(with: mouseDownEvent(in: window, at: linkPointInWindow))
    flushLayout(window)

    let preview = try #require(reader.testingReferencePreviewContent)
    #expect(preview.destination.page === reader.pdfView.document?.page(at: fixture.targetPageIndex))
    #expect(store.session(for: session.id)?.lastReadPosition == sourcePosition)
    #expect(reader.testingNavigationBackPositions.isEmpty)
    let jumpButton = try #require(preview.view.subviews.compactMap { $0 as? NSButton }.first {
        $0.identifier?.rawValue == "referencePreviewJump"
    })
    let action = try #require(jumpButton.action)
    let actionTarget = try #require(jumpButton.target)
    #expect(jumpButton.sendAction(action, to: actionTarget))
    flushLayout(window)
    #expect(reader.testingReferencePreviewContent == nil)

    let target = ReadingPosition(pageIndex: fixture.targetPageIndex, point: fixture.targetPoint)
    #expect(store.session(for: session.id)?.lastReadPosition == target)
    #expect(reader.testingNavigationBackPositions.last == sourcePosition)
    assertDocumentVisuallyCentered(in: reader.pdfView, axes: .horizontal)

    reader.navigateBack()
    flushLayout(window)
    #expect(store.session(for: session.id)?.lastReadPosition == sourcePosition)
    assertDocumentVisuallyCentered(in: reader.pdfView, axes: .horizontal)

    reader.navigateForward()
    flushLayout(window)
    #expect(store.session(for: session.id)?.lastReadPosition == target)
    assertDocumentVisuallyCentered(in: reader.pdfView, axes: .horizontal)
}
