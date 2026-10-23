import Foundation

/// Keeps one Claude Code started and waiting for its text, when the user
/// turns on Keep Claude Ready: a translation then doesn't wait for Claude Code
/// to start (about half a second faster), at the cost of about 270 MB of
/// memory while it waits. It sends nothing and uses none of the plan until a
/// translation actually happens.
///
/// Each waiting process serves one translation; a fresh one is started after
/// it, so translations never share context.
@MainActor
final class ReadyClaude {
    static let shared = ReadyClaude()

    private var isEnabled = false
    /// This Claude Code can't wait for its text (too old, or it keeps exiting).
    private var isUnsupported = false
    private var runner: ProcessRunner?
    private var executable: URL?
    /// Waiting processes that had exited by the time a translation came.
    private var exitsBeforeUse = 0

    /// Follows the menu: on when Keep Claude Ready and Claude are both on.
    func update(isEnabled: Bool, model: ClaudeModel) {
        self.isEnabled = isEnabled
        guard isEnabled else {
            stop()
            return
        }
        if let runner, runner.model != model {
            stop()
        }
        guard runner == nil else { return }
        Task {
            if executable == nil {
                executable = await ClaudeLocator.find()
            }
            if let executable {
                prepare(model: model, executable: executable)
            }
        }
    }

    /// Starts a Claude Code that waits for its text, if none is ready.
    func prepare(model: ClaudeModel, executable: URL) {
        guard isEnabled, !isUnsupported, runner == nil else { return }
        let ready = ProcessRunner(executable: executable, model: model)
        do {
            try ready.start(isFull: true, waitsForMessage: true)
        } catch {
            return
        }
        runner = ready
        self.executable = executable
    }

    /// The waiting Claude Code, for a translation with this model, if it's
    /// still running. It's handed over, not kept: call `prepare` for the next.
    func take(model: ClaudeModel, executable: URL) -> ProcessRunner? {
        guard isEnabled, !isUnsupported, let ready = runner else { return nil }
        runner = nil
        guard ready.isWaiting else {
            // It exited while waiting. Once in a while is fine; if it keeps
            // happening, this Claude Code doesn't support waiting.
            exitsBeforeUse += 1
            if exitsBeforeUse >= 3 {
                isUnsupported = true
            }
            return nil
        }
        guard ready.model == model, ready.executable == executable else {
            ready.cancel()
            return nil
        }
        exitsBeforeUse = 0
        return ready
    }

    func markUnsupported() {
        isUnsupported = true
        stop()
    }

    func stop() {
        runner?.cancel()
        runner = nil
    }
}
