import CoreServices
import Foundation

struct EnglishDictionary: Equatable, Sendable {
    let definition: String
    let pronunciation: String?

    var displayPronunciation: (region: String, text: String, voice: String)? {
        guard let pronunciation else { return nil }
        if let american = pronunciation.range(of: "AmE ") {
            return ("美", String(pronunciation[american.upperBound...]), "en-US")
        }
        if let british = pronunciation.range(of: "BrE ") {
            return ("英", String(pronunciation[british.upperBound...]), "en-GB")
        }
        return ("", pronunciation, "en-US")
    }

    private var wordClassRange: Range<String.Index>? {
        definition.range(
            of: #"^(?:[A-Z]\.\s+)?(?:phrasal verb|noun|verb|adjective|adverb|pronoun|preposition|conjunction|interjection|exclamation|determiner)\b"#,
            options: .regularExpression
        )
    }

    var partOfSpeech: String? {
        guard let range = wordClassRange else { return nil }
        let wordClass = definition[range].replacingOccurrences(of: #"^[A-Z]\.\s+"#, with: "", options: .regularExpression)
        return ["noun": "n.", "verb": "v.", "phrasal verb": "phr. v.", "adjective": "adj.",
                "adverb": "adv.", "pronoun": "pron.", "preposition": "prep.", "conjunction": "conj.",
                "interjection": "interj.", "exclamation": "exclam.", "determiner": "det."][wordClass]
    }

    /// A first-sense excerpt; the complete, unmodified entry remains available through system lookup.
    var summary: String {
        var text = wordClassRange.map { String(definition[$0.upperBound...]) } ?? definition
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstSense = text.firstIndex(of: "①") { text = String(text[text.index(after: firstSense)...]) }
        if let end = text.firstIndex(where: { "②③④⑤⑥⑦⑧⑨⑩▸\n".contains($0) }) { text = String(text[..<end]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:uncountable|countable)\s+"#, with: "", options: .regularExpression)
    }

    static func word(in text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’.,:;!?()[]{}"))
        guard word.range(of: #"^[A-Za-z]+(?:['’-][A-Za-z]+)*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return word
    }

    static func lookup(_ word: String) -> EnglishDictionary? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let result = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else {
            return nil
        }
        let text = (result as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return EnglishDictionary(text: text, word: word)
    }

    init(text: String, word: String) {
        // Apple's bilingual dictionaries delimit a headword's pronunciation with vertical bars.
        // Keep other dictionary formats intact rather than guessing their structure.
        if let opening = text.firstIndex(of: "|"),
           text[..<opening].trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(word, options: .caseInsensitive) == .orderedSame,
           let closing = text[text.index(after: opening)...].firstIndex(of: "|") {
            let phonetics = text[text.index(after: opening)..<closing]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pronunciation = phonetics.isEmpty ? nil : phonetics
            definition = text[text.index(after: closing)...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            pronunciation = nil
            definition = text
        }
    }
}
