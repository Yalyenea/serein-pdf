import AppKit

@MainActor
func makeKeyEvent(
    characters: String,
    keyCode: UInt16 = 0,
    charactersIgnoringModifiers: String? = nil,
    modifierFlags: NSEvent.ModifierFlags = [],
    window: NSWindow? = nil
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: window?.windowNumber ?? 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}

@MainActor
func makeReturnKeyEvent(
    in window: NSWindow,
    modifiers: NSEvent.ModifierFlags = []
) -> NSEvent {
    makeKeyEvent(
        characters: "\r",
        keyCode: 36,
        modifierFlags: modifiers,
        window: window
    )
}
