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
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                originalRow
                // The Improve button is under the original, so its row only
                // shows with the original.
                if model.isImprovementShown && model.isSourceShown {
                    improvedRow
                }
            }
        }
        .padding([.horizontal, .bottom], 14)
        // Draw the header inside the title bar, 12 points from the top. The
        // window's size still counts the title bar, so only the content moves.
        .padding(.top, 12 - layout.titlebarHeight)
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
            let request = model.appleRequest
            let state: TranslationState
            do {
                state = .done(try await session.translate(model.text).targetText)
            } catch is CancellationError {
                return  // A newer request replaced this one.
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
            model.setAppleState(state, for: request)
        }
        .translationTask(model.improvedAppleConfiguration) { session in
            let request = model.improvedAppleRequest
            guard let improved = model.improvedText else { return }
            let state: TranslationState
            do {
                state = .done(try await session.translate(improved).targetText)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
            model.setImprovedAppleState(state, for: request)
        }
        .onChange(of: model.appleState) { onContentChange() }
        .onChange(of: model.claudeState) { onContentChange() }
        .onChange(of: model.improvedState) { onContentChange() }
        .onChange(of: model.improvedTranslationState) { onContentChange() }
        .onChange(of: model.improvedAppleState) { onContentChange() }
        .onChange(of: model.isImprovementShown) { onContentChange() }
        .onChange(of: model.claudeUsage) { onContentChange() }
        .onChange(of: model.isAppleEnabled) { onContentChange() }
        .onChange(of: model.isClaudeEnabled) { onContentChange() }
        .onChange(of: model.isSourceShown) { onContentChange() }
        .onChange(of: model.textSize) { onContentChange() }
        // From the panel's language menu or the menu bar: translate again,
        // only when the language really changed.
        .onChange(of: model.target) { model.start() }
        .environment(\.textSize, model.textSize)
    }

    /// The original and its translations.
    private var originalRow: some View {
        // Improving runs the user's Claude Code, so only when Claude is on.
        let improve = model.isClaudeEnabled && !model.isImprovementShown
            ? ColumnAction(title: "Improve", perform: model.showImprovement)
            : nil
        return row {
            if model.isSourceShown {
                EngineColumn(
                    title: "Original",
                    state: .done(model.text),
                    isMuted: true,
                    fillsHeight: layout.isResized,
                    action: improve
                )
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
                EngineColumn(title: "Claude", state: model.claudeState, fillsHeight: layout.isResized) {
                    ClaudeUsageLabel(
                        usage: model.claudeUsage,
                        isUnavailable: model.isClaudeUsageUnavailable
                    )
                }
            }
        }
    }

    /// Claude's improved wording and its translations, under the original's,
    /// card for card.
    private var improvedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Improved by Claude")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                VStack { Divider() }
            }
            .padding(.top, 4)
            row {
                EngineColumn(
                    title: "Improved",
                    state: model.improvedState,
                    loadingText: "Improving…",
                    fillsHeight: layout.isResized
                )
                if model.isAppleEnabled {
                    EngineColumn(
                        title: "Apple · on-device",
                        state: model.improvedAppleState,
                        fillsHeight: layout.isResized,
                        onDownload: model.downloadAppleLanguages
                    )
                }
                if model.isClaudeEnabled {
                    EngineColumn(title: "Claude", state: model.improvedTranslationState, fillsHeight: layout.isResized)
                }
            }
        }
    }

    /// Cards side by side, all as tall as the tallest, so rows read as rows.
    /// Once the user resizes the panel, the rows share its height instead.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            content()
        }
        .fixedSize(horizontal: false, vertical: !layout.isResized)
    }

    /// At the medium text size. A single column is wider than a third of three:
    /// narrow, a long translation would make the panel very tall.
    private var defaultWidth: CGFloat {
        let engines = [model.isAppleEnabled, model.isClaudeEnabled].filter { $0 }.count
        let columns = engines == 0 ? 1 : engines + (model.isSourceShown ? 1 : 0)
        let width: CGFloat = [520, 760, 1000][min(columns, 3) - 1]
        return (width * model.textSize.widthScale).rounded()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .frame(width: 17, height: 17)
                .foregroundStyle(.primary)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
            SourceLanguageLabel(name: model.sourceName, isDetected: model.sourceLanguage != nil)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            TargetLanguageMenu(model: model)
            Spacer()
            CloseButton(action: onClose)
        }
        .font(.system(size: 14))
    }
}

/// A bare ✕ in the top-right corner, brighter on hover.
struct CloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                // A larger click target than the cross itself.
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { isHovered = $0 }
        .help("Close (Esc)")
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
            TargetLanguageLabel(name: model.target.displayName, isHovered: isHovered)
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
            let item = ClosureMenuItem(title: language.displayName) {
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

/// "Japanese (日本語) · Detected": the source language, with a hint that the
/// app found it on its own.
struct SourceLanguageLabel: View {
    let name: String
    let isDetected: Bool

    var body: some View {
        Group {
            if isDetected {
                Text("\(name) · Detected")
            } else {
                Text(verbatim: name)
            }
        }
        .foregroundStyle(.secondary)
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

/// A button at the bottom left of a column, e.g. Improve under the original.
struct ColumnAction {
    let title: LocalizedStringKey
    let perform: () -> Void
}

private struct EngineColumn<TitleAccessory: View>: View {
    let title: LocalizedStringKey
    let state: TranslationState
    /// Shown until the first words arrive.
    var loadingText: LocalizedStringKey = "Translating…"
    /// Shows the text in the same gray as the source language, for the
    /// original text, which is there for reference.
    var isMuted = false
    /// Fill the panel's height instead of growing with the text up to a limit.
    var fillsHeight = false
    var onDownload: (() -> Void)? = nil
    var action: ColumnAction? = nil
    /// Shown at the right of the title, e.g. the Claude plan usage: it
    /// describes the engine, so it sits next to its name.
    @ViewBuilder var titleAccessory: () -> TitleAccessory

    /// The texts are larger than the interface around them so they are
    /// comfortable to read, and the same size in every column, so lines can be
    /// compared side by side.
    @Environment(\.textSize) private var textSize
    private var textFont: Font { .system(size: textSize.textPointSize) }
    private var messageFont: Font { .system(size: textSize.messagePointSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if isWorking {
                    // The only progress indicator, from the start of the
                    // translation until it's complete, centered on the
                    // title's capital letters like the usage gauge.
                    let capHeight = Self.titleCapHeight
                    ProgressView()
                        .controlSize(.mini)
                        .alignmentGuide(.firstTextBaseline) { spinner in
                            spinner.height / 2 + capHeight / 2
                        }
                        .transition(.opacity)
                }
                Spacer(minLength: 8)
                titleAccessory()
            }
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: fillsHeight ? .infinity : 360)
            // In a row of taller cards, the buttons stay at the bottom.
            Spacer(minLength: 0)
            HStack {
                if let action {
                    Button(action.title, action: action.perform)
                }
                Spacer()
                Button("Copy") {
                    guard case .done(let text) = state else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(!isDone)
            }
        }
        .padding(14)
        // As tall as the row: see `TranslationView.row`.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            Text(loadingText)
                .font(messageFont)
                .foregroundStyle(.secondary)
        case .partial(let text), .done(let text):
            Text(text)
                .font(textFont)
                .lineSpacing(textSize.lineSpacing)
                .foregroundStyle(isMuted ? .secondary : .primary)
                .textSelection(.enabled)
        case .failed(let message):
            Text(message)
                .font(messageFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .needsDownload(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(messageFont)
                    .foregroundStyle(.secondary)
                if let onDownload {
                    Button("Download…", action: onDownload)
                }
            }
        case .needsClaudeSetup(let setup):
            ClaudeSetupView(setup: setup, font: messageFont)
        }
    }

    private var isDone: Bool {
        if case .done = state { return true }
        return false
    }

    /// Translating: nothing yet, or the text so far.
    private var isWorking: Bool {
        switch state {
        case .loading, .partial: true
        default: false
        }
    }

    /// The height of capital letters in the title's font.
    private static var titleCapHeight: CGFloat {
        NSFont.preferredFont(forTextStyle: .subheadline).capHeight
    }
}

extension EngineColumn where TitleAccessory == EmptyView {
    init(
        title: LocalizedStringKey,
        state: TranslationState,
        loadingText: LocalizedStringKey = "Translating…",
        isMuted: Bool = false,
        fillsHeight: Bool = false,
        onDownload: (() -> Void)? = nil,
        action: ColumnAction? = nil
    ) {
        self.init(
            title: title, state: state, loadingText: loadingText, isMuted: isMuted,
            fillsHeight: fillsHeight, onDownload: onDownload, action: action
        ) {
            EmptyView()
        }
    }
}

/// "Session 6% · resets in 2h 35m · Week 8%": the Claude plan usage, next to
/// the Claude title, kept up to date as time passes. The tooltip gives both
/// reset times.
///
/// Until numbers are known, a gray placeholder holds their place, so the
/// line doesn't pop in; the numbers then fade in.
private struct ClaudeUsageLabel: View {
    let usage: ClaudeUsage?
    /// No usage will come for this translation: show nothing rather than a
    /// placeholder that never fills in.
    let isUnavailable: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Numbers from a window that has already reset are stale.
            let current = usage?.current(at: context.date)
            // One view for the placeholder and the numbers, so the numbers
            // fade in where the placeholder was.
            if current != nil || !isUnavailable {
                ClaudeUsageText(
                    usage: current ?? .placeholder(at: context.date),
                    now: context.date,
                    isPlaceholder: current == nil
                )
            }
        }
    }
}

/// A rounded pill that breathes gently while numbers are on their way. The
/// repeating animation only changes its opacity: scoped this way, it can't
/// make the pill glide when the panel resizes.
private struct PlaceholderPill: View {
    @State private var isDim = false

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .padding(.vertical, 2)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pill in
                pill.opacity(isDim ? 0.45 : 1)
            }
            .onAppear { isDim = true }
    }
}

private extension ClaudeUsage {
    /// Typical values, only to give the placeholder bars a realistic length.
    static func placeholder(at date: Date) -> ClaudeUsage {
        ClaudeUsage(
            session: .init(usedFraction: 0.07, resetsAt: date.addingTimeInterval(2 * 3600 + 35 * 60)),
            week: .init(usedFraction: 0.08, resetsAt: date.addingTimeInterval(3 * 86400))
        )
    }
}

/// The usage line itself, for windows that haven't reset yet.
private struct ClaudeUsageText: View {
    let usage: ClaudeUsage
    let now: Date
    var isPlaceholder = false

    /// The height of capital letters in the caption font used here.
    private static let captionCapHeight = NSFont.preferredFont(forTextStyle: .caption1).capHeight

    var body: some View {
        // Aligned on the text's baseline, like the Claude title next to it,
        // with the icon centered on the capital letters: a round symbol on the
        // baseline itself dips below the text and looks low at this size.
        let capHeight = Self.captionCapHeight
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .alignmentGuide(.firstTextBaseline) { icon in
                    // + 0.5: the symbol's frame has a little more room below
                    // its drawing than above.
                    icon.height / 2 + capHeight / 2 + 0.5
                }
            Text(summary)
                .lineLimit(1)
                .truncationMode(.middle)
                // Fades in when the numbers arrive. The animation is scoped
                // to the opacity: when the panel resizes at the same moment,
                // the text moves at once instead of gliding.
                .animation(.easeInOut(duration: 0.35)) { text in
                    text.opacity(isPlaceholder ? 0 : 1)
                }
                // Until numbers arrive: a rounded pill as wide as the text,
                // in place of the text.
                .background {
                    if isPlaceholder {
                        PlaceholderPill()
                    }
                }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .help(isPlaceholder ? "" : details)
    }

    private var summary: String {
        var parts: [String] = []
        if let session = usage.session {
            parts.append(String(localized: "Session \(percent(session))"))
            parts.append(String(localized: "resets in \(timeLeft(until: session.resetsAt, from: now))"))
        }
        if let week = usage.week {
            parts.append(String(localized: "Week \(percent(week))"))
        }
        return parts.joined(separator: String(localized: " · ", comment: "Separates the parts of the Claude usage line."))
    }

    private var details: String {
        var lines = [String(localized: "Your Claude plan usage, as of the last translation.")]
        if let session = usage.session {
            lines.append(String(localized: "Current session: \(percent(session)) used, resets \(resetTime(session))"))
        }
        if let week = usage.week {
            lines.append(String(localized: "Current week: \(percent(week)) used, resets \(resetTime(week))"))
        }
        return lines.joined(separator: "\n")
    }

    private func percent(_ window: ClaudeUsage.Window) -> String {
        "\(Int((window.usedFraction * 100).rounded()))%"
    }

    private func resetTime(_ window: ClaudeUsage.Window) -> String {
        window.resetsAt.formatted(.dateTime.weekday(.wide).hour().minute())
    }

    /// "2h 35m" in English, "2時間35分" in Japanese: the formatter follows
    /// the user's language.
    private func timeLeft(until date: Date, from now: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)m"
    }
}

/// What to do when Claude Code is missing or signed out, with a button for
/// the first step. Signing in happens in Claude Code itself, in Terminal:
/// Emebal never handles the account.
private struct ClaudeSetupView: View {
    let setup: ClaudeSetup
    let font: Font

    static let setupPage = URL(string: "https://code.claude.com/docs/en/setup")!
    static let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch setup {
            case .install:
                Text("Claude Code isn't installed. Emebal uses it for Claude translations: install it, sign in once, then translate again.")
                    .font(font)
                    .foregroundStyle(.secondary)
                Button("Install Claude Code…") {
                    NSWorkspace.shared.open(Self.setupPage)
                }
            case .signIn:
                Text("Claude Code isn't signed in. In Terminal, run `claude` and sign in, then translate again.")
                    .font(font)
                    .foregroundStyle(.secondary)
                Button("Open Terminal") {
                    NSWorkspace.shared.open(Self.terminal)
                }
            }
        }
        .textSelection(.enabled)
    }
}

extension EnvironmentValues {
    /// The text size chosen in the menu, for the panel's columns.
    @Entry var textSize: TextSize = .medium
}
