import Foundation
import XCTest
@testable import Serein

final class SereinOpenURLResolverTests: XCTestCase {
    private let resolver = SereinOpenURLResolver()

    func testResolveDecodesRosewashFileURL() throws {
        let root = try makeTemporaryDirectory(named: "A Reader #1")
        let pdfURL = root.appendingPathComponent("paper #1.pdf")
        try Data("fixture".utf8).write(to: pdfURL)
        let deepLink = try makeDeepLink(fileURL: pdfURL)

        XCTAssertEqual(try resolver.resolve(deepLink), pdfURL.standardizedFileURL)
    }

    func testResolvePassesThroughOrdinaryFileURL() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/paper.pdf")

        XCTAssertEqual(try resolver.resolve(fileURL), fileURL)
    }

    func testResolveRejectsInvalidActionAndParameters() throws {
        let root = try makeTemporaryDirectory()
        let pdfURL = root.appendingPathComponent("paper.pdf")
        try Data("fixture".utf8).write(to: pdfURL)
        let encodedFileURL = encodeQueryValue(pdfURL.absoluteString)

        let invalidURLs = [
            "serein://read?file=\(encodedFileURL)",
            "serein://open",
            "serein://open?file=\(encodedFileURL)&file=\(encodedFileURL)",
            "serein://open?file=\(encodedFileURL)&page=1",
            "serein://open/path?file=\(encodedFileURL)",
            "serein://open?file=\(encodedFileURL)#fragment",
        ].compactMap(URL.init(string:))

        for url in invalidURLs {
            XCTAssertThrowsError(try resolver.resolve(url)) { error in
                XCTAssertEqual(error as? SereinOpenURLResolverError, .invalidDeepLink)
            }
        }
    }

    func testResolveRejectsRemoteAndHTTPFileParameters() throws {
        let invalidTargets = [
            "https://example.com/paper.pdf",
            "file://server/share/paper.pdf",
        ]

        for target in invalidTargets {
            let url = try XCTUnwrap(URL(string: "serein://open?file=\(encodeQueryValue(target))"))
            XCTAssertThrowsError(try resolver.resolve(url)) { error in
                XCTAssertEqual(error as? SereinOpenURLResolverError, .invalidFileURL)
            }
        }
    }

    func testResolveRejectsDirectoryAndNonPDF() throws {
        let root = try makeTemporaryDirectory()
        let textURL = root.appendingPathComponent("notes.txt")
        try Data("fixture".utf8).write(to: textURL)

        let directoryLink = try makeDeepLink(fileURL: root)
        XCTAssertThrowsError(try resolver.resolve(directoryLink)) { error in
            XCTAssertEqual(error as? SereinOpenURLResolverError, .unreadableFile(root.standardizedFileURL))
        }

        let textLink = try makeDeepLink(fileURL: textURL)
        XCTAssertThrowsError(try resolver.resolve(textLink)) { error in
            XCTAssertEqual(error as? SereinOpenURLResolverError, .notPDF(textURL.standardizedFileURL))
        }
    }

    private func makeTemporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SereinOpenURLResolverTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeDeepLink(fileURL: URL) throws -> URL {
        try XCTUnwrap(URL(string: "serein://open?file=\(encodeQueryValue(fileURL.absoluteString))"))
    }

    private func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
