import Foundation

/// An outline index reused while the viewport moves. PDF coordinates increase upward.
struct OutlineLocationResolver {
    struct Entry {
        let node: OutlineNode
        let path: [Int]

        var level: Int { path.count - 1 }
    }

    let entries: [Entry]

    init(nodes: [OutlineNode]) {
        var entries: [Entry] = []
        func append(_ nodes: [OutlineNode], prefix: [Int]) {
            for (index, node) in nodes.enumerated() {
                let path = prefix + [index]
                entries.append(Entry(node: node, path: path))
                append(node.children, prefix: path)
            }
        }
        append(nodes, prefix: [])
        self.entries = entries
    }

    func activeEntryIndex(at position: ReadingPosition, sessionIDs: Set<UUID>) -> Int? {
        var bestIndex: Int?
        for (index, entry) in entries.enumerated() {
            if let sourceID = entry.node.sourceSessionID, sessionIDs.contains(sourceID) == false {
                continue
            }
            guard let page = entry.node.pageIndex, let point = entry.node.destinationPoint,
                  page < position.pageIndex || (page == position.pageIndex && point.y >= position.pointY)
            else { continue }

            if let bestIndex {
                let best = entries[bestIndex]
                let bestPage = best.node.pageIndex!
                let bestY = best.node.destinationPoint!.y
                guard page > bestPage || (page == bestPage && point.y < bestY)
                    || (page == bestPage && point.y == bestY && entry.level > best.level)
                else { continue }
            }
            bestIndex = index
        }
        return bestIndex
    }
}

struct OutlineReadingLocation: Equatable {
    let sessionID: UUID
    let sourceSessionID: UUID
    let position: ReadingPosition

    var sessionIDs: Set<UUID> { [sessionID, sourceSessionID] }

    @MainActor
    static func capture(from store: DocumentStore, windowID: UUID) -> OutlineReadingLocation? {
        guard let session = store.activeSession(in: windowID) else { return nil }
        return OutlineReadingLocation(
            sessionID: session.id,
            sourceSessionID: store.publicSessionID(forDisplayedSessionID: session.id, in: windowID) ?? session.id,
            position: session.lastReadPosition
        )
    }
}
