import Foundation

/// GitHub Releases based updater for direct-distributed Serein builds.
struct AppUpdateService: Sendable {
    static let defaultOwner = "Yalyenea"
    static let defaultRepo = "serein-pdf"
    static let dmgNamePrefix = "Serein-"
    static let dmgNameSuffix = ".dmg"

    struct ReleaseInfo: Equatable, Sendable {
        var tagName: String
        var version: String
        var assetName: String
        var assetID: Int
        var browserDownloadURL: URL
        var size: Int64?
        var digest: String?
    }

    enum CheckResult: Equatable, Sendable {
        case upToDate(current: String, latest: String)
        case updateAvailable(ReleaseInfo)
    }

    enum ServiceError: Error, LocalizedError, Equatable {
        case invalidResponse
        case httpStatus(Int)
        case noReleaseAsset
        case invalidVersion(String)
        case downloadFailed(String)
        case missingGitHubToken

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "GitHub returned an invalid response."
            case let .httpStatus(code):
                if code == 404 {
                    "Release not found. For a private repo, set [updates] github_token in config.toml."
                } else {
                    "GitHub request failed (HTTP \(code))."
                }
            case .noReleaseAsset:
                "Latest release has no Serein-*.dmg asset."
            case let .invalidVersion(value):
                "Invalid version string: \(value)"
            case let .downloadFailed(detail):
                "Download failed: \(detail)"
            case .missingGitHubToken:
                "This repository is private. Add a GitHub token under [updates] github_token."
            }
        }
    }

    struct HTTPClient: Sendable {
        var data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        static let urlSession = HTTPClient { request in
            try await URLSession.shared.data(for: request)
        }
    }

    var owner: String = AppUpdateService.defaultOwner
    var repo: String = AppUpdateService.defaultRepo
    var githubToken: String?
    var currentVersion: String
    var httpClient: HTTPClient = .urlSession

    init(
        currentVersion: String,
        githubToken: String? = nil,
        owner: String = AppUpdateService.defaultOwner,
        repo: String = AppUpdateService.defaultRepo,
        httpClient: HTTPClient = .urlSession
    ) {
        self.currentVersion = currentVersion
        self.githubToken = Self.normalizedToken(githubToken)
        self.owner = owner
        self.repo = repo
        self.httpClient = httpClient
    }

    static func bundleShortVersion(from bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Check

    func checkForUpdate() async throws -> CheckResult {
        let release = try await fetchLatestRelease()
        let comparison = try Self.compareVersions(currentVersion, release.version)
        if comparison >= 0 {
            return .upToDate(current: currentVersion, latest: release.version)
        }
        return .updateAvailable(release)
    }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        applyAuth(to: &request)

        let (data, response) = try await httpClient.data(request)
        try throwIfHTTPError(response)
        return try Self.parseLatestRelease(data: data)
    }

    static func parseLatestRelease(data: Data) throws -> ReleaseInfo {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = root["tag_name"] as? String
        else {
            throw ServiceError.invalidResponse
        }

        let version = normalizeVersion(tagName)
        guard version.isEmpty == false else {
            throw ServiceError.invalidVersion(tagName)
        }

        guard let assets = root["assets"] as? [[String: Any]] else {
            throw ServiceError.noReleaseAsset
        }

        let dmgAssets = assets.compactMap { asset -> (name: String, id: Int, url: URL, size: Int64?, digest: String?)? in
            guard
                let name = asset["name"] as? String,
                name.hasPrefix(dmgNamePrefix),
                name.hasSuffix(dmgNameSuffix),
                let id = asset["id"] as? Int,
                let urlString = asset["browser_download_url"] as? String,
                let url = URL(string: urlString)
            else {
                return nil
            }
            let size = (asset["size"] as? NSNumber)?.int64Value
            let digest = asset["digest"] as? String
            return (name, id, url, size, digest)
        }

        guard let chosen = dmgAssets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedDescending }).first else {
            throw ServiceError.noReleaseAsset
        }

        return ReleaseInfo(
            tagName: tagName,
            version: version,
            assetName: chosen.name,
            assetID: chosen.id,
            browserDownloadURL: chosen.url,
            size: chosen.size,
            digest: chosen.digest
        )
    }

    // MARK: - Download

    func downloadRelease(
        _ release: ReleaseInfo,
        to directory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(release.assetName, isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        var request: URLRequest
        if githubToken != nil {
            // Private release assets require the API asset endpoint + Accept: octet-stream.
            let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/assets/\(release.assetID)")!
            request = URLRequest(url: apiURL)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            applyAuth(to: &request)
        } else {
            request = URLRequest(url: release.browserDownloadURL)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }

        let (bytes, response) = try await httpClient.data(request)
        try throwIfHTTPError(response)
        guard bytes.isEmpty == false else {
            throw ServiceError.downloadFailed("empty body")
        }
        try bytes.write(to: destination, options: .atomic)
        progress?(1)
        return destination
    }

    // MARK: - Install

    /// Writes a helper script that waits for this process to exit, then installs and relaunches.
    func scheduleInstallAndRelaunch(
        dmgURL: URL,
        destinationAppURL: URL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws -> URL {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("SereinUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let scriptURL = workDir.appendingPathComponent("install-and-relaunch.sh", isDirectory: false)
        let logURL = workDir.appendingPathComponent("install.log", isDirectory: false)

        let script = """
        #!/bin/bash
        set -euo pipefail
        LOG=\(shellEscape(logURL.path))
        exec >>"$LOG" 2>&1
        echo "Serein updater starting $(date)"
        PID=\(currentPID)
        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
        done
        sleep 0.4

        DMG=\(shellEscape(dmgURL.path))
        DEST=\(shellEscape(destinationAppURL.path))
        MOUNT="$(mktemp -d -t SereinUpdateMount)"
        cleanup() {
          hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
          rm -rf "$MOUNT"
        }
        trap cleanup EXIT

        hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT"
        SOURCE="$(find "$MOUNT" -maxdepth 3 -name 'Serein.app' -type d | head -n 1)"
        if [[ -z "${SOURCE:-}" || ! -d "$SOURCE" ]]; then
          echo "Serein.app not found in DMG"
          exit 1
        fi

        PARENT="$(dirname "$DEST")"
        STAGING="$PARENT/.SereinUpdateStaging-$$.app"
        BACKUP="$PARENT/.SereinUpdateBackup-$$.app"
        rm -rf "$STAGING" "$BACKUP"
        /bin/cp -R "$SOURCE" "$STAGING"
        if [[ -d "$DEST" ]]; then
          /bin/mv "$DEST" "$BACKUP"
        fi
        /bin/mv "$STAGING" "$DEST"
        rm -rf "$BACKUP"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        /usr/bin/open "$DEST"
        rm -f "$DMG"
        echo "Serein updater finished $(date)"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return scriptURL
    }

    // MARK: - Version helpers

    static func normalizeVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }
        // Strip pre-release / build metadata for ordering of stable tags.
        if let dash = value.firstIndex(of: "-") {
            value = String(value[..<dash])
        }
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        return value
    }

    /// Returns -1 if lhs < rhs, 0 if equal, 1 if lhs > rhs.
    static func compareVersions(_ lhs: String, _ rhs: String) throws -> Int {
        let left = normalizeVersion(lhs)
        let right = normalizeVersion(rhs)
        let leftParts = try versionComponents(left)
        let rightParts = try versionComponents(right)
        let count = max(leftParts.count, rightParts.count)
        for index in 0..<count {
            let l = index < leftParts.count ? leftParts[index] : 0
            let r = index < rightParts.count ? rightParts[index] : 0
            if l < r { return -1 }
            if l > r { return 1 }
        }
        return 0
    }

    // MARK: - Private

    private static func versionComponents(_ version: String) throws -> [Int] {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.isEmpty == false else {
            throw ServiceError.invalidVersion(version)
        }
        return try parts.map { part in
            guard let value = Int(part), value >= 0 else {
                throw ServiceError.invalidVersion(version)
            }
            return value
        }
    }

    private static func normalizedToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyAuth(to request: inout URLRequest) {
        if let githubToken {
            request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func throwIfHTTPError(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404, githubToken == nil {
                throw ServiceError.missingGitHubToken
            }
            throw ServiceError.httpStatus(http.statusCode)
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
