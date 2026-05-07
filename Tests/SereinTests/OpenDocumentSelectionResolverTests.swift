import Foundation
import XCTest
@testable import Serein

final class OpenDocumentSelectionResolverTests: XCTestCase {
    private let resolver = OpenDocumentSelectionResolver()

    func testResolveIncludesPDFsFromSelectedFoldersRecursively() throws {
        let root = try makeTemporaryDirectory()
        let directPDF = try createFile(named: "direct.pdf", in: root)
        let folder = root.appendingPathComponent("bundle", isDirectory: true)
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let firstFolderPDF = try createFile(named: "alpha.pdf", in: folder)
        let nestedPDF = try createFile(named: "beta.PDF", in: nested)
        _ = try createFile(named: "note.txt", in: nested)

        let resolved = try resolver.resolve([directPDF, folder])

        XCTAssertEqual(
            normalizedPaths(resolved),
            normalizedPaths([directPDF, firstFolderPDF, nestedPDF])
        )
    }

    func testResolveDeduplicatesFilesCoveredByFolderSelection() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appendingPathComponent("papers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sharedPDF = try createFile(named: "shared.pdf", in: folder)

        let resolved = try resolver.resolve([folder, sharedPDF, folder])

        XCTAssertEqual(normalizedPaths(resolved), normalizedPaths([sharedPDF]))
    }

    func testResolveThrowsWhenNoPDFsAreFound() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try createFile(named: "readme.txt", in: folder)

        XCTAssertThrowsError(try resolver.resolve([folder])) { error in
            XCTAssertEqual(error as? OpenDocumentSelectionResolverError, .noPDFFilesFound)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("SereinTests.OpenSelection.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    @discardableResult
    private func createFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: url)
        return url
    }

    private func normalizedPaths(_ urls: [URL]) -> [String] {
        urls.map { $0.standardizedFileURL.path }
    }
}
