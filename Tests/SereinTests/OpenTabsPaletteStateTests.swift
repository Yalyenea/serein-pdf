import AppKit
import PDFKit
import XCTest
@testable import Serein

final class OpenTabsPaletteStateTests: XCTestCase {
    func testInitialHighlightPrefersActiveSession() {
        let first = makeSession(title: "First", path: "/tmp/first.pdf")
        let second = makeSession(title: "Second", path: "/tmp/second.pdf")

        let state = OpenTabsPaletteState(sessions: [first, second], activeSessionID: second.id)

        XCTAssertEqual(state.highlightedItem?.sessionID, second.id)
    }

    func testItemsShowCurrentPageAndDocumentLength() {
        let session = makeSession(title: "Paper", path: "/tmp/paper.pdf", pageCount: 3, currentPageIndex: 2)

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageText, "Page 3 / 3")
    }

    func testPageIndexIsClampedToDocumentBounds() {
        let session = makeSession(title: "Paper", path: "/tmp/paper.pdf", pageCount: 2, currentPageIndex: 8)

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageText, "Page 2 / 2")
    }

    func testItemsDoNotRequireLoadedPDFMetadata() {
        let session = DocumentSession(
            url: URL(fileURLWithPath: "/tmp/unloaded.pdf"),
            title: "Unloaded",
            currentPageIndex: 4
        )

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageText, "Page 5")
    }

    func testItemsExposeSplitPaneBadges() {
        let primary = makeSession(title: "Primary", path: "/tmp/primary.pdf")
        let secondary = makeSession(title: "Secondary", path: "/tmp/secondary.pdf")

        let state = OpenTabsPaletteState(
            sessions: [primary, secondary],
            activeSessionID: secondary.id,
            primarySessionID: primary.id,
            secondarySessionID: secondary.id,
            focusedPane: .secondary
        )

        XCTAssertEqual(state.items[0].paneBadge, "P")
        XCTAssertFalse(state.items[0].isFocusedPane)
        XCTAssertEqual(state.items[1].paneBadge, "S")
        XCTAssertTrue(state.items[1].isFocusedPane)
    }

    func testListMovementWrapsInBothDirections() {
        let sessions = (0..<6).map { index in
            makeSession(title: "PDF \(index)", path: "/tmp/\(index).pdf")
        }
        var state = OpenTabsPaletteState(sessions: sessions, activeSessionID: sessions[0].id)

        state.moveHighlight(delta: 1)
        XCTAssertEqual(state.highlightedIndex, 1)

        state.moveHighlight(delta: -1)
        XCTAssertEqual(state.highlightedIndex, 0)

        state.moveHighlight(delta: -1)
        XCTAssertEqual(state.highlightedIndex, 5)

        state.moveHighlight(delta: 1)
        XCTAssertEqual(state.highlightedIndex, 0)
    }

    func testHeldControlUsesProvidedMRUOrderAndStartsAtPreviousDocument() {
        let sessions = (0..<3).map { makeSession(title: "PDF \($0)", path: "/tmp/\($0).pdf") }
        let items = sessions.enumerated().map {
            OpenTabsPaletteItem(session: $0.element, isActive: $0.offset == 0, workspaceName: "Space \($0.offset)")
        }
        var state = OpenTabsPaletteState(sessions: [], activeSessionID: nil)
        state.replaceItems(items, activationMode: .heldControl(reverse: false))
        XCTAssertEqual(state.highlightedItem?.sessionID, sessions[1].id)
        XCTAssertEqual(state.highlightedItem?.workspaceName, "Space 1")
        XCTAssertEqual(state.items, items)
        state.replaceItems(items, activationMode: .heldControl(reverse: true))
        XCTAssertEqual(state.highlightedItem?.sessionID, sessions[2].id)
        state.replaceItems([], activationMode: .heldControl(reverse: false))
        XCTAssertNil(state.highlightedItem)
    }

    func testHeldControlWithoutActivePDFStartsAtMRUEdge() {
        let items = (0..<3).map { index in
            OpenTabsPaletteItem(
                session: makeSession(title: "PDF \(index)", path: "/tmp/\(index).pdf"),
                isActive: false
            )
        }
        var state = OpenTabsPaletteState(sessions: [], activeSessionID: nil)

        state.replaceItems(items, activationMode: .heldControl(reverse: false))
        XCTAssertEqual(state.highlightedItem?.sessionID, items[0].sessionID)

        state.replaceItems(items, activationMode: .heldControl(reverse: true))
        XCTAssertEqual(state.highlightedItem?.sessionID, items[2].sessionID)
    }

    private func makeSession(
        title: String,
        path: String,
        pageCount: Int = 1,
        currentPageIndex: Int = 0
    ) -> DocumentSession {
        DocumentSession(
            url: URL(fileURLWithPath: path),
            title: title,
            pdfDocument: TestPDFFixtures.makeBlankDocument(pageCount: pageCount),
            currentPageIndex: currentPageIndex
        )
    }
}
