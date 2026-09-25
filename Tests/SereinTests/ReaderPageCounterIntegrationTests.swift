import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct ReaderPageCounterIntegrationTests {
    @Test func themeSwitchRefreshesReaderCounterWhileEditingWithoutChangingPage() throws {
        let original = ThemeManager.shared.selection
        defer {
            ThemeManager.shared.apply(light: original.light, dark: original.dark,
                                      lightBackground: original.lightBackground, darkBackground: original.darkBackground)
        }
        let (_, controller, split) = try makeWindow()
        defer { controller.close() }
        let readerCounter = try #require(counters(in: split.readerViewController.view).first)
        let window = try #require(controller.window)
        readerCounter.beginEditing()
        let field = try #require(readerCounter.subviews.compactMap { $0 as? NSTextField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("5", replacementRange: editor.selectedRange())
        let selection = editor.selectedRange()
        let text = readerCounter.displayText

        let presets: [(LightTheme, DarkTheme, NSAppearance.Name)] =
            LightTheme.allCases.map { ($0, .normal, .aqua) } +
            DarkTheme.allCases.map { (.normal, $0, .darkAqua) }
        for (light, dark, appearance) in presets {
            ThemeManager.shared.apply(light: light, dark: dark)
            window.appearance = NSAppearance(named: appearance)
            controller.refreshThemeAppearance()
            try assertCounterColors(readerCounter)
            #expect(readerCounter.displayText == text)
            #expect(readerCounter.isEditing)
            #expect(editor.string == "5")
            #expect(editor.selectedRange() == selection)
        }

        let background = ThemeBackgroundOverrides(window: ThemeHexColor(hex: "#164333"))
        ThemeManager.shared.apply(light: .normal, dark: .normal, lightBackground: background, darkBackground: background)
        controller.refreshThemeAppearance()
        try assertCounterColors(readerCounter)
    }

    @Test func appearanceChangeRefreshesBackgroundWithoutExplicitThemeRefresh() throws {
        _ = NSApplication.shared
        let counter = ReaderPageCounterView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        counter.update(pageIndex: 0, pageCount: 10, displayMode: .singlePage)
        counter.appearance = NSAppearance(named: .aqua)
        try assertCounterColors(counter)
        counter.appearance = NSAppearance(named: .darkAqua)
        try assertCounterColors(counter)
    }

    @Test func clickingReaderCounterAndPressingReturnNavigatesPDF() throws {
        let (store, controller, split) = try makeWindow()
        defer { controller.close() }
        let reader = split.readerWorkspaceViewController.activeReaderViewController()
        let counter = try #require(counters(in: reader.view).first)
        let button = try #require(counter.subviews.compactMap { $0 as? NSButton }.first)
        let root = try #require(controller.window?.contentView)
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: root.superview)
        let hit = try #require(root.hitTest(point))
        #expect(hit === button || hit.isDescendant(of: button))
        button.performClick(nil)
        #expect(counter.isEditing)

        let field = try #require(counter.subviews.compactMap { $0 as? NSTextField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("4", replacementRange: editor.selectedRange())
        let window = try #require(controller.window)
        let enter = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        window.sendEvent(enter)

        #expect(!counter.isEditing)
        #expect(reader.pdfView.currentPage === reader.pdfView.document?.page(at: 3))
        #expect(store.activeSession?.currentPageIndex == 3)
        #expect(controller.window?.firstResponder === reader.pdfView)
    }

    @Test func pageCounterSettingImmediatelyHidesAllPanesAndCancelsEditing() throws {
        let (store, controller, split) = try makeWindow()
        defer { controller.close() }
        let workspace = split.readerWorkspaceViewController
        #expect(workspace.splitActivePane(layout: .sideBySide))
        controller.window?.layoutIfNeeded()
        workspace.view.layoutSubtreeIfNeeded()
        let readerCounters = workspace.allReaderViewControllers.flatMap { counters(in: $0.view) }
        #expect(readerCounters.count == 2)
        #expect(readerCounters.allSatisfy { !$0.isHidden })
        let editing = try #require(readerCounters.first)
        editing.beginEditing()
        #expect(editing.isEditing)

        var configuration = store.appConfiguration
        configuration.reader.showPageCounter = false
        store.updateAppConfiguration(configuration)
        #expect(readerCounters.allSatisfy { $0.isHidden && !$0.isEditing })

        configuration.reader.showPageCounter = true
        store.updateAppConfiguration(configuration)
        #expect(readerCounters.allSatisfy { !$0.isHidden && !$0.isEditing })
    }

    private func makeWindow() throws -> (DocumentStore, MainWindowController, SplitViewController) {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "page-counter-integration", pageCount: 6))
        store.setDisplayMode(.singlePage, for: session.id)
        let controller = MainWindowController(documentStore: store)
        let window = try #require(controller.window)
        window.setContentSize(NSSize(width: 1600, height: 900))
        let split = try #require(window.contentViewController as? SplitViewController)
        window.layoutIfNeeded()
        split.view.layoutSubtreeIfNeeded()
        return (store, controller, split)
    }

    private func counters(in view: NSView) -> [ReaderPageCounterView] {
        if let counter = view as? ReaderPageCounterView { return [counter] }
        return view.subviews.flatMap { counters(in: $0) }
    }

    private func assertCounterColors(_ counter: ReaderPageCounterView) throws {
        let appearance = counter.effectiveAppearance
        let theme = ThemeManager.shared.snapshot.descriptor(for: appearance)
        let button = try #require(counter.subviews.compactMap { $0 as? NSButton }.first)
        let field = try #require(counter.subviews.compactMap { $0 as? NSTextField }.first)
        let background = try #require(counter.layer?.backgroundColor)
        #expect(abs(background.alpha - 0.92) < 0.001)
        func matches(_ actual: NSColor?, _ role: ThemeColorRole) {
            appearance.performAsCurrentDrawingAppearance {
                #expect(actual.flatMap { ThemeHexColor(color: $0) } == ThemeHexColor(color: theme.color(for: role, appearance: appearance)))
            }
        }
        matches(NSColor(cgColor: background), .readerBackdrop)
        matches(button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .secondaryText)
        matches(field.textColor, .primaryText)
        if let editor = field.currentEditor() as? NSTextView {
            matches(editor.textColor, .primaryText)
            matches(editor.insertionPointColor, .primaryText)
        }
    }
}
