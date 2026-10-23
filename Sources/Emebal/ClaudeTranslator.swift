import Foundation

/// A Claude translation, with the plan usage Claude Code reported along with it.
struct ClaudeTranslation: Sendable {
    let text: String
    let usage: ClaudeUsage?
}

/// How much of the user's Claude plan limits is used. Claude Code reports it
/// with each answer, so reading it costs nothing and needs no credentials.
/// Only subscriptions (not API keys) have these limits.
struct ClaudeUsage: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        /// From 0 to 1.
        let usedFraction: Double
        let resetsAt: Date
    }

    /// The 5-hour window, what Claude Code calls the current session.
    let session: Window?
    /// The 7-day window.
    let week: Window?
    /// When Claude Code reported it.
    var reportedAt = Date()

    /// The windows that haven't reset yet at `date`: after a reset, the old
    /// numbers no longer mean anything. Nil when none is left.
    func current(at date: Date) -> ClaudeUsage? {
        let session = session.flatMap { $0.resetsAt > date ? $0 : nil }
        let week = week.flatMap { $0.resetsAt > date ? $0 : nil }
        return session == nil && week == nil ? nil : ClaudeUsage(session: session, week: week, reportedAt: reportedAt)
    }

    /// How long a saved usage is shown in a new panel before fresh numbers
    /// arrive. Older numbers may be out of date (Claude used elsewhere), so a
    /// placeholder is shown instead.
    static let reuseInterval: TimeInterval = 5 * 60

    /// The last known usage, if it's recent enough to show in a new panel.
    static var recent: ClaudeUsage? {
        lastKnown.flatMap { Date().timeIntervalSince($0.reportedAt) < reuseInterval ? $0 : nil }
    }

    /// The last usage Claude Code reported, kept between translations and
    /// launches so a new panel can show it right away.
    static var lastKnown: ClaudeUsage? {
        get {
            UserDefaults.standard.data(forKey: lastKnownKey)
                .flatMap { try? JSONDecoder().decode(ClaudeUsage.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: lastKnownKey)
        }
    }

    private static let lastKnownKey = "lastClaudeUsage"
}

/// Translates by running the user's own, signed-in Claude Code CLI
/// (`claude -p`). Usage counts toward the user's Claude account.
enum ClaudeTranslator {
    enum Failure: LocalizedError, Equatable {
        case notInstalled
        /// Claude Code is installed but has no account to use.
        case notSignedIn
        /// Claude Code printed nothing for `ProcessRunner.idleTimeout`.
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                String(localized: "Claude Code not found. Install it and sign in, or turn Claude off in the menu.")
            case .notSignedIn:
                String(localized: "Claude Code isn't signed in.")
            case .timedOut:
                String(localized: "Claude took too long to answer. Try again.")
            case .failed(let message):
                message.isEmpty ? String(localized: "Claude Code failed.") : message
            }
        }

        /// Claude Code's own messages when it needs a sign-in, e.g. "Invalid
        /// API key · Please run /login".
        static func isSignInMessage(_ message: String) -> Bool {
            let text = message.lowercased()
            return ["/login", "invalid api key", "not logged in"].contains { text.contains($0) }
        }
    }

    /// `onUsage` is called as soon as Claude Code reports the plan usage,
    /// which comes before the translation itself.
    ///
    /// `onText` receives the translation written so far, as Claude writes it,
    /// so it can be shown before it's complete.
    static func translate(
        _ text: String,
        into target: TargetLanguage,
        model: ClaudeModel,
        onUsage: @escaping @Sendable (ClaudeUsage) -> Void = { _ in },
        onText: @escaping @Sendable (String) -> Void = { _ in },
        executable: URL? = nil,
        idleTimeout: TimeInterval = ProcessRunner.idleTimeout
    ) async throws -> ClaudeTranslation {
        // Tests pass their own stand-in `executable`; the app may use a ready
        // Claude Code.
        let isUsingReadyClaude = executable == nil
        var found = executable
        if found == nil {
            found = await ClaudeLocator.find()
        }
        guard let executable = found else {
            throw Failure.notInstalled
        }
        let prompt = prompt(for: text, into: target)

        let written = TextSoFar()
        @Sendable func handle(_ line: String) {
            if let usage = usage(fromLine: line) {
                onUsage(usage)
            } else if let piece = textPiece(fromLine: line) {
                onText(written.appending(piece))
            }
        }

        func send(to runner: ProcessRunner) async -> ProcessOutput {
            await withTaskCancellationHandler {
                await runner.send(prompt, onLine: handle)
            } onCancel: {
                runner.cancel()
            }
        }

        func run(isFull: Bool) async throws -> ProcessOutput {
            let runner = ProcessRunner(executable: executable, model: model, idleTimeout: idleTimeout)
            return try await withTaskCancellationHandler {
                try await runner.run(input: prompt, isFull: isFull, onLine: handle)
            } onCancel: {
                runner.cancel()
            }
        }

        var output: ProcessOutput
        // Claude Code already started and waiting, if the user keeps it ready.
        if isUsingReadyClaude, let ready = await ReadyClaude.shared.take(model: model, executable: executable) {
            output = await send(to: ready)
            if output.stderr.contains("unknown option") {
                // Too old for the waiting mode: translate the normal way.
                await ReadyClaude.shared.markUnsupported()
                output = try await run(isFull: true)
            }
        } else {
            output = try await run(isFull: true)
        }
        // An older Claude Code that doesn't know one of the options: ask again
        // the basic way, which works everywhere (the whole text at the end).
        if output.stderr.contains("unknown option") {
            output = try await run(isFull: false)
        }
        if isUsingReadyClaude {
            // Ready for the next translation.
            await ReadyClaude.shared.prepare(model: model, executable: executable)
        }
        if output.timedOut {
            throw Failure.timedOut
        }
        return try parse(output.stdout, errors: output.stderr)
    }

    /// A piece of the translation in one line of output, if it's a text delta
    /// from `--include-partial-messages`.
    static func textPiece(fromLine line: some StringProtocol) -> String? {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              event["type"] as? String == "stream_event",
              let inner = event["event"] as? [String: Any],
              inner["type"] as? String == "content_block_delta",
              let delta = inner["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta"
        else { return nil }
        return delta["text"] as? String
    }

    /// Reads the JSON lines that `claude -p --output-format stream-json`
    /// prints: the answer is in the `result` event, and the plan usage in the
    /// `rate_limit_event`. The usage format isn't documented, so anything
    /// unexpected there just leaves the usage out.
    static func parse(_ output: String, errors: String = "") throws -> ClaudeTranslation {
        var result: [String: Any]?
        var usage: ClaudeUsage?
        for line in output.split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            switch event["type"] as? String {
            case "result":
                result = event
            case "rate_limit_event":
                usage = parseUsage(event) ?? usage
            default:
                break
            }
        }
        guard let result, let text = result["result"] as? String else {
            let message = errors.isEmpty ? output : errors
            throw Failure.isSignInMessage(message) ? Failure.notSignedIn : Failure.failed(message)
        }
        if result["is_error"] as? Bool == true {
            throw Failure.isSignInMessage(text) ? Failure.notSignedIn : Failure.failed(text)
        }
        return ClaudeTranslation(text: text.trimmingCharacters(in: .whitespacesAndNewlines), usage: usage)
    }

    /// The usage in one line of output, if it's a `rate_limit_event`.
    static func usage(fromLine line: some StringProtocol) -> ClaudeUsage? {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              event["type"] as? String == "rate_limit_event"
        else { return nil }
        return parseUsage(event)
    }

    private static func parseUsage(_ event: [String: Any]) -> ClaudeUsage? {
        let info = event["rate_limit_info"] as? [String: Any]
        guard let windows = info?["unifiedWindows"] as? [String: Any] else { return nil }

        func window(_ name: String) -> ClaudeUsage.Window? {
            guard let window = windows[name] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue,
                  let resetsAt = (window["resetsAt"] as? NSNumber)?.doubleValue
            else { return nil }
            return ClaudeUsage.Window(usedFraction: used, resetsAt: Date(timeIntervalSince1970: resetsAt))
        }

        let usage = ClaudeUsage(session: window("five_hour"), week: window("seven_day"))
        return usage.session == nil && usage.week == nil ? nil : usage
    }

    static func prompt(for text: String, into target: TargetLanguage) -> String {
        """
        You are a professional translator. Translate the text below into \(target.englishName).

        - Write it the way a native speaker would naturally say it: idiomatic, fluent, \
        and with the same tone (casual, polite, technical) as the original. Don't translate word for word.
        - Keep the meaning exact. Don't add, drop or soften anything.
        - Leave code, identifiers, file paths, URLs, error codes and product names exactly as they are. \
        Keep Markdown formatting and lists, and keep the same lines: each line of the text, \
        including empty ones, becomes one line of the translation.
        - If the text is already in \(target.englishName), return it unchanged.

        Output only the translation: no notes, no quotes, no explanations.

        Text:
        \(text)
        """
    }
}

/// Finds the `claude` executable. Apps opened from Finder get a minimal PATH,
/// and installers usually add `claude` to the PATH in ~/.zshrc, which only
/// interactive shells read. So check the usual install locations first, then
/// ask an interactive login shell as a fallback.
enum ClaudeLocator {
    static func find() async -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",          // native installer
            "\(home)/.claude/local/claude",       // older local install
            "/opt/homebrew/bin/claude",           // Homebrew / npm on Apple silicon
            "/usr/local/bin/claude",              // Homebrew / npm on Intel
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        return await findWithInteractiveShell()
    }

    private static func findWithInteractiveShell() async -> URL? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // -i reads ~/.zshrc, where the PATH is usually set.
            process.arguments = ["-ilc", "command -v claude"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            // Shell startup files may print other lines; the path is the last one.
            let path = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .last { $0.hasPrefix("/") }
                .map(String.init)
            guard let path, FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }.value
    }
}

/// The translation written so far, built from the streamed pieces. Lines
/// arrive one after another on a background queue.
private final class TextSoFar: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func appending(_ piece: String) -> String {
        lock.withLock {
            text += piece
            return text
        }
    }
}

/// What `claude` printed. Errors are also reported on stdout, in the
/// `result` event, so both are kept whatever the exit status.
struct ProcessOutput: Sendable {
    let stdout: String
    let stderr: String
    /// Stopped because it printed nothing for too long.
    var timedOut = false
}

/// Runs `claude -p`. Either in one go (`run`), or in two steps: `start`
/// launches it and leaves it waiting for its message, and `send` gives it the
/// text later, so a translation doesn't wait for Claude Code to start (see
/// `ReadyClaude`).
final class ProcessRunner: @unchecked Sendable {
    /// How long `claude` may print nothing once it has its text before it's
    /// stopped. Not a limit on the whole translation: a long one that keeps
    /// streaming is never cut.
    static let idleTimeout: TimeInterval = 60

    /// The options of a full call. A translation needs no tools, MCP servers,
    /// skills or saved session, and leaving them out sends about 90% fewer
    /// tokens, with the same translations.
    static let fullOptions = [
        // The translation in pieces as it's written, to show it early.
        "--include-partial-messages",
        "--tools", "",
        "--strict-mcp-config",
        "--disable-slash-commands",
        "--no-session-persistence",
    ]

    let model: ClaudeModel
    let executable: URL
    private let idleTimeout: TimeInterval
    private let process = Process()
    private let stdin = Pipe()
    private let lock = NSLock()
    private var waitsForMessage = false
    private var isCancelled = false
    private var lastActivity = Date()
    private var timedOut = false
    private var lineHandler: (@Sendable (String) -> Void)?
    private var finished: ProcessOutput?
    private var finishedContinuation: CheckedContinuation<ProcessOutput, Never>?

    /// Writing to a `claude` that has already exited (a waiting one that died,
    /// or an older one that rejected an option) would otherwise kill Emebal
    /// with SIGPIPE. Ignored, the write just fails, and the fallbacks run.
    private static let ignoresBrokenPipes: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    init(executable: URL, model: ClaudeModel, idleTimeout: TimeInterval = ProcessRunner.idleTimeout) {
        _ = Self.ignoresBrokenPipes
        self.executable = executable
        self.model = model
        self.idleTimeout = idleTimeout
    }

    /// Whether it's still running and hasn't been given its text yet.
    var isWaiting: Bool {
        lock.withLock { finished == nil && lineHandler == nil && !isCancelled } && process.isRunning
    }

    /// Launches `claude`. `isFull` adds `fullOptions`; without it, the call
    /// works with older versions of Claude Code too. `waitsForMessage` makes
    /// it wait for a message on standard input instead of reading the whole
    /// input as the prompt (a plain `claude -p` gives up after a few seconds).
    func start(isFull: Bool, waitsForMessage: Bool = false) throws {
        self.waitsForMessage = waitsForMessage
        process.executableURL = executable
        // stream-json (which needs --verbose) is the output that also carries
        // the plan usage.
        process.arguments = ["-p", "--model", model.rawValue, "--output-format", "stream-json", "--verbose"]
            + (waitsForMessage ? ["--input-format", "stream-json"] : [])
            + (isFull ? Self.fullOptions : [])
        // Give `claude` a usable PATH (for example to find `node` when it was
        // installed with npm), since the app's own PATH is minimal.
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment
        // An empty working directory, so no project's CLAUDE.md is picked up.
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("emebal", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workDir

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Read both pipes while the process runs: if nobody reads, a long
        // output fills the pipe buffer and `claude` blocks forever.
        let output = PipeReader(stdout) { [weak self] line in
            self?.handle(line)
        }
        let errors = PipeReader(stderr)

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            let collected = ProcessOutput(
                stdout: output.waitForText(),
                stderr: errors.waitForText(),
                timedOut: lock.withLock { timedOut }
            )
            let continuation = lock.withLock {
                finished = collected
                defer { finishedContinuation = nil }
                return finishedContinuation
            }
            continuation?.resume(returning: collected)
        }

        try lock.withLock {
            if isCancelled { throw CancellationError() }
            try process.run()
        }
        output.start()
        errors.start()
    }

    /// Gives `claude` its text and waits until it's done. `onLine` receives
    /// each line of standard output as soon as it's printed.
    func send(_ input: String, onLine: @escaping @Sendable (String) -> Void) async -> ProcessOutput {
        lock.withLock {
            lineHandler = onLine
            lastActivity = Date()
        }
        let watchdog = startWatchdog()
        defer { watchdog.cancel() }

        let message: String
        if waitsForMessage {
            let user: [String: Any] = ["type": "user", "message": ["role": "user", "content": input]]
            let data = (try? JSONSerialization.data(withJSONObject: user)) ?? Data()
            message = String(decoding: data, as: UTF8.self) + "\n"
        } else {
            message = input
        }
        let handle = stdin.fileHandleForWriting
        try? handle.write(contentsOf: Data(message.utf8))
        try? handle.close()

        return await withCheckedContinuation { continuation in
            let done = lock.withLock { () -> ProcessOutput? in
                if let finished { return finished }
                finishedContinuation = continuation
                return nil
            }
            if let done {
                continuation.resume(returning: done)
            }
        }
    }

    /// Starts `claude` and gives it its text at once.
    func run(input: String, isFull: Bool, onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessOutput {
        try start(isFull: isFull)
        return await send(input, onLine: onLine)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if process.isRunning {
            process.terminate()
        }
    }

    private func handle(_ line: String) {
        let handler = lock.withLock {
            lastActivity = Date()
            return lineHandler
        }
        // Lines printed while waiting for the message (Claude Code starting)
        // have no translation to go to.
        handler?(line)
    }

    /// Stops `claude` when it has printed nothing for `idleTimeout` since it
    /// got its text, so a stalled call doesn't leave the panel on
    /// "Translating…" forever.
    private func startWatchdog() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let interval = min(5, idleTimeout / 2)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock()
            defer { lock.unlock() }
            if process.isRunning, Date().timeIntervalSince(lastActivity) > idleTimeout {
                timedOut = true
                process.terminate()
            }
        }
        timer.resume()
        return timer
    }
}

/// Reads a pipe to the end on a background queue, passing on each complete
/// line as soon as it arrives.
private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let onLine: (@Sendable (String) -> Void)?
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ pipe: Pipe, onLine: (@Sendable (String) -> Void)? = nil) {
        self.pipe = pipe
        self.onLine = onLine
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = self.pipe.fileHandleForReading
            var lineStart = 0
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }  // End of the output.
                self.data.append(chunk)
                guard let onLine = self.onLine else { continue }
                while let newline = self.data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                    onLine(String(decoding: self.data[lineStart..<newline], as: UTF8.self))
                    lineStart = newline + 1
                }
            }
            self.done.signal()
        }
    }

    /// Blocks until the pipe is closed; only call after the process exited.
    func waitForText() -> String {
        done.wait()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
