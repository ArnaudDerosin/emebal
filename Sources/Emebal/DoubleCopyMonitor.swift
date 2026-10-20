import AppKit
import ApplicationServices

/// Detects ⌘C pressed twice in a row in any app, then reads the copied text.
///
/// Watching key presses in other apps needs the Accessibility permission.
@MainActor
final class DoubleCopyMonitor {
    /// Maximum time between the two ⌘C presses.
    private let interval: TimeInterval = 0.4
    /// How long to wait for the second ⌘C to reach the clipboard.
    private let clipboardWait: TimeInterval = 0.3

    private var monitor: Any?
    private var lastCopyAt: Date?
    private var permissionTask: Task<Void, Never>?
    private let onDoubleCopy: (String) -> Void

    init(onDoubleCopy: @escaping (String) -> Void) {
        self.onDoubleCopy = onDoubleCopy
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that sends the user to Accessibility settings.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        if Self.isTrusted {
            installMonitor()
            return
        }
        Self.requestPermission()
        // Waiting for the user to grant the permission in System Settings.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Self.isTrusted {
                    self?.installMonitor()
                    return
                }
            }
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // keyCode 8 is the C key (kVK_ANSI_C), whatever the keyboard layout's letter.
            guard flags == .command, event.keyCode == 8, !event.isARepeat else { return }
            MainActor.assumeIsolated {
                self?.handleCopy()
            }
        }
    }

    private func handleCopy() {
        let now = Date()
        if let last = lastCopyAt, now.timeIntervalSince(last) <= interval {
            lastCopyAt = nil
            readClipboardAfterCopy()
        } else {
            lastCopyAt = now
        }
    }

    /// The key press arrives before the app writes to the clipboard, so wait
    /// for the clipboard to change (or a short timeout) before reading it.
    private func readClipboardAfterCopy() {
        Task { [weak self, clipboardWait] in
            let pasteboard = NSPasteboard.general
            let startCount = pasteboard.changeCount
            let deadline = ContinuousClock.now + .seconds(clipboardWait)
            // Waiting for the second ⌘C to land in the clipboard.
            while pasteboard.changeCount == startCount, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard let text = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            self?.onDoubleCopy(text)
        }
    }
}
