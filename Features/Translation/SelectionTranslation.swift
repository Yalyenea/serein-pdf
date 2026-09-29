import AppKit
import NaturalLanguage
import PDFKit

enum SelectionTranslationError: LocalizedError {
    case missingSelection
    case requiresMacOS15
    case unrecognizedLanguage
    case sourceDocumentChanged
    case missingTranslation
    case unableToAnnotate

    var errorDescription: String? {
        switch self {
        case .requiresMacOS15: L10n.text("Translation requires macOS 15 or later.", "翻译需要 macOS 15 或更高版本。")
        case .missingSelection: L10n.text("Select some text to translate.", "请选择要翻译的文字。")
        case .unrecognizedLanguage: L10n.text("Only Chinese and English text is supported. Select a word or passage and try again.", "仅支持中文和英文，请选择单词或段落后重试。")
        case .sourceDocumentChanged: L10n.text("The original PDF was closed or reloaded. Select the text again to add an annotation.", "原 PDF 已关闭或重新加载，请重新选择文字以添加批注。")
        case .missingTranslation: L10n.text("No translation is available to add.", "暂无可添加的译文。")
        case .unableToAnnotate: L10n.text("The selected text could not be highlighted.", "无法高亮所选文字。")
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
        let source = Self.detectSourceLanguage(of: text)
        request = Request(text: text, sourceLanguage: source, targetLanguage: Self.targetLanguage(for: source))
    }

    /// Count words by script so Chinese prose containing English technical terms stays Chinese.
    /// Within this bilingual tool, Latin-script words are treated as English.
    static func detectSourceLanguage(of text: String) -> Locale.Language? {
        let tagger = NLTagger(tagSchemes: [.script])
        tagger.string = text
        var english = 0
        var simplified = 0
        var traditional = 0
        var unsupported = false
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .script,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard text[range].unicodeScalars.contains(where: CharacterSet.letters.contains) else { return true }
            switch tag?.rawValue {
            case "Latn": english += 1
            case "Hans", "Hani": simplified += 1
            case "Hant": traditional += 1
            default: unsupported = true
            }
            return true
        }
        guard !unsupported, english + simplified + traditional > 0 else { return nil }
        if simplified + traditional >= english {
            return Locale.Language(identifier: traditional > simplified ? "zh-Hant" : "zh-Hans")
        }
        return Locale.Language(identifier: "en")
    }

    private static func targetLanguage(for source: Locale.Language?) -> Locale.Language {
        Locale.Language(identifier: source?.languageCode?.identifier == "zh" ? "en" : "zh-Hans")
    }

    var englishWord: String? {
        guard request.sourceLanguage?.languageCode?.identifier == "en" else { return nil }
        return EnglishDictionary.word(in: request.text)
    }

    @discardableResult
    func retry() -> Request {
        beginRequest(source: request.sourceLanguage, target: request.targetLanguage)
    }

    @discardableResult
    func reverseDirection() -> Request {
        beginRequest(source: request.targetLanguage, target: Self.targetLanguage(for: request.targetLanguage))
    }

    private func beginRequest(source: Locale.Language?, target: Locale.Language) -> Request {
        request = Request(text: request.text, sourceLanguage: source, targetLanguage: target)
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
