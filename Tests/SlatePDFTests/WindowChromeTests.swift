import AppKit
import Foundation
import PDFKit
import Testing
@testable import SlatePDF

@MainActor
struct WindowChromeTests {
    @Test
    func verticalTabsDetachToolbarStrip() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)
        controller.window?.layoutIfNeeded()

        #expect(controller.window?.toolbar == nil)

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setTabPresentationMode(.verticalSidebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func horizontalTabsHideWhenLeftSidebarReturns() {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let controller = MainWindowController(documentStore: store)

        store.setTabPresentationMode(.horizontalTitlebar)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar != nil)

        store.setLeftSidebarVisible(true)
        controller.window?.layoutIfNeeded()
        #expect(controller.window?.toolbar == nil)
    }

    @Test
    func nightModeKeepsLivePDFViewAvailableForSnapshots() {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }

        let store = DocumentStore(appConfiguration: .default)
        let controller = ReaderViewController(documentStore: store)
        controller.loadViewIfNeeded()

        #expect(controller.isNightModeEnabled)
        #expect(controller.pdfView.isHidden == false)
    }

    @Test
    func splitViewClearsLegacyAutosavedDividerFrames() {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "NSSplitView Subview Frames MainSplitView",
            "NSSplitView Subview Frames SlatePDFSplit.v2",
            "NSSplitView Subview Frames SlatePDFSplit.v3",
        ]
        let originals = legacyKeys.map { (key: $0, value: defaults.object(forKey: $0)) }
        defer {
            for entry in originals {
                if let value = entry.value {
                    defaults.set(value, forKey: entry.key)
                } else {
                    defaults.removeObject(forKey: entry.key)
                }
            }
        }

        for key in legacyKeys {
            defaults.set(
                [
                    "0.000000, 0.000000, 264.500000, 900.000000, NO, NO",
                    "265.500000, 0.000000, 973.500000, 900.000000, NO, NO",
                    "1240.000000, 0.000000, 120.000000, 900.000000, NO, NO",
                ],
                forKey: key
            )
        }

        let controller = SplitViewController(documentStore: DocumentStore(appConfiguration: .default))
        controller.loadViewIfNeeded()

        for key in legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(controller.splitView.autosaveName == nil)
    }

    @Test
    func documentStoreRefreshKeepsAdjustedRightSidebarWidth() throws {
        _ = NSApplication.shared
        let store = DocumentStore(appConfiguration: .default)
        let mainWindowController = MainWindowController(documentStore: store)
        guard let window = mainWindowController.window,
              let controller = window.contentViewController as? SplitViewController else {
            Issue.record("Failed to create main split view")
            return
        }
        window.layoutIfNeeded()

        let session = try store.open(documentAt: makeTemporaryPDF(named: "split-width"))
        window.layoutIfNeeded()
        controller.splitView.setPosition(900, ofDividerAt: 1)
        controller.splitView.adjustSubviews()
        window.layoutIfNeeded()

        let rightSidebarWidthBefore = controller.splitView.arrangedSubviews[2].frame.width
        store.setDirty(true, for: session.id)
        window.layoutIfNeeded()
        let rightSidebarWidthAfter = controller.splitView.arrangedSubviews[2].frame.width

        #expect(rightSidebarWidthBefore > 120)
        #expect(abs(rightSidebarWidthAfter - rightSidebarWidthBefore) < 0.5)
    }
}

@MainActor
private func makeTemporaryPDF(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    let document = PDFDocument()

    let image = NSImage(size: NSSize(width: 200, height: 260))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 260)).fill()
    let textRect = NSRect(x: 24, y: 110, width: 152, height: 40)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
        .foregroundColor: NSColor.black,
    ]
    NSString(string: name).draw(in: textRect, withAttributes: attributes)
    image.unlockFocus()

    guard let page = PDFPage(image: image) else {
        throw CocoaError(.fileWriteUnknown)
    }
    document.insert(page, at: 0)

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}
