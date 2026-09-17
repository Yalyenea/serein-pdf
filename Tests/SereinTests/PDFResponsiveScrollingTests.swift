import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct PDFResponsiveScrollingTests {
    @Test(arguments: [ReaderDisplayMode.singlePage, .twoUp])
    func discreteTrackpadTurnsMatchKeyboardAndConsumeRemainingGesture(mode: ReaderDisplayMode) throws {
        let (controller, reader, store, sessionID) = try makePagedReader(mode: mode)
        defer { controller.close() }
        reader.fitToHeight()
        settle(controller.window)

        for direction: Int32 in [-1, 1] {
            let start = direction < 0 ? 0 : 2
            _ = reader.goToPage(start)
            settle(controller.window)
            if direction < 0 { _ = reader.goToNextPage() } else { _ = reader.goToPreviousPage() }
            settle(controller.window)
            let expected = try #require(reader.testingCurrentReadingPosition)
            let expectedScale = reader.pdfView.scaleFactor
            _ = reader.goToPage(start)
            settle(controller.window)

            for step in rapidFlick {
                #expect(reader.testingHandleVerticalPageScroll(try makeEvent(step, direction: direction)))
                settle(controller.window)
            }
            let actual = try #require(reader.testingCurrentReadingPosition)
            #expect(actual.pageIndex == expected.pageIndex)
            #expect(abs(actual.point.x - expected.point.x) < 1)
            #expect(abs(actual.point.y - expected.point.y) < 1)
            #expect(abs(reader.pdfView.scaleFactor - expectedScale) < 0.001)
            #expect(store.session(for: sessionID)?.currentPageIndex == expected.pageIndex)
        }
    }

    @Test(arguments: [ReaderDisplayMode.singlePage, .twoUp])
    func discreteTrackpadScrollsWithinPageAndMomentumCannotTurn(mode: ReaderDisplayMode) throws {
        let (controller, reader, _, _) = try makePagedReader(mode: mode)
        defer { controller.close() }
        let scroll = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first)
        let clip = scroll.contentView
        let startY = clip.bounds.minY
        let began = WheelStep(delta: 0, phase: 1, expectedPhase: .began)
        let changed = WheelStep(delta: 120, phase: 2, expectedPhase: .changed)
        #expect(reader.testingHandleVerticalPageScroll(try makeEvent(began, direction: -1)))
        #expect(reader.testingHandleVerticalPageScroll(try makeEvent(changed, direction: -1)))
        #expect(clip.bounds.minY > startY + 1)
        #expect(reader.testingCurrentReadingPosition?.pageIndex == 0)

        let ended = WheelStep(delta: 0, phase: 4, expectedPhase: .ended)
        #expect(reader.testingHandleVerticalPageScroll(try makeEvent(ended, direction: -1)))
        for step in [
            WheelStep(delta: 9000, momentum: 1, expectedMomentum: .began),
            WheelStep(delta: 9000, momentum: 2, expectedMomentum: .changed),
            WheelStep(delta: 0, momentum: 3, expectedMomentum: .ended),
        ] {
            #expect(reader.testingHandleVerticalPageScroll(try makeEvent(step, direction: -1)))
        }
        settle(controller.window)
        #expect(reader.testingCurrentReadingPosition?.pageIndex == 0)

        #expect(reader.testingHandleVerticalPageScroll(try makeEvent(began, direction: -1)))
        #expect(reader.testingHandleVerticalPageScroll(try makeEvent(changed, direction: -1)))
        settle(controller.window)
        #expect(reader.testingCurrentReadingPosition?.pageIndex == (mode == .twoUp ? 2 : 1))
    }

    @Test
    func discreteTrackpadHandlerYieldsOutsideReaderAndInContinuousMode() throws {
        let (controller, reader, store, sessionID) = try makePagedReader(mode: .singlePage)
        defer { controller.close() }
        let event = try makeEvent(WheelStep(delta: 120, phase: 1, expectedPhase: .began), direction: -1)
        #expect(!reader.testingHandleVerticalPageScroll(event, pointerIsOverPDF: false))
        store.setDisplayMode(.singlePageContinuous, for: sessionID)
        #expect(!reader.testingHandleVerticalPageScroll(event))
    }

    private func makePagedReader(mode: ReaderDisplayMode) throws -> (MainWindowController, ReaderViewController, DocumentStore, UUID) {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(
            named: "discrete-trackpad", pageCount: 6, pageSize: NSSize(width: 720, height: 1800)
        ))
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: 1, for: session.id)
        settle(controller.window)
        let split = try #require(controller.window?.contentViewController as? SplitViewController)
        return (controller, split.readerViewController, store, session.id)
    }

    @Test(arguments: [
        ReaderDisplayMode.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous,
    ], [CGFloat(1), 1.37, 2.333333333333])
    func rapidGestureAndMomentumStayAtDocumentEdges(mode: ReaderDisplayMode, scale: CGFloat) throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".tmp/pdf-responsive-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("rapid-scroll.pdf")
        let fixture = TestPDFFixtures.makeBlankDocument(
            pageCount: 4, pageSize: NSSize(width: 720, height: 1800)
        )
        try #require(fixture.write(to: url))
        let store = makeIsolatedDocumentStore()
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        let session = try store.open(documentAt: url)
        store.setDisplayMode(mode, for: session.id)
        store.setScaleMode(.manual, scaleFactor: scale, for: session.id)
        settle(controller.window)
        let split = try #require(controller.window?.contentViewController as? SplitViewController)
        let reader = split.readerViewController
        let scroll = try #require(reader.pdfView.subviews.compactMap { $0 as? NSScrollView }.first)
        let clip = scroll.contentView

        // A phase-bearing direct call can enter AppKit's concurrent tracking
        // loop and wait for queued events. Fail before dispatch if the opt-out
        // regresses; never replace these events with legacy phase-less wheels.
        try #require(type(of: clip).isCompatibleWithResponsiveScrolling == false)
        let document = try #require(clip.documentView)
        try #require(document.frame.height > clip.bounds.height + 100)

        for atEnd in [false, true] {
            if atEnd { reader.goToLastPage() } else { reader.goToFirstPage() }
            settle(controller.window)
            var proposed = clip.bounds
            proposed.origin.y = atEnd ? 1_000_000 : -1_000_000
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
            settle(controller.window)
            let edge = clip.bounds.origin
            let samples = ResponsiveBoundarySamples()
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: nil
            ) { _ in
                MainActor.assumeIsolated { samples.origins.append(clip.bounds.origin) }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            // CG scroll phases and momentum phases have different numeric
            // encodings. Verify the resulting NSEvent lifecycle before dispatch.
            for step in rapidFlick {
                let event = try makeEvent(step, direction: atEnd ? -1 : 1)
                scroll.scrollWheel(with: event)
                samples.origins.append(clip.bounds.origin)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                samples.origins.append(clip.bounds.origin)
                #expect(abs(clip.bounds.origin.y - edge.y) < 0.01)
            }
            settle(controller.window)
            #expect(abs(clip.bounds.origin.y - edge.y) < 0.01)
            #expect(samples.origins.count >= rapidFlick.count * 2)
            #expect(samples.origins.allSatisfy { abs($0.y - edge.y) < 0.01 })
            NotificationCenter.default.removeObserver(observer)

            // A new gesture must immediately scroll back into the document.
            for step in inwardFlick {
                scroll.scrollWheel(with: try makeEvent(step, direction: atEnd ? 1 : -1))
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            settle(controller.window)
            let inwardDirection: CGFloat = atEnd ? -1 : 1
            #expect((clip.bounds.origin.y - edge.y) * inwardDirection > 0.5)

            // Start inside the page and reach the boundary at speed. Observe
            // every synchronous bounds change and both sides of each run-loop
            // turn, so an empty notification stream cannot make this pass.
            var lowerProposal = clip.bounds
            lowerProposal.origin.y = -1_000_000
            var upperProposal = clip.bounds
            upperProposal.origin.y = 1_000_000
            let minimumY = clip.constrainBoundsRect(lowerProposal).minY
            let maximumY = clip.constrainBoundsRect(upperProposal).minY
            let startY = edge.y + inwardDirection * min(120, (maximumY - minimumY) / 2)
            clip.scroll(to: NSPoint(x: edge.x, y: startY))
            scroll.reflectScrolledClipView(clip)
            settle(controller.window)
            try #require(abs(clip.bounds.minY - startY) < 0.01)
            let collisionSamples = ResponsiveBoundarySamples()
            let collisionObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: nil
            ) { _ in
                MainActor.assumeIsolated { collisionSamples.origins.append(clip.bounds.origin) }
            }
            defer { NotificationCenter.default.removeObserver(collisionObserver) }
            for step in rapidFlick {
                scroll.scrollWheel(with: try makeEvent(step, direction: atEnd ? -1 : 1))
                collisionSamples.origins.append(clip.bounds.origin)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                collisionSamples.origins.append(clip.bounds.origin)
            }
            #expect(collisionSamples.origins.count >= rapidFlick.count * 2)
            #expect(collisionSamples.origins.contains { abs($0.y - startY) > 0.5 })
            #expect(abs(clip.bounds.minY - edge.y) < 0.01)

            // Reverse immediately after the momentum ends, without a settling
            // wait or a programmatic position change between the two gestures.
            let reversedAt = collisionSamples.origins.count
            for step in inwardFlick {
                scroll.scrollWheel(with: try makeEvent(step, direction: atEnd ? 1 : -1))
                collisionSamples.origins.append(clip.bounds.origin)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                collisionSamples.origins.append(clip.bounds.origin)
            }
            #expect(collisionSamples.origins.count >= reversedAt + inwardFlick.count * 2)
            #expect(collisionSamples.origins.dropFirst(reversedAt).contains {
                ($0.y - edge.y) * inwardDirection > 0.5
            })
            #expect((clip.bounds.minY - edge.y) * inwardDirection > 0.5)
            #expect(collisionSamples.origins.allSatisfy {
                $0.y >= minimumY - 0.01 && $0.y <= maximumY + 0.01
            })
            NotificationCenter.default.removeObserver(collisionObserver)
        }
    }

    private var rapidFlick: [WheelStep] {
        [
            WheelStep(delta: 0, phase: 1, expectedPhase: .began),
            WheelStep(delta: 24, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 120, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 420, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 180, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 0, phase: 4, expectedPhase: .ended),
            WheelStep(delta: 60, momentum: 1, expectedMomentum: .began),
            WheelStep(delta: 22, momentum: 2, expectedMomentum: .changed),
            WheelStep(delta: 4, momentum: 2, expectedMomentum: .changed),
            WheelStep(delta: 0, momentum: 3, expectedMomentum: .ended),
        ]
    }

    private var inwardFlick: [WheelStep] {
        [
            WheelStep(delta: 0, phase: 1, expectedPhase: .began),
            WheelStep(delta: 20, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 35, phase: 2, expectedPhase: .changed),
            WheelStep(delta: 0, phase: 4, expectedPhase: .ended),
            WheelStep(delta: 10, momentum: 1, expectedMomentum: .began),
            WheelStep(delta: 0, momentum: 3, expectedMomentum: .ended),
        ]
    }

    private func makeEvent(_ step: WheelStep, direction: Int32) throws -> NSEvent {
        let cg = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: step.delta * direction, wheel2: 0, wheel3: 0
        ))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: step.phase)
        cg.flags = []
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: step.momentum)
        let event = try #require(NSEvent(cgEvent: cg))
        try #require(event.phase == step.expectedPhase)
        try #require(event.momentumPhase == step.expectedMomentum)
        try #require(event.hasPreciseScrollingDeltas)
        try #require(abs(event.scrollingDeltaY - CGFloat(step.delta * direction)) < 0.01)
        return event
    }

    private func settle(_ window: NSWindow?) {
        window?.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        window?.layoutIfNeeded()
    }
}

private struct WheelStep {
    let delta: Int32
    var phase: Int64 = 0
    var momentum: Int64 = 0
    var expectedPhase: NSEvent.Phase = []
    var expectedMomentum: NSEvent.Phase = []
}

@MainActor
private final class ResponsiveBoundarySamples {
    var origins: [NSPoint] = []
}
