import SwiftUI

// Reused unchanged from the user's FreeClip/Eko project.
struct FreeClipIcon: View {
    var body: some View {
        Rectangle().fill(.primary).mask {
            Canvas { context, size in
                context.drawLayer { layer in
                    for part in FreeClipSymbol.parts(in: CGRect(origin: .zero, size: size)) {
                        layer.blendMode = part.cutout ? .destinationOut : .normal
                        layer.fill(part.path, with: .color(.white))
                    }
                }
            }
        }
    }
}

enum FreeClipSymbol {
    struct Part { let path: Path; let cutout: Bool }
    static func parts(in rect: CGRect) -> [Part] {
        // Contours follow the supplied 270 x 286 reference, without an added outline.
        var rear = Path()
        rear.move(to: CGPoint(x: 151, y: 3))
        rear.addCurve(to: CGPoint(x: 186, y: 25), control1: CGPoint(x: 166, y: 2), control2: CGPoint(x: 178, y: 13))
        rear.addCurve(to: CGPoint(x: 247, y: 33), control1: CGPoint(x: 208, y: 17), control2: CGPoint(x: 233, y: 21))
        rear.addCurve(to: CGPoint(x: 266, y: 105), control1: CGPoint(x: 270, y: 52), control2: CGPoint(x: 277, y: 81))
        rear.addCurve(to: CGPoint(x: 262, y: 145), control1: CGPoint(x: 277, y: 119), control2: CGPoint(x: 270, y: 134))
        rear.addCurve(to: CGPoint(x: 190, y: 178), control1: CGPoint(x: 247, y: 167), control2: CGPoint(x: 210, y: 180))
        rear.addCurve(to: CGPoint(x: 159, y: 153), control1: CGPoint(x: 171, y: 177), control2: CGPoint(x: 160, y: 168))
        rear.addCurve(to: CGPoint(x: 177, y: 115), control1: CGPoint(x: 151, y: 134), control2: CGPoint(x: 161, y: 124))
        rear.addCurve(to: CGPoint(x: 247, y: 93), control1: CGPoint(x: 202, y: 100), control2: CGPoint(x: 230, y: 85))
        rear.addCurve(to: CGPoint(x: 237, y: 49), control1: CGPoint(x: 254, y: 77), control2: CGPoint(x: 248, y: 59))
        rear.addCurve(to: CGPoint(x: 194, y: 44), control1: CGPoint(x: 226, y: 39), control2: CGPoint(x: 209, y: 39))
        rear.addCurve(to: CGPoint(x: 174, y: 87), control1: CGPoint(x: 198, y: 61), control2: CGPoint(x: 187, y: 81))
        rear.addCurve(to: CGPoint(x: 117, y: 77), control1: CGPoint(x: 157, y: 98), control2: CGPoint(x: 132, y: 90))
        rear.addCurve(to: CGPoint(x: 113, y: 24), control1: CGPoint(x: 106, y: 61), control2: CGPoint(x: 105, y: 40))
        rear.addCurve(to: CGPoint(x: 151, y: 3), control1: CGPoint(x: 121, y: 10), control2: CGPoint(x: 137, y: 3))
        rear.closeSubpath()

        var front = Path()
        front.move(to: CGPoint(x: 77, y: 99))
        front.addCurve(to: CGPoint(x: 119, y: 132), control1: CGPoint(x: 99, y: 97), control2: CGPoint(x: 119, y: 111))
        front.addCurve(to: CGPoint(x: 99, y: 170), control1: CGPoint(x: 121, y: 148), control2: CGPoint(x: 111, y: 162))
        front.addCurve(to: CGPoint(x: 45, y: 174), control1: CGPoint(x: 81, y: 184), control2: CGPoint(x: 61, y: 184))
        front.addCurve(to: CGPoint(x: 32, y: 161), control1: CGPoint(x: 39, y: 171), control2: CGPoint(x: 35, y: 166))
        front.addCurve(to: CGPoint(x: 32, y: 221), control1: CGPoint(x: 15, y: 180), control2: CGPoint(x: 18, y: 206))
        front.addCurve(to: CGPoint(x: 61, y: 235), control1: CGPoint(x: 41, y: 230), control2: CGPoint(x: 49, y: 233))
        front.addCurve(to: CGPoint(x: 99, y: 206), control1: CGPoint(x: 72, y: 220), control2: CGPoint(x: 82, y: 213))
        front.addCurve(to: CGPoint(x: 146, y: 202), control1: CGPoint(x: 116, y: 198), control2: CGPoint(x: 131, y: 194))
        front.addCurve(to: CGPoint(x: 170, y: 240), control1: CGPoint(x: 165, y: 211), control2: CGPoint(x: 174, y: 223))
        front.addCurve(to: CGPoint(x: 139, y: 270), control1: CGPoint(x: 167, y: 253), control2: CGPoint(x: 153, y: 263))
        front.addCurve(to: CGPoint(x: 88, y: 285), control1: CGPoint(x: 119, y: 281), control2: CGPoint(x: 104, y: 288))
        front.addCurve(to: CGPoint(x: 58, y: 254), control1: CGPoint(x: 70, y: 283), control2: CGPoint(x: 59, y: 270))
        front.addCurve(to: CGPoint(x: 14, y: 221), control1: CGPoint(x: 38, y: 249), control2: CGPoint(x: 23, y: 238))
        front.addCurve(to: CGPoint(x: 12, y: 169), control1: CGPoint(x: 4, y: 204), control2: CGPoint(x: 4, y: 186))
        front.addCurve(to: CGPoint(x: 34, y: 140), control1: CGPoint(x: 16, y: 157), control2: CGPoint(x: 27, y: 146))
        front.addCurve(to: CGPoint(x: 77, y: 99), control1: CGPoint(x: 35, y: 117), control2: CGPoint(x: 53, y: 99))
        front.closeSubpath()

        func slit(_ rect: CGRect, angle: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        }
        let parts = [Part(path: rear, cutout: false), Part(path: front, cutout: false),
                     Part(path: slit(CGRect(x: 143, y: 39, width: 8, height: 23), angle: -0.42), cutout: true),
                     Part(path: slit(CGRect(x: 220, y: 120, width: 26, height: 7), angle: -0.44), cutout: true),
                     Part(path: slit(CGRect(x: 90, y: 122, width: 13, height: 28), angle: 0.37), cutout: true),
                     Part(path: slit(CGRect(x: 73, y: 251, width: 19, height: 7), angle: -0.44), cutout: true)]
        let scale = min(rect.width / 270, rect.height / 286)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - 135 * scale, y: rect.midY - 143 * scale))
        return parts.map { Part(path: $0.path.applying(transform), cutout: $0.cutout) }
    }
}
