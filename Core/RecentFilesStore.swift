import Foundation

protocol RecentFilesStore {
    func loadRecentFiles() throws -> [URL]
    func recordOpen(for url: URL) throws -> [URL]
    func recordOpen(for urls: [URL]) throws -> [URL]
    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL]
}

struct UserDefaultsRecentFilesStore: RecentFilesStore {
    private static let stateKey = "Serein.RecentFiles"
    private let maxCount: Int
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(maxCount: Int = 200, userDefaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.maxCount = max(1, maxCount)
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func loadRecentFiles() throws -> [URL] {
        let decoded = try decodeStoredRecentFiles()
        let normalized = normalizeRecentFiles(decoded, removingMissingFiles: true)
        if normalized != decoded {
            try persistRecentFiles(normalized)
        }
        return normalized
    }

    func recordOpen(for url: URL) throws -> [URL] {
        try recordOpen(for: [url])
    }

    func recordOpen(for urls: [URL]) throws -> [URL] {
        guard urls.isEmpty == false else { return try loadStoredRecentFiles() }

        var openedPaths: Set<String> = []
        let openedNewestFirst = urls.reversed().compactMap { url -> URL? in
            let normalizedURL = url.standardizedFileURL
            guard openedPaths.insert(normalizedURL.path).inserted else { return nil }
            return normalizedURL
        }
        let stored = try loadStoredRecentFiles()
        var recentFiles = openedNewestFirst + stored.filter {
            openedPaths.contains($0.standardizedFileURL.path) == false
        }

        if recentFiles.count > maxCount {
            recentFiles.removeLast(recentFiles.count - maxCount)
        }

        try persistRecentFiles(recentFiles)
        return recentFiles
    }

    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL] {
        let oldPath = oldURL.standardizedFileURL.path
        var recentFiles = try loadStoredRecentFiles()
        if let index = recentFiles.firstIndex(where: { $0.standardizedFileURL.path == oldPath }) {
            recentFiles[index] = newURL.standardizedFileURL
        } else {
            return recentFiles
        }
        recentFiles = normalizeRecentFiles(recentFiles, removingMissingFiles: false)
        try persistRecentFiles(recentFiles)
        return recentFiles
    }

    private func loadStoredRecentFiles() throws -> [URL] {
        normalizeRecentFiles(try decodeStoredRecentFiles(), removingMissingFiles: false)
    }

    private func decodeStoredRecentFiles() throws -> [URL] {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return [] }
        return try JSONDecoder().decode([URL].self, from: data)
    }

    private func persistRecentFiles(_ urls: [URL]) throws {
        let data = try JSONEncoder().encode(urls)
        userDefaults.set(data, forKey: Self.stateKey)
    }

    private func normalizeRecentFiles(_ urls: [URL], removingMissingFiles: Bool) -> [URL] {
        var normalized: [URL] = []
        var seenPaths: Set<String> = []

        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard seenPaths.insert(path).inserted else { continue }

            if removingMissingFiles {
                var isDirectory = ObjCBool(false)
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue == false else {
                    continue
                }
            }
            normalized.append(standardized)
        }

        if normalized.count > maxCount {
            normalized.removeLast(normalized.count - maxCount)
        }
        return normalized
    }
}
