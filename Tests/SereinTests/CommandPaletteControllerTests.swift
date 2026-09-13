import AppKit
import XCTest
@testable import Serein

@MainActor
final class CommandPaletteControllerTests: XCTestCase {
    func testBuiltInChordSuffixInvokesCommandFromVisiblePalette() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        var invokedWindowIDs: [UUID?] = []
        let targetWindowID = UUID()
        let controller = CommandPaletteController { command, windowID in
            invokedCommands.append(command)
            invokedWindowIDs.append(windowID)
        }
        controller.show(
            commands: [.switchCurrentTheme, .openLibraryPDF],
            bindings: [:],
            targetWindowID: targetWindowID,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "o",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.openLibraryPDF])
        XCTAssertEqual(invokedWindowIDs, [targetWindowID])
    }

    func testCommandTSwitchesThemeInsteadOfCreatingABlankTab() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.switchCurrentTheme, .newBlankTab, .openLibraryPDF],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "t",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testCommandTChordIsConsumedEvenWhenThemeCommandIsHidden() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.newBlankTab],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "t",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testLocalMonitorSwallowsCommandTBeforeMenuDispatch() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.switchCurrentTheme, .newBlankTab],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        NSApp.sendEvent(
            makeKeyEvent(
                characters: "t",
                modifierFlags: [.command],
                window: controller.window
            )
        )

        XCTAssertEqual(invokedCommands, [.switchCurrentTheme])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testSearchAndEnterInvokeHighlightedCommand() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.highlightSelection, .openLibraryPDF, .toggleReaderSplit],
            bindings: AppConfiguration.default.shortcuts.bindings,
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        controller.testingSetQuery("compare split")
        XCTAssertEqual(controller.testingFilteredCommands, [.toggleReaderSplit])
        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeReturnKeyEvent(in: controller.window!)
            )
        )
        XCTAssertEqual(invokedCommands, [.toggleReaderSplit])
    }

    func testCommandKClosesWithoutInvokingCommand() {
        _ = NSApplication.shared
        var invokedCommands: [ShortcutCommand] = []
        let controller = CommandPaletteController { command, _ in invokedCommands.append(command) }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }

        XCTAssertTrue(
            controller.testingHandlePanelKeyEvent(
                makeKeyEvent(
                    characters: "k",
                    modifierFlags: [.command],
                    window: controller.window
                )
            )
        )
        XCTAssertEqual(invokedCommands, [])
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testResigningKeyClosesWithoutRestoringParentWindow() {
        _ = NSApplication.shared
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = CommandPaletteController { _, _ in }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: parentWindow
        )
        XCTAssertTrue(controller.window?.delegate === controller)

        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: controller.window)
        )

        XCTAssertFalse(controller.window?.isVisible ?? true)
        XCTAssertFalse(parentWindow.isVisible)
    }

    func testSearchFieldMatchesFloatingOutlineChromeMetrics() {
        _ = NSApplication.shared
        let controller = CommandPaletteController { _, _ in }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let queryField = controller.testingQueryField
        XCTAssertTrue(queryField.cell is ThemedSearchFieldCell)
        XCTAssertEqual(queryField.controlSize, .large)
        XCTAssertEqual(queryField.font?.pointSize, 20)
        XCTAssertEqual(queryField.frame.width, 544, accuracy: 0.01)
        XCTAssertEqual(queryField.frame.height, 34, accuracy: 0.01)
        XCTAssertFalse(queryField.drawsBackground)
        XCTAssertFalse(queryField.hasAmbiguousLayout)
        XCTAssertGreaterThan(queryField.searchTextBounds.minX, queryField.searchButtonBounds.midX)
        XCTAssertLessThan(queryField.searchTextBounds.maxX, queryField.bounds.maxX)
        let placeholderColor = try? XCTUnwrap(
            queryField.placeholderAttributedString?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        queryField.effectiveAppearance.performAsCurrentDrawingAppearance {
            let actual = placeholderColor?.usingColorSpace(.deviceRGB)
            let expected = NightModeStyle.tertiaryTextColor.usingColorSpace(.deviceRGB)
            guard let actual, let expected else {
                XCTFail("Expected theme colors to resolve in device RGB")
                return
            }
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001)
            XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.001)
        }
    }

    func testSearchFieldChromeFollowsCurrentTheme() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let controller = CommandPaletteController { _, _ in }
        controller.show(
            commands: [.openLibraryPDF],
            bindings: [:],
            targetWindowID: nil,
            relativeTo: nil
        )
        defer { controller.dismiss() }
        let queryField = controller.testingQueryField
        let searchCell = try XCTUnwrap(queryField.cell as? ThemedSearchFieldCell)
        var resolvedNormalColor: NSColor?
        queryField.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedNormalColor = searchCell.backgroundColor?.usingColorSpace(.sRGB)
        }
        let normalColor = try XCTUnwrap(resolvedNormalColor)

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        controller.refreshChromeColors()
        var resolvedDawnColor: NSColor?
        var resolvedExpectedColor: NSColor?
        queryField.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedDawnColor = searchCell.backgroundColor?.usingColorSpace(.sRGB)
            resolvedExpectedColor = NightModeStyle.selectedChromeBackgroundColor.usingColorSpace(.sRGB)
        }
        let dawnColor = try XCTUnwrap(resolvedDawnColor)
        let expectedColor = try XCTUnwrap(resolvedExpectedColor)

        XCTAssertGreaterThan(abs(dawnColor.redComponent - normalColor.redComponent), 0.01)
        XCTAssertEqual(dawnColor.redComponent, expectedColor.redComponent, accuracy: 0.001)
        XCTAssertEqual(dawnColor.greenComponent, expectedColor.greenComponent, accuracy: 0.001)
        XCTAssertEqual(dawnColor.blueComponent, expectedColor.blueComponent, accuracy: 0.001)
        XCTAssertEqual(searchCell.strokeColor.alphaComponent, 0.32, accuracy: 0.001)
    }
}
