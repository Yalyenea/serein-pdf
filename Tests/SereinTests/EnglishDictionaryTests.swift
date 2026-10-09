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
            text: "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① 推断 ② 推论"
        )
        XCTAssertEqual(entry.pronunciation, "BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s")
        XCTAssertEqual(entry.definition, "noun ① 推断 ② 推论")
    }

    func testCompactEntryKeepsItsFirstSenseAndMatchesTheDisplayedAccent() {
        let entry = EnglishDictionary(
            text: "inference | BrE ˈɪnf(ə)r(ə)n(t)s, AmE ˈɪnf(ə)rən(t)s | noun ① uncountable (act, process) 推断 tuīduàn▸ by inference 通过推理 ② countable (conclusion) 推断结果"
        )
        XCTAssertEqual(entry.partOfSpeech, "n.")
        XCTAssertEqual(entry.summary, "(act, process) 推断 tuīduàn")
        XCTAssertEqual(entry.displayPronunciation?.region, "美")
        XCTAssertEqual(entry.displayPronunciation?.text, "ˈɪnf(ə)rən(t)s")
        XCTAssertEqual(entry.displayPronunciation?.voice, "en-US")
        XCTAssertTrue(entry.definition.contains("② countable (conclusion) 推断结果"))
        let british = EnglishDictionary(text: "word | BrE wɜːd | A. noun 词")
        XCTAssertEqual(british.displayPronunciation?.voice, "en-GB")
        XCTAssertEqual(british.partOfSpeech, "n.")
        XCTAssertEqual(british.summary, "词")
    }

    func testNumberedHeadwordsAndWordClassesBeforePronunciation() {
        let numbered = EnglishDictionary(text: "learned 1 | BrE ˈləːnɪd, AmE ˈlərnəd | adjective ① 博学的")
        XCTAssertEqual(numbered.displayPronunciation?.text, "ˈlərnəd")
        XCTAssertEqual(numbered.partOfSpeech, "adj.")
        XCTAssertEqual(numbered.summary, "博学的")

        let noun = EnglishDictionary(text: "use A. noun | BrE juːs, AmE jus | ① countable and uncountable 使用 ② 用途")
        XCTAssertEqual(noun.displayPronunciation?.text, "jus")
        XCTAssertEqual(noun.definition, "A. noun ① countable and uncountable 使用 ② 用途")
        XCTAssertEqual(noun.partOfSpeech, "n.")
    }

    func testOtherDictionaryFormatsArePreservedWithoutInventingPhonetics() {
        for text in ["inference noun 推理", "inference /ˈɪnfərəns/ noun 推理",
                     "inference noun an expression |x|", "an expression |x| has a magnitude",
                     "模型 | móxíng | noun model"] {
            let entry = EnglishDictionary(text: text)
            XCTAssertNil(entry.pronunciation)
            XCTAssertEqual(entry.definition, text)
        }
    }
}
