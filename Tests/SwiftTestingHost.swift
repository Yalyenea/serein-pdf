import CoreFoundation
import Darwin
import Testing

@main
struct SereinSwiftTestingHost {
    static func main() {
        guard let bundlePath = CommandLine.arguments.dropFirst().first else {
            fatalError("Missing test bundle path")
        }
        // Keep the bundle loaded while Testing discovers and executes its test metadata.
        guard dlopen(bundlePath, RTLD_NOW | RTLD_GLOBAL) != nil else {
            fatalError(String(cString: dlerror()))
        }
        Task { @MainActor in
            await Testing.__swiftPMEntryPoint() as Never
        }
        // AppKit may stop a nested run loop while the async test task is still live.
        // Re-enter on the physical main thread until Testing exits with its final result.
        // https://github.com/swiftlang/swift/issues/91716
        while true { CFRunLoopRun() }
    }
}
