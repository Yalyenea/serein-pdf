import Foundation

enum SereinOpenURLResolverError: Error, LocalizedError, Equatable {
    case invalidDeepLink
    case invalidFileURL
    case unreadableFile(URL)
    case notPDF(URL)

    var errorDescription: String? {
        switch self {
        case .invalidDeepLink:
            L10n.text("Invalid Serein link. Expected serein://open?file=<encoded file URL>.", "无效的 Serein 链接。应为 serein://open?file=<编码后的文件 URL>。")
        case .invalidFileURL:
            L10n.text("The Serein link must contain a local file URL.", "Serein 链接必须包含本地文件 URL。")
        case let .unreadableFile(url):
            L10n.text("Unable to read the requested file at \(url.path).", "无法读取文件 \(url.path)。")
        case let .notPDF(url):
            L10n.text("The requested file is not a PDF: \(url.lastPathComponent)", "该文件不是 PDF：\(url.lastPathComponent)")
        }
    }
}

struct SereinOpenURLResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(_ urls: [URL]) throws -> [URL] {
        try urls.map(resolve)
    }

    func resolve(_ url: URL) throws -> URL {
        guard url.isFileURL == false else { return url }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "serein",
              components.host?.lowercased() == "open",
              components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "file",
              let value = queryItems[0].value,
              value.isEmpty == false else {
            throw SereinOpenURLResolverError.invalidDeepLink
        }

        guard let fileURL = URL(string: value),
              fileURL.isFileURL,
              fileURL.host == nil else {
            throw SereinOpenURLResolverError.invalidFileURL
        }

        let normalizedURL = fileURL.standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false,
              fileManager.isReadableFile(atPath: normalizedURL.path) else {
            throw SereinOpenURLResolverError.unreadableFile(normalizedURL)
        }
        guard normalizedURL.pathExtension.compare("pdf", options: [.caseInsensitive]) == .orderedSame else {
            throw SereinOpenURLResolverError.notPDF(normalizedURL)
        }
        return normalizedURL
    }
}
