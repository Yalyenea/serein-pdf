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
    private var appConfiguration: AppConfiguration
    private(set) var sessions: [DocumentSession] = []
    private(set) var activeSessionID: UUID?
    private(set) var tabPresentationMode: TabPresentationMode = .verticalSidebar
    private(set) var isLeftSidebarVisible = true
    private(set) var isRightSidebarVisible = true
    private(set) var recentDocumentURLs: [URL] = []
    private(set) var recentlyClosedURLs: [URL] = []
    private static let recentlyClosedLimit = 10

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
        recentDocumentURLs = (try? recentFilesStore.loadRecentFiles()) ?? []
    }

    var activeSession: DocumentSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    func open(documentAt url: URL) throws -> DocumentSession {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentStoreError.unreadableDocument(url)
        }

        let restoredState = try readingStateStore.loadState(for: url)

        let session = DocumentSession(
            url: url,
            pdfDocument: pdfDocument,
            currentPageIndex: restoredState?.readingPosition.pageIndex ?? 0,
            displayMode: restoredState?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
            scaleMode: resolvedScaleMode(restoredState?.scaleMode),
            zoomScale: restoredState?.scaleFactor ?? 1.0,
            lastReadPosition: restoredState?.readingPosition ?? .zero,
            outlineTree: OutlineExtractor.extract(from: pdfDocument),
            sidebarState: SidebarState(
                isLeftSidebarVisible: isLeftSidebarVisible,
                isRightSidebarVisible: isRightSidebarVisible
            ),
            tabPresentationState: TabPresentationState(mode: tabPresentationMode),
            annotationSavePolicy: appConfiguration.annotations.autoSavePolicy
        )

        sessions.append(session)
        activeSessionID = session.id
        recentDocumentURLs = (try? recentFilesStore.recordOpen(for: url)) ?? recentDocumentURLs
        notifyChange()
        return session
    }

    func close(sessionID: UUID) {
        guard let closedIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let closedURL = sessions[closedIndex].url
        sessions.remove(at: closedIndex)
        pushRecentlyClosed(closedURL)

        if activeSessionID == sessionID {
            guard !sessions.isEmpty else {
                activeSessionID = nil
                notifyChange()
                return
            }

            let nextIndex = min(closedIndex, sessions.count - 1)
            activeSessionID = sessions[nextIndex].id
        }

        notifyChange()
    }

    private func pushRecentlyClosed(_ url: URL) {
        recentlyClosedURLs.removeAll { $0 == url }
        recentlyClosedURLs.append(url)
        if recentlyClosedURLs.count > Self.recentlyClosedLimit {
            recentlyClosedURLs.removeFirst(recentlyClosedURLs.count - Self.recentlyClosedLimit)
        }
    }

    func popRecentlyClosed() -> URL? {
        guard recentlyClosedURLs.isEmpty == false else { return nil }
        let url = recentlyClosedURLs.removeLast()
        notifyChange()
        return url
    }

    func closeActiveSession() {
        guard let activeSessionID else { return }
        close(sessionID: activeSessionID)
    }

    func activate(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        activeSessionID = sessionID
        isLeftSidebarVisible = session.sidebarState.isLeftSidebarVisible
        isRightSidebarVisible = session.sidebarState.isRightSidebarVisible
        notifyChange()
    }

    func activatePreviousSession() {
        guard let activeSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == activeSessionID }),
              sessions.count > 1 else { return }

        let previousIndex = (currentIndex - 1 + sessions.count) % sessions.count
        activate(sessionID: sessions[previousIndex].id)
    }

    func activateNextSession() {
        guard let activeSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == activeSessionID }),
              sessions.count > 1 else { return }

        let nextIndex = (currentIndex + 1) % sessions.count
        activate(sessionID: sessions[nextIndex].id)
    }

    func setTabPresentationMode(_ mode: TabPresentationMode) {
        guard tabPresentationMode != mode else { return }
        tabPresentationMode = mode
        isLeftSidebarVisible = mode == .verticalSidebar

        for index in sessions.indices {
            sessions[index].tabPresentationState.mode = mode
            sessions[index].sidebarState.isLeftSidebarVisible = isLeftSidebarVisible
        }

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
        let needsUpdate =
            sessions[sessionIndex].scaleMode != mode ||
            sessions[sessionIndex].zoomScale != scaleFactor

        guard needsUpdate else { return }

        sessions[sessionIndex].scaleMode = mode
        sessions[sessionIndex].zoomScale = scaleFactor
        persistReadingState(for: sessions[sessionIndex])
        notifyChange()
    }

    func updateReadingPosition(_ position: ReadingPosition, scaleFactor: CGFloat, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions[sessionIndex]
        let needsUpdate =
            session.lastReadPosition != position ||
            session.currentPageIndex != position.pageIndex ||
            session.zoomScale != scaleFactor

        guard needsUpdate else { return }

        sessions[sessionIndex].currentPageIndex = position.pageIndex
        sessions[sessionIndex].lastReadPosition = position
        sessions[sessionIndex].zoomScale = scaleFactor
        persistReadingState(for: sessions[sessionIndex])
        notifyChange()
    }

    func setLeftSidebarVisible(_ isVisible: Bool) {
        guard isLeftSidebarVisible != isVisible else { return }
        isLeftSidebarVisible = isVisible
        syncActiveSessionSidebarState()
        notifyChange()
    }

    func setRightSidebarVisible(_ isVisible: Bool) {
        guard isRightSidebarVisible != isVisible else { return }
        isRightSidebarVisible = isVisible
        syncActiveSessionSidebarState()
        notifyChange()
    }

    func setDirty(_ isDirty: Bool, for sessionID: UUID, now: Date = Date()) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].isDirty != isDirty else { return }

        sessions[sessionIndex].isDirty = isDirty
        sessions[sessionIndex].dirtySince = isDirty ? (sessions[sessionIndex].dirtySince ?? now) : nil
        notifyChange()
    }

    func setAnnotationSavePolicy(_ policy: AnnotationSavePolicy, for sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[sessionIndex].annotationSavePolicy != policy else { return }

        sessions[sessionIndex].annotationSavePolicy = policy
        notifyChange()
    }

    func updateAppConfiguration(_ configuration: AppConfiguration) {
        guard appConfiguration != configuration else { return }
        appConfiguration = configuration

        for index in sessions.indices {
            sessions[index].annotationSavePolicy = configuration.annotations.autoSavePolicy
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

        tabPresentationMode = persistedState.tabPresentationMode
        isLeftSidebarVisible = persistedState.tabPresentationMode == .verticalSidebar
            ? true
            : persistedState.isLeftSidebarVisible
        isRightSidebarVisible = persistedState.isRightSidebarVisible
        sessions = []
        activeSessionID = nil

        for reference in persistedState.sessions {
            guard let pdfDocument = PDFDocument(url: reference.url) else { continue }
            let restoredState = try readingStateStore.loadState(for: reference.url)
            sessions.append(
                DocumentSession(
                    url: reference.url,
                    pdfDocument: pdfDocument,
                    currentPageIndex: restoredState?.readingPosition.pageIndex ?? 0,
                    displayMode: restoredState?.displayMode ?? appConfiguration.reader.defaultDisplayMode,
                    scaleMode: resolvedScaleMode(restoredState?.scaleMode),
                    zoomScale: restoredState?.scaleFactor ?? 1.0,
                    lastReadPosition: restoredState?.readingPosition ?? .zero,
                    outlineTree: OutlineExtractor.extract(from: pdfDocument),
                    sidebarState: SidebarState(
                        isLeftSidebarVisible: isLeftSidebarVisible,
                        isRightSidebarVisible: isRightSidebarVisible
                    ),
                    tabPresentationState: TabPresentationState(mode: tabPresentationMode),
                    annotationSavePolicy: appConfiguration.annotations.autoSavePolicy
                )
            )
        }

        if let activeURL = persistedState.activeSessionURL,
           let activeSession = sessions.first(where: { $0.url == activeURL }) {
            activeSessionID = activeSession.id
        } else {
            activeSessionID = sessions.last?.id
        }

        notifyChange()
    }

    private func syncActiveSessionSidebarState() {
        guard let activeSessionID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }

        sessions[sessionIndex].sidebarState.isLeftSidebarVisible = isLeftSidebarVisible
        sessions[sessionIndex].sidebarState.isRightSidebarVisible = isRightSidebarVisible
    }

    private func notifyChange() {
        try? persistence.saveState(
            PersistedDocumentStoreState(
                sessions: sessions.map { PersistedDocumentStoreState.SessionReference(url: $0.url) },
                activeSessionURL: activeSession?.url,
                tabPresentationMode: tabPresentationMode,
                isLeftSidebarVisible: isLeftSidebarVisible,
                isRightSidebarVisible: isRightSidebarVisible
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

    private func persistReadingState(for session: DocumentSession) {
        try? readingStateStore.saveState(
            PersistedReadingState(
                url: session.url,
                displayMode: session.displayMode,
                scaleMode: session.scaleMode,
                scaleFactor: session.zoomScale,
                readingPosition: session.lastReadPosition
            )
        )
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
