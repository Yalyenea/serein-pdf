import Foundation
import XCTest

/// Creates a unique temp directory for config tests and removes it on teardown.
func withTemporaryConfigRoot(
    _ testCase: XCTestCase,
    _ body: (URL) throws -> Void
) throws {
    let rootURL = try TestPDFFixtures.makeRootDirectory(prefix: "serein-config")
    testCase.addTeardownBlock {
        try? FileManager.default.removeItem(at: rootURL)
    }
    try body(rootURL)
}
