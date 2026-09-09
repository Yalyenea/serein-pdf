import Foundation

struct PDFLibraryRoot: Equatable, Sendable {
    let url: URL
    let title: String
}

struct PDFLibraryItem: Equatable, Sendable {
    let url: URL
    let rootURL: URL
    let folderURL: URL
    let title: String
    let relativePath: String
    let relativeFolderPath: String
    let searchableText: String
}

struct PDFLibraryCatalog: Equatable, Sendable {
    let roots: [PDFLibraryRoot]
    let items: [PDFLibraryItem]
    let rootItemCounts: [URL: Int]
    private let itemsByRootURL: [URL: [PDFLibraryItem]]
    private let itemsByFolderURL: [URL: [PDFLibraryItem]]

    init(roots: [PDFLibraryRoot], items: [PDFLibraryItem]) {
        let itemsByRootURL = Dictionary(grouping: items, by: \.rootURL)
        self.roots = roots
        self.items = items
        self.itemsByRootURL = itemsByRootURL
        self.itemsByFolderURL = Dictionary(grouping: items, by: \.folderURL)
        self.rootItemCounts = roots.reduce(into: [:]) { counts, root in
            counts[root.url] = itemsByRootURL[root.url, default: []].count
        }
    }

    static func build(
        folderURLs: [URL],
        scanner: PDFLibraryScanner = PDFLibraryScanner(),
        fileManager: FileManager = .default,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> PDFLibraryCatalog {
        var seenRootPaths: Set<String> = []
        var seenPDFPaths: Set<String> = []
        var roots: [PDFLibraryRoot] = []
        var items: [PDFLibraryItem] = []

        for folderURL in folderURLs {
            guard shouldCancel() == false else { return PDFLibraryCatalog(roots: [], items: []) }
            let rootURL = folderURL.standardizedFileURL
            let rootPath = rootURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seenRootPaths.insert(rootPath).inserted else { continue }

            roots.append(PDFLibraryRoot(url: rootURL, title: Self.title(for: rootURL)))

            for pdfURL in scanner.scan(
                folderURLs: [rootURL],
                sortResults: false,
                shouldCancel: shouldCancel
            ) {
                guard shouldCancel() == false else { return PDFLibraryCatalog(roots: [], items: []) }
                let pdfPath = pdfURL.path
                guard seenPDFPaths.insert(pdfPath).inserted else { continue }
                let folderURL = pdfURL.deletingLastPathComponent().standardizedFileURL
                items.append(
                    PDFLibraryItem(
                        url: pdfURL,
                        rootURL: rootURL,
                        folderURL: folderURL,
                        title: pdfURL.deletingPathExtension().lastPathComponent,
                        relativePath: Self.relativePath(from: rootURL, to: pdfURL),
                        relativeFolderPath: Self.relativePath(from: rootURL, to: folderURL),
                        searchableText: Self.searchableText(for: pdfURL, rootURL: rootURL)
                    )
                )
            }
        }

        return PDFLibraryCatalog(
            roots: roots,
            items: items.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        )
    }

    func items(forRootURL rootURL: URL) -> [PDFLibraryItem] {
        itemsByRootURL[rootURL.standardizedFileURL, default: []]
    }

    func items(forFolderURL folderURL: URL) -> [PDFLibraryItem] {
        itemsByFolderURL[folderURL.standardizedFileURL, default: []]
    }

    private static func title(for url: URL) -> String {
        let title = url.lastPathComponent
        return title.isEmpty ? url.path : title
    }

    private static func relativePath(from rootURL: URL, to url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return path }
        let startIndex = path.index(path.startIndex, offsetBy: rootPath.count)
        let relative = String(path[startIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? title(for: url) : relative
    }

    private static func searchableText(for pdfURL: URL, rootURL: URL) -> String {
        [
            pdfURL.deletingPathExtension().lastPathComponent,
            relativePath(from: rootURL, to: pdfURL),
            pdfURL.path,
        ]
        .joined(separator: "\n")
        .lowercased()
    }
}

final class PDFLibraryCatalogCache {
    private var cachedFolderURLs: [URL] = []
    private var cachedCatalog: PDFLibraryCatalog?

    func catalog(
        folderURLs: [URL],
        builder: ([URL]) -> PDFLibraryCatalog = { PDFLibraryCatalog.build(folderURLs: $0) }
    ) -> PDFLibraryCatalog {
        let normalizedFolderURLs = Self.normalizedFolderURLs(folderURLs)
        if let cached = cachedCatalog(folderURLs: normalizedFolderURLs) {
            return cached
        }

        let catalog = builder(normalizedFolderURLs)
        store(catalog, folderURLs: normalizedFolderURLs)
        return catalog
    }

    func cachedCatalog(folderURLs: [URL]) -> PDFLibraryCatalog? {
        let normalizedFolderURLs = Self.normalizedFolderURLs(folderURLs)
        if cachedFolderURLs == normalizedFolderURLs, let cachedCatalog {
            return cachedCatalog
        }
        return nil
    }

    func store(_ catalog: PDFLibraryCatalog, folderURLs: [URL]) {
        cachedFolderURLs = Self.normalizedFolderURLs(folderURLs)
        cachedCatalog = catalog
    }

    func invalidate() {
        cachedFolderURLs = []
        cachedCatalog = nil
    }

    static func normalizedFolderURLs(_ folderURLs: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        return folderURLs.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else { return nil }
            return standardizedURL
        }
    }
}

struct PDFLibraryScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(
        folderURLs: [URL],
        sortResults: Bool = true,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> [URL] {
        var seenPaths: Set<String> = []
        var pdfURLs: [URL] = []

        for folderURL in folderURLs {
            guard shouldCancel() == false else { return [] }
            let folderPath = folderURL.standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
            guard let enumerator = fileManager.enumerator(
                at: folderURL.standardizedFileURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard shouldCancel() == false else { return [] }
                guard url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else { continue }
                guard (try? url.resourceValues(forKeys: resourceKeys).isRegularFile) == true else { continue }
                let standardizedURL = url.standardizedFileURL
                let standardizedPath = standardizedURL.path
                guard seenPaths.insert(standardizedPath).inserted else { continue }
                pdfURLs.append(standardizedURL)
            }
        }

        guard sortResults else { return pdfURLs }
        return pdfURLs.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}
