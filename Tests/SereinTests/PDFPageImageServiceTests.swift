import AppKit
import PDFKit
import XCTest
@testable import Serein

final class PDFPageImageServiceTests: XCTestCase {
    func testAreaCopyRendersVectorsWithRotationAndOffsetCropBox() throws {
        for rotation in [0, 90, 180, 270] {
            let document = try EmbeddedImagePDFFixture.document(content: "1 0 0 rg 50 60 70 80 re f",
                rotation: rotation, cropBox: "[20 30 380 480]")
            let page = try XCTUnwrap(document.page(at: 0))
            let image = try XCTUnwrap(PDFPageImageService.image(from: page, in: CGRect(x: 50, y: 60, width: 70, height: 80)))
            XCTAssertEqual(image.size, rotation % 180 == 0 ? NSSize(width: 140, height: 160) : NSSize(width: 160, height: 140))
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let color = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(color.redComponent, 0.95)
            XCTAssertLessThan(color.blueComponent, 0.1)
        }
    }

    func testAreaCopyIncludesAnnotationsOnWhitePaper() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "")
        let page = try XCTUnwrap(document.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 50, y: 60, width: 70, height: 80), forType: .square, withProperties: nil)
        annotation.interiorColor = .blue
        annotation.color = .blue
        page.addAnnotation(annotation)
        let image = try XCTUnwrap(PDFPageImageService.image(from: page, in: CGRect(x: 30, y: 40, width: 110, height: 120)))
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let blue = try XCTUnwrap(bitmap.colorAt(x: 100, y: 100)?.usingColorSpace(.sRGB))
        let white = try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(blue.blueComponent, 0.95)
        XCTAssertLessThan(blue.redComponent, 0.1)
        XCTAssertGreaterThan(white.redComponent, 0.95)
        XCTAssertGreaterThan(white.greenComponent, 0.95)
        XCTAssertEqual(page.annotations.count, 1)
    }

    func testAreaCopyClampsToCropBoxAndRejectsEmptyArea() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "")
        let page = try XCTUnwrap(document.page(at: 0))
        let image = try XCTUnwrap(PDFPageImageService.image(from: page, in: CGRect(x: -20, y: -20, width: 100, height: 100)))
        XCTAssertEqual(image.size, NSSize(width: 160, height: 160))
        XCTAssertNil(PDFPageImageService.image(from: page, in: .zero))
        XCTAssertNil(PDFPageImageService.image(from: page, in: CGRect(x: 450, y: 550, width: 20, height: 20)))
    }

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

    func testPNGDataKeepsRenderedPixelDimensions() throws {
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1)
        let page = try XCTUnwrap(document.page(at: 0))
        let image = PDFPageImageService.image(from: page)
        let data = try XCTUnwrap(PDFPageImageService.pngData(from: image))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(bitmap.pixelsWide, Int(image.size.width))
        XCTAssertEqual(bitmap.pixelsHigh, Int(image.size.height))
    }
}
