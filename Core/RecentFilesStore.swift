import Foundation

protocol RecentFilesStore {
    func loadRecentFiles() throws -> [URL]
    func recordOpen(for url: URL) throws -> [URL]
    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL]
}

struct UserDefaultsRecentFilesStore: RecentFilesStore {
    private static let stateKey = "Serein.RecentFiles"
    private let maxCount: Int
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(maxCount: Int = 200, userDefaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.maxCount = maxCount
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func loadRecentFiles() throws -> [URL] {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return [] }
        let decoded = try JSONDecoder().decode([URL].self, from: data)
        let normalized = normalizeRecentFiles(decoded)
        if normalized != decoded {
            try persistRecentFiles(normalized)
        }
        return normalized
    }

    func recordOpen(for url: URL) throws -> [URL] {
        let normalizedURL = url.standardizedFileURL
        let normalizedPath = normalizedURL.path
        var recentFiles = try loadRecentFiles().filter { $0.standardizedFileURL.path != normalizedPath }
        recentFiles.insert(normalizedURL, at: 0)

        if recentFiles.count > maxCount {
            recentFiles.removeLast(recentFiles.count - maxCount)
        }

        try persistRecentFiles(recentFiles)
        return recentFiles
    }

    func replaceURL(_ oldURL: URL, with newURL: URL) throws -> [URL] {
        let oldPath = oldURL.standardizedFileURL.path
        var recentFiles = try loadRecentFiles()
        if let index = recentFiles.firstIndex(where: { $0.standardizedFileURL.path == oldPath }) {
            recentFiles[index] = newURL.standardizedFileURL
        }
        try persistRecentFiles(recentFiles)
        return recentFiles
    }

    private func persistRecentFiles(_ urls: [URL]) throws {
        let data = try JSONEncoder().encode(urls)
        userDefaults.set(data, forKey: Self.stateKey)
    }

    private func normalizeRecentFiles(_ urls: [URL]) -> [URL] {
        var normalized: [URL] = []
        var seenPaths: Set<String> = []

        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard seenPaths.insert(path).inserted else { continue }

            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue == false else {
                continue
            }
            normalized.append(standardized)
        }

        if normalized.count > maxCount {
            normalized.removeLast(normalized.count - maxCount)
        }
        return normalized
    }
}
