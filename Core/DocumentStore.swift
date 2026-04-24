import AppKit
import Foundation
import PDFKit

enum TabPresentationMode: String, CaseIterable, Codable, Sendable {
    case verticalSidebar
    case horizontalTitlebar
}

extension Notification.Name {
    static let documentStoreDidChange = Notification.Name("DocumentStore.didChange")
}

@MainActor
final class DocumentStore {
    private let persistence: DocumentStorePersistence
    private let readingStateStore: ReadingStateStore
    private let recentFilesStore: RecentFilesStore
    private(set) var appConfiguration: AppConfiguration
    private(set) var sessions: [DocumentSession] = []
    private(set) var recentDocumentURLs: [URL] = []
    private(set) var windowWorkspaces: [WindowWorkspace]
    private var splitComparisonSessionIDs: Set<UUID> = []
    private static let recentlyClosedLimit = 10
    static let undoStackLimit = 50

    init(
        persistence: DocumentStorePersistence = UserDefaultsDocumentStorePersistence(),
        readingStateStore: ReadingStateStore = UserDefaultsReadingStateStore(),
        recentFilesStore: RecentFilesStore = UserDefaultsRecentFilesStore(),
        appConfiguration: AppConfiguration = .default
    ) {
        self.persistence = persistence
        self.readingStateStore = readingStateStore
        self.recentFilesStore = recentFilesStore
        self.appConfiguration = appConfiguration
        self.windowWorkspaces = [WindowWorkspace()]
        recentDocumentURLs = (try? recentFilesStore.loadRecentFiles()) ?? []
    }

    var defaultWindowID: UUID {
        if let id = windowWorkspaces.first?.id {
            return id
        }
        let fallback = WindowWorkspace()
        windowWorkspaces = [fallback]
        return fallback.id
    }

    var activeSessionID: UUID? {
        activeSessionID(in: defaultWindowID)
    }

    var activeSession: DocumentSession? {
        activeSession(in: defaultWindowID)
    }

    var tabPresentationMode: TabPresentationMode {
        windowWorkspace(for: defaultWindowID)?.tabPresentationMode ?? .verticalSidebar
    }

    func tabPresentationMode(in windowID: UUID) -> TabPresentationMode {
        windowWorkspace(for: windowID)?.tabPresentationMode ?? .verticalSidebar
    }

    var isLeftSidebarVisible: Bool {
        windowWorkspace(for: defaultWindowID)?.isLeftSidebarVisible ?? true
    }

    func isLeftSidebarVisible(in windowID: UUID) -> Bool {
        windowWorkspace(for: windowID)?.isLeftSidebarVisible ?? true
    }

    var isRightSidebarVisible: Bool {
        windowWorkspace(for: defaultWindowID)?.isRightSidebarVisible ?? true
    }

    func isRightSidebarVisible(in windowID: UUID) -> Bool {
        windowWorkspace(for: windowID)?.isRightSidebarVisible ?? true
    }

    var recentlyClosedURLs: [URL] {
        windowWorkspace(for: defaultWindowID)?.recentlyClosedURLs ?? []
    }

    func recentlyClosedURLs(in windowID: UUID) -> [URL] {
        windowWorkspace(for: windowID)?.recentlyClosedURLs ?? []
    }

    func windowIDs() -> [UUID] {
        windowWorkspaces.map(\.id)
    }

    func windowWorkspace(for windowID: UUID) -> WindowWorkspace? {
        windowWorkspaces.first { $0.id == windowID }
    }

    func sessions(in windowID: UUID) -> [DocumentSession] {
        guard let workspace = windowWorkspace(for: windowID) else { return [] }
        return workspace.sessionIDs.compactMap(session(for:))
    }

    func sessionCount(in windowID: UUID) -> Int {
        windowWorkspace(for: windowID)?.sessionIDs.count ?? 0
    }

    func exclusiveDirtySessions(in windowID: UUID) -> [DocumentSession] {
        sessions(in: windowID).filter { session in
            session.isDirty && isSessionReferencedOutsideWindow(session.id, excluding: windowID) == false
        }
    }

    func createWindow(copyingFrom sourceWindowID: UUID? = nil) -> UUID {
        let source = sourceWindowID.flatMap(windowWorkspace(for:)) ?? windowWorkspaces.first ?? WindowWorkspace()
        var copy = WindowWorkspace(
            sessionIDs: [],
            tabPresentationMode: source.tabPresentationMode,
            isLeftSidebarVisible: source.isLeftSidebarVisible,
            isRightSidebarVisible: source.isRightSidebarVisible,
            rightSidebarMode: .outline,
            searchQuery: "",
            searchScope: .currentDocument,
            isSplitEnabled: false,
            primarySessionID: nil,
            secondarySessionID: nil,
            focusedPane: .primary,
            recentlyClosedURLs: []
        )
        normalizeWorkspace(&copy)
        windowWorkspaces.append(copy)
        notifyChange()
        return copy.id
    }

    func closeWindow(id windowID: UUID) {
        guard windowWorkspaces.count > 1,
              let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        windowWorkspaces.remove(at: index)
        removeUnreferencedSessions()
        notifyChange()
    }

    func activeSessionID(in windowID: UUID) -> UUID? {
        windowWorkspace(for: windowID)?.activeSessionID
    }

    func activeSession(in windowID: UUID) -> DocumentSession? {
        guard let sessionID = activeSessionID(in: windowID) else { return nil }
        return session(for: sessionID)
    }

    func displayedSessionID(for pane: ReaderPane, in windowID: UUID) -> UUID? {
        guard let workspace = windowWorkspace(for: windowID) else { return nil }
        switch pane {
        case .primary:
            return workspace.primarySessionID
        case .secondary:
            return workspace.isSplitEnabled ? workspace.secondarySessionID : nil
        }
    }

    func focusedPane(in windowID: UUID) -> ReaderPane {
        windowWorkspace(for: windowID)?.focusedPane ?? .primary
    }

    func isSplitEnabled(in windowID: UUID) -> Bool {
        windowWorkspace(for: windowID)?.isSplitEnabled ?? false
    }

    func rightSidebarMode(in windowID: UUID) -> RightSidebarMode {
        windowWorkspace(for: windowID)?.rightSidebarMode ?? .outline
    }

    func searchQuery(in windowID: UUID) -> String {
        windowWorkspace(for: windowID)?.searchQuery ?? ""
    }

    func searchScope(in windowID: UUID) -> SearchScope {
        windowWorkspace(for: windowID)?.searchScope ?? .currentDocument
    }

    @discardableResult
    func open(documentAt url: URL) throws -> DocumentSession {
        try open(documentAt: url, in: defaultWindowID)
    }

    @discardableResult
    func open(documentAt url: URL, in windowID: UUID, targetPane: ReaderPane? = nil) throws -> DocumentSession {
        let session = try makeSession(documentAt: url)
        sessions.append(session)
        recentDocumentURLs = (try? recentFilesStore.recordOpen(for: url)) ?? recentDocumentURLs
        attach(sessionID: session.id, to: windowID)
        activate(sessionID: session.id, in: windowID, targetPane: targetPane)
        updateSearchCachesAfterOpen(for: session.id)
        notifyChange()
        return session
    }

    func close(sessionID: UUID) {
        close(sessionID: sessionID, from: defaultWindowID)
    }

    func close(sessionID: UUID, from windowID: UUID) {
        guard let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let closedURL = session(for: sessionID)?.url,
              let sessionIndexInWindow = windowWorkspaces[workspaceIndex].sessionIDs.firstIndex(of: sessionID) else { return }

        windowWorkspaces[workspaceIndex].sessionIDs.remove(at: sessionIndexInWindow)
        pushRecentlyClosed(closedURL, in: windowID)
        let remainingWindowSessionIDs = windowWorkspaces[workspaceIndex].sessionIDs
        let preferredSessionID = remainingWindowSessionIDs.isEmpty
            ? nil
            : remainingWindowSessionIDs[min(max(sessionIndexInWindow - 1, 0), remainingWindowSessionIDs.count - 1)]
        if isSessionReferenced(sessionID) == false {
            discardSession(sessionID)
        }
        normalizeWorkspace(&windowWorkspaces[workspaceIndex], preferredSessionID: preferredSessionID)
        notifyChange()
    }

    func popRecentlyClosed() -> URL? {
        popRecentlyClosed(in: defaultWindowID)
    }

    func popRecentlyClosed(in windowID: UUID) -> URL? {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].recentlyClosedURLs.isEmpty == false else { return nil }
        let url = windowWorkspaces[index].recentlyClosedURLs.removeLast()
        notifyChange()
        return url
    }

    func closeActiveSession() {
        closeActiveSession(in: defaultWindowID)
    }

    func closeActiveSession(in windowID: UUID) {
        guard let activeSessionID = activeSessionID(in: windowID) else { return }
        close(sessionID: activeSessionID, from: windowID)
    }

    func activate(sessionID: UUID) {
        activate(sessionID: sessionID, in: defaultWindowID)
    }

    func activate(sessionID: UUID, in windowID: UUID, targetPane: ReaderPane? = nil) {
        guard session(for: sessionID) != nil,
              let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }

        var workspace = windowWorkspaces[workspaceIndex]
        var duplicatedSessionID: UUID?
        guard workspace.sessionIDs.contains(sessionID) else { return }
        let pane = resolvedTargetPane(for: targetPane, in: workspace)

        if pane == .secondary, workspace.isSplitEnabled == false {
            workspace.isSplitEnabled = true
            if workspace.primarySessionID == nil {
                workspace.primarySessionID = sessionID
            }
            if workspace.secondarySessionID == nil {
                workspace.secondarySessionID = preferredSecondarySession(in: workspace, excluding: workspace.primarySessionID)
            }
        }

        if workspace.isSplitEnabled {
            let oppositeSessionID = pane == .primary ? workspace.secondarySessionID : workspace.primarySessionID
            let targetSessionID: UUID
            if oppositeSessionID == sessionID,
               let existingCloneID = existingSplitComparisonSessionID(
                   for: sessionID,
                   in: workspace,
                   excluding: oppositeSessionID
               ) {
                targetSessionID = existingCloneID
            } else if oppositeSessionID == sessionID,
                      let cloneID = duplicateSessionForSplitComparison(from: sessionID) {
                targetSessionID = cloneID
                duplicatedSessionID = cloneID
                workspace.sessionIDs.append(cloneID)
            } else {
                targetSessionID = sessionID
            }
            workspace.setSession(targetSessionID, for: pane)
            workspace.focusedPane = pane
        } else {
            workspace.primarySessionID = sessionID
            workspace.secondarySessionID = nil
            workspace.focusedPane = .primary
        }

        normalizeWorkspace(&workspace)
        windowWorkspaces[workspaceIndex] = workspace
        if let duplicatedSessionID {
            updateSearchCachesAfterOpen(for: duplicatedSessionID)
        }
        notifyChange()
    }

    func activatePreviousSession() {
        activatePreviousSession(in: defaultWindowID)
    }

    func activatePreviousSession(in windowID: UUID) {
        guard let workspace = windowWorkspace(for: windowID),
              let activeSessionID = workspace.activeSessionID,
              let currentIndex = workspace.sessionIDs.firstIndex(of: activeSessionID),
              workspace.sessionIDs.count > 1 else { return }
        let previousIndex = (currentIndex - 1 + workspace.sessionIDs.count) % workspace.sessionIDs.count
        activate(sessionID: workspace.sessionIDs[previousIndex], in: windowID)
    }

    func activateNextSession() {
        activateNextSession(in: defaultWindowID)
    }

    func activateNextSession(in windowID: UUID) {
        guard let workspace = windowWorkspace(for: windowID),
              let activeSessionID = workspace.activeSessionID,
              let currentIndex = workspace.sessionIDs.firstIndex(of: activeSessionID),
              workspace.sessionIDs.count > 1 else { return }
        let nextIndex = (currentIndex + 1) % workspace.sessionIDs.count
        activate(sessionID: workspace.sessionIDs[nextIndex], in: windowID)
    }

    func setFocusedPane(_ pane: ReaderPane, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        var workspace = windowWorkspaces[index]
        guard workspace.isSplitEnabled else {
            workspace.focusedPane = .primary
            windowWorkspaces[index] = workspace
            return
        }
        let resolvedPane = displayedSessionID(for: pane, in: windowID) == nil ? pane.other : pane
        guard workspace.focusedPane != resolvedPane else { return }
        workspace.focusedPane = resolvedPane
        windowWorkspaces[index] = workspace
        notifyChange()
    }

    func setSplitEnabled(_ isEnabled: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        var workspace = windowWorkspaces[index]
        var duplicatedSessionID: UUID?
        guard workspace.isSplitEnabled != isEnabled else { return }
        workspace.isSplitEnabled = isEnabled

        if isEnabled {
            if workspace.primarySessionID == nil {
                workspace.primarySessionID = workspace.sessionIDs.first
            }
            if workspace.secondarySessionID == nil || workspace.secondarySessionID == workspace.primarySessionID {
                if let secondary = preferredSecondarySession(in: workspace, excluding: workspace.primarySessionID),
                   secondary != workspace.primarySessionID {
                    workspace.secondarySessionID = secondary
                } else if let primarySessionID = workspace.primarySessionID,
                          let existingCloneID = existingSplitComparisonSessionID(
                              for: primarySessionID,
                              in: workspace,
                              excluding: primarySessionID
                          ) {
                    workspace.secondarySessionID = existingCloneID
                } else if let primarySessionID = workspace.primarySessionID,
                          let cloneID = duplicateSessionForSplitComparison(from: primarySessionID) {
                    duplicatedSessionID = cloneID
                    workspace.sessionIDs.append(cloneID)
                    workspace.secondarySessionID = cloneID
                } else {
                    workspace.secondarySessionID = workspace.primarySessionID
                }
            }
        } else {
            let activeBeforeCollapse = workspace.activeSessionID
            var preferredPrimaryID = activeBeforeCollapse ?? workspace.primarySessionID
            if let primarySessionID = workspace.primarySessionID,
               let secondarySessionID = workspace.secondarySessionID,
               let primaryURL = session(for: primarySessionID)?.url,
               let secondaryURL = session(for: secondarySessionID)?.url,
               primaryURL == secondaryURL {
                if splitComparisonSessionIDs.contains(primarySessionID),
                   splitComparisonSessionIDs.contains(secondarySessionID) == false {
                    preferredPrimaryID = secondarySessionID
                } else if splitComparisonSessionIDs.contains(secondarySessionID),
                          splitComparisonSessionIDs.contains(primarySessionID) == false,
                          preferredPrimaryID == secondarySessionID {
                    preferredPrimaryID = primarySessionID
                }
            }
            workspace.primarySessionID = preferredPrimaryID
            workspace.sessionIDs.removeAll { sessionID in
                splitComparisonSessionIDs.contains(sessionID) && sessionID != workspace.primarySessionID
            }
            workspace.secondarySessionID = nil
            workspace.focusedPane = .primary
        }

        normalizeWorkspace(&workspace)
        windowWorkspaces[index] = workspace
        removeUnreferencedSessions()
        if let duplicatedSessionID {
            updateSearchCachesAfterOpen(for: duplicatedSessionID)
        }
        notifyChange()
    }

    func setTabPresentationMode(_ mode: TabPresentationMode) {
        setTabPresentationMode(mode, in: defaultWindowID)
    }

    func setTabPresentationMode(_ mode: TabPresentationMode, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        var workspace = windowWorkspaces[index]
        guard workspace.tabPresentationMode != mode else { return }
        workspace.tabPresentationMode = mode

        let tabsPaneShouldBeVisible = mode == .verticalSidebar
        let tabsOnRight = appConfiguration.layout.sidebarsSwapped
        if tabsOnRight {
            workspace.isRightSidebarVisible = tabsPaneShouldBeVisible
        } else {
            workspace.isLeftSidebarVisible = tabsPaneShouldBeVisible
        }

        windowWorkspaces[index] = workspace
        notifyChange()
    }

    func session(for id: UUID) -> DocumentSession? {
        sessions.first { $0.id == id }
    }

    func updateCurrentPage(index: Int, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].currentPageIndex != index else { return }

        sessions[sessionIndex].currentPageIndex = index
        sessions[sessionIndex].lastReadPosition = ReadingPosition(
            pageIndex: index,
            point: sessions[sessionIndex].lastReadPosition.point
        )
        persistReadingState(for: sessions[sessionIndex])
        notifyChange()
    }

    func setDisplayMode(_ mode: ReaderDisplayMode, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].displayMode != mode else { return }
        sessions[sessionIndex].displayMode = mode
        persistReadingState(for: sessions[sessionIndex])
        notifyChange()
    }

    func setScaleMode(_ mode: ReaderScaleMode, scaleFactor: CGFloat, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let modeChanged = sessions[sessionIndex].scaleMode != mode
        let scaleChanged = abs(sessions[sessionIndex].zoomScale - scaleFactor) > 0.001
        let needsUpdate = modeChanged || scaleChanged
        guard needsUpdate else { return }

        sessions[sessionIndex].scaleMode = mode
        sessions[sessionIndex].zoomScale = scaleFactor
        persistReadingState(for: sessions[sessionIndex])
        if modeChanged || mode == .manual {
            notifyChange()
        }
    }

    func updateReadingPosition(_ position: ReadingPosition, scaleFactor: CGFloat, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions[sessionIndex]
        let pageChanged = session.currentPageIndex != position.pageIndex
        let scaleChanged = abs(session.zoomScale - scaleFactor) > 0.001
        let needsUpdate = session.lastReadPosition != position || pageChanged || scaleChanged
        guard needsUpdate else { return }

        sessions[sessionIndex].currentPageIndex = position.pageIndex
        sessions[sessionIndex].lastReadPosition = position
        sessions[sessionIndex].zoomScale = scaleFactor
        persistReadingState(for: sessions[sessionIndex])
        if pageChanged || scaleChanged {
            notifyChange()
        }
    }

    func setLeftSidebarVisible(_ isVisible: Bool) {
        setLeftSidebarVisible(isVisible, in: defaultWindowID)
    }

    func setLeftSidebarVisible(_ isVisible: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        guard windowWorkspaces[index].isLeftSidebarVisible != isVisible else { return }
        windowWorkspaces[index].isLeftSidebarVisible = isVisible
        notifyChange()
    }

    func setRightSidebarVisible(_ isVisible: Bool) {
        setRightSidebarVisible(isVisible, in: defaultWindowID)
    }

    func setRightSidebarVisible(_ isVisible: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        guard windowWorkspaces[index].isRightSidebarVisible != isVisible else { return }
        windowWorkspaces[index].isRightSidebarVisible = isVisible
        notifyChange()
    }

    func setRightSidebarMode(_ mode: RightSidebarMode, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        guard windowWorkspaces[index].rightSidebarMode != mode else { return }
        windowWorkspaces[index].rightSidebarMode = mode
        notifyChange()
    }

    func toggleRightSidebarMode(in windowID: UUID) {
        let nextMode = rightSidebarMode(in: windowID).toggledPreviewMode()
        setRightSidebarMode(nextMode, in: windowID)
    }

    func updateSearch(query: String, scope: SearchScope, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        windowWorkspaces[index].searchScope = scope
        windowWorkspaces[index].searchQuery = trimmed

        if trimmed.isEmpty {
            clearSearchCaches()
            if windowWorkspaces[index].rightSidebarMode == .search {
                windowWorkspaces[index].rightSidebarMode = .outline
            }
            notifyChange()
            return
        }

        populateSearchCaches(for: trimmed, scope: scope, windowID: windowID)
        windowWorkspaces[index].rightSidebarMode = .search
        notifyChange()
    }

    func clearSearch(in windowID: UUID) {
        updateSearch(query: "", scope: searchScope(in: windowID), in: windowID)
    }

    func searchSections(in windowID: UUID) -> [SearchSidebarSection] {
        let query = searchQuery(in: windowID)
        guard query.isEmpty == false else { return [] }

        switch searchScope(in: windowID) {
        case .currentDocument:
            guard let session = activeSession(in: windowID) else { return [] }
            let grouped = Dictionary(grouping: session.searchCache.matches) { $0.pageIndex }
            return grouped
                .keys
                .sorted()
                .map { pageIndex in
                    SearchSidebarSection(
                        title: "Page \(pageIndex + 1)",
                        matches: grouped[pageIndex, default: []].map {
                            SearchSidebarMatch(
                                sessionID: session.id,
                                sessionTitle: session.title,
                                matchIndex: $0.matchIndex,
                                pageIndex: $0.pageIndex,
                                matchedText: $0.matchedText,
                                previewText: $0.previewText,
                                selection: $0.selection
                            )
                        }
                    )
                }
        case .allOpen:
            return sessions(in: windowID).compactMap { session in
                guard session.searchCache.query == query,
                      session.searchCache.matches.isEmpty == false else { return nil }
                return SearchSidebarSection(
                    title: session.title,
                    matches: session.searchCache.matches.map {
                        SearchSidebarMatch(
                            sessionID: session.id,
                            sessionTitle: session.title,
                            matchIndex: $0.matchIndex,
                            pageIndex: $0.pageIndex,
                            matchedText: $0.matchedText,
                            previewText: $0.previewText,
                            selection: $0.selection
                        )
                    }
                )
            }
        }
    }

    func totalSearchMatches(in windowID: UUID) -> Int {
        searchSections(in: windowID).reduce(0) { $0 + $1.matches.count }
    }

    func annotationSections(in windowID: UUID) -> [DocumentHighlightSection] {
        guard let session = activeSession(in: windowID) else { return [] }
        let grouped = Dictionary(grouping: session.annotationCache.groups) { $0.pageIndex }
        return grouped
            .keys
            .sorted()
            .map { pageIndex in
                DocumentHighlightSection(
                    title: "Page \(pageIndex + 1)",
                    highlights: grouped[pageIndex, default: []]
                        .sorted { lhs, rhs in
                            let lhsDate = lhs.createdAt ?? .distantPast
                            let rhsDate = rhs.createdAt ?? .distantPast
                            if lhsDate != rhsDate {
                                return lhsDate < rhsDate
                            }
                            return lhs.groupID < rhs.groupID
                        }
                )
            }
    }

    func annotationGroups(for sessionID: UUID) -> [DocumentHighlightGroup] {
        session(for: sessionID)?.annotationCache.groups ?? []
    }

    func currentSessionSearchMatches(in windowID: UUID) -> [DocumentSearchMatch] {
        activeSession(in: windowID)?.searchCache.matches ?? []
    }

    func setDirty(_ isDirty: Bool, for sessionID: UUID, now: Date = Date()) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].isDirty != isDirty else { return }

        sessions[sessionIndex].isDirty = isDirty
        sessions[sessionIndex].dirtySince = isDirty ? (sessions[sessionIndex].dirtySince ?? now) : nil
        notifyChange()
    }

    func noteHighlightsAdded(_ records: [HighlightAnnotationRecord], for sessionID: UUID, now: Date = Date()) {
        guard records.isEmpty == false,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(.added(records))
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
        markAnnotationsDirty(for: sessionIndex, now: now)
        rebuildAnnotationCache(for: sessionIndex)
        notifyChange()
    }

    func noteHighlightsRemoved(_ records: [HighlightAnnotationRecord], for sessionID: UUID, now: Date = Date()) {
        guard records.isEmpty == false,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(.removed(records))
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
        markAnnotationsDirty(for: sessionIndex, now: now)
        rebuildAnnotationCache(for: sessionIndex)
        notifyChange()
    }

    @discardableResult
    func updateComment(_ comment: String, forHighlightGroup groupID: String, in sessionID: UUID, now: Date = Date()) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let group = sessions[sessionIndex].annotationCache.groups.first(where: { $0.groupID == groupID }),
              HighlightService.updateComment(comment, for: group.records) else { return false }

        markAnnotationsDirty(for: sessionIndex, now: now)
        rebuildAnnotationCache(for: sessionIndex)
        notifyChange()
        return true
    }

    func recordHighlightUndo(_ operation: HighlightUndoOperation, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(operation)
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
    }

    func hasUndoableHighlight(for sessionID: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        return session.undoStack.isEmpty == false
    }

    func hasRedoableHighlight(for sessionID: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        return session.redoStack.isEmpty == false
    }

    @discardableResult
    func undoLastHighlight(for sessionID: UUID) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let operation = sessions[sessionIndex].undoStack.popLast() else { return false }

        let document = sessions[sessionIndex].pdfDocument
        switch operation {
        case let .added(records):
            HighlightService.removeHighlights(records, in: document)
        case let .removed(records):
            HighlightService.reinsertHighlights(records, in: document)
        }

        sessions[sessionIndex].redoStack.append(operation)
        markAnnotationsDirty(for: sessionIndex, now: Date())
        rebuildAnnotationCache(for: sessionIndex)
        notifyChange()
        return true
    }

    @discardableResult
    func redoLastHighlight(for sessionID: UUID) -> Bool {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let operation = sessions[sessionIndex].redoStack.popLast() else { return false }

        let document = sessions[sessionIndex].pdfDocument
        switch operation {
        case let .added(records):
            HighlightService.reinsertHighlights(records, in: document)
        case let .removed(records):
            HighlightService.removeHighlights(records, in: document)
        }

        sessions[sessionIndex].undoStack.append(operation)
        markAnnotationsDirty(for: sessionIndex, now: Date())
        rebuildAnnotationCache(for: sessionIndex)
        notifyChange()
        return true
    }

    func setAnnotationSavePolicy(_ policy: AnnotationSavePolicy, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].annotationSavePolicy != policy else { return }
        sessions[sessionIndex].annotationSavePolicy = policy
        notifyChange()
    }

    func updateAppConfiguration(_ configuration: AppConfiguration) {
        guard appConfiguration != configuration else { return }
        let previousFitWidthOnOpen = appConfiguration.reader.fitWidthOnOpen
        let previousSwapped = appConfiguration.layout.sidebarsSwapped
        let newSwapped = configuration.layout.sidebarsSwapped
        let layoutWidthsChanged =
            appConfiguration.layout.leftSidebarWidth != configuration.layout.leftSidebarWidth ||
            appConfiguration.layout.rightSidebarWidth != configuration.layout.rightSidebarWidth
        let applyLayoutWidthsDirectly = layoutWidthsChanged && previousSwapped == newSwapped
        appConfiguration = configuration

        let fitWidthChanged = previousFitWidthOnOpen != configuration.reader.fitWidthOnOpen
        let targetScaleMode: ReaderScaleMode = configuration.reader.fitWidthOnOpen ? .fitWidth : .manual

        if previousSwapped != newSwapped {
            for index in windowWorkspaces.indices {
                let leftVisible = windowWorkspaces[index].isLeftSidebarVisible
                windowWorkspaces[index].isLeftSidebarVisible = windowWorkspaces[index].isRightSidebarVisible
                windowWorkspaces[index].isRightSidebarVisible = leftVisible
            }
        }

        for index in sessions.indices {
            sessions[index].annotationSavePolicy = configuration.annotations.autoSavePolicy
            if fitWidthChanged, sessions[index].scaleMode != targetScaleMode {
                sessions[index].scaleMode = targetScaleMode
                persistReadingState(for: sessions[index])
            }
            if applyLayoutWidthsDirectly {
                sessions[index].leftSidebarWidth = configuration.layout.leftSidebarWidth
                sessions[index].rightSidebarWidth = configuration.layout.rightSidebarWidth
                persistReadingState(for: sessions[index])
            }
            if previousSwapped != newSwapped {
                let storedLeftWidth = sessions[index].leftSidebarWidth
                sessions[index].leftSidebarWidth = sessions[index].rightSidebarWidth
                sessions[index].rightSidebarWidth = storedLeftWidth
                persistReadingState(for: sessions[index])
            }
        }

        notifyChange()
    }

    func saveAnnotations(for sessionID: UUID) throws {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].isDirty else { return }
        guard sessions[sessionIndex].pdfDocument.write(to: sessions[sessionIndex].url) else {
            throw DocumentStoreError.failedToSaveDocument(sessions[sessionIndex].url)
        }

        sessions[sessionIndex].isDirty = false
        sessions[sessionIndex].dirtySince = nil
        notifyChange()
    }

    @discardableResult
    func autoSaveDirtySessions(now: Date = Date()) -> [URL: Error] {
        var errors: [URL: Error] = [:]
        for session in sessions where session.isDirty {
            guard let interval = session.annotationSavePolicy.autoSaveInterval,
                  let dirtySince = session.dirtySince,
                  now.timeIntervalSince(dirtySince) >= interval else { continue }

            do {
                try saveAnnotations(for: session.id)
            } catch {
                errors[session.url] = error
            }
        }
        return errors
    }

    func restorePersistedState() throws {
        guard let persistedState = try persistence.loadState() else { return }

        sessions = []
        splitComparisonSessionIDs.removeAll()
        var usedSessionIDs: Set<UUID> = []
        for reference in persistedState.sessions {
            guard let pdfDocument = PDFDocument(url: reference.url) else { continue }
            let restoredState = try readingStateStore.loadState(for: reference.url)
            let sessionID = usedSessionIDs.insert(reference.id).inserted ? reference.id : UUID()
            var session = DocumentSession(
                    id: sessionID,
                    url: reference.url,
                    pdfDocument: pdfDocument,
                    currentPageIndex: restoredState?.readingPosition.pageIndex ?? 0,
                    displayMode: restoredState?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
                    scaleMode: resolvedScaleMode(restoredState?.scaleMode),
                    zoomScale: restoredState?.scaleFactor ?? 1.0,
                    lastReadPosition: restoredState?.readingPosition ?? .zero,
                    outlineTree: OutlineExtractor.extract(from: pdfDocument),
                    annotationSavePolicy: appConfiguration.annotations.autoSavePolicy,
                    leftSidebarWidth: appConfiguration.layout.leftSidebarWidth,
                    rightSidebarWidth: appConfiguration.layout.rightSidebarWidth
                )
            session.annotationCache = DocumentHighlightCache(
                groups: HighlightService.buildHighlightGroups(in: pdfDocument)
            )
            sessions.append(session)
        }

        let sessionIDByPersistedID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.id) })
        let firstSessionIDByURL = sessions.reduce(into: [URL: UUID]()) { mapping, session in
            mapping[session.url] = mapping[session.url] ?? session.id
        }
        let restoredWindows = persistedState.windows.isEmpty ? [WindowWorkspace()] : persistedState.windows.map { record in
            let primarySessionID =
                record.splitState.primarySessionID.flatMap { sessionIDByPersistedID[$0] }
                ?? record.splitState.primarySessionURL.flatMap { firstSessionIDByURL[$0] }
            let secondarySessionID =
                record.splitState.secondarySessionID.flatMap { sessionIDByPersistedID[$0] }
                ?? record.splitState.secondarySessionURL.flatMap { firstSessionIDByURL[$0] }
            let restoredSessionIDs = restoredSessionIDs(for: record, sessionIDByPersistedID: sessionIDByPersistedID, firstSessionIDByURL: firstSessionIDByURL)
            let restoredActiveSessionID = {
                if record.splitState.isEnabled, record.splitState.focusedPane == .secondary {
                    return secondarySessionID ?? primarySessionID
                }
                return primarySessionID ?? secondarySessionID
            }()
            return WindowWorkspace(
                id: record.id,
                sessionIDs: restoredSessionIDs,
                tabPresentationMode: record.tabPresentationMode,
                isLeftSidebarVisible: record.isLeftSidebarVisible,
                isRightSidebarVisible: record.isRightSidebarVisible,
                rightSidebarMode: record.rightSidebarMode,
                searchQuery: record.searchQuery,
                searchScope: record.searchScope,
                isSplitEnabled: false,
                primarySessionID: restoredActiveSessionID,
                secondarySessionID: nil,
                focusedPane: .primary,
                recentlyClosedURLs: record.recentlyClosedURLs
            )
        }

        windowWorkspaces = restoredWindows
        normalizeAllWorkspaces()
        notifyChange()
    }

    private func resolvedTargetPane(for requestedPane: ReaderPane?, in workspace: WindowWorkspace) -> ReaderPane {
        if let requestedPane {
            return requestedPane
        }
        return workspace.isSplitEnabled ? workspace.focusedPane : .primary
    }

    private func pushRecentlyClosed(_ url: URL, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        windowWorkspaces[index].recentlyClosedURLs.removeAll { $0 == url }
        windowWorkspaces[index].recentlyClosedURLs.append(url)
        if windowWorkspaces[index].recentlyClosedURLs.count > Self.recentlyClosedLimit {
            windowWorkspaces[index].recentlyClosedURLs.removeFirst(
                windowWorkspaces[index].recentlyClosedURLs.count - Self.recentlyClosedLimit
            )
        }
    }

    private func attach(sessionID: UUID, to windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        if windowWorkspaces[index].sessionIDs.contains(sessionID) == false {
            windowWorkspaces[index].sessionIDs.append(sessionID)
        }
    }

    private func isSessionReferenced(_ sessionID: UUID) -> Bool {
        windowWorkspaces.contains { $0.sessionIDs.contains(sessionID) }
    }

    private func isSessionReferencedOutsideWindow(_ sessionID: UUID, excluding windowID: UUID) -> Bool {
        windowWorkspaces.contains { $0.id != windowID && $0.sessionIDs.contains(sessionID) }
    }

    private func removeUnreferencedSessions() {
        sessions.removeAll { session in
            isSessionReferenced(session.id) == false
        }
        splitComparisonSessionIDs = splitComparisonSessionIDs.filter { sessionID in
            sessions.contains(where: { $0.id == sessionID })
        }
    }

    private func discardSession(_ sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        splitComparisonSessionIDs.remove(sessionID)
    }

    private func preferredSecondarySession(in workspace: WindowWorkspace, excluding sessionID: UUID?) -> UUID? {
        workspace.sessionIDs.first(where: { $0 != sessionID }) ?? sessionID
    }

    private func normalizeAllWorkspaces() {
        guard windowWorkspaces.isEmpty == false else {
            windowWorkspaces = [WindowWorkspace()]
            return
        }
        for index in windowWorkspaces.indices {
            var workspace = windowWorkspaces[index]
            normalizeWorkspace(&workspace)
            windowWorkspaces[index] = workspace
        }
    }

    private func normalizeWorkspace(_ workspace: inout WindowWorkspace, preferredSessionID: UUID? = nil) {
        let validIDs = Set(sessions.map(\.id))
        workspace.sessionIDs = workspace.sessionIDs.filter { validIDs.contains($0) }
        var seenSessionIDs: Set<UUID> = []
        workspace.sessionIDs.removeAll { seenSessionIDs.insert($0).inserted == false }
        let fallback = fallbackSessionID(in: workspace, preferredSessionID: preferredSessionID, excluding: workspace.isSplitEnabled ? workspace.secondarySessionID : nil)

        if workspace.primarySessionID.map({ workspace.sessionIDs.contains($0) }) != true {
            workspace.primarySessionID = fallback
        }

        if workspace.isSplitEnabled {
            if workspace.secondarySessionID.map({ workspace.sessionIDs.contains($0) }) != true || workspace.secondarySessionID == nil {
                workspace.secondarySessionID = fallbackSessionID(
                    in: workspace,
                    preferredSessionID: preferredSessionID,
                    excluding: workspace.primarySessionID
                ) ?? workspace.primarySessionID
            }
            if workspace.focusedPane == .secondary, workspace.secondarySessionID == nil {
                workspace.focusedPane = .primary
            }
        } else {
            workspace.secondarySessionID = nil
            workspace.focusedPane = .primary
        }

        if workspace.activeSessionID == nil {
            workspace.primarySessionID = fallbackSessionID(in: workspace, preferredSessionID: preferredSessionID, excluding: nil)
            workspace.secondarySessionID = workspace.isSplitEnabled
                ? (fallbackSessionID(in: workspace, preferredSessionID: preferredSessionID, excluding: workspace.primarySessionID)
                    ?? workspace.primarySessionID)
                : nil
            workspace.focusedPane = .primary
        }

    }

    private func fallbackSessionID(in workspace: WindowWorkspace, preferredSessionID: UUID?, excluding excludedID: UUID?) -> UUID? {
        guard workspace.sessionIDs.isEmpty == false else { return nil }

        if let preferredSessionID,
           workspace.sessionIDs.contains(preferredSessionID),
           preferredSessionID != excludedID {
            return preferredSessionID
        }

        return workspace.sessionIDs.first(where: { $0 != excludedID }) ?? excludedID
    }

    private func trimUndoStack(for sessionIndex: Int) {
        let overflow = sessions[sessionIndex].undoStack.count - Self.undoStackLimit
        if overflow > 0 {
            sessions[sessionIndex].undoStack.removeFirst(overflow)
        }
    }

    private func markAnnotationsDirty(for sessionIndex: Int, now: Date) {
        sessions[sessionIndex].isDirty = true
        sessions[sessionIndex].dirtySince = sessions[sessionIndex].dirtySince ?? now
    }

    private func rebuildAnnotationCache(for sessionIndex: Int) {
        sessions[sessionIndex].annotationCache = DocumentHighlightCache(
            groups: HighlightService.buildHighlightGroups(in: sessions[sessionIndex].pdfDocument)
        )
    }

    private func populateSearchCaches(for query: String, scope: SearchScope, windowID: UUID) {
        let targetSessionIDs: [UUID]
        switch scope {
        case .currentDocument:
            targetSessionIDs = activeSessionID(in: windowID).map { [$0] } ?? []
        case .allOpen:
            targetSessionIDs = windowWorkspace(for: windowID)?.sessionIDs ?? []
        }

        for sessionID in targetSessionIDs {
            rebuildSearchCache(for: sessionID, query: query)
        }
    }

    private func rebuildSearchCache(for sessionID: UUID, query: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if sessions[index].searchCache.query == query {
            return
        }
        let matches = DocumentSearchService.buildMatches(for: query, in: sessions[index].pdfDocument)
        sessions[index].searchCache = DocumentSearchCache(
            query: query,
            matches: matches.enumerated().map { offset, match in
                DocumentSearchMatch(
                    matchIndex: offset,
                    pageIndex: match.pageIndex,
                    matchedText: match.matchedText,
                    previewText: match.previewText,
                    selection: match.selection
                )
            }
        )
    }

    private func updateSearchCachesAfterOpen(for sessionID: UUID) {
        for index in windowWorkspaces.indices {
            let query = windowWorkspaces[index].searchQuery
            guard query.isEmpty == false else { continue }
            if windowWorkspaces[index].sessionIDs.contains(sessionID) &&
                (windowWorkspaces[index].searchScope == .allOpen ||
                 windowWorkspaces[index].activeSessionID == sessionID) {
                rebuildSearchCache(for: sessionID, query: query)
            }
        }
    }

    private func restoredSessionIDs(
        for record: PersistedDocumentStoreState.WindowRecord,
        sessionIDByPersistedID: [UUID: UUID],
        firstSessionIDByURL: [URL: UUID]
    ) -> [UUID] {
        let restoredIDs = record.sessionIDs.compactMap { sessionIDByPersistedID[$0] }
        if restoredIDs.isEmpty == false {
            return restoredIDs
        }

        let restoredURLs = record.sessionURLs.compactMap { firstSessionIDByURL[$0] }
        if restoredURLs.isEmpty == false {
            return restoredURLs
        }

        let fallbackIDs = [
            record.splitState.primarySessionID.flatMap { sessionIDByPersistedID[$0] }
                ?? record.splitState.primarySessionURL.flatMap { firstSessionIDByURL[$0] },
            record.splitState.secondarySessionID.flatMap { sessionIDByPersistedID[$0] }
                ?? record.splitState.secondarySessionURL.flatMap { firstSessionIDByURL[$0] },
        ].compactMap { $0 }
        var seen: Set<UUID> = []
        return fallbackIDs.filter { seen.insert($0).inserted }
    }

    private func clearSearchCaches() {
        for index in sessions.indices {
            sessions[index].searchCache.clear()
        }
    }

    private func notifyChange() {
        try? persistence.saveState(
            PersistedDocumentStoreState(
                sessions: sessions.map {
                    PersistedDocumentStoreState.SessionReference(id: $0.id, url: $0.url)
                },
                windows: windowWorkspaces.map { workspace in
                    PersistedDocumentStoreState.WindowRecord(
                        id: workspace.id,
                        sessionIDs: workspace.sessionIDs,
                        sessionURLs: workspace.sessionIDs.compactMap { session(for: $0)?.url },
                        tabPresentationMode: workspace.tabPresentationMode,
                        isLeftSidebarVisible: workspace.isLeftSidebarVisible,
                        isRightSidebarVisible: workspace.isRightSidebarVisible,
                        rightSidebarMode: workspace.rightSidebarMode,
                        searchQuery: workspace.searchQuery,
                        searchScope: workspace.searchScope,
                        splitState: PersistedDocumentStoreState.SplitStateRecord(
                            isEnabled: workspace.isSplitEnabled,
                            primarySessionID: workspace.primarySessionID,
                            secondarySessionID: workspace.secondarySessionID,
                            primarySessionURL: workspace.primarySessionID.flatMap { session(for: $0)?.url },
                            secondarySessionURL: workspace.secondarySessionID.flatMap { session(for: $0)?.url },
                            focusedPane: workspace.focusedPane
                        ),
                        recentlyClosedURLs: workspace.recentlyClosedURLs
                    )
                }
            )
        )
        NotificationCenter.default.post(name: .documentStoreDidChange, object: self)
    }

    private var defaultScaleMode: ReaderScaleMode {
        appConfiguration.reader.fitWidthOnOpen ? .fitWidth : .manual
    }

    private func resolvedScaleMode(_ restoredScaleMode: ReaderScaleMode?) -> ReaderScaleMode {
        guard let restoredScaleMode else { return defaultScaleMode }
        guard restoredScaleMode == .fitWidth else { return restoredScaleMode }
        return appConfiguration.reader.fitWidthOnOpen ? .fitWidth : .manual
    }

    private func makeSession(
        documentAt url: URL,
        seedState: DocumentSession? = nil
    ) throws -> DocumentSession {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentStoreError.unreadableDocument(url)
        }

        let restoredState = seedState == nil ? try readingStateStore.loadState(for: url) : nil
        var session = DocumentSession(
            url: url,
            title: seedState?.title,
            pdfDocument: pdfDocument,
            currentPageIndex: seedState?.currentPageIndex ?? restoredState?.readingPosition.pageIndex ?? 0,
            displayMode: seedState?.displayMode ?? restoredState?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
            scaleMode: seedState?.scaleMode ?? resolvedScaleMode(restoredState?.scaleMode),
            zoomScale: seedState?.zoomScale ?? restoredState?.scaleFactor ?? 1.0,
            lastReadPosition: seedState?.lastReadPosition ?? restoredState?.readingPosition ?? .zero,
            outlineTree: OutlineExtractor.extract(from: pdfDocument),
            annotationSavePolicy: seedState?.annotationSavePolicy ?? appConfiguration.annotations.autoSavePolicy,
            leftSidebarWidth: seedState?.leftSidebarWidth ?? appConfiguration.layout.leftSidebarWidth,
            rightSidebarWidth: seedState?.rightSidebarWidth ?? appConfiguration.layout.rightSidebarWidth
        )
        session.annotationCache = DocumentHighlightCache(
            groups: HighlightService.buildHighlightGroups(in: pdfDocument)
        )
        return session
    }

    private func duplicateSessionForSplitComparison(from sessionID: UUID) -> UUID? {
        guard let sourceSession = session(for: sessionID) else { return nil }
        do {
            let duplicate = try makeSession(documentAt: sourceSession.url, seedState: sourceSession)
            sessions.append(duplicate)
            splitComparisonSessionIDs.insert(duplicate.id)
            return duplicate.id
        } catch {
            NSLog("SlatePDF failed to duplicate session for split comparison: %@", error.localizedDescription)
            return nil
        }
    }

    private func existingSplitComparisonSessionID(
        for sessionID: UUID,
        in workspace: WindowWorkspace,
        excluding excludedSessionID: UUID?
    ) -> UUID? {
        guard let targetURL = session(for: sessionID)?.url else { return nil }
        return workspace.sessionIDs.first { candidateID in
            guard candidateID != sessionID else { return false }
            if let excludedSessionID, candidateID == excludedSessionID {
                return false
            }
            return session(for: candidateID)?.url == targetURL
        }
    }

    private func persistReadingState(for session: DocumentSession) {
        try? readingStateStore.saveState(
            PersistedReadingState(
                url: session.url,
                displayMode: session.displayMode,
                scaleMode: session.scaleMode,
                scaleFactor: session.zoomScale,
                readingPosition: session.lastReadPosition,
                leftSidebarWidth: session.leftSidebarWidth,
                rightSidebarWidth: session.rightSidebarWidth
            )
        )
    }

    func updateSidebarWidths(
        left leftWidth: CGFloat?,
        right rightWidth: CGFloat?,
        for sessionID: UUID
    ) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let needsUpdate =
            sessions[sessionIndex].leftSidebarWidth != leftWidth ||
            sessions[sessionIndex].rightSidebarWidth != rightWidth
        guard needsUpdate else { return }

        sessions[sessionIndex].leftSidebarWidth = leftWidth
        sessions[sessionIndex].rightSidebarWidth = rightWidth
        persistReadingState(for: sessions[sessionIndex])
    }
}

enum DocumentStoreError: Error, LocalizedError {
    case unreadableDocument(URL)
    case failedToSaveDocument(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableDocument(url):
            "Unable to open PDF at \(url.path)"
        case let .failedToSaveDocument(url):
            "Unable to save PDF at \(url.path)"
        }
    }
}
