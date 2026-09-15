import Foundation
import XCTest
@testable import Serein

final class ReferencePreviewEquationTests: XCTestCase {
    private let pageBounds = CGRect(x: 0, y: 0, width: 600, height: 800)

    func testStaggeredBodyLinesIdentifyEitherColumn() throws {
        let characters = staggeredBody(excludingEquationSpace: false)
        for x: CGFloat in [50, 330] {
            let bounds = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
                characterBounds: characters,
                pageBounds: pageBounds,
                target: CGPoint(x: x, y: 508)
            ))
            XCTAssertLessThan(bounds.width, 300)
            XCTAssertTrue(bounds.contains(CGPoint(x: x, y: 500)))
            XCTAssertTrue(bounds.contains(CGPoint(x: x + 215, y: 500)))
            XCTAssertFalse(bounds.contains(CGPoint(x: x == 50 ? 430 : 150, y: 500)))
        }
    }

    func testSparseEquationUsesNearbyBodyAndIncludesEquationNumber() throws {
        for x: CGFloat in [50, 330] {
            let equation = equationCharacters(x: x)
            let bounds = try XCTUnwrap(ReferencePreviewColumnLayout.columnBounds(
                characterBounds: staggeredBody(excludingEquationSpace: true) + equation,
                pageBounds: pageBounds,
                target: CGPoint(x: x + 60, y: 510)
            ))
            XCTAssertLessThan(bounds.width, 300)
            XCTAssertTrue(bounds.contains(CGPoint(x: x, y: 500)))
            for character in equation {
                XCTAssertTrue(bounds.contains(character), "Clipped equation glyph: \(character)")
            }
            XCTAssertFalse(bounds.contains(CGPoint(x: x == 50 ? 430 : 150, y: 500)))
        }
    }

    func testSpanningEquationKeepsPageWidthDespiteNearbyTwoColumnBody() {
        let equation = (0..<67).map { index in
            CGRect(x: 100 + CGFloat(index) * 6, y: 500, width: 5, height: 10)
        }
        for x: CGFloat in [100, 350] {
            XCTAssertNil(ReferencePreviewColumnLayout.columnBounds(
                characterBounds: staggeredBody(excludingEquationSpace: true) + equation,
                pageBounds: pageBounds,
                target: CGPoint(x: x, y: 510)
            ))
        }
    }

    private func staggeredBody(excludingEquationSpace: Bool) -> [CGRect] {
        [CGFloat(50), 330].flatMap { x in
            (0..<24).flatMap { row -> [CGRect] in
                // Independent paragraphs and display equations offset the two baselines.
                let y = 704 - CGFloat(row) * 24 - (x == 330 ? 12 : 0)
                guard !excludingEquationSpace || abs(y - 500) > 30 else { return [] }
                return (0..<36).map { column in
                    CGRect(x: x + CGFloat(column) * 6, y: y, width: 5, height: 8)
                }
            }
        }
    }

    private func equationCharacters(x: CGFloat) -> [CGRect] {
        let baseline = (0..<12).map { index in
            CGRect(x: x + 60 + CGFloat(index) * 8, y: 500, width: 5, height: 10)
        }
        let scripts = [
            CGRect(x: x + 74, y: 508, width: 3, height: 4),
            CGRect(x: x + 99, y: 496, width: 3, height: 4),
            CGRect(x: x + 131, y: 508, width: 3, height: 4),
        ]
        // The right-aligned equation number lies beyond the nearby paragraph's edge.
        let number = (0..<4).map { index in
            CGRect(x: x + 215 + CGFloat(index) * 4, y: 500, width: 3, height: 8)
        }
        return baseline + scripts + number
    }
}
