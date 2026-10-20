import Foundation
import NaturalLanguage

enum LanguageDetection {
    /// Detects the dominant language of `text` on-device. Returns nil when the
    /// text is too short or ambiguous to tell.
    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: language.rawValue)
    }

    /// The language's own name, e.g. "日本語" for Japanese.
    static func nativeName(of language: Locale.Language) -> String {
        let id = language.maximalIdentifier
        let locale = Locale(identifier: id)
        return locale.localizedString(forLanguageCode: language.languageCode?.identifier ?? id)?
            .capitalized(with: locale) ?? id
    }

    /// The language's name in the app's own language, e.g. "英語" for English
    /// when Emebal is in Japanese. Reads better than the native name inside a
    /// sentence.
    static func name(of language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.maximalIdentifier
        return appLocale.localizedString(forLanguageCode: code) ?? nativeName(of: language)
    }

    /// The language Emebal's interface is shown in, which can differ from the
    /// Mac's region format (`Locale.current`).
    private static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// Whether two languages are the same for translation purposes
    /// (e.g. "en" and "en-US" are).
    static func isSame(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode && (a.script == nil || b.script == nil || a.script == b.script)
    }
}
