import Foundation
import PDFKit

struct SidebarState: Equatable, Sendable {
    var isLeftSidebarVisible: Bool = true
    var isRightSidebarVisible: Bool = true
}

struct TabPresentationState: Equatable, Sendable {
    var mode: TabPresentationMode = .verticalSidebar
}

enum AnnotationSavePolicy: Equatable, Sendable {
    case after10Minutes
    case never
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
    var sidebarState: SidebarState
    var tabPresentationState: TabPresentationState
    var annotationSavePolicy: AnnotationSavePolicy

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
        sidebarState: SidebarState = SidebarState(),
        tabPresentationState: TabPresentationState = TabPresentationState(),
        annotationSavePolicy: AnnotationSavePolicy = .after10Minutes
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
        self.sidebarState = sidebarState
        self.tabPresentationState = tabPresentationState
        self.annotationSavePolicy = annotationSavePolicy
    }
}
