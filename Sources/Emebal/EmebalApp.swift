import AppKit
import SwiftUI

@main
struct EmebalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Translate Clipboard") {
                appDelegate.translateClipboard()
            }
            Divider()

            Picker("Translate Into", selection: $settings.targetLanguageID) {
                ForEach(TargetLanguage.all) { language in
                    Text(language.nativeName).tag(language.id)
                }
            }
            Toggle("Apple Translation", isOn: $settings.isAppleEnabled)
            Toggle("Claude", isOn: $settings.isClaudeEnabled)
            Picker("Claude Model", selection: $settings.claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .disabled(!settings.isClaudeEnabled)
            Divider()

            if !DoubleCopyMonitor.isTrusted {
                Button("Allow Accessibility to Use ⌘C ⌘C…") {
                    DoubleCopyMonitor.requestPermission()
                }
                Divider()
            }
            Button("Quit Emebal") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = TranslationPanel()
    private var monitor: DoubleCopyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = DoubleCopyMonitor { [weak self] text in
            self?.translate(text)
        }
        monitor.start()
        self.monitor = monitor
    }

    func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return }
        translate(text)
    }

    private func translate(_ text: String) {
        panel.show(text: text, settings: AppSettings.shared)
    }
}
