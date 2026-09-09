import Foundation
import PDFKit

struct SidebarState: Equatable, Sendable {
    var isLeftSidebarVisible: Bool = true
    var isRightSidebarVisible: Bool = true
}

struct TabPresentationState: Equatable, Sendable {
    var mode: TabPresentationMode = .verticalSidebar
}

enum AnnotationSavePolicy: String, CaseIterable, Equatable, Codable, Sendable {
    case after10Minutes = "after_10_minutes"
    case never

    static let `default`: AnnotationSavePolicy = .after10Minutes

    var autoSaveInterval: TimeInterval? {
        switch self {
        case .after10Minutes: 600
        case .never: nil
        }
    }

    var menuTitle: String {
        switch self {
        case .after10Minutes: "Every 10 Minutes"
        case .never: "Never"
        }
    }
}

struct AnnotationAutoSaveJob: Sendable {
    let sessionID: UUID
    let url: URL
    let annotationGeneration: UInt64
    let data: Data
}

struct AnnotationAutoSaveResult: Sendable {
    let job: AnnotationAutoSaveJob
    let stagedURL: URL?
    let errorDescription: String?
}

struct DocumentSession {
    private static let blankURLScheme = "serein-blank"

    let id: UUID
    var url: URL
    var title: String
    var isBlank: Bool
    var pageCount: Int?
    var currentPageIndex: Int
    var displayMode: ReaderDisplayMode
    var scaleMode: ReaderScaleMode
    var zoomScale: CGFloat
    var lastReadPosition: ReadingPosition
    var needsInitialReadingPosition: Bool
    var outlineTree: [OutlineNode]
    var isOutlineLoaded: Bool
    var firstPagePosition: ReadingPosition?
    var isDirty: Bool
    var dirtySince: Date?
    var sidebarState: SidebarState
    var tabPresentationState: TabPresentationState
    var annotationSavePolicy: AnnotationSavePolicy
    var annotationGeneration: UInt64 = 0
    var undoStack: [HighlightUndoOperation] = []
    var redoStack: [HighlightUndoOperation] = []
    var searchCache: DocumentSearchCache = DocumentSearchCache()
    var annotationCache: DocumentHighlightCache = DocumentHighlightCache()
    var isAnnotationCacheLoaded: Bool
    var fileSnapshot: PDFFileSnapshot?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        isBlank: Bool = false,
        pdfDocument: PDFDocument? = nil,
        pageCount: Int? = nil,
        currentPageIndex: Int = 0,
        displayMode: ReaderDisplayMode = .singlePageContinuous,
        scaleMode: ReaderScaleMode = .fitWidth,
        zoomScale: CGFloat = 1.0,
        lastReadPosition: ReadingPosition? = nil,
        outlineTree: [OutlineNode] = [],
        isOutlineLoaded: Bool = false,
        isDirty: Bool = false,
        dirtySince: Date? = nil,
        sidebarState: SidebarState = SidebarState(),
        tabPresentationState: TabPresentationState = TabPresentationState(),
        annotationSavePolicy: AnnotationSavePolicy = .default,
        annotationCache: DocumentHighlightCache = DocumentHighlightCache(),
        isAnnotationCacheLoaded: Bool = false,
        fileSnapshot: PDFFileSnapshot? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.isBlank = isBlank
        self.pageCount = pageCount ?? pdfDocument?.pageCount
        self.currentPageIndex = currentPageIndex
        self.displayMode = displayMode
        self.scaleMode = scaleMode
        self.zoomScale = zoomScale
        self.lastReadPosition = lastReadPosition ?? .zero
        needsInitialReadingPosition = isBlank == false && lastReadPosition == nil
        self.outlineTree = outlineTree
        self.isOutlineLoaded = isOutlineLoaded
        if isBlank {
            firstPagePosition = nil
        } else if let firstPage = pdfDocument?.page(at: 0) {
            firstPagePosition = ReadingPosition.pageTop(
                pageIndex: 0,
                pageBounds: firstPage.bounds(for: .cropBox)
            )
        } else {
            firstPagePosition = nil
        }
        self.isDirty = isDirty
        self.dirtySince = dirtySince
        self.sidebarState = sidebarState
        self.tabPresentationState = tabPresentationState
        self.annotationSavePolicy = annotationSavePolicy
        self.annotationCache = annotationCache
        self.isAnnotationCacheLoaded = isAnnotationCacheLoaded
        self.fileSnapshot = isBlank ? nil : (fileSnapshot ?? PDFFileSnapshot(url: url))
    }

    static func blank(
        id: UUID = UUID(),
        title: String = "Untitled",
        displayMode: ReaderDisplayMode,
        scaleMode: ReaderScaleMode,
        annotationSavePolicy: AnnotationSavePolicy
    ) -> DocumentSession {
        DocumentSession(
            id: id,
            url: URL(string: "\(blankURLScheme)://tab/\(id.uuidString)")!,
            title: title,
            isBlank: true,
            displayMode: displayMode,
            scaleMode: scaleMode,
            annotationSavePolicy: annotationSavePolicy,
            fileSnapshot: nil
        )
    }
}
