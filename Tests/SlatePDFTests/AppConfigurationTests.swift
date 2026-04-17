import Foundation
import XCTest
@testable import SlatePDF

final class AppConfigurationTests: XCTestCase {
    func testBootstrapCreatesDefaultTomlConfig() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        let store = try AppConfigurationStore(fileURL: fileURL)
        let configuration = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(configuration.reader.defaultDisplayMode, .singlePageContinuous)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth]?.key, "0")
    }

    func testLoadTomlOverridesReaderDefaultsAndShortcuts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("config.toml")

        try """
[reader]
default_display_mode = "two_up"
fit_width_on_open = false

[shortcuts]
fit_width = "command+shift+9"
two_up = "command+option+8"
""".write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try AppConfigurationStore(fileURL: fileURL).load()

        XCTAssertEqual(configuration.reader.defaultDisplayMode, .twoUp)
        XCTAssertFalse(configuration.reader.fitWidthOnOpen)
        XCTAssertEqual(configuration.shortcuts.bindings[.fitWidth], KeyboardShortcut(key: "9", modifiers: [.command, .shift]))
        XCTAssertEqual(configuration.shortcuts.bindings[.twoUp], KeyboardShortcut(key: "8", modifiers: [.command, .option]))
    }
}
