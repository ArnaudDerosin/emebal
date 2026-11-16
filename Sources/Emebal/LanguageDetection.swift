import Foundation
import NaturalLanguage

enum LanguageDetection {
    /// Detects the dominant language of `text` on-device. Returns nil when the
    /// text is too short or ambiguous to tell.
    ///
    /// Code is left out first: in a Japanese message about code, identifiers
    /// like `sendDisconnectionEvent` can outnumber the Japanese characters and
    /// make the text look English.
    ///
    /// When it could be one of several, the languages set on the Mac
    /// (`userLanguages`) win: "燃料電池" is written the same in Japanese and
    /// Traditional Chinese, and is Japanese for someone who reads Japanese.
    static func detect(_ text: String, userLanguages: [String] = Locale.preferredLanguages) -> Locale.Language? {
        var prose = withoutCode(text)
        // Quotes are often in another language: a Japanese note quoting
        // Apple's documentation is still Japanese.
        let unquoted = withoutQuotes(prose)
        if unquoted.contains(where: \.isLetter) {
            prose = unquoted
        }
        if let language = dominantAsianLanguage(prose) {
            return language
        }
        let recognizer = NLLanguageRecognizer()
        // Pure code has no prose left: then the whole text is all there is.
        recognizer.processString(prose.contains(where: \.isLetter) ? prose : text)
        // The recognizer's odds, with the user's own languages counting 3
        // times as much: they win a close call, not a clear one.
        let preferred = Set(userLanguages.map { recognizerCode(of: Locale.Language(identifier: $0)) })
        let best = recognizer.languageHypotheses(withMaximum: 5)
            .filter { $0.key != .undetermined }
            .max { weighted($0, preferred) < weighted($1, preferred) }
        return best.map { Locale.Language(identifier: $0.key.rawValue) }
    }

    private static func weighted(_ hypothesis: (key: NLLanguage, value: Double), _ preferred: Set<String>) -> Double {
        hypothesis.value * (preferred.contains(hypothesis.key.rawValue) ? 3 : 1)
    }

    /// The code the recognizer uses: "ja" for "ja-JP", "zh-Hant" for
    /// "zh-Hant-TW".
    private static func recognizerCode(of language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        guard code == "zh" else { return code }
        return language.script == .hanTraditional ? "zh-Hant" : "zh-Hans"
    }

    /// The text without quotations: "…", “…”, 「…」, 『…』.
    static func withoutQuotes(_ text: String) -> String {
        let patterns = ["\"[^\"]*\"", "“[^”]*”", "「[^」]*」", "『[^』]*』"]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    /// Japanese or Korean, when the text is mostly in it, even with English
    /// words mixed in. The recognizer counts characters, so a Japanese
    /// message full of English terms can look English: "dSYM は beta lane で
    /// gym の直後に Sentry へ上げる" has more Latin letters than Japanese.
    ///
    /// Two signs that the text is Japanese anyway:
    /// - Enough kana and kanji: one says about as much as 2 Latin letters.
    /// - Japanese grammar around the English words: particles and endings in
    ///   hiragana, here は, で, の, に, へ and げる, in several places. English
    ///   quoting a Japanese term or two has hardly any.
    /// English with a few Japanese words stays English.
    private static func dominantAsianLanguage(_ text: String) -> Locale.Language? {
        var kana = 0, hangul = 0, han = 0, latin = 0
        /// Separate stretches of hiragana, and of Latin letters (words).
        var hiraganaRuns = 0, latinWords = 0
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3041...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            default: if isLatin(scalar) { latin += 1 }
            }
            if isHiragana(scalar) && !(previous.map(isHiragana) ?? false) { hiraganaRuns += 1 }
            if isLatin(scalar) && !(previous.map(isLatin) ?? false) { latinWords += 1 }
            previous = scalar
        }
        let isMostlyAsian = (kana + hangul + han) * 2 >= latin
        let hasJapaneseGrammar = hiraganaRuns >= 3 && hiraganaRuns * 2 >= latinWords
        guard isMostlyAsian || hasJapaneseGrammar else { return nil }
        // Kana is only Japanese; Chinese has neither, and is left to the
        // recognizer.
        if kana > 0 && kana >= hangul { return Locale.Language(identifier: "ja") }
        if hangul > 0 { return Locale.Language(identifier: "ko") }
        return nil
    }

    private static func isHiragana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(scalar.value)
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
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
        let id = identifier(of: language)
        let locale = Locale(identifier: id)
        return locale.localizedString(forIdentifier: id).map { capitalizingFirstLetter($0, in: locale) } ?? id
    }

    /// How a language is shown in the interface: its name in the app's
    /// language, then its own name, e.g. "Japanese (日本語)" in English and
    /// "フランス語 (Français)" in Japanese. Just one name when both are the
    /// same, e.g. "English" in English.
    static func displayName(of language: Locale.Language, in appLocale: Locale = appLocale) -> String {
        let id = identifier(of: language)
        let inApp = appLocale.localizedString(forIdentifier: id)
            .map { capitalizingFirstLetter($0, in: appLocale) } ?? nativeName(of: language)
        let native = nativeName(of: language)
        if inApp.caseInsensitiveCompare(native) == .orderedSame {
            return inApp
        }
        return String(localized: "\(inApp) (\(native))", comment: "A language's name in the app's language, then its own name.")
    }

    /// "ja", "en", "zh-Hans": the language code, plus the script when it
    /// matters for the name. `Locale.Language` always fills in a script
    /// (Latin for English), so it's kept only when it isn't the language's
    /// usual one, or for Chinese, where Simplified and Traditional are both
    /// common and must be told apart.
    private static func identifier(of language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return language.minimalIdentifier }
        guard let script = language.script else { return code }
        let usualScript = Locale.Language(identifier: code).script
        return script != usualScript || code == "zh" ? "\(code)-\(script.identifier)" : code
    }

    /// "japonais" → "Japonais": names start a menu item or a label.
    private static func capitalizingFirstLetter(_ name: String, in locale: Locale) -> String {
        name.prefix(1).uppercased(with: locale) + name.dropFirst()
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
