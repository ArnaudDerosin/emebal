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

    @Test("The improvement prompt keeps the draft's language and includes the text")
    func improvementPrompt() {
        let draft = "PR has been sent upstream to prevent patch on our side.."
        let prompt = ClaudeTranslator.improvementPrompt(for: draft)
        #expect(prompt.contains("don't translate it"))
        #expect(prompt.hasSuffix(draft))
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

    @Test("Reads a piece of the translation from a single line, as it streams in")
    func textPieceFromLine() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"It looks"}}}"#
        #expect(ClaudeTranslator.textPiece(fromLine: line) == "It looks")
        let start = #"{"type":"stream_event","event":{"type":"message_start"}}"#
        #expect(ClaudeTranslator.textPiece(fromLine: start) == nil)
        #expect(ClaudeTranslator.textPiece(fromLine: #"{"type":"result","result":"x"}"#) == nil)
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
        let textArrival = UsageArrival()
        let result = try await ClaudeTranslator.translate(
            "`isStarted` を待っている間に abort されると、60 秒のタイムアウトまで待つようです。",
            into: TargetLanguage(id: "en"),
            model: .sonnet,
            onUsage: { _ in usageArrival.record() },
            onText: { _ in textArrival.record() }
        )
        let finished = Date()
        #expect(result.text.contains("`isStarted`"))
        // The usage arrives while Claude is still writing the translation.
        if let arrived = usageArrival.date {
            print("Usage arrived \(finished.timeIntervalSince(arrived))s before the translation finished")
            #expect(arrived < finished)
        }
        // The first words arrive while Claude is still writing the rest.
        let firstWords = try #require(textArrival.date)
        print("First words arrived \(finished.timeIntervalSince(firstWords))s before the translation finished")
        #expect(firstWords < finished)
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

/// Runs `ClaudeTranslator` against small shell scripts that stand in for
/// `claude`, to test how it handles a stalled or an older Claude Code.
@Suite("ClaudeTranslator with a stand-in claude")
struct FakeClaudeTests {
    static let result = #"{"type":"result","is_error":false,"result":"Bonjour"}"#

    /// Writes an executable shell script and returns its URL.
    func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try "#!/bin/sh\ncat > /dev/null\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("Stops a Claude Code that prints nothing for too long")
    func stalled() async throws {
        let fake = try script("sleep 30")
        let start = Date()
        await #expect(throws: ClaudeTranslator.Failure.timedOut) {
            try await ClaudeTranslator.translate("Hello", into: TargetLanguage(id: "fr"), model: .sonnet,
                                                 executable: fake, idleTimeout: 1)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("Doesn't stop a slow answer that keeps writing")
    func slowButWriting() async throws {
        // About 6 s in total, longer than the 3 s timeout, but never silent
        // for more than 1 s. The margin covers macOS checking a freshly
        // written script before it starts.
        let fake = try script("""
        for i in 1 2 3 4 5 6; do echo '{"type":"system"}'; sleep 1; done
        echo '\(Self.result)'
        """)
        let translation = try await ClaudeTranslator.translate("Hello", into: TargetLanguage(id: "fr"), model: .sonnet,
                                                               executable: fake, idleTimeout: 3)
        #expect(translation.text == "Bonjour")
    }

    @Test("Falls back to the basic call when Claude Code doesn't know an option")
    func olderClaudeCode() async throws {
        let fake = try script("""
        case "$*" in
          *--tools*) echo "error: unknown option '--tools'" >&2; exit 1 ;;
        esac
        echo '\(Self.result)'
        """)
        let translation = try await ClaudeTranslator.translate("Hello", into: TargetLanguage(id: "fr"), model: .sonnet,
                                                               executable: fake)
        #expect(translation.text == "Bonjour")
    }
}

/// The two-step mode used by Keep Claude Ready: `claude` started first,
/// waiting, and given its text later.
@Suite("Ready Claude Code")
struct ReadyClaudeTests {
    /// A stand-in that waits for one message, like `claude --input-format
    /// stream-json`, then runs `then`.
    func waitingScript(then: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-ready-claude-\(UUID().uuidString)")
        let body = """
        #!/bin/sh
        IFS= read -r line
        case "$line" in
          *'"type":"user"'*) ;;
          *) echo "not a user message" >&2; exit 1 ;;
        esac
        \(then)
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("Waits for its text, then answers it")
    func waitsThenAnswers() async throws {
        let fake = try waitingScript(then: "echo '\(FakeClaudeTests.result)'")
        let runner = ProcessRunner(executable: fake, model: .sonnet, idleTimeout: 1)
        try runner.start(isFull: true, waitsForMessage: true)
        try await Task.sleep(for: .seconds(2))  // Longer than the timeout.
        #expect(runner.isWaiting)
        let output = await runner.send("Translate this", onLine: { _ in })
        #expect(!runner.isWaiting)
        #expect(!output.timedOut)
        #expect(try ClaudeTranslator.parse(output.stdout).text == "Bonjour")
    }

    @Test("Survives a Claude Code that exits before reading its text")
    func exitedBeforeSend() async throws {
        // Exits at once without reading, like a Claude Code that rejects an option.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-exits-\(UUID().uuidString)")
        try "#!/bin/sh\necho 'error: unknown option' >&2\nexit 1\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let runner = ProcessRunner(executable: url, model: .sonnet)
        try runner.start(isFull: true, waitsForMessage: true)
        // macOS may check a freshly written script before running it.
        for _ in 0..<50 where runner.isWaiting {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!runner.isWaiting)
        // Sending to it used to kill the app with SIGPIPE.
        let output = await runner.send(String(repeating: "x", count: 200_000), onLine: { _ in })
        #expect(output.stderr.contains("unknown option"))
    }

    @Test("Times out on silence only after getting its text")
    func timesOutAfterSend() async throws {
        let fake = try waitingScript(then: "sleep 30")
        let runner = ProcessRunner(executable: fake, model: .sonnet, idleTimeout: 1)
        try runner.start(isFull: true, waitsForMessage: true)
        let start = Date()
        let output = await runner.send("Translate this", onLine: { _ in })
        #expect(output.timedOut)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    /// Runs the real `claude` in its waiting mode. Only with EMEBAL_LIVE_TESTS=1.
    @Test(
        "A real Claude Code waits, then translates",
        .enabled(if: ProcessInfo.processInfo.environment["EMEBAL_LIVE_TESTS"] == "1")
    )
    func liveReady() async throws {
        let executable = try #require(await ClaudeLocator.find())
        let prompt = ClaudeTranslator.prompt(for: "Bonjour, comment ça va ?", into: TargetLanguage(id: "en"))
        let runner = ProcessRunner(executable: executable, model: .sonnet)
        try runner.start(isFull: true, waitsForMessage: true)
        try await Task.sleep(for: .seconds(3))
        #expect(runner.isWaiting)
        let sent = Date()
        let firstWords = UsageArrival()
        let output = await runner.send(prompt) { line in
            if ClaudeTranslator.textPiece(fromLine: line) != nil { firstWords.record() }
        }
        let translation = try ClaudeTranslator.parse(output.stdout, errors: output.stderr)
        // The plan usage comes in this mode too.
        #expect(translation.usage != nil)
        print("Ready Claude: first words \(try #require(firstWords.date).timeIntervalSince(sent))s after sending, translation: \(translation.text)")
        #expect(translation.text.lowercased().contains("hello") || translation.text.lowercased().contains("hi"))
    }
}
