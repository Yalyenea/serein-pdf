import XCTest
@testable import Serein

final class PDFLibraryScannerTests: XCTestCase {
    func testScanFindsPDFsRecursivelyAndSortsThem() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = rootURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let alpha = rootURL.appendingPathComponent("Alpha.pdf")
        let beta = nestedURL.appendingPathComponent("Beta.PDF")
        let note = nestedURL.appendingPathComponent("note.txt")
        try Data("a".utf8).write(to: alpha)
        try Data("b".utf8).write(to: beta)
        try Data("n".utf8).write(to: note)

        let urls = PDFLibraryScanner().scan(folderURLs: [rootURL])

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Alpha.pdf", "Beta.PDF"])
    }

    func testScanDeduplicatesOverlappingFolders() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = rootURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let pdfURL = nestedURL.appendingPathComponent("Paper.pdf")
        try Data("p".utf8).write(to: pdfURL)

        let urls = PDFLibraryScanner().scan(folderURLs: [rootURL, nestedURL])

        XCTAssertEqual(urls, [pdfURL.standardizedFileURL])
    }

    func testCatalogKeepsRootAndRelativeFolderMetadata() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedURL = rootURL.appendingPathComponent("Books/Math", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        let pdfURL = nestedURL.appendingPathComponent("Sparse Estimation.pdf")
        try Data("p".utf8).write(to: pdfURL)

        let catalog = PDFLibraryCatalog.build(folderURLs: [rootURL])

        XCTAssertEqual(catalog.roots.map(\.url), [rootURL.standardizedFileURL])
        XCTAssertEqual(catalog.items.map(\.title), ["Sparse Estimation"])
        XCTAssertEqual(catalog.items.first?.relativeFolderPath, "Books/Math")
        XCTAssertEqual(catalog.items.first?.relativePath, "Books/Math/Sparse Estimation.pdf")
    }
}
