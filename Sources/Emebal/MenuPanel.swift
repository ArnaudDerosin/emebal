import AppKit
import SwiftUI

/// What the menu-bar icon opens: a small panel that looks like a menu, like
/// macOS's own Wi-Fi and Sound menus, so switches and choices can be changed
/// one after another without it closing. Actions (Translate Clipboard, Quit)
/// close it, as menu items do.
struct MenuPanel: View {
    @Bindable var settings: AppSettings
    let loginItem: LoginItem
    let onTranslateClipboard: () -> Void

    /// Read when the panel opens: the user may have changed it in System Settings.
    @State private var isAccessibilityAllowed = DoubleCopyMonitor.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Emebal")
                    .fontWeight(.semibold)
                Spacer()
                Text("Version \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, menuInset)
            .padding(.vertical, 6)

            MenuDivider()
            MenuAction("Translate Clipboard", icon: MenuBarIcon.wedges) {
                closeMenu()
                onTranslateClipboard()
            }

            MenuDivider()
            MenuSectionTitle("Translation")
            MenuChoice("Translate Into", selection: $settings.targetLanguageID) {
                ForEach(TargetLanguage.all) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            MenuChoice("Claude Model", selection: $settings.claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .disabled(!settings.isClaudeEnabled)
            MenuSwitch(
                "Keep Claude Ready",
                detail: "Faster translations · uses about 270 MB of memory",
                isOn: $settings.keepsClaudeReady
            )
            .disabled(!settings.isClaudeEnabled)

            MenuDivider()
            // In the same order as the columns in the panel.
            MenuSectionTitle("Columns")
            MenuSwitch("Original", isOn: $settings.isSourceShown)
            MenuSwitch("Apple Translation", isOn: $settings.isAppleEnabled)
            MenuSwitch("Claude", isOn: $settings.isClaudeEnabled)

            MenuDivider()
            MenuSectionTitle("Panel")
            MenuRow("Text Size") {
                Picker("Text Size", selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            MenuSwitch("Close When Clicking Outside", isOn: $settings.closesOnClickOutside)

            MenuDivider()
            MenuSwitch("Open at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            if !isAccessibilityAllowed {
                MenuAction("Allow Accessibility to Use ⌘C C…") {
                    closeMenu()
                    DoubleCopyMonitor.requestPermission()
                }
            }

            MenuDivider()
            MenuAction("Quit Emebal", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 5)
        .frame(width: 290)
        .onAppear {
            loginItem.refresh()
            isAccessibilityAllowed = DoubleCopyMonitor.isTrusted
        }
        .onExitCommand(perform: closeMenu)
    }

    /// The panel is the key window while it's open.
    private func closeMenu() {
        NSApplication.shared.keyWindow?.close()
    }
}

/// The horizontal margin of the rows, as in a menu.
private let menuInset: CGFloat = 14

/// A row with a label on the left and a control on the right.
private struct MenuRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder let control: () -> Control

    init(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    // Wraps rather than hiding the end, which says the cost.
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, menuInset)
        .padding(.vertical, 4)
    }
}

/// An on/off setting, with a small switch like in the Wi-Fi menu.
private struct MenuSwitch: View {
    let title: LocalizedStringKey
    /// A small gray line under the title, for what the setting costs.
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        MenuRow(title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}

/// A setting with several values, shown as a compact pop-up button.
private struct MenuChoice<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options

    init(_ title: LocalizedStringKey, selection: Binding<Value>, @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        MenuRow(title) {
            // As wide as the selected value needs, up to a limit: a pop-up
            // button is otherwise as wide as its longest option.
            Picker(title, selection: $selection, content: options)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 150, alignment: .trailing)
        }
    }
}

/// An action, highlighted on hover like a menu item.
private struct MenuAction: View {
    let title: LocalizedStringKey
    var shortcut: String?
    /// A small template image on the right, where switches sit in other rows.
    var icon: NSImage?
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, shortcut: String? = nil, icon: NSImage? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(verbatim: shortcut)
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
                if let icon {
                    Image(nsImage: icon)
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, menuInset - 5)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { isHovered = $0 }
    }
}

/// A small gray title above a group of settings.
private struct MenuSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, menuInset)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, menuInset - 4)
            .padding(.vertical, 5)
    }
}
