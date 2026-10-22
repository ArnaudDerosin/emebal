import AppKit
import Foundation
import Observation
import Translation

enum TranslationState: Equatable {
    case loading
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

/// One translation request: the copied text and the result of each engine.
@MainActor
@Observable
final class TranslationModel {
    let text: String
    let sourceLanguage: Locale.Language?
    private let settings: AppSettings

    var appleState: TranslationState = .loading
    var claudeState: TranslationState = .loading
    /// The plan usage Claude Code reported: the last known one at first, if
    /// recent, then this translation's, as soon as it arrives.
    var claudeUsage: ClaudeUsage? = ClaudeUsage.recent
    /// True when this translation finished without reporting any usage (an
    /// API key has no plan limits, or Claude failed): nothing will come, so
    /// the panel stops waiting for it.
    var isClaudeUsageUnavailable = false
    /// Changing it makes SwiftUI's `.translationTask` run Apple's translation.
    var appleConfiguration: TranslationSession.Configuration?

    private var claudeTask: Task<Void, Never>?

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

    func setTarget(_ language: TargetLanguage) {
        settings.targetLanguageID = language.id
        start()
    }

    /// Starts (or restarts, after a language change) both engines.
    func start() {
        if isAppleEnabled { startApple() }
        if isClaudeEnabled { startClaude() }
    }

    func cancel() {
        claudeTask?.cancel()
    }

    // MARK: Apple

    private func startApple() {
        appleState = .loading
        guard let source = sourceLanguage else {
            appleState = .failed(String(localized: "Couldn't detect the language of this text."))
            return
        }
        if LanguageDetection.isSame(source, target.localeLanguage) {
            appleState = .done(text)
            return
        }
        Task {
            let status = await LanguageAvailability().status(from: source, to: target.localeLanguage)
            switch status {
            case .installed:
                appleConfiguration = TranslationSession.Configuration(
                    source: source,
                    target: target.localeLanguage
                )
            case .supported:
                appleState = .needsDownload(
                    String(localized: "Apple needs to download \(LanguageDetection.name(of: source)) → \(LanguageDetection.name(of: target.localeLanguage)) once to translate on this Mac.")
                )
            case .unsupported:
                appleState = .failed(String(localized: "Apple can't translate \(LanguageDetection.name(of: source)) to \(LanguageDetection.name(of: target.localeLanguage))."))
            @unknown default:
                appleState = .failed(String(localized: "Apple Translation isn't available."))
            }
        }
    }

    /// Starts Apple's translation anyway: the framework then shows its own
    /// prompt to download the missing languages.
    func downloadAppleLanguages() {
        guard let source = sourceLanguage else { return }
        appleState = .loading
        // The panel doesn't take focus, but the download prompt needs the app
        // to be active to appear.
        NSApplication.shared.activate()
        appleConfiguration = TranslationSession.Configuration(source: source, target: target.localeLanguage)
    }

    /// Receives Apple's result from the view's `.translationTask`.
    func setAppleState(_ state: TranslationState) {
        appleState = state
    }

    // MARK: Claude

    private func startClaude() {
        claudeTask?.cancel()
        claudeState = .loading
        isClaudeUsageUnavailable = false
        let text = text
        let target = target
        let model = settings.claudeModel
        claudeTask = Task {
            do {
                let result = try await ClaudeTranslator.translate(text, into: target, model: model) { usage in
                    Task { @MainActor [weak self] in
                        self?.updateUsage(usage)
                    }
                }
                guard !Task.isCancelled else { return }
                claudeState = .done(result.text)
                if let usage = result.usage {
                    updateUsage(usage)
                } else {
                    isClaudeUsageUnavailable = true
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                switch error as? ClaudeTranslator.Failure {
                case .notInstalled: claudeState = .needsClaudeSetup(.install)
                case .notSignedIn: claudeState = .needsClaudeSetup(.signIn)
                default: claudeState = .failed(error.localizedDescription)
                }
                isClaudeUsageUnavailable = true
            }
        }
    }

    private func updateUsage(_ usage: ClaudeUsage) {
        claudeUsage = usage
        ClaudeUsage.lastKnown = usage
    }
}
