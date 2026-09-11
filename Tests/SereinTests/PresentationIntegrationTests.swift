import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct PresentationIntegrationTests {
    @Test
    func demoEntryEscapeAndReentryKeepInkTemporary() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let reader = try fixture.reader()
        let overlay = reader.presentationOverlay

        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        #expect(overlay.isPresentationEnabled)
        #expect(overlay.tool == .pointer)
        try drawStroke(in: reader)
        #expect(overlay.strokes.count == 1)

        #expect(fixture.controller.exitTransientReaderState())
        #expect(fixture.controller.isDemoModeEnabled)
        #expect(overlay.tool == .pointer)
        #expect(overlay.strokes.count == 1)

        #expect(fixture.controller.exitTransientReaderState())
        #expect(fixture.controller.isDemoModeEnabled == false)
        #expect(overlay.isPresentationEnabled == false)
        #expect(overlay.strokes.isEmpty)

        fixture.controller.toggleDemoMode()
        #expect(overlay.isPresentationEnabled)
        #expect(overlay.strokes.isEmpty)
        #expect(overlay.tool == .pointer)
    }

    @Test
    func nativeFullScreenExitEndsPresentationAndClearsInk() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let reader = try fixture.reader()
        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        try drawStroke(in: reader)
        #expect(reader.presentationOverlay.strokes.count == 1)

        fixture.controller.windowDidExitFullScreen(
            Notification(name: NSWindow.didExitFullScreenNotification, object: fixture.controller.window)
        )

        #expect(fixture.controller.isDemoModeEnabled == false)
        #expect(reader.presentationOverlay.isPresentationEnabled == false)
        #expect(reader.presentationOverlay.strokes.isEmpty)
        #expect(reader.presentationOverlay.tool == .pointer)
    }

    @Test
    func presentationShortcutsWinBeforeGlobalShortcutsAndYieldToTextEditing() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let window = try #require(fixture.controller.window as? ReaderShortcutWindow)
        let reader = try fixture.reader()
        var globalEvents: [String] = []
        fixture.controller.installPlainShortcutHandler { event, _ in
            globalEvents.append(event.charactersIgnoringModifiers ?? "")
            return true
        }
        fixture.controller.toggleDemoMode()
        flushLayout(window)
        window.makeFirstResponder(reader.pdfView)

        window.sendEvent(keyEvent("p", in: window))
        #expect(reader.presentationOverlay.tool == .pen)
        #expect(globalEvents.isEmpty)
        #expect(window.performKeyEquivalent(with: keyEvent("r", in: window)))
        #expect(reader.presentationOverlay.tool == .laser)
        #expect(globalEvents.isEmpty)

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 32))
        editor.isEditable = true
        window.contentView?.addSubview(editor)
        defer { editor.removeFromSuperview() }
        #expect(window.makeFirstResponder(editor))
        #expect(fixture.controller.handlePresentationShortcut(keyEvent("p", in: window)) == false)
        #expect(fixture.controller.handlePresentationShortcut(keyEvent("z", modifiers: .command, in: window)) == false)
        #expect(reader.presentationOverlay.tool == .laser)

        window.makeFirstResponder(reader.pdfView)
        #expect(window.performKeyEquivalent(with: keyEvent("z", modifiers: .command, in: window)))
        #expect(globalEvents.isEmpty)
        fixture.controller.toggleDemoMode()
        window.sendEvent(keyEvent("p", in: window))
        #expect(globalEvents == ["p"])
    }

    @Test
    func presentationStateAndInkStayWithinTheirWindow() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let secondID = fixture.store.createWindow(copyingFrom: fixture.controller.windowID)
        _ = try fixture.store.open(documentAt: fixture.makePDF(named: "second"), in: secondID)
        let second = MainWindowController(documentStore: fixture.store, windowID: secondID)
        defer { second.close() }
        let secondSplit = try #require(second.window?.contentViewController as? SplitViewController)
        let secondReader = secondSplit.readerViewController
        let firstReader = try fixture.reader()

        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        flushLayout(second.window)
        try drawStroke(in: firstReader)
        #expect(firstReader.presentationOverlay.strokes.count == 1)
        #expect(second.isDemoModeEnabled == false)
        #expect(secondReader.presentationOverlay.isPresentationEnabled == false)
        #expect(secondReader.presentationOverlay.strokes.isEmpty)
        #expect(second.handlePresentationShortcut(keyEvent("p", in: try #require(second.window))) == false)

        second.toggleDemoMode()
        flushLayout(second.window)
        try drawStroke(in: secondReader)
        second.toggleDemoMode()
        #expect(secondReader.presentationOverlay.strokes.isEmpty)
        #expect(firstReader.presentationOverlay.strokes.count == 1)
        #expect(firstReader.presentationOverlay.isPresentationEnabled)
    }

    @Test
    func pageScopedUndoKeepsOtherPagesAndDocumentSwitchClearsInk() throws {
        let fixture = try makeFixture(pageCount: 2)
        defer { fixture.close() }
        let reader = try fixture.reader()
        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        let firstPage = try #require(reader.pdfView.currentPage)
        try drawStroke(in: reader)

        reader.goToNextPage()
        flushLayout(fixture.controller.window)
        let secondPage = try #require(reader.pdfView.currentPage)
        #expect(firstPage !== secondPage)
        #expect(reader.hasUndoableHighlight == false)
        #expect(reader.presentationOverlay.strokes.first?.page === firstPage)
        try drawStroke(in: reader)
        #expect(reader.presentationOverlay.strokes.count == 2)
        #expect(reader.hasUndoableHighlight)
        #expect(reader.undoLastHighlight())
        #expect(reader.presentationOverlay.strokes.count == 1)
        #expect(reader.presentationOverlay.strokes.first?.page === firstPage)

        reader.goToPreviousPage()
        flushLayout(fixture.controller.window)
        #expect(reader.pdfView.currentPage === firstPage)
        #expect(reader.hasUndoableHighlight)
        _ = try fixture.store.open(documentAt: fixture.makePDF(named: "replacement"))
        flushLayout(fixture.controller.window)
        #expect(reader.presentationOverlay.isPresentationEnabled)
        #expect(reader.presentationOverlay.strokes.isEmpty)
        #expect(reader.hasUndoableHighlight == false)

        fixture.store.activate(sessionID: fixture.sessionID, in: fixture.controller.windowID)
        flushLayout(fixture.controller.window)
        #expect(reader.presentationOverlay.strokes.isEmpty)
    }

    @Test
    func penDoesNotMutatePDFBytesAnnotationsOrDirtyState() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let reader = try fixture.reader()
        let document = try #require(reader.pdfView.document)
        let page = try #require(document.page(at: 0))
        let url = try #require(fixture.store.session(for: fixture.sessionID)?.url)
        let originalBytes = try Data(contentsOf: url)
        let originalAnnotationCount = page.annotations.count
        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        try drawStroke(in: reader)

        #expect(reader.presentationOverlay.strokes.count == 1)
        #expect(page.annotations.count == originalAnnotationCount)
        let session = try #require(fixture.store.session(for: fixture.sessionID))
        #expect(session.isDirty == false)
        #expect(session.annotationGeneration == 0)
        #expect(session.undoStack.isEmpty)
        #expect(try Data(contentsOf: url) == originalBytes)
        let exportedData = try #require(document.dataRepresentation())
        let exported = try #require(PDFDocument(data: exportedData))
        #expect(exported.page(at: 0)?.annotations.count == originalAnnotationCount)
    }

    @Test
    func presentationUndoNeverConsumesExistingHighlightHistory() throws {
        let fixture = try makeFixture(selectable: true)
        defer { fixture.close() }
        let reader = try fixture.reader()
        let document = try #require(reader.pdfView.document)
        let page = try #require(document.page(at: 0))
        let selection: PDFSelection? = document.findString("Presentation", withOptions: []).first
        let selected: PDFSelection = try #require(selection)
        reader.pdfView.currentSelection = selected
        #expect(reader.triggerAnnotationShortcut(.highlight))
        let before = try #require(fixture.store.session(for: fixture.sessionID))
        #expect(before.undoStack.count == 1)
        let highlightCount = page.annotations.count
        #expect(highlightCount > 0)

        fixture.controller.toggleDemoMode()
        flushLayout(fixture.controller.window)
        try drawStroke(in: reader)
        #expect(reader.undoLastHighlight())
        #expect(reader.presentationOverlay.strokes.isEmpty)
        #expect(reader.undoLastHighlight())
        #expect(reader.redoLastHighlight() == false)
        #expect(reader.triggerAnnotationShortcut(.highlight) == false)
        let during = try #require(fixture.store.session(for: fixture.sessionID))
        #expect(during.undoStack.count == before.undoStack.count)
        #expect(during.annotationGeneration == before.annotationGeneration)
        #expect(page.annotations.count == highlightCount)

        fixture.controller.toggleDemoMode()
        #expect(reader.hasUndoableHighlight)
        #expect(reader.undoLastHighlight())
        #expect(page.annotations.isEmpty)
    }

}

@MainActor
private struct PresentationFixture {
    let root: URL
    let store: DocumentStore
    let controller: MainWindowController
    let sessionID: UUID

    func reader() throws -> ReaderViewController {
        try #require(controller.window?.contentViewController as? SplitViewController).readerViewController
    }

    func makePDF(named name: String, pageCount: Int = 1) throws -> URL {
        let url = root.appendingPathComponent("\(name).pdf")
        try TestPDFFixtures.writeLabeledPDF(
            to: url,
            named: name,
            pageSizes: Array(repeating: NSSize(width: 600, height: 800), count: pageCount)
        )
        return url
    }

    func close() {
        controller.close()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func makeFixture(pageCount: Int = 1, selectable: Bool = false) throws -> PresentationFixture {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".tmp/presentation-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("source.pdf")
    if selectable {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        text.string = "Presentation highlight history"
        text.font = NSFont.systemFont(ofSize: 24)
        text.textContainerInset = NSSize(width: 60, height: 80)
        try text.dataWithPDF(inside: text.bounds).write(to: url)
    } else {
        try TestPDFFixtures.writeLabeledPDF(
            to: url,
            named: "Presentation",
            pageSizes: Array(repeating: NSSize(width: 600, height: 800), count: pageCount)
        )
    }
    let store = makeIsolatedDocumentStore()
    let controller = MainWindowController(documentStore: store)
    let session = try store.open(documentAt: url)
    flushLayout(controller.window)
    return PresentationFixture(root: root, store: store, controller: controller, sessionID: session.id)
}

@MainActor
private func flushLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}

@MainActor
private func drawStroke(in reader: ReaderViewController) throws {
    let overlay = reader.presentationOverlay
    let window = try #require(overlay.window)
    let page = try #require(reader.pdfView.currentPage)
    let bounds = page.bounds(for: reader.pdfView.displayBox)
    overlay.selectTool(.pen)
    for (type, offset) in [(NSEvent.EventType.leftMouseDown, -30.0), (.leftMouseDragged, 0), (.leftMouseUp, 30)] {
        let pagePoint = NSPoint(x: bounds.midX + offset, y: bounds.midY)
        let viewPoint = reader.pdfView.convert(pagePoint, from: page)
        let event = try #require(NSEvent.mouseEvent(
            with: type,
            location: reader.pdfView.convert(viewPoint, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        switch type {
        case .leftMouseDown: overlay.mouseDown(with: event)
        case .leftMouseDragged: overlay.mouseDragged(with: event)
        default: overlay.mouseUp(with: event)
        }
    }
}

@MainActor
private func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: 0
    )!
}
