import AppKit
import PDFKit
import Testing
@testable import Serein

@MainActor
struct RightSidebarViewControllerTests {
    @Test
    func thumbnailsBindOnlyWhilePagesHaveAnActiveDocument() throws {
        let store = makeIsolatedDocumentStore()
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "pages-lazy-binding")
        )
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        let pdfView = PDFView()
        pdfView.document = try store.pdfDocument(for: session.id)
        controller.configure(pdfView: pdfView)
        controller.loadViewIfNeeded()
        let thumbnails = try #require(
            findDescendant(of: NavigationTrackingPDFThumbnailView.self, in: controller.view)
        )
        #expect(thumbnails.pdfView == nil)

        for mode in [RightSidebarMode.outline, .search, .annotations] {
            store.setRightSidebarMode(.pages, in: store.defaultWindowID)
            #expect(thumbnails.pdfView === pdfView)
            store.setRightSidebarMode(mode, in: store.defaultWindowID)
            #expect(thumbnails.pdfView == nil)
        }

        let replacementPDFView = PDFView()
        replacementPDFView.document = pdfView.document
        controller.configure(pdfView: replacementPDFView)
        #expect(thumbnails.pdfView == nil)
        store.setRightSidebarMode(.pages, in: store.defaultWindowID)
        #expect(thumbnails.pdfView === replacementPDFView)

        _ = store.newBlankTab(in: store.defaultWindowID)
        #expect(thumbnails.pdfView == nil)
    }

    @Test(arguments: [false, true])
    func thumbnailsDetachWhenTheirSidebarIsCollapsed(sidebarsSwapped: Bool) throws {
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = sidebarsSwapped
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        let session = try store.open(
            documentAt: TestPDFFixtures.makeBlankPDF(named: "pages-collapse-\(sidebarsSwapped)")
        )
        store.setRightSidebarMode(.pages, in: store.defaultWindowID)
        let controller = RightSidebarViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        let pdfView = PDFView()
        pdfView.document = try store.pdfDocument(for: session.id)
        controller.configure(pdfView: pdfView)
        controller.loadViewIfNeeded()
        let thumbnails = try #require(
            findDescendant(of: NavigationTrackingPDFThumbnailView.self, in: controller.view)
        )
        #expect(thumbnails.pdfView === pdfView)

        if sidebarsSwapped {
            store.setRightSidebarVisible(false)
            #expect(thumbnails.pdfView === pdfView)
            store.setLeftSidebarVisible(false)
        } else {
            store.setLeftSidebarVisible(false)
            #expect(thumbnails.pdfView === pdfView)
            store.setRightSidebarVisible(false)
        }
        #expect(thumbnails.pdfView == nil)

        if sidebarsSwapped {
            store.setLeftSidebarVisible(true)
        } else {
            store.setRightSidebarVisible(true)
        }
        #expect(thumbnails.pdfView === pdfView)
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 540)
        controller.view.layoutSubtreeIfNeeded()
        #expect(thumbnails.maximumNumberOfColumns == 3)
    }

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
    func emptyWindowShowsWeakenedChrome() {
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
        #expect(controller.testingEmptyStateVisible)
        #expect(controller.testingSegmentedHidden)
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
