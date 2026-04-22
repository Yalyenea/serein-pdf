import AppKit
import PDFKit
import Vision

enum HighlightOCRService {
    struct RecognizedLine {
        let text: VNRecognizedText
        let lineBox: CGRect
    }

    private static let renderScale: CGFloat = 6
    private static let recognitionLanguages = ["zh-Hans", "en-US"]

    static func snippet(
        for annotation: PDFAnnotation,
        on page: PDFPage,
        cache: inout [ObjectIdentifier: [RecognizedLine]]
    ) -> String? {
        let pageID = ObjectIdentifier(page)
        let lines: [RecognizedLine]

        if let cached = cache[pageID] {
            lines = cached
        } else {
            let recognized = recognizeLines(on: page)
            cache[pageID] = recognized
            lines = recognized
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let normalizedHighlight = CGRect(
            x: annotation.bounds.minX / pageBounds.width,
            y: annotation.bounds.minY / pageBounds.height,
            width: annotation.bounds.width / pageBounds.width,
            height: annotation.bounds.height / pageBounds.height
        )
        let candidateLines = lines.filter {
            $0.lineBox.intersects(normalizedHighlight.insetBy(dx: 0, dy: -0.01))
        }

        let snippet = candidateLines
            .map { excerpt(from: $0.text, within: normalizedHighlight) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        let sanitized = PDFTextSanitizer.sanitize(snippet)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func recognizeLines(on page: PDFPage) -> [RecognizedLine] {
        guard let image = renderedPageImage(for: page) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate, lineBox: observation.boundingBox)
        }
    }

    private static func renderedPageImage(for page: PDFPage) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let imageSize = CGSize(
            width: pageBounds.width * renderScale,
            height: pageBounds.height * renderScale
        )
        let image = NSImage(size: imageSize)

        image.lockFocusFlipped(false)
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()

        if let context = NSGraphicsContext.current?.cgContext {
            context.scaleBy(x: renderScale, y: renderScale)
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.cgImage
    }

    private static func excerpt(from text: VNRecognizedText, within highlight: CGRect) -> String {
        var result = ""

        for index in text.string.indices {
            let nextIndex = text.string.index(after: index)
            guard let box = try? text.boundingBox(for: index..<nextIndex) else { continue }

            let overlapX = max(
                0,
                min(highlight.maxX, box.boundingBox.maxX) - max(highlight.minX, box.boundingBox.minX)
            )
            let overlapY = max(
                0,
                min(highlight.maxY, box.boundingBox.maxY) - max(highlight.minY, box.boundingBox.minY)
            )
            let horizontalRatio = overlapX / max(box.boundingBox.width, 0.0001)
            let verticalRatio = overlapY / max(box.boundingBox.height, 0.0001)

            if horizontalRatio > 0.35 && verticalRatio > 0.35 {
                result.append(text.string[index])
            }
        }

        return result
    }
}
