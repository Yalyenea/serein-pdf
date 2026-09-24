import AppKit
import XCTest
@testable import Serein

@MainActor
final class RecentWindowsPaletteControllerTests: XCTestCase {
    func testFilteringPreservesProvidedOrderAndEnterActivatesSelectedWindow() {
        _ = NSApplication.shared
        let first = RecentWindowsPaletteItem(windowID: UUID(), title: "Reading", documentSummary: "Alpha.pdf")
        let second = RecentWindowsPaletteItem(windowID: UUID(), title: "Notes", documentSummary: "Beta.pdf")
        var activated: UUID?
        let controller = RecentWindowsPaletteController(onActivateWindow: { activated = $0 }, onSplitWindow: { _, _ in XCTFail() })
        defer { controller.close() }
        controller.show(with: [first, second], currentWindowID: nil, relativeTo: nil)
        XCTAssertEqual(controller.testingHighlightedWindowID, first.windowID)
        controller.testingSetQuery("Beta")
        XCTAssertEqual(controller.testingHighlightedWindowID, second.windowID)
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))
        XCTAssertEqual(activated, second.windowID)
        XCTAssertFalse(controller.window?.isVisible == true)
    }

    func testCurrentWindowMovesBehindOtherWindowsAndEnterActivatesPreviousWindow() {
        _ = NSApplication.shared
        let current = RecentWindowsPaletteItem(windowID: UUID(), title: "Current", documentSummary: "Current.pdf")
        let previous = RecentWindowsPaletteItem(windowID: UUID(), title: "Previous", documentSummary: "Previous.pdf")
        let older = RecentWindowsPaletteItem(windowID: UUID(), title: "Older", documentSummary: "Older.pdf")
        var activated: UUID?
        let controller = RecentWindowsPaletteController(onActivateWindow: { activated = $0 }, onSplitWindow: { _, _ in XCTFail() })
        defer { controller.close() }

        controller.show(with: [current, previous, older], currentWindowID: current.windowID, relativeTo: nil)

        XCTAssertEqual(controller.testingItems.map(\.windowID), [previous.windowID, older.windowID, current.windowID])
        XCTAssertEqual(controller.testingHighlightedWindowID, previous.windowID)
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))
        XCTAssertEqual(activated, previous.windowID)

        controller.show(with: [current], currentWindowID: current.windowID, relativeTo: nil)
        XCTAssertEqual(controller.testingHighlightedWindowID, current.windowID)
    }

    func testFilteringKeepsQueryFieldAtSameScreenPosition() throws {
        _ = NSApplication.shared
        let items = (0..<8).map {
            RecentWindowsPaletteItem(windowID: UUID(), title: "Window \($0)", documentSummary: "Paper \($0).pdf")
        }
        let controller = RecentWindowsPaletteController(onActivateWindow: { _ in }, onSplitWindow: { _, _ in })
        defer { controller.close() }
        controller.show(with: items, currentWindowID: nil, relativeTo: nil)
        let originalQueryFrame = try XCTUnwrap(controller.testingQueryFrameOnScreen)
        let originalHeight = try XCTUnwrap(controller.window?.frame.height)

        controller.testingSetQuery("Window 1")
        let filteredQueryFrame = try XCTUnwrap(controller.testingQueryFrameOnScreen)
        XCTAssertEqual(filteredQueryFrame.minY, originalQueryFrame.minY, accuracy: 0.5)
        XCTAssertLessThan(try XCTUnwrap(controller.window?.frame.height), originalHeight)

        controller.testingSetQuery("")
        XCTAssertEqual(try XCTUnwrap(controller.testingQueryFrameOnScreen).minY, originalQueryFrame.minY, accuracy: 0.5)
    }

    func testThemeRefreshPreservesActiveQueryAcrossPresetsAndCustomBackgrounds() throws {
        _ = NSApplication.shared
        let original = ThemeManager.shared.selection
        defer {
            ThemeManager.shared.apply(light: original.light, dark: original.dark,
                                      lightBackground: original.lightBackground, darkBackground: original.darkBackground)
        }
        let controller = RecentWindowsPaletteController(onActivateWindow: { _ in }, onSplitWindow: { _, _ in })
        defer { controller.close() }
        controller.show(with: [RecentWindowsPaletteItem(windowID: UUID(), title: "Reading", documentSummary: "Paper.pdf")],
                        currentWindowID: nil, relativeTo: nil)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Read", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        let selection = editor.selectedRange()

        func assertTheme() throws {
            controller.refreshChromeColors()
            let appearance = window.effectiveAppearance
            let theme = ThemeManager.shared.snapshot.descriptor(for: appearance)
            func matches(_ actual: NSColor?, _ role: ThemeColorRole) {
                appearance.performAsCurrentDrawingAppearance {
                    XCTAssertEqual(actual.flatMap { ThemeHexColor(color: $0) }, ThemeHexColor(color: theme.color(for: role, appearance: appearance)))
                }
            }
            matches(window.backgroundColor, .splitBackground)
            matches(field.textColor, .primaryText)
            matches(editor.textColor, .primaryText)
            matches(editor.insertionPointColor, .primaryText)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(editor.string, "Read")
            XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(controller.testingItems.count, 1)
        }

        let presets: [(LightTheme, DarkTheme, NSAppearance.Name)] =
            LightTheme.allCases.map { ($0, .normal, .aqua) } + DarkTheme.allCases.map { (.normal, $0, .darkAqua) }
        for (light, dark, appearance) in presets {
            ThemeManager.shared.apply(light: light, dark: dark)
            window.appearance = NSAppearance(named: appearance)
            try assertTheme()
        }
        for hex in ["#164333", "#F0DED0"] {
            let background = ThemeBackgroundOverrides(window: ThemeHexColor(hex: hex))
            ThemeManager.shared.apply(light: .normal, dark: .normal, lightBackground: background, darkBackground: background)
            for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try assertTheme()
            }
        }
    }

    func testSplitForwardsSourceWindowAndDirectionWithoutActivatingIt() {
        _ = NSApplication.shared
        let item = RecentWindowsPaletteItem(windowID: UUID(), title: "Reference", documentSummary: "Paper.pdf")
        var splits: [(UUID, ReaderSplitLayout)] = []
        let controller = RecentWindowsPaletteController(onActivateWindow: { _ in XCTFail() }, onSplitWindow: { splits.append(($0, $1)) })
        defer { controller.close() }
        let cases: [(NSEvent.ModifierFlags, ReaderSplitLayout)] = [([.option], .sideBySide), ([.option, .shift], .stacked)]
        for (flags, expected) in cases {
            controller.show(with: [item], currentWindowID: nil, relativeTo: nil)
            XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(
                characters: "\r", keyCode: 36, modifierFlags: flags, window: controller.window
            )))
            XCTAssertEqual(splits.last?.0, item.windowID)
            XCTAssertEqual(splits.last?.1, expected)
        }
    }

    func testWindowWithoutPDFRejectsSplitAndRemainsSelectable() {
        _ = NSApplication.shared
        let item = RecentWindowsPaletteItem(windowID: UUID(), title: "Empty", documentSummary: "No PDF", canSplit: false)
        var activated: UUID?
        let controller = RecentWindowsPaletteController(onActivateWindow: { activated = $0 }, onSplitWindow: { _, _ in XCTFail() })
        defer { controller.close() }
        controller.show(with: [item], currentWindowID: nil, relativeTo: nil)
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(
            characters: "\r", keyCode: 36, modifierFlags: [.option], window: controller.window
        )))
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.testingFooter.contains("no PDF"))
        XCTAssertTrue(controller.testingHandleKeyEvent(makeKeyEvent(characters: "\r", keyCode: 36, window: controller.window)))
        XCTAssertEqual(activated, item.windowID)
    }
}
