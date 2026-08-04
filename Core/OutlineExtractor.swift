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
        let destination = navigationDestination(for: outline, in: document)
        return OutlineNode(
            title: outline.label ?? "",
            pageIndex: destination?.pageIndex,
            destinationPoint: destination?.point,
            children: (0..<outline.numberOfChildren).compactMap { index in
                guard let child = outline.child(at: index) else { return nil }
                return extractNode(from: child, in: document)
            }
        )
    }

    private static func navigationDestination(
        for outline: PDFOutline,
        in document: PDFDocument
    ) -> ReadingPosition? {
        if let destination = outline.destination,
           let page = destination.page {
            return ReadingPosition(
                pageIndex: document.index(for: page),
                point: destination.point
            )
        }

        if let action = outline.action as? PDFActionGoTo,
           let page = action.destination.page {
            return ReadingPosition(
                pageIndex: document.index(for: page),
                point: action.destination.point
            )
        }

        return nil
    }
}
