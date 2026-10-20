import AppKit
import SwiftUI
@preconcurrency import Translation

struct TranslationView: View {
    @Bindable var model: TranslationModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.isAppleEnabled && !model.isClaudeEnabled {
                Text("Both engines are turned off. Turn one on in the Emebal menu.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if model.isAppleEnabled {
                        EngineColumn(
                            title: "Apple · on-device",
                            state: model.appleState,
                            onDownload: model.downloadAppleLanguages
                        )
                    }
                    if model.isClaudeEnabled {
                        EngineColumn(title: "Claude", state: model.claudeState)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: model.isAppleEnabled && model.isClaudeEnabled ? 640 : 360)
        .translationTask(model.appleConfiguration) { session in
            // The session must stay in this closure; only the result is passed on.
            let state: TranslationState
            do {
                state = .done(try await session.translate(model.text).targetText)
            } catch {
                state = .failed(error.localizedDescription)
            }
            model.setAppleState(state)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.sourceName)
                .foregroundStyle(.secondary)
                .help("Detected language")
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            TargetLanguageMenu(model: model)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
    }
}

/// The target language, shown as a quiet button that opens the language list.
private struct TargetLanguageMenu: View {
    let model: TranslationModel
    @State private var isHovered = false

    var body: some View {
        Menu {
            Picker("Translate Into", selection: Binding(
                get: { model.target.id },
                set: { id in
                    if let language = TargetLanguage.all.first(where: { $0.id == id }) {
                        model.setTarget(language)
                    }
                }
            )) {
                ForEach(TargetLanguage.all) { language in
                    Text(language.nativeName).tag(language.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(model.target.nativeName)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Change the language to translate into")
    }
}

private struct EngineColumn: View {
    let title: String
    let state: TranslationState
    var onDownload: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 320)
            HStack {
                Spacer()
                Button("Copy") {
                    guard case .done(let text) = state else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(!isDone)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(.secondary)
            }
        case .done(let text):
            Text(text)
                .textSelection(.enabled)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .needsDownload(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .foregroundStyle(.secondary)
                if let onDownload {
                    Button("Download…", action: onDownload)
                }
            }
        }
    }

    private var isDone: Bool {
        if case .done = state { return true }
        return false
    }
}
