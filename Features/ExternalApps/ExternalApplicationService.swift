import AppKit

struct ExternalPDFApplication {
    let url: URL
    let name: String
    let icon: NSImage
}

struct OpenWithRequest {
    let sessionID: UUID
    let applicationURL: URL
}

enum ExternalApplicationError: Error, LocalizedError, Sendable {
    case failedToOpen(String)

    var errorDescription: String? {
        switch self {
        case let .failedToOpen(message):
            "Unable to open the PDF: \(message)"
        }
    }
}

@MainActor
final class ExternalApplicationService {
    private static let excludedBundleIdentifiers: Set<String> = [
        "local.yfff.Serein",
        CodexShareCoordinator.applicationBundleIdentifier,
    ]

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func applications(for documentURL: URL) -> [ExternalPDFApplication] {
        var seenBundleIdentifiers: Set<String> = []
        return workspace.urlsForApplications(toOpen: documentURL).compactMap { applicationURL in
            guard let bundle = Bundle(url: applicationURL),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  Self.excludedBundleIdentifiers.contains(bundleIdentifier) == false,
                  seenBundleIdentifiers.insert(bundleIdentifier).inserted else { return nil }

            let icon = workspace.icon(forFile: applicationURL.path)
            icon.size = NSSize(width: 16, height: 16)
            return ExternalPDFApplication(
                url: applicationURL,
                name: fileManager.displayName(atPath: applicationURL.path),
                icon: icon
            )
        }
    }

    func open(
        documentURL: URL,
        with applicationURL: URL,
        completionHandler: @escaping @MainActor (ExternalApplicationError?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            [documentURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            let openError = error.map {
                ExternalApplicationError.failedToOpen($0.localizedDescription)
            }
            Task { @MainActor in
                completionHandler(openError)
            }
        }
    }
}
