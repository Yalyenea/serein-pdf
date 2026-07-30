import AppKit

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
