import AppKit
import PDFKit

enum HighlightService {
    static let defaultColor: NSColor = HighlightColor.default.nsColor

    static func selectionContainsText(_ selection: PDFSelection?) -> Bool {
        guard let text = selection?.string.map(PDFTextSanitizer.sanitize) else {
            return false
        }

        return text.isEmpty == false
    }

    @discardableResult
    static func applyHighlight(
        to selection: PDFSelection,
        color: NSColor = defaultColor,
        createdAt: Date = Date()
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
                annotation.modificationDate = createdAt
                annotation.contents = nil
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

    static func buildHighlightGroups(in document: PDFDocument) -> [DocumentHighlightGroup] {
        var groupedRecords: [String: [HighlightAnnotationRecord]] = [:]
        var orderedGroupIDs: [String] = []
        var ocrCache: [ObjectIdentifier: [HighlightOCRService.RecognizedLine]] = [:]

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let annotations = page.annotations
                .filter { isHighlight($0) }
                .sorted(by: annotationSortOrder)

            for annotation in annotations {
                let groupID = resolvedGroupID(for: annotation, pageIndex: pageIndex)
                if groupedRecords[groupID] == nil {
                    groupedRecords[groupID] = []
                    orderedGroupIDs.append(groupID)
                }
                groupedRecords[groupID]?.append(
                    HighlightAnnotationRecord(pageIndex: pageIndex, annotation: annotation)
                )
            }
        }

        return orderedGroupIDs.compactMap { groupID in
            highlightGroup(
                groupID: groupID,
                records: groupedRecords[groupID] ?? [],
                ocrCache: &ocrCache
            )
        }
    }

    static func buildHighlightGroups(from records: [HighlightAnnotationRecord]) -> [DocumentHighlightGroup] {
        var groupedRecords: [String: [HighlightAnnotationRecord]] = [:]
        var orderedGroupIDs: [String] = []
        var ocrCache: [ObjectIdentifier: [HighlightOCRService.RecognizedLine]] = [:]

        for record in records {
            let groupID = resolvedGroupID(for: record.annotation, pageIndex: record.pageIndex)
            if groupedRecords[groupID] == nil {
                groupedRecords[groupID] = []
                orderedGroupIDs.append(groupID)
            }
            groupedRecords[groupID]?.append(record)
        }

        return orderedGroupIDs.compactMap { groupID in
            highlightGroup(
                groupID: groupID,
                records: groupedRecords[groupID] ?? [],
                ocrCache: &ocrCache
            )
        }
    }

    static func highlightAnnotation(at pointOnPage: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        // PDFKit draws later annotations on top; prefer the topmost hit.
        page.annotations.last { annotation in
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

    @discardableResult
    static func updateComment(_ comment: String, for records: [HighlightAnnotationRecord]) -> Bool {
        let normalizedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : comment
        var didChange = false

        for record in records where record.annotation.contents != normalizedComment {
            record.annotation.contents = normalizedComment
            didChange = true
        }

        return didChange
    }

    static func groupIDs(for records: [HighlightAnnotationRecord]) -> Set<String> {
        Set(records.map { resolvedGroupID(for: $0.annotation, pageIndex: $0.pageIndex) })
    }

    private static func explodedSelections(_ selection: PDFSelection) -> [PDFSelection] {
        let lineSelections = selection.selectionsByLine()
        return lineSelections.isEmpty ? [selection] : lineSelections
    }

    private static func isHighlight(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == "Highlight"
    }

    private static func resolvedGroupID(for annotation: PDFAnnotation, pageIndex: Int) -> String {
        if let groupID = annotation.userName?.trimmingCharacters(in: .whitespacesAndNewlines),
           groupID.isEmpty == false {
            return groupID
        }

        let bounds = annotation.bounds.integral
        return "page-\(pageIndex)-\(Int(bounds.minX))-\(Int(bounds.minY))-\(Int(bounds.width))-\(Int(bounds.height))"
    }

    private static func annotationSortOrder(_ lhs: PDFAnnotation, _ rhs: PDFAnnotation) -> Bool {
        let lhsBounds = lhs.bounds
        let rhsBounds = rhs.bounds
        if abs(lhsBounds.maxY - rhsBounds.maxY) > 0.5 {
            return lhsBounds.maxY > rhsBounds.maxY
        }
        if abs(lhsBounds.minX - rhsBounds.minX) > 0.5 {
            return lhsBounds.minX < rhsBounds.minX
        }
        return lhsBounds.width < rhsBounds.width
    }

    private static func recordSortOrder(_ lhs: HighlightAnnotationRecord, _ rhs: HighlightAnnotationRecord) -> Bool {
        if lhs.pageIndex != rhs.pageIndex {
            return lhs.pageIndex < rhs.pageIndex
        }
        return annotationSortOrder(lhs.annotation, rhs.annotation)
    }

    private static func highlightGroup(
        groupID: String,
        records unsortedRecords: [HighlightAnnotationRecord],
        ocrCache: inout [ObjectIdentifier: [HighlightOCRService.RecognizedLine]]
    ) -> DocumentHighlightGroup? {
        let records = unsortedRecords.sorted(by: recordSortOrder)
        guard let firstRecord = records.first else { return nil }

        let snippet = records
            .compactMap { annotationSnippet(for: $0, ocrCache: &ocrCache) }
            .joined(separator: " ")
        let comment = records
            .compactMap(\.annotation.contents)
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            ?? ""

        return DocumentHighlightGroup(
            groupID: groupID,
            pageIndex: firstRecord.pageIndex,
            snippet: snippet.isEmpty ? "Untitled Highlight" : snippet,
            color: HighlightColor.closest(to: firstRecord.annotation.color),
            createdAt: records.compactMap(\.annotation.modificationDate).min(),
            comment: comment,
            primarySelection: annotationSelection(for: firstRecord),
            records: records
        )
    }

    private static func annotationSnippet(
        for record: HighlightAnnotationRecord,
        ocrCache: inout [ObjectIdentifier: [HighlightOCRService.RecognizedLine]]
    ) -> String? {
        let extracted = annotationSelection(for: record)?.string.map(PDFTextSanitizer.sanitize)

        if let extracted,
           extracted.isEmpty == false,
           containsIdeographicText(extracted) == false {
            return extracted
        }

        guard let page = record.annotation.page,
              let ocrSnippet = HighlightOCRService.snippet(
                for: record.annotation,
                on: page,
                cache: &ocrCache
              ) else {
            return extracted?.isEmpty == false ? extracted : nil
        }
        return ocrSnippet
    }

    private static func annotationSelection(for record: HighlightAnnotationRecord) -> PDFSelection? {
        guard let page = record.annotation.page else { return nil }
        return page.selection(for: record.annotation.bounds)
    }

    private static func containsIdeographicText(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic }
    }
}
