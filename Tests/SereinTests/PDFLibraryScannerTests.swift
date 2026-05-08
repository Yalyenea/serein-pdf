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
        XCTAssertEqual(catalog.rootItemCounts[rootURL.standardizedFileURL], 1)
        XCTAssertEqual(catalog.items(forRootURL: rootURL).map(\.title), ["Sparse Estimation"])
        XCTAssertEqual(catalog.items(forFolderURL: nestedURL).map(\.title), ["Sparse Estimation"])
        XCTAssertTrue(catalog.items.first?.searchableText.contains("sparse estimation") == true)
    }

    func testCatalogCacheReusesCatalogForSameFoldersUntilInvalidated() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try Data("a".utf8).write(to: rootURL.appendingPathComponent("A.pdf"))

        let cache = PDFLibraryCatalogCache()
        var buildCount = 0
        let builder: ([URL]) -> PDFLibraryCatalog = { folderURLs in
            buildCount += 1
            return PDFLibraryCatalog.build(folderURLs: folderURLs)
        }

        let first = cache.catalog(folderURLs: [rootURL], builder: builder)
        try Data("b".utf8).write(to: rootURL.appendingPathComponent("B.pdf"))
        let second = cache.catalog(folderURLs: [rootURL], builder: builder)

        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(first.items.map(\.title), ["A"])
        XCTAssertEqual(second.items.map(\.title), ["A"])

        cache.invalidate()
        let third = cache.catalog(folderURLs: [rootURL], builder: builder)

        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(third.items.map(\.title), ["A", "B"])
    }
}
