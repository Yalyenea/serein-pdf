import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderModeTransitionTests {
    @Test(arguments: [ReaderDisplayMode.singlePageContinuous, .twoUpContinuous])
    func seamlessPagesRemoveActualGapsAndPreserveLivePosition(_ mode: ReaderDisplayMode) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "seamless-pages", pageCount: 8, pageSize: NSSize(width: 500, height: 1800)
        ))
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1.37, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        #expect(reader.go(to: ReadingPosition(pageIndex: 2, point: NSPoint(x: 0, y: 1400)), recordHistory: false))
        let position = try #require(reader.currentPosition)
        let document = try #require(reader.pdfView.document)
        let first = try #require(document.page(at: 2))
        let next = try #require(document.page(at: mode == .twoUpContinuous ? 4 : 3))
        func gap() -> CGFloat {
            let a = reader.pdfView.convert(first.bounds(for: .cropBox), from: first)
            let b = reader.pdfView.convert(next.bounds(for: .cropBox), from: next)
            return max(a.minY, b.minY) - min(a.maxY, b.maxY)
        }
        let originalGap = gap()
        #expect(originalGap > 1)
        for enabled in [true, false, true] {
            var configuration = store.appConfiguration
            configuration.reader.seamlessPages = enabled
            store.updateAppConfiguration(configuration)
            reader.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            #expect(abs(gap() - (enabled ? 0 : originalGap)) < 0.1)
            let live = try #require(reader.currentPosition)
            #expect(live.pageIndex == position.pageIndex)
            #expect(abs(live.point.y - position.point.y) < 2)
            #expect(abs(reader.pdfView.scaleFactor - 1.37) < 0.001)
            #expect(store.session(for: session.id)?.scaleMode == .manual)
        }
        let newReader = makeReader(store: store, sessionID: session.id)
        #expect(!newReader.pdfView.displaysPageBreaks)
    }

    @Test(arguments: ReaderDisplayMode.allCases)
    func manualZoomRefitsNewLayoutAndKeepsLiveReadingPosition(_ mode: ReaderDisplayMode) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "mode-transition", pageCount: 6, pageSize: NSSize(width: 500, height: 1800)
        ))
        store.setDisplayMode(mode == .singlePage ? .twoUp : .singlePage, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1.8, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        #expect(reader.go(to: ReadingPosition(pageIndex: 2, point: NSPoint(x: 0, y: 1400)), recordHistory: false))
        let clip = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView)
        clip.scroll(to: clip.constrainBoundsRect(clip.bounds.offsetBy(dx: 0, dy: 70)).origin)
        let livePosition = try #require(reader.currentPosition)
        let oldScale = reader.pdfView.scaleFactor

        store.setDisplayMode(mode, for: session.id)
        reader.view.layoutSubtreeIfNeeded()
        reader.flushPendingReadingPosition()

        let updated = try #require(store.session(for: session.id))
        #expect(updated.scaleMode == .fitWidth)
        #expect(updated.lastReadPosition == livePosition)
        #expect(abs(reader.pdfView.scaleFactor - oldScale) > 0.05)
        #expect(abs(updated.zoomScale - reader.pdfView.scaleFactor) < 0.001)
        let live = try #require(reader.currentPosition)
        if !mode.usesBookLayout {
            #expect(live.pageIndex == livePosition.pageIndex)
            #expect(abs(live.point.y - livePosition.point.y) < 20)
        }
    }

    @Test
    func initialDocumentRestoreKeepsManualZoom() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "manual-restore"))
        store.setDisplayMode(.twoUp, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1.45, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        #expect(store.session(for: session.id)?.scaleMode == .manual)
        #expect(abs(reader.pdfView.scaleFactor - 1.45) < 0.001)
    }

    @Test(arguments: [ReaderDisplayMode.singlePage, .twoUp, .book, .bookContinuous])
    func keyboardPageCommandsTurnWholePageOrSpreadWhileMagnified(_ mode: ReaderDisplayMode) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "magnified-page-command", pageCount: 8, pageSize: NSSize(width: 500, height: 1000)
        ))
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 2, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        #expect(reader.go(to: ReadingPosition(pageIndex: 0, point: NSPoint(x: 100, y: 650)), recordHistory: false))
        #expect(reader.goToNextPage())
        #expect(store.session(for: session.id)?.currentPageIndex == (mode == .twoUp ? 2 : 1))
        #expect(abs(reader.pdfView.scaleFactor - 2) < 0.001)
        #expect(reader.goToPreviousPage())
        #expect(store.session(for: session.id)?.currentPageIndex == 0)
    }

    @Test(arguments: [ReaderDisplayMode.book, .bookContinuous])
    func bookPanReachesEdgeBeforeTurningAndConsumesRemainingMomentum(_ mode: ReaderDisplayMode) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "book-pan-edge", pageCount: 8, pageSize: NSSize(width: 500, height: 900)
        ))
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 2, for: session.id)
        let reader = makeReader(store: store, sessionID: session.id)
        #expect(reader.goToPage(1))
        reader.view.layoutSubtreeIfNeeded()
        let clip = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first?.contentView)
        let documentView = try #require(clip.documentView)
        let overflow = documentView.frame.width - clip.bounds.width
        #expect(overflow > 10)
        clip.scroll(to: NSPoint(x: overflow / 2, y: clip.bounds.origin.y))
        reader.testingResetBookScrollGesture()
        #expect(!reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1))
        #expect(store.session(for: session.id)?.currentPageIndex == 1)

        clip.scroll(to: NSPoint(x: overflow, y: clip.bounds.origin.y))
        #expect(reader.testingHandleContinuousBookScroll(deltaX: -60, timestamp: 1.2))
        #expect(store.session(for: session.id)?.currentPageIndex == 3)
        #expect(reader.testingHandleContinuousBookScroll(deltaX: -100, isMomentum: true, timestamp: 1.3))
        #expect(store.session(for: session.id)?.currentPageIndex == 3)
    }

    private func makeReader(store: DocumentStore, sessionID: UUID) -> ReaderViewController {
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = sessionID
        reader.loadViewIfNeeded()
        reader.view.frame = NSRect(x: 0, y: 0, width: 720, height: 440)
        reader.view.layoutSubtreeIfNeeded()
        return reader
    }
}
