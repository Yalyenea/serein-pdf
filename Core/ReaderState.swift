struct ReaderState: Equatable, Sendable {
    var isNightModeEnabled: Bool = false
    var annotationMode: AnnotationMarkupType?
    var highlightColor: HighlightColor = .default

    var isAnnotationModeEnabled: Bool { annotationMode != nil }
}
