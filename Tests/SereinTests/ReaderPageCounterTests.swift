import AppKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderPageCounterTests {
    @Test
    func buttonOpensFieldEditorAndReturnUsesTypedPage() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let counter = ReaderPageCounterView(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
        counter.update(pageIndex: 0, pageCount: 12, displayMode: .singlePage)
        counter.isHidden = false
        window.contentView?.addSubview(counter)
        window.contentView?.layoutSubtreeIfNeeded()
        var target: Int?
        counter.onGoToPage = { target = $0; return true }
        counter.onReturnFocus = { window.makeFirstResponder(nil) }
        let button = try #require(counter.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil)
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        let enter = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        editor.insertText("13", replacementRange: editor.selectedRange())
        editor.keyDown(with: enter)
        #expect(counter.isEditing)
        #expect(target == nil)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 2))
        editor.insertText("7", replacementRange: editor.selectedRange())
        editor.keyDown(with: enter)
        #expect(target == 6)
        #expect(!counter.isEditing)

        button.performClick(nil)
        let nextEditor = try #require(window.firstResponder as? NSTextView)
        nextEditor.insertText("3", replacementRange: nextEditor.selectedRange())
        nextEditor.keyDown(with: try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        )))
        #expect(target == 6)
        #expect(!counter.isEditing)
    }

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
