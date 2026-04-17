import AppKit
import Foundation
import PDFKit

enum TabPresentationMode: String, CaseIterable, Sendable {
    case verticalSidebar
    case horizontalTitlebar
}

extension Notification.Name {
    static let documentStoreDidChange = Notification.Name("DocumentStore.didChange")
}

@MainActor
final class DocumentStore {
    private(set) var sessions: [DocumentSession] = []
    private(set) var activeSessionID: UUID?
    private(set) var tabPresentationMode: TabPresentationMode = .verticalSidebar

    var activeSession: DocumentSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    func open(documentAt url: URL) throws -> DocumentSession {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentStoreError.unreadableDocument(url)
        }

        let session = DocumentSession(
            url: url,
            pdfDocument: pdfDocument,
            tabPresentationState: TabPresentationState(mode: tabPresentationMode)
        )

        sessions.append(session)
        activeSessionID = session.id
        notifyChange()
        return session
    }

    func close(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }

        if activeSessionID == sessionID {
            activeSessionID = sessions.last?.id
        }

        notifyChange()
    }

    func activate(sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        activeSessionID = sessionID
        notifyChange()
    }

    func setTabPresentationMode(_ mode: TabPresentationMode) {
        guard tabPresentationMode != mode else { return }
        tabPresentationMode = mode

        for index in sessions.indices {
            sessions[index].tabPresentationState.mode = mode
        }

        notifyChange()
    }

    func session(for id: UUID) -> DocumentSession? {
        sessions.first { $0.id == id }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .documentStoreDidChange, object: self)
    }
}

enum DocumentStoreError: Error, LocalizedError {
    case unreadableDocument(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableDocument(url):
            "Unable to open PDF at \(url.path)"
        }
    }
}
