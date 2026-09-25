import AppKit
import NaturalLanguage
import PDFKit

enum SelectionTranslationError: LocalizedError {
    case missingSelection
    case unrecognizedLanguage
    case sourceDocumentChanged
    case missingTranslation
    case unableToAnnotate

    var errorDescription: String? {
        switch self {
        case .missingSelection: "Select some text to translate."
        case .unrecognizedLanguage: "Could not detect the language. Select a longer passage and try again."
        case .sourceDocumentChanged: "The original PDF was closed or reloaded. Select the text again to add an annotation."
        case .missingTranslation: "No translation is available to add."
        case .unableToAnnotate: "The selected text could not be highlighted."
        }
    }
}

/// The selection and document are captured before translation, independently of the active reader.
@MainActor
final class SelectionTranslation {
    struct Request: Equatable, Sendable {
        let id = UUID()
        let text: String
        let sourceLanguage: Locale.Language?
        let targetLanguage: Locale.Language
    }

    enum State: Equatable {
        case translating
        case translated(String)
        case failed(String)
        case cancelled
    }

    private(set) var request: Request
    private(set) var state: State = .translating
    private(set) var addedGroupID: String?
    var onChange: (() -> Void)?

    private let documentStore: DocumentStore
    private let sessionID: UUID
    private let document: PDFDocument
    private let selection: PDFSelection

    init(selection: PDFSelection, sessionID: UUID, documentStore: DocumentStore) throws {
        guard let sourceID = documentStore.sharedDocumentSessionID(for: sessionID),
              documentStore.session(for: sourceID) != nil,
              let document = documentStore.loadedPDFDocument(for: sourceID),
              let snapshot = selection.copy() as? PDFSelection,
              let text = snapshot.string.map(PDFTextSanitizer.sanitize),
              text.isEmpty == false,
              snapshot.pages.isEmpty == false,
              snapshot.pages.allSatisfy({ $0.document === document }) else {
            throw SelectionTranslationError.missingSelection
        }
        self.documentStore = documentStore
        self.sessionID = sourceID
        self.document = document
        self.selection = snapshot
        request = Request(
            text: text,
            sourceLanguage: Self.detectSourceLanguage(of: text),
            targetLanguage: Locale.Language(identifier: "zh-Hans")
        )
    }

    /// Word-sized selections carry too little signal for statistical detection, so English,
    /// the usual source, is favored and confirmed by the system English dictionary.
    static func detectSourceLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 10)
        func weight(_ entry: (key: NLLanguage, value: Double)) -> Double {
            entry.value * (entry.key == .english ? englishPriorWeight : 1)
        }
        guard let language = hypotheses.max(by: { weight($0) < weight($1) })?.key else { return nil }
        if language != .english, isShortEnglishText(text) { return Locale.Language(identifier: "en") }
        return Locale.Language(identifier: language.rawValue)
    }

    private static let englishPriorWeight = 20.0
    private static let maximumDictionaryWordCount = 3

    private static func isShortEnglishText(_ text: String) -> Bool {
        guard text.split(whereSeparator: \.isWhitespace).count <= maximumDictionaryWordCount else { return false }
        let tagger = NLTagger(tagSchemes: [.script])
        tagger.string = text
        var isLatin = false
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .script,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            isLatin = tag?.rawValue == "Latn"
            return isLatin
        }
        guard isLatin else { return false }
        return NSSpellChecker.shared.checkSpelling(
            of: text, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        ).location == NSNotFound
    }

    @discardableResult
    func selectTargetLanguage(_ language: Locale.Language) -> Request {
        request = Request(text: request.text, sourceLanguage: request.sourceLanguage, targetLanguage: language)
        state = .translating
        addedGroupID = nil
        onChange?()
        return request
    }

    func complete(_ request: Request, with result: Result<String, Error>) {
        guard self.request.id == request.id, state != .cancelled, Task.isCancelled == false else { return }
        switch result {
        case let .success(text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state = .failed(SelectionTranslationError.missingTranslation.localizedDescription)
            } else {
                state = .translated(text)
            }
        case let .failure(error):
            state = .failed(error.localizedDescription)
        }
        onChange?()
    }

    @discardableResult
    func addAnnotation() throws -> String {
        if let addedGroupID { return addedGroupID }
        guard case let .translated(text) = state else { throw SelectionTranslationError.missingTranslation }
        guard documentStore.session(for: sessionID) != nil,
              documentStore.loadedPDFDocument(for: sessionID) === document,
              selection.pages.allSatisfy({ $0.document === document }) else {
            throw SelectionTranslationError.sourceDocumentChanged
        }

        let records = HighlightService.applyHighlight(
            to: selection,
            color: NightModeStyle.highlightColor(for: .pink)
        )
        guard let groupID = records.first?.annotation.userName else {
            throw SelectionTranslationError.unableToAnnotate
        }
        // Include /Contents before recording the addition, so undo/redo owns the complete annotation.
        _ = HighlightService.updateComment(text, for: records)
        documentStore.noteHighlightsAdded(records, for: sessionID)
        addedGroupID = groupID
        onChange?()
        return groupID
    }

    func cancel() {
        state = .cancelled
        onChange?()
    }
}
