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
    let isActive: Bool
    let isDirty: Bool
    let workspaceName: String?

    init(
        session: DocumentSession,
        isActive: Bool,
        workspaceName: String? = nil
    ) {
        self.sessionID = session.id
        self.workspaceName = workspaceName
        self.title = session.title
        self.subtitle = session.isBlank ? L10n.text("Blank tab", "空白标签页") : session.url.path
        self.isActive = isActive
        self.isDirty = session.isBlank == false && session.isDirty
        if session.isBlank {
            self.pageText = L10n.text("Blank", "空白")
        } else {
            let pageCount = session.pageCount
            let pageIndex = pageCount.map { $0 > 0 ? min(max(session.currentPageIndex, 0), $0 - 1) : 0 }
                ?? max(session.currentPageIndex, 0)
            if let pageCount, pageCount > 0 {
                self.pageText = L10n.text("Page \(pageIndex + 1) / \(pageCount)", "第 \(pageIndex + 1) / \(pageCount) 页")
            } else {
                self.pageText = L10n.text("Page \(pageIndex + 1)", "第 \(pageIndex + 1) 页")
            }
        }
    }
}

struct OpenTabsPaletteState {
    private(set) var items: [OpenTabsPaletteItem] = []
    private(set) var highlightedIndex: Int?

    init(items: [OpenTabsPaletteItem] = [], activationMode: OpenTabsPaletteActivationMode = .explicitSelection) {
        replaceItems(items, activationMode: activationMode)
    }

    var highlightedItem: OpenTabsPaletteItem? {
        guard let highlightedIndex,
              items.indices.contains(highlightedIndex) else { return nil }
        return items[highlightedIndex]
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
