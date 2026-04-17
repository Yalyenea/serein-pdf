import Foundation
import PDFKit

enum OutlineExtractor {
    static func extract(from document: PDFDocument) -> [OutlineNode] {
        guard let root = document.outlineRoot else { return [] }

        return (0..<root.numberOfChildren).compactMap { index in
            guard let child = root.child(at: index) else { return nil }
            return extractNode(from: child, in: document)
        }
    }

    private static func extractNode(from outline: PDFOutline, in document: PDFDocument) -> OutlineNode {
        OutlineNode(
            title: outline.label ?? "",
            pageIndex: pageIndex(for: outline, in: document),
            children: (0..<outline.numberOfChildren).compactMap { index in
                guard let child = outline.child(at: index) else { return nil }
                return extractNode(from: child, in: document)
            }
        )
    }

    private static func pageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            return document.index(for: page)
        }

        if let action = outline.action as? PDFActionGoTo,
           let page = action.destination.page {
            return document.index(for: page)
        }

        return nil
    }
}
