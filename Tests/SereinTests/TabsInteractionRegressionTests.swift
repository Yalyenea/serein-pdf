import AppKit
import XCTest
@testable import Serein

@MainActor
final class TabsInteractionRegressionTests: XCTestCase {
    func testTitlebarTabsBoundLongTitlesAndReserveTheHoverCloseButtonSpace() throws {
        let store = makeIsolatedDocumentStore()
        let first = store.newBlankTab()
        store.renameSession(String(repeating: "A long PDF title ", count: 20), for: first.id)
        _ = store.newBlankTab()
        store.setTabPresentationMode(.horizontalTitlebar)
        let controller = TitlebarTabsController(documentStore: store)
        let window = host(controller, size: NSSize(width: 900, height: 480))
        defer { window.close() }
        let items = findAllDescendants(of: TitlebarTabItemView.self, in: controller.view)
        let inactive = try XCTUnwrap(items.first { $0.sessionID == first.id })
        let selected = try XCTUnwrap(items.first { $0.isSelected })
        let close = try XCTUnwrap(findAllDescendants(of: NSButton.self, in: inactive).first {
            $0.toolTip == L10n.text("Close Tab", "关闭标签")
        })
        let selectedClose = try XCTUnwrap(findAllDescendants(of: NSButton.self, in: selected).first {
            $0.toolTip == L10n.text("Close Tab", "关闭标签")
        })
        XCTAssertLessThanOrEqual(inactive.frame.width, 196)
        XCTAssertGreaterThan(inactive.frame.width, 0)
        XCTAssertEqual(close.alphaValue, 0)
        XCTAssertEqual(selectedClose.alphaValue, 1)
        let originalFrame = inactive.frame
        let originalLabelFrame = try XCTUnwrap(findDescendant(of: NSTextField.self, in: inactive)).frame
        let closePoint = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: inactive.superview)
        XCTAssertTrue(inactive.hitTest(closePoint) is TabDragSourceButton)

        let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        inactive.mouseEntered(with: enter)
        window.layoutIfNeeded()
        XCTAssertEqual(close.alphaValue, 1)
        XCTAssertTrue(inactive.hitTest(closePoint) === close)
        XCTAssertEqual(inactive.frame, originalFrame)
        XCTAssertEqual(findDescendant(of: NSTextField.self, in: inactive)?.frame, originalLabelFrame)

        let exit = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        inactive.mouseExited(with: exit)
        XCTAssertEqual(close.alphaValue, 0)
        XCTAssertTrue(inactive.hitTest(closePoint) is TabDragSourceButton)
    }

    func testReturnStartsEditingThroughEventMonitorAndSecondReturnSaves() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let session = store.newBlankTab()
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(item))

            NSApp.sendEvent(makeReturnKeyEvent(in: window))

            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            XCTAssertTrue(field.isEditable)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertTrue(window.firstResponder === editor)
            editor.insertText("Renamed tab", replacementRange: editor.selectedRange())
            NSApp.sendEvent(makeReturnKeyEvent(in: window))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))

            XCTAssertEqual(store.session(for: session.id)?.title, "Renamed tab")
            XCTAssertFalse(field.isEditable)
            XCTAssertTrue(window.firstResponder === selectedTab(in: controller.view))
        }
    }

    func testReturnRespectsOtherControlsAndHiddenTabUI() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            _ = store.newBlankTab()
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            let table = NSTableView(frame: NSRect(x: 600, y: 40, width: 100, height: 100))
            window.contentView?.addSubview(table)
            XCTAssertTrue(window.makeFirstResponder(table))
            XCTAssertNotNil(handleRenameEvent(makeReturnKeyEvent(in: window), controller: controller))
            XCTAssertFalse(field.isEditable)

            let outline = NSOutlineView(frame: table.frame)
            window.contentView?.addSubview(outline)
            XCTAssertTrue(window.makeFirstResponder(outline))
            XCTAssertNotNil(handleRenameEvent(makeReturnKeyEvent(in: window), controller: controller))
            XCTAssertFalse(field.isEditable)

            XCTAssertTrue(window.makeFirstResponder(item))
            controller.view.isHidden = true
            XCTAssertNotNil(handleRenameEvent(makeReturnKeyEvent(in: window), controller: controller))
            XCTAssertFalse(field.isEditable)
        }
    }

    func testVerticalTabRenameFollowsDocumentPaneVisibilityInHorizontalMode() throws {
        for swapped in [false, true] {
            var configuration = AppConfiguration.default
            configuration.layout.sidebarsSwapped = swapped
            let store = makeIsolatedDocumentStore(appConfiguration: configuration)
            _ = store.newBlankTab()
            store.setTabPresentationMode(.horizontalTitlebar)
            if swapped {
                store.setRightSidebarVisible(true, in: store.defaultWindowID)
            } else {
                store.setLeftSidebarVisible(true, in: store.defaultWindowID)
            }
            let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
            let window = host(controller, size: NSSize(width: 240, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(item))
            XCTAssertNil(controller.testingHandleRenameKeyEvent(makeReturnKeyEvent(in: window)))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            XCTAssertTrue(field.isEditable)
            XCTAssertTrue(window.makeFirstResponder(item))
            if swapped {
                store.setRightSidebarVisible(false, in: store.defaultWindowID)
            } else {
                store.setLeftSidebarVisible(false, in: store.defaultWindowID)
            }
            XCTAssertTrue(window.makeFirstResponder(item))
            XCTAssertNotNil(controller.testingHandleRenameKeyEvent(makeReturnKeyEvent(in: window)))
            XCTAssertFalse(field.isEditable)
        }
    }

    func testClickingTabRetainsTabFocusAfterActivationRebuild() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let first = store.newBlankTab()
            _ = store.newBlankTab()
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(tabItems(in: controller.view).first)
            let button = try XCTUnwrap(item.hitTest(NSPoint(x: item.frame.midX, y: item.frame.midY)) as? NSButton)
            XCTAssertTrue(button.sendAction(button.action, to: button.target))
            XCTAssertEqual(store.activeSessionID, first.id)
            XCTAssertTrue(window.firstResponder === selectedTab(in: controller.view))
            XCTAssertNil(handleRenameEvent(makeReturnKeyEvent(in: window), controller: controller))
        }
    }

    func testComparisonPaneKeepsOwningTabActiveInBothPresentations() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "tab-comparison-active"))
        let vertical = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        let horizontal = TitlebarTabsController(documentStore: store)
        vertical.loadViewIfNeeded()
        horizontal.loadViewIfNeeded()
        XCTAssertNotNil(store.splitPane(from: .primary, layout: .sideBySide, in: store.defaultWindowID))
        XCTAssertNotEqual(store.activeSessionID, session.id)
        XCTAssertEqual(findAllDescendants(of: VerticalTabItemView.self, in: vertical.view).filter(\.isSelected).count, 1)
        XCTAssertEqual(findAllDescendants(of: TitlebarTabItemView.self, in: horizontal.view).filter(\.isSelected).count, 1)
    }

    func testTitlebarActiveTabScrollsIntoViewAfterActivationAndResize() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = (0..<24).map { _ in store.newBlankTab() }
        store.setTabPresentationMode(.horizontalTitlebar)
        let controller = TitlebarTabsController(documentStore: store)
        controller.setAvailableWidth(540)
        let window = host(controller, size: NSSize(width: 800, height: 480))
        defer { window.close() }
        let scroll = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: controller.view))
        assertSelectedTabVisible(in: controller.view, scroll: scroll)

        store.activateTab(sessionID: sessions[0].id, in: store.defaultWindowID)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        assertSelectedTabVisible(in: controller.view, scroll: scroll)
        XCTAssertLessThanOrEqual(scroll.documentVisibleRect.minX, 6)

        store.activateTab(sessionID: sessions[23].id, in: store.defaultWindowID)
        controller.setAvailableWidth(320)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.preferredContentSize.width, 320, accuracy: 0.5)
        assertSelectedTabVisible(in: controller.view, scroll: scroll)
    }

    func testManyVerticalTabsScrollWithoutIncreasingWindowHeight() throws {
        let store = makeIsolatedDocumentStore()
        let sessions = (0..<70).map { _ in store.newBlankTab() }
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = host(controller, size: NSSize(width: 240, height: 480))
        defer { window.close() }
        let scroll = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: controller.view))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertEqual(window.contentView?.frame.height ?? 0, 480, accuracy: 0.5)
        XCTAssertGreaterThan(document.frame.height, scroll.documentVisibleRect.height)
        assertSelectedTabVisible(in: controller.view, scroll: scroll)

        store.activateTab(sessionID: sessions[0].id, in: store.defaultWindowID)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        assertSelectedTabVisible(in: controller.view, scroll: scroll)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 1)
        XCTAssertEqual(window.contentView?.frame.height ?? 0, 480, accuracy: 0.5)
    }

    func testRecentSidebarReordersWhenOpenFileIsReopenedInAnotherWindow() throws {
        let store = makeIsolatedDocumentStore()
        let firstURL = try TestPDFFixtures.makeBlankPDF(named: "tab-recent-first")
        let secondURL = try TestPDFFixtures.makeBlankPDF(named: "tab-recent-second")
        _ = try store.open(documentAt: firstURL)
        _ = try store.open(documentAt: secondURL)
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let otherWindowID = store.createWindow()
        _ = try store.open(documentAt: firstURL, in: otherWindowID)
        XCTAssertEqual(controller.testingRecentFileTitles, ["tab-recent-first", "tab-recent-second"])
    }

    func testContinuousReadingMenuCountsOnlyPDFsInBothTabPresentations() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let first = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "tab-continuous-first"))
            let blank = store.newBlankTab()
            store.selectSessions([first.id, blank.id], in: store.defaultWindowID)
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            XCTAssertFalse(try continuousReadingMenuItem(in: controller.view, window: window).isEnabled)

            let second = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "tab-continuous-second"))
            store.selectSessions([first.id, blank.id, second.id], in: store.defaultWindowID)
            XCTAssertTrue(try continuousReadingMenuItem(in: controller.view, window: window).isEnabled)
        }
    }

    func testTabRenameEditorsRefreshForEveryThemeAndCustomBackground() throws {
        let originalTheme = ThemeManager.shared.selection
        defer {
            ThemeManager.shared.apply(
                light: originalTheme.light, dark: originalTheme.dark,
                lightBackground: originalTheme.lightBackground, darkBackground: originalTheme.darkBackground
            )
        }
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            _ = store.newBlankTab()
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(item))
            NSApp.sendEvent(makeReturnKeyEvent(in: window))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("Unsaved title", replacementRange: editor.selectedRange())

            for light in LightTheme.allCases {
                window.appearance = NSAppearance(named: .aqua)
                ThemeManager.shared.apply(light: light, dark: .rosePineMoon)
                refreshColors(controller)
                assertEditingColors(field: field, editor: editor, appearance: item.effectiveAppearance)
            }
            for dark in DarkTheme.allCases {
                window.appearance = NSAppearance(named: .darkAqua)
                ThemeManager.shared.apply(light: .normal, dark: dark)
                refreshColors(controller)
                assertEditingColors(field: field, editor: editor, appearance: item.effectiveAppearance)
            }
            let background = ThemeBackgroundOverrides(window: try XCTUnwrap(ThemeHexColor(hex: "#102035")))
            ThemeManager.shared.apply(light: .normal, dark: .normal, lightBackground: background, darkBackground: background)
            refreshColors(controller)
            assertEditingColors(field: field, editor: editor, appearance: item.effectiveAppearance)
            XCTAssertEqual(editor.string, "Unsaved title")
            XCTAssertTrue(window.firstResponder === editor)
        }
    }

    func testRenameDraftAndFieldEditorSurviveTabAndRecentRefreshes() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let firstURL = try TestPDFFixtures.makeBlankPDF(named: "tab-draft-first")
            _ = try store.open(documentAt: firstURL)
            let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "tab-draft-edited"))
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(item))
            NSApp.sendEvent(makeReturnKeyEvent(in: window))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("Keep this draft", replacementRange: editor.selectedRange())

            store.setDirty(true, for: session.id)
            let otherWindowID = store.createWindow()
            _ = try store.open(documentAt: firstURL, in: otherWindowID)
            window.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()

            XCTAssertTrue(selectedTab(in: controller.view) === item)
            XCTAssertTrue(field.currentEditor() === editor)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(editor.string, "Keep this draft")
            XCTAssertTrue(field.isEditable)
        }
    }

    func testClickingAnotherTabCommitsRenameBeforeEditedItemIsRebuilt() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let first = store.newBlankTab()
            let editedSession = store.newBlankTab()
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let editedItem = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(editedItem))
            NSApp.sendEvent(makeReturnKeyEvent(in: window))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: editedItem))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("Saved by tab switch", replacementRange: editor.selectedRange())
            let otherItem = try XCTUnwrap(tabItems(in: controller.view).first)
            let button = try XCTUnwrap(otherItem.hitTest(NSPoint(x: otherItem.frame.midX, y: otherItem.frame.midY)) as? NSButton)
            button.performClick(nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))

            XCTAssertEqual(store.activeSessionID, first.id)
            XCTAssertEqual(store.session(for: editedSession.id)?.title, "Saved by tab switch")
            XCTAssertFalse(field.isEditable)
        }
    }

    func testWorkspaceSwitchCommitsTabRenameBeforeRemovingItsEditor() throws {
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let originalID = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
            let session = store.newBlankTab()
            _ = store.createWorkspace(name: "Empty workspace", in: store.defaultWindowID)
            store.activateWorkspace(originalID, in: store.defaultWindowID)
            store.setTabPresentationMode(mode)
            let controller = makeTabsController(mode: mode, store: store)
            let window = host(controller, size: NSSize(width: 800, height: 480))
            defer { window.close() }
            let item = try XCTUnwrap(selectedTab(in: controller.view))
            XCTAssertTrue(window.makeFirstResponder(item))
            NSApp.sendEvent(makeReturnKeyEvent(in: window))
            let field = try XCTUnwrap(findDescendant(of: NSTextField.self, in: item))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("Saved across workspaces", replacementRange: editor.selectedRange())

            XCTAssertTrue(store.activateAdjacentWorkspace(direction: 1, in: store.defaultWindowID))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))

            XCTAssertEqual(store.session(for: session.id)?.title, "Saved across workspaces")
            XCTAssertFalse(field.isEditable)
            XCTAssertFalse(window.firstResponder === editor)
            XCTAssertTrue(store.sessions(in: store.defaultWindowID).isEmpty)
            store.activateWorkspace(originalID, in: store.defaultWindowID)
            XCTAssertEqual(store.activeSession?.title, "Saved across workspaces")
        }
    }

    private func makeTabsController(mode: TabPresentationMode, store: DocumentStore) -> NSViewController {
        mode == .verticalSidebar
            ? VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
            : TitlebarTabsController(documentStore: store)
    }

    private func host(_ controller: NSViewController, size: NSSize) -> NSWindow {
        _ = NSApplication.shared
        controller.loadViewIfNeeded()
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controller.view)
        var constraints = [
            controller.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            controller.view.topAnchor.constraint(equalTo: root.topAnchor),
        ]
        if controller is VerticalTabsViewController {
            constraints += [
                controller.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        root.layoutSubtreeIfNeeded()
        return window
    }

    private func tabItems(in root: NSView) -> [NSView] {
        findAllDescendants(of: VerticalTabItemView.self, in: root).map { $0 as NSView }
            + findAllDescendants(of: TitlebarTabItemView.self, in: root).map { $0 as NSView }
    }

    private func selectedTab(in root: NSView) -> NSView? {
        tabItems(in: root).first {
            ($0 as? VerticalTabItemView)?.isSelected == true || ($0 as? TitlebarTabItemView)?.isSelected == true
        }
    }

    private func handleRenameEvent(_ event: NSEvent, controller: NSViewController) -> NSEvent? {
        if let controller = controller as? VerticalTabsViewController {
            return controller.testingHandleRenameKeyEvent(event)
        }
        return (controller as! TitlebarTabsController).testingHandleRenameKeyEvent(event)
    }

    private func refreshColors(_ controller: NSViewController) {
        if let controller = controller as? VerticalTabsViewController {
            controller.refreshChromeColors()
        } else {
            (controller as! TitlebarTabsController).refreshChromeColors()
        }
    }

    private func assertSelectedTabVisible(in root: NSView, scroll: NSScrollView, file: StaticString = #filePath, line: UInt = #line) {
        guard let item = selectedTab(in: root), let document = scroll.documentView else {
            XCTFail("Missing selected tab", file: file, line: line)
            return
        }
        let rect = document.convert(item.bounds, from: item)
        XCTAssertTrue(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(rect), "tab \(rect), viewport \(scroll.documentVisibleRect)", file: file, line: line)
    }

    private func continuousReadingMenuItem(in root: NSView, window: NSWindow) throws -> NSMenuItem {
        let item = try XCTUnwrap(selectedTab(in: root))
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let menu = try XCTUnwrap(item.menu(for: event))
        return try XCTUnwrap(menu.item(withTitle: "Start Continuous Reading"))
    }

    private func assertEditingColors(field: NSTextField, editor: NSTextView, appearance: NSAppearance) {
        XCTAssertTrue(field.isEditable)
        XCTAssertEqual(editor.string, "Unsaved title")
        appearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(field.backgroundColor?.usingColorSpace(.sRGB), NightModeStyle.readerBackdropColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.backgroundColor.usingColorSpace(.sRGB), NightModeStyle.readerBackdropColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.textColor?.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.insertionPointColor.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
        }
    }
}
