import AppKit
import XCTest
@testable import Serein

@MainActor
final class PDFLibraryPaletteControllerTests: XCTestCase {
    func testRefreshResetsSegmentFilterAlongWithSegmentControl() async throws {
        _ = NSApplication.shared
        let root = try TestPDFFixtures.makeRootDirectory(prefix: "library-refresh")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: first.appendingPathComponent("Alpha.pdf"))
        try Data("b".utf8).write(to: second.appendingPathComponent("Beta.pdf"))
        let controller = PDFLibraryPaletteController { _ in }
        defer { controller.close() }
        controller.testingShow(folderURLs: [first, second])
        await controller.testingWaitForCatalog()
        controller.testingSelectSegment(2)
        XCTAssertEqual(controller.testingPDFTitles, ["Beta"])

        controller.testingInvalidateCatalogCache()
        await controller.testingWaitForCatalog()

        XCTAssertEqual(controller.testingPDFTitles, ["Alpha", "Beta"])
        XCTAssertEqual(controller.testingFolderRowTitles.first, "All libraries")
        XCTAssertFalse(controller.testingFolderRowTitles.contains("First/First"))
        XCTAssertFalse(controller.testingFolderRowTitles.contains("Second/Second"))
    }

    func testShowBuildsFolderRowsAndFiltersPDFs() async throws {
        _ = NSApplication.shared
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let mathURL = rootURL.appendingPathComponent("Math", isDirectory: true)
        let signalURL = rootURL.appendingPathComponent("Signal", isDirectory: true)
        try FileManager.default.createDirectory(at: mathURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: signalURL, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: mathURL.appendingPathComponent("Algebra.pdf"))
        try Data("s".utf8).write(to: signalURL.appendingPathComponent("Spectrum.pdf"))

        let controller = PDFLibraryPaletteController { _ in }
        controller.testingShow(folderURLs: [rootURL])
        defer { controller.close() }
        XCTAssertTrue(controller.testingIsLoadingCatalog)

        await controller.testingWaitForCatalog()

        XCTAssertEqual(
            controller.testingFolderRowTitles,
            ["All libraries", rootURL.lastPathComponent, "\(rootURL.lastPathComponent)/Math", "\(rootURL.lastPathComponent)/Signal"]
        )
        XCTAssertEqual(controller.testingPDFTitles, ["Algebra", "Spectrum"])

        controller.testingSetQuery("spectrum")

        XCTAssertEqual(controller.testingPDFTitles, ["Spectrum"])
    }

    func testInvalidateWhileVisibleRestartsCatalogBuild() async throws {
        _ = NSApplication.shared
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: rootURL.appendingPathComponent("Algebra.pdf"))

        let controller = PDFLibraryPaletteController { _ in }
        controller.testingShow(folderURLs: [rootURL])
        defer { controller.close() }
        XCTAssertTrue(controller.testingIsLoadingCatalog)

        controller.testingInvalidateCatalogCache()
        XCTAssertTrue(controller.testingIsLoadingCatalog)

        await controller.testingWaitForCatalog()
        XCTAssertFalse(controller.testingIsLoadingCatalog)
        XCTAssertEqual(controller.testingPDFTitles, ["Algebra"])
    }
}
