import AppKit
import PDFKit

enum PDFPageImageService {
    static let renderScale: CGFloat = 2

    static func image(from page: PDFPage) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let size = NSSize(
            width: bounds.width * renderScale,
            height: bounds.height * renderScale
        )
        return page.thumbnail(of: size, for: .mediaBox)
    }

    /// Draw the PDF, including annotations, so capture quality is independent of reader zoom and theme.
    static func image(from page: PDFPage, in rect: CGRect) -> NSImage? {
        guard page.document?.allowsCopying != false, let pageRef = page.pageRef,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return nil }
        let bounds = rect.standardized.intersection(pageRef.getBoxRect(.cropBox))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let displayBounds = bounds.applying(page.transform(for: .cropBox))
        let scale = min(renderScale, 8192 / max(displayBounds.width, displayBounds.height),
                        sqrt(16_000_000 / (displayBounds.width * displayBounds.height)))
        let width = max(1, Int(ceil(displayBounds.width * scale)))
        let height = max(1, Int(ceil(displayBounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -displayBounds.minX, y: -displayBounds.minY)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    @discardableResult
    static func copyToPasteboard(_ image: NSImage, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
