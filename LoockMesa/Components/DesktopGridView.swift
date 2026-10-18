import SwiftUI
import AppKit

struct DesktopGridView: View {
    var topInset: CGFloat = 0
    var leftInset: CGFloat = 0
    var body: some View {
        Canvas { context, size in
            let margin = DesktopGrid.inset
            // Small dots explain the plane; larger dots mark actual snapping origins.
            for row in stride(from: margin + topInset, through: size.height - margin, by: 30) {
                for column in stride(from: margin + leftInset, through: size.width - margin, by: 30) {
                    let primary = Int((column - margin - leftInset).rounded()) % 180 == 0 && Int((row - margin - topInset).rounded()) % 180 == 0
                    let radius: CGFloat = primary ? 2.8 : 1.1
                    let dot = Path(ellipseIn: CGRect(x: column - radius, y: row - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(.white.opacity(primary ? 0.7 : 0.22)))
                }
            }
        }.background(LinearGradient(colors: [.black.opacity(0.11), .black.opacity(0.08), .black.opacity(0.05)], startPoint: .top, endPoint: .bottom)).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Draw in the panel's exact bounds, independent of SwiftUI safe areas/intrinsic size.
final class DesktopGuideView: NSView {
    var topInset: CGFloat = 0
    var leftInset: CGFloat = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor.black.withAlphaComponent(0.11), NSColor.black.withAlphaComponent(0.08), NSColor.black.withAlphaComponent(0.05)])?.draw(in: bounds, angle: -90)
        let margin = DesktopGrid.inset
        for row in stride(from: margin + topInset, through: bounds.height - margin, by: 30) {
            for column in stride(from: margin + leftInset, through: bounds.width - margin, by: 30) {
                let primary = Int((column - margin - leftInset).rounded()) % 180 == 0 && Int((row - margin - topInset).rounded()) % 180 == 0
                let radius: CGFloat = primary ? 2.8 : 1.1
                NSColor.white.withAlphaComponent(primary ? 0.7 : 0.22).setFill()
                NSBezierPath(ovalIn: NSRect(x: column - radius, y: row - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }
    }
}
