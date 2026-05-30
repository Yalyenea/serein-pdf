import AppKit
import Foundation
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct WindowChromeTests {
    @Test
    func mainWindowDoesNotUseAppKitStateRestoration() {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: DocumentStore(appConfiguration: .default))

        #expect(controller.window?.isRestorable == false)
    }

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
    func transparentTitlebarDragAreaIsReservedBeforePDFContent() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: DocumentStore(appConfiguration: .default))
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
        let store = DocumentStore(appConfiguration: .default)
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
    func readerHidesPDFKitDocumentTreeFromAccessibilityInspection() {
        _ = NSApplication.shared
        let controller = ReaderViewController(documentStore: DocumentStore(appConfiguration: .default))
        controller.loadViewIfNeeded()

        #expect(controller.pdfView.isAccessibilityElement() == false)
        #expect(controller.pdfView.accessibilityChildren()?.isEmpty == true)
    }

    @Test
    func highlightModeUsesCompactInlineIndicator() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = ReaderViewController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.triggerHighlightShortcut() == false)
        controller.view.layoutSubtreeIfNeeded()

        let highlightLabels = textFields(in: controller.view)
            .filter { $0.stringValue.contains("Highlight") }
            .map(\.stringValue)

        #expect(highlightLabels.contains("Highlight · Esc"))
        #expect(highlightLabels.contains { $0.contains("Highlight Mode") } == false)
    }

    @Test
    func switchingPDFShowsBriefFileNameToast() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
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

        let store = DocumentStore(appConfiguration: .default)
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

        #expect(reader.pdfView.displaysPageBreaks == false)
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
    func switchingFromLightToDarkRetintsPDFMargins() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = previousAppearance }

        let store = DocumentStore(appConfiguration: .default)
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
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = DocumentStore(appConfiguration: .default)
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

        NightModeStyle.applyThemeSelections(light: .rosePineDawn, dark: .rosePineMoon)
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
        NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = DocumentStore(appConfiguration: .default)
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

        NightModeStyle.applyThemeSelections(light: .rosePineDawn, dark: .rosePineMoon)
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
    func collapsedRightSidebarStaysCollapsedAfterStoreRefresh() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        #expect(store.splitCandidateSessions(in: controller.windowID).map(\.id).count == 1)

        controller.toggleReaderSplit()
        controller.window?.layoutIfNeeded()
        #expect(controller.isReaderSplitEnabled == false)
    }

    @Test
    func alternateTabActivationUsesBrowserSplitEditSemantics() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
    func immersiveModeHidesChromeAndRestoresHorizontalTitlebarLayout() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        let windowID = controller.windowID
        _ = try store.open(documentAt: makeTemporaryPDF(named: "demo-mode"))

        store.setTabPresentationMode(.horizontalTitlebar, in: windowID)
        store.setLeftSidebarVisible(false, in: windowID)
        store.setRightSidebarVisible(true, in: windowID)
        flushLayout(controller.window)

        #expect(controller.window?.toolbar != nil)
        #expect(controller.isImmersiveModeEnabled == false)

        controller.toggleImmersiveMode()
        flushLayout(controller.window)

        #expect(controller.isImmersiveModeEnabled)
        #expect(controller.window?.toolbar == nil)
        #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == false)

        controller.toggleImmersiveMode()
        flushLayout(controller.window)

        #expect(controller.isImmersiveModeEnabled == false)
        #expect(controller.window?.toolbar != nil)
        #expect(store.tabPresentationMode(in: windowID) == .horizontalTitlebar)
        #expect(store.isLeftSidebarVisible(in: windowID) == false)
        #expect(store.isRightSidebarVisible(in: windowID) == true)
    }

    @Test
    func demoModeEntersImmersiveModeAndRestoresPreviousImmersiveState() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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

        guard let expectedScale = fitPageScaleExpected(for: splitController.readerViewController.pdfView) else {
            Issue.record("Failed to compute fit-page scale")
            return
        }

        #expect(store.session(for: session.id)?.displayMode == .singlePage)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - expectedScale) < 0.05)

        controller.toggleDemoMode()
        flushLayout(controller.window)

        #expect(store.session(for: session.id)?.displayMode == .singlePageContinuous)
        #expect(store.session(for: session.id)?.scaleMode == .fitWidth)
    }

    @Test
    func demoModeLeavesPreexistingImmersiveModeEnabledOnExit() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
    func closeFocusedPaneInSplitCollapsesToSinglePane() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
    func outlineSelectionNavigatesReaderToTargetPage() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        _ = try store.open(documentAt: makeTemporaryPDFWithOutline(named: "outline-navigation"))
        flushLayout(controller.window)

        guard let splitController = controller.window?.contentViewController as? SplitViewController,
              let outlineScrollView = splitController.rightSidebarViewController.outlineViewController.view.subviews
                .compactMap({ $0 as? NSScrollView })
                .first,
              let outlineView = outlineScrollView.documentView as? NSOutlineView,
              let document = splitController.readerViewController.pdfView.document else {
            Issue.record("Failed to locate outline UI")
            return
        }

        outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        flushLayout(controller.window)

        let currentPageIndex = splitController.readerViewController.pdfView.currentPage.map { document.index(for: $0) }
        #expect(currentPageIndex == 1)
    }

    @Test
    func continuousReadingNextPageActivatesNextPDF() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
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

        controller.goToNextPage()
        flushLayout(controller.window)

        #expect(store.activeSessionID == sessions[1].id)
        #expect(store.session(for: sessions[1].id)?.currentPageIndex == 0)
    }

    @Test
    func continuousReadingPreviousPageActivatesPreviousPDFLastPage() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
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

        controller.goToPreviousPage()
        flushLayout(controller.window)

        #expect(store.activeSessionID == sessions[0].id)
        #expect(store.session(for: sessions[0].id)?.currentPageIndex == 1)
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
    func enablingSplitFitsBothReadersToPaneWidth() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
    func settingsWindowUsesAdaptiveGeneralSize() {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        controller.showWindow(nil)

        #expect(controller.window?.contentRect(forFrameRect: controller.window?.frame ?? .zero).size == NSSize(width: 560, height: 440))
    }

    @Test
    func settingsWindowSwitchesBetweenPageSizes() throws {
        let controller = SettingsWindowController(configuration: .default) { _ in }
        controller.showWindow(nil)

        let window = try #require(controller.window)
        controller.selectPageForTesting(1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 460))

        controller.selectPageForTesting(2)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 920, height: 620))

        controller.selectPageForTesting(0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 560, height: 440))
    }

    @Test
    func settingsWindowCanEditSidebarDefaultWidths() throws {
        _ = NSApplication.shared
        var publishedConfigurations: [AppConfiguration] = []
        let controller = SettingsWindowController(configuration: .default) { configuration in
            publishedConfigurations.append(configuration)
        }
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
    func settingsWindowOpensWithConfiguredLibraryFolders() throws {
        var configuration = AppConfiguration.default
        configuration.library.folderURLs = [URL(fileURLWithPath: "/Users/your-name/Documents/Papers")]
        let controller = SettingsWindowController(configuration: configuration) { _ in }
        controller.showWindow(nil)

        let window = try #require(controller.window)
        controller.selectPageForTesting(1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(window.title == "Settings")
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 460))
    }

    @Test
    func mainWindowUsesUpdatedReaderFramingDefaults() {
        let controller = MainWindowController(documentStore: DocumentStore(appConfiguration: .default))
        let contentSize = controller.window?.contentRect(forFrameRect: controller.window?.frame ?? .zero).size

        #expect(contentSize == MainWindowController.defaultContentSize)
        #expect(controller.window?.minSize == MainWindowController.minimumWindowSize)
    }

    @Test
    func mainWindowSupportsSystemGreenButtonTilingActions() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(documentStore: DocumentStore(appConfiguration: .default))
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
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        defer { app.appearance = previousAppearance }

        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
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
        for _ in 0..<6 {
            flushLayout(controller.window)
        }

        guard let afterAnchor = visibleDocumentCenter(in: reader.pdfView) else {
            Issue.record("Failed to capture post-zoom anchor")
            return
        }

        #expect(abs(afterAnchor.x - beforeAnchor.x) < 2.0)
        #expect(abs(afterAnchor.y - beforeAnchor.y) < 8.0)
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
    func halfPageScrollDoesNotDriftAfterSettling() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        _ = try store.open(
            documentAt: makeTemporaryPDF(
                named: "half-page-scroll-settle",
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

        controller.scrollHalfPageDown()
        flushLayout(controller.window)
        let settledDownOrigin = clipView.bounds.origin.y
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        controller.window?.layoutIfNeeded()
        let settledAgainDownOrigin = clipView.bounds.origin.y
        #expect(abs(settledAgainDownOrigin - settledDownOrigin) < 1.0)

        controller.scrollHalfPageUp()
        flushLayout(controller.window)
        let settledUpOrigin = clipView.bounds.origin.y
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        controller.window?.layoutIfNeeded()
        let settledAgainUpOrigin = clipView.bounds.origin.y
        #expect(abs(settledAgainUpOrigin - settledUpOrigin) < 1.0)
    }

    @Test
    func halfPageScrollDoesNotDriftAfterSettlingWithOutlineSidebarVisible() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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

        controller.scrollHalfPageDown()
        flushLayout(controller.window)
        let settledDownOrigin = clipView.bounds.origin.y
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
            let store = DocumentStore(appConfiguration: .default)
            let controller = MainWindowController(documentStore: store)
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
    func fitHeightUsesPDFKitRowHeight() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        #expect(reader.triggerHighlightShortcut() == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - zoomedScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - zoomedScale) < 0.001)
    }

    @Test
    func highlightingAfterDirectPDFViewScaleChangeKeepsManualScale() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        #expect(reader.triggerHighlightShortcut() == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - targetScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - targetScale) < 0.001)
    }

    @Test
    func pageTurnKeepsManualScale() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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

        #expect(abs(reader.pdfView.scaleFactor - originalScale) < 0.001)
        #expect(store.session(for: session.id)?.currentPageIndex == 1)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - originalScale) < 0.001)
    }

    @Test
    func rapidPageTurnsSettleWithoutResidualDrift() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
        #expect(abs(afterWaitOrigin.x - settledOrigin.x) < 0.5)
        #expect(abs(afterWaitOrigin.y - settledOrigin.y) < 0.5)
        #expect(abs(afterWaitOrigin.y * backingScale - (afterWaitOrigin.y * backingScale).rounded()) < 0.001)
    }

    @Test
    func highlightingKeepsLiveManualScaleWhenStoreMissedScaleChange() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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

        NotificationCenter.default.removeObserver(
            reader,
            name: Notification.Name.PDFViewScaleChanged,
            object: reader.pdfView
        )

        let fitScale = reader.pdfView.scaleFactor
        let manualScale = min(fitScale * 1.2, reader.pdfView.maxScaleFactor)
        reader.pdfView.scaleFactor = manualScale
        flushLayout(controller.window)

        guard let selection = reader.pdfView.document?.findString("DeepSeek", withOptions: .caseInsensitive).first else {
            Issue.record("Failed to locate selectable text for highlighting")
            return
        }

        reader.pdfView.currentSelection = selection
        #expect(reader.triggerHighlightShortcut() == true)
        flushLayout(controller.window)

        #expect(abs(reader.pdfView.scaleFactor - manualScale) < 0.001)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs((store.session(for: session.id)?.zoomScale ?? 0) - manualScale) < 0.001)
    }

    @Test
    func storeRefreshKeepsLivePageWhenStoreMissedPageChange() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
    func fitWidthSkipsProgrammaticReapplyWhenTargetScaleIsAlreadyActive() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
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
private func textFields(in root: NSView) -> [NSTextField] {
    var matches: [NSTextField] = []
    var pending = [root]
    while let view = pending.popLast() {
        if let textField = view as? NSTextField {
            matches.append(textField)
        }
        pending.append(contentsOf: view.subviews)
    }
    return matches
}

@MainActor
private func textField(identifier: String, in root: NSView) -> NSTextField? {
    textFields(in: root).first { $0.identifier?.rawValue == identifier }
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

@MainActor
private func makeSelectableTemporaryPDF(named name: String, text: String) throws -> URL {
    let size = NSSize(width: 480, height: 240)
    let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
    textView.string = text
    textView.font = NSFont.systemFont(ofSize: 28, weight: .regular)
    textView.textContainerInset = NSSize(width: 24, height: 32)
    let data = textView.dataWithPDF(inside: textView.bounds)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    try data.write(to: url)
    return url
}

@MainActor
private func makeTemporaryPDFWithOutline(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    for index in 0..<2 {
        let pageSize = NSSize(width: 320, height: 480)
        let image = NSImage(size: pageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: pageSize)).fill()
        NSString(string: "Outline \(index + 1)").draw(
            in: NSRect(x: 36, y: 220, width: 200, height: 40),
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
    first.destination = PDFDestination(page: document.page(at: 0)!, at: .zero)
    let second = PDFOutline()
    second.label = "Page 2"
    second.destination = PDFDestination(page: document.page(at: 1)!, at: .zero)
    root.insertChild(first, at: 0)
    root.insertChild(second, at: 1)
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}
