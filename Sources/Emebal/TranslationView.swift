import AppKit
import SwiftUI
@preconcurrency import Translation

struct TranslationView: View {
    @Bindable var model: TranslationModel
    let layout: PanelLayout
    let onClose: () -> Void
    /// Called when the content may need a different size.
    var onContentChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.isAppleEnabled && !model.isClaudeEnabled {
                Text("Both engines are turned off. Turn one on in the Emebal menu.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if model.isSourceShown {
                        EngineColumn(title: "Original", state: .done(model.text), fillsHeight: layout.isResized)
                    }
                    if model.isAppleEnabled {
                        EngineColumn(
                            title: "Apple · on-device",
                            state: model.appleState,
                            fillsHeight: layout.isResized,
                            onDownload: model.downloadAppleLanguages
                        )
                    }
                    if model.isClaudeEnabled {
                        EngineColumn(title: "Claude", state: model.claudeState, fillsHeight: layout.isResized)
                    }
                }
            }
        }
        .padding(14)
        // The default width is also the smallest one. The view has no maximum,
        // so the panel can be resized freely and the view fills it.
        .frame(
            minWidth: defaultWidth,
            idealWidth: defaultWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
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
        .onChange(of: model.appleState) { onContentChange() }
        .onChange(of: model.claudeState) { onContentChange() }
        .onChange(of: model.isAppleEnabled) { onContentChange() }
        .onChange(of: model.isClaudeEnabled) { onContentChange() }
        .onChange(of: model.isSourceShown) { onContentChange() }
    }

    /// About 300 points per column, plus the spacing between them.
    private var defaultWidth: CGFloat {
        let engines = [model.isAppleEnabled, model.isClaudeEnabled].filter { $0 }.count
        let columns = engines == 0 ? 1 : engines + (model.isSourceShown ? 1 : 0)
        return [360, 640, 920][min(columns, 3) - 1]
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(.primary)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
            SourceLanguageLabel(name: model.sourceName, isDetected: model.sourceLanguage != nil)
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
///
/// SwiftUI's `Menu` on macOS rearranges a custom label into "icon + title", so
/// the chevron would come first. The button is drawn in SwiftUI instead, and a
/// native menu is opened under it on click.
struct TargetLanguageMenu: View {
    let model: TranslationModel
    @State private var isHovered = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button(action: showMenu) {
            TargetLanguageLabel(name: model.target.nativeName, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Change the language to translate into")
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        for language in TargetLanguage.all {
            let item = ClosureMenuItem(title: language.nativeName) {
                model.setTarget(language)
            }
            item.state = language.id == model.target.id ? .on : .off
            menu.addItem(item)
        }
        // Open the menu just below the button.
        let below = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: view)
    }
}

/// "日本語 (Detected)": the source language, with a lighter hint that the app
/// found it on its own.
struct SourceLanguageLabel: View {
    let name: String
    let isDetected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .foregroundStyle(.secondary)
            if isDetected {
                Text("(Detected)")
                    .foregroundStyle(.tertiary)
            }
        }
        .help(isDetected ? "Language detected automatically" : "The language couldn't be detected")
    }
}

/// "English ⌄": the language name, then the chevron.
struct TargetLanguageLabel: View {
    let name: String
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
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
}

/// Holds the AppKit view behind the button, to position the menu.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// A menu item that runs a closure when chosen.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func choose() {
        handler()
    }
}

private struct EngineColumn: View {
    let title: String
    let state: TranslationState
    /// Fill the panel's height instead of growing with the text up to a limit.
    var fillsHeight = false
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
            .frame(minHeight: 60, maxHeight: fillsHeight ? .infinity : 320)
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
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
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
