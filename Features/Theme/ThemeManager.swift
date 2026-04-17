import AppKit

@MainActor
final class ThemeManager {
    private(set) var readerState = ReaderState()

    func toggleNightMode() {
        readerState.isNightModeEnabled.toggle()
    }

    func setNightModeEnabled(_ isEnabled: Bool) {
        readerState.isNightModeEnabled = isEnabled
    }

    func setHighlightModeEnabled(_ isEnabled: Bool) {
        readerState.isHighlightModeEnabled = isEnabled
    }

    func setHighlightColor(_ color: HighlightColor) {
        readerState.highlightColor = color
    }
}
