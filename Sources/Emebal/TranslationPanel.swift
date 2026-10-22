import AppKit
import SwiftUI

/// Whether the user resized the panel. Until then, the panel follows the
/// view's size; after that, the view fills whatever size the user chose.
@MainActor
@Observable
final class PanelLayout {
    var isResized = false
    /// Height of the panel's (invisible) title bar. The header is drawn
    /// inside it, so the panel has no empty strip at the top.
    var titlebarHeight: CGFloat = 0
}

/// A floating panel that shows the translations. It doesn't take focus from
/// the app the text was copied from, and can be dragged and resized. It
/// closes with ✕ or Esc, and, unless the user turned it off, when they click
/// in another app.
@MainActor
final class TranslationPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hosting: NSHostingView<TranslationView>?
    private var model: TranslationModel?
    private var layout: PanelLayout?
    private var clickOutsideMonitor: Any?

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
        // With a full-size content view, the frame includes the title bar but
        // the layout rect doesn't, so the difference is the title bar height.
        panel.setContentSize(NSSize(width: 400, height: 300))
        layout.titlebarHeight = panel.frame.height - panel.contentLayoutRect.height
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
            panel.setContentSize(capped(hosting.intrinsicContentSize, on: Self.screenUnderMouse()))
            if let previousFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: previousFrame.minX, y: previousFrame.maxY))
            } else {
                position(panel)
            }
        }
        keepOnScreen(panel)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hosting = hosting
        self.model = model
        self.layout = layout
        model.start()

        if settings.closesOnClickOutside {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closeIfClickedOutside()
                }
            }
        }
    }

    func close() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        model?.cancel()
        model = nil
        panel?.close()
        panel = nil
        hosting = nil
        layout = nil
    }

    /// Closes the panel, unless the click was on it. Moving and resizing the
    /// panel are handled by macOS, so those clicks also arrive here, and the
    /// resize handles reach a few points beyond the panel's edge.
    private func closeIfClickedOutside() {
        guard let panel else { return }
        if panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { return }
        close()
    }

    /// The panel can be dragged by its background, so a double-click there
    /// counts as a title-bar double-click, which zooms the window to fill the
    /// screen. The panel sizes itself, or the user resizes it, so never zoom.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
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
        let size = capped(hosting.intrinsicContentSize, on: panel.screen)
        let current = panel.contentRect(forFrameRect: panel.frame).size
        guard size != current else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        // Growing down from the top can push it under the Dock, or past
        // another edge: move it back inside the screen.
        keepOnScreen(panel)
    }

    /// Moves the panel so it fits in the screen's usable area (without the
    /// menu bar and the Dock), with a small margin. When it's taller than the
    /// space, the top wins, so the header and its language menu stay reachable.
    private func keepOnScreen(_ panel: NSPanel) {
        guard let visible = (panel.screen ?? Self.screenUnderMouse())?.visibleFrame else { return }
        let origin = Self.origin(keeping: panel.frame, inside: visible)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    /// Where `frame` must move to fit in `visible`, `margin` points from its
    /// edges. The left and top edges are applied last, so they win when the
    /// frame is larger than the space.
    static func origin(keeping frame: NSRect, inside visible: NSRect, margin: CGFloat = 8) -> NSPoint {
        var origin = frame.origin
        origin.x = min(origin.x, visible.maxX - margin - frame.width)
        origin.x = max(origin.x, visible.minX + margin)
        origin.y = max(origin.y, visible.minY + margin)
        origin.y = min(origin.y, visible.maxY - margin - frame.height)
        return origin
    }

    /// Limits the size Emebal gives the panel by itself, so long text never
    /// makes it cover the screen. The user can still make it larger.
    private func capped(_ size: NSSize, on screen: NSScreen?) -> NSSize {
        guard let visible = screen?.visibleFrame else { return size }
        return NSSize(
            width: min(size.width, visible.width * 0.8),
            height: min(size.height, visible.height * 0.6)
        )
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Places the panel just below the mouse, kept inside the visible screen.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let visible = Self.screenUnderMouse()?.visibleFrame else { return }

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

