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
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                String(localized: "Claude Code not found. Install it and sign in, or turn Claude off in the menu.")
            case .notSignedIn:
                String(localized: "Claude Code isn't signed in.")
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
    static func translate(
        _ text: String,
        into target: TargetLanguage,
        model: ClaudeModel,
        onUsage: @escaping @Sendable (ClaudeUsage) -> Void = { _ in }
    ) async throws -> ClaudeTranslation {
        guard let executable = await ClaudeLocator.find() else {
            throw Failure.notInstalled
        }
        let prompt = prompt(for: text, into: target)
        let runner = ProcessRunner(executable: executable)
        let output = try await withTaskCancellationHandler {
            try await runner.run(model: model, input: prompt) { line in
                if let usage = usage(fromLine: line) {
                    onUsage(usage)
                }
            }
        } onCancel: {
            runner.cancel()
        }
        return try parse(output.stdout, errors: output.stderr)
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
        Keep Markdown formatting, lists and line breaks.
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

/// What `claude` printed. Errors are also reported on stdout, in the
/// `result` event, so both are kept whatever the exit status.
private struct ProcessOutput: Sendable {
    let stdout: String
    let stderr: String
}

/// Runs `claude -p` with the prompt on stdin.
private final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let executable: URL
    private let lock = NSLock()
    private var isCancelled = false

    init(executable: URL) {
        self.executable = executable
    }

    /// `onLine` receives each line of standard output as soon as it's printed.
    func run(model: ClaudeModel, input: String, onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessOutput {
        process.executableURL = executable
        // stream-json (which needs --verbose) is the output that also carries
        // the plan usage.
        process.arguments = ["-p", "--model", model.rawValue, "--output-format", "stream-json", "--verbose"]
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

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Read both pipes while the process runs: if nobody reads, a long
        // output fills the pipe buffer and `claude` blocks forever.
        let output = PipeReader(stdout, onLine: onLine)
        let errors = PipeReader(stderr)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume(returning: ProcessOutput(stdout: output.waitForText(), stderr: errors.waitForText()))
            }

            lock.lock()
            let cancelledBeforeStart = isCancelled
            if !cancelledBeforeStart {
                do {
                    try process.run()
                } catch {
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
            }
            lock.unlock()

            if cancelledBeforeStart {
                continuation.resume(throwing: CancellationError())
                return
            }
            output.start()
            errors.start()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if process.isRunning {
            process.terminate()
        }
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
