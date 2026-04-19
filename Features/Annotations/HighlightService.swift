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
    static func applyHighlight(
        to selection: PDFSelection,
        color: NSColor = defaultColor
    ) -> [HighlightAnnotationRecord] {
        var records: [HighlightAnnotationRecord] = []
        let groupID = UUID().uuidString

        for lineSelection in explodedSelections(selection) {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.isNull == false, bounds.isEmpty == false else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.userName = groupID
                page.addAnnotation(annotation)
                guard let document = page.document else { continue }
                records.append(
                    HighlightAnnotationRecord(
                        pageIndex: document.index(for: page),
                        annotation: annotation
                    )
                )
            }
        }

        return records
    }

    static func highlightAnnotation(at pointOnPage: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { annotation in
            annotation.type == "Highlight" && annotation.bounds.contains(pointOnPage)
        }
    }

    /// Removes the given annotation plus any siblings sharing the same `userName`
    /// group id across the whole document, so a multi-line highlight disappears as one block.
    /// Returns the removed annotations with their original page indexes, in page order.
    @discardableResult
    static func removeHighlightGroup(
        containing annotation: PDFAnnotation,
        in document: PDFDocument
    ) -> [HighlightAnnotationRecord] {
        let groupID = annotation.userName
        guard let groupID, groupID.isEmpty == false else {
            let pageIndex = annotation.page.map { document.index(for: $0) } ?? 0
            annotation.page?.removeAnnotation(annotation)
            return [HighlightAnnotationRecord(pageIndex: pageIndex, annotation: annotation)]
        }

        var records: [HighlightAnnotationRecord] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let victims = page.annotations.filter { $0.type == "Highlight" && $0.userName == groupID }
            for victim in victims {
                page.removeAnnotation(victim)
                records.append(HighlightAnnotationRecord(pageIndex: pageIndex, annotation: victim))
            }
        }
        return records
    }

    /// Re-adds previously removed highlight annotations to their original pages.
    static func reinsertHighlights(_ records: [HighlightAnnotationRecord], in document: PDFDocument) {
        for record in records {
            guard let page = document.page(at: record.pageIndex) else { continue }
            page.addAnnotation(record.annotation)
        }
    }

    /// Removes the given highlight annotations from their original pages.
    static func removeHighlights(_ records: [HighlightAnnotationRecord], in document: PDFDocument) {
        for record in records {
            guard let page = document.page(at: record.pageIndex) else { continue }
            page.removeAnnotation(record.annotation)
        }
    }

    private static func explodedSelections(_ selection: PDFSelection) -> [PDFSelection] {
        let lineSelections = selection.selectionsByLine()
        return lineSelections.isEmpty ? [selection] : lineSelections
    }
}
