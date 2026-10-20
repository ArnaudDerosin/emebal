import Foundation

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
    ) async throws -> String {
        guard let executable = await ClaudeLocator.find() else {
            throw Failure.notInstalled
        }
        let prompt = prompt(for: text, into: target)
        let runner = ProcessRunner(executable: executable)
        return try await withTaskCancellationHandler {
            try await runner.run(model: model, input: prompt)
        } onCancel: {
            runner.cancel()
        }
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

/// Runs `claude -p` with the prompt on stdin.
private final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let executable: URL
    private let lock = NSLock()
    private var isCancelled = false

    init(executable: URL) {
        self.executable = executable
    }

    func run(model: ClaudeModel, input: String) async throws -> String {
        process.executableURL = executable
        process.arguments = ["-p", "--model", model.rawValue]
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
            process.terminationHandler = { process in
                let status = process.terminationStatus
                let out = output.waitForText()
                let err = errors.waitForText()
                switch status {
                case 0:
                    continuation.resume(returning: out)
                default:
                    continuation.resume(throwing: ClaudeTranslator.Failure.failed(err.isEmpty ? out : err))
                }
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
