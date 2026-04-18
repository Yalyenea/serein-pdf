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

    @discardableResult
    static func removeHighlights(in selection: PDFSelection) -> Int {
        var removedAnnotations = 0

        for lineSelection in explodedSelections(selection) {
            for page in lineSelection.pages {
                let selectionBounds = lineSelection.bounds(for: page)
                guard selectionBounds.isNull == false, selectionBounds.isEmpty == false else { continue }

                let highlights = page.annotations.filter { annotation in
                    annotation.type == "Highlight" &&
                    shouldRemoveHighlight(annotationBounds: annotation.bounds, selectionBounds: selectionBounds)
                }

                for annotation in highlights {
                    page.removeAnnotation(annotation)
                    removedAnnotations += 1
                }
            }
        }

        return removedAnnotations
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

    private static func shouldRemoveHighlight(annotationBounds: NSRect, selectionBounds: NSRect) -> Bool {
        guard annotationBounds.intersects(selectionBounds) else { return false }

        let intersection = annotationBounds.intersection(selectionBounds)
        let overlapArea = area(of: intersection)
        guard overlapArea > 0 else { return false }

        let annotationArea = area(of: annotationBounds)
        let selectionArea = area(of: selectionBounds)
        if annotationArea > 0, overlapArea / annotationArea >= 0.6 { return true }
        if selectionArea > 0, overlapArea / selectionArea >= 0.6 { return true }

        return annotationBounds.contains(center(of: selectionBounds)) ||
            selectionBounds.contains(center(of: annotationBounds))
    }

    private static func area(of rect: NSRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }

    private static func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }
}
