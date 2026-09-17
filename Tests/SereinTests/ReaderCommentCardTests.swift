import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderCommentCardTests: XCTestCase {
    func testHoverCardKeepsItsPositionAndFocusThroughEditing() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let keyWindow = NSApp.keyWindow
        fixture.controller.handlePointerMoved(try fixture.event(.mouseMoved, in: fixture.annotation.bounds))
        settle(0.17)

        let panel = try XCTUnwrap(fixture.controller.testingCommentPanel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.editor.isEditing)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        XCTAssertFalse(panel.frame.intersects(fixture.iconScreenRect))
        let previewFrame = panel.frame

        fixture.controller.handlePointerMoved(try fixture.event(.mouseMoved, in: fixture.iconBounds))
        XCTAssertTrue(fixture.controller.testingCommentPanel === panel)
        XCTAssertEqual(panel.frame, previewFrame)

        fixture.controller.handlePointerMoved(nil)
        settle(0.06)
        XCTAssertTrue(panel.isVisible)
        panel.editor.cardView.mouseEntered(with: try cardEvent(.mouseEntered, in: panel))
        settle(0.18)
        XCTAssertTrue(fixture.controller.testingCommentPanel === panel)
        XCTAssertTrue(panel.isVisible)

        panel.editor.cardView.mouseDown(with: try cardEvent(.leftMouseDown, in: panel))
        let text = try XCTUnwrap(panel.firstResponder as? NSTextView)
        XCTAssertTrue(fixture.controller.testingCommentPanel === panel)
        XCTAssertTrue(panel.editor.isEditing)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(text.isEditable)
        XCTAssertTrue(text.window === panel)
        XCTAssertEqual(text.string, fixture.comment)
        XCTAssertEqual(panel.frame.width, previewFrame.width)
        XCTAssertEqual(panel.frame.minX, previewFrame.minX)
        XCTAssertTrue(panel.frame.minY == previewFrame.minY || panel.frame.maxY == previewFrame.maxY)
        XCTAssertFalse(panel.frame.intersects(fixture.iconScreenRect))

        panel.editor.cardView.mouseExited(with: try cardEvent(.mouseExited, in: panel))
        fixture.controller.handlePointerMoved(nil)
        settle(0.18)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.firstResponder === text)

        // Test runners may not become the foreground app. Deliver the delegate
        // notification produced when clicking the reader gives it key status.
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        settle(0.03)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(fixture.controller.testingCommentPanel)
        XCTAssertTrue(fixture.window.firstResponder === fixture.pdfView)
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.comment, fixture.comment)
    }

    func testClickingEachMarkupIconOpensFocusedEditorAndSavesToDocumentStore() throws {
        for type in AnnotationMarkupType.allCases {
            let fixture = try makeFixture(type: type)
            defer { fixture.close() }
            XCTAssertNil(fixture.controller.testingCommentPanel)
            fixture.pdfView.mouseDown(with: try fixture.event(.leftMouseDown, in: fixture.iconBounds))

            let panel = try XCTUnwrap(fixture.controller.testingCommentPanel, type.rawValue)
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.editor.isEditing)
            XCTAssertTrue(panel.canBecomeKey)
            XCTAssertFalse(panel.frame.intersects(fixture.iconScreenRect))
            let text = try XCTUnwrap(panel.firstResponder as? NSTextView)
            let comment = "Edited \(type.rawValue) comment\n第二行保留"
            text.insertText(comment, replacementRange: NSRange(location: 0, length: (text.string as NSString).length))
            text.keyDown(with: makeReturnKeyEvent(in: panel, modifiers: .command))

            XCTAssertNil(fixture.controller.testingCommentPanel)
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(fixture.annotation.contents, comment)
            XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.comment, comment)
            XCTAssertEqual(fixture.store.session(for: fixture.sessionID)?.isDirty, true)
        }
    }

    func testCancelAndSessionChangesCloseCardWithoutSavingDrafts() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.pdfView.mouseDown(with: try fixture.event(.leftMouseDown, in: fixture.iconBounds))
        let cancelledPanel = try XCTUnwrap(fixture.controller.testingCommentPanel)
        let text = try XCTUnwrap(cancelledPanel.firstResponder as? NSTextView)
        text.insertText("Discard this draft", replacementRange: NSRange(location: 0, length: (text.string as NSString).length))
        text.keyDown(with: makeKeyEvent(characters: "\u{1b}", keyCode: 53, window: cancelledPanel))
        XCTAssertNil(fixture.controller.testingCommentPanel)
        XCTAssertFalse(cancelledPanel.isVisible)
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.comment, fixture.comment)
        XCTAssertEqual(fixture.store.session(for: fixture.sessionID)?.isDirty, false)

        fixture.controller.handlePointerMoved(try fixture.event(.mouseMoved, in: fixture.iconBounds))
        settle(0.17)
        let dismissedPreview = try XCTUnwrap(fixture.controller.testingCommentPanel)
        fixture.controller.handlePointerMoved(nil)
        settle(0.17)
        XCTAssertFalse(dismissedPreview.isVisible)
        XCTAssertNil(fixture.controller.testingCommentPanel)

        fixture.controller.handlePointerMoved(try fixture.event(.mouseMoved, in: fixture.iconBounds))
        settle(0.17)
        let preview = try XCTUnwrap(fixture.controller.testingCommentPanel)
        XCTAssertFalse(preview.editor.isEditing)
        fixture.controller.sessionDidChange()
        XCTAssertFalse(preview.isVisible)
        XCTAssertNil(fixture.controller.testingCommentPanel)

        fixture.pdfView.mouseDown(with: try fixture.event(.leftMouseDown, in: fixture.iconBounds))
        let editor = try XCTUnwrap(fixture.controller.testingCommentPanel)
        let draft = try XCTUnwrap(editor.firstResponder as? NSTextView)
        draft.insertText("Another unsaved draft", replacementRange: NSRange(location: 0, length: (draft.string as NSString).length))
        fixture.controller.activeSessionID = nil
        fixture.controller.sessionDidChange()
        XCTAssertFalse(editor.isVisible)
        XCTAssertNil(fixture.controller.testingCommentPanel)
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.comment, fixture.comment)

        fixture.controller.activeSessionID = fixture.sessionID
        fixture.controller.handlePointerMoved(try fixture.event(.mouseMoved, in: fixture.iconBounds))
        fixture.controller.activeSessionID = nil
        fixture.controller.sessionDidChange()
        settle(0.17)
        XCTAssertNil(fixture.controller.testingCommentPanel)
    }

    private func makeFixture(type: AnnotationMarkupType = .highlight) throws -> Fixture {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".tmp/comment-card-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("comments.pdf")
        let source = TestPDFFixtures.makeBlankDocument(pageCount: 1, pageSize: NSSize(width: 600, height: 800))
        let page = try XCTUnwrap(source.page(at: 0))
        let annotation = PDFAnnotation(bounds: NSRect(x: 180, y: 430, width: 180, height: 20),
                                       forType: type.pdfSubtype, withProperties: nil)
        annotation.userName = UUID().uuidString
        annotation.color = HighlightColor.default.nsColor
        let comment = "Original comment\n第二行评论"
        annotation.contents = comment
        page.addAnnotation(annotation)
        XCTAssertTrue(source.write(to: url))

        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: url)
        let document = try store.pdfDocument(for: session.id)
        let loadedPage = try XCTUnwrap(document.page(at: 0))
        let loadedAnnotation = try XCTUnwrap(loadedPage.annotations.first)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        let pdfView = ReaderPDFView(frame: NSRect(x: 0, y: 0, width: 900, height: 800))
        window.contentView = pdfView
        pdfView.displayMode = .singlePage
        pdfView.document = document
        pdfView.scaleFactor = 0.8
        pdfView.layoutDocumentView()
        pdfView.annotationsChanged(on: loadedPage)
        let controller = ReaderAnnotationInteractionController(documentStore: store, pdfView: pdfView)
        controller.activeSessionID = session.id
        controller.install(in: pdfView)
        controller.onNavigateRequested = { _ in
            XCTFail("Editing a visible comment must not move the reader")
        }
        pdfView.onAnnotationActivationRequested = { [weak controller] event in
            controller?.activateAnnotation(at: event) ?? false
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(pdfView)
        pdfView.layoutSubtreeIfNeeded()
        return Fixture(root: root, store: store, sessionID: session.id, window: window,
                       pdfView: pdfView, annotation: loadedAnnotation, page: loadedPage,
                       controller: controller, comment: comment)
    }

    private func cardEvent(_ type: NSEvent.EventType, in panel: AnnotationCommentPanel) throws -> NSEvent {
        let point = NSPoint(x: panel.contentView!.bounds.midX, y: panel.contentView!.bounds.midY)
        if type == .mouseEntered || type == .mouseExited {
            return try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                trackingNumber: 0, userData: nil))
        }
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1))
    }

    private func settle(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let store: DocumentStore
        let sessionID: UUID
        let window: NSWindow
        let pdfView: ReaderPDFView
        let annotation: PDFAnnotation
        let page: PDFPage
        let controller: ReaderAnnotationInteractionController
        let comment: String

        var iconBounds: NSRect { pdfView.commentIcons.bounds(for: annotation) }

        var iconScreenRect: NSRect {
            window.convertToScreen(pdfView.convert(pdfView.convert(iconBounds, from: page), to: nil))
        }

        func event(_ type: NSEvent.EventType, in bounds: NSRect) throws -> NSEvent {
            let point = NSPoint(x: bounds.midX, y: bounds.midY)
            let location = pdfView.convert(pdfView.convert(point, from: page), to: nil)
            return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 1))
        }

        func close() {
            controller.sessionDidChange()
            window.close()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
