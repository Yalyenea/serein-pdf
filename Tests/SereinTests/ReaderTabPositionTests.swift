import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderTabPositionTests {
    @Test(arguments: [ReaderDisplayMode.singlePageContinuous, .twoUpContinuous], [false, true])
    func switchingTabsRestoresViewportWhenCurrentPageDiffersFromTopPage(
        _ mode: ReaderDisplayMode, publishPageChange: Bool
    ) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let firstURL = try ProcessInfo.processInfo.environment["SEREIN_TAB_QA_PDF"].map {
            URL(fileURLWithPath: $0)
        } ?? TestPDFFixtures.makeBlankPDF(
            named: "tab-position-first", pageCount: 8, pageSize: NSSize(width: 500, height: 792)
        )
        let first = try store.open(documentAt: firstURL)
        let second = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "tab-position-second", pageCount: 6, pageSize: NSSize(width: 612, height: 1000)
        ))
        store.setDisplayMode(mode, for: first.id)
        store.setScaleMode(.manual, scaleFactor: 1, for: first.id)
        store.activate(sessionID: first.id)
        let workspace = ReaderWorkspaceViewController(documentStore: store, windowID: store.defaultWindowID)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = workspace
        window.setContentSize(NSSize(width: 720, height: 440))
        defer { window.close() }
        settle(window)
        let reader = workspace.activeReaderViewController()
        #expect(reader.goToPage(mode.usesTwoUpLayout ? 4 : 3))
        settle(window)
        let scrollView = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first)
        let clip = scrollView.contentView
        let document = try #require(reader.pdfView.document)
        let nextPage = try #require(document.page(at: mode.usesTwoUpLayout ? 4 : 3))
        let nextBounds = clip.convert(reader.pdfView.convert(nextPage.bounds(for: .cropBox), from: nextPage), from: reader.pdfView)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
        // Leave the end of one page/spread above the next one in the viewport.
        let targetY = clip.isFlipped ? nextBounds.minY - 80 : nextBounds.maxY + 80 - clip.bounds.height
        clip.scroll(to: clip.constrainBoundsRect(NSRect(
            x: clip.bounds.minX, y: targetY,
            width: clip.bounds.width, height: clip.bounds.height
        )).origin)
        scrollView.reflectScrolledClipView(clip)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
        let before = try #require(reader.currentPosition)
        let current = try #require(reader.pdfView.currentPage)
        #expect(document.index(for: current) > before.pageIndex,
                "clip=\(clip.bounds), next=\(nextBounds), flipped=\(clip.isFlipped), before=\(before)")
        #expect(reader.testingHasPendingReadingPositionWriteback)
        if publishPageChange {
            NotificationCenter.default.post(name: .PDFViewPageChanged, object: reader.pdfView)
            #expect(store.session(for: first.id)?.lastReadPosition == before)
        }

        for _ in 0..<3 {
            store.activateNextSession()
            settle(window)
            #expect(workspace.activeReaderViewController().displayedSessionID == second.id)
            store.activatePreviousSession()
            settle(window)
            let after = try #require(workspace.activeReaderViewController().currentPosition)
            #expect(after.pageIndex == before.pageIndex)
            #expect(abs(after.point.x - before.point.x) < 2)
            #expect(abs(after.point.y - before.point.y) < 2)
        }
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
        window.layoutIfNeeded()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
    }
}
