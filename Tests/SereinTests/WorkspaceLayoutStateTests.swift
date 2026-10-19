import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class WorkspaceLayoutStateTests: XCTestCase {
    func testSpaceIconsPersistPerSpaceAndWindow() throws {
        let suite = "SereinTests.SpaceIcons.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makePersistedStore(defaults: defaults)
        let windowID = store.defaultWindowID
        let first = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let second = try XCTUnwrap(store.createWorkspace(name: "Research", icon: .leaf, in: windowID))
        let otherWindow = store.createWindow()
        store.setWorkspaceIcon(.books, for: first, in: windowID)
        store.setWorkspaceIcon(.star, for: second, in: otherWindow)
        XCTAssertEqual(store.workspaces(in: windowID).map(\.icon), [.books, .leaf])
        XCTAssertNil(store.workspaces(in: otherWindow).first?.icon)
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.workspaces(in: windowID).map(\.icon), [.books, .leaf])
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), second)
        restored.setWorkspaceIcon(nil, for: first, in: windowID)
        restored.flushPersistence()
        let withoutIcon = makePersistedStore(defaults: defaults)
        try withoutIcon.restorePersistedState()
        XCTAssertEqual(withoutIcon.workspaces(in: windowID).map(\.icon), [nil, .leaf])
    }

    func testSavedSpaceWithoutIconStillDecodesAndPaletteSymbolsExist() throws {
        var space = NamedWorkspace(name: "Research")
        space.icon = .books
        space.sessionIDs = [UUID()]
        let data = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "icon")
        let decoded = try JSONDecoder().decode(NamedWorkspace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.icon)
        XCTAssertEqual(decoded.id, space.id)
        XCTAssertEqual(decoded.sessionIDs, space.sessionIDs)
        for icon in SpaceIcon.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: nil), icon.rawValue)
        }
    }

    func testDeleteWorkspaceRemovesSplitSessionsAndMRUAndPersistsAdjacentSelection() throws {
        let suiteName = "SereinTests.WorkspaceDeletion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makePersistedStore(defaults: defaults)
        let windowID = store.defaultWindowID
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let kept = try store.open(documentAt: makePDF("workspace-delete-kept", pageCount: 8))
        let keptPosition = ReadingPosition(pageIndex: 3, point: CGPoint(x: 21, y: 72))
        setReadingState(keptPosition, scale: 1.6, sessionID: kept.id, in: store)
        let removedID = try XCTUnwrap(store.createWorkspace(name: "Remove", in: windowID))
        _ = try store.open(documentAt: makePDF("workspace-delete-removed", pageCount: 8))
        _ = try makeFourPaneLayout(in: store, windowID: windowID)
        let removedSessionIDs = try XCTUnwrap(store.workspaces(in: windowID).first { $0.id == removedID }).referencedSessionIDs
        let nextID = try XCTUnwrap(store.createWorkspace(name: "Next", in: windowID))
        store.activateWorkspace(removedID, in: windowID)
        store.updateSearch(query: "removed", scope: .allOpen, in: windowID)

        XCTAssertTrue(store.deleteWorkspace(removedID, in: windowID))
        XCTAssertEqual(store.workspaces(in: windowID).map(\.id), [firstID, nextID])
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), nextID)
        XCTAssertTrue(store.sessions(in: windowID).isEmpty)
        XCTAssertTrue(removedSessionIDs.allSatisfy { store.session(for: $0) == nil })
        XCTAssertFalse(store.recentDocumentEntries(in: windowID).contains { $0.workspaceID == removedID })
        XCTAssertEqual(store.searchSnapshot(in: windowID).query, "")
        XCTAssertTrue(store.deleteWorkspace(nextID, in: windowID))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), firstID)
        XCTAssertEqual(store.activeSession(in: windowID)?.lastReadPosition, keptPosition)
        XCTAssertEqual(store.activeSession(in: windowID)?.zoomScale, 1.6)
        XCTAssertFalse(store.deleteWorkspace(firstID, in: windowID))
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.workspaces(in: windowID).map(\.id), [firstID])
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), firstID)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [kept.id])
        XCTAssertTrue(removedSessionIDs.allSatisfy { restored.session(for: $0) == nil })
    }

    func testDeletingInactiveWorkspacePreservesActiveLayoutAndOtherWindows() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let removed = store.newBlankTab(in: windowID)
        let activeID = try XCTUnwrap(store.createWorkspace(name: "Active", in: windowID))
        _ = try store.open(documentAt: makePDF("workspace-delete-active", pageCount: 8))
        _ = try makeFourPaneLayout(in: store, windowID: windowID)
        let activeWorkspace = try XCTUnwrap(store.windowWorkspace(for: windowID)).activeWorkspace
        let otherWindowID = store.createWindow()
        let otherWindow = store.windowWorkspace(for: otherWindowID)

        XCTAssertFalse(store.deleteWorkspace(firstID, in: otherWindowID))
        XCTAssertFalse(store.deleteWorkspace(UUID(), in: windowID))
        XCTAssertTrue(store.deleteWorkspace(firstID, in: windowID))
        XCTAssertNil(store.session(for: removed.id))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), activeID)
        XCTAssertEqual(store.windowWorkspace(for: windowID)?.activeWorkspace, activeWorkspace)
        XCTAssertEqual(store.windowWorkspace(for: otherWindowID), otherWindow)
    }

    func testDeletionDirtyChecksRespectSharedDocumentsAcrossWorkspacesAndClosedWindows() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let sourceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let source = try store.open(documentAt: makePDF("workspace-delete-dirty"))
        _ = try makeFourPaneLayout(in: store, windowID: windowID)
        try addUnsavedHighlight(to: source.id, in: store)
        XCTAssertEqual(store.exclusiveDirtySessions(inWorkspace: sourceID, in: windowID).map(\.id), [source.id])
        let sharedID = try XCTUnwrap(store.createWorkspace(name: "Shared", in: windowID))
        let shared = try store.open(documentAt: source.url, in: windowID)
        XCTAssertTrue(store.exclusiveDirtySessions(inWorkspace: sourceID, in: windowID).isEmpty)
        XCTAssertTrue(store.deleteWorkspace(sourceID, in: windowID))
        XCTAssertTrue(store.session(for: shared.id)?.isDirty == true)
        XCTAssertTrue(try store.pdfDocument(for: shared.id).page(at: 0)?.annotations.isEmpty == false)
        XCTAssertEqual(store.exclusiveDirtySessions(inWorkspace: sharedID, in: windowID).map(\.id), [source.id])

        let otherWindowID = store.createWindow()
        _ = try store.open(documentAt: source.url, in: otherWindowID)
        XCTAssertTrue(store.exclusiveDirtySessions(inWorkspace: sharedID, in: windowID).isEmpty)
        store.closeWindow(id: otherWindowID)
        XCTAssertEqual(store.exclusiveDirtySessions(inWorkspace: sharedID, in: windowID).map(\.id), [source.id])
    }

    func testWorkspaceNavigationIncludesEmptyWorkspacesAndPreservesSavedOrderAndReadingState() throws {
        let suiteName = "SereinTests.WorkspaceNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makePersistedStore(defaults: defaults)
        let windowID = store.defaultWindowID
        let firstID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        XCTAssertFalse(store.activateAdjacentWorkspace(direction: 1, in: windowID))
        XCTAssertFalse(store.activateWorkspace(at: 0, in: windowID))
        _ = try store.open(documentAt: makePDF("workspace-navigation", pageCount: 8))
        let clonePane = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
        let cloneID = try XCTUnwrap(store.displayedSessionID(for: clonePane, in: windowID))
        let position = ReadingPosition(pageIndex: 5, point: CGPoint(x: 17, y: 103))
        setReadingState(position, scale: 1.8, sessionID: cloneID, in: store)
        let layout = try XCTUnwrap(store.readerLayout(in: windowID))
        var orderedIDs = [firstID]
        for index in 2...9 {
            orderedIDs.append(try XCTUnwrap(store.createWorkspace(name: "Space \(index)", in: windowID)))
        }
        let otherWindowID = store.createWindow()
        let otherActiveID = store.activeWorkspaceID(in: otherWindowID)

        XCTAssertTrue(store.activateAdjacentWorkspace(direction: 1, in: windowID))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), firstID)
        XCTAssertEqual(store.readerLayout(in: windowID), layout)
        XCTAssertEqual(store.focusedPane(in: windowID), clonePane)
        XCTAssertEqual(store.activeSession(in: windowID)?.lastReadPosition, position)
        XCTAssertEqual(store.activeSession(in: windowID)?.zoomScale, 1.8)
        XCTAssertTrue(store.activateAdjacentWorkspace(direction: -1, in: windowID))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), orderedIDs[8])
        XCTAssertTrue(store.sessions(in: windowID).isEmpty)
        XCTAssertFalse(store.activateAdjacentWorkspace(direction: 0, in: windowID))
        XCTAssertFalse(store.activateAdjacentWorkspace(direction: 2, in: windowID))
        XCTAssertFalse(store.activateWorkspace(at: 10, in: windowID))
        for index in 1...8 {
            XCTAssertTrue(store.activateWorkspace(at: index, in: windowID))
            XCTAssertEqual(store.activeWorkspaceID(in: windowID), orderedIDs[index - 1])
        }
        XCTAssertFalse(store.activateWorkspace(at: 8, in: windowID))
        XCTAssertEqual(store.activeWorkspaceID(in: otherWindowID), otherActiveID)
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.workspaces(in: windowID).map(\.id), orderedIDs)
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), orderedIDs[7])
        XCTAssertTrue(restored.activateWorkspace(at: 1, in: windowID))
        XCTAssertEqual(restored.readerLayout(in: windowID), layout)
        XCTAssertEqual(restored.focusedPane(in: windowID), clonePane)
        XCTAssertEqual(restored.activeSession(in: windowID)?.lastReadPosition, position)
        XCTAssertEqual(restored.activeSession(in: windowID)?.zoomScale, 1.8)
    }

    func testClosedWindowsKeepCloseOrderAcrossRestartAndReclosing() throws {
        let suiteName = "SereinTests.WindowCloseOrder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makePersistedStore(defaults: defaults)
        let keeper = store.defaultWindowID
        let first = store.createWindow()
        let second = store.createWindow()
        store.closeWindow(id: second)
        store.closeWindow(id: first)
        store.closeWindow(id: second) // Repeated close notifications must not change recency.
        XCTAssertEqual(store.closedWindowWorkspaces().map(\.id), [second, first])
        XCTAssertEqual(store.windowIDs(), [keeper])
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.closedWindowWorkspaces().map(\.id), [second, first])
        restored.reopenWindow(id: second)
        restored.closeWindow(id: second)
        XCTAssertEqual(restored.closedWindowWorkspaces().map(\.id), [first, second])
        restored.flushPersistence()
    }

    func testPaletteSplitsUseSurvivingComparisonReadingState() throws {
        for useURL in [false, true] {
            let store = makeIsolatedDocumentStore()
            let windowID = store.defaultWindowID
            let source = try store.open(documentAt: makePDF("palette-source-\(useURL)", pageCount: 8))
            let clonePane = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
            let cloneID = try XCTUnwrap(store.displayedSessionID(for: clonePane, in: windowID))
            let position = ReadingPosition(pageIndex: 5, point: CGPoint(x: 19, y: 110))
            setReadingState(position, scale: 1.7, sessionID: cloneID, in: store)
            store.setHorizontalPanLocked(true, for: cloneID)
            XCTAssertTrue(store.closePane(.primary, in: windowID))
            _ = try store.open(documentAt: makePDF("palette-target-\(useURL)"))
            let targetPane = store.focusedPane(in: windowID)
            let added: ReaderPane?
            if useURL {
                added = try store.splitPane(from: targetPane, layout: .stacked, documentAt: source.url, in: windowID)
            } else {
                added = store.splitPane(from: targetPane, layout: .stacked, sessionID: source.id, in: windowID)
            }
            let addedID = try XCTUnwrap(store.displayedSessionID(for: XCTUnwrap(added), in: windowID))
            let reading = try XCTUnwrap(store.session(for: addedID))
            XCTAssertEqual(reading.lastReadPosition, position)
            XCTAssertEqual(reading.zoomScale, 1.7)
            XCTAssertEqual(reading.scaleMode, .manual)
            XCTAssertTrue(reading.isHorizontalPanLocked)
            XCTAssertEqual(store.session(for: cloneID)?.lastReadPosition, position)
            XCTAssertEqual(store.session(for: source.id)?.currentPageIndex, 0)
        }
    }

    func testSplitFromAnotherWorkspaceUsesItsFocusedCopyAndHonorsExplicitDestination() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("palette-workspace-source", pageCount: 8))
        let clonePane = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
        let cloneID = try XCTUnwrap(store.displayedSessionID(for: clonePane, in: windowID))
        let position = ReadingPosition(pageIndex: 6, point: CGPoint(x: 30, y: 90))
        setReadingState(position, scale: 2.1, sessionID: cloneID, in: store)
        _ = try XCTUnwrap(store.createWorkspace(name: "Target", in: windowID))
        _ = try store.open(documentAt: makePDF("palette-workspace-target"))
        let pane = try XCTUnwrap(store.splitPane(from: .primary, layout: .stacked, sessionID: source.id, in: windowID))
        let targetID = try XCTUnwrap(store.displayedSessionID(for: pane, in: windowID))
        XCTAssertEqual(store.session(for: targetID)?.lastReadPosition, position)
        XCTAssertEqual(store.session(for: targetID)?.zoomScale, 2.1)

        let destination = ReadingPosition(pageIndex: 3, point: CGPoint(x: 10, y: 200))
        let explicitPane = try XCTUnwrap(store.splitPane(from: pane, layout: .sideBySide,
            sessionID: source.id, readingPosition: destination, in: windowID))
        let explicitID = try XCTUnwrap(store.displayedSessionID(for: explicitPane, in: windowID))
        XCTAssertEqual(store.session(for: explicitID)?.lastReadPosition, destination)
        XCTAssertEqual(store.session(for: explicitID)?.zoomScale, source.zoomScale)
    }

    func testSwitchingNamedWorkspacesPreservesSeparateTabsAndSelection() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstWorkspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let first = try store.open(documentAt: makePDF("workspace-first"), in: windowID)
        let second = try store.open(documentAt: makePDF("workspace-second"), in: windowID)
        store.activate(sessionID: first.id, in: windowID)

        let researchID = try XCTUnwrap(store.createWorkspace(name: "Research", in: windowID))
        store.activateWorkspace(researchID, in: windowID)
        XCTAssertTrue(store.sessions(in: windowID).isEmpty)
        XCTAssertNil(store.activeSessionID(in: windowID))
        let third = try store.open(documentAt: makePDF("workspace-third"), in: windowID)
        store.renameWorkspace(researchID, name: "References", in: windowID)

        store.activateWorkspace(firstWorkspaceID, in: windowID)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [first.id, second.id])
        XCTAssertEqual(store.activeSessionID(in: windowID), first.id)

        store.activateWorkspace(researchID, in: windowID)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [third.id])
        XCTAssertEqual(store.activeSessionID(in: windowID), third.id)
        XCTAssertEqual(store.workspaces(in: windowID).first { $0.id == researchID }?.name, "References")
        XCTAssertEqual(store.workspaces(in: windowID).count, 2)
    }

    func testRangeSelectionAnchorRemainsIndependentAcrossWorkspaces() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let originalID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let first = try (0..<4).map { try store.open(documentAt: makePDF("workspace-anchor-first-\($0)")) }
        store.activateTab(sessionID: first[0].id, in: windowID)
        store.selectSessionRange(through: first[1].id, in: windowID)
        let otherID = try XCTUnwrap(store.createWorkspace(name: "Other", in: windowID))
        let second = try (0..<4).map { try store.open(documentAt: makePDF("workspace-anchor-second-\($0)")) }
        store.activateTab(sessionID: second[3].id, in: windowID)
        store.selectSessionRange(through: second[2].id, in: windowID)

        store.activateWorkspace(originalID, in: windowID)
        store.selectSessionRange(through: first[3].id, in: windowID)
        XCTAssertEqual(store.selectedSessionIDsInWindowOrder(in: windowID), first.map(\.id))
        store.activateWorkspace(otherID, in: windowID)
        store.selectSessionRange(through: second[0].id, in: windowID)
        XCTAssertEqual(store.selectedSessionIDsInWindowOrder(in: windowID), second.map(\.id))
    }

    func testMovingComparisonToWorkspacePreservesItsReadingState() throws {
        for moveExplicitClone in [false, true] {
            let store = makeIsolatedDocumentStore()
            let windowID = store.defaultWindowID
            let originalID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
            let source = try store.open(documentAt: makePDF("move-workspace-comparison-\(moveExplicitClone)", pageCount: 8))
            let clonePane = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
            let cloneID = try XCTUnwrap(store.displayedSessionID(for: clonePane, in: windowID))
            let position = ReadingPosition(pageIndex: 5, point: CGPoint(x: 17, y: 81))
            setReadingState(position, scale: 2.2, sessionID: cloneID, in: store)
            store.setHorizontalPanLocked(true, for: cloneID)
            let destinationID = try XCTUnwrap(store.createWorkspace(name: "Destination", in: windowID))
            let destinationPDF = try store.open(documentAt: makePDF("move-workspace-existing-\(moveExplicitClone)"))
            let destinationLayout = try XCTUnwrap(store.readerLayout(in: windowID))
            store.activateWorkspace(originalID, in: windowID)

            XCTAssertTrue(store.moveSession(moveExplicitClone ? cloneID : source.id, toWorkspace: destinationID, in: windowID))
            XCTAssertTrue(store.sessions(in: windowID).isEmpty)
            XCTAssertNil(store.session(for: cloneID))
            store.activateWorkspace(destinationID, in: windowID)
            XCTAssertEqual(store.sessions(in: windowID).map(\.id), [destinationPDF.id, source.id])
            XCTAssertEqual(store.readerLayout(in: windowID), destinationLayout)
            store.activateTab(sessionID: source.id, in: windowID)
            let moved = try XCTUnwrap(store.activeSession(in: windowID))
            XCTAssertEqual(moved.lastReadPosition, position)
            XCTAssertEqual(moved.currentPageIndex, 5)
            XCTAssertEqual(moved.zoomScale, 2.2)
            XCTAssertEqual(moved.scaleMode, .manual)
            XCTAssertTrue(moved.isHorizontalPanLocked)
        }
    }

    func testSamePDFAcrossWorkspacesHasIndependentReadingStateAndSharedAnnotations() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let firstWorkspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let url = try makePDF("workspace-shared", pageCount: 8)
        let first = try store.open(documentAt: url, in: windowID)
        let firstPosition = ReadingPosition(pageIndex: 2, point: CGPoint(x: 17, y: 41))
        setReadingState(firstPosition, scale: 1.25, sessionID: first.id, in: store)

        let secondWorkspaceID = try XCTUnwrap(store.createWorkspace(name: "Compare", in: windowID))
        store.activateWorkspace(secondWorkspaceID, in: windowID)
        let second = try store.open(documentAt: url, in: windowID)
        let secondPosition = ReadingPosition(pageIndex: 6, point: CGPoint(x: 29, y: 73))
        setReadingState(secondPosition, scale: 2.0, sessionID: second.id, in: store)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.open(documentAt: url, in: windowID).id, second.id)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [second.id])
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition, firstPosition)
        XCTAssertEqual(store.session(for: first.id)?.zoomScale, 1.25)
        XCTAssertEqual(store.session(for: second.id)?.lastReadPosition, secondPosition)
        XCTAssertEqual(store.session(for: second.id)?.zoomScale, 2.0)

        let firstDocument = try store.pdfDocument(for: first.id)
        let secondDocument = try store.pdfDocument(for: second.id)
        XCTAssertTrue(firstDocument === secondDocument)
        let page = try XCTUnwrap(secondDocument.page(at: 0))
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 60, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        annotation.color = .systemPink
        page.addAnnotation(annotation)
        store.noteHighlightsAdded([.init(pageIndex: 0, annotation: annotation)], for: second.id)

        XCTAssertTrue(store.session(for: first.id)?.isDirty == true)
        XCTAssertTrue(store.session(for: second.id)?.isDirty == true)
        XCTAssertTrue(store.hasUndoableHighlight(for: first.id))
        XCTAssertTrue(store.undoLastHighlight(for: first.id))
        XCTAssertTrue(page.annotations.isEmpty)
        XCTAssertTrue(store.hasRedoableHighlight(for: second.id))

        store.activateWorkspace(firstWorkspaceID, in: windowID)
        XCTAssertEqual(store.activeSessionID(in: windowID), first.id)
        XCTAssertEqual(store.session(for: first.id)?.lastReadPosition, firstPosition)
        XCTAssertEqual(store.session(for: second.id)?.lastReadPosition, secondPosition)
    }

    func testSplitCopiesSourceReadingStateAndAcceptsExplicitDestination() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("split-position", pageCount: 8))
        let sourcePosition = ReadingPosition(pageIndex: 2, point: CGPoint(x: 11, y: 67))
        setReadingState(sourcePosition, scale: 1.75, sessionID: source.id, in: store)
        store.setDisplayMode(.twoUpContinuous, for: source.id)

        let copiedPane = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
        let copiedID = try XCTUnwrap(store.displayedSessionID(for: copiedPane, in: windowID))
        XCTAssertNotEqual(copiedID, source.id)
        XCTAssertEqual(store.session(for: copiedID)?.lastReadPosition, sourcePosition)
        XCTAssertEqual(store.session(for: copiedID)?.zoomScale, 1.75)
        XCTAssertEqual(store.session(for: copiedID)?.scaleMode, .manual)
        XCTAssertEqual(store.session(for: copiedID)?.displayMode, .twoUpContinuous)

        let destination = ReadingPosition(pageIndex: 6, point: CGPoint(x: 31, y: 59))
        let targetPane = try XCTUnwrap(store.splitPane(
            from: copiedPane,
            layout: .stacked,
            readingPosition: destination,
            in: windowID
        ))
        let targetID = try XCTUnwrap(store.displayedSessionID(for: targetPane, in: windowID))
        XCTAssertEqual(Set([source.id, copiedID, targetID]).count, 3)
        XCTAssertEqual(store.session(for: targetID)?.lastReadPosition, destination)
        XCTAssertEqual(store.session(for: copiedID)?.lastReadPosition, sourcePosition)
        XCTAssertEqual(store.focusedPane(in: windowID), targetPane)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [source.id])
        XCTAssertTrue(try store.pdfDocument(for: targetID) === store.pdfDocument(for: source.id))
    }

    func testFourPaneMixedLayoutPreservesRatiosAndSiblingsWhenClosingFocusedPane() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        _ = try store.open(documentAt: makePDF("mixed-four-panes", pageCount: 8))
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        let originalLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        guard case let .split(rootID, rootDirection, _, left, right) = originalLayout,
              case let .split(leftID, leftDirection, _, leftFirst, leftSecond) = left,
              case let .split(rightID, rightDirection, _, rightFirst, rightSecond) = right else {
            return XCTFail("Splitting each side must keep two nested branches.")
        }
        XCTAssertEqual(rootDirection, .sideBySide)
        XCTAssertEqual(leftDirection, .stacked)
        XCTAssertEqual(rightDirection, .stacked)
        XCTAssertEqual(leftFirst, .pane(.primary))
        XCTAssertEqual(leftSecond, .pane(panes.leftBottom))
        XCTAssertEqual(rightFirst, .pane(panes.rightTop))
        XCTAssertEqual(rightSecond, .pane(panes.rightBottom))
        XCTAssertEqual(Set(store.readerPanes(in: windowID).compactMap(\.sessionID)).count, 4)

        store.updateSplitRatio(0.4, splitID: rootID, in: windowID)
        store.updateSplitRatio(0.3, splitID: leftID, in: windowID)
        store.updateSplitRatio(0.65, splitID: rightID, in: windowID)
        let preservedLeft = ReaderLayoutNode.split(
            id: leftID, layout: .stacked, ratio: 0.3, first: leftFirst, second: leftSecond
        )
        let expectedLayout = ReaderLayoutNode.split(
            id: rootID,
            layout: .sideBySide,
            ratio: 0.4,
            first: preservedLeft,
            second: .split(id: rightID, layout: .stacked, ratio: 0.65, first: rightFirst, second: rightSecond)
        )
        XCTAssertEqual(store.readerLayout(in: windowID), expectedLayout)

        let survivingIDs = Dictionary(uniqueKeysWithValues: store.readerPanes(in: windowID)
            .filter { $0.id != panes.rightBottom }
            .map { ($0.id, $0.sessionID) })
        store.setFocusedPane(panes.rightBottom, in: windowID)
        store.togglePaneZoom(in: windowID)
        XCTAssertEqual(store.zoomedPane(in: windowID), panes.rightBottom)
        XCTAssertEqual(store.readerLayout(in: windowID), expectedLayout)
        store.togglePaneZoom(in: windowID)
        XCTAssertNil(store.zoomedPane(in: windowID))
        XCTAssertEqual(store.readerLayout(in: windowID), expectedLayout)

        XCTAssertTrue(store.closePane(panes.rightBottom, in: windowID))
        XCTAssertEqual(store.readerLayout(in: windowID), .split(
            id: rootID, layout: .sideBySide, ratio: 0.4, first: preservedLeft, second: rightFirst
        ))
        XCTAssertEqual(Set(store.readerPanes(in: windowID).map(\.id)), Set(survivingIDs.keys))
        XCTAssertTrue(store.readerPanes(in: windowID).contains { $0.id == store.focusedPane(in: windowID) })
        for (pane, sessionID) in survivingIDs {
            XCTAssertEqual(store.displayedSessionID(for: pane, in: windowID), sessionID)
        }

        XCTAssertTrue(store.closePane(panes.leftBottom, in: windowID))
        XCTAssertTrue(store.closePane(panes.rightTop, in: windowID))
        XCTAssertEqual(store.readerLayout(in: windowID), .pane(.primary))
        XCTAssertFalse(store.closePane(.primary, in: windowID))
        XCTAssertEqual(store.readerPanes(in: windowID).count, 1)
    }

    func testPlainTabActivationLeavesAndRestoresEntireLayoutGroup() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let grouped = try store.open(documentAt: makePDF("grouped-document", pageCount: 8))
        _ = try makeFourPaneLayout(in: store, windowID: windowID)
        let groupedLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        let groupedSessions = store.readerPanes(in: windowID).compactMap(\.sessionID)

        let other = try store.open(documentAt: makePDF("outside-group"), in: windowID)
        store.activate(sessionID: other.id, in: windowID)
        XCTAssertEqual(store.readerPanes(in: windowID).compactMap(\.sessionID), [other.id])
        XCTAssertFalse(store.isSplitEnabled(in: windowID))

        store.activate(sessionID: grouped.id, in: windowID)
        XCTAssertEqual(store.readerLayout(in: windowID), groupedLayout)
        XCTAssertEqual(store.readerPanes(in: windowID).compactMap(\.sessionID), groupedSessions)
        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [grouped.id, other.id])
    }

    func testRestartRestoresAllPanePositionsAndHiddenWorkspaceForSamePDF() throws {
        let suiteName = "SereinTests.WorkspaceLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makePersistedStore(defaults: defaults)
        let windowID = store.defaultWindowID
        let firstWorkspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let url = try makePDF("persisted-shared-panes", pageCount: 12)
        let source = try store.open(documentAt: url, in: windowID)
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        let paneSessionIDs = store.readerPanes(in: windowID).compactMap(\.sessionID)
        let originalLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        guard case let .split(splitID, _, _, _, _) = originalLayout else {
            return XCTFail("Expected a split layout.")
        }
        store.updateSplitRatio(0.37, splitID: splitID, in: windowID)
        store.setFocusedPane(panes.rightBottom, in: windowID)
        let expectedLayout = try XCTUnwrap(store.readerLayout(in: windowID))

        for (index, sessionID) in paneSessionIDs.enumerated() {
            setReadingState(
                ReadingPosition(pageIndex: index + 1, point: CGPoint(x: 10 + index, y: 90 - index)),
                scale: 1 + CGFloat(index) / 4,
                sessionID: sessionID,
                in: store
            )
        }
        let expectedSessions = try paneSessionIDs.map { try XCTUnwrap(store.session(for: $0)) }
        let hiddenWorkspaceID = try XCTUnwrap(store.createWorkspace(name: "Second reading", in: windowID))
        store.activateWorkspace(hiddenWorkspaceID, in: windowID)
        let independent = try store.open(documentAt: url, in: windowID)
        let independentPosition = ReadingPosition(pageIndex: 10, point: CGPoint(x: 53, y: 107))
        setReadingState(independentPosition, scale: 2.5, sessionID: independent.id, in: store)
        store.activateWorkspace(firstWorkspaceID, in: windowID)
        store.togglePaneZoom(in: windowID)
        XCTAssertEqual(store.zoomedPane(in: windowID), panes.rightBottom)
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), firstWorkspaceID)
        XCTAssertEqual(restored.readerLayout(in: windowID), expectedLayout)
        XCTAssertEqual(restored.focusedPane(in: windowID), panes.rightBottom)
        XCTAssertNil(restored.zoomedPane(in: windowID))
        XCTAssertEqual(restored.readerPanes(in: windowID).compactMap(\.sessionID), paneSessionIDs)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [source.id])
        for expected in expectedSessions {
            let actual = try XCTUnwrap(restored.session(for: expected.id))
            XCTAssertEqual(actual.lastReadPosition, expected.lastReadPosition)
            XCTAssertEqual(actual.zoomScale, expected.zoomScale)
            XCTAssertEqual(actual.scaleMode, expected.scaleMode)
        }

        restored.activateWorkspace(hiddenWorkspaceID, in: windowID)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [independent.id])
        XCTAssertEqual(restored.session(for: independent.id)?.lastReadPosition, independentPosition)
        XCTAssertEqual(restored.session(for: independent.id)?.zoomScale, 2.5)
        XCTAssertTrue(try restored.pdfDocument(for: independent.id) === restored.pdfDocument(for: source.id))
        restored.flushPersistence()
    }

    func testClosingWindowPreservesNamedWorkspacesAndLayoutForReopeningAfterRestart() throws {
        let suiteName = "SereinTests.ClosedWorkspace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makePersistedStore(defaults: defaults)
        let keeperWindowID = store.defaultWindowID
        let keeper = try store.open(documentAt: makePDF("keeper-window"), in: keeperWindowID)
        let windowID = store.createWindow(copyingFrom: keeperWindowID)
        let firstWorkspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let first = try store.open(documentAt: makePDF("closed-window-first"), in: windowID)
        let secondWorkspaceID = try XCTUnwrap(store.createWorkspace(name: "Retained", in: windowID))
        store.activateWorkspace(secondWorkspaceID, in: windowID)
        let second = try store.open(documentAt: makePDF("closed-window-second", pageCount: 8), in: windowID)
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        store.setFocusedPane(panes.rightBottom, in: windowID)
        let layout = try XCTUnwrap(store.readerLayout(in: windowID))
        let paneSessionIDs = store.readerPanes(in: windowID).compactMap(\.sessionID)

        store.closeWindow(id: windowID)
        XCTAssertEqual(store.windowIDs(), [keeperWindowID])
        XCTAssertTrue(store.closedWindowWorkspaces().contains { $0.id == windowID })
        XCTAssertNotNil(store.session(for: first.id))
        XCTAssertNotNil(store.session(for: second.id))
        XCTAssertEqual(store.sessions(in: keeperWindowID).map(\.id), [keeper.id])
        store.flushPersistence()

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertFalse(restored.windowIDs().contains(windowID))
        XCTAssertTrue(restored.closedWindowWorkspaces().contains { $0.id == windowID })
        restored.reopenWindow(id: windowID)
        XCTAssertEqual(Set(restored.windowIDs()), [keeperWindowID, windowID])
        XCTAssertFalse(restored.closedWindowWorkspaces().contains { $0.id == windowID })
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), secondWorkspaceID)
        XCTAssertEqual(restored.readerLayout(in: windowID), layout)
        XCTAssertEqual(restored.readerPanes(in: windowID).compactMap(\.sessionID), paneSessionIDs)
        XCTAssertEqual(restored.focusedPane(in: windowID), panes.rightBottom)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [second.id])
        restored.activateWorkspace(firstWorkspaceID, in: windowID)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [first.id])
        restored.flushPersistence()
    }

    func testMovingPDFToWorkspaceRemovesOnlyItsPanesAndPreservesOtherGroups() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let sourceWorkspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let retained = try store.open(documentAt: makePDF("move-retained", pageCount: 8))
        _ = try makeFourPaneLayout(in: store, windowID: windowID)
        let retainedLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        let retainedPaneSessions = store.readerPanes(in: windowID).compactMap(\.sessionID)

        let moved = try store.open(documentAt: makePDF("move-workspace", pageCount: 8))
        let movedPosition = ReadingPosition(pageIndex: 5, point: CGPoint(x: 19, y: 83))
        setReadingState(movedPosition, scale: 1.8, sessionID: moved.id, in: store)
        let neighborURL = try makePDF("move-neighbor", pageCount: 8)
        let neighborPane = try XCTUnwrap(store.splitPane(
            from: .primary, layout: .sideBySide, documentAt: neighborURL, in: windowID
        ))
        let neighborID = try XCTUnwrap(store.displayedSessionID(for: neighborPane, in: windowID))
        let neighborTabID = try XCTUnwrap(store.sessions(in: windowID).first { $0.url == neighborURL }?.id)
        _ = try XCTUnwrap(store.splitPane(from: .primary, layout: .stacked, in: windowID))

        let targetWorkspaceID = try XCTUnwrap(store.createWorkspace(name: "Destination", in: windowID))
        let target = try store.open(documentAt: makePDF("move-target", pageCount: 8), in: windowID)
        _ = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
        let targetLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        store.activateWorkspace(sourceWorkspaceID, in: windowID)

        XCTAssertTrue(store.moveSession(moved.id, toWorkspace: targetWorkspaceID, in: windowID))
        XCTAssertEqual(store.activeWorkspaceID(in: windowID), sourceWorkspaceID)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [retained.id, neighborTabID])
        XCTAssertEqual(store.readerLayout(in: windowID), .pane(neighborPane))
        XCTAssertEqual(store.displayedSessionID(for: neighborPane, in: windowID), neighborID)
        store.activate(sessionID: retained.id, in: windowID)
        XCTAssertEqual(store.readerLayout(in: windowID), retainedLayout)
        XCTAssertEqual(store.readerPanes(in: windowID).compactMap(\.sessionID), retainedPaneSessions)

        store.activateWorkspace(targetWorkspaceID, in: windowID)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [target.id, moved.id])
        XCTAssertEqual(store.readerLayout(in: windowID), targetLayout)
        store.activate(sessionID: moved.id, in: windowID)
        XCTAssertEqual(store.readerPanes(in: windowID).compactMap(\.sessionID), [moved.id])
        XCTAssertEqual(store.session(for: moved.id)?.lastReadPosition, movedPosition)
        XCTAssertEqual(store.session(for: moved.id)?.zoomScale, 1.8)
    }

    func testURLSplitAddsOnlyRequestedBranchWithoutSwitchingSourceGroup() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("url-split-source", pageCount: 8))
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        let layoutBefore = try XCTUnwrap(store.readerLayout(in: windowID))
        let paneSessionsBefore = Dictionary(uniqueKeysWithValues: store.readerPanes(in: windowID)
            .map { ($0.id, $0.sessionID) })
        let targetURL = try makePDF("url-split-target", pageCount: 8)

        let addedPane = try XCTUnwrap(store.splitPane(
            from: panes.rightBottom, layout: .sideBySide, documentAt: targetURL, in: windowID
        ))
        let addedID = try XCTUnwrap(store.displayedSessionID(for: addedPane, in: windowID))
        let targetTab = try XCTUnwrap(store.sessions(in: windowID).first { $0.url == targetURL })
        let layoutAfter = try XCTUnwrap(store.readerLayout(in: windowID))
        XCTAssertEqual(layoutAfter.removing(addedPane), layoutBefore)
        XCTAssertEqual(store.readerPanes(in: windowID).count, 5)
        XCTAssertEqual(store.focusedPane(in: windowID), addedPane)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [source.id, targetTab.id])
        XCTAssertEqual(addedID, targetTab.id)
        XCTAssertFalse(paneSessionsBefore.values.contains { $0 == addedID })
        XCTAssertTrue(try store.pdfDocument(for: addedID) === store.pdfDocument(for: targetTab.id))
        for (pane, sessionID) in paneSessionsBefore {
            XCTAssertEqual(store.displayedSessionID(for: pane, in: windowID), sessionID)
        }

        let missingURL = targetURL.deletingLastPathComponent().appendingPathComponent("missing.pdf")
        XCTAssertThrowsError(try store.splitPane(
            from: addedPane, layout: .stacked, documentAt: missingURL, in: windowID
        ))
        XCTAssertEqual(store.readerLayout(in: windowID), layoutAfter)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [source.id, targetTab.id])
        let targetPosition = ReadingPosition(pageIndex: 3, point: CGPoint(x: 21, y: 84))
        setReadingState(targetPosition, scale: 1.6, sessionID: addedID, in: store)
        XCTAssertTrue(store.closePane(addedPane, in: windowID))
        XCTAssertEqual(store.readerLayout(in: windowID), layoutBefore)
        store.activateTab(sessionID: targetTab.id, in: windowID)
        XCTAssertEqual(store.activeSessionID(in: windowID), targetTab.id)
        XCTAssertEqual(store.activeSession(in: windowID)?.lastReadPosition, targetPosition)
        XCTAssertEqual(store.activeSession(in: windowID)?.zoomScale, 1.6)
    }

    func testOpeningPDFInNewWindowKeepsOriginalLayoutAndIndependentViewport() throws {
        let store = makeIsolatedDocumentStore()
        let sourceWindowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("new-window-shared", pageCount: 10))
        let panes = try makeFourPaneLayout(in: store, windowID: sourceWindowID)
        let sourceLayout = try XCTUnwrap(store.readerLayout(in: sourceWindowID))
        let focusedSessionID = try XCTUnwrap(store.displayedSessionID(for: panes.rightBottom, in: sourceWindowID))
        let sourcePosition = ReadingPosition(pageIndex: 3, point: CGPoint(x: 13, y: 97))
        setReadingState(sourcePosition, scale: 1.4, sessionID: focusedSessionID, in: store)
        store.setFocusedPane(panes.rightBottom, in: sourceWindowID)

        let destinationWindowID = store.createWindow(copyingFrom: sourceWindowID)
        let destination = try store.open(documentAt: source.url, in: destinationWindowID)
        let destinationPosition = ReadingPosition(pageIndex: 8, point: CGPoint(x: 43, y: 71))
        setReadingState(destinationPosition, scale: 2.1, sessionID: destination.id, in: store)

        XCTAssertNotEqual(destination.id, source.id)
        XCTAssertEqual(store.readerLayout(in: sourceWindowID), sourceLayout)
        XCTAssertEqual(store.focusedPane(in: sourceWindowID), panes.rightBottom)
        XCTAssertEqual(store.sessions(in: sourceWindowID).map(\.id), [source.id])
        XCTAssertEqual(store.sessions(in: destinationWindowID).map(\.id), [destination.id])
        XCTAssertEqual(store.readerPanes(in: destinationWindowID).compactMap(\.sessionID), [destination.id])
        XCTAssertEqual(store.session(for: focusedSessionID)?.lastReadPosition, sourcePosition)
        XCTAssertEqual(store.session(for: focusedSessionID)?.zoomScale, 1.4)
        XCTAssertEqual(store.session(for: destination.id)?.lastReadPosition, destinationPosition)
        XCTAssertEqual(store.session(for: destination.id)?.zoomScale, 2.1)
        XCTAssertTrue(try store.pdfDocument(for: destination.id) === store.pdfDocument(for: focusedSessionID))
        store.setDirty(true, for: destination.id)
        XCTAssertTrue(store.session(for: source.id)?.isDirty == true)
        XCTAssertTrue(store.session(for: focusedSessionID)?.isDirty == true)
    }

    func testLegacyWindowMigrationKeepsDuplicateURLSessionIDsAndSplitInSchemaTwo() throws {
        let suiteName = "SereinTests.LegacyWorkspace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = try makePDF("legacy-same-url", pageCount: 10)
        let windowID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let legacy = PersistedDocumentStoreState(
            sessions: [.init(id: firstID, url: url), .init(id: secondID, url: url)],
            windows: [.init(
                id: windowID,
                sessionIDs: [firstID, secondID],
                sessionURLs: [url, url],
                tabPresentationMode: .horizontalTitlebar,
                isLeftSidebarVisible: false,
                isRightSidebarVisible: true,
                rightSidebarMode: .outline,
                searchQuery: "",
                searchScope: .currentDocument,
                splitState: .init(
                    isEnabled: true,
                    primarySessionID: firstID,
                    secondarySessionID: secondID,
                    primarySessionURL: url,
                    secondarySessionURL: url,
                    focusedPane: .secondary
                ),
                recentlyClosedURLs: []
            )]
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: UserDefaultsDocumentStorePersistence.stateKey)
        let store = makePersistedStore(defaults: defaults)
        try store.restorePersistedState()
        XCTAssertEqual(store.workspaces(in: windowID).count, 1)
        XCTAssertEqual(store.sessions(in: windowID).map(\.id), [firstID, secondID])
        XCTAssertEqual(store.displayedSessionID(for: .primary, in: windowID), firstID)
        XCTAssertEqual(store.displayedSessionID(for: .secondary, in: windowID), secondID)
        XCTAssertEqual(store.focusedPane(in: windowID), .secondary)
        XCTAssertTrue(store.isSplitEnabled(in: windowID))
        let migratedLayout = try XCTUnwrap(store.readerLayout(in: windowID))
        let workspaceID = try XCTUnwrap(store.activeWorkspaceID(in: windowID))
        let firstPosition = ReadingPosition(pageIndex: 1, point: CGPoint(x: 11, y: 101))
        let secondPosition = ReadingPosition(pageIndex: 7, point: CGPoint(x: 37, y: 79))
        setReadingState(firstPosition, scale: 1.2, sessionID: firstID, in: store)
        setReadingState(secondPosition, scale: 1.9, sessionID: secondID, in: store)
        store.flushPersistence()

        let savedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsDocumentStorePersistence.stateKey))
        let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        XCTAssertEqual(savedJSON["schemaVersion"] as? Int, 2)
        let savedState = try JSONDecoder().decode(PersistedDocumentStoreState.self, from: savedData)
        XCTAssertEqual(Set(savedState.sessions.map(\.id)), [firstID, secondID])
        XCTAssertEqual(savedState.workspaceWindows?.first?.id, windowID)

        let restored = makePersistedStore(defaults: defaults)
        try restored.restorePersistedState()
        XCTAssertEqual(restored.activeWorkspaceID(in: windowID), workspaceID)
        XCTAssertEqual(restored.readerLayout(in: windowID), migratedLayout)
        XCTAssertEqual(restored.sessions(in: windowID).map(\.id), [firstID, secondID])
        XCTAssertEqual(restored.displayedSessionID(for: .primary, in: windowID), firstID)
        XCTAssertEqual(restored.displayedSessionID(for: .secondary, in: windowID), secondID)
        XCTAssertEqual(restored.focusedPane(in: windowID), .secondary)
        XCTAssertEqual(restored.session(for: firstID)?.lastReadPosition, firstPosition)
        XCTAssertEqual(restored.session(for: secondID)?.lastReadPosition, secondPosition)
        XCTAssertEqual(restored.session(for: firstID)?.zoomScale, 1.2)
        XCTAssertEqual(restored.session(for: secondID)?.zoomScale, 1.9)
        XCTAssertTrue(try restored.pdfDocument(for: firstID) === restored.pdfDocument(for: secondID))
        restored.setFocusedPane(.primary, in: windowID)
        restored.activateTab(sessionID: secondID, in: windowID)
        XCTAssertEqual(restored.focusedPane(in: windowID), .secondary)
        restored.flushPersistence()
    }

    func testDiscardAndClosedWindowArchivePreserveReadingStateAndDirtyOwnership() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("discard-workspace", pageCount: 10))
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        let paneSessionIDs = store.readerPanes(in: windowID).compactMap(\.sessionID)
        for (index, sessionID) in paneSessionIDs.enumerated() {
            setReadingState(
                ReadingPosition(pageIndex: index + 1, point: CGPoint(x: 13 + index, y: 83 - index)),
                scale: 1 + CGFloat(index) / 4,
                sessionID: sessionID,
                in: store
            )
        }
        store.setFocusedPane(panes.rightBottom, in: windowID)
        let layout = try XCTUnwrap(store.readerLayout(in: windowID))
        let expectedSessions = try paneSessionIDs.map { try XCTUnwrap(store.session(for: $0)) }
        let focusedID = try XCTUnwrap(store.displayedSessionID(for: panes.rightBottom, in: windowID))
        let otherWindowID = store.createWindow(copyingFrom: windowID)
        let other = try store.open(documentAt: source.url, in: otherWindowID)

        try addUnsavedHighlight(to: focusedID, in: store)
        XCTAssertTrue(store.session(for: other.id)?.isDirty == true)
        try store.discardUnsavedAnnotations(for: focusedID)
        XCTAssertTrue(try store.pdfDocument(for: focusedID).page(at: 0)?.annotations.isEmpty == true)
        XCTAssertFalse(store.hasUndoableHighlight(for: source.id))
        XCTAssertFalse(store.hasRedoableHighlight(for: other.id))
        XCTAssertTrue(store.session(for: other.id)?.isDirty == false)
        store.closeWindow(id: windowID)

        try addUnsavedHighlight(to: other.id, in: store)
        XCTAssertEqual(store.exclusiveDirtySessions(in: otherWindowID).map(\.id), [source.id])
        XCTAssertTrue(store.closedWindowWorkspaces().contains { $0.id == windowID })
        try store.discardUnsavedAnnotations(for: other.id)
        store.reopenWindow(id: windowID)

        XCTAssertEqual(store.readerLayout(in: windowID), layout)
        XCTAssertEqual(store.focusedPane(in: windowID), panes.rightBottom)
        XCTAssertEqual(store.readerPanes(in: windowID).compactMap(\.sessionID), paneSessionIDs)
        for expected in expectedSessions {
            let actual = try XCTUnwrap(store.session(for: expected.id))
            XCTAssertEqual(actual.lastReadPosition, expected.lastReadPosition)
            XCTAssertEqual(actual.zoomScale, expected.zoomScale)
            XCTAssertFalse(actual.isDirty)
            XCTAssertTrue(try store.pdfDocument(for: actual.id).page(at: 0)?.annotations.isEmpty == true)
        }
    }

    func testReturningToSamePDFLayoutRestoresPreviouslyFocusedRightPane() throws {
        let store = makeIsolatedDocumentStore()
        let windowID = store.defaultWindowID
        let source = try store.open(documentAt: makePDF("remember-group-focus", pageCount: 8))
        let panes = try makeFourPaneLayout(in: store, windowID: windowID)
        let rightSessionID = try XCTUnwrap(store.displayedSessionID(for: panes.rightBottom, in: windowID))
        let position = ReadingPosition(pageIndex: 5, point: CGPoint(x: 31, y: 67))
        setReadingState(position, scale: 1.75, sessionID: rightSessionID, in: store)
        store.setFocusedPane(panes.rightBottom, in: windowID)
        let expectedLayout = try XCTUnwrap(store.readerLayout(in: windowID))

        let other = try store.open(documentAt: makePDF("remember-group-outside"), in: windowID)
        store.activateTab(sessionID: other.id, in: windowID)
        XCTAssertEqual(store.activeSessionID(in: windowID), other.id)
        store.activateTab(sessionID: source.id, in: windowID)

        XCTAssertEqual(store.readerLayout(in: windowID), expectedLayout)
        XCTAssertEqual(store.focusedPane(in: windowID), panes.rightBottom)
        XCTAssertEqual(store.activeSessionID(in: windowID), rightSessionID)
        XCTAssertEqual(store.session(for: rightSessionID)?.lastReadPosition, position)
        XCTAssertEqual(store.session(for: rightSessionID)?.zoomScale, 1.75)
        store.activateTab(sessionID: source.id, in: windowID)
        XCTAssertEqual(store.focusedPane(in: windowID), panes.rightBottom)
    }

    private func makePDF(_ name: String, pageCount: Int = 1) throws -> URL {
        try TestPDFFixtures.makeBlankPDF(named: name, pageCount: pageCount)
    }

    private func addUnsavedHighlight(to sessionID: UUID, in store: DocumentStore) throws {
        let page = try XCTUnwrap(store.pdfDocument(for: sessionID).page(at: 0))
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 60, height: 18),
            forType: .highlight,
            withProperties: nil
        )
        annotation.color = .systemPink
        page.addAnnotation(annotation)
        store.noteHighlightsAdded([.init(pageIndex: 0, annotation: annotation)], for: sessionID)
    }

    private func makePersistedStore(defaults: UserDefaults) -> DocumentStore {
        DocumentStore(
            persistence: UserDefaultsDocumentStorePersistence(userDefaults: defaults, debounceInterval: 0),
            readingStateStore: UserDefaultsReadingStateStore(userDefaults: defaults, debounceInterval: 0),
            recentFilesStore: TestInMemoryRecentFilesStore()
        )
    }

    private func setReadingState(
        _ position: ReadingPosition,
        scale: CGFloat,
        sessionID: UUID,
        in store: DocumentStore
    ) {
        store.setScaleMode(.manual, scaleFactor: scale, for: sessionID)
        store.updateReadingPosition(position, scaleFactor: scale, for: sessionID)
    }

    private func makeFourPaneLayout(
        in store: DocumentStore,
        windowID: UUID
    ) throws -> (rightTop: ReaderPane, rightBottom: ReaderPane, leftBottom: ReaderPane) {
        let rightTop = try XCTUnwrap(store.splitPane(from: .primary, layout: .sideBySide, in: windowID))
        let rightBottom = try XCTUnwrap(store.splitPane(from: rightTop, layout: .stacked, in: windowID))
        let leftBottom = try XCTUnwrap(store.splitPane(from: .primary, layout: .stacked, in: windowID))
        return (rightTop, rightBottom, leftBottom)
    }
}
