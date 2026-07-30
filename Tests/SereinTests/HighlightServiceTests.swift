import AppKit
import PDFKit
import XCTest
@testable import Serein

@MainActor
final class HighlightServiceTests: XCTestCase {
    func testDefaultHighlightColorIsPink() {
        XCTAssertEqual(HighlightColor.default, .pink)
    }

    func testAllPaletteColorsAreAvailable() {
        XCTAssertEqual(Set(HighlightColor.allCases), [.pink, .yellow, .green])
    }

    func testHighlightColorHasDistinctMenuTitles() {
        let titles = HighlightColor.allCases.map(\.menuTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testSelectionContainsTextReturnsFalseForNilSelection() {
        XCTAssertFalse(HighlightService.selectionContainsText(nil))
    }

    func testDefaultColorMatchesPinkPalette() {
        XCTAssertEqual(
            HighlightService.defaultColor.cgColor.components,
            HighlightColor.pink.nsColor.cgColor.components
        )
    }

    func testHighlightPalettesMatchApprovedThemeDefaults() {
        assertColor(
            HighlightColor.pink.nsColor(in: .normal),
            red: 241.0 / 255.0,
            green: 171.0 / 255.0,
            blue: 192.0 / 255.0,
            alpha: 0.70
        )
        assertColor(
            HighlightColor.yellow.nsColor(in: .normal),
            red: 239.0 / 255.0,
            green: 213.0 / 255.0,
            blue: 110.0 / 255.0,
            alpha: 0.63
        )
        assertColor(
            HighlightColor.green.nsColor(in: .normal),
            red: 169.0 / 255.0,
            green: 217.0 / 255.0,
            blue: 180.0 / 255.0,
            alpha: 0.66
        )
        assertColor(
            HighlightColor.pink.nsColor(in: .rosePineDawn),
            red: 233.0 / 255.0,
            green: 168.0 / 255.0,
            blue: 186.0 / 255.0,
            alpha: 0.68
        )
        assertColor(
            HighlightColor.yellow.nsColor(in: .rosePineDawn),
            red: 228.0 / 255.0,
            green: 201.0 / 255.0,
            blue: 103.0 / 255.0,
            alpha: 0.62
        )
        assertColor(
            HighlightColor.green.nsColor(in: .rosePineDawn),
            red: 159.0 / 255.0,
            green: 204.0 / 255.0,
            blue: 167.0 / 255.0,
            alpha: 0.64
        )
        assertColor(
            HighlightColor.pink.nsColor(in: .rosePineMoon),
            red: 232.0 / 255.0,
            green: 140.0 / 255.0,
            blue: 171.0 / 255.0,
            alpha: 0.48
        )
        assertColor(
            HighlightColor.yellow.nsColor(in: .rosePineMoon),
            red: 232.0 / 255.0,
            green: 196.0 / 255.0,
            blue: 110.0 / 255.0,
            alpha: 0.42
        )
        assertColor(
            HighlightColor.green.nsColor(in: .rosePineMoon),
            red: 143.0 / 255.0,
            green: 207.0 / 255.0,
            blue: 167.0 / 255.0,
            alpha: 0.44
        )
    }

    func testClosestHighlightColorRecognizesThemePalettes() {
        for palette in HighlightPalette.allCases {
            XCTAssertEqual(HighlightColor.closest(to: HighlightColor.pink.nsColor(in: palette)), .pink)
            XCTAssertEqual(HighlightColor.closest(to: HighlightColor.yellow.nsColor(in: palette)), .yellow)
            XCTAssertEqual(HighlightColor.closest(to: HighlightColor.green.nsColor(in: palette)), .green)
        }
    }

    func testNightModeStyleResolvesHighlightColorFromActiveTheme() {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        NightModeStyle.applyThemeSelections(light: .rosePineDawn, dark: .rosePineMoon)
        defer {
            NightModeStyle.applyThemeSelections(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        app.appearance = NSAppearance(named: .aqua)
        assertColor(
            NightModeStyle.highlightColor(for: .pink, appearance: app.effectiveAppearance),
            matches: HighlightColor.pink.nsColor(in: .rosePineDawn)
        )

        app.appearance = NSAppearance(named: .darkAqua)
        assertColor(
            NightModeStyle.highlightColor(for: .pink, appearance: app.effectiveAppearance),
            matches: HighlightColor.pink.nsColor(in: .rosePineMoon)
        )
    }

    func testHighlightAnnotationAtPointReturnsCoveringHighlight() throws {
        let document = try makeSearchableDocument(text: "alpha beta")
        let page = try XCTUnwrap(document.page(at: 0))
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        XCTAssertEqual(HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor).count, 1)
        XCTAssertEqual(HighlightService.applyHighlight(to: betaSelection, color: HighlightColor.green.nsColor).count, 1)

        let alphaBounds = alphaSelection.bounds(for: page)
        let alphaCenter = NSPoint(x: alphaBounds.midX, y: alphaBounds.midY)
        let outside = NSPoint(x: alphaBounds.maxX + 1000, y: alphaBounds.maxY + 1000)

        let hitAlpha = HighlightService.highlightAnnotation(at: alphaCenter, on: page)
        XCTAssertEqual(hitAlpha?.color.cgColor.components, HighlightColor.pink.nsColor.cgColor.components)
        XCTAssertNil(HighlightService.highlightAnnotation(at: outside, on: page))
    }

    func testHighlightAnnotationAtPointPrefersTopmostOverlappingHighlight() throws {
        let document = try makeSearchableDocument(text: "overlap")
        let page = try XCTUnwrap(document.page(at: 0))
        let selection = try XCTUnwrap(document.findString("overlap", withOptions: []).first)
        XCTAssertEqual(HighlightService.applyHighlight(to: selection, color: HighlightColor.pink.nsColor).count, 1)
        XCTAssertEqual(HighlightService.applyHighlight(to: selection, color: HighlightColor.green.nsColor).count, 1)

        let bounds = selection.bounds(for: page)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let hit = HighlightService.highlightAnnotation(at: center, on: page)
        XCTAssertEqual(hit?.color.cgColor.components, HighlightColor.green.nsColor.cgColor.components)
    }

    func testTextSanitizerPreservesChineseAndRemovesHiddenUnicodeArtifacts() {
        let sanitized = PDFTextSanitizer.sanitize("中\u{0000}\u{200B}文\u{FEFF} 高\u{2060}亮")
        XCTAssertEqual(sanitized, "中文 高亮")
    }

    func testBuildHighlightGroupsPreservesChineseSnippet() throws {
        let document = try makeSearchableDocument(text: "海瑟矩阵可能非正定，导致牛顿方向其实并非下降方向。")
        let selection = try XCTUnwrap(document.findString("非正定", withOptions: []).first)
        _ = HighlightService.applyHighlight(to: selection)

        let groups = HighlightService.buildHighlightGroups(in: document)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.snippet, "非正定")
    }

    func testBuildHighlightGroupsFromRecordsOnlyUsesChangedRecords() throws {
        let document = try makeSearchableDocument(text: "alpha beta gamma")
        let alphaSelection = try XCTUnwrap(document.findString("alpha", withOptions: []).first)
        let betaSelection = try XCTUnwrap(document.findString("beta", withOptions: []).first)
        _ = HighlightService.applyHighlight(to: alphaSelection, color: HighlightColor.pink.nsColor)
        let betaRecords = HighlightService.applyHighlight(
            to: betaSelection,
            color: HighlightColor.green.nsColor,
            createdAt: Date(timeIntervalSince1970: 42)
        )
        XCTAssertTrue(HighlightService.updateComment("changed only", for: betaRecords))

        let groups = HighlightService.buildHighlightGroups(from: betaRecords)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.snippet, "beta")
        XCTAssertEqual(groups.first?.color, .green)
        XCTAssertEqual(groups.first?.comment, "changed only")
        XCTAssertEqual(groups.first?.createdAt, Date(timeIntervalSince1970: 42))
    }

    private func makeSearchableDocument(text: String) throws -> PDFDocument {
        try TestPDFFixtures.makeSearchableDocument(text: text)
    }
}

private func assertColor(
    _ color: NSColor,
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    XCTAssertEqual(srgb.redComponent, red, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.greenComponent, green, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.blueComponent, blue, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.alphaComponent, alpha, accuracy: 0.001, file: file, line: line)
}

private func assertColor(
    _ color: NSColor,
    matches expected: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    let expectedSRGB = expected.usingColorSpace(.sRGB) ?? expected
    XCTAssertEqual(srgb.redComponent, expectedSRGB.redComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.greenComponent, expectedSRGB.greenComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.blueComponent, expectedSRGB.blueComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(srgb.alphaComponent, expectedSRGB.alphaComponent, accuracy: 0.001, file: file, line: line)
}
