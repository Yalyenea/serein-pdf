import AppKit
import PDFKit
import Testing
@testable import Serein

struct ReaderPaneGeometryTests {
    @Test func admissionUsesBothReadableDimensionsWithoutAPaneCountLimit() {
        #expect(ReaderPaneGeometry.canSplit(NSSize(width: 641, height: 160), layout: .sideBySide))
        #expect(!ReaderPaneGeometry.canSplit(NSSize(width: 640, height: 160), layout: .sideBySide))
        #expect(!ReaderPaneGeometry.canSplit(NSSize(width: 900, height: 159), layout: .sideBySide))
        #expect(ReaderPaneGeometry.canSplit(NSSize(width: 320, height: 321), layout: .stacked))
        #expect(!ReaderPaneGeometry.canSplit(NSSize(width: 319, height: 900), layout: .stacked))
        #expect(!ReaderPaneGeometry.canSplit(NSSize(width: 900, height: 320), layout: .stacked))
    }

    @Test func mixedLayoutFocusUsesAlignedNeighboursAndDoesNotWrap() {
        let bottom = ReaderPane()
        let frames: [ReaderPane: NSRect] = [
            .primary: NSRect(x: 0, y: 0, width: 500, height: 800),
            .secondary: NSRect(x: 501, y: 0, width: 500, height: 399),
            bottom: NSRect(x: 501, y: 400, width: 500, height: 400),
        ]
        #expect(ReaderPaneGeometry.neighbour(from: .primary, direction: .up, frames: frames, recentFocus: []) == nil)
        #expect(ReaderPaneGeometry.neighbour(from: .primary, direction: .left, frames: frames, recentFocus: []) == nil)
        #expect(ReaderPaneGeometry.neighbour(from: .secondary, direction: .down, frames: frames, recentFocus: []) == bottom)
        #expect(ReaderPaneGeometry.neighbour(from: bottom, direction: .left, frames: frames, recentFocus: []) == .primary)
        #expect(ReaderPaneGeometry.neighbour(from: bottom, direction: .down, frames: frames, recentFocus: []) == nil)
    }

    @Test func equallyNearBranchesUseRecentFocus() {
        let bottom = ReaderPane()
        let frames: [ReaderPane: NSRect] = [
            .primary: NSRect(x: 0, y: 0, width: 500, height: 801),
            .secondary: NSRect(x: 501, y: 0, width: 500, height: 400),
            bottom: NSRect(x: 501, y: 401, width: 500, height: 400),
        ]
        #expect(ReaderPaneGeometry.neighbour(from: .primary, direction: .right, frames: frames, recentFocus: [bottom, .secondary]) == bottom)
        #expect(ReaderPaneGeometry.neighbour(from: .primary, direction: .right, frames: frames, recentFocus: [.secondary, bottom]) == .secondary)
    }

    @Test func localRatioOnlyChangesItsOwnSubtree() {
        let bottom = ReaderPane()
        let branchID = UUID()
        let layout = ReaderLayoutNode.split(id: UUID(), layout: .sideBySide, ratio: 0.5,
            first: .split(id: branchID, layout: .stacked, ratio: 0.25, first: .pane(.primary), second: .pane(bottom)),
            second: .pane(.secondary))
        let bounds = NSRect(x: 0, y: 0, width: 1441, height: 1001)
        let before = ReaderPaneGeometry.frames(for: layout, in: bounds)
        let after = ReaderPaneGeometry.frames(for: layout.updatingRatio(0.7, splitID: branchID), in: bounds)
        #expect(before[.secondary] == after[.secondary])
        #expect(before[.primary]?.height == 250)
        #expect(after[.primary]?.height == 700)
        #expect(after[bottom]?.height == 300)
    }
}

@Suite(.serialized)
@MainActor
struct ReaderSplitWorkspaceTests {
    @Test func recursiveSplitCreatesFourIndependentReadersAndClosesOnlyFocusedLeaf() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        var changeCount = 0
        workspace.readersDidChange = { changeCount += 1 }
        #expect(workspace.splitActivePane(layout: .sideBySide))
        store.setFocusedPane(.primary, in: store.defaultWindowID)
        #expect(workspace.splitActivePane(layout: .stacked))
        let lowerLeft = store.focusedPane(in: store.defaultWindowID)
        store.setFocusedPane(.secondary, in: store.defaultWindowID)
        #expect(workspace.splitActivePane(layout: .stacked))
        let lowerRight = store.focusedPane(in: store.defaultWindowID)
        layout(workspace, window)

        let panes = store.readerPanes(in: store.defaultWindowID)
        #expect(panes.count == 4)
        #expect(workspace.allReaderViewControllers.count == 4)
        #expect(Set(panes.compactMap(\.sessionID)).count == 4)
        #expect(Set(workspace.allReaderViewControllers.map(ObjectIdentifier.init)).count == 4)
        for pane in panes {
            let reader = try #require(workspace.readerViewController(for: pane.id))
            let frame = try #require(workspace.testingPaneFrames[pane.id])
            #expect(reader.view.window === window)
            #expect(abs(reader.view.bounds.width - frame.width) < 1)
            #expect(abs(reader.view.bounds.height - frame.height) < 1)
        }
        let sharedDocument = try #require(workspace.primaryReaderViewController.pdfView.document)
        #expect(workspace.allReaderViewControllers.allSatisfy { $0.pdfView.document === sharedDocument })
        #expect(changeCount == 3)
        let survivingReader = workspace.readerViewController(for: lowerLeft)
        #expect(workspace.closeFocusedPane())
        #expect(store.readerPanes(in: store.defaultWindowID).count == 3)
        #expect(workspace.readerViewController(for: lowerRight) == nil)
        #expect(workspace.readerViewController(for: lowerLeft) === survivingReader)
    }

    @Test func splittingOneBranchPreservesTheOtherReadersScaleAndPage() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        #expect(workspace.splitActivePane(layout: .sideBySide))
        let rightReader = try #require(workspace.readerViewController(for: .secondary))
        let rightID = try #require(rightReader.displayedSessionID)
        #expect(rightReader.goToPage(5))
        store.setScaleMode(.manual, scaleFactor: 1.7, for: rightID)
        layout(workspace, window)
        rightReader.flushPendingReadingPosition()
        let before = try #require(store.session(for: rightID))
        store.setFocusedPane(.primary, in: store.defaultWindowID)
        #expect(workspace.splitActivePane(layout: .stacked))
        layout(workspace, window)
        let after = try #require(store.session(for: rightID))
        #expect(workspace.readerViewController(for: .secondary) === rightReader)
        #expect(after.scaleMode == .manual)
        #expect(abs(after.zoomScale - before.zoomScale) < 0.001)
        #expect(after.currentPageIndex == before.currentPageIndex)
    }

    @Test func temporaryZoomRestoresLayoutReaderIdentityAndReadingPages() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        #expect(workspace.splitActivePane(layout: .sideBySide))
        #expect(workspace.splitActivePane(layout: .stacked))
        layout(workspace, window)
        let focused = store.focusedPane(in: store.defaultWindowID)
        let active = workspace.activeReaderViewController()
        #expect(active.goToPage(4))
        workspace.flushPendingReadingPositions()
        let tree = store.readerLayout(in: store.defaultWindowID)
        let frames = workspace.testingPaneFrames
        let readers = workspace.allReaderViewControllers.map(ObjectIdentifier.init)
        workspace.togglePaneZoom()
        layout(workspace, window)
        #expect(store.zoomedPane(in: store.defaultWindowID) == focused)
        #expect(workspace.activeReaderViewController() === active)
        #expect(active.view.bounds.width > 1400)
        #expect(workspace.allReaderViewControllers.filter { !$0.view.isHiddenOrHasHiddenAncestor }.count == 1)
        workspace.togglePaneZoom()
        layout(workspace, window)
        #expect(store.zoomedPane(in: store.defaultWindowID) == nil)
        #expect(store.readerLayout(in: store.defaultWindowID) == tree)
        #expect(workspace.testingPaneFrames == frames)
        #expect(workspace.allReaderViewControllers.map(ObjectIdentifier.init) == readers)
        #expect(workspace.allReaderViewControllers.allSatisfy { !$0.view.isHiddenOrHasHiddenAncestor })
        #expect(workspace.allReaderViewControllers.allSatisfy { $0.view.window === window })
        #expect(active.pdfView.currentPage.map { active.pdfView.document?.index(for: $0) } == 4)
    }

    @Test func insufficientSizeLeavesLayoutUnchanged() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        window.setContentSize(NSSize(width: 600, height: 300))
        layout(workspace, window)
        let tree = store.readerLayout(in: store.defaultWindowID)
        #expect(!workspace.canSplitPane(layout: .sideBySide))
        #expect(!workspace.canSplitPane(layout: .stacked))
        #expect(!workspace.splitActivePane(layout: .sideBySide))
        #expect(store.readerLayout(in: store.defaultWindowID) == tree)
        #expect(workspace.allReaderViewControllers.count == 1)
    }

    @Test func sourceDocumentOutlineNavigationStaysInFocusedComparisonPane() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        let sourceID = try #require(store.activeSessionID(in: store.defaultWindowID))
        let sourceReader = workspace.activeReaderViewController()
        #expect(sourceReader.goToPage(1))
        layout(workspace, window)
        sourceReader.flushPendingReadingPosition()
        let sourcePosition = try #require(sourceReader.currentPosition)
        #expect(sourcePosition.pageIndex == 1)
        #expect(workspace.splitActivePane(layout: .sideBySide))
        let comparisonID = try #require(store.activeSessionID(in: store.defaultWindowID))
        let page = try #require(workspace.activeReaderViewController().pdfView.document?.page(at: 5))
        let position = ReadingPosition.pageTop(pageIndex: 5, pageBounds: page.bounds(for: .cropBox))
        #expect(workspace.navigate(to: position, in: sourceID))
        #expect(store.focusedPane(in: store.defaultWindowID) == .secondary)
        #expect(store.activeSessionID(in: store.defaultWindowID) == comparisonID)
        #expect(store.session(for: comparisonID)?.currentPageIndex == 5)
        #expect(store.session(for: sourceID)?.currentPageIndex == 1)
        let restoredSourcePosition = try #require(sourceReader.currentPosition)
        #expect(restoredSourcePosition.pageIndex == sourcePosition.pageIndex)
        #expect(abs(restoredSourcePosition.point.y - sourcePosition.point.y) < 1)
    }

    @Test func returningToSavedSplitGroupKeepsManualScale() throws {
        let (store, workspace, window) = try makeWorkspace()
        defer { window.close() }
        let sourceID = try #require(store.activeSessionID(in: store.defaultWindowID))
        #expect(workspace.splitActivePane(layout: .sideBySide))
        let comparisonID = try #require(store.activeSessionID(in: store.defaultWindowID))
        store.setScaleMode(.manual, scaleFactor: 1.6, for: comparisonID)
        layout(workspace, window)
        workspace.flushPendingReadingPositions()
        _ = store.newBlankTab(in: store.defaultWindowID)
        #expect(workspace.allReaderViewControllers.count == 1)
        store.activate(sessionID: sourceID, in: store.defaultWindowID)
        layout(workspace, window)
        #expect(workspace.allReaderViewControllers.count == 2)
        #expect(store.session(for: comparisonID)?.scaleMode == .manual)
        #expect(abs((store.session(for: comparisonID)?.zoomScale ?? 0) - 1.6) < 0.001)
    }

    private func makeWorkspace() throws -> (DocumentStore, ReaderWorkspaceViewController, NSWindow) {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "recursive-reader-\(UUID().uuidString)", pageCount: 8))
        let workspace = ReaderWorkspaceViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1441, height: 1001),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = workspace
        window.setContentSize(NSSize(width: 1441, height: 1001))
        layout(workspace, window)
        return (store, workspace, window)
    }

    private func layout(_ workspace: ReaderWorkspaceViewController, _ window: NSWindow) {
        window.layoutIfNeeded()
        workspace.view.layoutSubtreeIfNeeded()
    }
}
