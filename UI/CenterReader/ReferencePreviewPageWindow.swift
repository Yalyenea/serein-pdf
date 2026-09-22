import PDFKit

/// A small, contiguous collection of page copies. Source pages and annotations
/// never enter the preview document, even when a link points outside this window.
@MainActor
final class ReferencePreviewPageWindow {
    static let maximumPageCount = 3

    let sourceDocument: PDFDocument
    let document = PDFDocument()
    private(set) var sourceIndices: [Int]

    init?(document source: PDFDocument, pageIndex: Int) {
        guard let copy = Self.copyPage(at: pageIndex, in: source) else { return nil }
        sourceDocument = source
        sourceIndices = [pageIndex]
        document.insert(copy, at: 0)
    }

    func sourceIndex(for page: PDFPage) -> Int? {
        let index = document.index(for: page)
        guard sourceIndices.indices.contains(index) else { return nil }
        return sourceIndices[index]
    }

    func page(atSourceIndex index: Int) -> PDFPage? {
        guard let localIndex = sourceIndices.firstIndex(of: index) else { return nil }
        return document.page(at: localIndex)
    }

    @discardableResult
    func extend(forward: Bool, keeping anchor: Int) -> Bool {
        guard let first = sourceIndices.first, let last = sourceIndices.last,
              sourceIndices.contains(anchor) else { return false }
        let next = forward ? last + 1 : first - 1
        // A very tall or heavily zoomed-out viewport must not lose its anchor.
        if sourceIndices.count == Self.maximumPageCount,
           (forward ? first : last) == anchor { return false }
        guard let copy = Self.copyPage(at: next, in: sourceDocument) else { return false }
        if sourceIndices.count == Self.maximumPageCount {
            let removed = forward ? 0 : sourceIndices.count - 1
            document.removePage(at: removed)
            sourceIndices.remove(at: removed)
        }
        let insertion = forward ? sourceIndices.count : 0
        sourceIndices.insert(next, at: insertion)
        document.insert(copy, at: insertion)
        return true
    }

    private static func copyPage(at index: Int, in document: PDFDocument) -> PDFPage? {
        guard (0..<document.pageCount).contains(index), let page = document.page(at: index),
              let copy = page.copy() as? PDFPage else { return nil }
        for annotation in copy.annotations {
            if annotation.type == "Widget" {
                annotation.isReadOnly = true
            } else if HighlightService.isMarkupAnnotation(annotation) {
                annotation.contents = nil
                if let popup = annotation.popup {
                    copy.removeAnnotation(popup)
                    annotation.popup = nil
                }
            }
        }
        return copy
    }
}
