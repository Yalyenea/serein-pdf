import Foundation

final class SecurityScopedAccessController {
    private var activeRootURLs: [String: URL] = [:]

    deinit {
        stopAllAccess()
    }

    func sync(access: AppConfiguration.Access) -> AppConfiguration.Access {
        let allowedPaths = Set(access.rootURLs.map { $0.standardizedFileURL.path })
        for path in activeRootURLs.keys where allowedPaths.contains(path) == false {
            stopAccess(for: path)
        }

        var updatedAccess = access
        updatedAccess.rootBookmarkData = access.rootBookmarkData.filter { path, _ in
            allowedPaths.contains(path)
        }

        for (path, bookmarkData) in updatedAccess.rootBookmarkData {
            guard activeRootURLs[path] == nil else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            let standardizedURL = url.standardizedFileURL
            guard allowedPaths.contains(standardizedURL.path),
                  standardizedURL.startAccessingSecurityScopedResource() else { continue }

            activeRootURLs[standardizedURL.path] = standardizedURL
            if isStale,
               let refreshedBookmarkData = Self.makeBookmarkData(for: standardizedURL) {
                updatedAccess.rootBookmarkData[standardizedURL.path] = refreshedBookmarkData
            }
        }

        return updatedAccess
    }

    func stopAllAccess() {
        for path in Array(activeRootURLs.keys) {
            stopAccess(for: path)
        }
    }

    static func makeBookmarkData(for url: URL) -> Data? {
        try? url.standardizedFileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func stopAccess(for path: String) {
        activeRootURLs[path]?.stopAccessingSecurityScopedResource()
        activeRootURLs.removeValue(forKey: path)
    }
}
