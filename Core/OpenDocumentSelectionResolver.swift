import Foundation
import UniformTypeIdentifiers

enum OpenDocumentSelectionResolverError: Error, LocalizedError, Equatable {
    case noPDFFilesFound
    case unreadableFolder(URL)

    var errorDescription: String? {
        switch self {
        case .noPDFFilesFound:
            return "No PDF files were found in the selected files or folders."
        case let .unreadableFolder(url):
            return "Unable to read folder at \(url.path)"
        }
    }
}

struct OpenDocumentSelectionResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(_ selectedURLs: [URL]) throws -> [URL] {
        var resolvedURLs: [URL] = []
        var seenPaths: Set<String> = []

        for selectedURL in selectedURLs {
            let expandedURLs = try expand(selectedURL)
            for url in expandedURLs {
                let normalizedPath = normalizePath(url)
                guard seenPaths.insert(normalizedPath).inserted else { continue }
                resolvedURLs.append(url)
            }
        }

        guard resolvedURLs.isEmpty == false else {
            throw OpenDocumentSelectionResolverError.noPDFFilesFound
        }

        return resolvedURLs
    }

    private func expand(_ selectedURL: URL) throws -> [URL] {
        let resourceValues = try selectedURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey])
        if resourceValues.isDirectory == true {
            return try pdfURLs(in: selectedURL)
        }
        guard resourceValues.isRegularFile == true else { return [] }
        return isPDFFile(at: selectedURL, resourceValues: resourceValues) ? [selectedURL] : []
    }

    private func pdfURLs(in directoryURL: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw OpenDocumentSelectionResolverError.unreadableFolder(directoryURL)
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isRegularFile == true else { continue }
            guard isPDFFile(at: url, resourceValues: resourceValues) else { continue }
            urls.append(url)
        }

        return urls.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private func isPDFFile(at url: URL, resourceValues: URLResourceValues) -> Bool {
        if resourceValues.contentType?.conforms(to: .pdf) == true {
            return true
        }
        return url.pathExtension.compare("pdf", options: [.caseInsensitive]) == .orderedSame
    }

    private func normalizePath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
