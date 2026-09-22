import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderPageCounterTests {
    @Test
    func usesPhysicalPageRangesForOrdinaryAndBookSpreads() {
        let counter = ReaderPageCounterView()
        for (mode, index, count, expected): (ReaderDisplayMode, Int, Int, String) in [
            (.singlePage, 0, 10, "1 / 10"),
            (.singlePageContinuous, 3, 10, "4 / 10"),
            (.twoUp, 1, 10, "1–2 / 10"),
            (.twoUpContinuous, 4, 5, "5 / 5"),
            (.book, 0, 6, "1 / 6"),
            (.book, 2, 6, "2–3 / 6"),
            (.bookContinuous, 5, 6, "6 / 6"),
        ] {
            counter.update(pageIndex: index, pageCount: count, displayMode: mode)
            #expect(counter.displayText == expected)
        }
    }

    @Test
    func inlineJumpAcceptsOnlyValidPhysicalPageAndCancelDoesNotNavigate() {
        let counter = ReaderPageCounterView()
        counter.update(pageIndex: 2, pageCount: 12, displayMode: .twoUp)
        var targets: [Int] = []
        var focusReturns = 0
        counter.onGoToPage = { targets.append($0); return true }
        counter.onReturnFocus = { focusReturns += 1 }
        counter.beginEditing()
        #expect(counter.isEditing)
        for invalid in ["0", "13", "ii", "3–4", ""] {
            #expect(!counter.submitPageNumber(invalid))
            #expect(counter.isEditing)
        }
        #expect(targets.isEmpty)
        #expect(counter.submitPageNumber(" 12 "))
        #expect(targets == [11])
        #expect(!counter.isEditing)
        #expect(focusReturns == 1)

        counter.beginEditing()
        counter.cancelEditing(restoreFocus: true)
        #expect(targets == [11])
        #expect(!counter.isEditing)
    }

    @Test
    func pageUpdatesKeepUnsubmittedInputAndEmptyDocumentCancelsEditing() throws {
        let counter = ReaderPageCounterView()
        counter.update(pageIndex: 0, pageCount: 10, displayMode: .singlePage)
        counter.beginEditing()
        let field = try #require(counter.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "9"
        counter.update(pageIndex: 3, pageCount: 10, displayMode: .singlePage)
        #expect(counter.isEditing)
        #expect(field.stringValue == "9")
        counter.update(pageIndex: 0, pageCount: 0, displayMode: .singlePage)
        #expect(!counter.isEditing)
        #expect(counter.isHidden)
    }

}
