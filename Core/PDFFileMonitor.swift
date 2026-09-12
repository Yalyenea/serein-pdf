import Darwin
import Dispatch
import Foundation
import os

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
    typealias SnapshotProvider = @Sendable (URL) -> PDFFileSnapshot?

    private enum FileState: Equatable, Sendable {
        case missing
        case existing(PDFFileSnapshot)
    }

    private final class DirectoryMonitor: @unchecked Sendable {
        var source: DispatchSourceFileSystemObject?
        var watchedDirectoryURL: URL?
        var fileURLs: Set<URL>
        var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
        var snapshots: [URL: FileState] = [:]
        var scanGeneration: UInt64 = 0
        var pendingScan: DispatchWorkItem?
        var pendingURLs: Set<URL> = []
        var isScanning = false

        init(fileURLs: Set<URL>) {
            self.fileURLs = fileURLs
        }
    }

    var onChange: ChangeHandler?

    private static let logger = Logger(subsystem: "local.yfff.Serein", category: "PDFFileMonitor")
    private let debounceInterval: TimeInterval
    private let snapshotProvider: SnapshotProvider
    private let snapshotQueue = DispatchQueue(
        label: "local.yfff.Serein.PDFFileMonitor.snapshots",
        qos: .utility
    )
    private var monitors: [URL: DirectoryMonitor] = [:]

    init(
        debounceInterval: TimeInterval = 0.25,
        snapshotProvider: @escaping SnapshotProvider = { PDFFileSnapshot(url: $0) }
    ) {
        self.debounceInterval = max(0, debounceInterval)
        self.snapshotProvider = snapshotProvider
    }

    deinit {
        for monitor in monitors.values {
            monitor.pendingScan?.cancel()
            monitor.source?.cancel()
            for source in monitor.fileSources.values {
                source.cancel()
            }
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
                updateFileSources(for: directoryURL, monitor: monitor)
                scheduleScan(for: directoryURL, delay: 0)
            } else {
                startMonitoring(directoryURL, fileURLs: uniqueFileURLs)
            }
        }
    }

    private func startMonitoring(_ directoryURL: URL, fileURLs: Set<URL>) {
        let monitor = DirectoryMonitor(fileURLs: fileURLs)
        monitors[directoryURL] = monitor
        updateDirectorySource(for: directoryURL, monitor: monitor)
        updateFileSources(for: directoryURL, monitor: monitor)
        scheduleScan(for: directoryURL, delay: 0)
    }

    private func stopMonitoring(_ directoryURL: URL) {
        guard let monitor = monitors.removeValue(forKey: directoryURL) else { return }
        monitor.pendingScan?.cancel()
        monitor.source?.cancel()
        for source in monitor.fileSources.values {
            source.cancel()
        }
    }

    @discardableResult
    private func updateDirectorySource(for directoryURL: URL, monitor: DirectoryMonitor) -> Bool {
        var candidate = directoryURL
        while true {
            if candidate == monitor.watchedDirectoryURL, monitor.source != nil { return false }
            let descriptor = open(candidate.path, O_EVTONLY)
            if descriptor >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor,
                    eventMask: [.write, .attrib, .delete, .rename, .revoke],
                    queue: .main
                )
                source.setEventHandler { [weak self, weak monitor] in
                    guard let self, let monitor,
                          self.monitors[directoryURL] === monitor,
                          let currentSource = monitor.source,
                          currentSource.handle == descriptor else { return }
                    if currentSource.data.intersection([.delete, .rename, .revoke]).isEmpty == false {
                        monitor.source?.cancel()
                        monitor.source = nil
                        monitor.watchedDirectoryURL = nil
                        for fileSource in monitor.fileSources.values {
                            fileSource.cancel()
                        }
                        monitor.fileSources.removeAll()
                        monitor.scanGeneration &+= 1
                        self.updateDirectorySource(for: directoryURL, monitor: monitor)
                    } else if monitor.watchedDirectoryURL != directoryURL,
                              self.updateDirectorySource(for: directoryURL, monitor: monitor) == false {
                        return
                    }
                    self.scheduleScan(for: directoryURL)
                }
                source.setCancelHandler { close(descriptor) }
                monitor.source?.cancel()
                monitor.source = source
                monitor.watchedDirectoryURL = candidate
                source.resume()
                return true
            }
            let openError = errno
            guard openError == ENOENT || openError == ENOTDIR,
                  candidate.path != "/" else {
                Self.logger.error("Cannot monitor PDF directory \(candidate.path, privacy: .public): errno \(openError)")
                return false
            }
            // Keep watching the nearest existing ancestor while a removed directory is rebuilt.
            candidate.deleteLastPathComponent()
        }
    }

    private func updateFileSources(for directoryURL: URL, monitor: DirectoryMonitor) {
        for fileURL in monitor.fileSources.keys where monitor.fileURLs.contains(fileURL) == false {
            monitor.fileSources.removeValue(forKey: fileURL)?.cancel()
        }
        for fileURL in monitor.fileURLs where monitor.fileSources[fileURL] == nil {
            let descriptor = open(fileURL.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self, weak monitor] in
                guard let self, let monitor,
                      self.monitors[directoryURL] === monitor,
                      let currentSource = monitor.fileSources[fileURL],
                      currentSource.handle == descriptor else { return }
                if currentSource.data.intersection([.delete, .rename, .revoke]).isEmpty == false {
                    monitor.fileSources.removeValue(forKey: fileURL)?.cancel()
                }
                self.scheduleScan(for: directoryURL, fileURLs: [fileURL])
            }
            source.setCancelHandler {
                close(descriptor)
            }
            monitor.fileSources[fileURL] = source
            source.resume()
        }
    }

    private func scheduleScan(
        for directoryURL: URL,
        fileURLs: Set<URL>? = nil,
        delay: TimeInterval? = nil
    ) {
        guard let monitor = monitors[directoryURL] else { return }
        monitor.pendingScan?.cancel()
        monitor.pendingURLs.formUnion(fileURLs ?? monitor.fileURLs)
        guard monitor.isScanning == false else { return }
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
        guard monitor.isScanning == false else { return }
        let fileURLs = monitor.pendingURLs.intersection(monitor.fileURLs)
        monitor.pendingURLs.removeAll(keepingCapacity: true)
        guard fileURLs.isEmpty == false else { return }
        updateFileSources(for: directoryURL, monitor: monitor)
        monitor.isScanning = true
        let generation = monitor.scanGeneration

        snapshotQueue.async { [weak self, snapshotProvider] in
            let snapshots = Self.captureStates(for: fileURLs, snapshotProvider: snapshotProvider)
            Task { @MainActor [weak self] in
                self?.apply(
                    snapshots,
                    generation: generation,
                    monitor: monitor,
                    to: directoryURL
                )
            }
        }
    }

    private func apply(
        _ snapshots: [URL: FileState],
        generation: UInt64,
        monitor: DirectoryMonitor,
        to directoryURL: URL
    ) {
        guard monitors[directoryURL] === monitor else { return }
        if monitor.scanGeneration == generation {
            for (fileURL, current) in snapshots where monitor.fileURLs.contains(fileURL) {
                let previous = monitor.snapshots.updateValue(current, forKey: fileURL)
                if let previous, previous != current {
                    onChange?(fileURL)
                }
            }
        }
        monitor.isScanning = false
        if monitor.pendingURLs.isEmpty == false {
            scheduleScan(for: directoryURL, fileURLs: [], delay: 0)
        }
    }

    nonisolated private static func captureStates(
        for fileURLs: Set<URL>,
        snapshotProvider: SnapshotProvider
    ) -> [URL: FileState] {
        Dictionary(uniqueKeysWithValues: fileURLs.map { fileURL in
            let state = snapshotProvider(fileURL).map(FileState.existing) ?? .missing
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
