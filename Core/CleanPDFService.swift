import Foundation
import PDFKit

enum CleanPDFService {
    static func cleanCopyData(from document: PDFDocument) throws -> Data {
        guard let sourceData = document.dataRepresentation(),
              let copy = PDFDocument(data: sourceData) else {
            throw CleanPDFServiceError.failedToCopyDocument
        }

        for pageIndex in 0..<copy.pageCount {
            guard let page = copy.page(at: pageIndex) else { continue }
            for annotation in page.annotations where shouldRemove(annotation) {
                page.removeAnnotation(annotation)
            }
        }

        guard let cleanData = copy.dataRepresentation() else {
            throw CleanPDFServiceError.failedToExportDocument
        }

        return cleanData
    }

    static func writeCleanCopy(from document: PDFDocument, to url: URL) throws {
        let data = try cleanCopyData(from: document)
        try data.write(to: url, options: .atomic)
    }

    private static func shouldRemove(_ annotation: PDFAnnotation) -> Bool {
        annotation.type != "Link" && annotation.type != "Widget"
    }
}

enum CleanPDFServiceError: Error, LocalizedError {
    case failedToCopyDocument
    case failedToExportDocument

    var errorDescription: String? {
        switch self {
        case .failedToCopyDocument:
            "Unable to create a clean PDF copy"
        case .failedToExportDocument:
            "Unable to export the clean PDF copy"
        }
    }
}
