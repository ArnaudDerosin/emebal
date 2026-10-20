import Foundation

/// A Claude translation, with the plan usage Claude Code reported along with it.
struct ClaudeTranslation: Sendable {
    let text: String
    let usage: ClaudeUsage?
}

/// How much of the user's Claude plan limits is used. Claude Code reports it
/// with each answer, so reading it costs nothing and needs no credentials.
/// Only subscriptions (not API keys) have these limits.
struct ClaudeUsage: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        /// From 0 to 1.
        let usedFraction: Double
        let resetsAt: Date
    }

    /// The 5-hour window, what Claude Code calls the current session.
    let session: Window?
    /// The 7-day window.
    let week: Window?
}

/// Translates by running the user's own, signed-in Claude Code CLI
/// (`claude -p`). Usage counts toward the user's Claude account.
enum ClaudeTranslator {
    enum Failure: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Claude Code not found. Install it and sign in, or turn Claude off in the menu."
            case .failed(let message):
                message.isEmpty ? "Claude Code failed." : message
            }
        }
    }

    static func translate(
        _ text: String,
        into target: TargetLanguage,
        model: ClaudeModel
    ) async throws -> ClaudeTranslation {
        guard let executable = await ClaudeLocator.find() else {
            throw Failure.notInstalled
        }
        let prompt = prompt(for: text, into: target)
        let runner = ProcessRunner(executable: executable)
        let output = try await withTaskCancellationHandler {
            try await runner.run(model: model, input: prompt)
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
            throw Failure.failed(errors.isEmpty ? output : errors)
        }
        if result["is_error"] as? Bool == true {
            throw Failure.failed(text)
        }
        return ClaudeTranslation(text: text.trimmingCharacters(in: .whitespacesAndNewlines), usage: usage)
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

    func run(model: ClaudeModel, input: String) async throws -> ProcessOutput {
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
        let output = PipeReader(stdout)
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

/// Reads a pipe to the end on a background queue.
private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.data = self.pipe.fileHandleForReading.readDataToEndOfFile()
            self.done.signal()
        }
    }

    /// Blocks until the pipe is closed; only call after the process exited.
    func waitForText() -> String {
        done.wait()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
