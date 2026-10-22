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

    @Test("Recognizes when Claude Code needs a sign-in")
    func notSignedIn() {
        let output = """
        {"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login"}
        """
        #expect(throws: ClaudeTranslator.Failure.notSignedIn) {
            try ClaudeTranslator.parse(output)
        }
        #expect(throws: ClaudeTranslator.Failure.notSignedIn) {
            try ClaudeTranslator.parse("", errors: "Not logged in · Please run /login")
        }
        #expect(!ClaudeTranslator.Failure.isSignInMessage("There's an issue with the selected model."))
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

    @Test("Reads the usage from a single line, as it streams in")
    func usageFromLine() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.07,"resetsAt":1792516200}}}}"#
        #expect(ClaudeTranslator.usage(fromLine: line)?.session?.usedFraction == 0.07)
        #expect(ClaudeTranslator.usage(fromLine: #"{"type":"assistant"}"#) == nil)
        #expect(ClaudeTranslator.usage(fromLine: "not json") == nil)
    }

    @Test("Leaves out the windows that have already reset")
    func currentUsage() {
        let now = Date()
        let usage = ClaudeUsage(
            session: .init(usedFraction: 0.5, resetsAt: now.addingTimeInterval(-60)),
            week: .init(usedFraction: 0.1, resetsAt: now.addingTimeInterval(3600))
        )
        #expect(usage.current(at: now)?.session == nil)
        #expect(usage.current(at: now)?.week?.usedFraction == 0.1)
        #expect(usage.current(at: now.addingTimeInterval(7200)) == nil)
    }

    @Test("Keeps when the usage was reported, through saving and filtering")
    func reportedAt() throws {
        let reported = Date(timeIntervalSince1970: 1792500000)
        let usage = ClaudeUsage(
            session: .init(usedFraction: 0.07, resetsAt: reported.addingTimeInterval(3600)),
            week: nil,
            reportedAt: reported
        )
        #expect(usage.current(at: reported)?.reportedAt == reported)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: JSONEncoder().encode(usage))
        #expect(decoded.reportedAt == reported)
    }

    @Test("Keeps the usage between launches")
    func usageIsCodable() throws {
        let usage = ClaudeUsage(
            session: .init(usedFraction: 0.07, resetsAt: Date(timeIntervalSince1970: 1792516200)),
            week: nil
        )
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: JSONEncoder().encode(usage))
        #expect(decoded == usage)
    }

    /// Runs the real `claude` CLI, so it uses the signed-in Claude account.
    /// Only runs with EMEBAL_LIVE_TESTS=1.
    @Test(
        "Translates through the installed Claude Code",
        .enabled(if: ProcessInfo.processInfo.environment["EMEBAL_LIVE_TESTS"] == "1")
    )
    func liveTranslation() async throws {
        let usageArrival = UsageArrival()
        let result = try await ClaudeTranslator.translate(
            "`isStarted` を待っている間に abort されると、60 秒のタイムアウトまで待つようです。",
            into: TargetLanguage(id: "en"),
            model: .sonnet
        ) { _ in
            usageArrival.record()
        }
        let finished = Date()
        #expect(result.text.contains("`isStarted`"))
        // The usage arrives while Claude is still writing the translation.
        if let arrived = usageArrival.date {
            print("Usage arrived \(finished.timeIntervalSince(arrived))s before the translation finished")
            #expect(arrived < finished)
        }
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

    @Test("Names languages in the app's language, then in their own")
    func displayNames() {
        let english = Locale(identifier: "en")
        #expect(LanguageDetection.displayName(of: .init(identifier: "ja"), in: english) == "Japanese (日本語)")
        #expect(LanguageDetection.displayName(of: .init(identifier: "fr"), in: english) == "French (Français)")
        #expect(LanguageDetection.displayName(of: .init(identifier: "en"), in: english) == "English")

        let japanese = Locale(identifier: "ja")
        #expect(LanguageDetection.displayName(of: .init(identifier: "en"), in: japanese) == "英語 (English)")
        #expect(LanguageDetection.displayName(of: .init(identifier: "ja"), in: japanese) == "日本語")

        // Simplified Chinese keeps its script in both names.
        let chinese = LanguageDetection.displayName(of: .init(identifier: "zh-Hans"), in: english)
        print("zh-Hans in English:", chinese)
        #expect(chinese.contains("Simplified"))
    }

    @Test("Treats regional variants as the same language")
    func sameLanguage() {
        #expect(LanguageDetection.isSame(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en")))
        #expect(!LanguageDetection.isSame(Locale.Language(identifier: "ja"), Locale.Language(identifier: "en")))
    }
}

/// When the usage callback ran, for the live test.
private final class UsageArrival: @unchecked Sendable {
    private let lock = NSLock()
    private var first: Date?

    var date: Date? { lock.withLock { first } }

    func record() {
        lock.withLock {
            if first == nil { first = Date() }
        }
    }
}
