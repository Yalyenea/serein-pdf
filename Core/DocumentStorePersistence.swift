import Foundation

struct PersistedDocumentStoreState: Codable, Equatable {
    struct SessionReference: Codable, Equatable {
        var url: URL
    }

    var sessions: [SessionReference]
    var activeSessionURL: URL?
    var tabPresentationMode: TabPresentationMode
    var isLeftSidebarVisible: Bool
    var isRightSidebarVisible: Bool
}

protocol DocumentStorePersistence {
    func loadState() throws -> PersistedDocumentStoreState?
    func saveState(_ state: PersistedDocumentStoreState) throws
}

struct UserDefaultsDocumentStorePersistence: DocumentStorePersistence {
    private static let stateKey = "SlatePDF.DocumentStoreState"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState() throws -> PersistedDocumentStoreState? {
        guard let data = userDefaults.data(forKey: Self.stateKey) else { return nil }
        return try JSONDecoder().decode(PersistedDocumentStoreState.self, from: data)
    }

    func saveState(_ state: PersistedDocumentStoreState) throws {
        let data = try JSONEncoder().encode(state)
        userDefaults.set(data, forKey: Self.stateKey)
    }
}
