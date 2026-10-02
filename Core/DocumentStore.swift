import AppKit
import Foundation
import os
import PDFKit

enum TabPresentationMode: String, CaseIterable, Codable, Sendable {
    case verticalSidebar
    case horizontalTitlebar
}

extension Notification.Name {
    static let documentStoreDidChange = Notification.Name("DocumentStore.didChange")
}

struct DocumentStoreChange: OptionSet, Sendable {
    let rawValue: Int

    static let sidebarVisibility = DocumentStoreChange(rawValue: 1 << 0)
    static let rightSidebarMode = DocumentStoreChange(rawValue: 1 << 1)
    static let content = DocumentStoreChange(rawValue: 1 << 2)
    /// Page/zoom/reading-position writeback; does not reshape tabs or search results.
    static let readingPosition = DocumentStoreChange(rawValue: 1 << 3)
    static let search = DocumentStoreChange(rawValue: 1 << 4)
    static let annotations = DocumentStoreChange(rawValue: 1 << 5)
    static let recentFiles = DocumentStoreChange(rawValue: 1 << 6)
    static let appearance = DocumentStoreChange(rawValue: 1 << 7)
    static let tabs = DocumentStoreChange(rawValue: 1 << 8)
    static let all: DocumentStoreChange = [
        .sidebarVisibility,
        .rightSidebarMode,
        .content,
        .readingPosition,
        .search,
        .annotations,
        .recentFiles,
        .appearance,
        .tabs,
    ]

    static let notificationUserInfoKey = "DocumentStore.change"
    static let windowIDsUserInfoKey = "DocumentStore.windowIDs"
    static let sessionIDsUserInfoKey = "DocumentStore.sessionIDs"

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    func containsOnly(_ changes: DocumentStoreChange) -> Bool {
        rawValue != 0 && (rawValue & ~changes.rawValue) == 0
    }
}

extension Notification {
    var documentStoreChange: DocumentStoreChange {
        guard let rawValue = userInfo?[DocumentStoreChange.notificationUserInfoKey] as? Int else {
            return .all
        }
        return DocumentStoreChange(rawValue: rawValue)
    }

    var isOnlySidebarVisibilityChange: Bool {
        documentStoreChange.containsOnly(.sidebarVisibility)
    }

    var isOnlyRightSidebarModeChange: Bool {
        documentStoreChange.containsOnly(.rightSidebarMode)
    }

    var isOnlySidebarChromeChange: Bool {
        documentStoreChange.containsOnly([.sidebarVisibility, .rightSidebarMode])
    }

    var isOnlyReadingPositionChange: Bool {
        documentStoreChange.containsOnly(.readingPosition)
    }

    /// Chrome or reading-position only: tabs / search lists can skip full rebuild.
    var isLightweightStoreChange: Bool {
        documentStoreChange.containsOnly([.sidebarVisibility, .rightSidebarMode, .readingPosition, .search])
    }

    func affects(windowID: UUID) -> Bool {
        guard let windowIDs = userInfo?[DocumentStoreChange.windowIDsUserInfoKey] as? Set<UUID> else {
            return true
        }
        return windowIDs.contains(windowID)
    }

    func affects(sessionID: UUID) -> Bool {
        guard let sessionIDs = userInfo?[DocumentStoreChange.sessionIDsUserInfoKey] as? Set<UUID> else {
            return true
        }
        return sessionIDs.contains(sessionID)
    }
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
    private var sharedDocumentSources: [UUID: UUID] = [:]
    private var selectionAnchorIDsByWorkspace: [UUID: UUID] = [:]
    /// Windows whose outline pane the empty-window policy auto-collapsed.
    /// Cleared when the user explicitly touches visibility while empty, or when
    /// the first session opens (which restores the pane).
    private var outlineAutoHiddenWindowIDs: Set<UUID> = []
    private var pdfDocumentCache: [UUID: PDFDocument] = [:]
    private var pdfDocumentRecency: [UUID] = []
    private var searchSnapshots: [UUID: SearchSnapshot] = [:]
    private var searchOperations: [UUID: DocumentSearchOperation] = [:]
    private var outlineSnapshots: [UUID: [OutlineNode]] = [:]
    private var searchOptionsByWindowID: [UUID: SearchOptions] = [:]
    private let fileMonitor = PDFFileMonitor()
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private static let recentlyClosedLimit = 10
    private static let livePDFDocumentLimit = 4
    private static let highlightedSearchSelectionLimit = 1_000
    static let undoStackLimit = 50
    var noteRecentDocumentURL: ((URL) -> Void)?

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
        self.windowWorkspaces = [
            WindowWorkspace(
                leftSidebarWidth: appConfiguration.layout.leftSidebarWidth,
                rightSidebarWidth: appConfiguration.layout.rightSidebarWidth
            ),
        ]
        // M12-010: a fresh empty window starts with the outline pane collapsed so
        // the reader owns the window; the tabs pane stays (it hosts recents).
        applyEmptyWindowSidebarPolicy(&windowWorkspaces[0])
        recentDocumentURLs = (try? recentFilesStore.loadRecentFiles()) ?? []
        fileMonitor.onChange = { [weak self] url in
            self?.refreshExternallyChangedFile(at: url)
        }
        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource.setEventHandler { [weak self] in
            self?.discardCleanBackgroundDocuments()
        }
        memoryPressureSource.resume()
        self.memoryPressureSource = memoryPressureSource
    }

    var defaultWindowID: UUID {
        if let window = windowWorkspaces.first(where: { !$0.isClosed }) { return window.id }
        return createWindow()
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

    /// True only when the outline *pane content* is on screen (sidebar open + Outline mode).
    /// Pages / Search / Annotations leave room for the floating outline rail.
    func isOutlineSidebarVisible(in windowID: UUID) -> Bool {
        guard let workspace = windowWorkspace(for: windowID),
              isOutlinePaneVisible(in: workspace) else { return false }
        return rightSidebarMode(in: windowID) == .outline
    }

    func isOutlinePaneVisible(in windowID: UUID) -> Bool {
        guard let workspace = windowWorkspace(for: windowID) else { return false }
        return isOutlinePaneVisible(in: workspace)
    }

    func setOutlinePaneVisible(_ isVisible: Bool, in windowID: UUID) {
        if appConfiguration.layout.sidebarsSwapped {
            setLeftSidebarVisible(isVisible, in: windowID)
        } else {
            setRightSidebarVisible(isVisible, in: windowID)
        }
    }

    func sidebarWidths(in windowID: UUID) -> (left: CGFloat, right: CGFloat) {
        guard let workspace = windowWorkspace(for: windowID) else {
            return (appConfiguration.layout.leftSidebarWidth, appConfiguration.layout.rightSidebarWidth)
        }
        return (
            workspace.leftSidebarWidth ?? appConfiguration.layout.leftSidebarWidth,
            workspace.rightSidebarWidth ?? appConfiguration.layout.rightSidebarWidth
        )
    }

    var recentlyClosedURLs: [URL] {
        windowWorkspace(for: defaultWindowID)?.recentlyClosedURLs ?? []
    }

    func recentlyClosedURLs(in windowID: UUID) -> [URL] {
        windowWorkspace(for: windowID)?.recentlyClosedURLs ?? []
    }

    func windowIDs() -> [UUID] {
        windowWorkspaces.filter { !$0.isClosed }.map(\.id)
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
        let ownersInWindow = Set(windowWorkspace(for: windowID)?.workspaces.flatMap { Array($0.referencedSessionIDs) }
            .map { documentSessionID(for: $0) } ?? [])
        let ownersElsewhere = Set(windowWorkspaces.filter { $0.id != windowID && !$0.isClosed }
            .flatMap { $0.workspaces.flatMap { Array($0.referencedSessionIDs) } }
            .map { documentSessionID(for: $0) })
        return sessions.filter { $0.isDirty && ownersInWindow.contains($0.id) && !ownersElsewhere.contains($0.id) }
    }

    func createWindow(copyingFrom sourceWindowID: UUID? = nil) -> UUID {
        let source = sourceWindowID.flatMap(windowWorkspace(for:)) ?? windowWorkspaces.first ?? WindowWorkspace()
        let sourceVisibility = sidebarVisibilityReflectingUserIntent(in: source)
        var copy = WindowWorkspace(
            sessionIDs: [],
            selectedSessionIDs: [],
            continuousReadingState: ContinuousReadingState(),
            tabPresentationMode: source.tabPresentationMode,
            isLeftSidebarVisible: sourceVisibility.left,
            isRightSidebarVisible: sourceVisibility.right,
            rightSidebarMode: .outline,
            searchQuery: "",
            searchScope: .currentDocument,
            isSplitEnabled: false,
            primarySessionID: nil,
            secondarySessionID: nil,
            focusedPane: .primary,
            recentlyClosedURLs: [],
            leftSidebarWidth: source.leftSidebarWidth,
            rightSidebarWidth: source.rightSidebarWidth
        )
        normalizeWorkspace(&copy)
        windowWorkspaces.append(copy)
        notifyChange(.content, windowIDs: [copy.id])
        return copy.id
    }

    func closeWindow(id windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              !windowWorkspaces[index].isClosed else { return }
        var window = windowWorkspaces.remove(at: index)
        window.isClosed = true
        windowWorkspaces.append(window)
        cancelSearchOperation(in: windowID)
        searchSnapshots.removeValue(forKey: windowID)
        searchOptionsByWindowID.removeValue(forKey: windowID)
        prunePDFDocumentCache()
        notifyChange(.content)
    }

    func mergeAllWindows(into targetWindowID: UUID) {
        guard let targetIndex = windowWorkspaces.firstIndex(where: { $0.id == targetWindowID }) else { return }
        let sources = windowWorkspaces.filter { $0.id != targetWindowID && !$0.isClosed }
        guard !sources.isEmpty else { return }
        var target = windowWorkspaces[targetIndex]
        for source in sources {
            for workspace in source.workspaces {
                if workspace.id == source.activeWorkspaceID {
                    target.sessionIDs.append(contentsOf: workspace.sessionIDs.filter { !target.sessionIDs.contains($0) })
                    target.activeWorkspace.groups.append(contentsOf: workspace.groups)
                    if target.activeWorkspace.activeGroupID == nil {
                        target.activeWorkspace.activeGroupID = workspace.activeGroupID
                    }
                    target.recentlyClosedURLs.append(contentsOf: workspace.recentlyClosedURLs)
                } else { target.workspaces.append(workspace) }
            }
            target.documentMRU.append(contentsOf: source.documentMRU.map {
                WorkspaceDocumentReference(workspaceID: $0.workspaceID == source.activeWorkspaceID ? target.activeWorkspaceID : $0.workspaceID,
                                           sessionID: $0.sessionID)
            })
            cancelSearchOperation(in: source.id)
            searchSnapshots.removeValue(forKey: source.id)
            searchOptionsByWindowID.removeValue(forKey: source.id)
        }
        target.continuousReadingState = ContinuousReadingState()
        target.selectedSessionIDs = []
        target.recentlyClosedURLs = Array(target.recentlyClosedURLs.suffix(Self.recentlyClosedLimit))
        normalizeWorkspace(&target)
        windowWorkspaces[targetIndex] = target
        let sourceIDs = Set(sources.map(\.id))
        windowWorkspaces.removeAll { sourceIDs.contains($0.id) }
        rebuildSearchIfNeeded(in: targetWindowID)
        notifyChange(.content)
    }

    func moveActiveSessionToNewWindow(from sourceWindowID: UUID) -> UUID? {
        guard let sourceIndex = windowWorkspaces.firstIndex(where: { $0.id == sourceWindowID }),
              let sessionID = publicSessionID(
                for: windowWorkspaces[sourceIndex].activeSessionID,
                in: windowWorkspaces[sourceIndex]
              ) else { return nil }

        let source = windowWorkspaces[sourceIndex]
        guard source.sessionIDs.contains(sessionID) else { return nil }

        let destination = WindowWorkspace(
            sessionIDs: [],
            selectedSessionIDs: [],
            continuousReadingState: ContinuousReadingState(),
            tabPresentationMode: source.tabPresentationMode,
            isLeftSidebarVisible: source.isLeftSidebarVisible,
            isRightSidebarVisible: source.isRightSidebarVisible,
            rightSidebarMode: source.rightSidebarMode,
            searchQuery: "",
            searchScope: .currentDocument,
            isSplitEnabled: false,
            primarySessionID: nil,
            secondarySessionID: nil,
            focusedPane: .primary,
            recentlyClosedURLs: [],
            leftSidebarWidth: source.leftSidebarWidth,
            rightSidebarWidth: source.rightSidebarWidth
        )

        windowWorkspaces.append(destination)
        let destinationIndex = windowWorkspaces.index(before: windowWorkspaces.endIndex)
        guard transferSession(
            sessionID,
            fromWorkspaceAt: sourceIndex,
            toWorkspaceAt: destinationIndex,
            readingSessionID: source.activeSessionID
        ) else {
            windowWorkspaces.remove(at: destinationIndex)
            return nil
        }

        notifyChange(.content, windowIDs: [sourceWindowID, destination.id])
        return destination.id
    }

    @discardableResult
    func moveSession(_ sessionID: UUID, from sourceWindowID: UUID, to destinationWindowID: UUID) -> Bool {
        guard sourceWindowID != destinationWindowID,
              let sourceIndex = windowWorkspaces.firstIndex(where: { $0.id == sourceWindowID }),
              let destinationIndex = windowWorkspaces.firstIndex(where: { $0.id == destinationWindowID }),
              let resolvedSessionID = publicSessionID(
                for: sessionID,
                in: windowWorkspaces[sourceIndex]
              ),
              transferSession(
                resolvedSessionID,
                fromWorkspaceAt: sourceIndex,
                toWorkspaceAt: destinationIndex,
                readingSessionID: sessionID == resolvedSessionID ? nil : sessionID
              ) else { return false }

        notifyChange(.content, windowIDs: [sourceWindowID, destinationWindowID])
        return true
    }

    func activeSessionID(in windowID: UUID) -> UUID? {
        windowWorkspace(for: windowID)?.activeSessionID
    }

    func activeSession(in windowID: UUID) -> DocumentSession? {
        guard let sessionID = activeSessionID(in: windowID) else { return nil }
        return session(for: sessionID)
    }

    func displayedSessionID(for pane: ReaderPane, in windowID: UUID) -> UUID? {
        windowWorkspace(for: windowID)?.activeWorkspace.activeGroup?.sessionIDsByPane[pane]
    }

    func publicSessionID(forDisplayedSessionID sessionID: UUID, in windowID: UUID) -> UUID? {
        guard let workspace = windowWorkspace(for: windowID) else { return nil }
        return publicSessionID(for: sessionID, in: workspace)
    }

    func focusedPane(in windowID: UUID) -> ReaderPane {
        windowWorkspace(for: windowID)?.focusedPane ?? .primary
    }

    func isSplitEnabled(in windowID: UUID) -> Bool {
        windowWorkspace(for: windowID)?.isSplitEnabled ?? false
    }

    func splitLayout(in windowID: UUID) -> ReaderSplitLayout {
        windowWorkspace(for: windowID)?.splitLayout ?? .sideBySide
    }

    func splitPair(in windowID: UUID) -> ReaderSplitPair? {
        windowWorkspace(for: windowID)?.splitPair
    }

    func splitCandidateSessions(in windowID: UUID) -> [DocumentSession] {
        guard let workspace = windowWorkspace(for: windowID),
              workspace.isSplitEnabled,
              workspace.secondarySessionID == nil,
              let primarySessionID = workspace.primarySessionID,
              let primarySession = session(for: primarySessionID),
              primarySession.isBlank == false else { return [] }

        let candidateIDs = [primarySessionID] + workspace.sessionIDs.filter { $0 != primarySessionID }
        return candidateIDs.compactMap { candidateID in
            guard let candidate = session(for: candidateID),
                  candidate.isBlank == false else { return nil }
            return candidate
        }
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

    func searchOptions(in windowID: UUID) -> SearchOptions {
        searchOptionsByWindowID[windowID] ?? .default
    }

    static func normalizedDocumentURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    @discardableResult
    func open(documentAt url: URL) throws -> DocumentSession {
        try open(documentAt: url, in: defaultWindowID)
    }

    @discardableResult
    func open(documentAt url: URL, in windowID: UUID, targetPane: ReaderPane? = nil) throws -> DocumentSession {
        let openedSessions = try open(documentsAt: [url], in: windowID, targetPane: targetPane)
        guard let session = openedSessions.first else {
            throw DocumentStoreError.unreadableDocument(url)
        }
        return session
    }

    @discardableResult
    func open(documentsAt urls: [URL], in windowID: UUID, targetPane: ReaderPane? = nil) throws -> [DocumentSession] {
        // Validate the batch before changing workspace membership.
        for url in urls where !FileManager.default.isReadableFile(atPath: url.path) {
            throw DocumentStoreError.unreadableDocument(url)
        }
        let openedSessions = try urls.map { try ensurePublicSession(documentAt: $0, seed: nil, in: windowID) }
        guard !openedSessions.isEmpty else { return [] }
        recentDocumentURLs = (try? recentFilesStore.recordOpen(for: openedSessions.map(\.url))) ?? recentDocumentURLs
        selectSessions(openedSessions.map(\.id), in: windowID, notify: false)
        if let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }) {
            windowWorkspaces[workspaceIndex].continuousReadingState = ContinuousReadingState()
        }
        if let last = openedSessions.last {
            activateSession(sessionID: last.id, in: windowID, targetPane: targetPane, notify: false)
        }
        syncPDFFileMonitor()
        notifyChange([.content, .tabs, .recentFiles], windowIDs: [windowID])
        return openedSessions
    }

    @discardableResult
    func newBlankTab(in windowID: UUID? = nil, targetPane: ReaderPane? = nil) -> DocumentSession {
        let targetWindowID = windowID ?? defaultWindowID
        let session = DocumentSession.blank(
            displayMode: appConfiguration.reader.defaultDisplayMode,
            scaleMode: defaultScaleMode,
            annotationSavePolicy: appConfiguration.annotations.autoSavePolicy
        )

        sessions.append(session)
        attach(sessionID: session.id, to: targetWindowID)
        selectSessions([session.id], in: targetWindowID, notify: false)
        if let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == targetWindowID }) {
            windowWorkspaces[workspaceIndex].continuousReadingState = ContinuousReadingState()
        }
        activateSession(sessionID: session.id, in: targetWindowID, targetPane: targetPane, notify: false)
        notifyChange([.content, .tabs], windowIDs: [targetWindowID])
        return session
    }

    func refreshRecentDocumentURLsFromStore() {
        let refreshedRecentURLs = (try? recentFilesStore.loadRecentFiles()) ?? recentDocumentURLs
        guard refreshedRecentURLs != recentDocumentURLs else { return }
        recentDocumentURLs = refreshedRecentURLs
        notifyChange(.recentFiles, persistState: false)
    }

    func close(sessionID: UUID) {
        close(sessionID: sessionID, from: defaultWindowID)
    }

    func close(sessionID: UUID, from windowID: UUID) {
        guard let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let publicID = publicSessionID(for: sessionID, in: windowWorkspaces[workspaceIndex]),
              let closedSession = session(for: publicID) else { return }
        let sessionID = publicID

        let sessionIndexInWindow = windowWorkspaces[workspaceIndex].sessionIDs.firstIndex(of: sessionID)
        let closesVisibleSplitSession = isSessionReferencedInSplit(sessionID, workspace: windowWorkspaces[workspaceIndex])
        guard sessionIndexInWindow != nil || closesVisibleSplitSession else { return }

        if let sessionIndexInWindow {
            windowWorkspaces[workspaceIndex].sessionIDs.remove(at: sessionIndexInWindow)
        }
        if closedSession.isBlank == false {
            pushRecentlyClosed(closedSession.url, in: windowID)
        }
        let remainingWindowSessionIDs = windowWorkspaces[workspaceIndex].sessionIDs
        let preferredSessionID = sessionIndexInWindow == nil || remainingWindowSessionIDs.isEmpty
            ? nil
            : remainingWindowSessionIDs[min(max((sessionIndexInWindow ?? 0) - 1, 0), remainingWindowSessionIDs.count - 1)]
        clearSplitReferences(to: sessionID, in: &windowWorkspaces[workspaceIndex])
        normalizeWorkspace(&windowWorkspaces[workspaceIndex], preferredSessionID: preferredSessionID)
        removeUnreferencedSessions()
        rebuildSearchIfNeeded(in: windowID)
        notifyChange([.content, .tabs], windowIDs: [windowID])
    }

    func popRecentlyClosed() -> URL? {
        popRecentlyClosed(in: defaultWindowID)
    }

    func popRecentlyClosed(in windowID: UUID) -> URL? {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].recentlyClosedURLs.isEmpty == false else { return nil }
        let url = windowWorkspaces[index].recentlyClosedURLs.removeLast()
        notifyChange(.content, windowIDs: [windowID])
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
        activateSession(sessionID: sessionID, in: windowID, targetPane: targetPane, notify: true)
    }

    /// Activates a user-facing tab as one store mutation so selection, search
    /// teardown and reader activation publish a single coherent snapshot.
    func activateTab(sessionID: UUID, in windowID: UUID, targetPane: ReaderPane? = nil) {
        guard session(for: sessionID) != nil,
              let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[workspaceIndex].sessionIDs.contains(sessionID) else { return }

        let previousSearchTargetIDs = Set(
            searchSnapshots[windowID]?.source.targets.map(\.sessionID) ?? []
        )
        cancelSearchOperation(in: windowID)
        searchSnapshots.removeValue(forKey: windowID)

        var workspace = windowWorkspaces[workspaceIndex]
        workspace.selectedSessionIDs = [sessionID]
        selectionAnchorIDsByWorkspace[workspace.activeWorkspaceID] = sessionID
        workspace.searchQuery = ""
        if workspace.rightSidebarMode == .search {
            workspace.rightSidebarMode = .outline
        }
        if let targetPane {
            _ = activateSessionForSplitEdit(
                sessionID: sessionID,
                targetPane: targetPane,
                in: &workspace
            )
        } else {
            activateSessionForTabNavigation(sessionID: sessionID, in: &workspace)
        }
        normalizeWorkspace(&workspace)
        windowWorkspaces[workspaceIndex] = workspace
        removeUnreferencedSessions()
        recordActiveDocument(in: windowID)
        clearUnusedSearchCaches(for: previousSearchTargetIDs)
        prunePDFDocumentCache()
        notifyChange([.tabs, .search, .rightSidebarMode], windowIDs: [windowID])
    }

    private func activateSession(sessionID: UUID, in windowID: UUID, targetPane: ReaderPane?, notify: Bool) {
        guard session(for: sessionID) != nil,
              let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }

        var workspace = windowWorkspaces[workspaceIndex]
        guard workspace.sessionIDs.contains(sessionID) else { return }
        if let targetPane {
            _ = activateSessionForSplitEdit(
                sessionID: sessionID,
                targetPane: targetPane,
                in: &workspace
            )
        } else {
            activateSessionForTabNavigation(sessionID: sessionID, in: &workspace)
        }

        normalizeWorkspace(&workspace)
        windowWorkspaces[workspaceIndex] = workspace
        removeUnreferencedSessions()
        recordActiveDocument(in: windowID)
        rebuildSearchIfNeeded(in: windowID)
        if notify {
            notifyChange(.tabs, windowIDs: [windowID])
        }
    }

    func activatePreviousSession() {
        activatePreviousSession(in: defaultWindowID)
    }

    func activatePreviousSession(in windowID: UUID) {
        guard let workspace = windowWorkspace(for: windowID),
              let activeSessionID = workspace.activeSessionID,
              let tabSessionID = publicSessionID(for: activeSessionID, in: workspace),
              let currentIndex = workspace.sessionIDs.firstIndex(of: tabSessionID),
              workspace.sessionIDs.count > 1 else { return }
        let previousIndex = (currentIndex - 1 + workspace.sessionIDs.count) % workspace.sessionIDs.count
        activateTab(sessionID: workspace.sessionIDs[previousIndex], in: windowID)
    }

    func activateNextSession() {
        activateNextSession(in: defaultWindowID)
    }

    func activateNextSession(in windowID: UUID) {
        guard let workspace = windowWorkspace(for: windowID),
              let activeSessionID = workspace.activeSessionID,
              let tabSessionID = publicSessionID(for: activeSessionID, in: workspace),
              let currentIndex = workspace.sessionIDs.firstIndex(of: tabSessionID),
              workspace.sessionIDs.count > 1 else { return }
        let nextIndex = (currentIndex + 1) % workspace.sessionIDs.count
        activateTab(sessionID: workspace.sessionIDs[nextIndex], in: windowID)
    }

    func selectedSessionIDs(in windowID: UUID) -> Set<UUID> {
        windowWorkspace(for: windowID)?.selectedSessionIDs ?? []
    }

    func selectedSessionIDsInWindowOrder(in windowID: UUID) -> [UUID] {
        guard let workspace = windowWorkspace(for: windowID) else { return [] }
        return workspace.sessionIDs.filter { workspace.selectedSessionIDs.contains($0) }
    }

    func selectSessions(_ sessionIDs: [UUID], in windowID: UUID) {
        selectSessions(sessionIDs, in: windowID, notify: true)
    }

    private func selectSessions(_ sessionIDs: [UUID], in windowID: UUID, notify: Bool) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let validIDs = Set(windowWorkspaces[index].sessionIDs)
        let selected = Set(sessionIDs.filter { validIDs.contains($0) })
        selectionAnchorIDsByWorkspace[windowWorkspaces[index].activeWorkspaceID] =
            sessionIDs.first { validIDs.contains($0) }
        guard windowWorkspaces[index].selectedSessionIDs != selected else { return }
        windowWorkspaces[index].selectedSessionIDs = selected
        if notify {
            notifyChange(.tabs, windowIDs: [windowID], persistState: false)
        }
    }

    func toggleSessionSelection(_ sessionID: UUID, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].sessionIDs.contains(sessionID) else { return }
        var selected = windowWorkspaces[index].selectedSessionIDs
        if selected.contains(sessionID) {
            selected.remove(sessionID)
        } else {
            selected.insert(sessionID)
        }
        windowWorkspaces[index].selectedSessionIDs = selected
        selectionAnchorIDsByWorkspace[windowWorkspaces[index].activeWorkspaceID] =
            selected.contains(sessionID) ? sessionID : windowWorkspaces[index].sessionIDs.first { selected.contains($0) }
        notifyChange(.tabs, windowIDs: [windowID], persistState: false)
    }

    func selectSessionRange(through sessionID: UUID, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let targetIndex = windowWorkspaces[index].sessionIDs.firstIndex(of: sessionID) else { return }
        let workspace = windowWorkspaces[index]
        let activeTabID = publicSessionID(for: workspace.activeSessionID, in: workspace)
        let anchorID = selectionAnchorIDsByWorkspace[workspace.activeWorkspaceID]
            ?? activeTabID.flatMap { workspace.selectedSessionIDs.contains($0) ? $0 : nil }
            ?? workspace.sessionIDs.first { workspace.selectedSessionIDs.contains($0) }
            ?? activeTabID
            ?? workspace.sessionIDs.first
        guard let anchorID,
              let anchorIndex = workspace.sessionIDs.firstIndex(of: anchorID) else { return }
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectionAnchorIDsByWorkspace[workspace.activeWorkspaceID] = anchorID
        windowWorkspaces[index].selectedSessionIDs = Set(workspace.sessionIDs[bounds])
        notifyChange(.tabs, windowIDs: [windowID], persistState: false)
    }

    func isContinuousReadingEnabled(in windowID: UUID) -> Bool {
        windowWorkspace(for: windowID)?.continuousReadingState.isEnabled == true
    }

    func continuousReadingSessionIDs(in windowID: UUID) -> [UUID] {
        windowWorkspace(for: windowID)?.continuousReadingState.orderedSessionIDs ?? []
    }

    func canStartContinuousReadingFromSelection(in windowID: UUID) -> Bool {
        continuousReadingSelection(in: windowID).count > 1
    }

    private func continuousReadingSelection(in windowID: UUID) -> [UUID] {
        selectedSessionIDsInWindowOrder(in: windowID).filter { session(for: $0)?.isBlank == false }
    }

    @discardableResult
    func startContinuousReadingFromSelectedSessions(in windowID: UUID) -> Bool {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return false }
        let workspace = windowWorkspaces[index]
        let orderedSelection = continuousReadingSelection(in: windowID)
        guard orderedSelection.count > 1 else { return false }
        windowWorkspaces[index].continuousReadingState = ContinuousReadingState(orderedSessionIDs: orderedSelection)
        windowWorkspaces[index].selectedSessionIDs = Set(orderedSelection)
        let activeTabID = publicSessionID(for: workspace.activeSessionID, in: workspace)
        if selectionAnchorIDsByWorkspace[workspace.activeWorkspaceID].map({ orderedSelection.contains($0) }) != true {
            selectionAnchorIDsByWorkspace[workspace.activeWorkspaceID] =
                activeTabID.flatMap { orderedSelection.contains($0) ? $0 : nil } ?? orderedSelection.first
        }
        if activeTabID.map({ orderedSelection.contains($0) }) != true,
           let firstSessionID = orderedSelection.first {
            activateSession(sessionID: firstSessionID, in: windowID, targetPane: nil, notify: false)
        }
        notifyChange([.content, .tabs], windowIDs: [windowID])
        return true
    }

    func stopContinuousReading(in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].continuousReadingState.isEnabled else { return }
        windowWorkspaces[index].continuousReadingState = ContinuousReadingState()
        notifyChange([.content, .tabs], windowIDs: [windowID])
    }

    @discardableResult
    func toggleContinuousReadingFromSelection(in windowID: UUID) -> Bool {
        if isContinuousReadingEnabled(in: windowID) {
            stopContinuousReading(in: windowID)
            return false
        }
        return startContinuousReadingFromSelectedSessions(in: windowID)
    }

    func continuousReadingTarget(from sessionID: UUID, direction: Int, in windowID: UUID) -> ContinuousReadingTarget? {
        guard direction != 0,
              let workspace = windowWorkspace(for: windowID),
              workspace.continuousReadingState.isEnabled,
              let currentIndex = workspace.continuousReadingState.orderedSessionIDs.firstIndex(of: sessionID) else {
            return nil
        }
        let targetIndex = direction > 0 ? currentIndex + 1 : currentIndex - 1
        guard workspace.continuousReadingState.orderedSessionIDs.indices.contains(targetIndex) else { return nil }
        let targetSessionID = workspace.continuousReadingState.orderedSessionIDs[targetIndex]
        guard let document = try? pdfDocument(for: targetSessionID), document.pageCount > 0 else { return nil }
        let pageIndex = direction > 0 ? 0 : document.pageCount - 1
        guard let page = document.page(at: pageIndex) else { return nil }
        let pageBounds = page.bounds(for: .cropBox)
        let readingPosition = direction > 0
            ? ReadingPosition.pageTop(pageIndex: pageIndex, pageBounds: pageBounds)
            : ReadingPosition.pageBottom(pageIndex: pageIndex, pageBounds: pageBounds)
        return ContinuousReadingTarget(sessionID: targetSessionID, readingPosition: readingPosition)
    }

    @discardableResult
    func activateContinuousReadingTarget(
        _ target: ContinuousReadingTarget,
        in windowID: UUID,
        targetPane: ReaderPane?
    ) -> UUID? {
        guard let workspaceIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else {
            return nil
        }
        var workspace = windowWorkspaces[workspaceIndex]
        guard workspace.sessionIDs.contains(target.sessionID) else { return nil }

        if let targetPane {
            _ = activateSessionForSplitEdit(
                sessionID: target.sessionID,
                targetPane: targetPane,
                in: &workspace
            )
        } else {
            activateSessionForTabNavigation(sessionID: target.sessionID, in: &workspace)
        }
        normalizeWorkspace(&workspace)

        let resolvedSessionID = targetPane.flatMap { workspace.activeWorkspace.activeGroup?.sessionIDsByPane[$0] }
            ?? workspace.activeSessionID
        guard let resolvedSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == resolvedSessionID }) else {
            return nil
        }

        sessions[sessionIndex].currentPageIndex = target.readingPosition.pageIndex
        sessions[sessionIndex].lastReadPosition = target.readingPosition
        sessions[sessionIndex].needsInitialReadingPosition = false
        persistReadingState(for: sessions[sessionIndex])
        windowWorkspaces[workspaceIndex] = workspace
        removeUnreferencedSessions()
        rebuildSearchIfNeeded(in: windowID)
        notifyChange([.tabs, .readingPosition], windowIDs: [windowID], sessionIDs: [resolvedSessionID])
        return resolvedSessionID
    }

    func setFocusedPane(_ pane: ReaderPane, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].paneIDs.contains(pane),
              windowWorkspaces[index].focusedPane != pane else { return }
        windowWorkspaces[index].focusedPane = pane
        recordActiveDocument(in: windowID)
        rebuildSearchIfNeeded(in: windowID)
        notifyChange(.tabs, windowIDs: [windowID])
    }

    func setSplitEnabled(_ isEnabled: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].isSplitEnabled != isEnabled,
              windowWorkspaces[index].activeSessionID != nil else { return }
        if isEnabled {
            windowWorkspaces[index].isSplitEnabled = true
        } else {
            guard let focusedID = windowWorkspaces[index].activeSessionID,
                  let publicID = publicSessionID(for: focusedID, in: windowWorkspaces[index]),
                  var group = windowWorkspaces[index].activeWorkspace.activeGroup else { return }
            if focusedID != publicID, let focused = session(for: focusedID) { copyReadingState(from: focused, to: publicID) }
            group.root = .pane(.primary)
            group.sessionIDsByPane = [.primary: publicID]
            group.focusedPane = .primary
            group.zoomedPane = nil
            windowWorkspaces[index].activeWorkspace.activeGroup = group
        }
        removeUnreferencedSessions()
        rebuildSearchIfNeeded(in: windowID)
        notifyChange(.content, windowIDs: [windowID])
    }

    func setSplitLayout(_ layout: ReaderSplitLayout, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].splitLayout != layout else { return }
        windowWorkspaces[index].splitLayout = layout
        notifyChange(.tabs, windowIDs: [windowID])
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
        notifyChange([.tabs, .sidebarVisibility], windowIDs: [windowID])
    }

    func session(for id: UUID) -> DocumentSession? {
        guard var session = sessions.first(where: { $0.id == id }) else { return nil }
        if let sourceID = sharedDocumentSources[id],
           let source = sessions.first(where: { $0.id == sourceID }) {
            session.isDirty = source.isDirty
            session.dirtySince = source.dirtySince
            session.annotationGeneration = source.annotationGeneration
            session.annotationSavePolicy = source.annotationSavePolicy
            session.annotationCache = source.annotationCache
            session.isAnnotationCacheLoaded = source.isAnnotationCacheLoaded
            session.undoStack = source.undoStack
            session.redoStack = source.redoStack
        }
        return session
    }

    func documentSessionID(for sessionID: UUID) -> UUID {
        sharedDocumentSources[sessionID] ?? sessionID
    }

    func isPDFDocumentLoaded(for sessionID: UUID) -> Bool {
        loadedPDFDocument(for: sessionID) != nil
    }

    func loadedPDFDocument(for sessionID: UUID) -> PDFDocument? {
        pdfDocumentCache[documentSessionID(for: sessionID)]
    }

    func discardCleanBackgroundDocuments() {
        let pinned = pinnedPDFDocumentIDs()
        let victims = pdfDocumentCache.keys.filter { sessionID in
            guard pinned.contains(sessionID) == false,
                  let session = session(for: sessionID) else { return false }
            return session.isDirty == false
        }
        for sessionID in victims {
            discardPDFDocumentCache(for: sessionID)
        }
    }

    @discardableResult
    func pdfDocument(for sessionID: UUID) throws -> PDFDocument {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw DocumentStoreError.missingSession(sessionID)
        }
        guard sessions[sessionIndex].isBlank == false else {
            throw DocumentStoreError.blankSession(sessionID)
        }
        if let sourceID = sharedDocumentSources[sessionID] {
            let document = try pdfDocument(for: sourceID)
            sessions[sessionIndex].pageCount = document.pageCount
            if sessions[sessionIndex].firstPagePosition == nil, let firstPage = document.page(at: 0) {
                sessions[sessionIndex].firstPagePosition = ReadingPosition.pageTop(pageIndex: 0, pageBounds: firstPage.bounds(for: .cropBox))
            }
            clampReadingPositionIfNeeded(for: sessionIndex, in: document)
            return document
        }
        if let document = pdfDocumentCache[sessionID] {
            touchPDFDocument(sessionID)
            return document
        }

        let url = sessions[sessionIndex].url
        guard let document = PDFDocument(url: url) else {
            throw DocumentStoreError.unreadableDocument(url)
        }

        HighlightService.consolidateComments(in: document)

        pdfDocumentCache[sessionID] = document
        touchPDFDocument(sessionID)
        sessions[sessionIndex].pageCount = document.pageCount
        sessions[sessionIndex].fileSnapshot = PDFFileSnapshot(url: url)
        if sessions[sessionIndex].firstPagePosition == nil,
           let firstPage = document.page(at: 0) {
            sessions[sessionIndex].firstPagePosition = ReadingPosition.pageTop(
                pageIndex: 0,
                pageBounds: firstPage.bounds(for: .cropBox)
            )
        }
        clampReadingPositionIfNeeded(for: sessionIndex, in: document)
        prunePDFDocumentCache()
        return document
    }

    func outlineTree(for sessionID: UUID) -> [OutlineNode] {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return [] }
        guard sessions[sessionIndex].isBlank == false else { return [] }
        if sessions[sessionIndex].isOutlineLoaded {
            return sessions[sessionIndex].outlineTree
        }
        guard let document = try? pdfDocument(for: sessionID) else { return [] }
        let outlineTree = OutlineExtractor.extract(from: document).withSourceSessionID(sessionID)
        sessions[sessionIndex].outlineTree = outlineTree
        sessions[sessionIndex].isOutlineLoaded = true
        return outlineTree
    }

    func outlineTreeForSidebar(in windowID: UUID) -> [OutlineNode] {
        if let cached = outlineSnapshots[windowID] {
            return cached
        }
        guard let workspace = windowWorkspace(for: windowID) else { return [] }
        if workspace.continuousReadingState.isEnabled {
            let roots: [OutlineNode] = workspace.continuousReadingState.orderedSessionIDs.compactMap { sessionID in
                guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
                if sessions[sessionIndex].firstPagePosition == nil {
                    _ = try? pdfDocument(for: sessionID)
                }
                guard let firstPosition = sessions[sessionIndex].firstPagePosition else { return nil }
                return OutlineNode(
                    title: sessions[sessionIndex].title,
                    pageIndex: firstPosition.pageIndex,
                    destinationPoint: firstPosition.point,
                    children: outlineTree(for: sessionID),
                    sourceSessionID: sessionID,
                    isDocumentRoot: true
                )
            }
            outlineSnapshots[windowID] = roots
            return roots
        }

        guard let sessionID = workspace.activeSessionID else { return [] }
        let roots = outlineTree(for: sessionID)
        outlineSnapshots[windowID] = roots
        return roots
    }

    func pageCount(for sessionID: UUID) -> Int? {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        if let pageCount = sessions[sessionIndex].pageCount {
            return pageCount
        }
        return loadedPDFDocument(for: sessionID)?.pageCount
    }

    func refreshExternallyChangedFile(at url: URL) {
        let normalizedURL = url.standardizedFileURL
        let matchingIndexes = sessions.indices.filter {
            sessions[$0].isBlank == false && sessions[$0].url.standardizedFileURL == normalizedURL
        }
        guard matchingIndexes.isEmpty == false,
              let snapshot = PDFFileSnapshot(url: normalizedURL),
              matchingIndexes.contains(where: {
                  sharedDocumentSources[sessions[$0].id] == nil && sessions[$0].fileSnapshot != snapshot
              }) else { return }

        guard matchingIndexes.allSatisfy({ sessions[$0].isDirty == false }) else { return }

        let invalidatedSessionIDs = Set(matchingIndexes.map { sessions[$0].id })
        for index in matchingIndexes {
            invalidateCleanSessionAfterExternalChange(at: index, snapshot: snapshot)
        }
        invalidateSearchSnapshots(referencing: invalidatedSessionIDs)
        notifyChange(.content, sessionIDs: invalidatedSessionIDs)
    }

    func updateCurrentPage(index: Int, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let document = try? pdfDocument(for: sessionID),
              let page = document.page(at: index) else { return }
        let position = ReadingPosition.pageTop(
            pageIndex: index,
            pageBounds: page.bounds(for: .cropBox)
        )
        guard sessions[sessionIndex].currentPageIndex != index ||
                sessions[sessionIndex].lastReadPosition != position else { return }

        sessions[sessionIndex].currentPageIndex = index
        sessions[sessionIndex].lastReadPosition = position
        sessions[sessionIndex].needsInitialReadingPosition = false
        persistReadingState(for: sessions[sessionIndex])
        notifyChange(.readingPosition, sessionIDs: [sessionID])
    }

    func setDisplayMode(_ mode: ReaderDisplayMode, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].displayMode != mode else { return }
        sessions[sessionIndex].displayMode = mode
        if mode.usesBookLayout {
            sessions[sessionIndex].isHorizontalPanLocked = false
        }
        persistReadingState(for: sessions[sessionIndex])
        notifyChange(.content, sessionIDs: [sessionID])
    }

    func effectiveHorizontalPanLock(for session: DocumentSession) -> Bool {
        !session.isBlank && !session.displayMode.usesBookLayout &&
            (appConfiguration.reader.globalHorizontalPanLock || session.isHorizontalPanLocked)
    }

    func setHorizontalPanLocked(_ enabled: Bool, for sessionID: UUID) {
        guard !appConfiguration.reader.globalHorizontalPanLock else { return }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              !sessions[index].isBlank,
              !enabled || !sessions[index].displayMode.usesBookLayout,
              sessions[index].isHorizontalPanLocked != enabled else { return }
        sessions[index].isHorizontalPanLocked = enabled
        persistReadingState(for: sessions[index])
        notifyChange(.content, sessionIDs: [sessionID])
    }

    func toggleDisplayModeContinuity(for sessionID: UUID) {
        guard let session = session(for: sessionID) else { return }
        setDisplayMode(session.displayMode.toggledContinuity, for: sessionID)
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
        if modeChanged {
            notifyChange(.content, sessionIDs: [sessionID])
        } else if mode == .manual {
            notifyChange(.readingPosition, sessionIDs: [sessionID])
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
        sessions[sessionIndex].needsInitialReadingPosition = false
        sessions[sessionIndex].zoomScale = scaleFactor
        persistReadingState(for: sessions[sessionIndex])
        if pageChanged || scaleChanged {
            notifyChange(.readingPosition, sessionIDs: [sessionID])
        }
    }

    func setLeftSidebarVisible(_ isVisible: Bool) {
        setLeftSidebarVisible(isVisible, in: defaultWindowID)
    }

    func setLeftSidebarVisible(_ isVisible: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let explicitlyControlsOutline = appConfiguration.layout.sidebarsSwapped &&
            windowWorkspaces[index].sessionIDs.isEmpty
        let clearsAutoHiddenState = explicitlyControlsOutline &&
            outlineAutoHiddenWindowIDs.contains(windowID)
        let recordsEmptyWindowIntent = explicitlyControlsOutline &&
            windowWorkspaces[index].outlineVisibilityWhileEmpty != isVisible
        guard windowWorkspaces[index].isLeftSidebarVisible != isVisible ||
              clearsAutoHiddenState || recordsEmptyWindowIntent else { return }
        windowWorkspaces[index].isLeftSidebarVisible = isVisible
        if explicitlyControlsOutline {
            outlineAutoHiddenWindowIDs.remove(windowID)
            windowWorkspaces[index].outlineVisibilityWhileEmpty = isVisible
        }
        notifyChange(.sidebarVisibility, windowIDs: [windowID])
    }

    func setRightSidebarVisible(_ isVisible: Bool) {
        setRightSidebarVisible(isVisible, in: defaultWindowID)
    }

    func setRightSidebarVisible(_ isVisible: Bool, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let explicitlyControlsOutline = appConfiguration.layout.sidebarsSwapped == false &&
            windowWorkspaces[index].sessionIDs.isEmpty
        let clearsAutoHiddenState = explicitlyControlsOutline &&
            outlineAutoHiddenWindowIDs.contains(windowID)
        let recordsEmptyWindowIntent = explicitlyControlsOutline &&
            windowWorkspaces[index].outlineVisibilityWhileEmpty != isVisible
        guard windowWorkspaces[index].isRightSidebarVisible != isVisible ||
              clearsAutoHiddenState || recordsEmptyWindowIntent else { return }
        windowWorkspaces[index].isRightSidebarVisible = isVisible
        // An explicit toggle while the window is empty hands visibility back to
        // the user; the auto-collapse must not restore the pane on first open.
        if explicitlyControlsOutline {
            outlineAutoHiddenWindowIDs.remove(windowID)
            windowWorkspaces[index].outlineVisibilityWhileEmpty = isVisible
        }
        notifyChange(.sidebarVisibility, windowIDs: [windowID])
    }

    func setRightSidebarMode(_ mode: RightSidebarMode, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        guard windowWorkspaces[index].rightSidebarMode != mode else { return }
        windowWorkspaces[index].rightSidebarMode = mode
        notifyChange(.rightSidebarMode, windowIDs: [windowID])
    }

    func toggleRightSidebarMode(in windowID: UUID) {
        let nextMode = rightSidebarMode(in: windowID).toggledPreviewMode()
        setRightSidebarMode(nextMode, in: windowID)
    }

    func updateSearch(
        query: String,
        scope: SearchScope,
        options: SearchOptions = .default,
        in windowID: UUID
    ) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        windowWorkspaces[index].searchScope = scope
        windowWorkspaces[index].searchQuery = trimmed
        searchOptionsByWindowID[windowID] = options

        if trimmed.isEmpty {
            cancelSearchOperation(in: windowID)
            let previousTargetIDs = Set(searchSnapshots[windowID]?.source.targets.map(\.sessionID) ?? [])
            searchSnapshots.removeValue(forKey: windowID)
            if windowWorkspaces[index].rightSidebarMode == .search {
                windowWorkspaces[index].rightSidebarMode = .outline
            }
            clearUnusedSearchCaches(for: previousTargetIDs)
            prunePDFDocumentCache()
            notifyChange([.search, .rightSidebarMode], windowIDs: [windowID])
            return
        }

        rebuildSearchIfNeeded(in: windowID)
        windowWorkspaces[index].rightSidebarMode = .search
        notifyChange([.search, .rightSidebarMode], windowIDs: [windowID])
    }

    func clearSearch(in windowID: UUID) {
        updateSearch(
            query: "",
            scope: searchScope(in: windowID),
            options: searchOptions(in: windowID),
            in: windowID
        )
    }

    func searchSnapshot(in windowID: UUID) -> SearchSnapshot {
        searchSnapshots[windowID] ?? SearchSnapshot.empty(
            query: searchQuery(in: windowID),
            scope: searchScope(in: windowID),
            options: searchOptions(in: windowID)
        )
    }

    func searchSelection(for match: SearchSidebarMatch) -> PDFSelection? {
        searchSelection(
            pageIndex: match.pageIndex,
            textRange: match.textRange,
            sessionID: match.sessionID
        )
    }

    func searchSelections(for sessionID: UUID, in windowID: UUID) -> [PDFSelection] {
        searchSnapshot(in: windowID).matches(for: sessionID)
            .prefix(Self.highlightedSearchSelectionLimit)
            .compactMap { match in
            searchSelection(
                pageIndex: match.pageIndex,
                textRange: match.textRange,
                sessionID: sessionID
            )
            }
    }

    private func searchSelection(
        pageIndex: Int,
        textRange: NSRange,
        sessionID: UUID
    ) -> PDFSelection? {
        guard let document = try? pdfDocument(for: sessionID),
              let page = document.page(at: pageIndex) else { return nil }
        return page.selection(for: textRange)
    }

    func annotationSections(in windowID: UUID) -> [DocumentHighlightSection] {
        guard let activeID = activeSessionID(in: windowID) else { return [] }
        let sessionID = documentSessionID(for: activeID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return [] }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        guard let refreshedSessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return [] }
        let grouped = Dictionary(grouping: sessions[refreshedSessionIndex].annotationCache.groups) { $0.pageIndex }
        return grouped
            .keys
            .sorted()
            .map { pageIndex in
                DocumentHighlightSection(
                    title: L10n.text("Page \(pageIndex + 1)", "第 \(pageIndex + 1) 页"),
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
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return [] }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        return sessions.first(where: { $0.id == sessionID })?.annotationCache.groups ?? []
    }

    func annotationGroup(
        containing annotation: PDFAnnotation,
        for sessionID: UUID
    ) -> DocumentHighlightGroup? {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        guard let refreshedIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        return sessions[refreshedIndex].annotationCache.group(containing: annotation)
    }

    @discardableResult
    func removeHighlightGroup(
        _ group: DocumentHighlightGroup,
        in sessionID: UUID,
        now: Date = Date()
    ) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let document = loadedPDFDocument(for: sessionID),
              group.records.allSatisfy({ $0.annotation.page?.document === document }) else { return false }

        HighlightService.removeHighlights(group.records, in: document)
        noteHighlightsRemoved(group.records, for: sessionID, now: now)
        return true
    }

    func hasHighlights(for sessionID: UUID) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        return sessions.first(where: { $0.id == sessionID })?.annotationCache.groups.isEmpty == false
    }

    func setDirty(_ isDirty: Bool, for sessionID: UUID, now: Date = Date()) {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].isDirty != isDirty else { return }

        sessions[sessionIndex].isDirty = isDirty
        sessions[sessionIndex].dirtySince = isDirty ? (sessions[sessionIndex].dirtySince ?? now) : nil
        if isDirty == false {
            prunePDFDocumentCache()
        }
        notifyChange(.annotations, sessionIDs: [sessionID])
    }

    func noteHighlightsAdded(_ records: [HighlightAnnotationRecord], for sessionID: UUID, now: Date = Date()) {
        let sessionID = documentSessionID(for: sessionID)
        guard records.isEmpty == false,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(.added(records))
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
        markAnnotationsDirty(for: sessionIndex, now: now)
        upsertCachedAnnotationGroups(from: records, for: sessionIndex)
        notifyChange(.annotations, sessionIDs: [sessionID])
    }

    func noteHighlightsRemoved(_ records: [HighlightAnnotationRecord], for sessionID: UUID, now: Date = Date()) {
        let sessionID = documentSessionID(for: sessionID)
        guard records.isEmpty == false,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(.removed(records))
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
        markAnnotationsDirty(for: sessionIndex, now: now)
        removeCachedAnnotationGroups(for: records, from: sessionIndex)
        notifyChange(.annotations, sessionIDs: [sessionID])
    }

    @discardableResult
    func updateComment(_ comment: String, forHighlightGroup groupID: String, in sessionID: UUID, now: Date = Date()) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let group = sessions[sessionIndex].annotationCache.groups.first(where: { $0.groupID == groupID }),
              HighlightService.updateComment(comment, for: group.records) else { return false }

        markAnnotationsDirty(for: sessionIndex, now: now)
        upsertCachedAnnotationGroups(from: group.records, for: sessionIndex)
        notifyChange(.annotations, sessionIDs: [sessionID])
        return true
    }

    @discardableResult
    func updateHighlightColor(
        _ color: HighlightColor,
        forHighlightGroup groupID: String,
        in sessionID: UUID,
        now: Date = Date()
    ) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        ensureAnnotationCacheLoaded(for: sessionIndex)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let group = sessions[sessionIndex].annotationCache.groups.first(where: { $0.groupID == groupID }),
              HighlightService.updateColor(
                NightModeStyle.highlightColor(for: color),
                for: group.records
              ) else { return false }

        markAnnotationsDirty(for: sessionIndex, now: now)
        upsertCachedAnnotationGroups(from: group.records, for: sessionIndex)
        notifyChange(.annotations, sessionIDs: [sessionID])
        return true
    }

    func recordHighlightUndo(_ operation: HighlightUndoOperation, for sessionID: UUID) {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].undoStack.append(operation)
        sessions[sessionIndex].redoStack.removeAll()
        trimUndoStack(for: sessionIndex)
    }

    func hasUndoableHighlight(for sessionID: UUID) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        return session.undoStack.isEmpty == false
    }

    func hasRedoableHighlight(for sessionID: UUID) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        return session.redoStack.isEmpty == false
    }

    @discardableResult
    func undoLastHighlight(for sessionID: UUID) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let document = try? pdfDocument(for: sessionID),
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let operation = sessions[sessionIndex].undoStack.popLast() else { return false }

        switch operation {
        case let .added(records):
            HighlightService.removeHighlights(records, in: document)
        case let .removed(records):
            HighlightService.reinsertHighlights(records, in: document)
        }

        sessions[sessionIndex].redoStack.append(operation)
        markAnnotationsDirty(for: sessionIndex, now: Date())
        switch operation {
        case let .added(records):
            removeCachedAnnotationGroups(for: records, from: sessionIndex)
        case let .removed(records):
            upsertCachedAnnotationGroups(from: records, for: sessionIndex)
        }
        notifyChange(.annotations, sessionIDs: [sessionID])
        return true
    }

    @discardableResult
    func redoLastHighlight(for sessionID: UUID) -> Bool {
        let sessionID = documentSessionID(for: sessionID)
        guard let document = try? pdfDocument(for: sessionID),
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let operation = sessions[sessionIndex].redoStack.popLast() else { return false }

        switch operation {
        case let .added(records):
            HighlightService.reinsertHighlights(records, in: document)
        case let .removed(records):
            HighlightService.removeHighlights(records, in: document)
        }

        sessions[sessionIndex].undoStack.append(operation)
        markAnnotationsDirty(for: sessionIndex, now: Date())
        switch operation {
        case let .added(records):
            upsertCachedAnnotationGroups(from: records, for: sessionIndex)
        case let .removed(records):
            removeCachedAnnotationGroups(for: records, from: sessionIndex)
        }
        notifyChange(.annotations, sessionIDs: [sessionID])
        return true
    }

    func setAnnotationSavePolicy(_ policy: AnnotationSavePolicy, for sessionID: UUID) {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].annotationSavePolicy != policy else { return }
        sessions[sessionIndex].annotationSavePolicy = policy
        notifyChange(.annotations, sessionIDs: [sessionID])
    }

    func updateAppConfiguration(_ configuration: AppConfiguration) {
        guard appConfiguration != configuration else { return }
        let previousFitWidthOnOpen = appConfiguration.reader.fitWidthOnOpen
        let previousSwapped = appConfiguration.layout.sidebarsSwapped
        let newSwapped = configuration.layout.sidebarsSwapped
        let widthChangesOnlySwapDefaults = previousSwapped != newSwapped &&
            appConfiguration.layout.leftSidebarWidth == configuration.layout.rightSidebarWidth &&
            appConfiguration.layout.rightSidebarWidth == configuration.layout.leftSidebarWidth
        let layoutWidthsChanged = !widthChangesOnlySwapDefaults && (
            appConfiguration.layout.leftSidebarWidth != configuration.layout.leftSidebarWidth ||
            appConfiguration.layout.rightSidebarWidth != configuration.layout.rightSidebarWidth
        )
        appConfiguration = configuration

        let fitWidthChanged = previousFitWidthOnOpen != configuration.reader.fitWidthOnOpen
        let targetScaleMode: ReaderScaleMode = configuration.reader.fitWidthOnOpen ? .fitWidth : .manual

        for index in windowWorkspaces.indices {
            if previousSwapped != newSwapped {
                let leftVisible = windowWorkspaces[index].isLeftSidebarVisible
                windowWorkspaces[index].isLeftSidebarVisible = windowWorkspaces[index].isRightSidebarVisible
                windowWorkspaces[index].isRightSidebarVisible = leftVisible
                let leftWidth = windowWorkspaces[index].leftSidebarWidth
                windowWorkspaces[index].leftSidebarWidth = windowWorkspaces[index].rightSidebarWidth
                windowWorkspaces[index].rightSidebarWidth = leftWidth
            }
            if layoutWidthsChanged {
                windowWorkspaces[index].leftSidebarWidth = configuration.layout.leftSidebarWidth
                windowWorkspaces[index].rightSidebarWidth = configuration.layout.rightSidebarWidth
            }
        }

        for index in sessions.indices {
            sessions[index].annotationSavePolicy = configuration.annotations.autoSavePolicy
            if fitWidthChanged, sessions[index].scaleMode != targetScaleMode {
                sessions[index].scaleMode = targetScaleMode
                persistReadingState(for: sessions[index])
            }
        }

        notifyChange(.appearance)
    }

    func saveAnnotations(for sessionID: UUID) throws {
        let sessionID = documentSessionID(for: sessionID)
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].isBlank == false else { return }
        guard sessions[sessionIndex].isDirty else { return }
        let document = try pdfDocument(for: sessionID)
        guard document.write(to: sessions[sessionIndex].url) else {
            throw DocumentStoreError.failedToSaveDocument(sessions[sessionIndex].url)
        }

        sessions[sessionIndex].annotationGeneration &+= 1
        sessions[sessionIndex].isDirty = false
        sessions[sessionIndex].dirtySince = nil
        sessions[sessionIndex].fileSnapshot = PDFFileSnapshot(url: sessions[sessionIndex].url)
        prunePDFDocumentCache()
        notifyChange(.annotations, sessionIDs: [sessionID])
    }

    func currentPageImage(for sessionID: UUID) throws -> NSImage {
        let document = try pdfDocument(for: sessionID)
        guard let session = session(for: sessionID) else {
            throw DocumentStoreError.missingSession(sessionID)
        }
        guard let page = document.page(at: session.currentPageIndex) else {
            throw DocumentStoreError.unreadableDocument(session.url)
        }
        return PDFPageImageService.image(from: page)
    }

    func cleanCopyData(for sessionID: UUID) throws -> Data {
        let document = try pdfDocument(for: sessionID)
        return try CleanPDFService.cleanCopyData(from: document)
    }

    func writeCleanCopy(for sessionID: UUID, to url: URL) throws {
        let document = try pdfDocument(for: sessionID)
        try CleanPDFService.writeCleanCopy(from: document, to: url)
    }

    @discardableResult
    func autoSaveDirtySessions(now: Date = Date()) -> [URL: Error] {
        let prepared = prepareAutoSaveJobs(now: now)
        let results = Self.performAutoSaveJobs(prepared.jobs)
        var errors = prepared.errors
        errors.merge(completeAutoSave(results)) { _, latest in latest }
        return errors
    }

    func prepareAutoSaveJobs(now: Date = Date()) -> (jobs: [AnnotationAutoSaveJob], errors: [URL: Error]) {
        var jobs: [AnnotationAutoSaveJob] = []
        var errors: [URL: Error] = [:]
        for session in sessions where session.isDirty && session.isBlank == false {
            guard let interval = session.annotationSavePolicy.autoSaveInterval,
                  let dirtySince = session.dirtySince,
                  now.timeIntervalSince(dirtySince) >= interval else { continue }
            guard let document = loadedPDFDocument(for: session.id),
                  let data = document.dataRepresentation() else {
                errors[session.url] = DocumentStoreError.failedToSaveDocument(session.url)
                continue
            }
            jobs.append(
                AnnotationAutoSaveJob(
                    sessionID: session.id,
                    url: session.url,
                    annotationGeneration: session.annotationGeneration,
                    data: data
                )
            )
        }
        return (jobs, errors)
    }

    nonisolated static func performAutoSaveJobs(
        _ jobs: [AnnotationAutoSaveJob]
    ) -> [AnnotationAutoSaveResult] {
        jobs.map { job in
            let stagedURL = job.url
                .deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).serein-autosave")
            do {
                try job.data.write(to: stagedURL, options: .atomic)
                return AnnotationAutoSaveResult(
                    job: job,
                    stagedURL: stagedURL,
                    errorDescription: nil
                )
            } catch {
                try? FileManager.default.removeItem(at: stagedURL)
                return AnnotationAutoSaveResult(
                    job: job,
                    stagedURL: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    func completeAutoSave(_ results: [AnnotationAutoSaveResult]) -> [URL: Error] {
        var errors: [URL: Error] = [:]
        var savedSessionIDs: Set<UUID> = []
        for result in results {
            if let errorDescription = result.errorDescription {
                if let stagedURL = result.stagedURL {
                    try? FileManager.default.removeItem(at: stagedURL)
                }
                errors[result.job.url] = NSError(
                    domain: "Serein.AnnotationAutoSave",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: errorDescription]
                )
                continue
            }
            guard let stagedURL = result.stagedURL else { continue }
            guard let index = sessions.firstIndex(where: { $0.id == result.job.sessionID }),
                  sessions[index].url == result.job.url,
                  sessions[index].isDirty,
                  sessions[index].annotationGeneration == result.job.annotationGeneration else {
                try? FileManager.default.removeItem(at: stagedURL)
                continue
            }
            do {
                _ = try FileManager.default.replaceItemAt(result.job.url, withItemAt: stagedURL)
                sessions[index].isDirty = false
                sessions[index].dirtySince = nil
                sessions[index].fileSnapshot = PDFFileSnapshot(url: result.job.url)
                savedSessionIDs.insert(result.job.sessionID)
            } catch {
                try? FileManager.default.removeItem(at: stagedURL)
                errors[result.job.url] = error
            }
        }
        if savedSessionIDs.isEmpty == false {
            prunePDFDocumentCache()
            notifyChange(.annotations, sessionIDs: savedSessionIDs)
        }
        return errors
    }

    func restorePersistedState() throws {
        guard let state = try persistence.loadState() else { return }
        for operation in searchOperations.values { operation.cancel() }
        searchOperations.removeAll()
        sessions = []
        pdfDocumentCache.removeAll()
        pdfDocumentRecency.removeAll()
        searchSnapshots.removeAll()
        searchOptionsByWindowID.removeAll()
        sharedDocumentSources.removeAll()
        var seenIDs = Set<UUID>()
        for reference in state.sessions {
            guard seenIDs.insert(reference.id).inserted else {
                throw DocumentStoreError.invalidPersistedState(L10n.text("Duplicate reading session ID", "阅读会话 ID 重复"))
            }
            let reading: PersistedReadingState?
            let restoredScaleMode: ReaderScaleMode
            if state.workspaceWindows != nil {
                guard let savedReading = reference.readingState else {
                    throw DocumentStoreError.invalidPersistedState(L10n.text("Missing saved reading position", "缺少已保存的阅读位置"))
                }
                reading = savedReading
                restoredScaleMode = savedReading.scaleMode
            } else {
                reading = try readingStateStore.loadState(for: reference.url)
                restoredScaleMode = resolvedScaleMode(reading?.scaleMode)
            }
            var session = DocumentSession(
                id: reference.id, url: reference.url, title: reference.title,
                currentPageIndex: reading?.readingPosition.pageIndex ?? 0,
                displayMode: reading?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
                scaleMode: restoredScaleMode,
                zoomScale: reading?.scaleFactor ?? 1,
                isHorizontalPanLocked: reading?.isHorizontalPanLocked ?? false,
                lastReadPosition: reading?.readingPosition,
                annotationSavePolicy: appConfiguration.annotations.autoSavePolicy)
            if state.workspaceWindows != nil { session.needsInitialReadingPosition = reference.needsInitialReadingPosition }
            session.tabSessionID = reference.tabSessionID
            sessions.append(session)
        }
        // All reading sessions for a file share one live PDF and annotation owner.
        var sourceByURL: [URL: UUID] = [:]
        for reference in state.sessions {
            let url = Self.normalizedDocumentURL(reference.url)
            if let source = reference.documentSourceID {
                guard seenIDs.contains(source), source != reference.id,
                      state.sessions.first(where: { $0.id == source })?.documentSourceID == nil else {
                    throw DocumentStoreError.invalidPersistedState(L10n.text("Invalid shared document source", "共享文档来源无效"))
                }
                sharedDocumentSources[reference.id] = source
                sourceByURL[url] = source
            } else if let source = sourceByURL[url], source != reference.id {
                sharedDocumentSources[reference.id] = source
            } else { sourceByURL[url] = reference.id }
        }
        if let windows = state.workspaceWindows {
            for window in windows {
                guard !window.workspaces.isEmpty,
                      window.workspaces.contains(where: { $0.id == window.activeWorkspaceID }) else {
                    throw DocumentStoreError.invalidPersistedState(L10n.text("Invalid active workspace", "当前工作区无效"))
                }
            }
            windowWorkspaces = windows
        } else {
            // One-time migration: each legacy window becomes one named workspace.
            let ids = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.id) })
            let byURL = sessions.reduce(into: [URL: UUID]()) { result, session in
                if result[session.url] == nil { result[session.url] = session.id }
            }
            windowWorkspaces = state.windows.map { record in
                let primary = record.splitState.primarySessionID.flatMap { ids[$0] }
                    ?? record.splitState.primarySessionURL.flatMap { byURL[$0] }
                let secondary = record.splitState.secondarySessionID.flatMap { ids[$0] }
                    ?? record.splitState.secondarySessionURL.flatMap { byURL[$0] }
                return WindowWorkspace(
                    id: record.id,
                    sessionIDs: restoredSessionIDs(for: record, sessionIDByPersistedID: ids, firstSessionIDByURL: byURL),
                    continuousReadingState: ContinuousReadingState(orderedSessionIDs: record.continuousReadingSessionIDs),
                    tabPresentationMode: record.tabPresentationMode,
                    isLeftSidebarVisible: record.isLeftSidebarVisible,
                    isRightSidebarVisible: record.isRightSidebarVisible,
                    rightSidebarMode: record.rightSidebarMode,
                    searchQuery: record.searchQuery, searchScope: record.searchScope,
                    isSplitEnabled: record.splitState.isEnabled && secondary != nil,
                    primarySessionID: primary, secondarySessionID: secondary,
                    focusedPane: record.splitState.focusedPane,
                    recentlyClosedURLs: record.recentlyClosedURLs,
                    leftSidebarWidth: appConfiguration.layout.leftSidebarWidth,
                    rightSidebarWidth: appConfiguration.layout.rightSidebarWidth)
            }
            // Early multi-window records could point two windows at the same
            // reading session. Preserve its first ID and give other windows
            // independent reading state while retaining the shared PDF owner.
            var assignedSessionIDs = Set<UUID>()
            for windowIndex in windowWorkspaces.indices {
                var window = windowWorkspaces[windowIndex]
                var replacements: [UUID: UUID] = [:]
                for sessionID in window.sessionIDs {
                    if assignedSessionIDs.insert(sessionID).inserted { continue }
                    guard let independentID = duplicateSessionForSplitComparison(from: sessionID, tabSessionID: sessionID),
                          let index = sessions.firstIndex(where: { $0.id == independentID }) else {
                        throw DocumentStoreError.invalidPersistedState(L10n.text("Missing migrated document", "缺少迁移后的文档"))
                    }
                    sessions[index].tabSessionID = nil
                    replacements[sessionID] = independentID
                }
                window.sessionIDs = window.sessionIDs.map { replacements[$0] ?? $0 }
                window.continuousReadingState.orderedSessionIDs = window.continuousReadingState.orderedSessionIDs.map {
                    replacements[$0] ?? $0
                }
                for groupIndex in window.activeWorkspace.groups.indices {
                    let paneIDs = window.activeWorkspace.groups[groupIndex].root.paneIDs
                    for pane in paneIDs {
                        if let oldID = window.activeWorkspace.groups[groupIndex].sessionIDsByPane[pane],
                           let newID = replacements[oldID] {
                            window.activeWorkspace.groups[groupIndex].sessionIDsByPane[pane] = newID
                        }
                    }
                }
                windowWorkspaces[windowIndex] = window
            }
        }
        if windowWorkspaces.isEmpty { windowWorkspaces = [WindowWorkspace()] }
        for index in windowWorkspaces.indices {
            for workspaceIndex in windowWorkspaces[index].workspaces.indices {
                for groupIndex in windowWorkspaces[index].workspaces[workspaceIndex].groups.indices {
                    windowWorkspaces[index].workspaces[workspaceIndex].groups[groupIndex].zoomedPane = nil
                }
            }
        }
        outlineAutoHiddenWindowIDs.removeAll()
        selectionAnchorIDsByWorkspace.removeAll()
        normalizeAllWorkspaces()
        syncPDFFileMonitor()
        notifyChange()
    }

    private func activateSessionForTabNavigation(sessionID: UUID, in workspace: inout WindowWorkspace) {
        let sourceID = documentSessionID(for: sessionID)
        let hasSeparatePublicCopies = workspace.sessionIDs.filter {
            documentSessionID(for: $0) == sourceID
        }.count > 1
        let containsDocument: (ReaderLayoutGroup) -> Bool = { group in
            if hasSeparatePublicCopies { return group.sessionIDs.contains(sessionID) }
            return group.sessionIDs.contains { self.documentSessionID(for: $0) == sourceID }
        }
        let current = workspace.activeWorkspace.activeGroup.flatMap { containsDocument($0) ? $0 : nil }
        if var group = current ?? workspace.activeWorkspace.groups.last(where: containsDocument) {
            let focusedMatches = group.sessionIDsByPane[group.focusedPane].map {
                hasSeparatePublicCopies ? $0 == sessionID : documentSessionID(for: $0) == sourceID
            } == true
            if !focusedMatches, let pane = group.root.paneIDs.first(where: {
                group.sessionIDsByPane[$0].map {
                    hasSeparatePublicCopies ? $0 == sessionID : documentSessionID(for: $0) == sourceID
                } == true
            }) { group.focusedPane = pane }
            workspace.activeWorkspace.activeGroup = group
        } else {
            workspace.activeWorkspace.activeGroup = ReaderLayoutGroup(sessionID: sessionID)
        }
    }

    private func activateSessionForSplitEdit(
        sessionID: UUID,
        targetPane: ReaderPane,
        in workspace: inout WindowWorkspace
    ) -> UUID? {
        guard session(for: sessionID)?.isBlank == false else {
            activateSessionForTabNavigation(sessionID: sessionID, in: &workspace)
            return nil
        }
        guard var group = workspace.activeWorkspace.activeGroup else {
            workspace.activeWorkspace.activeGroup = ReaderLayoutGroup(sessionID: sessionID)
            return nil
        }
        if !group.root.paneIDs.contains(targetPane) {
            guard let first = group.root.paneIDs.first else { return nil }
            group.root = group.root.replacing(first, with: .split(id: UUID(), layout: .sideBySide, ratio: 0.5,
                                                               first: .pane(first), second: .pane(targetPane)))
        }
        let canonical = documentSessionID(for: sessionID)
        let occupied = group.sessionIDsByPane.contains {
            $0.key != targetPane && documentSessionID(for: $0.value) == canonical
        }
        let targetID: UUID
        if occupied {
            if let existingID = group.sessionIDsByPane[targetPane],
               session(for: existingID)?.tabSessionID == sessionID {
                targetID = existingID
            } else {
                guard let clone = duplicateSessionForSplitComparison(from: sessionID, tabSessionID: sessionID) else { return nil }
                targetID = clone
            }
        } else { targetID = sessionID }
        group.sessionIDsByPane[targetPane] = targetID
        group.focusedPane = targetPane
        group.zoomedPane = nil
        workspace.activeWorkspace.activeGroup = group
        return occupied ? targetID : nil
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

    private func transferSession(
        _ sessionID: UUID,
        fromWorkspaceAt sourceIndex: Int,
        toWorkspaceAt destinationIndex: Int,
        readingSessionID: UUID? = nil
    ) -> Bool {
        guard sourceIndex != destinationIndex,
              windowWorkspaces.indices.contains(sourceIndex),
              windowWorkspaces.indices.contains(destinationIndex),
              let session = session(for: sessionID),
              session.isBlank == false else { return false }

        var source = windowWorkspaces[sourceIndex]
        var destination = windowWorkspaces[destinationIndex]
        guard let sessionIndex = source.sessionIDs.firstIndex(of: sessionID),
              destination.sessionIDs.contains(sessionID) == false else { return false }

        let readingSourceID = readingSessionID ?? self.readingSessionID(forTab: sessionID)
        if readingSourceID != sessionID, let readingSource = self.session(for: readingSourceID) {
            copyReadingState(from: readingSource, to: sessionID)
        }

        source.sessionIDs.remove(at: sessionIndex)
        source.selectedSessionIDs.remove(sessionID)
        source.continuousReadingState.orderedSessionIDs.removeAll { $0 == sessionID }
        clearSplitReferences(to: sessionID, in: &source)

        let preferredSourceSessionID = source.sessionIDs.isEmpty
            ? nil
            : source.sessionIDs[min(max(sessionIndex - 1, 0), source.sessionIDs.count - 1)]

        destination.sessionIDs.append(sessionID)
        destination.selectedSessionIDs = [sessionID]
        selectionAnchorIDsByWorkspace[destination.activeWorkspaceID] = sessionID
        activateSessionForTabNavigation(sessionID: sessionID, in: &destination)

        normalizeWorkspace(&source, preferredSessionID: preferredSourceSessionID)
        normalizeWorkspace(&destination, preferredSessionID: sessionID)
        windowWorkspaces[sourceIndex] = source
        windowWorkspaces[destinationIndex] = destination
        removeUnreferencedSessions()
        if readingSourceID != sessionID, let moved = self.session(for: sessionID) {
            persistReadingState(for: moved)
        }
        rebuildSearchIfNeeded(in: source.id)
        rebuildSearchIfNeeded(in: destination.id)
        return true
    }






    private func isSessionReferencedInSplit(_ sessionID: UUID, workspace: WindowWorkspace) -> Bool {
        workspace.activeWorkspace.groups.contains { $0.sessionIDs.contains(sessionID) }
    }

    private func clearSplitReferences(to sessionID: UUID, in workspace: inout WindowWorkspace) {
        let relatedIDs = Set(workspace.activeWorkspace.groups.flatMap(\.sessionIDs).filter {
            $0 == sessionID || session(for: $0)?.tabSessionID == sessionID
        }).union([sessionID])
        removeLayoutSessions(relatedIDs, from: &workspace.activeWorkspace)
    }

    private func removeUnreferencedSessions() {
        let references = Set(windowWorkspaces.flatMap { $0.workspaces.flatMap { Array($0.referencedSessionIDs) } })
        let retained = references.union(references.map { documentSessionID(for: $0) })
        let removedIDs = sessions.filter { !retained.contains($0.id) }.map(\.id)
        sessions.removeAll { !retained.contains($0.id) }
        for id in removedIDs { discardPDFDocumentCache(for: id) }
        sharedDocumentSources = sharedDocumentSources.filter { retained.contains($0.key) }
        syncPDFFileMonitor()
    }


    private func syncPDFFileMonitor() {
        fileMonitor.replaceMonitoredURLs(
            with: Set(sessions.filter {
                $0.isBlank == false && sharedDocumentSources[$0.id] == nil
            }.map { $0.url.standardizedFileURL })
        )
    }

    private func publicSessionID(for sessionID: UUID?, in workspace: WindowWorkspace) -> UUID? {
        guard let sessionID else { return nil }
        if workspace.sessionIDs.contains(sessionID) { return sessionID }
        if let tabID = session(for: sessionID)?.tabSessionID, workspace.sessionIDs.contains(tabID) { return tabID }
        let canonical = documentSessionID(for: sessionID)
        return workspace.sessionIDs.first { documentSessionID(for: $0) == canonical }
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
        for index in workspace.workspaces.indices {
            var named = workspace.workspaces[index]
            var seen = Set<UUID>()
            named.sessionIDs = named.sessionIDs.filter { validIDs.contains($0) && seen.insert($0).inserted }
            named.selectedSessionIDs.formIntersection(named.sessionIDs)
            if let anchorID = selectionAnchorIDsByWorkspace[named.id], !named.sessionIDs.contains(anchorID) {
                selectionAnchorIDsByWorkspace.removeValue(forKey: named.id)
            }
            named.continuousReadingState.orderedSessionIDs.removeAll {
                !named.sessionIDs.contains($0) || session(for: $0)?.isBlank != false
            }
            if named.continuousReadingState.orderedSessionIDs.count < 2 { named.continuousReadingState = ContinuousReadingState() }
            let invalid = named.referencedSessionIDs.subtracting(validIDs)
            removeLayoutSessions(invalid, from: &named)
            for groupIndex in named.groups.indices {
                let paneIDs = named.groups[groupIndex].root.paneIDs
                if !paneIDs.contains(named.groups[groupIndex].focusedPane) {
                    named.groups[groupIndex].focusedPane = paneIDs[0]
                }
            }
            if named.activeGroup == nil, let sessionID = preferredSessionID.flatMap({ named.sessionIDs.contains($0) ? $0 : nil }) ?? named.sessionIDs.first {
                named.activeGroup = ReaderLayoutGroup(sessionID: sessionID)
            }
            if named.sessionIDs.isEmpty { named.groups = []; named.activeGroupID = nil }
            workspace.workspaces[index] = named
        }
        workspace.documentMRU.removeAll { reference in
            !workspace.workspaces.contains { $0.id == reference.workspaceID && $0.sessionIDs.contains(reference.sessionID) }
        }
        applyEmptyWindowSidebarPolicy(&workspace)
    }

    /// M12-010: an empty window (no sessions) has nothing for the outline pane
    /// to answer, so it auto-collapses; the tabs pane stays because it hosts the
    /// recent-files quick entry. Runs on every workspace normalization so all
    /// close / move / merge / restore paths converge on the same policy.
    /// Opening the first session into an auto-collapsed window restores the pane
    /// unless the user explicitly touched its visibility while it was empty.
    private func applyEmptyWindowSidebarPolicy(_ workspace: inout WindowWorkspace) {
        if workspace.sessionIDs.isEmpty {
            if let explicitVisibility = workspace.outlineVisibilityWhileEmpty {
                setOutlinePaneVisible(explicitVisibility, in: &workspace)
                return
            }
            if isOutlinePaneVisible(in: workspace) {
                setOutlinePaneVisible(false, in: &workspace)
                outlineAutoHiddenWindowIDs.insert(workspace.id)
            }
        } else {
            if outlineAutoHiddenWindowIDs.remove(workspace.id) != nil {
                setOutlinePaneVisible(true, in: &workspace)
            }
            workspace.outlineVisibilityWhileEmpty = nil
        }
    }

    private func isOutlinePaneVisible(in workspace: WindowWorkspace) -> Bool {
        appConfiguration.layout.sidebarsSwapped
            ? workspace.isLeftSidebarVisible
            : workspace.isRightSidebarVisible
    }

    private func setOutlinePaneVisible(_ isVisible: Bool, in workspace: inout WindowWorkspace) {
        if appConfiguration.layout.sidebarsSwapped {
            workspace.isLeftSidebarVisible = isVisible
        } else {
            workspace.isRightSidebarVisible = isVisible
        }
    }

    private func sidebarVisibilityReflectingUserIntent(
        in workspace: WindowWorkspace
    ) -> (left: Bool, right: Bool) {
        var visibility = (
            left: workspace.isLeftSidebarVisible,
            right: workspace.isRightSidebarVisible
        )
        guard outlineAutoHiddenWindowIDs.contains(workspace.id) else { return visibility }
        if appConfiguration.layout.sidebarsSwapped {
            visibility.left = true
        } else {
            visibility.right = true
        }
        return visibility
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
        sessions[sessionIndex].annotationGeneration &+= 1
    }

    private func rebuildAnnotationCache(for sessionIndex: Int) {
        guard let document = try? pdfDocument(for: sessions[sessionIndex].id) else { return }
        sessions[sessionIndex].annotationCache = DocumentHighlightCache(
            groups: HighlightService.buildHighlightGroups(in: document)
        )
        sessions[sessionIndex].isAnnotationCacheLoaded = true
    }

    private func upsertCachedAnnotationGroups(from records: [HighlightAnnotationRecord], for sessionIndex: Int) {
        guard sessions[sessionIndex].isAnnotationCacheLoaded else { return }
        sessions[sessionIndex].annotationCache.upsert(HighlightService.buildHighlightGroups(from: records))
    }

    private func removeCachedAnnotationGroups(for records: [HighlightAnnotationRecord], from sessionIndex: Int) {
        guard sessions[sessionIndex].isAnnotationCacheLoaded else { return }
        sessions[sessionIndex].annotationCache.removeGroups(withIDs: HighlightService.groupIDs(for: records))
    }

    private func ensureAnnotationCacheLoaded(for sessionIndex: Int) {
        guard sessions[sessionIndex].isAnnotationCacheLoaded == false else { return }
        rebuildAnnotationCache(for: sessionIndex)
    }

    private func invalidateCleanSessionAfterExternalChange(at sessionIndex: Array<DocumentSession>.Index, snapshot: PDFFileSnapshot) {
        let sessionID = sessions[sessionIndex].id
        discardPDFDocumentCache(for: sessionID)
        sessions[sessionIndex].pageCount = nil
        sessions[sessionIndex].outlineTree = []
        sessions[sessionIndex].isOutlineLoaded = false
        sessions[sessionIndex].firstPagePosition = nil
        sessions[sessionIndex].fileSnapshot = snapshot
    }

    private func clampReadingPositionIfNeeded(
        for sessionIndex: Array<DocumentSession>.Index,
        in document: PDFDocument
    ) {
        guard document.pageCount > 0 else { return }
        let session = sessions[sessionIndex]
        let clampedPageIndex = min(max(session.lastReadPosition.pageIndex, 0), document.pageCount - 1)
        let currentPageIndex = min(max(session.currentPageIndex, 0), document.pageCount - 1)
        let needsPageTop = session.needsInitialReadingPosition ||
            clampedPageIndex != session.lastReadPosition.pageIndex
        guard needsPageTop ||
                currentPageIndex != session.currentPageIndex else { return }

        sessions[sessionIndex].currentPageIndex = clampedPageIndex
        if needsPageTop {
            guard let page = document.page(at: clampedPageIndex) else { return }
            sessions[sessionIndex].lastReadPosition = ReadingPosition.pageTop(
                pageIndex: clampedPageIndex,
                pageBounds: page.bounds(for: .cropBox)
            )
        }
        sessions[sessionIndex].needsInitialReadingPosition = false
        persistReadingState(for: sessions[sessionIndex])
    }

    private func touchPDFDocument(_ sessionID: UUID) {
        pdfDocumentRecency.removeAll { $0 == sessionID }
        pdfDocumentRecency.append(sessionID)
    }

    private func discardPDFDocumentCache(for sessionID: UUID) {
        pdfDocumentCache.removeValue(forKey: sessionID)
        pdfDocumentRecency.removeAll { $0 == sessionID }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].searchCache.clear()
        sessions[index].annotationCache.clear()
        sessions[index].isAnnotationCacheLoaded = false
        // Undo records refer to annotations in this exact PDFDocument instance.
        sessions[index].undoStack.removeAll()
        sessions[index].redoStack.removeAll()
    }

    private func pinnedPDFDocumentIDs() -> Set<UUID> {
        var pinned = Set(sessions.filter(\.isDirty).map(\.id))
        for window in windowWorkspaces where !window.isClosed {
            for sessionID in window.activeWorkspace.activeGroup?.sessionIDs ?? [] {
                pinned.insert(documentSessionID(for: sessionID))
            }
        }
        return pinned
    }

    private func prunePDFDocumentCache() {
        let pinned = pinnedPDFDocumentIDs()
        while pdfDocumentCache.count > Self.livePDFDocumentLimit {
            guard let victim = pdfDocumentRecency.first(where: { pinned.contains($0) == false }) else { return }
            discardPDFDocumentCache(for: victim)
        }
    }

    private func cancelSearchOperation(in windowID: UUID) {
        searchOperations.removeValue(forKey: windowID)?.cancel()
    }

    func rebuildSearchIfNeeded(in windowID: UUID) {
        guard let workspace = windowWorkspace(for: windowID) else {
            cancelSearchOperation(in: windowID)
            searchSnapshots.removeValue(forKey: windowID)
            return
        }
        let query = workspace.searchQuery
        guard query.isEmpty == false else {
            cancelSearchOperation(in: windowID)
            searchSnapshots.removeValue(forKey: windowID)
            return
        }

        let source = SearchSnapshotSource(
            query: query,
            scope: workspace.searchScope,
            options: searchOptions(in: windowID),
            targets: searchTargetSessionIDs(in: workspace).compactMap { sessionID in
                guard let session = session(for: sessionID) else { return nil }
                return SearchSnapshotSource.Target(
                    sessionID: sessionID,
                    sessionTitle: session.title,
                    url: session.url,
                    fileSnapshot: session.fileSnapshot
                )
            }
        )
        guard searchSnapshots[windowID]?.source != source else { return }
        cancelSearchOperation(in: windowID)

        var cachedMatches: [UUID: [DocumentSearchMatch]] = [:]
        for target in source.targets {
            guard let session = session(for: target.sessionID),
                  session.searchCache.query == query,
                  session.searchCache.options == source.options else { continue }
            cachedMatches[target.sessionID] = session.searchCache.matches
        }

        let operation = DocumentSearchOperation(
            source: source,
            cachedMatchesBySessionID: cachedMatches
        )
        operation.onUpdate = { [weak self, weak operation] matchesBySessionID, isSearching in
            guard let self,
                  let operation,
                  self.searchOperations[windowID] === operation else { return }
            for target in source.targets {
                guard let matches = matchesBySessionID[target.sessionID],
                      let index = self.sessions.firstIndex(where: { $0.id == target.sessionID }) else { continue }
                self.sessions[index].searchCache = DocumentSearchCache(
                    query: source.query,
                    options: source.options,
                    matches: matches
                )
            }
            self.searchSnapshots[windowID] = SearchSnapshot.make(
                source: source,
                matchesBySessionID: matchesBySessionID,
                isSearching: isSearching
            )
            self.notifyChange(.search, windowIDs: [windowID], persistState: false)
            if isSearching == false {
                self.searchOperations.removeValue(forKey: windowID)
            }
        }
        searchOperations[windowID] = operation
        searchSnapshots[windowID] = SearchSnapshot.make(
            source: source,
            matchesBySessionID: cachedMatches,
            isSearching: source.targets.count > cachedMatches.count
        )
        operation.start()
    }

    private func searchTargetSessionIDs(in workspace: WindowWorkspace) -> [UUID] {
        switch workspace.searchScope {
        case .currentDocument:
            workspace.activeSessionID.map { [$0] } ?? []
        case .allOpen:
            workspace.sessionIDs
        }
    }

    private func invalidateSearchSnapshots(referencing sessionIDs: Set<UUID>) {
        let invalidatedWindowIDs = searchSnapshots.compactMap { windowID, snapshot in
            snapshot.source.targets.contains { sessionIDs.contains($0.sessionID) } ? windowID : nil
        }
        for windowID in invalidatedWindowIDs {
            cancelSearchOperation(in: windowID)
            searchSnapshots.removeValue(forKey: windowID)
        }
    }

    private func clearUnusedSearchCaches(for sessionIDs: Set<UUID>) {
        let referencedSessionIDs = Set(searchSnapshots.values.flatMap { snapshot in
            snapshot.source.targets.map(\.sessionID)
        })
        for index in sessions.indices
            where sessionIDs.contains(sessions[index].id)
                && referencedSessionIDs.contains(sessions[index].id) == false {
            sessions[index].searchCache.clear()
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

    private static let logger = Logger(subsystem: "local.yfff.Serein", category: "DocumentStore")

    /// Forces pending reading-state writes to disk. Call on app termination.
    func flushPersistence() {
        do {
            try readingStateStore.flush()
        } catch {
            Self.logger.error("Failed to flush reading state: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try persistence.flush()
        } catch {
            Self.logger.error("Failed to flush document state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func notifyChange(
        _ change: DocumentStoreChange = .all,
        windowIDs: Set<UUID>? = nil,
        sessionIDs: Set<UUID>? = nil,
        persistState: Bool? = nil
    ) {
        if change.contains(.content) || change.contains(.tabs) {
            if let windowIDs {
                for windowID in windowIDs {
                    outlineSnapshots.removeValue(forKey: windowID)
                }
            } else {
                outlineSnapshots.removeAll(keepingCapacity: true)
            }
        }
        // Reading changes already saved the session snapshot; annotation bytes live in the PDF.
        let shouldPersist = persistState
            ?? change.containsOnly([.readingPosition, .annotations]) == false
        if shouldPersist {
            persistDocumentStoreState()
        }
        var userInfo: [String: Any] = [DocumentStoreChange.notificationUserInfoKey: change.rawValue]
        if let windowIDs {
            userInfo[DocumentStoreChange.windowIDsUserInfoKey] = windowIDs
        }
        if let sessionIDs {
            let comparisonIDs = change.contains(.annotations) ? sharedDocumentSources.compactMap { comparisonID, sourceID in
                sessionIDs.contains(sourceID) ? comparisonID : nil
            } : []
            userInfo[DocumentStoreChange.sessionIDsUserInfoKey] = sessionIDs.union(comparisonIDs)
        }
        NotificationCenter.default.post(
            name: .documentStoreDidChange,
            object: self,
            userInfo: userInfo
        )
    }

    private func persistDocumentStoreState() {
        let persistedSessions = sessions.filter { !$0.isBlank }
        let blankIDs = Set(sessions.filter(\.isBlank).map(\.id))
        var windows = windowWorkspaces
        for windowIndex in windows.indices {
            let visibility = sidebarVisibilityReflectingUserIntent(in: windows[windowIndex])
            windows[windowIndex].isLeftSidebarVisible = visibility.left
            windows[windowIndex].isRightSidebarVisible = visibility.right
            for workspaceIndex in windows[windowIndex].workspaces.indices {
                windows[windowIndex].workspaces[workspaceIndex].sessionIDs.removeAll { blankIDs.contains($0) }
                windows[windowIndex].workspaces[workspaceIndex].selectedSessionIDs.subtract(blankIDs)
                removeLayoutSessions(blankIDs, from: &windows[windowIndex].workspaces[workspaceIndex])
                if windows[windowIndex].workspaces[workspaceIndex].activeGroup == nil {
                    if let last = windows[windowIndex].workspaces[workspaceIndex].groups.last {
                        windows[windowIndex].workspaces[workspaceIndex].activeGroupID = last.id
                    } else if let firstID = windows[windowIndex].workspaces[workspaceIndex].sessionIDs.first {
                        windows[windowIndex].workspaces[workspaceIndex].activeGroup = ReaderLayoutGroup(sessionID: firstID)
                    }
                }
                for groupIndex in windows[windowIndex].workspaces[workspaceIndex].groups.indices {
                    windows[windowIndex].workspaces[workspaceIndex].groups[groupIndex].zoomedPane = nil
                }
            }
        }
        let references = persistedSessions.map { session in
            PersistedDocumentStoreState.SessionReference(
                id: session.id, url: session.url, title: session.title,
                documentSourceID: sharedDocumentSources[session.id], tabSessionID: session.tabSessionID,
                readingState: PersistedReadingState(
                    url: session.url, displayMode: session.displayMode, scaleMode: session.scaleMode,
                    scaleFactor: session.zoomScale, readingPosition: session.lastReadPosition,
                    leftSidebarWidth: nil, rightSidebarWidth: nil,
                    isHorizontalPanLocked: session.isHorizontalPanLocked),
                needsInitialReadingPosition: session.needsInitialReadingPosition)
        }
        do {
            try persistence.saveState(PersistedDocumentStoreState(sessions: references, workspaceWindows: windows))
        } catch {
            Self.logger.error("Failed to persist document store: \(error.localizedDescription, privacy: .public)")
        }
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
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw DocumentStoreError.unreadableDocument(url)
        }

        let restoredState = seedState == nil ? try readingStateStore.loadState(for: url) : nil
        let lastReadPosition = seedState.map {
            $0.needsInitialReadingPosition ? nil : $0.lastReadPosition
        } ?? restoredState?.readingPosition
        return DocumentSession(
            url: url,
            title: seedState?.title,
            pageCount: seedState?.pageCount,
            currentPageIndex: seedState?.currentPageIndex ?? restoredState?.readingPosition.pageIndex ?? 0,
            displayMode: seedState?.displayMode ?? restoredState?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
            scaleMode: seedState?.scaleMode ?? resolvedScaleMode(restoredState?.scaleMode),
            zoomScale: seedState?.zoomScale ?? restoredState?.scaleFactor ?? 1.0,
            isHorizontalPanLocked: seedState?.isHorizontalPanLocked ?? restoredState?.isHorizontalPanLocked ?? false,
            lastReadPosition: lastReadPosition,
            outlineTree: [],
            isOutlineLoaded: false,
            annotationSavePolicy: seedState?.annotationSavePolicy ?? appConfiguration.annotations.autoSavePolicy,
            annotationCache: seedState?.annotationCache ?? DocumentHighlightCache(),
            isAnnotationCacheLoaded: seedState?.isAnnotationCacheLoaded ?? false,
            fileSnapshot: PDFFileSnapshot(url: url)
        )
    }

    private func duplicateSessionForSplitComparison(from sessionID: UUID, tabSessionID: UUID) -> UUID? {
        guard let source = session(for: sessionID), !source.isBlank else { return nil }
        var duplicate = DocumentSession(
            url: source.url, title: source.title, pageCount: source.pageCount,
            currentPageIndex: source.currentPageIndex, displayMode: source.displayMode,
            scaleMode: source.scaleMode, zoomScale: source.zoomScale,
            isHorizontalPanLocked: source.isHorizontalPanLocked,
            lastReadPosition: source.needsInitialReadingPosition ? nil : source.lastReadPosition,
            annotationSavePolicy: source.annotationSavePolicy, fileSnapshot: source.fileSnapshot)
        duplicate.tabSessionID = tabSessionID
        sessions.append(duplicate)
        sharedDocumentSources[duplicate.id] = documentSessionID(for: sessionID)
        return duplicate.id
    }

    private func copyReadingState(from source: DocumentSession, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].currentPageIndex = source.currentPageIndex
        sessions[index].displayMode = source.displayMode
        sessions[index].scaleMode = source.scaleMode
        sessions[index].zoomScale = source.zoomScale
        sessions[index].isHorizontalPanLocked = source.isHorizontalPanLocked
        sessions[index].lastReadPosition = source.lastReadPosition
        sessions[index].needsInitialReadingPosition = source.needsInitialReadingPosition
    }

    private func persistReadingState(for session: DocumentSession) {
        guard session.isBlank == false else { return }
        persistDocumentStoreState()
        guard session.tabSessionID == nil else { return }
        do {
            try readingStateStore.saveState(
                PersistedReadingState(
                    url: session.url,
                    displayMode: session.displayMode,
                    scaleMode: session.scaleMode,
                    scaleFactor: session.zoomScale,
                    readingPosition: session.lastReadPosition,
                    leftSidebarWidth: nil,
                    rightSidebarWidth: nil,
                    isHorizontalPanLocked: session.isHorizontalPanLocked
                )
            )
        } catch {
            Self.logger.error("Failed to persist reading state for \(session.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func renameSession(_ title: String, for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[index].isBlank == false else {
            sessions[index].title = title.isEmpty ? L10n.text("Untitled", "未命名") : title
            notifyChange(.tabs, sessionIDs: [sessionID])
            return
        }
        guard title.isEmpty == false, title.contains("/") == false else { return }
        let oldURL = sessions[index].url
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(title).appendingPathExtension("pdf")

        guard oldURL != newURL else {
            sessions[index].title = title
            notifyChange(.tabs, sessionIDs: [sessionID])
            return
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            NSLog("Serein failed to rename file: %@", error.localizedDescription)
            return
        }

        let snapshot = PDFFileSnapshot(url: newURL)
        let affectedIndexes = sessions.indices.filter { sessions[$0].url == oldURL }
        let affectedSessionIDs = Set(affectedIndexes.map { sessions[$0].id })
        for affectedIndex in affectedIndexes {
            sessions[affectedIndex].url = newURL
            sessions[affectedIndex].title = title
            sessions[affectedIndex].fileSnapshot = snapshot
            sessions[affectedIndex].annotationGeneration &+= 1
        }
        syncPDFFileMonitor()

        if let oldState = try? readingStateStore.loadState(for: oldURL) {
            var migratedState = oldState
            migratedState.url = newURL
            try? readingStateStore.saveState(migratedState)
        }

        recentDocumentURLs = (try? recentFilesStore.replaceURL(oldURL, with: newURL)) ?? recentDocumentURLs
        noteRecentDocumentURL?(newURL)

        for windowIndex in windowWorkspaces.indices {
            for workspaceIndex in windowWorkspaces[windowIndex].workspaces.indices {
                for closedIndex in windowWorkspaces[windowIndex].workspaces[workspaceIndex].recentlyClosedURLs.indices
                where windowWorkspaces[windowIndex].workspaces[workspaceIndex].recentlyClosedURLs[closedIndex] == oldURL {
                    windowWorkspaces[windowIndex].workspaces[workspaceIndex].recentlyClosedURLs[closedIndex] = newURL
                }
            }
        }

        invalidateSearchSnapshots(referencing: affectedSessionIDs)
        for workspace in windowWorkspaces {
            rebuildSearchIfNeeded(in: workspace.id)
        }
        notifyChange([.content, .tabs, .recentFiles], sessionIDs: affectedSessionIDs)
    }

    func updateSidebarWidths(left leftWidth: CGFloat, right rightWidth: CGFloat, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return }
        let needsUpdate =
            windowWorkspaces[index].leftSidebarWidth != leftWidth ||
            windowWorkspaces[index].rightSidebarWidth != rightWidth
        guard needsUpdate else { return }

        windowWorkspaces[index].leftSidebarWidth = leftWidth
        windowWorkspaces[index].rightSidebarWidth = rightWidth
    }

    func testingIsSearchInFlight(in windowID: UUID) -> Bool {
        searchOperations[windowID] != nil
    }
}

extension DocumentStore {
    func workspaces(in windowID: UUID) -> [NamedWorkspace] {
        windowWorkspace(for: windowID)?.workspaces ?? []
    }

    func activeWorkspaceID(in windowID: UUID) -> UUID? {
        windowWorkspace(for: windowID)?.activeWorkspaceID
    }

    @discardableResult
    func activateAdjacentWorkspace(direction: Int, in windowID: UUID) -> Bool {
        guard direction == -1 || direction == 1,
              let window = windowWorkspace(for: windowID), window.workspaces.count > 1,
              let currentIndex = window.workspaces.firstIndex(where: { $0.id == window.activeWorkspaceID }) else { return false }
        let targetIndex = (currentIndex + direction + window.workspaces.count) % window.workspaces.count
        activateWorkspace(window.workspaces[targetIndex].id, in: windowID)
        return true
    }

    /// Workspace numbers are one-based and follow the saved order within the window.
    @discardableResult
    func activateWorkspace(at index: Int, in windowID: UUID) -> Bool {
        guard index > 0,
              let window = windowWorkspace(for: windowID), window.workspaces.indices.contains(index - 1),
              window.workspaces[index - 1].id != window.activeWorkspaceID else { return false }
        activateWorkspace(window.workspaces[index - 1].id, in: windowID)
        return true
    }

    @discardableResult
    func createWorkspace(name: String, in windowID: UUID) -> UUID? {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let workspace = NamedWorkspace(name: name)
        windowWorkspaces[index].workspaces.append(workspace)
        activateWorkspace(workspace.id, in: windowID)
        return workspace.id
    }

    func renameWorkspace(_ workspaceID: UUID, name: String, in windowID: UUID) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let workspaceIndex = windowWorkspaces[index].workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        windowWorkspaces[index].workspaces[workspaceIndex].name = name
        notifyChange(.tabs, windowIDs: [windowID])
    }

    func activateWorkspace(_ workspaceID: UUID, in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              windowWorkspaces[index].workspaces.contains(where: { $0.id == workspaceID }),
              windowWorkspaces[index].activeWorkspaceID != workspaceID else { return }
        cancelSearchOperation(in: windowID)
        searchSnapshots.removeValue(forKey: windowID)
        windowWorkspaces[index].activeWorkspaceID = workspaceID
        normalizeWorkspace(&windowWorkspaces[index])
        recordActiveDocument(in: windowID)
        rebuildSearchIfNeeded(in: windowID)
        prunePDFDocumentCache()
        notifyChange(.content, windowIDs: [windowID])
    }

    @discardableResult
    func moveSession(_ sessionID: UUID, toWorkspace workspaceID: UUID, in windowID: UUID) -> Bool {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let targetIndex = windowWorkspaces[index].workspaces.firstIndex(where: { $0.id == workspaceID }),
              workspaceID != windowWorkspaces[index].activeWorkspaceID,
              let publicID = publicSessionID(for: sessionID, in: windowWorkspaces[index]),
              let session = session(for: publicID), !session.isBlank else { return false }
        var window = windowWorkspaces[index]
        let existing = window.workspaces[targetIndex].sessionIDs.first {
            self.session(for: $0).map { Self.normalizedDocumentURL($0.url) == Self.normalizedDocumentURL(session.url) } == true
        }
        let readingSourceID = sessionID == publicID ? readingSessionID(forTab: publicID) : sessionID
        if existing == nil, readingSourceID != publicID, let readingSource = self.session(for: readingSourceID) {
            copyReadingState(from: readingSource, to: publicID)
        }
        let movingIDs = Set(window.activeWorkspace.groups.flatMap(\.sessionIDs).filter {
            $0 == publicID || self.session(for: $0)?.tabSessionID == publicID
        }).union([publicID])
        window.sessionIDs.removeAll { $0 == publicID }
        window.selectedSessionIDs.remove(publicID)
        window.continuousReadingState.orderedSessionIDs.removeAll { $0 == publicID }
        removeLayoutSessions(movingIDs, from: &window.activeWorkspace)
        if existing == nil { window.workspaces[targetIndex].sessionIDs.append(publicID) }
        window.documentMRU.removeAll { $0.sessionID == publicID }
        normalizeWorkspace(&window)
        windowWorkspaces[index] = window
        removeUnreferencedSessions()
        if existing == nil, readingSourceID != publicID, let moved = self.session(for: publicID) {
            persistReadingState(for: moved)
        }
        rebuildSearchIfNeeded(in: windowID)
        notifyChange(.content, windowIDs: [windowID])
        return true
    }

    func recentDocumentEntries(in windowID: UUID) -> [WorkspaceDocumentEntry] {
        guard let window = windowWorkspace(for: windowID) else { return [] }
        let allReferences = window.workspaces.flatMap { workspace in
            workspace.sessionIDs.map { WorkspaceDocumentReference(workspaceID: workspace.id, sessionID: $0) }
        }
        var seen = Set<UUID>()
        return (window.documentMRU + allReferences).compactMap { reference in
            guard seen.insert(reference.sessionID).inserted,
                  let workspace = window.workspaces.first(where: { $0.id == reference.workspaceID }),
                  workspace.sessionIDs.contains(reference.sessionID),
                  let session = session(for: reference.sessionID), !session.isBlank else { return nil }
            return WorkspaceDocumentEntry(windowID: windowID, workspaceID: workspace.id,
                                          workspaceName: workspace.name, session: session)
        }
    }

    func activateDocumentEntry(_ entry: WorkspaceDocumentEntry) {
        activateWorkspace(entry.workspaceID, in: entry.windowID)
        activateTab(sessionID: entry.session.id, in: entry.windowID)
    }

    func closedWindowWorkspaces() -> [WindowWorkspace] { windowWorkspaces.filter(\.isClosed) }

    func reopenWindow(id: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == id }), windowWorkspaces[index].isClosed else { return }
        windowWorkspaces[index].isClosed = false
        notifyChange(.content, windowIDs: [id])
    }

    func readerLayout(in windowID: UUID) -> ReaderLayoutNode? {
        windowWorkspace(for: windowID)?.readerLayout
    }

    func readerPanes(in windowID: UUID) -> [ReaderPaneState] {
        guard let group = windowWorkspace(for: windowID)?.activeWorkspace.activeGroup else { return [] }
        return group.root.paneIDs.map { ReaderPaneState(id: $0, sessionID: group.sessionIDsByPane[$0]) }
    }

    func zoomedPane(in windowID: UUID) -> ReaderPane? {
        windowWorkspace(for: windowID)?.activeWorkspace.activeGroup?.zoomedPane
    }

    @discardableResult
    func splitPane(from pane: ReaderPane, layout: ReaderSplitLayout,
                   sessionID: UUID? = nil, readingPosition: ReadingPosition? = nil,
                   in windowID: UUID) -> ReaderPane? {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              var group = windowWorkspaces[index].activeWorkspace.activeGroup,
              group.root.paneIDs.contains(pane),
              let requestedID = sessionID ?? group.sessionIDsByPane[pane] else { return nil }
        let sourceID = sessionID != nil && readingPosition == nil
            ? readingSessionID(forTab: requestedID) : requestedID
        guard let source = session(for: sourceID), !source.isBlank else { return nil }
        do {
            let publicSession = try ensurePublicSession(documentAt: source.url, seed: source, in: windowID)
            let alreadyHasReader = windowWorkspaces[index].activeWorkspace.groups.contains {
                $0.sessionIDs.contains { $0 == publicSession.id || session(for: $0)?.tabSessionID == publicSession.id }
            }
            let readingSessionID: UUID
            if alreadyHasReader {
                guard let cloneID = duplicateSessionForSplitComparison(from: sourceID, tabSessionID: publicSession.id) else { return nil }
                readingSessionID = cloneID
            } else {
                readingSessionID = publicSession.id
                if readingSessionID != sourceID { copyReadingState(from: source, to: readingSessionID) }
            }
            if let readingPosition, let readingIndex = sessions.firstIndex(where: { $0.id == readingSessionID }) {
                sessions[readingIndex].currentPageIndex = readingPosition.pageIndex
                sessions[readingIndex].lastReadPosition = readingPosition
                sessions[readingIndex].needsInitialReadingPosition = false
            }
            let newPane: ReaderPane = group.root.paneIDs.contains(.secondary) ? ReaderPane() : .secondary
            group.root = group.root.replacing(pane, with: .split(
                id: UUID(), layout: layout, ratio: 0.5, first: .pane(pane), second: .pane(newPane)))
            group.sessionIDsByPane[newPane] = readingSessionID
            group.focusedPane = newPane
            group.zoomedPane = nil
            windowWorkspaces[index].activeWorkspace.activeGroup = group
            recordActiveDocument(in: windowID)
            syncPDFFileMonitor()
            rebuildSearchIfNeeded(in: windowID)
            notifyChange(.content, windowIDs: [windowID])
            return newPane
        } catch {
            Self.logger.error("Unable to split PDF: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func splitPane(from pane: ReaderPane, layout: ReaderSplitLayout, documentAt url: URL,
                   in windowID: UUID) throws -> ReaderPane? {
        guard readerPanes(in: windowID).contains(where: { $0.id == pane && $0.sessionID != nil }) else { return nil }
        let target = try ensurePublicSession(documentAt: url, seed: nil, in: windowID)
        return splitPane(from: pane, layout: layout, sessionID: target.id, in: windowID)
    }

    /// A tab can remain open after its original reader has been replaced by a comparison pane.
    private func readingSessionID(forTab sessionID: UUID) -> UUID {
        guard let workspace = windowWorkspaces.lazy.flatMap(\.workspaces)
            .first(where: { $0.sessionIDs.contains(sessionID) }) else { return sessionID }
        for group in workspace.groups.reversed() {
            let matches: (UUID) -> Bool = { id in
                id == sessionID || self.session(for: id)?.tabSessionID == sessionID
            }
            if let focused = group.sessionIDsByPane[group.focusedPane], matches(focused) { return focused }
            if let displayed = group.sessionIDs.first(where: matches) { return displayed }
        }
        return sessionID
    }

    @discardableResult
    func closePane(_ pane: ReaderPane, in windowID: UUID) -> Bool {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              var group = windowWorkspaces[index].activeWorkspace.activeGroup,
              group.root.paneIDs.count > 1, group.root.paneIDs.contains(pane) else { return false }
        group.removePane(pane)
        windowWorkspaces[index].activeWorkspace.activeGroup = group
        removeUnreferencedSessions()
        recordActiveDocument(in: windowID)
        rebuildSearchIfNeeded(in: windowID)
        notifyChange(.content, windowIDs: [windowID])
        return true
    }

    func updateSplitRatio(_ ratio: Double, splitID: UUID, in windowID: UUID) {
        guard ratio.isFinite, ratio > 0, ratio < 1,
              let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              var group = windowWorkspaces[index].activeWorkspace.activeGroup else { return }
        let root = group.root.updatingRatio(ratio, splitID: splitID)
        guard root != group.root else { return }
        group.root = root
        windowWorkspaces[index].activeWorkspace.activeGroup = group
        persistDocumentStoreState()
    }

    func togglePaneZoom(in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              var group = windowWorkspaces[index].activeWorkspace.activeGroup,
              group.root.paneIDs.count > 1 else { return }
        group.zoomedPane = group.zoomedPane == nil ? group.focusedPane : nil
        windowWorkspaces[index].activeWorkspace.activeGroup = group
        notifyChange(.tabs, windowIDs: [windowID], persistState: false)
    }

    func discardUnsavedAnnotations(for sessionID: UUID) throws {
        guard let sourceID = sharedDocumentSessionID(for: sessionID),
              let ownerIndex = sessions.firstIndex(where: { $0.id == sourceID }) else {
            throw DocumentStoreError.missingSession(sessionID)
        }
        let url = sessions[ownerIndex].url
        guard let cleanDocument = PDFDocument(url: url) else {
            throw DocumentStoreError.unreadableDocument(url)
        }
        HighlightService.consolidateComments(in: cleanDocument)
        let affectedIDs = Set(sessions.filter { documentSessionID(for: $0.id) == sourceID }.map(\.id))
        for index in sessions.indices where affectedIDs.contains(sessions[index].id) {
            sessions[index].isDirty = false
            sessions[index].dirtySince = nil
            sessions[index].annotationGeneration &+= 1
            sessions[index].undoStack.removeAll()
            sessions[index].redoStack.removeAll()
            sessions[index].annotationCache.clear()
            sessions[index].isAnnotationCacheLoaded = false
            sessions[index].searchCache.clear()
            sessions[index].outlineTree = []
            sessions[index].isOutlineLoaded = false
            sessions[index].fileSnapshot = PDFFileSnapshot(url: url)
            sessions[index].pageCount = cleanDocument.pageCount
        }
        pdfDocumentCache[sourceID] = cleanDocument
        touchPDFDocument(sourceID)
        invalidateSearchSnapshots(referencing: affectedIDs)
        notifyChange([.content, .annotations], sessionIDs: affectedIDs)
    }

    func sharedDocumentSessionID(for sessionID: UUID) -> UUID? {
        guard sessions.contains(where: { $0.id == sessionID }) else { return nil }
        return documentSessionID(for: sessionID)
    }

    private func recordActiveDocument(in windowID: UUID) {
        guard let index = windowWorkspaces.firstIndex(where: { $0.id == windowID }),
              let sessionID = publicSessionID(for: windowWorkspaces[index].activeSessionID,
                                              in: windowWorkspaces[index]),
              session(for: sessionID)?.isBlank == false else { return }
        let reference = WorkspaceDocumentReference(workspaceID: windowWorkspaces[index].activeWorkspaceID,
                                                   sessionID: sessionID)
        windowWorkspaces[index].documentMRU.removeAll { $0 == reference }
        windowWorkspaces[index].documentMRU.insert(reference, at: 0)
    }

    private func ensurePublicSession(documentAt url: URL, seed: DocumentSession?, in windowID: UUID) throws -> DocumentSession {
        guard let windowIndex = windowWorkspaces.firstIndex(where: { $0.id == windowID }) else {
            throw DocumentStoreError.unreadableDocument(url)
        }
        let normalizedURL = Self.normalizedDocumentURL(url)
        if let existing = sessions(in: windowID).first(where: { !$0.isBlank && Self.normalizedDocumentURL($0.url) == normalizedURL }) {
            return existing
        }
        let newSession = try makeSession(documentAt: normalizedURL, seedState: seed)
        let canonical = sessions.first {
            !$0.isBlank && sharedDocumentSources[$0.id] == nil && Self.normalizedDocumentURL($0.url) == normalizedURL
        }?.id
        sessions.append(newSession)
        if let canonical { sharedDocumentSources[newSession.id] = canonical }
        windowWorkspaces[windowIndex].sessionIDs.append(newSession.id)
        recentDocumentURLs = (try? recentFilesStore.recordOpen(for: [normalizedURL])) ?? recentDocumentURLs
        noteRecentDocumentURL?(normalizedURL)
        return newSession
    }

    private func removeLayoutSessions(_ sessionIDs: Set<UUID>, from workspace: inout NamedWorkspace) {
        for index in workspace.groups.indices.reversed() {
            var group = workspace.groups[index]
            let panes = group.root.paneIDs.filter { group.sessionIDsByPane[$0].map(sessionIDs.contains) == true }
            for pane in panes {
                if group.root.paneIDs.count == 1 {
                    workspace.groups.remove(at: index)
                    break
                }
                group.removePane(pane)
            }
            if workspace.groups.indices.contains(index), workspace.groups[index].id == group.id {
                workspace.groups[index] = group
            }
        }
        if workspace.groups.contains(where: { $0.id == workspace.activeGroupID }) == false {
            workspace.activeGroupID = nil
        }
    }
}

enum DocumentStoreError: Error, LocalizedError {
    case missingSession(UUID)
    case blankSession(UUID)
    case unreadableDocument(URL)
    case failedToSaveDocument(URL)
    case invalidPersistedState(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPersistedState(reason):
            L10n.text("Invalid saved workspace: \(reason)", "已保存的工作区无效：\(reason)")
        case let .missingSession(id):
            L10n.text("Missing PDF session \(id.uuidString)", "缺少 PDF 会话：\(id.uuidString)")
        case let .blankSession(id):
            L10n.text("Blank tab \(id.uuidString) has no PDF", "空白标签页 \(id.uuidString) 没有 PDF")
        case let .unreadableDocument(url):
            L10n.text("Unable to open PDF at \(url.path)", "无法打开 PDF：\(url.path)")
        case let .failedToSaveDocument(url):
            L10n.text("Unable to save PDF at \(url.path)", "无法保存 PDF：\(url.path)")
        }
    }
}
