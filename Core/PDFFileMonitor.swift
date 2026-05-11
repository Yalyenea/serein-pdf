import Darwin
import Dispatch
import Foundation

struct PDFFileSnapshot: Equatable, Sendable {
    let modificationDate: Date
    let fileSize: UInt64
    let fileIdentifier: UInt64?

    init?(url: URL, fileManager: FileManager = .default) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else { return nil }
        self.modificationDate = modificationDate
        self.fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        self.fileIdentifier = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}

@MainActor
final class PDFFileMonitor {
    typealias ChangeHandler = (URL) -> Void

    private struct DirectoryMonitor: @unchecked Sendable {
        let descriptor: CInt
        let source: DispatchSourceFileSystemObject
        var fileURLs: Set<URL>
        var pendingScan: DispatchWorkItem?
    }

    var onChange: ChangeHandler?

    private let debounceInterval: TimeInterval
    private var monitors: [URL: DirectoryMonitor] = [:]

    init(debounceInterval: TimeInterval = 0.25) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        for monitor in monitors.values {
            monitor.pendingScan?.cancel()
            monitor.source.cancel()
        }
    }

    func replaceMonitoredURLs(with urls: Set<URL>) {
        let groupedURLs = Dictionary(grouping: urls.map(normalizedFileURL)) { url in
            normalizedDirectoryURL(for: url)
        }

        let obsoleteDirectories = monitors.keys.filter { groupedURLs[$0] == nil }
        for directoryURL in obsoleteDirectories {
            stopMonitoring(directoryURL)
        }

        for (directoryURL, fileURLs) in groupedURLs {
            let uniqueFileURLs = Set(fileURLs)
            if monitors[directoryURL] != nil {
                monitors[directoryURL]?.fileURLs = uniqueFileURLs
            } else {
                startMonitoring(directoryURL, fileURLs: uniqueFileURLs)
            }
        }
    }

    private func startMonitoring(_ directoryURL: URL, fileURLs: Set<URL>) {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan(for: directoryURL)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        monitors[directoryURL] = DirectoryMonitor(
            descriptor: descriptor,
            source: source,
            fileURLs: fileURLs
        )
        source.resume()
    }

    private func stopMonitoring(_ directoryURL: URL) {
        guard let monitor = monitors.removeValue(forKey: directoryURL) else { return }
        monitor.pendingScan?.cancel()
        monitor.source.cancel()
    }

    private func scheduleScan(for directoryURL: URL) {
        monitors[directoryURL]?.pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            self?.emitChanges(in: directoryURL)
        }
        monitors[directoryURL]?.pendingScan = scan
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: scan)
    }

    private func emitChanges(in directoryURL: URL) {
        guard let monitor = monitors[directoryURL] else { return }
        monitors[directoryURL]?.pendingScan = nil
        for fileURL in monitor.fileURLs {
            onChange?(fileURL)
        }
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private func normalizedDirectoryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().standardizedFileURL
    }
}
