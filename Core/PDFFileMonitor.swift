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

    private final class DirectoryMonitor: @unchecked Sendable {
        let descriptor: CInt
        let source: DispatchSourceFileSystemObject
        var fileURLs: Set<URL>
        var pendingScan: DispatchWorkItem?

        init(descriptor: CInt, source: DispatchSourceFileSystemObject, fileURLs: Set<URL>) {
            self.descriptor = descriptor
            self.source = source
            self.fileURLs = fileURLs
        }
    }

    private final class FileMonitor: @unchecked Sendable {
        let descriptor: CInt
        let source: DispatchSourceFileSystemObject
        var pendingScan: DispatchWorkItem?

        init(descriptor: CInt, source: DispatchSourceFileSystemObject) {
            self.descriptor = descriptor
            self.source = source
        }
    }

    var onChange: ChangeHandler?

    private let debounceInterval: TimeInterval
    private var monitors: [URL: DirectoryMonitor] = [:]
    private var fileMonitors: [URL: FileMonitor] = [:]

    init(debounceInterval: TimeInterval = 0.25) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        for monitor in monitors.values {
            monitor.pendingScan?.cancel()
            monitor.source.cancel()
        }
        for monitor in fileMonitors.values {
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
            if let monitor = monitors[directoryURL] {
                let obsoleteFileURLs = monitor.fileURLs.subtracting(uniqueFileURLs)
                for fileURL in obsoleteFileURLs {
                    stopMonitoringFile(fileURL)
                }
                monitor.fileURLs = uniqueFileURLs
                for fileURL in uniqueFileURLs where fileMonitors[fileURL] == nil {
                    startMonitoringFile(fileURL)
                }
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
        for fileURL in fileURLs {
            startMonitoringFile(fileURL)
        }
        source.resume()
    }

    private func stopMonitoring(_ directoryURL: URL) {
        guard let monitor = monitors.removeValue(forKey: directoryURL) else { return }
        monitor.pendingScan?.cancel()
        monitor.source.cancel()
        for fileURL in monitor.fileURLs {
            stopMonitoringFile(fileURL)
        }
    }

    private func startMonitoringFile(_ fileURL: URL) {
        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan(forFileAt: fileURL)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        fileMonitors[fileURL] = FileMonitor(descriptor: descriptor, source: source)
        source.resume()
    }

    private func stopMonitoringFile(_ fileURL: URL) {
        guard let monitor = fileMonitors.removeValue(forKey: fileURL) else { return }
        monitor.pendingScan?.cancel()
        monitor.source.cancel()
    }

    private func restartMonitoringFile(_ fileURL: URL) {
        stopMonitoringFile(fileURL)
        startMonitoringFile(fileURL)
    }

    private func scheduleScan(for directoryURL: URL) {
        monitors[directoryURL]?.pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            self?.emitChanges(in: directoryURL)
        }
        monitors[directoryURL]?.pendingScan = scan
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: scan)
    }

    private func scheduleScan(forFileAt fileURL: URL) {
        fileMonitors[fileURL]?.pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            self?.emitChange(forFileAt: fileURL)
        }
        fileMonitors[fileURL]?.pendingScan = scan
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: scan)
    }

    private func emitChanges(in directoryURL: URL) {
        guard let monitor = monitors[directoryURL] else { return }
        monitors[directoryURL]?.pendingScan = nil
        for fileURL in monitor.fileURLs {
            restartMonitoringFile(fileURL)
            onChange?(fileURL)
        }
    }

    private func emitChange(forFileAt fileURL: URL) {
        fileMonitors[fileURL]?.pendingScan = nil
        onChange?(fileURL)
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private func normalizedDirectoryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().standardizedFileURL
    }
}
