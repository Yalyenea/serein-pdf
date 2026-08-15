import AppKit
import PDFKit
import XCTest
@testable import Serein

private final class VTRecordingWindow: NSWindow {
    private(set) var windowDragCount = 0

    override func performDrag(with event: NSEvent) {
        windowDragCount += 1
    }
}

@MainActor
final class VerticalTabsViewControllerTests: XCTestCase {
    func testRecentFooterShowsAndOpensMostRecentURL() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let firstURL = try makeTemporaryPDF(named: "recent-sidebar-first")
        let secondURL = try makeTemporaryPDF(named: "recent-sidebar-second")
        _ = try store.open(documentAt: firstURL)
        _ = try store.open(documentAt: secondURL)

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        var openedURL: URL?
        controller.onOpenRecentURLRequested = { openedURL = $0 }
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.testingRecentSectionVisible)
        XCTAssertEqual(controller.testingRecentFileTitles, ["recent-sidebar-second", "recent-sidebar-first"])

        controller.testingTriggerOpenRecent(at: 0)
        XCTAssertEqual(openedURL, secondURL)
    }

    func testRecentFooterRespectsSettingsToggle() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.showRecentFilesInSidebar = false
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeTemporaryPDF(named: "recent-sidebar-hidden"))

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertFalse(controller.testingRecentSectionVisible)
        XCTAssertTrue(controller.testingRecentFileTitles.isEmpty)
    }

    func testRecentFooterAdaptsToSidebarWidthChanges() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "recent-sidebar-width"))

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.testingRecentSectionVisible)

        controller.view.frame = NSRect(x: 0, y: 0, width: 180, height: 460)
        controller.view.layoutSubtreeIfNeeded()
        let narrowListWidth = controller.testingRecentListWidth
        let narrowButtonWidth = controller.testingRecentButtonWidths.first ?? 0

        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 460)
        controller.view.layoutSubtreeIfNeeded()
        let wideListWidth = controller.testingRecentListWidth
        let wideButtonWidth = controller.testingRecentButtonWidths.first ?? 0

        XCTAssertGreaterThan(wideListWidth, narrowListWidth)
        XCTAssertGreaterThan(wideButtonWidth, narrowButtonWidth)
    }

    func testEmptyWindowShowsDocumentsHeaderAndSharedHint() throws {
        _ = NSApplication.shared
        let store = makeStore()

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 240, height: 360)
        controller.view.layoutSubtreeIfNeeded()
        let emptyState = try XCTUnwrap(
            findDescendant(of: EmptyStateView.self, in: controller.view)
        )

        XCTAssertEqual(controller.testingDocumentsTitle, "Documents")
        XCTAssertTrue(controller.testingEmptyStateVisible)
        XCTAssertFalse(controller.testingCountLabelVisible)
        XCTAssertFalse(controller.testingRecentSectionVisible)
        XCTAssertEqual(emptyState.frame.width, 216, accuracy: 0.5)
        XCTAssertGreaterThan(emptyState.frame.height, 0)
    }

    func testEmptyWindowMovesRecentFilesUpUnderHeader() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let firstURL = try makeTemporaryPDF(named: "empty-recents-first")
        let secondURL = try makeTemporaryPDF(named: "empty-recents-second")
        let first = try store.open(documentAt: firstURL)
        let second = try store.open(documentAt: secondURL)
        store.close(sessionID: second.id, from: store.defaultWindowID)
        store.close(sessionID: first.id, from: store.defaultWindowID)

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertTrue(store.sessions(in: store.defaultWindowID).isEmpty)
        XCTAssertTrue(controller.testingRecentSectionVisible)
        XCTAssertTrue(controller.testingRecentSectionTopPinned)
        XCTAssertFalse(controller.testingEmptyStateVisible)
        XCTAssertEqual(
            controller.testingRecentFileTitles,
            ["empty-recents-second", "empty-recents-first"]
        )
    }

    func testEmptyWindowHintShowsWhenRecentsDisabled() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.showRecentFilesInSidebar = false
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let url = try makeTemporaryPDF(named: "empty-recents-disabled")
        let session = try store.open(documentAt: url)
        store.close(sessionID: session.id, from: store.defaultWindowID)

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.testingEmptyStateVisible)
        XCTAssertFalse(controller.testingRecentSectionVisible)
    }

    func testNonEmptyWindowShowsCountAndBottomPinnedRecents() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-count-first"))
        _ = try store.open(documentAt: makeTemporaryPDF(named: "empty-count-second"))

        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()

        XCTAssertFalse(controller.testingEmptyStateVisible)
        XCTAssertTrue(controller.testingCountLabelVisible)
        XCTAssertTrue(controller.testingRecentSectionVisible)
        XCTAssertFalse(controller.testingRecentSectionTopPinned)
    }

    func testVerticalTabsReturnRenameStaysInOwnWindow() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "vertical-return-own-window"))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeWindow(for: controller.view)
        defer { window.close() }

        XCTAssertNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: window)))
        XCTAssertTrue(controller.testingIsSelectedTabEditing)
    }

    func testVerticalTabsReturnRenameIgnoresOtherWindowsAndTextEditing() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "vertical-return-scoped"))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeWindow(for: controller.view)
        let otherWindow = makeWindow(for: NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120)))
        defer {
            otherWindow.close()
            window.close()
        }

        XCTAssertNotNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: otherWindow)))
        XCTAssertFalse(controller.testingIsSelectedTabEditing)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        controller.view.addSubview(textView)
        window.makeFirstResponder(textView)

        XCTAssertNotNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: window)))
        XCTAssertFalse(controller.testingIsSelectedTabEditing)
    }

    func testVerticalTabsEmptyBackgroundDragsWindowWithoutStealingTabControls() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "vertical-background-drag"))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeRecordingWindow(for: controller.view)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()

        let backgroundView = try XCTUnwrap(controller.testingWindowDragBackgroundView)
        let blankPoint = try XCTUnwrap(firstPoint(in: controller.view) { point in
            controller.view.hitTest(point) === backgroundView
        })
        let tabItem = try XCTUnwrap(findDescendant(of: VerticalTabItemView.self, in: controller.view))
        let tabPoint = controller.view.convert(
            NSPoint(x: tabItem.bounds.midX, y: tabItem.bounds.midY),
            from: tabItem
        )
        let closeButton = try XCTUnwrap(findButton(titled: "×", in: tabItem))
        let closePoint = controller.view.convert(
            NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
            from: closeButton
        )

        XCTAssertTrue(controller.view.hitTest(blankPoint) === backgroundView)
        XCTAssertFalse(controller.view.hitTest(tabPoint) === backgroundView)
        XCTAssertTrue(controller.view.hitTest(closePoint) === closeButton)
        XCTAssertTrue(backgroundView.acceptsFirstMouse(for: nil))

        let blankPointInBackground = backgroundView.convert(blankPoint, from: controller.view)
        backgroundView.mouseDown(
            with: mouseDownEvent(
                in: window,
                at: backgroundView.convert(blankPointInBackground, to: nil)
            )
        )

        XCTAssertEqual(window.windowDragCount, 1)
    }

    func testVerticalTabsBlankDoubleClickDoesNotRenameSelectedTab() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "vertical-background-double-click"))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeWindow(for: controller.view)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()

        let backgroundView = try XCTUnwrap(controller.testingWindowDragBackgroundView)
        let blankPoint = try XCTUnwrap(firstPoint(in: controller.view) { point in
            controller.view.hitTest(point) === backgroundView
        })
        let blankPointInWindow = controller.view.convert(blankPoint, to: nil)

        XCTAssertNotNil(
            controller.testingHandleRenameMouseEvent(
                mouseDownEvent(in: window, at: blankPointInWindow, clickCount: 2)
            )
        )
        XCTAssertFalse(controller.testingIsSelectedTabEditing)

        let tabItem = try XCTUnwrap(findDescendant(of: VerticalTabItemView.self, in: controller.view))
        let tabPointInWindow = tabItem.convert(
            NSPoint(x: tabItem.bounds.midX, y: tabItem.bounds.midY),
            to: nil
        )
        XCTAssertNil(
            controller.testingHandleRenameMouseEvent(
                mouseDownEvent(in: window, at: tabPointInWindow, clickCount: 2)
            )
        )
        XCTAssertTrue(controller.testingIsSelectedTabEditing)
    }

    func testTitlebarTabsReturnRenameRequiresVisibleHorizontalModeOwnWindow() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-return-own-window"))
        store.setTabPresentationMode(.horizontalTitlebar, in: store.defaultWindowID)
        let controller = TitlebarTabsController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeWindow(for: controller.view)
        defer { window.close() }

        XCTAssertNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: window)))
        XCTAssertTrue(controller.testingIsSelectedTabEditing)
    }

    func testTitlebarTabsReturnRenameIgnoresOtherWindowsAndHiddenStrip() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "titlebar-return-scoped"))
        store.setTabPresentationMode(.horizontalTitlebar, in: store.defaultWindowID)
        let controller = TitlebarTabsController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = makeWindow(for: controller.view)
        let otherWindow = makeWindow(for: NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120)))
        defer {
            otherWindow.close()
            window.close()
        }

        XCTAssertNotNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: otherWindow)))
        XCTAssertFalse(controller.testingIsSelectedTabEditing)

        controller.setTabsStripVisible(false)
        XCTAssertNotNil(controller.testingHandleRenameKeyEvent(returnKeyEvent(in: window)))
        XCTAssertFalse(controller.testingIsSelectedTabEditing)
    }

    func testTabDragPayloadRoundTripsThroughPasteboard() throws {
        let payload = TabDragPayload(sourceWindowID: UUID(), sessionID: UUID())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SereinTests.TabDragPayload.\(UUID())"))
        pasteboard.clearContents()
        let item = try XCTUnwrap(payload.makePasteboardItem())

        XCTAssertTrue(pasteboard.writeObjects([item]))
        XCTAssertEqual(TabDragPayload.read(from: pasteboard), payload)
    }

    func testVerticalTabsMoveDroppedPDFToExistingWindow() throws {
        _ = NSApplication.shared
        let store = makeStore()
        let sourceAnchor = try store.open(documentAt: makeTemporaryPDF(named: "vertical-drag-source-anchor"))
        let moved = try store.open(documentAt: makeTemporaryPDF(named: "vertical-drag-moved"))
        let sourceWindowID = store.defaultWindowID
        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)
        let destinationAnchor = try store.open(
            documentAt: makeTemporaryPDF(named: "vertical-drag-destination-anchor"),
            in: destinationWindowID
        )
        let controller = VerticalTabsViewController(
            documentStore: store,
            windowID: destinationWindowID
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(
            controller.testingMoveTab(
                TabDragPayload(sourceWindowID: sourceWindowID, sessionID: moved.id)
            )
        )
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [sourceAnchor.id])
        XCTAssertEqual(
            store.sessions(in: destinationWindowID).map(\.id),
            [destinationAnchor.id, moved.id]
        )
        XCTAssertEqual(store.activeSessionID(in: destinationWindowID), moved.id)
    }

    func testVerticalPDFTabUsesDragSourceAsPrimaryHitTarget() throws {
        _ = NSApplication.shared
        let store = makeStore()
        _ = try store.open(documentAt: makeTemporaryPDF(named: "vertical-drag-hit-target"))
        let controller = VerticalTabsViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 240, height: 360)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.testingTabDragSourceHitTargets, [true])
    }

    private func makeTemporaryPDF(named name: String) throws -> URL {
        try TestPDFFixtures.makeBlankPDF(named: name)
    }

    private func makeStore() -> DocumentStore {
        makeIsolatedDocumentStore()
    }

    private func makeWindow(for contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeRecordingWindow(for contentView: NSView) -> VTRecordingWindow {
        let window = VTRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func mouseDownEvent(
        in window: NSWindow,
        at location: NSPoint,
        clickCount: Int = 1
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func firstPoint(in view: NSView, matching predicate: (NSPoint) -> Bool) -> NSPoint? {
        let step: CGFloat = 12
        var y = view.bounds.minY + step
        while y < view.bounds.maxY {
            var x = view.bounds.minX + step
            while x < view.bounds.maxX {
                let point = NSPoint(x: x, y: y)
                if predicate(point) {
                    return point
                }
                x += step
            }
            y += step
        }
        return nil
    }

    private func returnKeyEvent(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        makeReturnKeyEvent(in: window, modifiers: modifiers)
    }
}
