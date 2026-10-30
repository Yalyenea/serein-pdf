import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReaderContextMenuTests: XCTestCase {
    func testBlankMenuHidesIrrelevantActionsAndNativePDFControls() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let menu = try fixture.menu(at: CGPoint(x: 300, y: 300))
        XCTAssertFalse(menu.allowsContextMenuPlugIns)
        if #available(macOS 15.2, *) { XCTAssertFalse(menu.automaticallyInsertsWritingToolsItems) }
        XCTAssertEqual(titles(menu), ["Copy Area…", "Copy Page as Image", "Send Page Image to Codex"])
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled))
        XCTAssertFalse(menu.items.last?.isSeparatorItem == true)
        XCTAssertFalse(menu.items.first?.isSeparatorItem == true)
    }

    func testSelectedTextMenuAndSubmenuBindCopyToOriginalSelection() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let selection = try fixture.selection("alpha")
        fixture.reader.pdfView.currentSelection = selection
        let menu = try fixture.menu(over: selection)
        XCTAssertEqual(titles(menu), ["Copy", "Translate…", "Mark Up", "Add Comment", "Copy Area…", "Send Selection to Codex"])
        let markup = try XCTUnwrap(menu.item(withTitle: "Mark Up")?.submenu)
        XCTAssertEqual(titles(markup), ["Highlight", "Underline", "Strikethrough"])
        let copy = try XCTUnwrap(menu.item(withTitle: "Copy"))
        XCTAssertEqual(copy.keyEquivalent, "c")
        XCTAssertEqual(copy.keyEquivalentModifierMask, [.command])
        fixture.reader.pdfView.currentSelection = try fixture.selection("beta")
        preservingClipboard {
            menu.performActionForItem(at: menu.index(of: copy))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "alpha")
        }
        let translate = try XCTUnwrap(menu.item(withTitle: "Translate…"))
        let controller = try XCTUnwrap(translate.target as? ReaderAnnotationInteractionController)
        var translated: String?
        controller.onTranslateSelectionRequested = { translated = $0.string }
        menu.performActionForItem(at: menu.index(of: translate))
        XCTAssertEqual(translated, "alpha")
        markup.performActionForItem(at: 0)
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.snippet, "alpha")
    }

    func testPermissionsHideCopyAndAnnotationActionsIndependently() throws {
        // PDF permission flags: commenting (bit 6) and content copying (bit 4).
        for (permissions, expected) in [
            (1 << 6, ["Mark Up", "Add Comment"]),
            (1 << 4, ["Copy", "Translate…", "Copy Area…", "Send Selection to Codex"]),
        ] {
            let fixture = try Fixture(permissions: permissions)
            defer { fixture.window.close() }
            let selection = try fixture.selection("alpha")
            fixture.reader.pdfView.currentSelection = selection
            XCTAssertEqual(titles(try fixture.menu(over: selection)), expected)
        }
    }

    func testRightClickOutsideSelectionDoesNotReuseStaleText() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        fixture.reader.pdfView.currentSelection = try fixture.selection("alpha")
        let blank = try fixture.menu(at: CGPoint(x: 300, y: 300))
        XCTAssertNil(blank.item(withTitle: "Copy"))
        XCTAssertNil(blank.item(withTitle: "Translate…"))
        XCTAssertNil(blank.item(withTitle: "Mark Up"))
        let target = try fixture.selection("beta")
        let text = try fixture.menu(over: target)
        var sent: String?
        fixture.reader.onSendSelectionToCodexRequested = { sent = $0 }
        let item = try XCTUnwrap(text.item(withTitle: "Send Selection to Codex"))
        text.performActionForItem(at: text.index(of: item))
        XCTAssertEqual(sent, "beta")
    }

    func testExternalLinkKeepsBrowserActionAndCopiesTheClickedURL() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        fixture.reader.pdfView.currentSelection = try fixture.selection("alpha")
        let link = PDFAnnotation(bounds: CGRect(x: 200, y: 300, width: 100, height: 30), forType: .link, withProperties: nil)
        let url = try XCTUnwrap(URL(string: "https://example.com/paper?section=2"))
        link.url = url
        fixture.page.addAnnotation(link)
        let menu = try fixture.menu(at: CGPoint(x: 220, y: 310))
        XCTAssertEqual(titles(menu), ["Open in Browser", "Copy Link", "Copy Area…"])
        let open = try XCTUnwrap(menu.item(withTitle: "Open in Browser"))
        let controller = try XCTUnwrap(open.target as? ReaderAnnotationInteractionController)
        var opened: URL?
        controller.openURL = { opened = $0; return true }
        menu.performActionForItem(at: menu.index(of: open))
        XCTAssertEqual(opened, url)
        let copy = try XCTUnwrap(menu.item(withTitle: "Copy Link"))
        preservingClipboard {
            menu.performActionForItem(at: menu.index(of: copy))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), url.absoluteString)
        }
    }

    func testInternalLinkUsesExistingNavigationCallback() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let destination = PDFDestination(page: fixture.page, at: CGPoint(x: 40, y: 100))
        let link = PDFAnnotation(bounds: CGRect(x: 200, y: 300, width: 100, height: 30), forType: .link, withProperties: nil)
        link.action = PDFActionGoTo(destination: destination)
        fixture.page.addAnnotation(link)
        let menu = try fixture.menu(at: CGPoint(x: 220, y: 310))
        XCTAssertEqual(titles(menu), ["Open Link", "Copy Area…"])
        var navigated: PDFDestination?
        fixture.reader.pdfView.onInternalLinkNavigationRequested = { navigated = $0; return true }
        let item = try XCTUnwrap(menu.item(withTitle: "Open Link"))
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertTrue(navigated?.page === fixture.page)
        XCTAssertEqual(navigated?.point, destination.point)
    }

    func testAnnotationMenuCanRecolorAndDeleteClickedGroup() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let selection = try fixture.selection("beta")
        let records = HighlightService.applyHighlight(to: selection)
        fixture.store.noteHighlightsAdded(records, for: fixture.sessionID)
        fixture.reader.pdfView.currentSelection = try fixture.selection("alpha")
        let menu = try fixture.menu(over: selection)
        XCTAssertEqual(titles(menu), ["Copy Snippet", "Edit Comment", "Color", "Delete Annotation", "Copy Area…"])
        let colors = try XCTUnwrap(menu.item(withTitle: "Color")?.submenu)
        let green = try XCTUnwrap(colors.item(withTitle: "Green"))
        colors.performActionForItem(at: colors.index(of: green))
        XCTAssertEqual(fixture.store.annotationGroups(for: fixture.sessionID).first?.color, .green)
        XCTAssertTrue(try XCTUnwrap(fixture.store.session(for: fixture.sessionID)).isDirty)
        let delete = try XCTUnwrap(menu.item(withTitle: "Delete Annotation"))
        menu.performActionForItem(at: menu.index(of: delete))
        XCTAssertTrue(fixture.store.annotationGroups(for: fixture.sessionID).isEmpty)
    }

    func testStaleMenuCannotAnnotateTranslateOrStartAreaCopyInAnotherDocument() throws {
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let selection = try fixture.selection("alpha")
        fixture.reader.pdfView.currentSelection = selection
        let menu = try fixture.menu(over: selection)
        let markup = try XCTUnwrap(menu.item(withTitle: "Mark Up")?.submenu)
        let translate = try XCTUnwrap(menu.item(withTitle: "Translate…"))
        let controller = try XCTUnwrap(translate.target as? ReaderAnnotationInteractionController)
        var translations = 0
        var sends = 0
        controller.onTranslateSelectionRequested = { _ in translations += 1 }
        fixture.reader.onSendSelectionToCodexRequested = { _ in sends += 1 }
        let replacement = try EmbeddedImagePDFFixture.document(content: "")
        fixture.reader.pdfView.setReaderDocument(replacement)
        markup.performActionForItem(at: 0)
        menu.performActionForItem(at: menu.index(of: translate))
        let area = try XCTUnwrap(menu.item(withTitle: "Copy Area…"))
        menu.performActionForItem(at: menu.index(of: area))
        let send = try XCTUnwrap(menu.item(withTitle: "Send Selection to Codex"))
        menu.performActionForItem(at: menu.index(of: send))
        XCTAssertFalse(try XCTUnwrap(fixture.reader.pdfView.areaSelectionOverlay).isSelecting)
        XCTAssertEqual(translations, 0)
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(fixture.page.annotations.isEmpty)
        XCTAssertTrue(try XCTUnwrap(replacement.page(at: 0)).annotations.isEmpty)
    }

    private func titles(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }

    private func preservingClipboard(_ body: () -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            })
        }
        body()
    }

    @MainActor
    private struct Fixture {
        let store: DocumentStore
        let sessionID: UUID
        let window: MainWindowController
        let reader: ReaderViewController
        let document: PDFDocument
        let page: PDFPage

        init(permissions: Int? = nil) throws {
            store = makeIsolatedDocumentStore()
            let url = try TestPDFFixtures.makeSearchablePDF(named: "reader-context-menu", pages: ["alpha beta gamma"])
            if let permissions {
                let source = try XCTUnwrap(PDFDocument(url: url))
                XCTAssertTrue(source.write(to: url, withOptions: [
                    .ownerPasswordOption: "owner-only", .userPasswordOption: "",
                    .accessPermissionsOption: NSNumber(value: permissions),
                ]))
            }
            sessionID = try store.open(documentAt: url).id
            window = MainWindowController(documentStore: store)
            window.showWindow(nil)
            window.window?.contentView?.layoutSubtreeIfNeeded()
            reader = try XCTUnwrap((window.window?.contentViewController as? SplitViewController)?.readerViewController)
            document = try XCTUnwrap(reader.pdfView.document)
            page = try XCTUnwrap(document.page(at: 0))
            store.setScaleMode(.manual, scaleFactor: 1, for: sessionID)
            reader.pdfView.layoutDocumentView()
            window.window?.contentView?.layoutSubtreeIfNeeded()
        }

        func selection(_ text: String) throws -> PDFSelection {
            try XCTUnwrap(document.findString(text, withOptions: []).first)
        }

        func menu(over selection: PDFSelection) throws -> NSMenu {
            let bounds = selection.bounds(for: page)
            return try menu(at: CGPoint(x: bounds.midX, y: bounds.midY))
        }

        func menu(at point: CGPoint) throws -> NSMenu {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
                location: reader.pdfView.convert(reader.pdfView.convert(point, from: page), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: try XCTUnwrap(window.window).windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            return try XCTUnwrap(reader.pdfView.menu(for: event))
        }
    }
}
