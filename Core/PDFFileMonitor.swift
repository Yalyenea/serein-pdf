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

    private enum FileState: Equatable, Sendable {
        case missing
        case existing(PDFFileSnapshot)
    }

    private final class DirectoryMonitor: @unchecked Sendable {
        let source: DispatchSourceFileSystemObject
        var fileURLs: Set<URL>
        var snapshots: [URL: FileState] = [:]
        var scanGeneration: UInt64 = 0
        var pendingScan: DispatchWorkItem?

        init(source: DispatchSourceFileSystemObject, fileURLs: Set<URL>) {
            self.source = source
            self.fileURLs = fileURLs
        }
    }

    var onChange: ChangeHandler?

    private let debounceInterval: TimeInterval
    private let pollingInterval: TimeInterval
    private let snapshotQueue = DispatchQueue(
        label: "local.yfff.Serein.PDFFileMonitor.snapshots",
        qos: .utility
    )
    private var monitors: [URL: DirectoryMonitor] = [:]
    private var pollingTimer: DispatchSourceTimer?

    init(debounceInterval: TimeInterval = 0.25, pollingInterval: TimeInterval = 1.0) {
        self.debounceInterval = max(0, debounceInterval)
        self.pollingInterval = max(0.1, pollingInterval)
    }

    deinit {
        pollingTimer?.cancel()
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
            if let monitor = monitors[directoryURL] {
                guard monitor.fileURLs != uniqueFileURLs else { continue }
                monitor.fileURLs = uniqueFileURLs
                monitor.snapshots = monitor.snapshots.filter { uniqueFileURLs.contains($0.key) }
                monitor.scanGeneration &+= 1
                scheduleScan(for: directoryURL, delay: 0)
            } else {
                startMonitoring(directoryURL, fileURLs: uniqueFileURLs)
            }
        }

        updatePollingTimer()
    }

    private func startMonitoring(_ directoryURL: URL, fileURLs: Set<URL>) {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .attrib, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan(for: directoryURL)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        monitors[directoryURL] = DirectoryMonitor(source: source, fileURLs: fileURLs)
        source.resume()
        scheduleScan(for: directoryURL, delay: 0)
    }

    private func stopMonitoring(_ directoryURL: URL) {
        guard let monitor = monitors.removeValue(forKey: directoryURL) else { return }
        monitor.pendingScan?.cancel()
        monitor.source.cancel()
    }

    private func scheduleScan(for directoryURL: URL, delay: TimeInterval? = nil) {
        guard let monitor = monitors[directoryURL] else { return }
        monitor.pendingScan?.cancel()
        if delay == 0 {
            monitor.pendingScan = nil
            beginScan(for: directoryURL)
            return
        }
        let scan = DispatchWorkItem { [weak self] in
            self?.beginScan(for: directoryURL)
        }
        monitor.pendingScan = scan
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (delay ?? debounceInterval),
            execute: scan
        )
    }

    private func beginScan(for directoryURL: URL) {
        guard let monitor = monitors[directoryURL] else { return }
        monitor.pendingScan = nil
        monitor.scanGeneration &+= 1
        let generation = monitor.scanGeneration
        let fileURLs = monitor.fileURLs
        let previousSnapshots = monitor.snapshots

        snapshotQueue.async { [weak self] in
            let snapshots = Self.captureStates(for: fileURLs)
            Task { @MainActor [weak self] in
                self?.apply(
                    snapshots,
                    previousSnapshots: previousSnapshots,
                    generation: generation,
                    to: directoryURL
                )
            }
        }
    }

    private func apply(
        _ snapshots: [URL: FileState],
        previousSnapshots: [URL: FileState],
        generation: UInt64,
        to directoryURL: URL
    ) {
        guard let monitor = monitors[directoryURL],
              monitor.scanGeneration == generation else { return }
        monitor.snapshots = snapshots

        for fileURL in monitor.fileURLs {
            guard let previous = previousSnapshots[fileURL],
                  let current = snapshots[fileURL],
                  previous != current else { continue }
            onChange?(fileURL)
        }
    }

    private func updatePollingTimer() {
        guard monitors.isEmpty == false else {
            pollingTimer?.cancel()
            pollingTimer = nil
            return
        }
        guard pollingTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for directoryURL in self.monitors.keys {
                self.scheduleScan(for: directoryURL, delay: 0)
            }
        }
        pollingTimer = timer
        timer.resume()
    }

    nonisolated private static func captureStates(for fileURLs: Set<URL>) -> [URL: FileState] {
        Dictionary(uniqueKeysWithValues: fileURLs.map { fileURL in
            let state = PDFFileSnapshot(url: fileURL).map(FileState.existing) ?? .missing
            return (fileURL, state)
        })
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private func normalizedDirectoryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().standardizedFileURL
    }
}
