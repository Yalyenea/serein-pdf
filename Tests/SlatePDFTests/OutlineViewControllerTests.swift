import AppKit
import Testing
@testable import SlatePDF

@MainActor
struct OutlineViewControllerTests {
    @Test
    func outlineColumnTracksSidebarWidth() {
        let store = DocumentStore(appConfiguration: .default)
        let controller = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()

        guard let scrollView = controller.view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let outlineView = scrollView.documentView as? NSOutlineView,
              let column = outlineView.tableColumns.first else {
            Issue.record("Failed to locate outline sidebar views")
            return
        }

        #expect(abs(column.width - scrollView.contentSize.width) < 0.5)
    }
}
