import AppKit
import Foundation
import Observation
import Translation

enum TranslationState: Equatable {
    case loading
    /// Claude is still writing: the translation so far.
    case partial(String)
    case done(String)
    case failed(String)
    /// Apple supports the pair, but the languages aren't downloaded yet.
    case needsDownload(String)
    /// Claude Code must be installed or signed in first.
    case needsClaudeSetup(ClaudeSetup)
}

enum ClaudeSetup: Equatable {
    case install
    case signIn
}

/// One translation request: the copied text and the result of each engine,
/// and Claude's improved wording if the user asks for it.
@MainActor
@Observable
final class TranslationModel {
    let text: String
    let sourceLanguage: Locale.Language?
    private let settings: AppSettings

    var appleState: TranslationState = .loading
    var claudeState: TranslationState = .loading
    /// Claude's improved wording of the text, in its own language, shown
    /// under the original once the user asks for it.
    private(set) var isImprovementShown = false
    var improvedState: TranslationState = .loading
    /// Apple's and Claude's translations of the improved wording, in the row
    /// under the original's.
    var improvedAppleState: TranslationState = .loading
    var improvedTranslationState: TranslationState = .loading
    /// The plan usage Claude Code reported: the last known one at first, if
    /// recent, then this translation's, as soon as it arrives.
    var claudeUsage: ClaudeUsage? = ClaudeUsage.recent
    /// True when this translation finished without reporting any usage (an
    /// API key has no plan limits, or Claude failed): nothing will come, so
    /// the panel stops waiting for it.
    var isClaudeUsageUnavailable = false
    /// Changing it makes SwiftUI's `.translationTask` run Apple's translation.
    var appleConfiguration: TranslationSession.Configuration?
    /// Counts Apple translation requests. When the target language changes
    /// quickly, results and checks from an earlier request are ignored.
    @ObservationIgnored private(set) var appleRequest = 0
    /// The same, for the improved wording.
    var improvedAppleConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private(set) var improvedAppleRequest = 0

    private var claudeTask: Task<Void, Never>?
    /// Nil until the user asks for the improved wording; it's asked only once.
    private var improveTask: Task<Void, Never>?
    private var improvedTranslationTask: Task<Void, Never>?

    init(text: String, settings: AppSettings) {
        self.text = text
        self.sourceLanguage = LanguageDetection.detect(text)
        self.settings = settings
    }

    var target: TargetLanguage { settings.targetLanguage }
    var isAppleEnabled: Bool { settings.isAppleEnabled }
    var isClaudeEnabled: Bool { settings.isClaudeEnabled }
    var isSourceShown: Bool { settings.isSourceShown }
    var textSize: TextSize { settings.textSize }

    var sourceName: String {
        sourceLanguage.map { LanguageDetection.displayName(of: $0) } ?? String(localized: "Unknown language")
    }

    /// The panel restarts the translations when the target actually changes
    /// (see `TranslationView`), so picking the current language again, here
    /// or in the menu bar, does nothing.
    func setTarget(_ language: TargetLanguage) {
        settings.targetLanguageID = language.id
    }

    /// Starts (or restarts, after a language change) both engines.
    func start() {
        if isAppleEnabled { startApple() }
        if isClaudeEnabled { startClaude() }
        if isImprovementShown { translateImprovement() }
    }

    func cancel() {
        claudeTask?.cancel()
        improveTask?.cancel()
        improvedTranslationTask?.cancel()
    }

    // MARK: Improved wording

    func showImprovement() {
        isImprovementShown = true
        guard improveTask == nil else { return }
        improvedAppleState = .loading
        improvedTranslationState = .loading
        let text = text
        let model = settings.claudeModel
        improveTask = runClaude(into: .improvement) { onUsage, onText in
            try await ClaudeTranslator.improve(text, model: model, onUsage: onUsage, onText: onText)
        }
    }

    /// The improved wording, once complete.
    var improvedText: String? {
        if case .done(let text) = improvedState { return text }
        return nil
    }

    /// Translates the improved wording once it's complete; until then, the
    /// row waits, and the improvement starts it when it ends.
    private func translateImprovement() {
        if isAppleEnabled { startImprovedApple() }
        startImprovedTranslation()
    }

    private func startImprovedApple() {
        improvedAppleRequest += 1
        let request = improvedAppleRequest
        switch improvedState {
        case .done(let improved):
            // The improved wording keeps the original's language.
            guard let source = sourceLanguage else {
                improvedAppleState = .failed(String(localized: "Couldn't detect the language of this text."))
                return
            }
            if LanguageDetection.isSame(source, target.localeLanguage) {
                improvedAppleState = .done(improved)
                return
            }
            improvedAppleState = .loading
            let target = target.localeLanguage
            Task {
                let unavailable = await appleUnavailability(from: source, to: target)
                guard request == improvedAppleRequest else { return }
                if let unavailable {
                    improvedAppleState = unavailable
                } else if improvedAppleConfiguration?.source == source, improvedAppleConfiguration?.target == target {
                    // See `requestAppleTranslation`.
                    improvedAppleConfiguration?.invalidate()
                } else {
                    improvedAppleConfiguration = TranslationSession.Configuration(source: source, target: target)
                }
            }
        case .loading, .partial:
            improvedAppleState = .loading
        case .failed, .needsDownload, .needsClaudeSetup:
            improvedAppleState = improvedState
        }
    }

    /// Receives Apple's translation of the improved wording, unless a newer
    /// request started since.
    func setImprovedAppleState(_ state: TranslationState, for request: Int) {
        guard request == improvedAppleRequest else { return }
        improvedAppleState = state
    }

    private func startImprovedTranslation() {
        guard isClaudeEnabled else { return }
        improvedTranslationTask?.cancel()
        switch improvedState {
        case .done(let improved):
            if let source = sourceLanguage, LanguageDetection.isSame(source, target.localeLanguage) {
                // Already in the target language: nothing to ask Claude.
                improvedTranslationState = .done(improved)
                return
            }
            let target = target
            let model = settings.claudeModel
            improvedTranslationTask = runClaude(into: .improvedTranslation) { onUsage, onText in
                try await ClaudeTranslator.translate(
                    improved, into: target, model: model, onUsage: onUsage, onText: onText
                )
            }
        case .loading, .partial:
            improvedTranslationState = .loading
        case .failed, .needsDownload, .needsClaudeSetup:
            // Same cause, same message.
            improvedTranslationState = improvedState
        }
    }

    // MARK: Apple

    private func startApple() {
        appleRequest += 1
        let request = appleRequest
        appleState = .loading
        guard let source = sourceLanguage else {
            appleState = .failed(String(localized: "Couldn't detect the language of this text."))
            return
        }
        if LanguageDetection.isSame(source, target.localeLanguage) {
            appleState = .done(text)
            return
        }
        let target = target.localeLanguage
        Task {
            let unavailable = await appleUnavailability(from: source, to: target)
            // The user picked another language in the meantime.
            guard request == appleRequest else { return }
            if let unavailable {
                appleState = unavailable
            } else {
                requestAppleTranslation(from: source, to: target)
            }
        }
    }

    /// What to show when Apple can't translate the pair right now, or nil
    /// when its languages are installed.
    private func appleUnavailability(from source: Locale.Language, to target: Locale.Language) async -> TranslationState? {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            nil
        case .supported:
            .needsDownload(
                String(localized: "Apple needs to download \(LanguageDetection.name(of: source)) → \(LanguageDetection.name(of: target)) once to translate on this Mac.")
            )
        case .unsupported:
            .failed(String(localized: "Apple can't translate \(LanguageDetection.name(of: source)) to \(LanguageDetection.name(of: target))."))
        @unknown default:
            .failed(String(localized: "Apple Translation isn't available."))
        }
    }

    /// Starts Apple's translation anyway: the framework then shows its own
    /// prompt to download the missing languages.
    func downloadAppleLanguages() {
        guard let source = sourceLanguage else { return }
        appleRequest += 1
        appleState = .loading
        // The panel doesn't take focus, but the download prompt needs the app
        // to be active to appear.
        NSApplication.shared.activate()
        requestAppleTranslation(from: source, to: target.localeLanguage)
    }

    /// Makes the view's `.translationTask` run. It only runs when the
    /// configuration changes, so asking again for the same languages (for
    /// example back to English after trying Japanese) must invalidate the
    /// current one instead of setting an equal one, which would do nothing.
    func requestAppleTranslation(from source: Locale.Language, to target: Locale.Language) {
        if appleConfiguration?.source == source, appleConfiguration?.target == target {
            appleConfiguration?.invalidate()
        } else {
            appleConfiguration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Receives Apple's result from the view's `.translationTask`, unless a
    /// newer request started since.
    func setAppleState(_ state: TranslationState, for request: Int) {
        guard request == appleRequest else { return }
        appleState = state
        // The languages were just downloaded for the original: the improved
        // wording can use them too.
        if case .done = state, case .needsDownload = improvedAppleState {
            startImprovedApple()
        }
    }

    /// Sets the state directly, for previews and tests.
    func setAppleState(_ state: TranslationState) {
        appleState = state
    }

    // MARK: Claude

    private func startClaude() {
        claudeTask?.cancel()
        let text = text
        let target = target
        let model = settings.claudeModel
        claudeTask = runClaude(into: .translation) { onUsage, onText in
            try await ClaudeTranslator.translate(text, into: target, model: model, onUsage: onUsage, onText: onText)
        }
    }

    /// Runs one Claude request, showing its text in `state` as it's written.
    private func runClaude(
        into state: ClaudeResult,
        _ request: @escaping (
            _ onUsage: @escaping @Sendable (ClaudeUsage) -> Void,
            _ onText: @escaping @Sendable (String) -> Void
        ) async throws -> ClaudeTranslation
    ) -> Task<Void, Never> {
        self[state] = .loading
        isClaudeUsageUnavailable = false
        return Task {
            do {
                let result = try await request(
                    { usage in
                        Task { @MainActor [weak self] in
                            self?.updateUsage(usage)
                        }
                    },
                    { written in
                        Task { @MainActor [weak self] in
                            self?.showPartialText(written, in: state)
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                self[state] = .done(result.text)
                if let usage = result.usage {
                    updateUsage(usage)
                } else {
                    isClaudeUsageUnavailable = true
                }
                if state == .improvement { translateImprovement() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                switch error as? ClaudeTranslator.Failure {
                case .notInstalled: self[state] = .needsClaudeSetup(.install)
                case .notSignedIn: self[state] = .needsClaudeSetup(.signIn)
                default: self[state] = .failed(error.localizedDescription)
                }
                isClaudeUsageUnavailable = true
                if state == .improvement { translateImprovement() }
            }
        }
    }

    /// Shows the text as Claude writes it, until the final one arrives (a
    /// late piece never replaces it).
    private func showPartialText(_ written: String, in state: ClaudeResult) {
        switch self[state] {
        case .loading, .partial:
            self[state] = .partial(written.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            break
        }
    }

    /// Which of Claude's two results a request fills.
    private enum ClaudeResult {
        case translation
        case improvement
        case improvedTranslation
    }

    private subscript(result: ClaudeResult) -> TranslationState {
        get {
            switch result {
            case .translation: claudeState
            case .improvement: improvedState
            case .improvedTranslation: improvedTranslationState
            }
        }
        set {
            switch result {
            case .translation: claudeState = newValue
            case .improvement: improvedState = newValue
            case .improvedTranslation: improvedTranslationState = newValue
            }
        }
    }

    private func updateUsage(_ usage: ClaudeUsage) {
        claudeUsage = usage
        ClaudeUsage.lastKnown = usage
    }
}
