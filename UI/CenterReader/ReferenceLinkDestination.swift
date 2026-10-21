import PDFKit

enum ReferenceLinkDestination {
    static func navigationPoint(for destination: PDFDestination) -> CGPoint {
        guard let page = destination.page else { return destination.point }
        let bounds = page.bounds(for: .cropBox)
        // PDF's unspecified-coordinate sentinel is finite (FLT_MAX), but cannot
        // be used as a scroll offset. Page-only links start at the page edge.
        let point = destination.point
        return CGPoint(
            x: point.x.isFinite && point.x != kPDFDestinationUnspecifiedValue ? point.x : bounds.minX,
            y: point.y.isFinite && point.y != kPDFDestinationUnspecifiedValue ? point.y : bounds.maxY
        )
    }

    static func resolve(_ annotation: PDFAnnotation) -> PDFDestination? {
        guard let destination = (annotation.action as? PDFActionGoTo)?.destination ?? annotation.destination,
              let page = destination.page else { return nil }
        // Some publishers encode every citation as a whole-page FitR destination.
        // Recover its position only from a unique numbered entry on that same page.
        guard destination.point.x == kPDFDestinationUnspecifiedValue,
              destination.point.y == kPDFDestinationUnspecifiedValue,
              let source = annotation.page, source.document === page.document,
              let selection = source.selection(for: annotation.bounds),
              let label = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let number = citationNumber(label),
              isBracketedCitation(selection, on: source),
              let text = page.string else { return destination }

        let pattern = #"(?<!\S)(?:\[(\d+)\]|(\d+)\.)(?=\s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let string = text as NSString
        let entries = regex.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap {
            match -> (number: Int, bounds: CGRect)? in
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            guard let value = Int(string.substring(with: range)),
                  let selection = page.selection(for: match.range) else { return nil }
            let bounds = selection.bounds(for: page)
            guard !bounds.isEmpty, !bounds.isInfinite, !bounds.isNull else { return nil }
            return (value, bounds)
        }
        let matches = entries.filter { $0.number == number }
        guard matches.count == 1, let entry = matches.first else { return destination }
        // A bibliography has a repeated number margin. This excludes isolated
        // numbers in prose, equations, and most section headings.
        let aligned = entries.filter { abs($0.bounds.minX - entry.bounds.minX) < 3 }
        guard Set(aligned.map(\.number)).count >= 3 else { return destination }
        return PDFDestination(page: page, at: CGPoint(x: entry.bounds.minX, y: entry.bounds.maxY))
    }

    private static func citationNumber(_ label: String) -> Int? {
        let digits = label.hasPrefix("[") && label.hasSuffix("]")
            ? String(label.dropFirst().dropLast()) : label
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    private static func isBracketedCitation(_ selection: PDFSelection, on page: PDFPage) -> Bool {
        guard selection.numberOfTextRanges(on: page) == 1, let text = page.string else { return false }
        let range = selection.range(at: 0, on: page)
        let regex = try! NSRegularExpression(pattern: #"\[\s*\d+(?:\s*[,;–—-]\s*\d+)*\s*\]"#)
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).contains {
            NSIntersectionRange($0.range, range) == range
        }
    }
}
