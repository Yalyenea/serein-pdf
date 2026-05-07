import AppKit
import PDFKit
import XCTest
@testable import Serein

final class OpenTabsPaletteStateTests: XCTestCase {
    func testInitialHighlightPrefersActiveSession() throws {
        let first = try makeSession(title: "First", path: "/tmp/first.pdf")
        let second = try makeSession(title: "Second", path: "/tmp/second.pdf")

        let state = OpenTabsPaletteState(sessions: [first, second], activeSessionID: second.id)

        XCTAssertEqual(state.highlightedItem?.sessionID, second.id)
    }

    func testItemsExposeCurrentPagePreviewTarget() throws {
        let session = try makeSession(title: "Paper", path: "/tmp/paper.pdf", pageCount: 3, currentPageIndex: 2)

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageIndex, 2)
        XCTAssertEqual(state.items.first?.pageCount, 3)
        XCTAssertEqual(state.items.first?.pageText, "Page 3 / 3")
    }

    func testPageIndexIsClampedToDocumentBounds() throws {
        let session = try makeSession(title: "Paper", path: "/tmp/paper.pdf", pageCount: 2, currentPageIndex: 8)

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageIndex, 1)
        XCTAssertEqual(state.items.first?.pageText, "Page 2 / 2")
    }

    func testItemsDoNotRequireLoadedPDFMetadata() {
        let session = DocumentSession(
            url: URL(fileURLWithPath: "/tmp/unloaded.pdf"),
            title: "Unloaded",
            currentPageIndex: 4
        )

        let state = OpenTabsPaletteState(sessions: [session], activeSessionID: session.id)

        XCTAssertEqual(state.items.first?.pageIndex, 4)
        XCTAssertEqual(state.items.first?.pageCount, 0)
        XCTAssertEqual(state.items.first?.pageText, "Page 5")
    }

    func testItemsExposeSplitPaneBadges() throws {
        let primary = try makeSession(title: "Primary", path: "/tmp/primary.pdf")
        let secondary = try makeSession(title: "Secondary", path: "/tmp/secondary.pdf")

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

    func testGridMovementUsesColumns() throws {
        let sessions = try (0..<6).map { index in
            try makeSession(title: "PDF \(index)", path: "/tmp/\(index).pdf")
        }
        var state = OpenTabsPaletteState(sessions: sessions, activeSessionID: sessions[0].id)

        state.moveHighlight(.right, columnCount: 3)
        XCTAssertEqual(state.highlightedIndex, 1)

        state.moveHighlight(.down, columnCount: 3)
        XCTAssertEqual(state.highlightedIndex, 4)

        state.moveHighlight(.left, columnCount: 3)
        XCTAssertEqual(state.highlightedIndex, 3)

        state.moveHighlight(.up, columnCount: 3)
        XCTAssertEqual(state.highlightedIndex, 0)
    }

    private func makeSession(
        title: String,
        path: String,
        pageCount: Int = 1,
        currentPageIndex: Int = 0
    ) throws -> DocumentSession {
        DocumentSession(
            url: URL(fileURLWithPath: path),
            title: title,
            pdfDocument: try makePDFDocument(pageCount: pageCount),
            currentPageIndex: currentPageIndex
        )
    }

    private func makePDFDocument(pageCount: Int) throws -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 200, height: 260))
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
            image.unlockFocus()

            guard let page = PDFPage(image: image) else {
                throw CocoaError(.fileWriteUnknown)
            }
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}
