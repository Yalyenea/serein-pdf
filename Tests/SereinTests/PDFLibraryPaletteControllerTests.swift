import AppKit
import XCTest
@testable import Serein

@MainActor
final class PDFLibraryPaletteControllerTests: XCTestCase {
    func testShowBuildsFolderRowsAndFiltersPDFs() throws {
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

        XCTAssertEqual(
            controller.testingFolderRowTitles,
            ["All libraries", rootURL.lastPathComponent, "\(rootURL.lastPathComponent)/Math", "\(rootURL.lastPathComponent)/Signal"]
        )
        XCTAssertEqual(controller.testingPDFTitles, ["Algebra", "Spectrum"])

        controller.testingSetQuery("spectrum")

        XCTAssertEqual(controller.testingPDFTitles, ["Spectrum"])
    }
}
