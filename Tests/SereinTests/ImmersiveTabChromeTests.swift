import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ImmersiveTabChromeTests {
    @Test(arguments: [false, true])
    func openingOutlineAfterImmersiveKeepsTitlebarTabsHidden(sidebarsSwapped: Bool) throws {
        let (store, controller) = try makeController(sidebarsSwapped: sidebarsSwapped)
        defer { controller.close() }
        let split = try #require(controller.window?.contentViewController as? SplitViewController)
        #expect(controller.window?.toolbar != nil)

        controller.toggleImmersiveMode()
        for _ in 0..<3 {
            setOutlineVisible(true, store: store, swapped: sidebarsSwapped)
            controller.window?.layoutIfNeeded()
            #expect(controller.isImmersiveModeEnabled == false)
            #expect(controller.window?.toolbar == nil)
            #expect(split.titlebarTabsController.view.isHidden)
            setOutlineVisible(false, store: store, swapped: sidebarsSwapped)
            controller.window?.layoutIfNeeded()
            #expect(controller.window?.toolbar == nil)
        }
    }

    @Test
    func closingLastSidebarAlsoKeepsTabsHiddenWhenOutlineReopens() throws {
        let (store, controller) = try makeController()
        defer { controller.close() }
        store.setRightSidebarVisible(false)
        #expect(controller.window?.toolbar == nil)
        store.setRightSidebarVisible(true)
        #expect(controller.window?.toolbar == nil)
    }

    @Test(arguments: [false, true])
    func explicitTabPresentationRestoresTabsAfterImmersive(outlineVisible: Bool) throws {
        let (store, controller) = try makeController()
        defer { controller.close() }
        controller.toggleImmersiveMode()
        store.setRightSidebarVisible(outlineVisible)

        store.setTabPresentationMode(.verticalSidebar)
        #expect(store.isLeftSidebarVisible)
        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)
        _ = store.newBlankTab()
        #expect(controller.window?.toolbar != nil)
    }

    @Test(arguments: [false, true])
    func demoRestoresTitlebarVisibilityWithOutlineOpen(wasHidden: Bool) throws {
        let (store, controller) = try makeController()
        defer { controller.close() }
        if wasHidden {
            controller.toggleImmersiveMode()
            store.setRightSidebarVisible(true)
        }
        #expect((controller.window?.toolbar == nil) == wasHidden)

        controller.toggleDemoMode()
        #expect(controller.window?.toolbar == nil)
        controller.toggleDemoMode()

        #expect(store.isRightSidebarVisible)
        #expect((controller.window?.toolbar == nil) == wasHidden)
    }

    @Test
    func demoTemporarilyHidesExplicitHorizontalTabsWithBothSidebarsClosed() throws {
        let (store, controller) = try makeController()
        defer { controller.close() }
        store.setTabPresentationMode(.verticalSidebar)
        store.setRightSidebarVisible(false)
        store.setTabPresentationMode(.horizontalTitlebar)
        #expect(controller.window?.toolbar != nil)

        controller.toggleDemoMode()
        #expect(controller.window?.toolbar == nil)
        controller.toggleDemoMode()
        #expect(controller.window?.toolbar != nil)
        #expect(store.isLeftSidebarVisible == false)
        #expect(store.isRightSidebarVisible == false)
    }

    private func setOutlineVisible(_ visible: Bool, store: DocumentStore, swapped: Bool) {
        if swapped {
            store.setLeftSidebarVisible(visible)
        } else {
            store.setRightSidebarVisible(visible)
        }
    }

    private func makeController(sidebarsSwapped: Bool = false) throws -> (DocumentStore, MainWindowController) {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = sidebarsSwapped
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let url = try TestPDFFixtures.makeLabeledPDF(named: "immersive-tabs")
        _ = try store.open(documentAt: url)
        store.setTabPresentationMode(.horizontalTitlebar)
        setOutlineVisible(true, store: store, swapped: sidebarsSwapped)
        let controller = MainWindowController(documentStore: store)
        return (store, controller)
    }
}
