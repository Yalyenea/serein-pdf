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
