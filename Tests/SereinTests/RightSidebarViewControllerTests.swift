import AppKit
import Testing
@testable import Serein

@MainActor
struct RightSidebarViewControllerTests {
    @Test
    func loadingSidebarDoesNotEagerlyLoadAnnotationsPane() {
        let store = DocumentStore(appConfiguration: .default)
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )

        controller.loadViewIfNeeded()

        #expect(controller.annotationsViewController.isViewLoaded == false)
    }

    @Test
    func selectingAnnotationsLoadsAnnotationsPane() {
        let store = DocumentStore(appConfiguration: .default)
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
        let store = DocumentStore(appConfiguration: .default)
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
