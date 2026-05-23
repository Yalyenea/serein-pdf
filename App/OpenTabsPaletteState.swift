import Foundation

enum OpenTabsPaletteMoveDirection {
    case left
    case right
    case up
    case down
}

struct OpenTabsPaletteItem: Equatable, Sendable {
    let sessionID: UUID
    let title: String
    let subtitle: String
    let pageText: String
    let pageIndex: Int
    let pageCount: Int
    let paneBadge: String?
    let isFocusedPane: Bool
    let isActive: Bool
    let isDirty: Bool

    init(
        session: DocumentSession,
        isActive: Bool,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary
    ) {
        if session.isBlank {
            self.sessionID = session.id
            self.title = session.title
            self.subtitle = "Blank tab"
            self.pageText = "Blank"
            self.pageIndex = 0
            self.pageCount = 0
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
            self.isActive = isActive
            self.isDirty = false
            return
        }

        let pageCount = session.pageCount
        let pageIndex = pageCount.map { $0 > 0 ? min(max(session.currentPageIndex, 0), $0 - 1) : 0 }
            ?? max(session.currentPageIndex, 0)
        self.sessionID = session.id
        self.title = session.title
        self.subtitle = session.url.path
        if let pageCount, pageCount > 0 {
            self.pageText = "Page \(pageIndex + 1) / \(pageCount)"
        } else {
            self.pageText = "Page \(pageIndex + 1)"
        }
        self.pageIndex = pageIndex
        self.pageCount = pageCount ?? 0
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
        self.isActive = isActive
        self.isDirty = session.isDirty
    }
}

struct OpenTabsPaletteState {
    private(set) var items: [OpenTabsPaletteItem]
    private(set) var highlightedIndex: Int?

    init(
        sessions: [DocumentSession],
        activeSessionID: UUID?,
        primarySessionID: UUID? = nil,
        secondarySessionID: UUID? = nil,
        focusedPane: ReaderPane = .primary
    ) {
        let items = sessions.map {
            OpenTabsPaletteItem(
                session: $0,
                isActive: $0.id == activeSessionID,
                primarySessionID: primarySessionID,
                secondarySessionID: secondarySessionID,
                focusedPane: focusedPane
            )
        }
        self.items = items
        self.highlightedIndex = Self.initialHighlightIndex(in: items)
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

    mutating func moveHighlight(_ direction: OpenTabsPaletteMoveDirection, columnCount: Int) {
        guard items.isEmpty == false else {
            highlightedIndex = nil
            return
        }

        let count = items.count
        let columns = max(1, columnCount)
        let current = highlightedIndex ?? 0
        let rowStart = (current / columns) * columns
        let rowEnd = min(rowStart + columns - 1, count - 1)

        highlightedIndex = switch direction {
        case .left:
            max(rowStart, current - 1)
        case .right:
            min(rowEnd, current + 1)
        case .up:
            max(0, current - columns)
        case .down:
            min(count - 1, current + columns)
        }
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
