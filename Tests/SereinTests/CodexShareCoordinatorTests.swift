import AppKit
import XCTest
@testable import Serein

@MainActor
final class CodexShareCoordinatorTests: XCTestCase {
    func testTextDeepLinkRoundTripsPromptWithoutWorkspacePath() throws {
        let prompt = "中文 selection\nreserved: & # %"
        let url = try XCTUnwrap(CodexShareCoordinator.textDeepLink(for: prompt))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "new")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "prompt", value: prompt)])
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "path" }))
    }

    func testWritePageImageCreatesReadablePNGWithSanitizedFilename() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let coordinator = CodexShareCoordinator(transferRootURL: rootURL)
        let document = TestPDFFixtures.makeBlankDocument(pageCount: 1)
        let page = try XCTUnwrap(document.page(at: 0))

        let url = try coordinator.writePageImage(
            PDFPageImageService.image(from: page),
            documentTitle: "notes:revision.pdf",
            pageNumber: 3
        )

        XCTAssertEqual(url.lastPathComponent, "notes-revision-page-3.png")
        let data = try Data(contentsOf: url)
        XCTAssertNotNil(NSBitmapImageRep(data: data))
    }

    func testInitializationRemovesOnlyExpiredTransferDirectories() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let expiredURL = rootURL.appendingPathComponent("expired", isDirectory: true)
        let recentURL = rootURL.appendingPathComponent("recent", isDirectory: true)
        try fileManager.createDirectory(at: expiredURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recentURL, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-48 * 60 * 60)],
            ofItemAtPath: expiredURL.path
        )
        defer { try? fileManager.removeItem(at: rootURL) }

        _ = CodexShareCoordinator(fileManager: fileManager, transferRootURL: rootURL)

        XCTAssertFalse(fileManager.fileExists(atPath: expiredURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recentURL.path))
    }
}
