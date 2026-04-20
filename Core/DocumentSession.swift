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
    let url: URL
    var title: String
    let pdfDocument: PDFDocument
    var currentPageIndex: Int
    var displayMode: ReaderDisplayMode
    var scaleMode: ReaderScaleMode
    var zoomScale: CGFloat
    var lastReadPosition: ReadingPosition
    var outlineTree: [OutlineNode]
    var isDirty: Bool
    var dirtySince: Date?
    var sidebarState: SidebarState
    var tabPresentationState: TabPresentationState
    var annotationSavePolicy: AnnotationSavePolicy
    var leftSidebarWidth: CGFloat?
    var rightSidebarWidth: CGFloat?
    var undoStack: [HighlightUndoOperation] = []
    var searchCache: DocumentSearchCache = DocumentSearchCache()
    var annotationCache: DocumentHighlightCache = DocumentHighlightCache()

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        pdfDocument: PDFDocument,
        currentPageIndex: Int = 0,
        displayMode: ReaderDisplayMode = .singlePageContinuous,
        scaleMode: ReaderScaleMode = .fitWidth,
        zoomScale: CGFloat = 1.0,
        lastReadPosition: ReadingPosition = .zero,
        outlineTree: [OutlineNode] = [],
        isDirty: Bool = false,
        dirtySince: Date? = nil,
        sidebarState: SidebarState = SidebarState(),
        tabPresentationState: TabPresentationState = TabPresentationState(),
        annotationSavePolicy: AnnotationSavePolicy = .default,
        leftSidebarWidth: CGFloat? = nil,
        rightSidebarWidth: CGFloat? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.pdfDocument = pdfDocument
        self.currentPageIndex = currentPageIndex
        self.displayMode = displayMode
        self.scaleMode = scaleMode
        self.zoomScale = zoomScale
        self.lastReadPosition = lastReadPosition
        self.outlineTree = outlineTree
        self.isDirty = isDirty
        self.dirtySince = dirtySince
        self.sidebarState = sidebarState
        self.tabPresentationState = tabPresentationState
        self.annotationSavePolicy = annotationSavePolicy
        self.leftSidebarWidth = leftSidebarWidth
        self.rightSidebarWidth = rightSidebarWidth
    }
}
