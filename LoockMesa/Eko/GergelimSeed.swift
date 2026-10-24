import AppKit

enum GergelimSeed {
    static func image(size: CGFloat = 18, template: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let context = NSGraphicsContext.current!.cgContext
            context.scaleBy(x: rect.width / 18, y: rect.height / 18)
            let seed = NSBezierPath()
            seed.move(to: NSPoint(x: 12.8, y: 16.6))
            seed.curve(to: NSPoint(x: 3.8, y: 3.2), controlPoint1: NSPoint(x: 6, y: 15.7), controlPoint2: NSPoint(x: 0.5, y: 7))
            seed.curve(to: NSPoint(x: 14.3, y: 5.8), controlPoint1: NSPoint(x: 6.8, y: -0.1), controlPoint2: NSPoint(x: 12.9, y: 1.5))
            seed.curve(to: NSPoint(x: 12.8, y: 16.6), controlPoint1: NSPoint(x: 16.4, y: 11.1), controlPoint2: NSPoint(x: 13.5, y: 13.9))
            seed.close()
            (template ? NSColor.black : NSColor(srgbRed: 0.88, green: 0.76, blue: 0.51, alpha: 1)).setFill(); seed.fill()
            context.setBlendMode(.clear)
            let seam = NSBezierPath(); seam.move(to: NSPoint(x: 6, y: 4))
            seam.curve(to: NSPoint(x: 11.8, y: 13.6), controlPoint1: NSPoint(x: 9.3, y: 5.1), controlPoint2: NSPoint(x: 9, y: 11.2))
            seam.lineWidth = 0.75; seam.lineCapStyle = .round; seam.stroke()
            return true
        }
        image.isTemplate = template; image.accessibilityDescription = "Gergelim"
        return image
    }
}
