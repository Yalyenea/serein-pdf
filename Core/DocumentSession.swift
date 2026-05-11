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

struct DocumentSession {
    let id: UUID
    var url: URL
    var title: String
    var pageCount: Int?
    var currentPageIndex: Int
    var displayMode: ReaderDisplayMode
    var scaleMode: ReaderScaleMode
    var zoomScale: CGFloat
    var lastReadPosition: ReadingPosition
    var outlineTree: [OutlineNode]
    var isOutlineLoaded: Bool
    var isDirty: Bool
    var dirtySince: Date?
    var sidebarState: SidebarState
    var tabPresentationState: TabPresentationState
    var annotationSavePolicy: AnnotationSavePolicy
    var leftSidebarWidth: CGFloat?
    var rightSidebarWidth: CGFloat?
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
        pdfDocument: PDFDocument? = nil,
        pageCount: Int? = nil,
        currentPageIndex: Int = 0,
        displayMode: ReaderDisplayMode = .singlePageContinuous,
        scaleMode: ReaderScaleMode = .fitWidth,
        zoomScale: CGFloat = 1.0,
        lastReadPosition: ReadingPosition = .zero,
        outlineTree: [OutlineNode] = [],
        isOutlineLoaded: Bool = false,
        isDirty: Bool = false,
        dirtySince: Date? = nil,
        sidebarState: SidebarState = SidebarState(),
        tabPresentationState: TabPresentationState = TabPresentationState(),
        annotationSavePolicy: AnnotationSavePolicy = .default,
        leftSidebarWidth: CGFloat? = nil,
        rightSidebarWidth: CGFloat? = nil,
        annotationCache: DocumentHighlightCache = DocumentHighlightCache(),
        isAnnotationCacheLoaded: Bool = false,
        fileSnapshot: PDFFileSnapshot? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.pageCount = pageCount ?? pdfDocument?.pageCount
        self.currentPageIndex = currentPageIndex
        self.displayMode = displayMode
        self.scaleMode = scaleMode
        self.zoomScale = zoomScale
        self.lastReadPosition = lastReadPosition
        self.outlineTree = outlineTree
        self.isOutlineLoaded = isOutlineLoaded
        self.isDirty = isDirty
        self.dirtySince = dirtySince
        self.sidebarState = sidebarState
        self.tabPresentationState = tabPresentationState
        self.annotationSavePolicy = annotationSavePolicy
        self.leftSidebarWidth = leftSidebarWidth
        self.rightSidebarWidth = rightSidebarWidth
        self.annotationCache = annotationCache
        self.isAnnotationCacheLoaded = isAnnotationCacheLoaded
        self.fileSnapshot = fileSnapshot ?? PDFFileSnapshot(url: url)
    }
}
