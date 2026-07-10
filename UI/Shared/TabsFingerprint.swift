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
}
