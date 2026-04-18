import AppKit
import PDFKit

enum HighlightService {
    static let defaultColor: NSColor = HighlightColor.default.nsColor

    static func selectionContainsText(_ selection: PDFSelection?) -> Bool {
        guard let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        return text.isEmpty == false
    }

    @discardableResult
    static func applyHighlight(to selection: PDFSelection, color: NSColor = defaultColor) -> Int {
        var appliedAnnotations = 0
        let groupID = UUID().uuidString

        for lineSelection in explodedSelections(selection) {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.isNull == false, bounds.isEmpty == false else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.userName = groupID
                page.addAnnotation(annotation)
                appliedAnnotations += 1
            }
        }

        return appliedAnnotations
    }

    static func highlightAnnotation(at pointOnPage: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { annotation in
            annotation.type == "Highlight" && annotation.bounds.contains(pointOnPage)
        }
    }

    /// Removes the given annotation plus any siblings sharing the same `userName`
    /// group id across the whole document, so a multi-line highlight disappears as one block.
    /// Returns total number of annotations removed.
    @discardableResult
    static func removeHighlightGroup(containing annotation: PDFAnnotation, in document: PDFDocument) -> Int {
        let groupID = annotation.userName
        guard let groupID, groupID.isEmpty == false else {
            annotation.page?.removeAnnotation(annotation)
            return 1
        }

        var removed = 0
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let victims = page.annotations.filter { $0.type == "Highlight" && $0.userName == groupID }
            for victim in victims {
                page.removeAnnotation(victim)
                removed += 1
            }
        }
        return removed
    }

    private static func explodedSelections(_ selection: PDFSelection) -> [PDFSelection] {
        let lineSelections = selection.selectionsByLine()
        return lineSelections.isEmpty ? [selection] : lineSelections
    }
}
