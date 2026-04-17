import AppKit

@MainActor
final class ThemeManager {
    private(set) var readerState = ReaderState()

    func toggleNightMode() {
        readerState.isNightModeEnabled.toggle()
    }
}
