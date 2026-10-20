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
        let prompt = prompt(for: text, into: target)
        let runner = ProcessRunner()
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

/// Runs `claude -p` through the user's login shell. Apps opened from Finder
/// don't get the shell's PATH, so `claude` (often in ~/.local/bin) would not be
/// found if it were launched directly.
private final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var isCancelled = false

    func run(model: ClaudeModel, input: String) async throws -> String {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec claude -p --model \(model.rawValue)"]
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
                case 127:
                    // The shell couldn't find `claude`.
                    continuation.resume(throwing: ClaudeTranslator.Failure.notInstalled)
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
