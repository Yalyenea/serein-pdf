import AppKit
import PDFKit
import XCTest
@testable import Serein

final class PDFPageImageServiceTests: XCTestCase {
    func testImageUsesTwiceTheMediaBoxSize() throws {
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1)
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let image = PDFPageImageService.image(from: page)

        XCTAssertEqual(image.size.width, bounds.width * PDFPageImageService.renderScale, accuracy: 0.5)
        XCTAssertEqual(image.size.height, bounds.height * PDFPageImageService.renderScale, accuracy: 0.5)
    }

    func testCopyWritesImageToPasteboard() throws {
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1)
        let page = try XCTUnwrap(document.page(at: 0))
        let image = PDFPageImageService.image(from: page)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        XCTAssertTrue(PDFPageImageService.copyToPasteboard(image, pasteboard: pasteboard))
        let copied = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) ?? []
        XCTAssertEqual(copied.count, 1)
        let copiedImage = try XCTUnwrap(copied.first as? NSImage)
        XCTAssertEqual(copiedImage.size.width, image.size.width, accuracy: 0.5)
        XCTAssertEqual(copiedImage.size.height, image.size.height, accuracy: 0.5)
    }
}
