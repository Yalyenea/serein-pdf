import AppKit
@testable import Serein

@MainActor
func waitForChromeLayout(in window: NSWindow?, timeout: TimeInterval = 1.5) -> Bool {
    guard let split = window?.contentViewController as? SplitViewController else { return true }
    let deadline = Date(timeIntervalSinceNow: timeout)
    while split.testingIsApplyingChromeLayout, Date() < deadline {
        window?.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    window?.layoutIfNeeded()
    return !split.testingIsApplyingChromeLayout
}

@MainActor
func findDescendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
    if let match = root as? T {
        return match
    }
    for subview in root.subviews {
        if let match = findDescendant(of: type, in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
func findButton(titled title: String, in root: NSView) -> NSButton? {
    if let button = root as? NSButton, button.title == title {
        return button
    }
    for subview in root.subviews {
        if let button = findButton(titled: title, in: subview) {
            return button
        }
    }
    return nil
}

@MainActor
func findTextField(matching stringValue: String, in root: NSView) -> NSTextField? {
    if let textField = root as? NSTextField, textField.stringValue == stringValue {
        return textField
    }
    for subview in root.subviews {
        if let textField = findTextField(matching: stringValue, in: subview) {
            return textField
        }
    }
    return nil
}

@MainActor
func findView(identifier: String, in root: NSView) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }
    for subview in root.subviews {
        if let match = findView(identifier: identifier, in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
func findAllDescendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
    var matches = (root as? T).map { [$0] } ?? []
    for subview in root.subviews {
        matches.append(contentsOf: findAllDescendants(of: type, in: subview))
    }
    return matches
}
