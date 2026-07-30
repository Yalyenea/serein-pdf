import AppKit
import Foundation
import PDFKit
import XCTest

/// Shared PDF fixtures for SereinTests. Files live under unique temp directories
/// that are registered for best-effort cleanup (XCTest teardown + process exit).
enum TestPDFFixtures {
    private final class RootRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var roots: [URL] = []

        func register(_ url: URL) {
            lock.lock()
            roots.append(url)
            lock.unlock()
        }

        func takeAll() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            let snapshot = roots
            roots.removeAll()
            return snapshot
        }
    }

    private static let registry = RootRegistry()

    static func registerRoot(_ url: URL) {
        registry.register(url)
    }

    static func makeRootDirectory(prefix: String = "serein-test") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registerRoot(root)
        return root
    }

    static func purgeRegisteredRoots() {
        for root in registry.takeAll() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Blank multi-page PDF (image pages, no selectable text).
    static func makeBlankPDF(
        named name: String,
        pageCount: Int = 1,
        pageSize: NSSize = NSSize(width: 200, height: 260)
    ) throws -> URL {
        let root = try makeRootDirectory()
        let url = root.appendingPathComponent("\(name).pdf")
        let document = makeBlankDocument(pageCount: pageCount, pageSize: pageSize)
        guard document.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Labeled image pages (used by WindowChrome framing tests).
    static func makeLabeledPDF(
        named name: String,
        pageSizes: [NSSize] = [NSSize(width: 200, height: 260)]
    ) throws -> URL {
        let root = try makeRootDirectory()
        let url = root.appendingPathComponent("\(name).pdf")
        try writeLabeledPDF(to: url, named: name, pageSizes: pageSizes)
        return url
    }

    static func writeLabeledPDF(to url: URL, named name: String, pageSizes: [NSSize]) throws {
        let document = PDFDocument()
        for (index, pageSize) in pageSizes.enumerated() {
            let image = NSImage(size: pageSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: pageSize)).fill()
            let textRect = NSRect(
                x: max(pageSize.width * 0.12, 24),
                y: max(pageSize.height * 0.42, 24),
                width: max(pageSize.width * 0.76, 120),
                height: 40
            )
            NSString(string: "\(name)-\(index)").draw(
                in: textRect,
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: NSColor.black,
                ]
            )
            image.unlockFocus()
            guard let page = PDFPage(image: image) else {
                throw CocoaError(.fileWriteUnknown)
            }
            document.insert(page, at: index)
        }
        guard document.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Searchable multi-page PDF with drawn text on each page.
    static func makeSearchablePDF(named name: String, pages: [String]) throws -> URL {
        let root = try makeRootDirectory()
        let url = root.appendingPathComponent("\(name).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]

        for pageText in pages {
            context.beginPDFPage(nil)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            NSColor.white.setFill()
            NSBezierPath(rect: mediaBox).fill()
            NSString(string: pageText).draw(
                in: NSRect(x: 72, y: 520, width: 468, height: 160),
                withAttributes: attributes
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        guard let document = PDFDocument(url: url), document.pageCount == pages.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return url
    }

    /// Single-page searchable PDF document (draw-at-point path keeps CJK findable).
    static func makeSearchableDocument(text: String) throws -> PDFDocument {
        let root = try makeRootDirectory()
        let url = root.appendingPathComponent("searchable-inline.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 220)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.white.setFill()
        NSBezierPath(rect: mediaBox).fill()
        NSString(string: text).draw(
            at: NSPoint(x: 48, y: 112),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        data.write(to: url, atomically: true)

        guard let document = PDFDocument(url: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    /// Selectable text PDF via NSTextView export.
    @MainActor
    static func makeSelectablePDF(named name: String, text: String) throws -> URL {
        let size = NSSize(width: 480, height: 240)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 28, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 32)
        let data = textView.dataWithPDF(inside: textView.bounds)
        let root = try makeRootDirectory()
        let url = root.appendingPathComponent("\(name).pdf")
        try data.write(to: url)
        return url
    }

    static func makeBlankDocument(
        pageCount: Int,
        pageSize: NSSize = NSSize(width: 200, height: 260)
    ) -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<pageCount {
            let image = NSImage(size: pageSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: pageSize)).fill()
            image.unlockFocus()
            if let page = PDFPage(image: image) {
                document.insert(page, at: document.pageCount)
            }
        }
        return document
    }

    static func blankPDFData(pageCount: Int) throws -> Data {
        guard let data = makeBlankDocument(pageCount: pageCount).dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

extension XCTestCase {
    /// Ensure temp roots created by `TestPDFFixtures` during this test are removed.
    func trackPDFFixturesForTeardown() {
        addTeardownBlock {
            TestPDFFixtures.purgeRegisteredRoots()
        }
    }
}
