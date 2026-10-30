import AppKit
import PDFKit

/// A one-shot rectangle tool above the reader; PDFKit keeps its normal text selection outside this mode.
final class ReaderAreaSelectionView: NSView {
    private(set) var selectionRect: CGRect?
    var isSelecting: Bool { !isHidden }
    var copyImage: (NSImage) -> Bool = { PDFPageImageService.copyToPasteboard($0) }

    private weak var pdfView: PDFView?
    private var sourceDocument: PDFDocument?
    private var page: PDFPage?
    private var anchor: CGPoint?
    private var pageFrame: CGRect?
    private var outlineColor = NSColor.clear
    private var fillColor = NSColor.clear

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        setAccessibilityLabel(L10n.text("Select an area to copy. Escape cancels.", "拖动框选复制区域，按 Esc 取消。"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isSelecting }
    override var isOpaque: Bool { false }

    @discardableResult
    func begin(in pdfView: PDFView) -> Bool {
        guard let document = pdfView.document, document.allowsCopying, window != nil else { return false }
        cancel()
        self.pdfView = pdfView
        sourceDocument = document
        isHidden = false
        refreshThemeAppearance()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
        return true
    }

    func cancel() {
        guard isSelecting else { return }
        let reader = pdfView
        let restoresFocus = window?.firstResponder === self
        isHidden = true
        selectionRect = nil
        anchor = nil
        page = nil
        pageFrame = nil
        sourceDocument = nil
        pdfView = nil
        if restoresFocus { window?.makeFirstResponder(reader) }
        window?.invalidateCursorRects(for: self)
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey),
                                                  name: NSWindow.didResignKeyNotification, object: window)
        } else {
            cancel()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func windowDidResignKey(_ notification: Notification) { cancel() }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { cancel() }
        super.setFrameSize(newSize)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isSelecting && bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        if isSelecting { addCursorRect(bounds, cursor: .crosshair) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let pdfView, pdfView.document === sourceDocument else { cancel(); return }
        let point = convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: pdfView.convert(point, from: self), nearest: false),
              page.document?.allowsCopying != false, let pageRef = page.pageRef else { return }
        self.page = page
        pageFrame = convert(pdfView.convert(pageRef.getBoxRect(.cropBox), from: page), from: pdfView)
        anchor = point
        selectionRect = nil
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) { updateSelection(with: event) }

    override func mouseUp(with event: NSEvent) {
        updateSelection(with: event)
        guard let pdfView, pdfView.document === sourceDocument, let page, let selectionRect,
              selectionRect.width >= 3, selectionRect.height >= 3 else { cancel(); return }
        let pageRect = pdfView.convert(pdfView.convert(selectionRect, from: self), to: page)
        // End the modal interaction before rendering and writing to the clipboard.
        cancel()
        guard let image = PDFPageImageService.image(from: page, in: pageRect), copyImage(image) else {
            NSSound.beep()
            return
        }
    }

    private func updateSelection(with event: NSEvent) {
        guard let pdfView, pdfView.document === sourceDocument, let page, let anchor,
              let pageRef = page.pageRef else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                          width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
        let pageRect = convert(pdfView.convert(pageRef.getBoxRect(.cropBox), from: page), from: pdfView)
        guard pageRect == pageFrame else { cancel(); return }
        // A drag belongs to the page where it starts, including in two-page and continuous layouts.
        selectionRect = rect.intersection(pageRect).intersection(bounds)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel() }
    }

    override func cancelOperation(_ sender: Any?) { cancel() }
    override func rightMouseDown(with event: NSEvent) { cancel() }
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshThemeAppearance()
    }

    func refreshThemeAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            outlineColor = NightModeStyle.primaryTextColor.withAlphaComponent(0.85)
            fillColor = NightModeStyle.primaryTextColor.withAlphaComponent(0.08)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = selectionRect, !rect.isNull else { return }
        fillColor.setFill()
        rect.fill()
        outlineColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }
}
