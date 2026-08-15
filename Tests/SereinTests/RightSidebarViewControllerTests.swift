import AppKit
import Testing
@testable import Serein

@MainActor
struct RightSidebarViewControllerTests {
    @Test
    func pageThumbnailIntentForwardsThroughSidebar() throws {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        var phases: [String] = []
        controller.onWillNavigateFromPages = { phases.append("will") }
        controller.onDidNavigateFromPages = { phases.append("did") }
        controller.loadViewIfNeeded()
        let thumbnailView = try #require(
            findDescendant(of: NavigationTrackingPDFThumbnailView.self, in: controller.view)
        )

        thumbnailView.notifyWillNavigate()
        thumbnailView.notifyDidNavigate()

        #expect(phases == ["will", "did"])
    }

    @Test
    func loadingSidebarDoesNotEagerlyLoadAnnotationsPane() {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )

        controller.loadViewIfNeeded()

        #expect(controller.annotationsViewController.isViewLoaded == false)
    }

    @Test
    func selectingAnnotationsLoadsAnnotationsPane() {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setRightSidebarMode(.annotations, in: store.defaultWindowID)

        #expect(controller.annotationsViewController.isViewLoaded == true)
    }

    @Test
    func reapplyingSameModeDoesNotInvalidateLayout() {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.needsLayout = false

        controller.applyStateFromStore()

        #expect(controller.view.needsLayout == false)
    }

    @Test
    func emptyWindowShowsWeakenedChrome() throws {
        // M12-011: no document → segmented chrome and mode panes hide, one
        // shared centered empty state remains.
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        let emptyState = try #require(
            findDescendant(of: EmptyStateView.self, in: controller.view)
        )

        #expect(controller.testingEmptyStateVisible)
        #expect(controller.testingSegmentedHidden)
        #expect(emptyState.frame.width > 0)
        #expect(emptyState.frame.height > 0)
        #expect(abs(emptyState.frame.midY - controller.view.bounds.midY) < 0.5)
    }

    @Test
    func blankTabAlsoShowsWeakenedChrome() {
        let store = makeIsolatedDocumentStore()
        _ = store.newBlankTab(in: store.defaultWindowID)
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        #expect(controller.testingEmptyStateVisible)
        #expect(controller.testingSegmentedHidden)
    }

    @Test
    func openingPDFRestoresSidebarChrome() throws {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        #expect(controller.testingEmptyStateVisible)

        _ = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "right-chrome-restore")
        )

        #expect(controller.testingEmptyStateVisible == false)
        #expect(controller.testingSegmentedHidden == false)
    }

    @Test
    func switchingFromPDFToBlankTabWeakensChromeAgain() throws {
        let store = makeIsolatedDocumentStore()
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        _ = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "right-chrome-blank-return")
        )
        #expect(controller.testingEmptyStateVisible == false)

        _ = store.newBlankTab(in: store.defaultWindowID)

        #expect(controller.testingEmptyStateVisible)
        #expect(controller.testingSegmentedHidden)
    }
}
