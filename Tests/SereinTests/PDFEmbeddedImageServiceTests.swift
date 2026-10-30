import AppKit
import PDFKit
import XCTest
@testable import Serein

final class PDFEmbeddedImageServiceTests: XCTestCase {
    func testTransformsAndSavedStateKeepEachPaintedImageSeparate() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 1 0 0 1 10 20 cm 100 0 0 60 0 0 cm /Red Do Q q 40 0 0 30 200 100 cm /Red Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page)?.bounds,
                       CGRect(x: 10, y: 20, width: 100, height: 60))
        XCTAssertEqual(PDFEmbeddedImageService.region(at: CGPoint(x: 220, y: 110), on: page)?.bounds,
                       CGRect(x: 200, y: 100, width: 40, height: 30))
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 150, y: 50), on: page))
    }

    func testEvenOddClipRejectsHoleAndRestoresAfterQ() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 10 20 100 100 re 40 50 20 20 re W* n 100 0 0 100 10 20 cm /Red Do Q " +
            "q 20 0 0 20 200 200 cm /Blue Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertNotNil(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page))
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 50, y: 60), on: page))
        XCTAssertNotNil(PDFEmbeddedImageService.region(at: CGPoint(x: 210, y: 210), on: page))
    }

    func testClipAppliesAtPaintingPathEndAndUsesConstructionTransform() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 10 20 30 40 re W 2 0 0 2 0 0 cm S 100 0 0 100 0 0 cm /Red Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page)?.bounds,
                       CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 60, y: 90), on: page))
    }

    func testShearedImageUsesItsQuadrilateralForHitTesting() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "100 0 100 100 20 20 cm /Red Do")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertNotNil(PDFEmbeddedImageService.region(at: CGPoint(x: 120, y: 70), on: page))
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 25, y: 115), on: page))
    }

    func testNestedFormsUseLocalResourcesMatrixAndBBoxOnEveryInvocation() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 100 0 0 80 10 20 cm /Form Do Q q 100 0 0 80 210 20 cm /Form Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        let region = try XCTUnwrap(PDFEmbeddedImageService.region(at: CGPoint(x: 30, y: 40), on: page))
        XCTAssertEqual(region.bounds, CGRect(x: 10, y: 20, width: 100, height: 80))
        let image = try XCTUnwrap(region.image())
        let color = try color(in: image, x: 20, y: 20)
        XCTAssertGreaterThan(color.blueComponent, 0.95)
        XCTAssertLessThan(color.redComponent, 0.05)
        XCTAssertNotNil(PDFEmbeddedImageService.region(at: CGPoint(x: 230, y: 40), on: page))
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 130, y: 40), on: page))
    }

    func testInlineImageAndFollowingXObjectAreBothLocated() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 40 0 0 30 10 20 cm BI /W 1 /H 1 /CS /RGB /BPC 8 ID \u{ff}\u{00}\u{00} EI Q " +
            "q 40 0 0 30 100 20 cm /Blue Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page)?.bounds,
                       CGRect(x: 10, y: 20, width: 40, height: 30))
        XCTAssertNotNil(PDFEmbeddedImageService.region(at: CGPoint(x: 110, y: 30), on: page))
    }

    func testLastPaintedImageWinsAndRenderedRegionKeepsColor() throws {
        let document = try EmbeddedImagePDFFixture.document(content:
            "q 100 0 0 100 10 20 cm /Red Do Q q 30 0 0 40 40 50 cm /Blue Do Q")
        let page = try XCTUnwrap(document.page(at: 0))
        let region = try XCTUnwrap(PDFEmbeddedImageService.region(at: CGPoint(x: 50, y: 60), on: page))
        XCTAssertEqual(region.bounds, CGRect(x: 40, y: 50, width: 30, height: 40))
        let image = try XCTUnwrap(region.image())
        XCTAssertEqual(image.size, NSSize(width: 60, height: 80))
        XCTAssertGreaterThan(try color(in: image, x: 30, y: 40).blueComponent, 0.95)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        XCTAssertTrue(PDFPageImageService.copyToPasteboard(image, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.readObjects(forClasses: [NSImage.self])?.count, 1)
    }

    func testPageRotationsAndOffsetCropBoxKeepTheSameHitCoordinates() throws {
        for rotation in [0, 90, 180, 270] {
            let document = try EmbeddedImagePDFFixture.document(content: "80 0 0 40 50 70 cm /Red Do",
                rotation: rotation, cropBox: "[60 80 300 400]")
            let page = try XCTUnwrap(document.page(at: 0))
            let region = try XCTUnwrap(PDFEmbeddedImageService.region(at: CGPoint(x: 80, y: 90), on: page))
            XCTAssertEqual(region.bounds, CGRect(x: 60, y: 80, width: 70, height: 30))
            XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 55, y: 75), on: page))
            let image = try XCTUnwrap(region.image())
            let expected = rotation % 180 == 0 ? NSSize(width: 140, height: 60) : NSSize(width: 60, height: 140)
            XCTAssertEqual(image.size.width, expected.width, accuracy: 1)
            XCTAssertEqual(image.size.height, expected.height, accuracy: 1)
            XCTAssertGreaterThan(try color(in: image, x: 20, y: 20).redComponent, 0.95)
        }
    }

    func testSoftMaskPreservesTransparentPixels() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "40 0 0 40 10 20 cm /Red Do", softMask: true)
        let page = try XCTUnwrap(document.page(at: 0))
        let image = try XCTUnwrap(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page)?.image())
        XCTAssertGreaterThan(try color(in: image, x: 10, y: 10).alphaComponent, 0.95)
        XCTAssertLessThan(try color(in: image, x: 70, y: 10).alphaComponent, 0.05)
    }

    func testPageRotationTurnsTheCopiedPixelsClockwise() throws {
        for (rotation, expected) in [(0, NSColor.red), (90, .blue), (180, .yellow), (270, .green)] {
            let document = try EmbeddedImagePDFFixture.document(content: "40 0 0 40 10 20 cm /Red Do",
                rotation: rotation, redPixels: "FF000000FF000000FFFFFF00>")
            let page = try XCTUnwrap(document.page(at: 0))
            let image = try XCTUnwrap(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: page)?.image())
            let actual = try color(in: image, x: 10, y: 10)
            let expected = try XCTUnwrap(expected.usingColorSpace(.sRGB))
            // PDF DeviceRGB is color managed; identify the quadrant without requiring exact sRGB values.
            XCTAssertEqual(actual.redComponent > 0.5, expected.redComponent > 0.5, "Rotation \(rotation)")
            XCTAssertEqual(actual.greenComponent > 0.5, expected.greenComponent > 0.5, "Rotation \(rotation)")
            XCTAssertEqual(actual.blueComponent > 0.5, expected.blueComponent > 0.5, "Rotation \(rotation)")
        }
    }

    func testCopyRestrictedPDFDoesNotOfferAnImageRegion() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "40 0 0 40 10 20 cm /Red Do")
        let data = try XCTUnwrap(document.dataRepresentation(options: [
            PDFDocumentWriteOption.ownerPasswordOption: "owner-only",
            PDFDocumentWriteOption.userPasswordOption: "",
            PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: 0),
        ]))
        let restricted = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertFalse(restricted.allowsCopying)
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: try XCTUnwrap(restricted.page(at: 0))))
    }

    func testVectorOnlyContentHasNoImageRegion() throws {
        let document = try EmbeddedImagePDFFixture.document(content: "1 0 0 rg 10 20 100 100 re f")
        XCTAssertNil(PDFEmbeddedImageService.region(at: CGPoint(x: 20, y: 30), on: try XCTUnwrap(document.page(at: 0))))
    }

    private func color(in image: NSImage, x: Int, y: Int) throws -> NSColor {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
}

/// Explicit PDF objects exercise scanner geometry independently of PDFKit's PDF writer.
enum EmbeddedImagePDFFixture {
    static func document(content: String, rotation: Int = 0, cropBox: String = "[0 0 400 500]",
                         softMask: Bool = false, redPixels: String = "FF0000FF0000FF0000FF0000>") throws -> PDFDocument {
        func stream(_ dictionary: String, _ content: String) -> String {
            "<< \(dictionary) /Length \(content.data(using: .isoLatin1)!.count) >>\nstream\n\(content)\nendstream"
        }
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /CropBox \(cropBox) /Rotate \(rotation) " +
                "/Resources << /XObject << /Red 5 0 R /Blue 6 0 R /Form 7 0 R >> >> /Contents 4 0 R >>",
            stream("", content),
            stream("/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 " +
                "/Filter /ASCIIHexDecode \(softMask ? "/SMask 9 0 R" : "")", redPixels),
            stream("/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode", "0000FF>"),
            stream("/Type /XObject /Subtype /Form /BBox [0 0 1 1] /Matrix [2 0 0 2 0 0] " +
                "/Resources << /XObject << /Inner 8 0 R >> >>", "/Inner Do"),
            stream("/Type /XObject /Subtype /Form /BBox [0 0 0.5 0.5] " +
                "/Resources << /XObject << /Red 6 0 R >> >>", "/Red Do"),
            stream("/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode", "FF00FFFF>"),
        ]
        var data = Data("%PDF-1.7\n".utf8)
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append("\(index + 1) 0 obj\n\(object)\nendobj\n".data(using: .isoLatin1)!)
        }
        let xref = data.count
        data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return try XCTUnwrap(PDFDocument(data: data))
    }
}
