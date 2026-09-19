import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct SidebarViewportTests {
    @Test(arguments: [false, true])
    func openingOutlinePreservesManualVisibleWidthAndHiddenTabs(locked: Bool) async throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let fixture = ProcessInfo.processInfo.environment["SEREIN_SIDEBAR_QA_PDF"]
        let url = try fixture.map { URL(fileURLWithPath: $0) } ?? TestPDFFixtures.makeBlankPDF(
            named: "sidebar-visible-width", pageCount: 5, pageSize: NSSize(width: 612, height: 792)
        )
        let session = try store.open(documentAt: url)
        store.setDisplayMode(.singlePageContinuous, for: session.id)
        store.setTabPresentationMode(.horizontalTitlebar)
        let window = try #require(controller.window)
        window.setContentSize(NSSize(width: 1450, height: 912))
        controller.showWindow(nil)
        settle(window)
        let split = try #require(window.contentViewController as? SplitViewController)
        let reader = split.readerViewController
        controller.toggleImmersiveMode()
        settle(window)
        reader.zoomIn()
        reader.pdfView.scaleFactor = 2.7708971734187635
        #expect(reader.go(to: ReadingPosition(pageIndex: 3, point: NSPoint(x: 45.5, y: 471.00465730058795))))
        settle(window)
        if locked { #expect(controller.toggleHorizontalPanLock()) }
        reader.flushPendingReadingPosition()
        let page = try #require(reader.pdfView.document?.page(at: 3))
        let before = try viewport(on: page, reader: reader)
        let scaleBefore = reader.pdfView.scaleFactor
        try await capture(window, name: "sidebar-before", enabled: fixture != nil && locked)
        for visible in [true, false, true, false] {
            store.setRightSidebarVisible(visible)
            settle(window)
            let after = try viewport(on: page, reader: reader)
            #expect(abs(after.width - before.width) < 2)
            #expect(abs(after.midX - before.midX) < 2)
            #expect(abs(after.midY - before.midY) < 5)
            #expect(store.session(for: session.id)?.scaleMode == .manual)
            #expect(window.toolbar == nil)
            #expect(split.titlebarTabsController.view.isHidden)
            if visible {
                #expect(reader.pdfView.scaleFactor < scaleBefore - 0.05)
                let readerFrame = reader.pdfView.convert(reader.pdfView.bounds, to: window.contentView)
                let outlineFrame = split.rightSidebarViewController.view.convert(
                    split.rightSidebarViewController.view.bounds, to: window.contentView
                )
                #expect(readerFrame.intersection(outlineFrame).width <= 1)
                try await capture(window, name: "sidebar-after", enabled: fixture != nil && locked)
            }
        }
    }

    private func settle(_ window: NSWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
        window.layoutIfNeeded()
    }

    private func viewport(on page: PDFPage, reader: ReaderViewController) throws -> NSRect {
        let clip = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView)
        return reader.pdfView.convert(reader.pdfView.convert(clip.bounds, from: clip), to: page)
    }

    private func capture(_ window: NSWindow, name: String, enabled: Bool) async throws {
        guard enabled else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(1))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber),
                             FileManager.default.currentDirectoryPath + "/.tmp/" + name + ".png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}
