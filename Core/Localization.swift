import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case automatic
    case english = "en"
    case chinese = "zh"

    var menuTitle: String {
        switch self {
        case .automatic: L10n.text("Automatic", "自动")
        case .english: "English"
        case .chinese: "中文"
        }
    }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .automatic else { return self }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
}

/// UI language is resolved once at launch; settings take effect on the next launch.
enum L10n {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var language = AppLanguage.english
    }
    private static let state = State()

    static func configure(_ language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.language = language.resolved(preferredLanguages: preferredLanguages)
    }

    static func text(_ english: String, _ chinese: String) -> String {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.language == .chinese ? chinese : english
    }
}
