import Foundation

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
}

struct UserDefaultsReadingStateStore: ReadingStateStore {
    private static let stateKey = "SlatePDF.ReadingState"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState(for url: URL) throws -> PersistedReadingState? {
        try loadAllStates()[url.absoluteString]
    }

    func saveState(_ state: PersistedReadingState) throws {
        var states = try loadAllStates()
        states[state.url.absoluteString] = state
        let data = try JSONEncoder().encode(states)
        userDefaults.set(data, forKey: Self.stateKey)
    }

    private func loadAllStates() throws -> [String: PersistedReadingState] {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return [:] }
        return try JSONDecoder().decode([String: PersistedReadingState].self, from: data)
    }
}
