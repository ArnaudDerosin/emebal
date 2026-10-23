import AppKit
import SwiftUI

@main
struct EmebalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared
    @State private var loginItem = LoginItem.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(settings: settings, loginItem: loginItem) {
                appDelegate.translateClipboard()
            }
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
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
        AppSettings.shared.updateReadyClaude()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave a waiting Claude Code behind.
        ReadyClaude.shared.stop()
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
