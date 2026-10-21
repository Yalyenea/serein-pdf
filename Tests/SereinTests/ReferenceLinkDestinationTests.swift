import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class ReferenceLinkDestinationTests: XCTestCase {
    func testPageOnlyCitationsResolveEitherColumnAndGroupedNumbers() throws {
        let document = try makeDocument()
        for number in [1, 2, 3, 4, 5, 6] {
            let link = try makeLink(number: number, document: document)
            let destination = try XCTUnwrap(ReferenceLinkDestination.resolve(link))
            XCTAssertTrue(destination.page === document.page(at: 1))
            XCTAssertEqual(destination.point.x, number <= 3 ? 50 : 330, accuracy: 1)
            XCTAssertEqual(destination.point.y, 700 - CGFloat((number - 1) % 3) * 40 + 12, accuracy: 4)
        }
    }

    func testExplicitDestinationIsPreserved() throws {
        let document = try makeDocument()
        let link = try makeLink(number: 1, document: document)
        let destination = PDFDestination(page: document.page(at: 1)!, at: CGPoint(x: 120, y: 480))
        link.action = PDFActionGoTo(destination: destination)
        XCTAssertTrue(ReferenceLinkDestination.resolve(link) === destination)
    }

    func testUnbracketedNumberAndAmbiguousEntriesKeepPageOnlyDestination() throws {
        for (label, duplicate) in [("Section 1", false), ("[1]", true)] {
            let document = try makeDocument(sourceText: label, duplicate: duplicate)
            let link = try makeLink(number: 1, document: document)
            let original = try XCTUnwrap((link.action as? PDFActionGoTo)?.destination)
            XCTAssertTrue(ReferenceLinkDestination.resolve(link) === original)
        }
    }

    func testPageOnlyNavigationUsesCropBoxEdge() throws {
        let page = try XCTUnwrap(try makeDocument().page(at: 1))
        page.setBounds(CGRect(x: 20, y: 30, width: 560, height: 740), for: .cropBox)
        let destination = PDFDestination(page: page, at: CGPoint(
            x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue
        ))
        XCTAssertEqual(ReferenceLinkDestination.navigationPoint(for: destination), CGPoint(x: 20, y: 770))
        let partial = PDFDestination(page: page, at: CGPoint(x: 330, y: kPDFDestinationUnspecifiedValue))
        XCTAssertEqual(ReferenceLinkDestination.navigationPoint(for: partial), CGPoint(x: 330, y: 770))
    }

    // Opt-in reproduction against the user's original PDF, without adding it to the repository.
    func testPublisherPDFReferencesPreviewOneColumnAndCommandClickNavigates() throws {
        guard let path = ProcessInfo.processInfo.environment["SEREIN_REFERENCE_TEST_PDF"] else {
            throw XCTSkip("Set SEREIN_REFERENCE_TEST_PDF to validate the publisher PDF")
        }
        _ = NSApplication.shared
        let document = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path)))
        var count = 0
        for index in 0..<document.pageCount {
            let source = try XCTUnwrap(document.page(at: index))
            for link in source.annotations where link.type == "Link" {
                guard let original = (link.action as? PDFActionGoTo)?.destination ?? link.destination,
                      let target = original.page, document.index(for: target) >= 15 else { continue }
                let destination = try XCTUnwrap(ReferenceLinkDestination.resolve(link))
                XCTAssertNotEqual(destination.point.x, kPDFDestinationUnspecifiedValue)
                XCTAssertNotEqual(destination.point.y, kPDFDestinationUnspecifiedValue)
                let preview = try XCTUnwrap(ReferencePreviewViewController(destination: destination, document: document))
                let window = makeWindow(controller: preview)
                preview.positionReference()
                let pdfView = try XCTUnwrap(preview.view.subviews.compactMap { $0 as? PDFView }.first)
                pdfView.layoutDocumentView()
                XCTAssertGreaterThan(pdfView.scaleFactor, pdfView.bounds.width / target.bounds(for: .cropBox).width * 1.7)
                let copy = try XCTUnwrap(pdfView.currentPage)
                let visibleTarget = pdfView.convert(destination.point, from: copy)
                XCTAssertTrue(pdfView.visibleRect.insetBy(dx: -1, dy: -1).contains(visibleTarget),
                              "Source page \(index + 1), \(destination.point) became \(visibleTarget), viewport \(pdfView.visibleRect)")
                window.close()
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 40)
        print("Validated \(count) publisher citation previews")

        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: URL(fileURLWithPath: path))
        let reader = ReaderViewController(documentStore: store, windowID: store.defaultWindowID)
        reader.targetSessionID = session.id
        let window = makeWindow(controller: reader)
        defer { window.close() }
        let view = reader.pdfView
        let readerDocument = try XCTUnwrap(view.document)
        let source = try XCTUnwrap(readerDocument.page(at: 0))
        let link = try XCTUnwrap(source.annotations.first)
        view.displayMode = .singlePageContinuous
        view.scaleFactor = 0.8
        view.go(to: source)
        view.layoutDocumentView()
        let point = view.convert(view.convert(CGPoint(x: link.bounds.midX, y: link.bounds.midY), from: source), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
        view.layoutDocumentView()
        XCTAssertEqual(readerDocument.index(for: try XCTUnwrap(view.currentPage)), 15)
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition.pageIndex, 15)
        reader.navigateBack()
        XCTAssertEqual(readerDocument.index(for: try XCTUnwrap(view.currentPage)), 0)

        let pageOnly = PDFDestination(page: readerDocument.page(at: 15)!, at: CGPoint(
            x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue
        ))
        XCTAssertTrue(view.onInternalLinkNavigationRequested?(pageOnly) == true)
        XCTAssertEqual(readerDocument.index(for: try XCTUnwrap(view.currentPage)), 15)
        XCTAssertEqual(store.session(for: session.id)?.lastReadPosition.point, CGPoint(x: 0, y: 793.701))
    }

    private func makeWindow(controller: NSViewController) -> NSWindow {
        let size = NSSize(width: 580, height: 360)
        controller.preferredContentSize = size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        return window
    }

    private func makeLink(number: Int, document: PDFDocument) throws -> PDFAnnotation {
        let source = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(source.string) as NSString
        let range = text.range(of: String(number))
        let selection = try XCTUnwrap(source.selection(for: range))
        let link = PDFAnnotation(bounds: selection.bounds(for: source), forType: .link, withProperties: nil)
        link.action = PDFActionGoTo(destination: PDFDestination(page: document.page(at: 1)!, at: CGPoint(
            x: kPDFDestinationUnspecifiedValue, y: kPDFDestinationUnspecifiedValue
        )))
        source.addAnnotation(link)
        return link
    }

    private func makeDocument(sourceText: String = "See [1,2,3-4,5,6].", duplicate: Bool = false) throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &box, nil))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
        for page in 0..<2 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            if page == 0 {
                NSString(string: sourceText)
                    .draw(at: CGPoint(x: 50, y: 700), withAttributes: attributes)
            } else {
                for number in 1...6 {
                    NSString(string: "\(duplicate && number == 4 ? 1 : number). Author, Reference title.").draw(
                        at: CGPoint(x: number <= 3 ? 50 : 330, y: 700 - CGFloat((number - 1) % 3) * 40), withAttributes: attributes)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }
}
