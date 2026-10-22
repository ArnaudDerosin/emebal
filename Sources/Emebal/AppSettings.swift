import Foundation
import Observation

/// A language the user can translate into.
struct TargetLanguage: Identifiable, Hashable, Sendable {
    /// BCP 47 identifier, e.g. "en", "fr", "zh-Hans".
    let id: String

    /// "French (Français)", shown in menus: see `LanguageDetection.displayName`.
    var displayName: String {
        LanguageDetection.displayName(of: localeLanguage)
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
        case .sonnet: String(localized: "Sonnet (most natural)")
        case .haiku: String(localized: "Haiku (lighter)")
        }
    }
}

/// The size of the texts in the panel, chosen in the menu.
enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }

    /// The original text and the translations.
    var textPointSize: CGFloat {
        switch self {
        case .small: 14
        case .medium: 16
        case .large: 19
        }
    }

    /// Status and error messages, a little smaller than the texts.
    var messagePointSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 14
        case .large: 16
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .small: 3
        case .medium: 4
        case .large: 5
        }
    }

    /// The panel's default width grows with the text, so lines don't wrap
    /// into narrow columns.
    var widthScale: CGFloat {
        switch self {
        case .small: 0.9
        case .medium: 1
        case .large: 1.15
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

    /// Close the panel when the user clicks in another app. Off, the panel
    /// stays until closed (✕ or Esc), so it can be kept aside.
    var closesOnClickOutside: Bool {
        didSet { defaults.set(closesOnClickOutside, forKey: Keys.closesOnClickOutside) }
    }

    var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Keys.textSize) }
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
        closesOnClickOutside = defaults.object(forKey: Keys.closesOnClickOutside) as? Bool ?? true
        textSize = defaults.string(forKey: Keys.textSize).flatMap(TextSize.init(rawValue:)) ?? .medium
        claudeModel = defaults.string(forKey: Keys.claudeModel).flatMap(ClaudeModel.init(rawValue:)) ?? .sonnet
    }

    private enum Keys {
        static let targetLanguage = "targetLanguage"
        static let appleEnabled = "appleEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let sourceShown = "sourceShown"
        static let closesOnClickOutside = "closesOnClickOutside"
        static let textSize = "textSize"
        static let claudeModel = "claudeModel"
    }
}
