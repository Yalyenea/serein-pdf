import XCTest
@testable import Serein

final class AppUpdateServiceTests: XCTestCase {
    func testNormalizeVersionStripsPrefixAndMetadata() {
        XCTAssertEqual(AppUpdateService.normalizeVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(AppUpdateService.normalizeVersion("1.2.3-beta"), "1.2.3")
        XCTAssertEqual(AppUpdateService.normalizeVersion("1.2.3+build"), "1.2.3")
    }

    func testCompareVersionsOrdersSemver() throws {
        XCTAssertEqual(try AppUpdateService.compareVersions("0.4.0", "0.4.0"), 0)
        XCTAssertEqual(try AppUpdateService.compareVersions("0.3.9", "0.4.0"), -1)
        XCTAssertEqual(try AppUpdateService.compareVersions("0.4.1", "0.4.0"), 1)
        XCTAssertEqual(try AppUpdateService.compareVersions("v0.4.0", "0.4"), 0)
        XCTAssertEqual(try AppUpdateService.compareVersions("1.0", "1.0.1"), -1)
    }

    func testParseLatestReleasePicksDMGAsset() throws {
        let json = """
        {
          "tag_name": "v0.5.0",
          "assets": [
            {
              "id": 11,
              "name": "notes.txt",
              "browser_download_url": "https://example.com/notes.txt",
              "size": 12
            },
            {
              "id": 42,
              "name": "Serein-0.5.0.dmg",
              "browser_download_url": "https://github.com/Yalyenea/serein-pdf/releases/download/v0.5.0/Serein-0.5.0.dmg",
              "size": 1000,
              "digest": "sha256:abc"
            }
          ]
        }
        """.data(using: .utf8)!

        let release = try AppUpdateService.parseLatestRelease(data: json)
        XCTAssertEqual(release.version, "0.5.0")
        XCTAssertEqual(release.tagName, "v0.5.0")
        XCTAssertEqual(release.assetName, "Serein-0.5.0.dmg")
        XCTAssertEqual(release.assetID, 42)
        XCTAssertEqual(release.digest, "sha256:abc")
    }

    func testParseLatestReleaseRequiresDMG() {
        let json = """
        {"tag_name":"v1.0.0","assets":[{"id":1,"name":"source.zip","browser_download_url":"https://example.com/a.zip"}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AppUpdateService.parseLatestRelease(data: json)) { error in
            XCTAssertEqual(error as? AppUpdateService.ServiceError, .noReleaseAsset)
        }
    }

    func testCheckForUpdateReportsAvailableAndUpToDate() async throws {
        let payload = """
        {
          "tag_name": "v9.9.9",
          "assets": [{
            "id": 7,
            "name": "Serein-9.9.9.dmg",
            "browser_download_url": "https://example.com/Serein-9.9.9.dmg",
            "size": 10
          }]
        }
        """.data(using: .utf8)!

        let client = AppUpdateService.HTTPClient { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (payload, response)
        }

        let outdated = AppUpdateService(currentVersion: "0.1.0", httpClient: client)
        let available = try await outdated.checkForUpdate()
        guard case let .updateAvailable(release) = available else {
            return XCTFail("expected updateAvailable")
        }
        XCTAssertEqual(release.version, "9.9.9")

        let current = AppUpdateService(currentVersion: "9.9.9", httpClient: client)
        let upToDate = try await current.checkForUpdate()
        guard case let .upToDate(currentVersion, latest) = upToDate else {
            return XCTFail("expected upToDate")
        }
        XCTAssertEqual(currentVersion, "9.9.9")
        XCTAssertEqual(latest, "9.9.9")
    }

    func testMissingTokenSurfacesPrivateRepoError() async {
        let client = AppUpdateService.HTTPClient { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("{}".utf8), response)
        }
        let service = AppUpdateService(currentVersion: "0.1.0", githubToken: nil, httpClient: client)
        do {
            _ = try await service.checkForUpdate()
            XCTFail("expected error")
        } catch let error as AppUpdateService.ServiceError {
            XCTAssertEqual(error, .missingGitHubToken)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
