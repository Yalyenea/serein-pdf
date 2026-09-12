import XCTest
@testable import Serein

final class AnnotationCommentPlacementTests: XCTestCase {
    private let available = NSRect(x: 20, y: 30, width: 1200, height: 900)
    private let previewSize = NSSize(width: 360, height: 140)
    private let editorSize = NSSize(width: 360, height: 380)

    func testCenterPrefersRightAndKeepsTopCornerWhileEditing() {
        let anchor = NSRect(x: 600, y: 500, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        let preview = placement.frame(for: previewSize)
        let editor = placement.frame(for: editorSize)

        XCTAssertEqual(preview.minX, anchor.maxX + 8)
        XCTAssertEqual(preview.maxY, anchor.maxY)
        XCTAssertEqual(preview.minX, editor.minX)
        XCTAssertEqual(preview.maxY, editor.maxY)
        XCTAssertEqual(preview.width, editor.width)
        XCTAssertFalse(editor.intersects(anchor))
    }

    func testRightEdgeUsesLeftAndKeepsBottomCornerWhileEditing() {
        let anchor = NSRect(x: 1180, y: 80, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        let preview = placement.frame(for: previewSize)
        let editor = placement.frame(for: editorSize)

        XCTAssertEqual(preview.maxX, anchor.minX - 8)
        XCTAssertEqual(preview.minY, anchor.minY)
        XCTAssertEqual(preview.maxX, editor.maxX)
        XCTAssertEqual(preview.minY, editor.minY)
        XCTAssertTrue(available.contains(editor))
    }

    func testFourCornersAndEdgesStayVisibleWithoutCoveringIcon() {
        for x in [available.minX, available.midX, available.maxX - 16] {
            for y in [available.minY, available.midY, available.maxY - 16] {
                let anchor = NSRect(x: x, y: y, width: 16, height: 16)
                let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
                let preview = placement.frame(for: previewSize)
                let editor = placement.frame(for: editorSize)

                XCTAssertTrue(available.contains(preview), "\(anchor)")
                XCTAssertTrue(available.contains(editor), "\(anchor)")
                XCTAssertFalse(preview.intersects(anchor), "\(anchor)")
                XCTAssertFalse(editor.intersects(anchor), "\(anchor)")
                XCTAssertEqual(preview.minX, editor.minX)
                XCTAssertTrue(preview.minY == editor.minY || preview.maxY == editor.maxY)
            }
        }
    }

    func testNarrowWindowChoosesAboveBeforePreviewAppears() {
        let available = NSRect(x: 10, y: 20, width: 500, height: 900)
        let anchor = NSRect(x: 250, y: 400, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        let preview = placement.frame(for: previewSize)
        let editor = placement.frame(for: editorSize)

        XCTAssertEqual(preview.minY, anchor.maxY + 8)
        XCTAssertEqual(preview.origin, editor.origin)
        XCTAssertTrue(available.contains(editor))
        XCTAssertFalse(editor.intersects(anchor))
    }

    func testNarrowWindowUsesBelowWhenOnlyEditorFitsThere() {
        let available = NSRect(x: 10, y: 20, width: 500, height: 900)
        let anchor = NSRect(x: 250, y: 700, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        let preview = placement.frame(for: previewSize)
        let editor = placement.frame(for: editorSize)

        // A short preview fits above, but selecting using its height would
        // make the card jump below when the user starts editing.
        XCTAssertEqual(preview.maxY, anchor.minY - 8)
        XCTAssertEqual(preview.maxY, editor.maxY)
        XCTAssertEqual(preview.minX, editor.minX)
        XCTAssertTrue(available.contains(editor))
        XCTAssertFalse(editor.intersects(anchor))
    }

    func testGrowingTextPreservesAttachmentThroughoutReservedHeight() {
        let anchor = NSRect(x: 600, y: 600, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        for height in stride(from: CGFloat(140), through: 380, by: 20) {
            let frame = placement.frame(for: NSSize(width: 360, height: height))
            XCTAssertEqual(frame.minX, anchor.maxX + 8)
            XCTAssertEqual(frame.maxY, anchor.maxY)
            XCTAssertEqual(frame.height, height)
            XCTAssertTrue(available.contains(frame))
        }
    }

    func testNegativeScreenCoordinatesArePreserved() {
        let available = NSRect(x: -1400, y: -300, width: 1200, height: 900)
        let anchor = NSRect(x: -1100, y: 200, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)
        let frame = placement.frame(for: editorSize)

        XCTAssertEqual(frame.minX, anchor.maxX + 8)
        XCTAssertTrue(available.contains(frame))
        XCTAssertFalse(frame.intersects(anchor))
    }

    func testCardIsConstrainedWhenAvailableAreaCannotFitReservedSize() {
        let available = NSRect(x: 30, y: 40, width: 250, height: 200)
        let anchor = NSRect(x: 140, y: 130, width: 16, height: 16)
        let placement = AnnotationCommentPlacement(anchor: anchor, available: available, reservedSize: editorSize)

        XCTAssertEqual(placement.frame(for: editorSize), available)
        XCTAssertTrue(available.contains(placement.frame(for: previewSize)))
    }
}
