import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderMagnificationTests {
    @Test(arguments: [
        ReaderDisplayMode.singlePage, .singlePageContinuous, .twoUp,
        .twoUpContinuous, .book, .bookContinuous,
    ], [CGFloat(0.2), 0.8])
    func pinchPreservesViewportCenterAndAllowsPanningBetweenGestures(
        mode: ReaderDisplayMode, pointerFraction: CGFloat
    ) throws {
        try withReader(mode: mode) { controller, reader, store, sessionID in
            let pdf = reader.pdfView
            let scroll = try #require(pdf.subviews.compactMap { $0 as? NSScrollView }.first)
            let clip = scroll.contentView
            let documentView = try #require(clip.documentView)
            clip.scroll(to: NSPoint(x: max(documentView.frame.width - clip.bounds.width, 0) * 0.5, y: 300))
            scroll.reflectScrolledClipView(clip)
            settle(controller)
            let center = NSPoint(x: pdf.bounds.midX, y: pdf.bounds.midY)
            let page = try #require(pdf.page(for: center, nearest: true))
            let initialCenter = pdf.convert(center, to: page)
            let initialPosition = try #require(reader.testingCurrentReadingPosition)
            let initialScale = pdf.scaleFactor

            try pinch(0.1, in: reader, pointerFraction: pointerFraction)
            settle(controller)
            let pinchScale = pdf.scaleFactor
            let pinchCenter = pdf.convert(center, to: page)
            #expect(abs(pinchScale - initialScale * 1.1) < 0.001)
            expectSamePoint(pinchCenter, initialCenter)
            #expect(store.session(for: sessionID)?.scaleMode == .manual)
            #expect(abs((store.session(for: sessionID)?.zoomScale ?? 0) - pinchScale) < 0.001)

            // Compare the gesture with the same keyboard zoom from the same view.
            store.setScaleMode(.manual, scaleFactor: initialScale, for: sessionID)
            #expect(reader.go(to: initialPosition, recordHistory: false))
            settle(controller)
            reader.zoomIn()
            settle(controller)
            #expect(abs(pdf.scaleFactor - pinchScale) < 0.001)
            expectSamePoint(pdf.convert(center, to: page), pinchCenter)

            let beforePan = clip.bounds.origin
            clip.scroll(to: NSPoint(x: beforePan.x + 60, y: beforePan.y + 100))
            scroll.reflectScrolledClipView(clip)
            settle(controller)
            #expect(clip.bounds.minX > beforePan.x + 40)
            #expect(clip.bounds.minY > beforePan.y + 80)
            let pannedCenter = pdf.convert(center, to: page)
            try pinch(-0.1, in: reader, pointerFraction: 1 - pointerFraction)
            settle(controller)
            expectSamePoint(pdf.convert(center, to: page), pannedCenter)
            let savedPosition = try #require(store.session(for: sessionID)?.lastReadPosition)
            let livePosition = try #require(reader.testingCurrentReadingPosition)
            #expect(savedPosition.pageIndex == livePosition.pageIndex)
            expectSamePoint(savedPosition.point, livePosition.point)
            #expect(abs((store.session(for: sessionID)?.zoomScale ?? 0) - pdf.scaleFactor) < 0.001)
        }
    }

    @Test
    func directPDFViewPinchLeavesFitModeAndPreservesCenter() throws {
        try withReader(mode: .singlePageContinuous) { controller, reader, store, sessionID in
            reader.fitToWidth()
            settle(controller)
            let pdf = reader.pdfView
            let center = NSPoint(x: pdf.bounds.midX, y: pdf.bounds.midY)
            let page = try #require(pdf.page(for: center, nearest: true))
            let before = pdf.convert(center, to: page)
            let scale = pdf.scaleFactor
            let window = try #require(controller.window)
            for (amount, phase) in [(CGFloat(0), NSEvent.Phase.began), (0.25, .changed), (0, .ended)] {
                pdf.magnify(with: ReaderPinchEvent(amount: amount, phase: phase, window: window,
                    location: pdf.convert(NSPoint(x: pdf.bounds.width * 0.8, y: pdf.bounds.midY), to: nil)))
            }
            settle(controller)
            #expect(pdf.scaleFactor > scale)
            expectSamePoint(pdf.convert(center, to: page), before)
            #expect(store.session(for: sessionID)?.scaleMode == .manual)
            #expect(abs((store.session(for: sessionID)?.zoomScale ?? 0) - pdf.scaleFactor) < 0.001)
        }
    }

    @Test
    func magnificationRoutingRespectsLockAndReaderBounds() throws {
        try withReader(mode: .singlePageContinuous) { controller, reader, store, sessionID in
            let window = try #require(controller.window)
            let event = ReaderPinchEvent(amount: 0.2, phase: .changed, window: window,
                location: reader.pdfView.convert(NSPoint(x: reader.pdfView.bounds.midX, y: reader.pdfView.bounds.midY), to: nil))
            let originalScale = reader.pdfView.scaleFactor
            #expect(controller.toggleHorizontalPanLock())
            #expect(reader.testingRewriteMagnificationEvent(event) == nil)
            reader.pdfView.magnify(with: event)
            #expect(reader.pdfView.scaleFactor == originalScale)
            #expect(controller.toggleHorizontalPanLock() == false)

            let outside = ReaderPinchEvent(amount: 0.2, phase: .changed, window: window,
                location: NSPoint(x: -20, y: -20))
            #expect(reader.testingRewriteMagnificationEvent(outside) === outside)
            let overlay = NSView(frame: reader.view.convert(reader.pdfView.bounds, from: reader.pdfView))
            reader.view.addSubview(overlay)
            #expect(reader.testingRewriteMagnificationEvent(event) === event)
            #expect(reader.pdfView.scaleFactor == originalScale)
            overlay.removeFromSuperview()
            reader.setAllPagesOverviewActive(true)
            let overviewScale = reader.pdfView.scaleFactor
            #expect(reader.testingRewriteMagnificationEvent(event) === event)
            #expect(reader.pdfView.scaleFactor == overviewScale)
            #expect(store.session(for: sessionID)?.zoomScale == overviewScale)
        }
    }

    private func pinch(_ amount: CGFloat, in reader: ReaderViewController, pointerFraction: CGFloat) throws {
        let pdf = reader.pdfView
        let window = try #require(pdf.window)
        let location = pdf.convert(NSPoint(x: pdf.bounds.width * pointerFraction, y: pdf.bounds.midY), to: nil)
        for (delta, phase) in [(CGFloat(0), NSEvent.Phase.began), (amount, .changed), (0, .ended)] {
            let event = ReaderPinchEvent(amount: delta, phase: phase, window: window, location: location)
            #expect(reader.testingRewriteMagnificationEvent(event) == nil)
        }
    }

    private func expectSamePoint(_ actual: NSPoint, _ expected: NSPoint) {
        #expect(abs(actual.x - expected.x) < 1)
        #expect(abs(actual.y - expected.y) < 1)
    }

    private func withReader(mode: ReaderDisplayMode,
        body: (MainWindowController, ReaderViewController, DocumentStore, UUID) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let url = try TestPDFFixtures.makeBlankPDF(named: "centered-pinch", pageCount: 4,
            pageSize: NSSize(width: 720, height: 1800))
        let session = try store.open(documentAt: url)
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 2, for: session.id)
        let split = try #require(controller.window?.contentViewController as? SplitViewController)
        settle(controller)
        try body(controller, split.readerViewController, store, session.id)
    }

    private func settle(_ controller: MainWindowController) {
        controller.window?.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
        controller.window?.layoutIfNeeded()
    }
}

private final class ReaderPinchEvent: NSEvent, @unchecked Sendable {
    private let amount: CGFloat
    private let gesturePhase: NSEvent.Phase
    private let location: NSPoint
    private let targetWindowNumber: Int
    private weak var targetWindow: NSWindow?

    @MainActor
    init(amount: CGFloat, phase: NSEvent.Phase, window: NSWindow, location: NSPoint) {
        self.amount = amount
        gesturePhase = phase
        targetWindow = window
        targetWindowNumber = window.windowNumber
        self.location = location
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var type: NSEvent.EventType { .magnify }
    override var magnification: CGFloat { amount }
    override var phase: NSEvent.Phase { gesturePhase }
    override var locationInWindow: NSPoint { location }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { targetWindowNumber }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
