import XCTest
@testable import Serein

final class EnglishDictionaryTests: XCTestCase {
    func testOnlySingleEnglishWordsUseDictionaryLookup() {
        for (text, expected) in [("inference", "inference"), ("  inference.\n", "inference"),
                                 ("“kernel”", "kernel"), ("don't", "don't"), ("well-known", "well-known")] {
            XCTAssertEqual(EnglishDictionary.word(in: text), expected)
        }
        for text in ["", "123", "l2", "机器学习", "two words", "one\ntwo", "x/y", "a + b"] {
            XCTAssertNil(EnglishDictionary.word(in: text), text)
        }
    }

    func testAppleBilingualPronunciationIsSeparatedWithoutLosingTheDefinition() {
        let entry = EnglishDictionary(
            text: "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① 推断 ② 推论",
            word: "inference"
        )
        XCTAssertEqual(entry.pronunciation, "BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s")
        XCTAssertEqual(entry.definition, "noun ① 推断 ② 推论")
    }

    func testCompactEntryKeepsItsFirstSenseAndMatchesTheDisplayedAccent() {
        let entry = EnglishDictionary(
            text: "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① uncountable (act, process) 推断 tuīduàn▸ by inference 通过推理 ② countable (conclusion) 推断结果",
            word: "inference"
        )
        XCTAssertEqual(entry.partOfSpeech, "n.")
        XCTAssertEqual(entry.summary, "(act, process) 推断 tuīduàn")
        XCTAssertEqual(entry.displayPronunciation?.region, "美")
        XCTAssertEqual(entry.displayPronunciation?.text, "ˈɪnf(ə)rən(t)s")
        XCTAssertEqual(entry.displayPronunciation?.voice, "en-US")
        XCTAssertTrue(entry.definition.contains("② countable (conclusion) 推断结果"))
        let british = EnglishDictionary(text: "word | BrE wɜːd | A. noun 词", word: "word")
        XCTAssertEqual(british.displayPronunciation?.voice, "en-GB")
        XCTAssertEqual(british.partOfSpeech, "n.")
        XCTAssertEqual(british.summary, "词")
    }

    func testOtherDictionaryFormatsArePreservedWithoutInventingPhonetics() {
        for text in ["inference noun 推理", "inference /ˈɪnfərəns/ noun 推理",
                     "inference noun an expression |x|", "infer | ɪnˈfɜː | verb 推断"] {
            let entry = EnglishDictionary(text: text, word: "inference")
            XCTAssertNil(entry.pronunciation)
            XCTAssertEqual(entry.definition, text)
        }
    }
}
