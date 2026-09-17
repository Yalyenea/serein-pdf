import Foundation
import os

struct PersistedReadingState: Codable, Equatable, Sendable {
    var url: URL
    var displayMode: ReaderDisplayMode
    var scaleMode: ReaderScaleMode
    var scaleFactor: CGFloat
    var readingPosition: ReadingPosition
    var leftSidebarWidth: CGFloat?
    var rightSidebarWidth: CGFloat?
    // Older reading records omit this field; DocumentStore treats nil as unlocked.
    var isHorizontalPanLocked: Bool? = false
}

protocol ReadingStateStore {
    func loadState(for url: URL) throws -> PersistedReadingState?
    func saveState(_ state: PersistedReadingState) throws
    /// Forces any pending debounced writes to disk. Default is a no-op.
    func flush() throws
}

extension ReadingStateStore {
    func flush() throws {}
}

final class UserDefaultsReadingStateStore: ReadingStateStore, @unchecked Sendable {
    static let maxEntries = 500
    static let debounceInterval: TimeInterval = 0.75
    static let stateKey = "Serein.ReadingState"
    static let lruKey = "Serein.ReadingState.LRU"

    private static let logger = Logger(subsystem: "local.yfff.Serein", category: "ReadingStateStore")

    private let userDefaults: UserDefaults
    private let sendableUserDefaults: SendableUserDefaults
    private let maxEntries: Int
    private let debounceInterval: TimeInterval
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "local.yfff.Serein.ReadingStateStore.persistence",
        qos: .utility
    )
    private let persistenceQueueKey = DispatchSpecificKey<UInt8>()
    private var cache: [String: PersistedReadingState] = [:]
    /// Most-recently-used keys last.
    private var lruOrder: [String] = []
    private var isCacheLoaded = false
    private var isDirty = false
    private var mutationGeneration: UInt64 = 0
    private var scheduleGeneration: UInt64 = 0
    private var flushWorkItem: DispatchWorkItem?

    init(
        userDefaults: UserDefaults = .standard,
        maxEntries: Int = UserDefaultsReadingStateStore.maxEntries,
        debounceInterval: TimeInterval = UserDefaultsReadingStateStore.debounceInterval
    ) {
        self.userDefaults = userDefaults
        self.sendableUserDefaults = SendableUserDefaults(userDefaults)
        self.maxEntries = max(1, maxEntries)
        self.debounceInterval = max(0, debounceInterval)
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: 1)
    }

    deinit {
        lock.lock()
        flushWorkItem?.cancel()
        lock.unlock()
        try? flush()
    }

    func loadState(for url: URL) throws -> PersistedReadingState? {
        lock.lock()
        do {
            try ensureCacheLoadedLocked()
        } catch {
            lock.unlock()
            throw error
        }
        let key = url.absoluteString
        let state = cache[key]
        if state != nil, lruOrder.last != key {
            touchLRULocked(key)
            markDirtyLocked()
        }
        let flushImmediately = isDirty && debounceInterval <= 0
        scheduleFlushLocked()
        lock.unlock()
        if flushImmediately {
            try flush()
        }
        return state
    }

    func saveState(_ state: PersistedReadingState) throws {
        lock.lock()
        do {
            try ensureCacheLoadedLocked()
        } catch {
            lock.unlock()
            throw error
        }
        let key = state.url.absoluteString
        let cacheChanged = cache[key] != state
        let lruChanged = lruOrder.last != key
        guard cacheChanged || lruChanged else {
            lock.unlock()
            return
        }
        if cacheChanged {
            cache[key] = state
        }
        if lruChanged {
            touchLRULocked(key)
        }
        pruneIfNeededLocked()
        markDirtyLocked()
        let flushImmediately = debounceInterval <= 0
        scheduleFlushLocked()
        lock.unlock()
        if flushImmediately {
            try flush()
        }
    }

    func flush() throws {
        lock.lock()
        flushWorkItem?.cancel()
        flushWorkItem = nil
        scheduleGeneration &+= 1
        guard let snapshot = persistenceSnapshotLocked() else {
            lock.unlock()
            return
        }
        lock.unlock()

        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            try Self.write(snapshot, to: userDefaults)
        } else {
            let completion = DispatchSemaphore(value: 0)
            let result = PersistenceResult()
            persistenceQueue.async { [sendableUserDefaults] in
                do {
                    try Self.write(snapshot, to: sendableUserDefaults.value)
                } catch {
                    result.error = error
                }
                completion.signal()
            }
            completion.wait()
            if let error = result.error {
                throw error
            }
        }
        markPersisted(generation: snapshot.generation)
    }

    private func ensureCacheLoadedLocked() throws {
        guard isCacheLoaded == false else { return }
        if let data = userDefaults.data(forKey: Self.stateKey) {
            let decoded = try JSONDecoder().decode([String: PersistedReadingState].self, from: data)
            cache = decoded
            let persistedOrder: [String]
            if let lruData = userDefaults.data(forKey: Self.lruKey) {
                persistedOrder = try JSONDecoder().decode([String].self, from: lruData)
            } else {
                // One-time migration from the original dictionary-only format.
                persistedOrder = decoded.keys.sorted()
            }
            lruOrder = normalizedLRUOrder(persistedOrder, cacheKeys: Set(decoded.keys))
            let needsMigration = userDefaults.data(forKey: Self.lruKey) == nil && decoded.isEmpty == false
            let needsNormalization = lruOrder != persistedOrder
            if lruOrder.count > maxEntries {
                pruneIfNeededLocked()
            }
            if needsMigration || needsNormalization || isDirty {
                markDirtyLocked()
            }
        }
        isCacheLoaded = true
    }

    private func normalizedLRUOrder(_ order: [String], cacheKeys: Set<String>) -> [String] {
        var seen: Set<String> = []
        let knownOrder = order.filter { cacheKeys.contains($0) && seen.insert($0).inserted }
        let missingKeys = cacheKeys.subtracting(seen).sorted()
        return missingKeys + knownOrder
    }

    private func touchLRULocked(_ key: String) {
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }

    private func pruneIfNeededLocked() {
        while lruOrder.count > maxEntries {
            let evicted = lruOrder.removeFirst()
            cache.removeValue(forKey: evicted)
            isDirty = true
        }
    }

    private func markDirtyLocked() {
        isDirty = true
        mutationGeneration &+= 1
    }

    private func scheduleFlushLocked() {
        guard isDirty else { return }
        flushWorkItem?.cancel()
        if debounceInterval <= 0 {
            return
        }
        scheduleGeneration &+= 1
        let scheduledGeneration = scheduleGeneration
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistScheduled(generation: scheduledGeneration)
        }
        flushWorkItem = workItem
        persistenceQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func persistScheduled(generation scheduledGeneration: UInt64) {
        lock.lock()
        guard self.scheduleGeneration == scheduledGeneration,
              let snapshot = persistenceSnapshotLocked() else {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            try Self.write(snapshot, to: userDefaults)
            markPersisted(generation: snapshot.generation)
        } catch {
            Self.logger.error("Failed to persist reading state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistenceSnapshotLocked() -> PersistenceSnapshot? {
        guard isDirty else { return nil }
        return PersistenceSnapshot(
            cache: cache,
            lruOrder: lruOrder,
            generation: mutationGeneration
        )
    }

    private func markPersisted(generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if mutationGeneration == generation {
            isDirty = false
            flushWorkItem = nil
        }
    }

    private static func write(_ snapshot: PersistenceSnapshot, to userDefaults: UserDefaults) throws {
        let encoder = JSONEncoder()
        userDefaults.set(try encoder.encode(snapshot.cache), forKey: Self.stateKey)
        userDefaults.set(try encoder.encode(snapshot.lruOrder), forKey: Self.lruKey)
    }

    private struct PersistenceSnapshot: Sendable {
        let cache: [String: PersistedReadingState]
        let lruOrder: [String]
        let generation: UInt64
    }

    private final class PersistenceResult: @unchecked Sendable {
        var error: Error?
    }

    private final class SendableUserDefaults: @unchecked Sendable {
        let value: UserDefaults

        init(_ value: UserDefaults) {
            self.value = value
        }
    }
}
