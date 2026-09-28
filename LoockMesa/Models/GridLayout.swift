import Foundation

struct PlacementRequest {
    let kind: WidgetKind
    let size: CGSize
    let preferred: CGRect
}
/// A 180-point pitch accommodates P (164) and M/G (344) with a 16-point gap.
/// Pure geometry: deterministic, testable, and independent from WindowServer.
enum DesktopGrid {
    static let pitch: CGFloat = 180
    static let inset: CGFloat = 20
    static let gap: CGFloat = 16
    static func candidates(size: CGSize, screen: CGRect) -> [CGRect] {
        let usable = screen.insetBy(dx: inset, dy: inset)
        guard size.width <= usable.width, size.height <= usable.height else { return [] }
        let columns = Int(floor((usable.width - size.width) / pitch)) + 1
        let rows = Int(floor((usable.height - size.height) / pitch)) + 1
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGRect(x: usable.minX + CGFloat(column) * pitch, y: usable.maxY - CGFloat(row) * pitch - size.height, width: size.width, height: size.height)
            }
        }
    }
    static func conflicts(_ a: CGRect, _ b: CGRect) -> Bool {
        !(a.maxX + gap <= b.minX + 0.1 || b.maxX + gap <= a.minX + 0.1 || a.maxY + gap <= b.minY + 0.1 || b.maxY + gap <= a.minY + 0.1)
    }
    static func nearest(size: CGSize, to preferred: CGRect, screens: [CGRect], occupied: [CGRect]) -> CGRect? {
        let options = screens.flatMap { candidates(size: size, screen: $0) }
        // Top-left anchoring keeps a resized widget at the same grid origin.
        return options.enumerated().filter { _, candidate in !occupied.contains { conflicts(candidate, $0) } }
            .min { a, b in
                let da = pow(a.element.minX - preferred.minX, 2) + pow(a.element.maxY - preferred.maxY, 2)
                let db = pow(b.element.minX - preferred.minX, 2) + pow(b.element.maxY - preferred.maxY, 2)
                return da == db ? a.offset < b.offset : da < db
            }?.element
    }
    static func arrange(_ requests: [PlacementRequest], screens: [CGRect]) -> [WidgetKind: CGRect] {
        var result: [WidgetKind: CGRect] = [:]
        for item in requests {
            if let frame = nearest(size: item.size, to: item.preferred, screens: screens, occupied: Array(result.values)) { result[item.kind] = frame }
        }
        return result
    }
}
