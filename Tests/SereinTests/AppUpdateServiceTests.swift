import XCTest
@testable import Serein

final class AppUpdateServiceTests: XCTestCase {
    func testInstallationRestoresExistingAppIfReplacingItFails() throws {
        try checkInstallationReplacement(failReplacement: true)
    }

    func testInstallationRemovesBackupAfterSuccessfulReplacement() throws {
        try checkInstallationReplacement(failReplacement: false)
    }

    private func checkInstallationReplacement(failReplacement: Bool) throws {
        let directory = try makeDownloadDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.app")
        let destination = directory.appendingPathComponent("destination.app")
        let staging = directory.appendingPathComponent("staging.app")
        let backup = directory.appendingPathComponent("backup.app")
        for (url, version) in [(source, "new"), (destination, "original")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try version.write(to: url.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        }
        let moveCommand = directory.appendingPathComponent("move")
        try """
        #!/bin/bash
        if [[ "$FAIL_REPLACEMENT" == "1" && "$1" == "$STAGING" ]]; then exit 1; fi
        exec /bin/mv "$@"
        """.write(to: moveCommand, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: moveCommand.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "set -euo pipefail\n" + AppUpdateService.installationReplacementScript
            .replacingOccurrences(of: "/bin/mv", with: "\"$MOVE_COMMAND\"")]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "SOURCE": source.path, "DEST": destination.path, "STAGING": staging.path,
            "BACKUP": backup.path, "MOVE_COMMAND": moveCommand.path,
            "FAIL_REPLACEMENT": failReplacement ? "1" : "0",
        ]) { _, value in value }
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, failReplacement ? 1 : 0)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8),
                       failReplacement ? "original" : "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testDownloadMovesValidatedFileAndUsesAuthenticatedAssetEndpoint() async throws {
        let directory = try makeDownloadDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("temporary-download")
        try Data("abc".utf8).write(to: source)
        let response = downloadResponse()
        let client = AppUpdateService.HTTPClient(download: { request in
            XCTAssertEqual(request.url?.path, "/repos/Yalyenea/serein-pdf/releases/assets/42")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
            return (source, response)
        }, data: { _ in
            XCTFail("Release files must download directly to disk")
            throw AppUpdateService.ServiceError.invalidResponse
        })
        let service = AppUpdateService(currentVersion: "1", githubToken: "token", httpClient: client)
        let destination = try await service.downloadRelease(
            downloadReleaseInfo(size: 3, digest: "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            to: directory.appendingPathComponent("output")
        )
        XCTAssertEqual(try Data(contentsOf: destination), Data("abc".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testDownloadRejectsInvalidContentAndRemovesTemporaryFile() async throws {
        let directory = try makeDownloadDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("temporary-download")
        let output = directory.appendingPathComponent("output")
        let response = downloadResponse()
        let client = AppUpdateService.HTTPClient(download: { _ in (source, response) }, data: { _ in
            throw AppUpdateService.ServiceError.invalidResponse
        })
        let service = AppUpdateService(currentVersion: "1", httpClient: client)
        for (content, size, digest) in [
            ("", Int64(0), nil as String?),
            ("abc", Int64(4), nil),
            ("abc", Int64(3), "sha256:" + String(repeating: "0", count: 64)),
            ("abc", Int64(3), "sha512:unsupported"),
        ] {
            try Data(content.utf8).write(to: source)
            do {
                _ = try await service.downloadRelease(downloadReleaseInfo(size: size, digest: digest), to: output)
                XCTFail("Invalid download must be rejected")
            } catch let error as AppUpdateService.ServiceError {
                guard case .downloadFailed = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Serein-2.dmg").path))
        }
    }

    func testDownloadRemovesHTTPErrorBody() async throws {
        let directory = try makeDownloadDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("temporary-download")
        try Data("error".utf8).write(to: source)
        let response = downloadResponse(statusCode: 500)
        let client = AppUpdateService.HTTPClient(download: { _ in (source, response) }, data: { _ in
            throw AppUpdateService.ServiceError.invalidResponse
        })
        let service = AppUpdateService(currentVersion: "1", httpClient: client)
        do {
            _ = try await service.downloadRelease(downloadReleaseInfo(size: nil, digest: nil), to: directory)
            XCTFail("HTTP error must be rejected")
        } catch {
            XCTAssertEqual(error as? AppUpdateService.ServiceError, .httpStatus(500))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeDownloadDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/AppUpdateServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloadResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com/Serein-2.dmg")!,
                        statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func downloadReleaseInfo(size: Int64?, digest: String?) -> AppUpdateService.ReleaseInfo {
        AppUpdateService.ReleaseInfo(tagName: "v2", version: "2", assetName: "Serein-2.dmg", assetID: 42,
                                     browserDownloadURL: URL(string: "https://example.com/Serein-2.dmg")!,
                                     size: size, digest: digest)
    }

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
