import AppKit
import Testing
@testable import SlatePDF

@MainActor
struct RightSidebarViewControllerTests {
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
