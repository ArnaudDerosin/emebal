import AppKit
import SwiftUI

/// Whether the user resized the panel. Until then, the panel follows the
/// view's size; after that, the view fills whatever size the user chose.
@MainActor
@Observable
final class PanelLayout {
    var isResized = false
}

/// A floating panel that shows the translations. It doesn't take focus from
/// the app the text was copied from, can be dragged and resized, and stays
/// open until the user closes it (✕ or Esc).
@MainActor
final class TranslationPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hosting: NSHostingView<TranslationView>?
    private var model: TranslationModel?
    private var layout: PanelLayout?

    func show(text: String, settings: AppSettings) {
        // A new translation replaces the open one in the same place, so a
        // panel the user moved aside stays where they put it, and keeps the
        // size they gave it.
        let previousFrame = panel?.frame
        let wasResized = layout?.isResized ?? false
        close()

        let model = TranslationModel(text: text, settings: settings)
        let layout = PanelLayout()
        layout.isResized = wasResized
        let view = TranslationView(
            model: model,
            layout: layout,
            onClose: { [weak self] in self?.close() },
            // Until the user resizes it, the panel fits the view, so it grows
            // when translations arrive. Fit after SwiftUI applies the change.
            onContentChange: { [weak self] in
                DispatchQueue.main.async { self?.fitToContent() }
            }
        )
        let hosting = NSHostingView(rootView: view)
        // The panel gets the view's minimum size but never a maximum, so the
        // user can resize it freely. (A hosting controller's preferred size
        // would stop the user from resizing it.) The intrinsic size is the
        // view's ideal size, which the panel fits until the user resizes it.
        hosting.sizingOptions = [.minSize, .intrinsicContentSize]
        // Start the content at the top: the title bar has no buttons or title.
        hosting.safeAreaRegions = []

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // The header has its own close button (✕, or Esc). The panel stays
        // titled anyway, for its rounded corners, shadow and resizing.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.delegate = self
        if let previousFrame, wasResized {
            panel.setFrame(previousFrame, display: false)
        } else {
            panel.setContentSize(hosting.intrinsicContentSize)
            if let previousFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: previousFrame.minX, y: previousFrame.maxY))
            } else {
                position(panel)
            }
        }
        panel.orderFrontRegardless()

        self.panel = panel
        self.hosting = hosting
        self.model = model
        self.layout = layout
        model.start()
    }

    func close() {
        model?.cancel()
        model = nil
        panel?.close()
        panel = nil
        hosting = nil
        layout = nil
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        // From now on the user's size wins. The view's minimum still applies,
        // so the content never gets cut off.
        layout?.isResized = true
    }

    /// Resizes the panel to the view's ideal size, keeping its top-left corner
    /// in place, unless the user has resized it.
    private func fitToContent() {
        guard let panel, let hosting, layout?.isResized == false else { return }
        let size = hosting.intrinsicContentSize
        let current = panel.contentRect(forFrameRect: panel.frame).size
        guard size != current else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
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

