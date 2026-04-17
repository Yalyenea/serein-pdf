import Foundation

protocol RecentFilesStore {
    func loadRecentFiles() throws -> [URL]
    func recordOpen(for url: URL) throws -> [URL]
}

struct UserDefaultsRecentFilesStore: RecentFilesStore {
    private static let stateKey = "SlatePDF.RecentFiles"
    private let maxCount: Int
    private let userDefaults: UserDefaults

    init(maxCount: Int = 20, userDefaults: UserDefaults = .standard) {
        self.maxCount = maxCount
        self.userDefaults = userDefaults
    }

    func loadRecentFiles() throws -> [URL] {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return [] }
        return try JSONDecoder().decode([URL].self, from: data)
    }

    func recordOpen(for url: URL) throws -> [URL] {
        var recentFiles = try loadRecentFiles().filter { $0 != url }
        recentFiles.insert(url, at: 0)

        if recentFiles.count > maxCount {
            recentFiles.removeLast(recentFiles.count - maxCount)
        }

        let data = try JSONEncoder().encode(recentFiles)
        userDefaults.set(data, forKey: Self.stateKey)
        return recentFiles
    }
}
