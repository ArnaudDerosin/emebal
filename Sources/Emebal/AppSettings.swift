import Foundation
import Observation

/// A language the user can translate into.
struct TargetLanguage: Identifiable, Hashable, Sendable {
    /// BCP 47 identifier, e.g. "en", "fr", "zh-Hans".
    let id: String

    /// The language's own name ("Français", "日本語"), shown in menus.
    var nativeName: String {
        Locale(identifier: id).localizedString(forIdentifier: id)?.capitalized(with: Locale(identifier: id)) ?? id
    }

    /// The English name ("French", "Japanese"), used in the Claude prompt.
    var englishName: String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: id)
    }

    /// Languages supported by both engines.
    static let all: [TargetLanguage] = [
        "en", "fr", "ja", "de", "es", "it", "pt", "ko", "zh-Hans",
    ].map(TargetLanguage.init(id:))
}

enum ClaudeModel: String, CaseIterable, Identifiable, Sendable {
    case sonnet
    case haiku

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet: "Sonnet (most natural)"
        case .haiku: "Haiku (lighter)"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var targetLanguageID: String {
        didSet { defaults.set(targetLanguageID, forKey: Keys.targetLanguage) }
    }

    var isAppleEnabled: Bool {
        didSet { defaults.set(isAppleEnabled, forKey: Keys.appleEnabled) }
    }

    var isClaudeEnabled: Bool {
        didSet { defaults.set(isClaudeEnabled, forKey: Keys.claudeEnabled) }
    }

    /// Show the copied text in its own column, left of the translations.
    var isSourceShown: Bool {
        didSet { defaults.set(isSourceShown, forKey: Keys.sourceShown) }
    }

    var claudeModel: ClaudeModel {
        didSet { defaults.set(claudeModel.rawValue, forKey: Keys.claudeModel) }
    }

    var targetLanguage: TargetLanguage {
        TargetLanguage.all.first { $0.id == targetLanguageID } ?? TargetLanguage(id: "en")
    }

    private init() {
        targetLanguageID = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        isAppleEnabled = defaults.object(forKey: Keys.appleEnabled) as? Bool ?? true
        isClaudeEnabled = defaults.object(forKey: Keys.claudeEnabled) as? Bool ?? true
        isSourceShown = defaults.object(forKey: Keys.sourceShown) as? Bool ?? true
        claudeModel = defaults.string(forKey: Keys.claudeModel).flatMap(ClaudeModel.init(rawValue:)) ?? .sonnet
    }

    private enum Keys {
        static let targetLanguage = "targetLanguage"
        static let appleEnabled = "appleEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let sourceShown = "sourceShown"
        static let claudeModel = "claudeModel"
    }
}
