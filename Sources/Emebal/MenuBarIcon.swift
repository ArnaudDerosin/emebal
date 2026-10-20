import AppKit

/// The menu-bar icon: an octagonal speech bubble with two cuneiform wedges
/// cut out of it, pointing in opposite directions (eme-bal, "tongue-turner").
/// Drawn in code from the 18×18 template SVG, so it needs no resource bundle,
/// and marked as a template so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            // Bubble, with its tail at the bottom right.
            addPolygon(to: path, [
                (4, 1), (14, 1), (17, 4), (17, 10), (14, 13),
                (14, 16.5), (10.5, 13), (4, 13), (1, 10), (1, 4),
            ])
            // Top wedge, head on the left.
            addPolygon(to: path, [
                (5, 3), (7.75, 4.25), (13, 4.5), (13, 5), (7.75, 5.25), (5, 6.5),
            ])
            // Bottom wedge, head on the right.
            addPolygon(to: path, [
                (13, 11), (10.25, 9.75), (5, 9.5), (5, 9), (10.25, 8.75), (13, 7.5),
            ])
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Emebal"
        return image
    }()

    private static func addPolygon(to path: NSBezierPath, _ points: [(CGFloat, CGFloat)]) {
        guard let first = points.first else { return }
        path.move(to: NSPoint(x: first.0, y: first.1))
        for point in points.dropFirst() {
            path.line(to: NSPoint(x: point.0, y: point.1))
        }
        path.close()
    }
}
