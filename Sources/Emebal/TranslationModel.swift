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

    var sourceName: String {
        sourceLanguage.map(LanguageDetection.nativeName(of:)) ?? "Unknown language"
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
            appleState = .failed("Couldn't detect the language of this text.")
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
                    "Apple needs to download \(sourceName) → \(target.nativeName) once to translate on this Mac."
                )
            case .unsupported:
                appleState = .failed("Apple can't translate \(sourceName) to \(target.nativeName).")
            @unknown default:
                appleState = .failed("Apple Translation isn't available.")
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
        let text = text
        let target = target
        let model = settings.claudeModel
        claudeTask = Task {
            do {
                let result = try await ClaudeTranslator.translate(text, into: target, model: model)
                guard !Task.isCancelled else { return }
                claudeState = .done(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                claudeState = .failed(error.localizedDescription)
            }
        }
    }
}
