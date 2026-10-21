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

    @Test("Reads the answer and the plan usage from the stream-json output")
    func parsesStream() throws {
        let output = """
        {"type":"system","subtype":"init","model":"claude-haiku-5-5"}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.06,"resetsAt":1792516200},"seven_day":{"utilization":0.08,"resetsAt":1792670400}}}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Bonjour"}]}}
        {"type":"result","subtype":"success","is_error":false,"result":"Bonjour\\n"}
        """
        let translation = try ClaudeTranslator.parse(output)
        #expect(translation.text == "Bonjour")
        #expect(translation.usage?.session?.usedFraction == 0.06)
        #expect(translation.usage?.session?.resetsAt == Date(timeIntervalSince1970: 1792516200))
        #expect(translation.usage?.week?.usedFraction == 0.08)
    }

    @Test("Leaves the usage out when it's missing or in an unknown format")
    func missingUsage() throws {
        let output = """
        {"type":"rate_limit_event","rate_limit_info":{"something":"else"}}
        {"type":"result","is_error":false,"result":"Hello"}
        """
        let translation = try ClaudeTranslator.parse(output)
        #expect(translation.text == "Hello")
        #expect(translation.usage == nil)
    }

    @Test("Reports Claude Code's error message")
    func parsesError() {
        let output = """
        {"type":"result","subtype":"success","is_error":true,"result":"There's an issue with the selected model."}
        """
        #expect(throws: ClaudeTranslator.Failure.self) {
            try ClaudeTranslator.parse(output, errors: "[claude-code:unrecognized_model]")
        }
        do {
            _ = try ClaudeTranslator.parse(output)
        } catch {
            #expect(error.localizedDescription == "There's an issue with the selected model.")
        }
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
        #expect(result.text.contains("`isStarted`"))
        #expect(result.text.contains("60"))
        #expect(!result.text.contains("待"))
    }
}

@Suite("LanguageDetection")
struct LanguageDetectionTests {
    @Test("Detects Japanese and French")
    func detects() {
        #expect(LanguageDetection.detect("この PR の変更は問題ないと思います。")?.languageCode == "ja")
        #expect(LanguageDetection.detect("Je pense que ce changement est correct.")?.languageCode == "fr")
    }

    @Test("Ignores code when detecting the language of a technical message")
    func ignoresCode() {
        let japanese = """
        ありがとうございます。react-native-ble-manager 12.4.5 の Peripheral.disconnect でも、`sendDisconnectionEvent` → callback.invoke() の順になっていることを確認しました。
        ca79b0f で、`addDisconnectListener` の前に提案どおりのコメントを入れました。あわせて、`BleManager.disconnect` の完了より先にイベントが届く場合 (Android の順番) でも 5 秒待たずに返るテストを足しました。登録を await BleManager.disconnect のあとに動かすと、このテストが落ちることも確かめています。
        """
        #expect(LanguageDetection.detect(japanese)?.languageCode == "ja")

        let korean = "`useEffect` 안에서 fetchUserProfile() 을 호출하면 src/hooks/useUser.ts 의 캐시가 무효화됩니다. PR #1234 에서 확인 부탁드립니다."
        #expect(LanguageDetection.detect(korean)?.languageCode == "ko")

        let chinese = "我在 `UserService.getById()` 里加了缓存，config/cache.yaml 的 ttl_seconds 改成了 300。请帮忙看一下 a1b2c3d 这个提交。"
        #expect(LanguageDetection.detect(chinese)?.languageCode == "zh")

        let french = "J'ai vérifié que `handleSubmit` appelle bien validateForm() avant setIsLoading(true), voir src/components/LoginForm.tsx et le commit 9f8e7d6."
        #expect(LanguageDetection.detect(french)?.languageCode == "fr")

        let english = "I checked that `handleSubmit` calls validateForm() before setIsLoading(true); see src/components/LoginForm.tsx and commit 9f8e7d6."
        #expect(LanguageDetection.detect(english)?.languageCode == "en")
    }

    @Test("Keeps the words glued to code")
    func keepsGluedWords() {
        let text = "BleManager.disconnectの完了を待たずにsendEventを呼ぶと、ca79b0fのテストが落ちます。"
        let prose = LanguageDetection.withoutCode(text)
        #expect(prose.contains("の完了を待たずに"))
        #expect(prose.contains("を呼ぶと、"))
        #expect(prose.contains("のテストが落ちます。"))
        #expect(!prose.contains("disconnect"))
        #expect(!prose.contains("sendEvent"))
        #expect(LanguageDetection.detect(text)?.languageCode == "ja")
    }

    @Test("Treats regional variants as the same language")
    func sameLanguage() {
        #expect(LanguageDetection.isSame(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en")))
        #expect(!LanguageDetection.isSame(Locale.Language(identifier: "ja"), Locale.Language(identifier: "en")))
    }
}
