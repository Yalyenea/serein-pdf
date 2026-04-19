import PDFKit

struct HighlightAnnotationRecord {
    let pageIndex: Int
    let annotation: PDFAnnotation
}

enum HighlightUndoOperation {
    case added([HighlightAnnotationRecord])
    case removed([HighlightAnnotationRecord])
}
