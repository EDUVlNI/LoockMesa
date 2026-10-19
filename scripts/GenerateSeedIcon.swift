import AppKit

@main struct GenerateSeedIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let rect = CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
                NSColor(srgbRed: 0.15, green: 0.25, blue: 0.18, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(pixels) * 0.06, dy: CGFloat(pixels) * 0.06), xRadius: CGFloat(pixels) * 0.2, yRadius: CGFloat(pixels) * 0.2).fill()
                GergelimSeed.image(size: CGFloat(pixels), template: false).draw(in: rect.insetBy(dx: CGFloat(pixels) * 0.2, dy: CGFloat(pixels) * 0.2))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
