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
        var callCount = 0
        controller.onWillNavigateFromPages = { callCount += 1 }
        controller.loadViewIfNeeded()
        let thumbnailView = try #require(
            findDescendant(of: NavigationTrackingPDFThumbnailView.self, in: controller.view)
        )

        thumbnailView.notifyWillNavigate()

        #expect(callCount == 1)
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
}
