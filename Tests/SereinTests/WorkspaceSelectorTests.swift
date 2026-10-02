import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct WorkspaceSelectorTests {
    @Test
    func bothTabPresentationsSwitchWorkspacesAndRefreshTheirNames() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstID = try #require(store.activeWorkspaceID(in: windowID))
        let firstTab = store.newBlankTab(in: windowID)
        let secondID = try #require(store.createWorkspace(name: "Research", in: windowID))
        let secondTab = store.newBlankTab(in: windowID)
        let vertical = VerticalTabsViewController(documentStore: store, windowID: windowID)
        let horizontal = TitlebarTabsController(documentStore: store, windowID: windowID)
        vertical.loadViewIfNeeded()
        horizontal.loadViewIfNeeded()
        let verticalSelector = try #require(findView(identifier: "workspaceFooter", in: vertical.view) as? WorkspaceSelectorView)
        let horizontalSelector = try selector(in: horizontal.view)

        #expect(verticalSelector.testingCurrentWorkspaceName == "Research")
        #expect(horizontalSelector.testingCurrentWorkspaceName == "Research")
        let footer = try #require(findView(identifier: "workspaceFooter", in: vertical.view) as? WorkspaceSelectorView)
        let firstButton = try #require(footer.testingWorkspaceButtons.first)
        #expect(NSApp.sendAction(try #require(firstButton.action), to: firstButton.target, from: firstButton))
        #expect(store.activeWorkspaceID(in: windowID) == firstID)
        #expect(store.sessions(in: windowID).map(\.id) == [firstTab.id])
        #expect(horizontalSelector.testingMenu.items.first?.state == .on)

        try select(index: 1, in: horizontalSelector)
        #expect(store.activeWorkspaceID(in: windowID) == secondID)
        #expect(store.sessions(in: windowID).map(\.id) == [secondTab.id])
        #expect(verticalSelector.testingCurrentWorkspaceName == "Research")
        store.renameWorkspace(secondID, name: "Papers", in: windowID)
        #expect(verticalSelector.testingCurrentWorkspaceName == "Papers")
        #expect(horizontalSelector.testingCurrentWorkspaceName == "Papers")
        #expect(footer.testingWorkspaceButtons.last?.toolTip == "Papers")
    }

    @Test
    func moveMenuUsesOnlyOtherWorkspacesInTheSameWindow() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let sourceID = try #require(store.activeWorkspaceID(in: windowID))
        let url = try TestPDFFixtures.makeBlankPDF(named: "workspace-move")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try store.open(documentAt: url, in: windowID)
        let destinationID = try #require(store.createWorkspace(name: "Research", in: windowID))
        let otherWindowID = store.createWindow(copyingFrom: windowID)
        store.createWorkspace(name: "Other Window", in: otherWindowID)
        store.activateWorkspace(sourceID, in: windowID)
        let selector = WorkspaceSelectorView(documentStore: store, windowID: windowID)
        let menu = try #require(selector.moveMenu(for: document.id))
        #expect(menu.items.map(\.title) == ["Research"])
        let item = try #require(menu.items.first)
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
        #expect(store.activeWorkspaceID(in: windowID) == sourceID)
        #expect(store.sessions(in: windowID).isEmpty)
        store.activateWorkspace(destinationID, in: windowID)
        #expect(store.sessions(in: windowID).map(\.url) == [url])
        let blank = store.newBlankTab(in: windowID)
        #expect(selector.moveMenu(for: blank.id) == nil)
    }

    @Test
    func emptyWorkspacesKeepSelectorAvailableInBothPresentations() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let vertical = VerticalTabsViewController(documentStore: store, windowID: windowID)
        let horizontal = TitlebarTabsController(documentStore: store, windowID: windowID)
        vertical.loadViewIfNeeded()
        horizontal.loadViewIfNeeded()
        let footer = try #require(findView(identifier: "workspaceFooter", in: vertical.view) as? WorkspaceSelectorView)
        for selector in [footer, try selector(in: horizontal.view)] {
            #expect(!selector.isHiddenOrHasHiddenAncestor)
            #expect(selector.testingMenu.items.map(\.title).contains("New Workspace"))
            #expect(selector.testingMenu.items.map(\.title).contains("Rename"))
        }
        #expect(horizontal.preferredContentSize.width >= 26)
        #expect(!footer.isHiddenOrHasHiddenAncestor)
        #expect(footer.testingWorkspaceButtons.count == 1)
        #expect(!footer.testingAddButton.isHiddenOrHasHiddenAncestor)
    }

    private func selector(in view: NSView) throws -> WorkspaceSelectorView {
        try #require(findView(identifier: "workspaceSelector", in: view) as? WorkspaceSelectorView)
    }

    private func select(index: Int, in selector: WorkspaceSelectorView) throws {
        let item = selector.testingMenu.items[index]
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
    }
}
