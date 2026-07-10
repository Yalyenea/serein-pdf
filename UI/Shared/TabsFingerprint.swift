import Foundation

/// Snapshot of tab-list UI inputs. Skip rebuild when equal across store notifications.
struct TabsFingerprint: Equatable {
    struct Item: Equatable {
        var id: UUID
        var title: String
        var isDirty: Bool
    }

    var activeSessionID: UUID?
    var selectedSessionIDs: Set<UUID>
    var continuousSessionIDs: [UUID]
    var items: [Item]
    var recentURLs: [URL]
    var showRecentSection: Bool

    @MainActor
    static func capture(
        from store: DocumentStore,
        windowID: UUID,
        recentURLs: [URL] = [],
        showRecentSection: Bool = false
    ) -> TabsFingerprint {
        let sessions = store.sessions(in: windowID)
        return TabsFingerprint(
            activeSessionID: store.activeSessionID(in: windowID),
            selectedSessionIDs: store.selectedSessionIDs(in: windowID),
            continuousSessionIDs: store.continuousReadingSessionIDs(in: windowID),
            items: sessions.map { Item(id: $0.id, title: $0.title, isDirty: $0.isDirty) },
            recentURLs: recentURLs,
            showRecentSection: showRecentSection
        )
    }
}
