import AppKit
import PDFKit
import Testing
@testable import Serein

@Suite(.serialized)
@MainActor
struct FloatingOutlineViewControllerTests {
    @Test
    func floatingOutlinePanelIsTranslucentAndFollowsTheme() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = makeIsolatedDocumentStore()
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.refreshChromeColors()
        let normalColor = try #require(
            controller.testingPanelBackgroundColor?.usingColorSpace(.sRGB)
        )

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        controller.refreshChromeColors()
        let dawnColor = try #require(
            controller.testingPanelBackgroundColor?.usingColorSpace(.sRGB)
        )
        var resolvedDawnColor: NSColor?
        controller.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedDawnColor = NightModeStyle.paneBackgroundColor.usingColorSpace(.sRGB)
        }
        let expectedDawnColor = try #require(resolvedDawnColor)

        let panel = try #require(
            floatingOutlineView(identifier: "floatingOutlinePanel", in: controller.view)
        )

        #expect(panel is NSVisualEffectView == false)
        #expect(abs(dawnColor.alphaComponent - 0.92) < 0.001)
        #expect(abs(dawnColor.redComponent - normalColor.redComponent) > 0.01)
        #expect(abs(dawnColor.redComponent - expectedDawnColor.redComponent) < 0.001)
        #expect(abs(dawnColor.greenComponent - expectedDawnColor.greenComponent) < 0.001)
        #expect(abs(dawnColor.blueComponent - expectedDawnColor.blueComponent) < 0.001)
    }

    @Test
    func floatingOutlineSearchFieldBackgroundFollowsTheme() throws {
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
        app.appearance = NSAppearance(named: .aqua)
        defer {
            ThemeManager.shared.apply(light: .normal, dark: .rosePineMoon)
            app.appearance = previousAppearance
        }

        let store = makeIsolatedDocumentStore()
        let outlineController = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID,
            isFloatingPresentation: true
        )
        outlineController.loadViewIfNeeded()
        outlineController.refreshChromeColors()
        let filterField = try #require(
            floatingOutlineView(
                identifier: "outlineFilterField",
                in: outlineController.view
            ) as? NSSearchField
        )
        filterField.frame = NSRect(x: 0, y: 0, width: 276, height: 22)
        let normalRenderedColor = try renderedColor(of: filterField, at: NSPoint(x: 250, y: 11))

        ThemeManager.shared.apply(light: .rosePineDawn, dark: .rosePineMoon)
        outlineController.refreshChromeColors()
        let dawnColor = try #require(filterField.backgroundColor?.usingColorSpace(.sRGB))
        let dawnRenderedColor = try renderedColor(of: filterField, at: NSPoint(x: 250, y: 11))
        var resolvedExpectedColor: NSColor?
        filterField.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedExpectedColor = NightModeStyle.selectedChromeBackgroundColor
                .usingColorSpace(.sRGB)
        }
        let expectedColor = try #require(resolvedExpectedColor)

        #expect(filterField.isBezeled)
        #expect(filterField.bezelStyle == .squareBezel)
        #expect(filterField.drawsBackground == false)
        #expect(abs(dawnColor.redComponent - expectedColor.redComponent) < 0.001)
        #expect(abs(dawnColor.greenComponent - expectedColor.greenComponent) < 0.001)
        #expect(abs(dawnColor.blueComponent - expectedColor.blueComponent) < 0.001)
        #expect(abs(dawnColor.alphaComponent - expectedColor.alphaComponent) < 0.001)
        #expect(colorDistance(dawnRenderedColor, normalRenderedColor) > 0.05)
        #expect(colorDistance(dawnRenderedColor, .white) > 0.08)
    }

    @Test
    func floatingOutlineSearchFieldUsesNativeTextInsets() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let outlineController = OutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID,
            isFloatingPresentation: true
        )
        outlineController.loadViewIfNeeded()
        let filterField = try #require(
            floatingOutlineView(
                identifier: "outlineFilterField",
                in: outlineController.view
            ) as? NSSearchField
        )
        filterField.frame = NSRect(x: 0, y: 0, width: 276, height: 22)
        let searchTextBounds = filterField.searchTextBounds
        let searchButtonBounds = filterField.searchButtonBounds

        #expect(filterField.isBezeled)
        #expect(filterField.bezelStyle == .squareBezel)
        #expect(searchTextBounds.minX > filterField.bounds.minX + 8)
        #expect(searchTextBounds.minX >= searchButtonBounds.midX)
        #expect(searchTextBounds.maxX < filterField.bounds.maxX)
        #expect(searchTextBounds.minY > filterField.bounds.minY)
    }

    @Test
    func floatingOutlineAppearsAsRailAndExpandsOnHover() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-rail"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        #expect(controller.testingIsPresented == false)

        store.setRightSidebarVisible(false)

        #expect(controller.testingIsPresented)
        #expect(controller.testingItemCount == 3)
        #expect(controller.testingIsExpanded == false)
        #expect(controller.preferredSize.width == 28)

        controller.testingSetHovered(true)

        #expect(controller.testingIsExpanded)
        #expect(controller.preferredSize.width == 300)
        #expect(controller.testingOutlineViewController.isViewLoaded)

        controller.testingSetHovered(false)
        #expect(controller.testingIsExpanded == false)

        store.setRightSidebarVisible(true)
        #expect(controller.testingIsPresented == false)
    }

    @Test
    func floatingOutlineRemainsExpandedWhileSearchFieldIsEditing() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-search-focus"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.testingSetHovered(true)
        let outlineController = controller.testingOutlineViewController

        outlineController.controlTextDidBeginEditing(
            Notification(name: NSControl.textDidBeginEditingNotification)
        )
        controller.testingSetHovered(false)

        #expect(controller.testingIsExpanded)

        outlineController.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification)
        )

        #expect(controller.testingIsExpanded == false)
    }

    @Test
    func shortFloatingOutlineUsesNaturalHeightAndAvailableSpace() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.floatingOutlineHeight = 700
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-short-height"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(700)
        controller.testingSetHovered(true)

        let naturalHeight = controller.preferredSize.height
        #expect(naturalHeight < AppConfiguration.Layout.minimumFloatingOutlineHeight)

        configuration.layout.floatingOutlineHeight = 500
        store.updateAppConfiguration(configuration)
        #expect(controller.preferredSize.height == naturalHeight)

        controller.setMaximumAvailableHeight(140)
        #expect(controller.preferredSize.height == 140)

        controller.setMaximumAvailableHeight(700)
        #expect(controller.preferredSize.height == naturalHeight)
    }

    @Test
    func floatingOutlineHeightTracksVisibleRows() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-visible-rows"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(700)
        controller.testingSetHovered(true)

        let expandedHeight = controller.preferredSize.height
        let outlineController = controller.testingOutlineViewController
        let toggleButton = try #require(
            floatingOutlineView(
                identifier: "outlineExpansionToggleButton",
                in: outlineController.view
            ) as? NSButton
        )

        toggleButton.performClick(nil)
        let collapsedHeight = controller.preferredSize.height
        #expect(collapsedHeight < expandedHeight)

        toggleButton.performClick(nil)
        #expect(controller.preferredSize.height == expandedHeight)
    }

    @Test
    func floatingOutlineUsesConfiguredMaximumHeightUntilWindowOverridesIt() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.floatingOutlineHeight = 340
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeLongFloatingOutlinePDF(named: "floating-height"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(700)
        controller.testingSetHovered(true)

        #expect(controller.preferredSize.height == 340)

        configuration.layout.floatingOutlineHeight = 410
        store.updateAppConfiguration(configuration)
        #expect(controller.preferredSize.height == 410)

        controller.testingResizeFromTop(by: 25)
        #expect(controller.preferredSize.height == 460)

        configuration.layout.floatingOutlineHeight = 300
        store.updateAppConfiguration(configuration)
        #expect(controller.preferredSize.height == 460)

        controller.testingSetHovered(false)
        controller.testingSetHovered(true)
        #expect(controller.preferredSize.height == 460)

        let otherWindowController = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        otherWindowController.loadViewIfNeeded()
        otherWindowController.setMaximumAvailableHeight(700)
        otherWindowController.testingSetHovered(true)
        #expect(otherWindowController.preferredSize.height == 300)
    }

    @Test
    func floatingOutlineResizesFromEitherEdgeWithinLimits() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeLongFloatingOutlinePDF(named: "floating-edges"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(500)
        controller.testingSetHovered(true)

        controller.testingResizeFromTop(by: 40)
        #expect(controller.preferredSize.height == 440)

        controller.testingResizeFromBottom(by: -20)
        #expect(controller.preferredSize.height == 480)

        controller.testingResizeFromTop(by: 100)
        #expect(controller.preferredSize.height == 500)

        controller.testingResizeFromBottom(by: 250)
        #expect(controller.preferredSize.height == 180)
    }

    @Test
    func floatingOutlineCanResizePastConfiguredRangeUpToWindowLimit() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeLongFloatingOutlinePDF(named: "floating-window-limit"))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.setMaximumAvailableHeight(800)
        controller.testingSetHovered(true)

        controller.testingResizeFromTop(by: 300)

        #expect(controller.preferredSize.height == 800)
    }

    @Test
    func floatingOutlineUsesSemanticOutlinePaneWhenSidebarsAreSwapped() throws {
        _ = NSApplication.shared
        var configuration = AppConfiguration.default
        configuration.layout.sidebarsSwapped = true
        let store = makeIsolatedDocumentStore(appConfiguration: configuration)
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-swapped"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setLeftSidebarVisible(false)
        store.setRightSidebarVisible(true)
        #expect(controller.testingIsPresented)

        store.setLeftSidebarVisible(true)
        store.setRightSidebarVisible(false)
        #expect(controller.testingIsPresented == false)
    }

    @Test
    func floatingOutlineStaysHiddenForPDFWithoutOutline() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: TestPDFFixtures.makeBlankPDF(named: "floating-empty"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setRightSidebarVisible(false)

        #expect(controller.testingIsPresented == false)
        #expect(controller.testingItemCount == 0)
    }

    @Test
    func floatingOutlineShowsWhenRightSidebarIsNotOnOutlineMode() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-while-annotations"))
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()

        store.setRightSidebarVisible(true)
        store.setRightSidebarMode(.outline, in: store.defaultWindowID)
        #expect(controller.testingIsPresented == false)

        store.setRightSidebarMode(.annotations, in: store.defaultWindowID)
        #expect(controller.testingIsPresented)

        store.setRightSidebarMode(.pages, in: store.defaultWindowID)
        #expect(controller.testingIsPresented)

        store.setRightSidebarMode(.search, in: store.defaultWindowID)
        #expect(controller.testingIsPresented)

        store.setRightSidebarMode(.outline, in: store.defaultWindowID)
        #expect(controller.testingIsPresented == false)
    }

    @Test
    func expandedFloatingOutlineNavigatesWithoutResizingReader() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let session = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-navigation"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let workspace = splitController.readerWorkspaceViewController
        let floatingOutline = workspace.floatingOutlineViewController
        #expect(floatingOutline.testingIsPresented)
        let centerWidthBefore = splitController.splitView.arrangedSubviews[1].frame.width
        let scaleBefore = splitController.readerViewController.pdfView.scaleFactor

        floatingOutline.testingSetHovered(true)
        flushFloatingOutlineLayout(windowController.window)

        #expect(floatingOutline.view.frame.width > 250)
        #expect(abs(splitController.splitView.arrangedSubviews[1].frame.width - centerWidthBefore) < 0.5)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - scaleBefore) < 0.001)

        let outlineController = floatingOutline.testingOutlineViewController
        var request: OutlineNavigationRequest?
        floatingOutline.onNavigationRequested = { request = $0 }
        outlineController.view.frame = NSRect(x: 0, y: 0, width: 292, height: 360)
        outlineController.view.layoutSubtreeIfNeeded()
        let rows = floatingOutlineRows(in: outlineController.view)
        #expect(rows.count == 3)

        rows[2].performPrimaryAction()
        #expect(request == OutlineNavigationRequest(
            sessionID: session.id,
            position: ReadingPosition(pageIndex: 2, point: CGPoint(x: 30, y: 170))
        ))
    }

    @Test
    func resizingFloatingOutlineIsSymmetricAndKeepsReaderGeometryStable() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeLongFloatingOutlinePDF(named: "floating-window-resize"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        windowController.window?.setContentSize(NSSize(width: 1_200, height: 900))
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let workspace = splitController.readerWorkspaceViewController
        let floatingOutline = workspace.floatingOutlineViewController
        floatingOutline.testingSetHovered(true)
        flushFloatingOutlineLayout(windowController.window)

        let centerWidthBefore = splitController.splitView.arrangedSubviews[1].frame.width
        let scaleBefore = splitController.readerViewController.pdfView.scaleFactor
        let initialFrame = floatingOutline.view.frame

        floatingOutline.testingResizeFromTop(by: 40)
        flushFloatingOutlineLayout(windowController.window)
        let topResizedFrame = floatingOutline.view.frame
        #expect(abs(topResizedFrame.midY - initialFrame.midY) < 0.5)
        #expect(abs(topResizedFrame.minY - initialFrame.minY + 40) < 0.5)
        #expect(abs(topResizedFrame.maxY - initialFrame.maxY - 40) < 0.5)
        #expect(abs(topResizedFrame.height - initialFrame.height - 80) < 0.5)

        floatingOutline.testingResizeFromBottom(by: -30)
        flushFloatingOutlineLayout(windowController.window)
        let bottomResizedFrame = floatingOutline.view.frame
        #expect(abs(bottomResizedFrame.midY - topResizedFrame.midY) < 0.5)
        #expect(abs(bottomResizedFrame.minY - topResizedFrame.minY + 30) < 0.5)
        #expect(abs(bottomResizedFrame.maxY - topResizedFrame.maxY - 30) < 0.5)
        #expect(abs(bottomResizedFrame.height - topResizedFrame.height - 60) < 0.5)
        #expect(abs(splitController.splitView.arrangedSubviews[1].frame.width - centerWidthBefore) < 0.5)
        #expect(abs(splitController.readerViewController.pdfView.scaleFactor - scaleBefore) < 0.001)
    }

    @Test
    func allPagesOverviewSuppressesAndRestoresFloatingOutline() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        _ = try store.open(documentAt: makeFloatingOutlinePDF(named: "floating-overview"))
        let windowController = MainWindowController(documentStore: store)
        defer { windowController.close() }
        windowController.showWindow(nil)
        store.setRightSidebarVisible(false)
        flushFloatingOutlineLayout(windowController.window)

        let splitController = try #require(
            windowController.window?.contentViewController as? SplitViewController
        )
        let floatingOutline = splitController.readerWorkspaceViewController.floatingOutlineViewController
        let reader = splitController.readerViewController
        #expect(floatingOutline.testingIsPresented)

        reader.setAllPagesOverviewActive(true)
        flushFloatingOutlineLayout(windowController.window)
        #expect(reader.isAllPagesOverviewActive)
        #expect(floatingOutline.testingIsPresented == false)

        reader.setAllPagesOverviewActive(false)
        flushFloatingOutlineLayout(windowController.window)
        #expect(reader.isAllPagesOverviewActive == false)
        #expect(floatingOutline.testingIsPresented)
    }

    @Test
    func continuousReadingFloatingOutlineNavigatesAcrossDocuments() throws {
        _ = NSApplication.shared
        let store = makeIsolatedDocumentStore()
        let sessions = try store.open(
            documentsAt: [
                makeFloatingOutlinePDF(named: "floating-continuous-first"),
                makeFloatingOutlinePDF(named: "floating-continuous-second"),
            ],
            in: store.defaultWindowID
        )
        #expect(store.startContinuousReadingFromSelectedSessions(in: store.defaultWindowID))
        store.setRightSidebarVisible(false)
        let controller = FloatingOutlineViewController(
            documentStore: store,
            windowID: store.defaultWindowID
        )
        controller.loadViewIfNeeded()
        controller.testingSetHovered(true)

        let outlineController = controller.testingOutlineViewController
        var request: OutlineNavigationRequest?
        controller.onNavigationRequested = { request = $0 }
        outlineController.view.frame = NSRect(x: 0, y: 0, width: 292, height: 420)
        outlineController.view.layoutSubtreeIfNeeded()
        let rows = floatingOutlineRows(in: outlineController.view)
        #expect(rows.count == 8)

        rows[6].performPrimaryAction()

        #expect(request == OutlineNavigationRequest(
            sessionID: sessions[1].id,
            position: ReadingPosition(pageIndex: 1, point: CGPoint(x: 20, y: 190))
        ))
    }
}

@MainActor
private func makeFloatingOutlinePDF(named name: String) throws -> URL {
    let rootDirectory = try TestPDFFixtures.makeRootDirectory(prefix: "serein-floating-outline")
    let url = rootDirectory.appendingPathComponent("\(name).pdf")
    let document = TestPDFFixtures.makeBlankDocument(pageCount: 3)

    let root = PDFOutline()
    let first = PDFOutline()
    first.label = "Introduction"
    first.destination = PDFDestination(page: document.page(at: 0)!, at: CGPoint(x: 10, y: 210))
    let child = PDFOutline()
    child.label = "Background"
    child.destination = PDFDestination(page: document.page(at: 1)!, at: CGPoint(x: 20, y: 190))
    first.insertChild(child, at: 0)
    let second = PDFOutline()
    second.label = "Conclusion"
    second.destination = PDFDestination(page: document.page(at: 2)!, at: CGPoint(x: 30, y: 170))
    root.insertChild(first, at: 0)
    root.insertChild(second, at: 1)
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func makeLongFloatingOutlinePDF(named name: String) throws -> URL {
    let rootDirectory = try TestPDFFixtures.makeRootDirectory(prefix: "serein-floating-outline")
    let url = rootDirectory.appendingPathComponent("\(name).pdf")
    let document = TestPDFFixtures.makeBlankDocument(pageCount: 3)
    let root = PDFOutline()

    for index in 0..<32 {
        let item = PDFOutline()
        item.label = "Section \(index + 1)"
        item.destination = PDFDestination(
            page: document.page(at: index % 3)!,
            at: CGPoint(x: 20, y: 200 - index)
        )
        root.insertChild(item, at: index)
    }
    document.outlineRoot = root

    guard document.write(to: url) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return url
}

@MainActor
private func floatingOutlineView(identifier: String, in root: NSView) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }
    for subview in root.subviews {
        if let match = floatingOutlineView(identifier: identifier, in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private func floatingOutlineRows(in root: NSView) -> [OutlineRowView] {
    var rows: [OutlineRowView] = []
    if let row = root as? OutlineRowView {
        rows.append(row)
    }
    for subview in root.subviews {
        rows.append(contentsOf: floatingOutlineRows(in: subview))
    }
    return rows.sorted { $0.frame.minY < $1.frame.minY }
}

@MainActor
private func renderedColor(of searchField: NSSearchField, at point: NSPoint) throws -> NSColor {
    let pixelWidth = Int(searchField.bounds.width)
    let pixelHeight = Int(searchField.bounds.height)
    let bytesPerRow = pixelWidth * 4
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    searchField.cell?.draw(withFrame: searchField.bounds, in: searchField)
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let pixelData = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let pixelOffset = Int(point.y) * bytesPerRow + Int(point.x) * 4
    let alpha = CGFloat(pixelData[pixelOffset + 3]) / 255
    try #require(alpha > 0)
    return NSColor(
        srgbRed: CGFloat(pixelData[pixelOffset]) / 255 / alpha,
        green: CGFloat(pixelData[pixelOffset + 1]) / 255 / alpha,
        blue: CGFloat(pixelData[pixelOffset + 2]) / 255 / alpha,
        alpha: alpha
    )
}

private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    let lhsRGB = lhs.usingColorSpace(.sRGB)!
    let rhsRGB = rhs.usingColorSpace(.sRGB)!
    return abs(lhsRGB.redComponent - rhsRGB.redComponent)
        + abs(lhsRGB.greenComponent - rhsRGB.greenComponent)
        + abs(lhsRGB.blueComponent - rhsRGB.blueComponent)
}

@MainActor
private func flushFloatingOutlineLayout(_ window: NSWindow?) {
    window?.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    window?.layoutIfNeeded()
}
