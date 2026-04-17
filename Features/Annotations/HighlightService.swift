import AppKit
import PDFKit

enum HighlightService {
    static let defaultColor = NSColor(
        calibratedRed: 0.97,
        green: 0.79,
        blue: 0.86,
        alpha: 0.85
    )

    static func selectionContainsText(_ selection: PDFSelection?) -> Bool {
        guard let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        return text.isEmpty == false
    }

    static func applyHighlight(to selection: PDFSelection) -> Int {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var appliedAnnotations = 0

        for lineSelection in selections {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.isNull == false, bounds.isEmpty == false else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = defaultColor
                page.addAnnotation(annotation)
                appliedAnnotations += 1
            }
        }

        return appliedAnnotations
    }
}
