import AppKit
import PDFKit

/// Locates painted images without decoding their pixels while the context menu opens.
enum PDFEmbeddedImageService {
    struct Region {
        let page: PDFPage
        let bounds: CGRect
        fileprivate let clips: [Clip]
        fileprivate let scale: CGFloat

        func image() -> NSImage? {
            guard let pageRef = page.pageRef else { return nil }
            let rotation = CGAffineTransform(rotationAngle: -CGFloat(page.rotation) * .pi / 180)
            let rotatedBounds = bounds.applying(rotation)
            // Bound clipboard allocations even for unusually large scanned pages.
            let renderScale = min(scale, 8192 / max(rotatedBounds.width, rotatedBounds.height),
                                  sqrt(16_000_000 / (rotatedBounds.width * rotatedBounds.height)))
            let width = max(1, Int(ceil(rotatedBounds.width * renderScale)))
            let height = max(1, Int(ceil(rotatedBounds.height * renderScale)))
            guard let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.scaleBy(x: renderScale, y: renderScale)
            context.translateBy(x: -rotatedBounds.minX, y: -rotatedBounds.minY)
            context.concatenate(rotation)
            for clip in clips {
                context.addPath(clip.path)
                context.clip(using: clip.rule)
            }
            // Quartz resolves masks and PDF color spaces; retain the visible content of the image area.
            context.drawPDFPage(pageRef)
            guard let image = context.makeImage() else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: width, height: height))
        }
    }

    static func region(at point: CGPoint, on page: PDFPage) -> Region? {
        guard page.document?.allowsCopying != false, let pageRef = page.pageRef,
              pageRef.getBoxRect(.cropBox).contains(point) else { return nil }
        let stream = CGPDFContentStreamCreateWithPage(pageRef)
        defer { CGPDFContentStreamRelease(stream) }
        let scanner = ImageScanner(point: point, page: page,
            state: GraphicsState(clips: [Clip(path: CGPath(rect: pageRef.getBoxRect(.cropBox),
                                                         transform: nil))]))
        var dictionary = pageRef.dictionary
        var parents: Set<UInt> = []
        while let current = dictionary, parents.insert(UInt(bitPattern: current.rawValue)).inserted {
            if CGPDFDictionaryGetDictionary(current, "Resources", &scanner.resources) { break }
            CGPDFDictionaryGetDictionary(current, "Parent", &dictionary)
            if dictionary == current { break }
        }
        return scanner.scan(stream) ? scanner.result : nil
    }

    fileprivate struct Clip {
        let path: CGPath
        var rule: CGPathFillRule = .winding
    }

    private struct GraphicsState {
        var transform: CGAffineTransform = .identity
        var clips: [Clip]
    }

    private final class ImageScanner {
        let point: CGPoint
        let page: PDFPage
        var state: GraphicsState
        var savedStates: [GraphicsState] = []
        var path = CGMutablePath()
        var pendingClip: CGPathFillRule?
        var ancestors: Set<UInt> = []
        var resources: CGPDFDictionaryRef?
        var result: Region?
        var succeeded = true

        init(point: CGPoint, page: PDFPage, state: GraphicsState) {
            self.point = point
            self.page = page
            self.state = state
        }

        func scan(_ stream: CGPDFContentStreamRef) -> Bool {
            let info = Unmanaged.passUnretained(self).toOpaque()
            let scanner = CGPDFScannerCreate(stream, Self.operators, info)
            defer { CGPDFScannerRelease(scanner) }
            return CGPDFScannerScan(scanner) && succeeded
        }

        static func owner(_ info: UnsafeMutableRawPointer?) -> ImageScanner {
            Unmanaged<ImageScanner>.fromOpaque(info!).takeUnretainedValue()
        }

        static func numbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat]? {
            var values = [CGFloat](repeating: 0, count: count)
            for index in (0..<count).reversed() {
                var value: CGPDFReal = 0
                guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
                values[index] = CGFloat(value)
            }
            return values
        }

        func finishPath() {
            if let pendingClip {
                state.clips.append(Clip(path: path.copy()!, rule: pendingClip))
            }
            pendingClip = nil
            path = CGMutablePath()
        }

        func recordImage(_ dictionary: CGPDFDictionaryRef, inline: Bool = false) {
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            let hasWidth = CGPDFDictionaryGetInteger(dictionary, "Width", &width)
                || (inline && CGPDFDictionaryGetInteger(dictionary, "W", &width))
            let hasHeight = CGPDFDictionaryGetInteger(dictionary, "Height", &height)
                || (inline && CGPDFDictionaryGetInteger(dictionary, "H", &height))
            guard hasWidth, hasHeight, width > 0, height > 0 else { return }
            var transform = state.transform
            let imagePath = CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1), transform: &transform)
            let clips = state.clips + [Clip(path: imagePath)]
            guard clips.allSatisfy({ $0.path.contains(point, using: $0.rule) }) else { return }
            let bounds = clips.reduce(imagePath.boundingBoxOfPath) { $0.intersection($1.path.boundingBoxOfPath) }
            guard bounds.isNull == false, bounds.width > 0, bounds.height > 0 else { return }
            let xLength = hypot(transform.a, transform.b)
            let yLength = hypot(transform.c, transform.d)
            guard xLength > 0, yLength > 0 else { return }
            // Prefer the original pixel density, with at least the existing page-copy density.
            result = Region(page: page, bounds: bounds, clips: clips,
                            scale: max(2, CGFloat(width) / xLength, CGFloat(height) / yLength))
        }

        func drawObject(_ scanner: CGPDFScannerRef) {
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
            switch String(cString: subtype) {
            case "Image": recordImage(dictionary)
            case "Form":
                // A malformed recursive Form must not keep the reader in an unbounded scan.
                let identity = UInt(bitPattern: stream.rawValue)
                guard ancestors.contains(identity) == false else { succeeded = false; return }
                let child = ImageScanner(point: point, page: page, state: state)
                child.ancestors = ancestors.union([identity])
                var matrix: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrix), let matrix {
                    var values = [CGPDFReal](repeating: 0, count: 6)
                    guard values.indices.allSatisfy({ CGPDFArrayGetNumber(matrix, $0, &values[$0]) && values[$0].isFinite }) else {
                        succeeded = false; return
                    }
                    child.state.transform = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                        d: values[3], tx: values[4], ty: values[5]).concatenating(state.transform)
                }
                var bbox: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dictionary, "BBox", &bbox), let bbox {
                    var values = [CGPDFReal](repeating: 0, count: 4)
                    guard values.indices.allSatisfy({ CGPDFArrayGetNumber(bbox, $0, &values[$0]) && values[$0].isFinite }) else {
                        succeeded = false; return
                    }
                    let box = CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
                    var transform = child.state.transform
                    child.state.clips.append(Clip(path: CGPath(rect: box, transform: &transform)))
                }
                var ownResources: CGPDFDictionaryRef?
                CGPDFDictionaryGetDictionary(dictionary, "Resources", &ownResources)
                child.resources = ownResources ?? resources
                guard let resources = child.resources else { return }
                let content = CGPDFContentStreamCreateWithStream(stream, resources, CGPDFScannerGetContentStream(scanner))
                defer { CGPDFContentStreamRelease(content) }
                guard child.scan(content) else { succeeded = false; return }
                if let result = child.result { self.result = result }
            default: break
            }
        }

        // Registered once, then only read by independent page scanners.
        nonisolated(unsafe) static let operators: CGPDFOperatorTableRef = {
            let table = CGPDFOperatorTableCreate()!
            CGPDFOperatorTableSetCallback(table, "q") { _, info in
                let owner = owner(info); owner.savedStates.append(owner.state)
            }
            CGPDFOperatorTableSetCallback(table, "Q") { _, info in
                let owner = owner(info)
                if let state = owner.savedStates.popLast() { owner.state = state }
            }
            CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
                guard let values = numbers(scanner, count: 6) else { return }
                let owner = owner(info)
                owner.state.transform = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                    d: values[3], tx: values[4], ty: values[5]).concatenating(owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in owner(info).drawObject(scanner) }
            CGPDFOperatorTableSetCallback(table, "EI") { scanner, info in
                var stream: CGPDFStreamRef?
                if CGPDFScannerPopStream(scanner, &stream), let stream,
                   let dictionary = CGPDFStreamGetDictionary(stream) { owner(info).recordImage(dictionary, inline: true) }
            }
            CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
                guard let v = numbers(scanner, count: 2) else { return }
                let owner = owner(info)
                owner.path.move(to: CGPoint(x: v[0], y: v[1]), transform: owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
                guard let v = numbers(scanner, count: 2) else { return }
                let owner = owner(info)
                owner.path.addLine(to: CGPoint(x: v[0], y: v[1]), transform: owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
                guard let v = numbers(scanner, count: 6) else { return }
                let owner = owner(info)
                owner.path.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]),
                                    control2: CGPoint(x: v[2], y: v[3]), transform: owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
                guard let v = numbers(scanner, count: 4) else { return }
                let owner = owner(info)
                owner.path.addCurve(to: CGPoint(x: v[2], y: v[3]).applying(owner.state.transform),
                    control1: owner.path.currentPoint, control2: CGPoint(x: v[0], y: v[1]).applying(owner.state.transform))
            }
            CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
                guard let v = numbers(scanner, count: 4) else { return }
                let owner = owner(info)
                owner.path.addCurve(to: CGPoint(x: v[2], y: v[3]), control1: CGPoint(x: v[0], y: v[1]),
                    control2: CGPoint(x: v[2], y: v[3]), transform: owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "h") { _, info in owner(info).path.closeSubpath() }
            CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
                guard let v = numbers(scanner, count: 4) else { return }
                let owner = owner(info)
                owner.path.addRect(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]), transform: owner.state.transform)
            }
            CGPDFOperatorTableSetCallback(table, "W") { _, info in owner(info).pendingClip = .winding }
            CGPDFOperatorTableSetCallback(table, "W*") { _, info in owner(info).pendingClip = .evenOdd }
            for operation in ["n", "S", "s", "f", "F", "f*", "B", "B*", "b", "b*"] {
                CGPDFOperatorTableSetCallback(table, operation) { _, info in owner(info).finishPath() }
            }
            return table
        }()
    }
}
