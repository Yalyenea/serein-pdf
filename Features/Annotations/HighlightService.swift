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

        for lineSelection in explodedSelections(selection) {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.isNull == false, bounds.isEmpty == false else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
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

    private static func explodedSelections(_ selection: PDFSelection) -> [PDFSelection] {
        let lineSelections = selection.selectionsByLine()
        return lineSelections.isEmpty ? [selection] : lineSelections
    }
}
