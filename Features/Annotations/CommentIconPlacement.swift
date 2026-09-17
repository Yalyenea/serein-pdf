import AppKit
import PDFKit

/// Reader-local page-space layout shared by drawing, hit testing and comment cards.
final class CommentIconPlacement {
    static let size = NSSize(width: 9, height: 9)
    static let gap: CGFloat = 3

    private struct Owner: Equatable {
        let id: ObjectIdentifier
        let bounds: NSRect
    }
    private struct Entry {
        let page: PDFPage
        let bounds: NSRect
        let rotation: Int
        let owners: [Owner]
        let frames: [(annotation: PDFAnnotation, frame: NSRect)]
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func retainPages(_ pages: [PDFPage]) {
        let ids = Set(pages.map(ObjectIdentifier.init))
        entries = entries.filter { ids.contains($0.key) }
    }

    func frames(on page: PDFPage) -> [(annotation: PDFAnnotation, frame: NSRect)] {
        let annotations = page.annotations.filter(Self.isCommentOwner)
        let owners = annotations.map { Owner(id: ObjectIdentifier($0), bounds: $0.bounds) }
        let bounds = Self.pageBounds(page)
        let key = ObjectIdentifier(page)
        if let entry = entries[key], entry.bounds == bounds,
           entry.rotation == page.rotation, entry.owners == owners {
            return entry.frames
        }
        var occupied: [NSRect] = []
        let frames = annotations.sorted(by: HighlightService.annotationSortOrder).map { annotation in
            let frame = Self.place(annotation.bounds, on: page, within: bounds, occupied: occupied)
            occupied.append(frame)
            return (annotation: annotation, frame: frame)
        }
        entries[key] = Entry(page: page, bounds: bounds, rotation: page.rotation, owners: owners, frames: frames)
        return frames
    }

    func bounds(for annotation: PDFAnnotation) -> NSRect {
        if let page = annotation.page {
            return frames(on: page).first(where: { $0.annotation === annotation })?.frame
                ?? Self.place(annotation.bounds, on: page, within: Self.pageBounds(page), occupied: [])
        }
        // An empty comment editor still needs an anchor beside its annotation.
        return NSRect(x: annotation.bounds.maxX + Self.gap,
                      y: annotation.bounds.midY - Self.size.height / 2,
                      width: Self.size.width, height: Self.size.height)
    }

    func annotation(at point: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        frames(on: page).last { $0.frame.contains(point) }?.annotation
    }

    static func isCommentOwner(_ annotation: PDFAnnotation) -> Bool {
        HighlightService.isMarkupAnnotation(annotation)
            && annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func pageBounds(_ page: PDFPage) -> NSRect {
        let crop = page.bounds(for: .cropBox)
        return (crop.isEmpty || crop.isNull ? page.bounds(for: .mediaBox) : crop).insetBy(dx: 4, dy: 4)
    }

    private static func place(_ highlight: NSRect, on page: PDFPage, within bounds: NSRect, occupied: [NSRect]) -> NSRect {
        let y = highlight.midY - size.height / 2
        func rect(_ x: CGFloat, _ y: CGFloat) -> NSRect {
            NSRect(x: x, y: y, width: size.width, height: size.height)
        }
        func isClear(_ frame: NSRect) -> Bool {
            guard bounds.contains(frame), !frame.intersects(highlight),
                  !occupied.contains(where: { $0.intersects(frame) }) else { return false }
            return (page.selection(for: frame)?.string.map(PDFTextSanitizer.sanitize) ?? "").isEmpty
        }
        for direction: CGFloat in [1, -1] {
            let start = direction > 0 ? highlight.maxX + gap : highlight.minX - gap - size.width
            for offset in stride(from: CGFloat.zero, through: 96, by: 3) {
                let candidate = rect(start + direction * offset, y)
                if isClear(candidate) { return candidate }
            }
        }
        let clampedY = min(max(y, bounds.minY), bounds.maxY - size.height)
        for candidate in [
            rect(highlight.maxX - size.width, highlight.maxY + gap),
            rect(highlight.maxX - size.width, highlight.minY - gap - size.height),
            rect(bounds.maxX - size.width, clampedY),
        ] where isClear(candidate) { return candidate }
        return rect(min(max(highlight.maxX + gap, bounds.minX), bounds.maxX - size.width), clampedY)
    }
}
