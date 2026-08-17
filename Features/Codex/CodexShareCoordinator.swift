import AppKit

enum CodexShareError: Error, LocalizedError, Sendable {
    case applicationNotInstalled
    case invalidTextDeepLink
    case failedToOpenTextComposer
    case failedToEncodePageImage
    case failedToOpenFiles(String)

    var errorDescription: String? {
        switch self {
        case .applicationNotInstalled:
            "Codex is not installed."
        case .invalidTextDeepLink:
            "Unable to create the Codex text link."
        case .failedToOpenTextComposer:
            "Unable to open the text in Codex."
        case .failedToEncodePageImage:
            "Unable to encode the current page as a PNG image."
        case let .failedToOpenFiles(message):
            "Unable to open the file in Codex: \(message)"
        }
    }
}

@MainActor
final class CodexShareCoordinator {
    static let applicationBundleIdentifier = "com.openai.codex"
    private static let transferRetentionInterval: TimeInterval = 24 * 60 * 60

    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let transferRootURL: URL

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        transferRootURL: URL? = nil
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.transferRootURL = transferRootURL
            ?? fileManager.temporaryDirectory.appendingPathComponent("SereinCodexShare", isDirectory: true)
        removeExpiredTransfers()
    }

    static func textDeepLink(for text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "prompt", value: text)]
        return components.url
    }

    func openText(_ text: String) throws {
        guard let url = Self.textDeepLink(for: text) else {
            throw CodexShareError.invalidTextDeepLink
        }
        guard workspace.open(url) else {
            throw CodexShareError.failedToOpenTextComposer
        }
    }

    func writePageImage(_ image: NSImage, documentTitle: String, pageNumber: Int) throws -> URL {
        guard let data = PDFPageImageService.pngData(from: image) else {
            throw CodexShareError.failedToEncodePageImage
        }

        let directory = transferRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = sanitizedBaseName(documentTitle)
        let url = directory.appendingPathComponent("\(baseName)-page-\(pageNumber).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    func openFiles(
        _ urls: [URL],
        completionHandler: @escaping @MainActor (CodexShareError?) -> Void
    ) throws {
        guard let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: Self.applicationBundleIdentifier
        ) else {
            throw CodexShareError.applicationNotInstalled
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            let shareError = error.map {
                CodexShareError.failedToOpenFiles($0.localizedDescription)
            }
            Task { @MainActor in
                completionHandler(shareError)
            }
        }
    }

    private func sanitizedBaseName(_ title: String) -> String {
        let stem = (title as NSString).deletingPathExtension
        let sanitized = stem.map { character in
            character == "/" || character == ":" ? "-" : character
        }
        let baseName = String(sanitized)
        return baseName.isEmpty ? "Page" : baseName
    }

    private func removeExpiredTransfers(referenceDate: Date = Date()) {
        guard fileManager.fileExists(atPath: transferRootURL.path) else { return }
        let cutoffDate = referenceDate.addingTimeInterval(-Self.transferRetentionInterval)

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: transferRootURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for url in urls {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modificationDate = values.contentModificationDate,
                      modificationDate < cutoffDate else { continue }
                try fileManager.removeItem(at: url)
            }
        } catch {
            NSLog("Serein failed to clean expired Codex transfers: %@", error.localizedDescription)
        }
    }
}
