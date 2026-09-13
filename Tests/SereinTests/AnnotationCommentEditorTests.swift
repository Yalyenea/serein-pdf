import AppKit
import XCTest
@testable import Serein

@MainActor
final class AnnotationCommentEditorTests: XCTestCase {
    func testEditorPreservesPreviewContextAboveTheComment() throws {
        let (editor, window, hostWindow) = makeEditor(comment: "还要大于，以保证 P 正定")
        defer { window.close(); hostWindow.close() }
        let scroll = try XCTUnwrap(descendants(NSScrollView.self, in: editor.view).first)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)

        XCTAssertEqual(editor.view.bounds.width, 360, accuracy: 0.5)
        let commentFrame = scroll.convert(scroll.bounds, to: editor.view)
        XCTAssertEqual(commentFrame.minX, 14, accuracy: 0.5)
        XCTAssertGreaterThan(editor.view.bounds.maxY - commentFrame.maxY, 40)
        XCTAssertLessThan(editor.view.bounds.height, 160)
        XCTAssertEqual(text.string, "还要大于，以保证 P 正定")
        XCTAssertFalse(descendants(NSTextField.self, in: editor.view).contains { $0.stringValue.isEmpty })
        XCTAssertTrue(descendants(NSTextField.self, in: editor.view).contains { $0.stringValue == "Original highlighted passage" })
        let footer = try XCTUnwrap(descendants(ShortcutSequenceView.self, in: editor.view).first)
        let save = try XCTUnwrap(descendants(NSButton.self, in: editor.view).first { $0.title == "Save" })
        XCTAssertEqual(footer.frame.minY - editor.view.bounds.minY, 2, accuracy: 0.5)
        XCTAssertGreaterThan(footer.frame.minX, save.frame.maxX)
        XCTAssertLessThan(footer.frame.minX - save.frame.maxX, 10)
        XCTAssertEqual(scroll.frame.height, 20, accuracy: 0.5)
        XCTAssertEqual(window.frame.size, editor.view.bounds.size)
        XCTAssertEqual(try XCTUnwrap(editor.view.layer).cornerRadius, 6, accuracy: 0.01)
        XCTAssertTrue(try XCTUnwrap(editor.view.layer).masksToBounds)
    }

    func testEditorGrowsForTextAndScrollsAfterReachingItsHeightLimit() throws {
        let (editor, window, hostWindow) = makeEditor(comment: "Short comment")
        defer { window.close(); hostWindow.close() }
        let scroll = try XCTUnwrap(descendants(NSScrollView.self, in: editor.view).first)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        let shortHeight = scroll.frame.height

        text.string = (1...6).map { "Comment line \($0)" }.joined(separator: "\n")
        text.didChangeText()
        layout(editor, in: window)
        XCTAssertGreaterThan(scroll.frame.height, shortHeight)

        text.string = (1...50).map { "Long comment line \($0)" }.joined(separator: "\n")
        text.didChangeText()
        layout(editor, in: window)
        XCTAssertLessThanOrEqual(scroll.frame.height, 180.5)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertGreaterThan(text.frame.height, scroll.contentView.bounds.height)
        let lastCharacter = NSRange(location: (text.string as NSString).length - 1, length: 1)
        text.scrollRangeToVisible(lastCharacter)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)

        text.string = ""
        text.didChangeText()
        layout(editor, in: window)
        XCTAssertEqual(scroll.frame.height, shortHeight, accuracy: 0.5)
    }

    func testThemeRefreshUpdatesAlreadyLoadedEditorInBothAppearances() throws {
        let original = ThemeManager.shared.selection
        defer { ThemeManager.shared.apply(light: original.light, dark: original.dark) }

        for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
            ThemeManager.shared.apply(light: .normal, dark: .normal)
            let (editor, window, hostWindow) = makeEditor(comment: "Theme preview", appearance: appearanceName)
            defer { window.close(); hostWindow.close() }
            let text = try XCTUnwrap(descendants(NSTextView.self, in: editor.view).first)
            let originalBackground = try XCTUnwrap(editor.view.layer?.backgroundColor)

            ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
            window.refreshThemeAppearance()
            layout(editor, in: window)

            let appearance = editor.view.effectiveAppearance
            let theme = ThemeManager.shared.snapshot.descriptor(for: appearance)
            let background = try XCTUnwrap(editor.view.layer?.backgroundColor)
            XCTAssertNotEqual(background, originalBackground)
            assertColor(try XCTUnwrap(NSColor(cgColor: background)), equals: theme.color(for: .paneBackground, appearance: appearance), appearance: appearance)
            assertColor(try XCTUnwrap(text.textColor), equals: theme.color(for: .primaryText, appearance: appearance), appearance: appearance)
            assertColor(text.insertionPointColor, equals: theme.color(for: .primaryText, appearance: appearance), appearance: appearance)

            let bar = try XCTUnwrap(editor.view.subviews.first { $0.frame.width <= 4 && $0.frame.height > 30 })
            let barColor = try XCTUnwrap(bar.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
            assertColor(barColor, equals: HighlightColor.pink.nsColor(in: theme.highlightPalette), appearance: appearance)
        }
    }

    func testShownPanelResizesWithEditsAndReturnsToTopAfterDeletingLongComment() throws {
        _ = NSApplication.shared
        let group = DocumentHighlightGroup(
            groupID: "panel-resize-test",
            pageIndex: 0,
            snippet: "Original highlighted passage",
            color: .pink,
            createdAt: nil,
            comment: "Short comment",
            primarySelection: nil,
            records: []
        )
        let editor = AnnotationCommentEditorViewController(group: group)
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        hostWindow.isReleasedWhenClosed = false
        hostWindow.center()
        hostWindow.orderFront(nil)
        let panel = AnnotationCommentPanel(editor: editor)
        defer {
            panel.close()
            hostWindow.close()
        }
        let anchor = try XCTUnwrap(hostWindow.contentView)
        panel.show(
            relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 1, height: 1),
            of: anchor
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        editor.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(editor.view.window === panel)
        XCTAssertEqual(panel.frame.size, editor.view.bounds.size)
        let shortWindowHeight = panel.frame.height
        let scroll = try XCTUnwrap(descendants(NSScrollView.self, in: editor.view).first)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertTrue(panel.firstResponder === text)

        let longComment = (1...50).map { "Long comment line \($0)" }.joined(separator: "\n")
        text.insertText(longComment, replacementRange: NSRange(location: 0, length: (text.string as NSString).length))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        editor.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(panel.frame.height, shortWindowHeight)
        XCTAssertEqual(panel.frame.height, editor.preferredContentSize.height, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, editor.view.bounds.size)
        XCTAssertLessThanOrEqual(scroll.frame.height, 180.5)
        text.scrollRangeToVisible(NSRange(location: (text.string as NSString).length - 1, length: 1))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)

        text.selectAll(nil)
        text.deleteBackward(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        editor.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(text.string, "")
        XCTAssertEqual(panel.frame.height, shortWindowHeight, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, editor.view.bounds.size)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    }

    func testPanelClosesWithItsReaderWindow() throws {
        let (editor, panel, hostWindow) = makeEditor(comment: "Close with the reader")
        defer {
            panel.close()
            hostWindow.close()
        }
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.firstResponder === descendants(NSTextView.self, in: editor.view).first)

        hostWindow.close()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.parent)
    }

    func testSaveAndCancelKeyboardActionsPreserveTheEditedText() throws {
        let (editor, window, hostWindow) = makeEditor(comment: "Original")
        defer { window.close(); hostWindow.close() }
        let text = try XCTUnwrap(descendants(NSTextView.self, in: editor.view).first)
        var saved: [String] = []
        var cancelCount = 0
        editor.onSave = { saved.append($0) }
        editor.onCancel = { cancelCount += 1 }
        text.string = "Edited comment\n第二行"

        text.keyDown(with: try keyEvent(code: 36, characters: "\r", modifiers: .command))
        XCTAssertEqual(saved, [text.string])
        text.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}", modifiers: []))
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(saved.count, 1)

        let save = try XCTUnwrap(descendants(NSButton.self, in: editor.view).first { $0.title == "Save" })
        save.performClick(nil)
        XCTAssertEqual(saved, [text.string, text.string])
    }

    func testPreviewClickKeepsThePanelAndImmediatelyFocusesTheEditor() throws {
        let (editor, panel, hostWindow) = makeEditor(comment: "第一行评论\n第二行评论\n第三行评论", editing: false)
        defer { panel.close(); hostWindow.close() }
        XCTAssertFalse(editor.isEditing)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.isKeyWindow)
        let previewFrame = panel.frame
        let card = editor.cardView
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: 30, y: 30), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))

        card.mouseDown(with: event)

        XCTAssertTrue(editor.isEditing)
        XCTAssertTrue(card === panel.contentView)
        XCTAssertTrue(card.window === panel)
        XCTAssertEqual(previewFrame.minX, panel.frame.minX, accuracy: 0.5)
        XCTAssertEqual(previewFrame.width, panel.frame.width, accuracy: 0.5)
        XCTAssertTrue(abs(previewFrame.maxY - panel.frame.maxY) < 0.5 || abs(previewFrame.minY - panel.frame.minY) < 0.5)
        XCTAssertTrue(panel.firstResponder === descendants(NSTextView.self, in: editor.view).first)
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testRenderThemePreviewsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["SEREIN_COMMENT_SNAPSHOTS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = ThemeManager.shared.selection
        defer { ThemeManager.shared.apply(light: original.light, dark: original.dark) }
        let themes: [(String, LightTheme, DarkTheme, NSAppearance.Name)] = [
            ("normal-light", .normal, .normal, .aqua),
            ("rose-pine-dawn", .rosePineDawn, .rosePineMoon, .aqua),
            ("normal-dark", .normal, .normal, .darkAqua),
            ("rose-pine-moon", .rosePineDawn, .rosePineMoon, .darkAqua),
        ]
        for (name, light, dark, appearance) in themes {
            ThemeManager.shared.apply(light: light, dark: dark)
            let (editor, window, hostWindow) = makeEditor(comment: "还要大于，以保证 P 正定。\n第二行评论保持原位，点击后可以直接编辑。", appearance: appearance, editing: false)
            defer { window.close(); hostWindow.close() }
            window.refreshThemeAppearance()
            for state in ["preview", "editing", "empty"] {
                if state == "editing" { window.beginEditing() }
                if state == "empty" {
                    let text = try XCTUnwrap(descendants(NSTextView.self, in: editor.view).first)
                    text.string = ""
                    text.didChangeText()
                }
                layout(editor, in: window)
                let content = try XCTUnwrap(window.contentView)
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.1)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("comment-\(name)-\(state).png"))
            }
        }
    }

    private func makeEditor(
        comment: String,
        appearance: NSAppearance.Name = .aqua,
        editing: Bool = true
    ) -> (AnnotationCommentEditorViewController, AnnotationCommentPanel, NSWindow) {
        _ = NSApplication.shared
        let group = DocumentHighlightGroup(
            groupID: "comment-editor-test",
            pageIndex: 0,
            snippet: "Original highlighted passage",
            color: .pink,
            createdAt: nil,
            comment: comment,
            primarySelection: nil,
            records: []
        )
        let editor = AnnotationCommentEditorViewController(group: group)
        let window = AnnotationCommentPanel(editor: editor)
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        hostWindow.isReleasedWhenClosed = false
        hostWindow.appearance = NSAppearance(named: appearance)
        let reader = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        hostWindow.contentView = reader
        hostWindow.center()
        hostWindow.makeKeyAndOrderFront(nil)
        hostWindow.makeFirstResponder(reader)
        window.show(relativeTo: NSRect(x: 250, y: 200, width: 1, height: 1), of: reader, editing: editing)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        layout(editor, in: window)
        return (editor, window, hostWindow)
    }

    private func layout(_ editor: NSViewController, in window: NSWindow) {
        editor.view.layoutSubtreeIfNeeded()
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? []
        } + view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func keyEvent(code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        ))
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        appearance.performAsCurrentDrawingAppearance {
            guard let actualRGB = actual.usingColorSpace(.sRGB), let expectedRGB = expected.usingColorSpace(.sRGB) else {
                XCTFail("Colors must resolve to sRGB", file: file, line: line)
                return
            }
            XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.005, file: file, line: line)
        }
    }
}
