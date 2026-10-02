import AppKit
import XCTest
@testable import Serein

@MainActor
final class WorkspaceSelectorInteractionTests: XCTestCase {
    func testKeyboardConfirmationActivatesHighlightedWorkspaceFromAnotherRow() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let originalID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let researchID = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
        let selector = WorkspaceSelectorView(documentStore: store, windowID: windowID)
        let source = selector.testingMenu
        let menu = WorkspaceKeyboardTestMenu()
        menu.autoenablesItems = false
        for item in source.items {
            source.removeItem(item)
            menu.addItem(item)
        }
        let receivingRow = try XCTUnwrap(menu.items.first?.view)
        menu.keyboardSelection = menu.items[1]
        for keyCode in [UInt16(36), 76, 49] {
            store.activateWorkspace(originalID, in: windowID)
            receivingRow.keyDown(with: makeKeyEvent(characters: keyCode == 49 ? " " : "\r", keyCode: keyCode))
            XCTAssertEqual(store.activeWorkspaceID(in: windowID), researchID, "Confirmation key \(keyCode)")
        }
    }

    func testCompactControlUsesOneIconAndMenuMarksCurrentWorkspace() throws {
        let store = makeIsolatedDocumentStore()
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
        _ = store.createWorkspace(name: "Research", in: store.defaultWindowID)
        let selector = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID)
        XCTAssertEqual(selector.intrinsicContentSize, NSSize(width: 26, height: 24))
        XCTAssertTrue(findAllDescendants(of: NSTextField.self, in: selector).isEmpty)
        let button = try XCTUnwrap(findDescendant(of: NSButton.self, in: selector))
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.toolTip, "Research")
        let menu = selector.testingMenu
        let workspaces = menu.items.filter { $0.representedObject is UUID }
        XCTAssertEqual(workspaces.count, 2)
        XCTAssertTrue(workspaces.allSatisfy { $0.image == nil })
        XCTAssertTrue(menu.items.allSatisfy { $0.view != nil })
        XCTAssertEqual(menu.items.suffix(2).map(\.title), ["New Workspace", "Rename"])
        XCTAssertEqual(workspaces.filter { $0.state == .on }.map(\.title), ["Research"])
        let first = try XCTUnwrap(workspaces.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(first.action), to: first.target, from: first))
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), firstID)
        XCTAssertEqual(selector.testingMenu.items.filter { $0.state == .on }.count, 1)
    }

    func testVerticalSidebarHasOnlyFooterWorkspaceControls() throws {
        let store = makeIsolatedDocumentStore()
        let id = try XCTUnwrap(store.createWorkspace(name: "Research", in: store.defaultWindowID))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        XCTAssertNil(findView(identifier: "workspaceSelector", in: controller.view))
        let selector = try XCTUnwrap(findView(identifier: "workspaceFooter", in: controller.view) as? WorkspaceSelectorView)
        let icon = try XCTUnwrap(selector.testingWorkspaceButtons.last)
        let menu = try XCTUnwrap(icon.menu)
        XCTAssertEqual(menu.items.map(\.title), ["New Workspace", "Rename"])
        XCTAssertEqual(menu.items.last?.representedObject as? String, id.uuidString)
        store.renameWorkspace(id, name: "Papers", in: store.defaultWindowID)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(selector.testingCurrentWorkspaceName, "Papers")
    }

    func testFooterIconsAreOneClickActionsWithFullNameTooltips() throws {
        let store = makeIsolatedDocumentStore()
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
        _ = store.createWorkspace(name: "研究", in: store.defaultWindowID)
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        XCTAssertEqual(footer.testingWorkspaceButtons.last?.title, "研")
        XCTAssertEqual(footer.testingWorkspaceButtons.last?.toolTip, "研究")
        let firstButton = try XCTUnwrap(footer.testingWorkspaceButtons.first)
        firstButton.performClick(nil)
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), firstID)
        XCTAssertEqual(firstButton.accessibilityValue() as? String, "Current Workspace")
        XCTAssertFalse(footer.testingAddButton.isHidden)
        XCTAssertEqual(footer.testingAddButton.toolTip, "New Workspace")
    }

    func testFooterContextMenuRenamesItsWorkspaceWithoutSwitching() throws {
        let store = makeIsolatedDocumentStore()
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
        let secondID = try XCTUnwrap(store.createWorkspace(name: "Research", in: store.defaultWindowID))
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        let menu = try XCTUnwrap(footer.testingWorkspaceButtons.first?.menu)
        menu.performActionForItem(at: 1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        let sheet = try XCTUnwrap(window.attachedSheet)
        let field = try XCTUnwrap(footer.testingNameField)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.string, "Workspace")
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        editor.insertText("Reading", replacementRange: editor.selectedRange())
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), secondID)
        XCTAssertEqual(store.workspaces(in: store.defaultWindowID).first { $0.id == firstID }?.name, "Reading")
        XCTAssertEqual(footer.testingWorkspaceButtons.first?.toolTip, "Reading")
    }

    func testLongFooterUsesNativeScrollAndRevealsNewlyActiveIcon() throws {
        let store = makeIsolatedDocumentStore()
        for index in 0..<30 { _ = store.createWorkspace(name: "Research \(index)", in: store.defaultWindowID) }
        let firstID = try XCTUnwrap(store.workspaces(in: store.defaultWindowID).first?.id)
        store.activateWorkspace(firstID, in: store.defaultWindowID)
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 240, height: 100))
        defer { window.close() }
        let scroll = try XCTUnwrap(findDescendant(of: NSScrollView.self, in: footer))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertGreaterThan(document.frame.width, scroll.documentVisibleRect.width)
        let last = try XCTUnwrap(footer.testingWorkspaceButtons.last)
        last.performClick(nil)
        window.layoutIfNeeded()
        footer.layoutSubtreeIfNeeded()
        let lastRect = document.convert(last.bounds, from: last)
        XCTAssertTrue(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(lastRect))
        XCTAssertEqual(window.contentView?.frame.width ?? 0, 240, accuracy: 0.5)
    }

    func testFooterStaysPinnedWhenEmptyWorkspaceShowsRecentFiles() throws {
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "workspace-footer-recent"))
        _ = store.createWorkspace(name: "Empty", in: store.defaultWindowID)
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        let window = host(controller.view, size: NSSize(width: 240, height: 480), fillHeight: true)
        defer { window.close() }
        let footer = try XCTUnwrap(findView(identifier: "workspaceFooter", in: controller.view) as? WorkspaceSelectorView)
        XCTAssertFalse(footer.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(footer.frame.minY, 8, accuracy: 0.5)
        XCTAssertTrue(controller.testingRecentSectionTopPinned)
        XCTAssertEqual(footer.testingWorkspaceButtons.count, 2)
    }

    func testHorizontalTrackpadGestureSwitchesOnceAndMomentumCannotSwitch() throws {
        for style in [WorkspaceSelectorView.Style.compact, .sidebarFooter] {
            let store = makeIsolatedDocumentStore()
            let first = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
            let second = try XCTUnwrap(store.createWorkspace(name: "Second", in: store.defaultWindowID))
            _ = store.createWorkspace(name: "Third", in: store.defaultWindowID)
            store.activateWorkspace(first, in: store.defaultWindowID)
            let selector = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: style)
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: 0, y: 0, phase: 1))
            XCTAssertTrue(selector.testingHandleScrollWheel(try scrollEvent(x: -24, y: 0, phase: 2)))
            XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), second)
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: -240, y: 0, phase: 2))
            XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), second)
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: 0, y: 0, phase: 4))
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: -240, y: 0, momentum: 1))
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: -180, y: 0, momentum: 2))
            XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), second)
            _ = selector.testingHandleScrollWheel(try scrollEvent(x: 24, y: 0, phase: 1))
            XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), first)
        }
    }

    func testVerticalTrackpadGesturePassesThroughWithoutWorkspaceSwitch() throws {
        let store = makeIsolatedDocumentStore()
        _ = store.createWorkspace(name: "Research", in: store.defaultWindowID)
        let originalID = store.activeWorkspaceID(in: store.defaultWindowID)
        let selector = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID)
        XCTAssertFalse(selector.testingHandleScrollWheel(try scrollEvent(x: 2, y: 40, phase: 1)))
        XCTAssertFalse(selector.testingHandleScrollWheel(try scrollEvent(x: 80, y: 10, phase: 2)))
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), originalID)
        XCTAssertFalse(selector.testingHandleScrollWheel(try scrollEvent(x: 2, y: 80, momentum: 1)))
    }

    func testWorkspaceControlsAndActiveNameEditorRefreshAcrossThemes() throws {
        let original = ThemeManager.shared.selection
        defer {
            ThemeManager.shared.apply(light: original.light, dark: original.dark,
                                      lightBackground: original.lightBackground, darkBackground: original.darkBackground)
        }
        let store = makeIsolatedDocumentStore()
        _ = store.createWorkspace(name: "Research", in: store.defaultWindowID)
        let compact = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID)
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        footer.testingPresentNameEditor(workspaceID: store.activeWorkspaceID(in: store.defaultWindowID))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        let sheet = try XCTUnwrap(window.attachedSheet)
        defer { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
        let field = try XCTUnwrap(footer.testingNameField)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Unsaved workspace name", replacementRange: editor.selectedRange())
        let menu = compact.testingMenu
        compact.menuWillOpen(menu)
        defer { compact.menuDidClose(menu) }
        let controls = [compact, footer]
        for light in LightTheme.allCases {
            window.appearance = NSAppearance(named: .aqua)
            compact.appearance = NSAppearance(named: .aqua)
            footer.appearance = NSAppearance(named: .aqua)
            ThemeManager.shared.apply(light: light, dark: .rosePineMoon)
            checkTheme(controls: controls, field: field, editor: editor)
            XCTAssertTrue(menu.items.allSatisfy { $0.view?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua })
            XCTAssertEqual(sheet.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        }
        for dark in DarkTheme.allCases {
            window.appearance = NSAppearance(named: .darkAqua)
            compact.appearance = NSAppearance(named: .darkAqua)
            footer.appearance = NSAppearance(named: .darkAqua)
            ThemeManager.shared.apply(light: .normal, dark: dark)
            checkTheme(controls: controls, field: field, editor: editor)
            XCTAssertTrue(menu.items.allSatisfy { $0.view?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua })
            XCTAssertEqual(sheet.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        }
        let background = ThemeBackgroundOverrides(window: try XCTUnwrap(ThemeHexColor(hex: "#102035")))
        ThemeManager.shared.apply(light: .normal, dark: .normal, lightBackground: background, darkBackground: background)
        checkTheme(controls: controls, field: field, editor: editor)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "Unsaved workspace name")
    }

    private func checkTheme(controls: [WorkspaceSelectorView], field: NSTextField, editor: NSTextView) {
        controls.forEach { $0.refreshChromeColors() }
        for selector in controls {
            selector.effectiveAppearance.performAsCurrentDrawingAppearance {
                if selector.style == .compact {
                    let button = findDescendant(of: NSButton.self, in: selector)
                    XCTAssertEqual(button?.contentTintColor?.usingColorSpace(.sRGB), NightModeStyle.secondaryTextColor.usingColorSpace(.sRGB))
                }
                for button in selector.testingWorkspaceButtons {
                    let expected = button.accessibilityValue() as? String == "Current Workspace" ? NightModeStyle.primaryTextColor : NightModeStyle.secondaryTextColor
                    let color = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    XCTAssertEqual(color?.usingColorSpace(.sRGB), expected.usingColorSpace(.sRGB))
                }
            }
        }
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(field.backgroundColor?.usingColorSpace(.sRGB), NightModeStyle.readerBackdropColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.backgroundColor.usingColorSpace(.sRGB), NightModeStyle.readerBackdropColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.textColor?.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.insertionPointColor.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
        }
    }

    private func scrollEvent(x: Int32, y: Int32, phase: Int64 = 0, momentum: Int64 = 0) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func host(_ view: NSView, size: NSSize, fillHeight: Bool = false) -> NSWindow {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
        ]
        if fillHeight { constraints.append(view.bottomAnchor.constraint(equalTo: root.bottomAnchor)) }
        NSLayoutConstraint.activate(constraints)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        root.layoutSubtreeIfNeeded()
        return window
    }
}

private final class WorkspaceKeyboardTestMenu: NSMenu {
    var keyboardSelection: NSMenuItem?
    override var highlightedItem: NSMenuItem? { keyboardSelection }
}
