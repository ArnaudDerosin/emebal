import Foundation
import NaturalLanguage

enum LanguageDetection {
    /// Detects the dominant language of `text` on-device. Returns nil when the
    /// text is too short or ambiguous to tell.
    ///
    /// Code is left out first: in a Japanese message about code, identifiers
    /// like `sendDisconnectionEvent` can outnumber the Japanese characters and
    /// make the text look English.
    static func detect(_ text: String) -> Locale.Language? {
        let prose = withoutCode(text)
        let recognizer = NLLanguageRecognizer()
        // Pure code has no prose left: then the whole text is all there is.
        recognizer.processString(prose.contains(where: \.isLetter) ? prose : text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: language.rawValue)
    }

    /// The text without what looks like code: code blocks, inline code, URLs,
    /// paths, identifiers (camelCase, snake_case, kebab-case, dotted.names,
    /// calls()), hashes and version numbers.
    static func withoutCode(_ text: String) -> String {
        // Identifiers are ASCII. Japanese or Chinese often follows code with no
        // space ("disconnectの完了"), so word boundaries are spelled out
        // instead of `\b`, which would treat those characters as letters too.
        let before = "(?<![A-Za-z0-9_$])"
        let after = "(?![A-Za-z0-9_$])"
        let identifier = "[A-Za-z_$][A-Za-z0-9_$]*"
        let patterns = [
            "```[\\s\\S]*?```",                                                   // code blocks
            "`[^`\\n]*`",                                                         // inline code
            "[a-z][a-z0-9+.-]*://[!-~]+",                                         // URLs
            "(?:~|\\.{1,2})?(?:/[A-Za-z0-9_.@-]+){2,}/?",                          // paths
            before + identifier + "(?:\\." + identifier + ")+(?:\\(\\))?",          // dotted.names
            before + identifier + "\\(\\)",                                         // calls()
            before + "[a-z]+[A-Z][A-Za-z0-9]*" + after,                            // camelCase
            before + "[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*" + after,                    // PascalCase
            before + "[A-Za-z0-9]*_[A-Za-z0-9_]+" + after,                         // snake_case
            before + "[a-z0-9]+(?:-[a-z0-9]+){2,}" + after,                        // kebab-case
            before + "(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}" + after, // commit hashes
            before + "v?[0-9]+(?:\\.[0-9]+)+" + after,                              // versions
            "#[0-9]+",                                                            // #1234
        ]
        var prose = text
        for pattern in patterns {
            prose = prose.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return prose
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
