import AppKit

/// Menu bar glyphs matching the app icon: a shield between radio waves.
/// Allowed: outlined shield, two waves each side. Held down: filled shield, inner waves only.
enum MenuBarIcon {
    static func image(heldDown: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Drawn on a 20-unit grid.
            let t = NSAffineTransform()
            t.scale(by: 0.9)
            t.concat()
            NSColor.black.set()

            let shield = NSBezierPath()
            shield.move(to: NSPoint(x: 10, y: 6.6))
            shield.line(to: NSPoint(x: 12.6, y: 7.6))
            shield.line(to: NSPoint(x: 12.6, y: 10))
            shield.curve(to: NSPoint(x: 10, y: 13.6), controlPoint1: NSPoint(x: 12.6, y: 11.7),
                         controlPoint2: NSPoint(x: 11.5, y: 12.8))
            shield.curve(to: NSPoint(x: 7.4, y: 10), controlPoint1: NSPoint(x: 8.5, y: 12.8),
                         controlPoint2: NSPoint(x: 7.4, y: 11.7))
            shield.line(to: NSPoint(x: 7.4, y: 7.6))
            shield.close()
            // Top-heavy shape: nudge it down to look centred between the waves, as in the app icon.
            shield.transform(using: AffineTransform(translationByX: 0, byY: 0.4))
            shield.lineWidth = 1.5
            shield.lineJoinStyle = .round
            heldDown ? shield.fill() : shield.stroke()
            if heldDown { shield.stroke() }

            for radius in heldDown ? [6.2] : [6.2, 9.6] {
                for mid in [180.0, 0.0] {
                    let wave = NSBezierPath()
                    wave.appendArc(withCenter: NSPoint(x: 10, y: 10), radius: radius,
                                   startAngle: mid - 45, endAngle: mid + 45)
                    wave.lineWidth = 1.5
                    wave.lineCapStyle = .round
                    wave.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = heldDown ? "AWDL held down" : "AWDL allowed"
        return image
    }
}
