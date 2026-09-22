import Foundation

enum OpenTabsPaletteActivationMode: Equatable {
    case explicitSelection
    case heldControl(reverse: Bool)
}

struct OpenTabsPaletteItem: Equatable, Sendable {
    let sessionID: UUID
    let title: String
    let subtitle: String
    let pageText: String
    let paneBadge: String?
    let isFocusedPane: Bool
    let isActive: Bool
    let isDirty: Bool
    let workspaceName: String?

    init(
        session: DocumentSession,
        isActive: Bool,
        workspaceName: String? = nil,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary
    ) {
        self.sessionID = session.id
        self.workspaceName = workspaceName
        self.title = session.title
        self.subtitle = session.isBlank ? "Blank tab" : session.url.path
        self.isActive = isActive
        self.isDirty = session.isBlank == false && session.isDirty
        if session.isBlank {
            self.pageText = "Blank"
        } else {
            let pageCount = session.pageCount
            let pageIndex = pageCount.map { $0 > 0 ? min(max(session.currentPageIndex, 0), $0 - 1) : 0 }
                ?? max(session.currentPageIndex, 0)
            if let pageCount, pageCount > 0 {
                self.pageText = "Page \(pageIndex + 1) / \(pageCount)"
            } else {
                self.pageText = "Page \(pageIndex + 1)"
            }
        }
        if session.id == primarySessionID {
            self.paneBadge = "P"
            self.isFocusedPane = focusedPane == .primary
        } else if session.id == secondarySessionID {
            self.paneBadge = "S"
            self.isFocusedPane = focusedPane == .secondary
        } else {
            self.paneBadge = nil
            self.isFocusedPane = false
        }
    }
}

struct OpenTabsPaletteState {
    private(set) var items: [OpenTabsPaletteItem] = []
    private(set) var highlightedIndex: Int?

    init(
        sessions: [DocumentSession],
        activeSessionID: UUID?,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary
    ) {
        replaceSessions(
            sessions,
            activeSessionID: activeSessionID,
            primarySessionID: primarySessionID,
            secondarySessionID: secondarySessionID,
            focusedPane: focusedPane
        )
    }

    var highlightedItem: OpenTabsPaletteItem? {
        guard let highlightedIndex,
              items.indices.contains(highlightedIndex) else { return nil }
        return items[highlightedIndex]
    }

    mutating func replaceSessions(
        _ sessions: [DocumentSession],
        activeSessionID: UUID?,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary
    ) {
        items = sessions.map {
            OpenTabsPaletteItem(
                session: $0,
                isActive: $0.id == activeSessionID,
                primarySessionID: primarySessionID,
                secondarySessionID: secondarySessionID,
                focusedPane: focusedPane
            )
        }
        highlightedIndex = Self.initialHighlightIndex(in: items)
    }

    mutating func replaceItems(_ items: [OpenTabsPaletteItem], activationMode: OpenTabsPaletteActivationMode) {
        self.items = items
        highlightedIndex = Self.initialHighlightIndex(in: items)
        if case let .heldControl(reverse) = activationMode {
            if items.contains(where: \.isActive) {
                moveHighlight(delta: reverse ? -1 : 1)
            } else if reverse, !items.isEmpty {
                highlightedIndex = items.count - 1
            }
        }
    }

    mutating func moveHighlight(delta: Int) {
        guard items.isEmpty == false else {
            highlightedIndex = nil
            return
        }

        let count = items.count
        let current = highlightedIndex ?? 0
        highlightedIndex = ((current + delta) % count + count) % count
    }

    mutating func setHighlightedIndex(_ index: Int?) {
        guard let index else {
            highlightedIndex = Self.initialHighlightIndex(in: items)
            return
        }
        guard items.indices.contains(index) else { return }
        highlightedIndex = index
    }

    private static func initialHighlightIndex(in items: [OpenTabsPaletteItem]) -> Int? {
        guard items.isEmpty == false else { return nil }
        return items.firstIndex(where: \.isActive) ?? 0
    }
}
