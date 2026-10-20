import Foundation
import Testing
@testable import Emebal

@Suite("ClaudeTranslator")
struct ClaudeTranslatorTests {
    @Test("The prompt names the target language and includes the text")
    func prompt() {
        let prompt = ClaudeTranslator.prompt(for: "こんにちは", into: TargetLanguage(id: "fr"))
        #expect(prompt.contains("into French"))
        #expect(prompt.hasSuffix("こんにちは"))
    }

    /// Runs the real `claude` CLI, so it uses the signed-in Claude account.
    /// Only runs with EMEBAL_LIVE_TESTS=1.
    @Test(
        "Translates through the installed Claude Code",
        .enabled(if: ProcessInfo.processInfo.environment["EMEBAL_LIVE_TESTS"] == "1")
    )
    func liveTranslation() async throws {
        let result = try await ClaudeTranslator.translate(
            "`isStarted` を待っている間に abort されると、60 秒のタイムアウトまで待つようです。",
            into: TargetLanguage(id: "en"),
            model: .sonnet
        )
        #expect(result.contains("`isStarted`"))
        #expect(result.contains("60"))
        #expect(!result.contains("待"))
    }
}

@Suite("LanguageDetection")
struct LanguageDetectionTests {
    @Test("Detects Japanese and French")
    func detects() {
        #expect(LanguageDetection.detect("この PR の変更は問題ないと思います。")?.languageCode == "ja")
        #expect(LanguageDetection.detect("Je pense que ce changement est correct.")?.languageCode == "fr")
    }

    @Test("Treats regional variants as the same language")
    func sameLanguage() {
        #expect(LanguageDetection.isSame(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en")))
        #expect(!LanguageDetection.isSame(Locale.Language(identifier: "ja"), Locale.Language(identifier: "en")))
    }
}
