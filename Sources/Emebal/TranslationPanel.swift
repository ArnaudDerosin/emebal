import AppKit
import SwiftUI

/// A floating panel near the mouse that shows the translations. It doesn't
/// take focus from the app the text was copied from.
@MainActor
final class TranslationPanel {
    private var panel: NSPanel?
    private var model: TranslationModel?
    private var clickOutsideMonitor: Any?

    func show(text: String, settings: AppSettings) {
        close()

        let model = TranslationModel(text: text, settings: settings)
        let hosting = NSHostingController(rootView: TranslationView(model: model, onClose: { [weak self] in
            self?.close()
        }))
        // The panel follows the view's size, so it grows when translations arrive.
        hosting.sizingOptions = .preferredContentSize

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        position(panel)
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        model.start()

        // Close when the user clicks in another app.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }

    func close() {
        model?.cancel()
        model = nil
        panel?.close()
        panel = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    /// Places the panel just below the mouse, kept inside the visible screen.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 {
            // Not enough room below the mouse: show it above instead.
            origin.y = min(mouse.y + 16, visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }
}
