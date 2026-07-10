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

final class UserDefaultsReadingStateStore: ReadingStateStore {
    static let maxEntries = 500
    static let debounceInterval: TimeInterval = 0.75
    static let stateKey = "Serein.ReadingState"

    private static let logger = Logger(subsystem: "local.yfff.Serein", category: "ReadingStateStore")

    private let userDefaults: UserDefaults
    private let maxEntries: Int
    private let debounceInterval: TimeInterval
    private var cache: [String: PersistedReadingState] = [:]
    /// Most-recently-used keys last.
    private var lruOrder: [String] = []
    private var isCacheLoaded = false
    private var isDirty = false
    private var flushWorkItem: DispatchWorkItem?

    init(
        userDefaults: UserDefaults = .standard,
        maxEntries: Int = UserDefaultsReadingStateStore.maxEntries,
        debounceInterval: TimeInterval = UserDefaultsReadingStateStore.debounceInterval
    ) {
        self.userDefaults = userDefaults
        self.maxEntries = max(1, maxEntries)
        self.debounceInterval = max(0, debounceInterval)
    }

    deinit {
        flushWorkItem?.cancel()
        if isDirty {
            try? writeCacheToUserDefaults()
        }
    }

    func loadState(for url: URL) throws -> PersistedReadingState? {
        try ensureCacheLoaded()
        let key = url.absoluteString
        guard let state = cache[key] else { return nil }
        touchLRU(key)
        return state
    }

    func saveState(_ state: PersistedReadingState) throws {
        try ensureCacheLoaded()
        let key = state.url.absoluteString
        cache[key] = state
        touchLRU(key)
        pruneIfNeeded()
        isDirty = true
        scheduleFlush()
    }

    func flush() throws {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        try persistIfDirty()
    }

    private func ensureCacheLoaded() throws {
        guard isCacheLoaded == false else { return }
        if let data = userDefaults.data(forKey: Self.stateKey) {
            let decoded = try JSONDecoder().decode([String: PersistedReadingState].self, from: data)
            cache = decoded
            lruOrder = Array(decoded.keys)
            if lruOrder.count > maxEntries {
                pruneIfNeeded()
                try writeCacheToUserDefaults()
                isDirty = false
            }
        }
        isCacheLoaded = true
    }

    private func touchLRU(_ key: String) {
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }

    private func pruneIfNeeded() {
        while lruOrder.count > maxEntries {
            let evicted = lruOrder.removeFirst()
            cache.removeValue(forKey: evicted)
            isDirty = true
        }
    }

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        if debounceInterval <= 0 {
            flushIgnoringErrors()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushIgnoringErrors()
        }
        flushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushIgnoringErrors() {
        do {
            try persistIfDirty()
        } catch {
            Self.logger.error("Failed to persist reading state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistIfDirty() throws {
        guard isDirty else { return }
        try writeCacheToUserDefaults()
        isDirty = false
    }

    private func writeCacheToUserDefaults() throws {
        let data = try JSONEncoder().encode(cache)
        userDefaults.set(data, forKey: Self.stateKey)
    }
}
