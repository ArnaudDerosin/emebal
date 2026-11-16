import Foundation

/// Japanese written in Latin letters (Hepburn romaji), like the reading
/// Google Translate shows under Japanese text: "東京に行きたいです" →
/// "Tōkyō ni ikitai desu".
///
/// All on-device: macOS's Japanese tokenizer splits the text into words and
/// gives each one's reading, including kanji. Its raw output is close to
/// romaji but not quite ("ha" for the particle は, "i~tsu" for 行っ), so it's
/// tidied up here into words as a learner reads them.
enum Romaji {
    /// The romaji for `text`, or nil when it has no Japanese in it.
    static func of(_ text: String) -> String? {
        let words = mergingCode(tokens(of: text))
        guard words.contains(where: \.isJapanese) else { return nil }
        return capitalizingSentences(join(words))
    }

    // MARK: Words

    private struct Token {
        /// The text as written, e.g. "行っ".
        let surface: String
        /// The tokenizer's reading, e.g. "i~tsu"; nil for spaces.
        let reading: String?

        var isJapanese: Bool { surface.unicodeScalars.contains(where: Romaji.isJapanese) }
        var hasKanji: Bool { surface.unicodeScalars.contains(where: Romaji.isKanji) }
        var isSpace: Bool { surface.allSatisfy(\.isWhitespace) }
    }

    private static func tokens(of text: String) -> [Token] {
        let string = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: string.length),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var tokens: [Token] = []
        var end = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Keep anything the tokenizer skipped, such as line breaks.
            if range.location > end {
                tokens.append(Token(surface: string.substring(with: NSRange(location: end, length: range.location - end)), reading: nil))
            }
            let surface = string.substring(with: NSRange(location: range.location, length: range.length))
            let reading = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            tokens.append(Token(surface: surface, reading: reading))
            end = range.location + range.length
        }
        if end < string.length {
            tokens.append(Token(surface: string.substring(from: end), reading: nil))
        }
        return tokens
    }

    /// The tokenizer splits code like `sendEvent()` into pieces: put back
    /// together what was written with no Japanese or space in between.
    private static func mergingCode(_ tokens: [Token]) -> [Token] {
        var merged: [Token] = []
        for token in tokens {
            if let last = merged.last, isPlain(last), isPlain(token) {
                merged[merged.count - 1] = Token(surface: last.surface + token.surface, reading: nil)
            } else {
                merged.append(token)
            }
        }
        return merged
    }

    /// Not Japanese, full-width or a space: ASCII and other scripts.
    private static func isPlain(_ token: Token) -> Bool {
        !token.isSpace && token.surface.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
    }

    /// Endings that are never words on their own: "行きます" is "ikimasu".
    private static let suffixes: Set<String> = [
        "ます", "まし", "ませ", "ましょ", "たい", "たく", "たかっ", "たけれ", "られ", "させ",
    ]
    /// Endings joined to a verb or adjective before them: "書いて" is
    /// "kaite", but "お金がない" stays "okane ga nai".
    private static let inflections: Set<String> = [
        "て", "た", "ない", "なかっ", "なく", "なけれ", "れ", "せ", "たら", "たり", "ん", "ば", "う", "よう",
    ]

    private static func join(_ tokens: [Token]) -> String {
        var result = ""
        /// The previous word, while it may still take an ending.
        var previous: Token?
        var previousWasEnding = false
        /// After a small っ: the next word starts with a doubled consonant.
        var isDoubling = false
        /// Before the next word: a space, or a line break kept from the text.
        var pendingSeparator: String?

        for token in tokens {
            if token.isSpace {
                if token.surface.contains(where: \.isNewline) {
                    pendingSeparator = String(token.surface.filter(\.isNewline))
                } else if pendingSeparator == nil {
                    pendingSeparator = " "
                }
                previous = nil
                isDoubling = false
                continue
            }
            if let punctuation = punctuation(token.surface) {
                if punctuation.isOpening {
                    result += (result.isEmpty ? "" : pendingSeparator ?? " ") + punctuation.text
                    pendingSeparator = ""
                } else {
                    result += punctuation.text
                    pendingSeparator = punctuation.spaceAfter ? nil : ""
                }
                previous = nil
                isDoubling = false
                continue
            }

            var word = romanize(token)
            let isEnding = token.isJapanese && previous.map { joins(token, after: $0, previousWasEnding: previousWasEnding) } ?? false
            if isDoubling {
                word = doublingFirstConsonant(of: word)
            }
            if !(isDoubling || isEnding) && !result.isEmpty {
                result += pendingSeparator ?? " "
            }
            pendingSeparator = nil

            // A small っ at the end doubles the next word's consonant instead.
            isDoubling = token.isJapanese && word.hasSuffix("~tsu")
            if isDoubling { word.removeLast(4) }
            result += tidy(word)

            previousWasEnding = isEnding
            previous = token.isJapanese ? token : nil
        }
        return result
    }

    private static func joins(_ token: Token, after previous: Token, previousWasEnding: Bool) -> Bool {
        if suffixes.contains(token.surface) { return true }
        // The polite prefix: "お金" is "okane".
        if previous.surface == "お" || previous.surface == "ご" { return true }
        let isVerb = previous.hasKanji || previousWasEnding
        if inflections.contains(token.surface) { return isVerb }
        // "読んで", "飛んだ": で and だ after ん, but "学校で" stays apart.
        if token.surface == "で" || token.surface == "だ" { return isVerb && previous.surface.hasSuffix("ん") }
        return false
    }

    /// One word in romaji, before `tidy`.
    private static func romanize(_ token: Token) -> String {
        // English, code, numbers: as written, in plain ASCII width.
        guard token.isJapanese, var reading = token.reading else {
            return token.surface.precomposedStringWithCompatibilityMapping
        }
        reading = reading.lowercased()
        if let special = specialReadings[token.surface] { return special }
        // Particles are written as they're said.
        switch token.surface {
        case "は": return "wa"
        case "へ": return "e"
        case "を": return "o"
        default: break
        }
        // "では", "には", "こんにちは": は at the end of a kana word is the particle.
        if token.surface.hasSuffix("は"), !token.hasKanji, reading.hasSuffix("ha") {
            reading = String(reading.dropLast(2)) + "wa"
        }
        // Long vowels in kanji words: "toukyou" → "tōkyō". Not a final う
        // written in kana, which is a verb ending: "思う" stays "omou".
        if token.hasKanji {
            let keepsLast = token.surface.hasSuffix("う")
            var body = keepsLast ? String(reading.dropLast(2)) : reading
            let tail = keepsLast ? String(reading.suffix(2)) : ""
            body = body.replacingOccurrences(of: "ou", with: "ō").replacingOccurrences(of: "uu", with: "ū")
            reading = body + tail
        }
        return reading
    }

    /// Where the tokenizer's usual reading isn't the everyday one.
    private static let specialReadings: [String: String] = [
        "私": "watashi",
    ]

    /// Small kana: "vu~aiorin" → "vaiorin", "u~iki" → "wiki", "ne~e" → "nē".
    private static func tidy(_ word: String) -> String {
        guard word.contains("~") else { return word }
        var word = word
        for (from, to) in [("vu~", "v"), ("u~i", "wi"), ("u~e", "we"), ("u~o", "wo"),
                           ("a~a", "ā"), ("i~i", "ī"), ("u~u", "ū"), ("e~e", "ē"), ("o~o", "ō"),
                           ("~tsu", "")] {
            word = word.replacingOccurrences(of: from, with: to)
        }
        // Anything else, e.g. "fu~a": drop the vowel the small kana replaces.
        word = word.replacingOccurrences(of: "[aiueo]~", with: "", options: .regularExpression)
        return word.replacingOccurrences(of: "~", with: "")
    }

    /// "te" → "tte", "chotto" style: "chi" → "tchi".
    private static func doublingFirstConsonant(of word: String) -> String {
        guard let first = word.first, first.isLetter, !"aiueoāīūēō".contains(first) else { return word }
        return (word.hasPrefix("ch") ? "t" : String(first)) + word
    }

    // MARK: Punctuation

    private struct Punctuation {
        let text: String
        let isOpening: Bool
        let spaceAfter: Bool
    }

    private static func punctuation(_ surface: String) -> Punctuation? {
        guard !surface.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        switch surface {
        case "「", "『": return Punctuation(text: "\"", isOpening: true, spaceAfter: false)
        case "」", "』": return Punctuation(text: "\"", isOpening: false, spaceAfter: true)
        case "（", "(", "［", "[", "【": return Punctuation(text: "(", isOpening: true, spaceAfter: false)
        case "）", ")", "］", "]", "】": return Punctuation(text: ")", isOpening: false, spaceAfter: true)
        case "。", "．": return Punctuation(text: ".", isOpening: false, spaceAfter: true)
        case "、", "，": return Punctuation(text: ",", isOpening: false, spaceAfter: true)
        case "・": return Punctuation(text: " ", isOpening: false, spaceAfter: false)
        case "〜", "～": return Punctuation(text: "~", isOpening: false, spaceAfter: true)
        default:
            let text = surface.precomposedStringWithCompatibilityMapping
            // ! ? : ; … stick to the word before; anything else, like a
            // dash or a slash, is a word of its own.
            if text.allSatisfy({ "!?:;….,".contains($0) }) {
                return Punctuation(text: text, isOpening: false, spaceAfter: true)
            }
            return nil
        }
    }

    /// A capital at the start of each sentence, as Google Translate does.
    private static func capitalizingSentences(_ text: String) -> String {
        var result = ""
        var startsSentence = true
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if startsSentence, character.isLetter {
                // "iOS", "iPhone": already capitalized as they should be.
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                result += next.isUppercase ? String(character) : character.uppercased()
                startsSentence = false
                continue
            }
            result.append(character)
            if ".!?".contains(character) || character.isNewline {
                startsSentence = true
            } else if !character.isWhitespace && character != "\"" && character != "(" {
                startsSentence = false
            }
        }
        return result
    }

    // MARK: Characters

    private static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true  // kana
        default: isKanji(scalar)
        }
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x3005: true  // 々 too
        default: false
        }
    }
}
