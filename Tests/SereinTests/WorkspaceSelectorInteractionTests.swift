import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class WorkspaceSelectorInteractionTests: XCTestCase {
    func testKeyboardSwitchesFocusedSpaceAndKeepsPickerOpen() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let researchID = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
        store.activateWorkspace(firstID, in: windowID)
        let selector = WorkspaceSelectorView(documentStore: store, windowID: windowID)
        let window = host(selector, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        selector.testingShowPicker()
        let picker = selector.testingPicker
        XCTAssertTrue(picker.handleKey(makeKeyEvent(characters: "", keyCode: 125)))
        XCTAssertTrue(picker.handleKey(makeKeyEvent(characters: "\r", keyCode: 36)))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), researchID)
        XCTAssertTrue(picker.isVisible)
        XCTAssertNil(window.attachedSheet)
        XCTAssertEqual(picker.testingPanel.frame.width, 196)
        let nameButton = try XCTUnwrap(picker.testingNameButtons.last)
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: picker.testingPanel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        nameButton.mouseDown(with: doubleClick)
        XCTAssertEqual(picker.activeNameField?.stringValue, "Research")
        picker.finishEditing(commit: false)
        XCTAssertTrue(picker.handleKey(makeKeyEvent(characters: "", keyCode: 53)))
        XCTAssertFalse(picker.isVisible)
    }

    func testCompactControlUsesOnlyTheOriginalGroupIcon() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        _ = try XCTUnwrap(store.createWorkspace(name: "Research", icon: .leaf, in: windowID))
        let selector = WorkspaceSelectorView(documentStore: store, windowID: windowID)
        let button = try XCTUnwrap(findDescendant(of: NSButton.self, in: selector))
        XCTAssertEqual(button.title, "")
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.toolTip, "Research")
        XCTAssertEqual(selector.intrinsicContentSize, NSSize(width: 26, height: 24))
        XCTAssertEqual(selector.testingPicker.testingNameButtons.count, 2)
        XCTAssertEqual(selector.testingPicker.testingNameButtons.last?.accessibilityValue() as? String, "Current Space")
        XCTAssertTrue(selector.testingPicker.testingNameButtons.allSatisfy { $0.image == nil })
        XCTAssertNil(button.menu)
        let window = host(selector, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        let picker = selector.testingPicker
        try rightClick(button)
        XCTAssertTrue(picker.isVisible)
        XCTAssertNil(window.attachedSheet)
        button.performClick(nil)
        XCTAssertFalse(picker.isVisible)
        button.performClick(nil)
        XCTAssertTrue(picker.isVisible)
        XCTAssertTrue(selector.testingPicker === picker)
        XCTAssertTrue(picker.testingNameButtons.allSatisfy { $0.menu == nil })
    }

    func testVerticalSidebarHasOnlyFooterWorkspaceControls() throws {
        let store = makeIsolatedDocumentStore()
        let id = try XCTUnwrap(store.createWorkspace(name: "Research", in: store.defaultWindowID))
        let controller = VerticalTabsViewController(documentStore: store, windowID: store.defaultWindowID)
        controller.loadViewIfNeeded()
        XCTAssertNil(findView(identifier: "workspaceSelector", in: controller.view))
        let selector = try XCTUnwrap(findView(identifier: "workspaceFooter", in: controller.view) as? WorkspaceSelectorView)
        let icon = try XCTUnwrap(selector.testingWorkspaceButtons.last)
        XCTAssertNil(icon.menu)
        store.renameWorkspace(id, name: "Papers", in: store.defaultWindowID)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(selector.testingCurrentWorkspaceName, "Papers")
    }

    func testFooterClickSwitchesAndRightClickOpensSharedPickerWithoutSwitching() throws {
        let store = makeIsolatedDocumentStore()
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: store.defaultWindowID))
        let secondID = try XCTUnwrap(store.createWorkspace(name: "研究", in: store.defaultWindowID))
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        XCTAssertEqual(footer.testingWorkspaceButtons.last?.title, "研")
        XCTAssertEqual(footer.testingWorkspaceButtons.last?.toolTip, "研究")
        let firstButton = try XCTUnwrap(footer.testingWorkspaceButtons.first)
        try rightClick(firstButton)
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), secondID)
        XCTAssertTrue(footer.testingPicker.isVisible)
        XCTAssertEqual(footer.testingPicker.testingNameButtons.count, 2)
        XCTAssertNil(window.attachedSheet)
        XCTAssertNil(firstButton.menu)
        try rightClick(firstButton)
        XCTAssertFalse(footer.testingPicker.isVisible)
        firstButton.performClick(nil)
        XCTAssertEqual(store.activeWorkspaceID(in: store.defaultWindowID), firstID)
        XCTAssertFalse(footer.testingPicker.isVisible)
        XCTAssertEqual(firstButton.accessibilityValue() as? String, "Current Space")
        XCTAssertFalse(footer.testingAddButton.isHidden)
        XCTAssertEqual(footer.testingAddButton.toolTip, "New space")
    }

    func testFooterDoubleClickRenamesInline() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        _ = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
        let footer = WorkspaceSelectorView(documentStore: store, windowID: windowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        let button = try XCTUnwrap(footer.testingWorkspaceButtons.first)
        button.performClick(nil)
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        button.mouseDown(with: doubleClick)
        let picker = footer.testingPicker
        let field = try XCTUnwrap(picker.activeNameField)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertNil(window.attachedSheet)
        XCTAssertEqual(editor.string, "Space")
        editor.selectAll(nil)
        editor.insertText("Reading", replacementRange: editor.selectedRange())
        XCTAssertTrue(picker.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), firstID)
        XCTAssertEqual(store.workspaces(in: windowID).first { $0.id == firstID }?.name, "Reading")
        XCTAssertEqual(footer.testingWorkspaceButtons.first?.toolTip, "Reading")
    }

    func testNewSpaceAndRenameCommitCancelAndValidateWithoutButtons() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let selector = WorkspaceSelectorView(documentStore: store, windowID: windowID)
        let window = host(selector, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        selector.testingShowPicker()
        let picker = selector.testingPicker
        try savePreview(picker, name: "switch")
        picker.beginCreating()
        var field = try XCTUnwrap(picker.activeNameField)
        XCTAssertEqual(field.stringValue, "Space 2")
        field.stringValue = "   "
        XCTAssertFalse(picker.finishEditing(commit: true))
        XCTAssertEqual(store.workspaces(in: windowID).count, 1)
        picker.finishEditing(commit: false)
        XCTAssertNil(picker.activeNameField)
        picker.beginCreating()
        field = try XCTUnwrap(picker.activeNameField)
        field.stringValue = "Writing"
        try XCTUnwrap(picker.testingDraftIconButton).performClick(nil)
        picker.selectIcon(.moon)
        XCTAssertTrue(picker.activeNameField === field)
        try savePreview(picker, name: "create")
        XCTAssertTrue(picker.finishEditing(commit: true))
        XCTAssertEqual(store.workspaces(in: windowID).count, 2)
        XCTAssertEqual(store.workspaces(in: windowID).last?.icon, .moon)
        let id = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        picker.beginRenaming(id)
        field = try XCTUnwrap(picker.activeNameField)
        field.stringValue = "Discard"
        picker.finishEditing(commit: false)
        XCTAssertEqual(store.workspaces(in: windowID).last?.name, "Writing")
        picker.beginRenaming(id)
        picker.activeNameField?.stringValue = "Writing notes"
        picker.dismiss()
        XCTAssertEqual(store.workspaces(in: windowID).last?.name, "Writing notes")
        XCTAssertNil(window.attachedSheet)
    }

    func testIconSelectionUpdatesBothControlsWithoutEndingRename() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let id = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let footer = WorkspaceSelectorView(documentStore: store, windowID: windowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        footer.testingShowPicker()
        let picker = footer.testingPicker
        picker.beginRenaming(id)
        let field = try XCTUnwrap(picker.activeNameField)
        field.stringValue = "Draft name"
        picker.showIcons(for: id)
        XCTAssertEqual(picker.testingIconChoices.count, SpaceIcon.allCases.count + 1)
        try savePreview(picker, name: "icons")
        picker.selectIcon(.books)
        XCTAssertTrue(picker.activeNameField === field)
        XCTAssertEqual(field.stringValue, "Draft name")
        XCTAssertNotNil(footer.testingWorkspaceButtons.first?.image)
        XCTAssertEqual(store.workspaces(in: windowID).first?.icon, .books)
        picker.finishEditing(commit: true)
        XCTAssertEqual(store.workspaces(in: windowID).first?.name, "Draft name")
        picker.showIcons(for: id)
        picker.selectIcon(nil)
        XCTAssertNil(footer.testingWorkspaceButtons.first?.image)
        XCTAssertEqual(footer.testingWorkspaceButtons.first?.title, "D")
    }

    func testDeleteKeyTargetsFocusedSpaceInBothTabPresentations() throws {
        _ = NSApplication.shared
        for mode in [TabPresentationMode.verticalSidebar, .horizontalTitlebar] {
            let store = makeIsolatedDocumentStore()
            let windowID = store.defaultWindowID
            let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
            let firstTab = store.newBlankTab(in: windowID)
            let secondID = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
            let secondTab = store.newBlankTab(in: windowID)
            store.setTabPresentationMode(mode)
            if mode == .horizontalTitlebar { store.activateWorkspace(firstID, in: windowID) }
            let controller = MainWindowController(documentStore: store)
            defer { controller.close() }
            controller.showWindow(nil)
            controller.window?.layoutIfNeeded()
            let split = try XCTUnwrap(controller.window?.contentViewController as? SplitViewController)
            let content = mode == .verticalSidebar ? split.verticalTabsViewController.view : split.titlebarTabsController.view
            let selector = try XCTUnwrap(findView(
                identifier: mode == .verticalSidebar ? "workspaceFooter" : "workspaceSelector", in: content
            ) as? WorkspaceSelectorView)
            selector.testingShowPicker()
            let picker = selector.testingPicker
            try XCTUnwrap(picker.testingNameButtons.first).performClick(nil)
            XCTAssertTrue(picker.handleKey(makeKeyEvent(characters: "", keyCode: 51)))
            XCTAssertEqual(store.workspaces(in: windowID).map(\.id), [secondID])
            XCTAssertEqual(store.activeWorkspaceID(in: windowID), secondID)
            XCTAssertEqual(store.sessions(in: windowID).map(\.id), [secondTab.id])
            XCTAssertNil(store.session(for: firstTab.id))
            selector.testingShowPicker()
            XCTAssertTrue(picker.handleKey(makeKeyEvent(characters: "", keyCode: 51)))
            XCTAssertEqual(store.workspaces(in: windowID).map(\.id), [secondID])
        }
    }

    func testDeleteButtonRemovesSpaceAndHidesWhenAlone() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        _ = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let secondID = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
        store.setTabPresentationMode(.verticalSidebar)
        let controller = MainWindowController(documentStore: store)
        defer { controller.close() }
        controller.showWindow(nil)
        controller.window?.layoutIfNeeded()
        let split = try XCTUnwrap(controller.window?.contentViewController as? SplitViewController)
        let selector = try XCTUnwrap(findView(identifier: "workspaceFooter", in: split.verticalTabsViewController.view) as? WorkspaceSelectorView)
        selector.testingShowPicker()
        let picker = selector.testingPicker
        XCTAssertEqual(picker.testingDeleteButtons.count, 2)
        XCTAssertTrue(picker.testingDeleteButtons.allSatisfy { !$0.isHidden && $0.toolTip != nil })
        try XCTUnwrap(picker.testingDeleteButtons.first).performClick(nil)
        XCTAssertEqual(store.workspaces(in: windowID).map(\.id), [secondID])
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), secondID)
        XCTAssertFalse(picker.isVisible)
        selector.testingShowPicker()
        XCTAssertEqual(picker.testingDeleteButtons.count, 1)
        XCTAssertTrue(picker.testingDeleteButtons.allSatisfy(\.isHidden))
    }

    func testWorkspaceDeletionHonorsSaveDiscardAndCancel() throws {
        _ = NSApplication.shared
        for response in [NSApplication.ModalResponse.alertSecondButtonReturn, .alertThirdButtonReturn, .alertFirstButtonReturn] {
            let store = makeIsolatedDocumentStore()
            let windowID = store.defaultWindowID
            let workspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
            let url = try TestPDFFixtures.makeBlankPDF(named: "workspace-delete-prompt")
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let session = try store.open(documentAt: url)
            let page = try XCTUnwrap(store.pdfDocument(for: session.id).page(at: 0))
            let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 60, height: 18), forType: .highlight, withProperties: nil)
            page.addAnnotation(annotation)
            store.noteHighlightsAdded([.init(pageIndex: 0, annotation: annotation)], for: session.id)
            _ = store.createWorkspace(name: "Keep", in: windowID)
            let controller = MainWindowController(documentStore: store)
            defer { controller.close() }
            // Answer the native modal from its event loop, exercising the actual save decision path.
            DispatchQueue.main.async { NSApp.stopModal(withCode: response) }
            let deleted = controller.requestDeleteWorkspace(workspaceID)
            let cancelled = response == .alertSecondButtonReturn
            XCTAssertEqual(deleted, !cancelled)
            XCTAssertEqual(store.workspaces(in: windowID).contains { $0.id == workspaceID }, cancelled)
            if cancelled { XCTAssertTrue(store.session(for: session.id)?.isDirty == true) }
            let savedPage = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
            XCTAssertEqual(savedPage.annotations.count, response == .alertFirstButtonReturn ? 1 : 0)
        }
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
        let id = try XCTUnwrap(store.createWorkspace(name: "Research", icon: .leaf, in: store.defaultWindowID))
        let footer = WorkspaceSelectorView(documentStore: store, windowID: store.defaultWindowID, style: .sidebarFooter)
        let window = host(footer, size: NSSize(width: 320, height: 240))
        defer { window.close() }
        footer.testingShowPicker()
        let picker = footer.testingPicker
        picker.beginRenaming(id)
        let field = try XCTUnwrap(picker.activeNameField)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("Unsaved space name", replacementRange: editor.selectedRange())
        picker.showIcons(for: id)
        for light in LightTheme.allCases {
            window.appearance = NSAppearance(named: .aqua)
            ThemeManager.shared.apply(light: light, dark: .rosePineMoon)
            footer.refreshChromeColors()
            checkTheme(footer: footer, field: field, editor: editor)
            if light == .rosePineDawn { try savePreview(picker, name: "light-edit") }
        }
        for dark in DarkTheme.allCases {
            window.appearance = NSAppearance(named: .darkAqua)
            ThemeManager.shared.apply(light: .normal, dark: dark)
            footer.refreshChromeColors()
            checkTheme(footer: footer, field: field, editor: editor)
            if dark == .rosePineMoon { try savePreview(picker, name: "dark-edit") }
        }
        let background = ThemeBackgroundOverrides(window: try XCTUnwrap(ThemeHexColor(hex: "#102035")))
        ThemeManager.shared.apply(light: .normal, dark: .normal, lightBackground: background, darkBackground: background)
        footer.refreshChromeColors()
        checkTheme(footer: footer, field: field, editor: editor)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "Unsaved space name")
        picker.finishEditing(commit: false)
    }

    private func checkTheme(footer: WorkspaceSelectorView, field: NSTextField, editor: NSTextView) {
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(field.textColor?.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.textColor?.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.insertionPointColor.usingColorSpace(.sRGB), NightModeStyle.primaryTextColor.usingColorSpace(.sRGB))
            XCTAssertEqual(editor.backgroundColor.usingColorSpace(.sRGB), NightModeStyle.readerBackdropColor.usingColorSpace(.sRGB))
            for button in footer.testingPicker.testingIconChoices {
                XCTAssertEqual(button.contentTintColor?.usingColorSpace(.sRGB), NightModeStyle.secondaryTextColor.usingColorSpace(.sRGB))
            }
            for button in footer.testingPicker.testingDeleteButtons {
                XCTAssertEqual(button.contentTintColor?.usingColorSpace(.sRGB), NightModeStyle.secondaryTextColor.usingColorSpace(.sRGB))
            }
        }
        XCTAssertNil(footer.window?.attachedSheet)
    }

    private func savePreview(_ picker: SpacePickerController, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SEREIN_SPACE_PREVIEW"],
              let view = picker.testingPanel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        picker.testingPanel.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("space-\(name).png"))
    }

    private func rightClick(_ button: NSButton) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: button.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        button.rightMouseDown(with: event)
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
