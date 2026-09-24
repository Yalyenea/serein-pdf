import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderTranslationControllerTests: XCTestCase {
    func testEscapeClosesBeforeTheFocusedControlConsumesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let control = EscapeConsumingTextView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        try XCTUnwrap(fixture.panel.contentView).addSubview(control)
        XCTAssertTrue(fixture.panel.makeFirstResponder(control))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.panel.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))

        fixture.panel.sendEvent(event)

        XCTAssertFalse(control.receivedKeyDown)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)
    }

    func testReturningFocusToReaderClosesTheTranslation() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        // SwiftPM runs without an active application; dispatch AppKit's focus lifecycle directly.
        fixture.panel.becomeKey()
        fixture.panel.resignKey()
        fixture.owner.makeKey()
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)
    }

    func testDownloadSheetDoesNotDismissItsTranslationWindow() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: .titled, backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        fixture.panel.beginSheet(sheet)
        defer { fixture.panel.endSheet(sheet); sheet.close() }
        fixture.panel.resignKey()
        XCTAssertTrue(fixture.panel.isVisible)
        XCTAssertTrue(fixture.panel.attachedSheet === sheet)
    }

    func testApplicationDeactivationAndOwnerClosureDismissTheTranslation() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertNil(fixture.panel.parent)

        XCTAssertTrue(fixture.controller.show(selection: fixture.selection, sessionID: fixture.sessionID, in: fixture.pdf))
        let reopened = try XCTUnwrap(fixture.owner.childWindows?.first)
        fixture.owner.close()
        XCTAssertFalse(reopened.isVisible)
        XCTAssertNil(reopened.parent)
    }

    @available(macOS 15.0, *)
    func testUnrecognizedLanguageDisplaysAnErrorWithoutRemovingContent() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.close(); fixture.owner.close() }
        let content = try XCTUnwrap(fixture.panel.contentView)
        func textViews(in view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        XCTAssertTrue(textViews(in: content).contains {
            $0.string == SelectionTranslationError.unrecognizedLanguage.localizedDescription
        })
    }

    private func makeFixture() throws -> (
        controller: ReaderTranslationController, owner: NSWindow, panel: NSWindow,
        pdf: PDFView, selection: PDFSelection, sessionID: UUID
    ) {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        // No language can be inferred from numbers, so lifecycle tests never start a system download.
        let session = try store.open(documentAt: TestPDFFixtures.makeSearchablePDF(
            named: "translation-panel", pages: ["12345 + 67890"]
        ))
        let document = try store.pdfDocument(for: session.id)
        let selection = try XCTUnwrap(document.findString("12345 + 67890", withOptions: []).first)
        let owner = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 500),
                             styleMask: .titled, backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let pdf = PDFView(frame: owner.contentView!.bounds)
        pdf.document = document
        owner.contentView = pdf
        owner.makeKeyAndOrderFront(nil)
        let controller = ReaderTranslationController(documentStore: store)
        XCTAssertTrue(controller.show(selection: selection, sessionID: session.id, in: pdf))
        let panel = try XCTUnwrap(owner.childWindows?.first)
        XCTAssertTrue(panel.isVisible)
        return (controller, owner, panel, pdf, selection, session.id)
    }
}

private final class EscapeConsumingTextView: NSTextView {
    var receivedKeyDown = false
    override func keyDown(with event: NSEvent) { receivedKeyDown = true }
}
