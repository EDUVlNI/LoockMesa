import SwiftUI
import AppKit

struct AnalogClock: View {
    let date: Date
    var dark = false
    private var ink: Color { dark ? .white : .black }
    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let center = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let radius = side / 2
            Canvas { context, _ in
                let face = CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side)
                context.fill(Path(ellipseIn: face), with: .color(CardPalette.base(light: !dark)))
                for i in 0..<60 {
                    let angle = Double(i) * .pi / 30
                    let outer = radius * 0.92; let inner = radius * (i % 5 == 0 ? 0.84 : 0.885)
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + sin(angle) * inner, y: center.y - cos(angle) * inner))
                    tick.addLine(to: CGPoint(x: center.x + sin(angle) * outer, y: center.y - cos(angle) * outer))
                    context.stroke(tick, with: .color(ink.opacity(i % 5 == 0 ? 0.85 : 0.25)), lineWidth: i % 5 == 0 ? 1.5 : 0.8)
                }
                for n in 1...12 {
                    let angle = Double(n) * .pi / 6
                    context.draw(Text("\(n)").font(.system(size: side * 0.12, weight: .regular)).foregroundColor(ink), at: CGPoint(x: center.x + sin(angle) * radius * 0.68, y: center.y - cos(angle) * radius * 0.68))
                }
                let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
                let minute = Double(c.minute ?? 0); let second = Double(c.second ?? 0)
                func hand(_ angle: Double, length: Double, width: Double, color: Color, tail: Double = 0.09) {
                    var path = Path()
                    path.move(to: CGPoint(x: center.x - sin(angle) * radius * tail, y: center.y + cos(angle) * radius * tail))
                    path.addLine(to: CGPoint(x: center.x + sin(angle) * radius * length, y: center.y - cos(angle) * radius * length))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                hand((Double((c.hour ?? 0) % 12) + minute / 60) * .pi / 6, length: 0.45, width: side * 0.037, color: ink)
                hand((minute + second / 60) * .pi / 30, length: 0.72, width: side * 0.026, color: ink)
                hand(second * .pi / 30, length: 0.81, width: 1.4, color: .orange, tail: 0.2)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(.orange))
            }
        }.accessibilityLabel(date.formatted(date: .omitted, time: .standard))
    }
}
struct BatteryRing: View {
    let symbol: String
    let value: Int?
    var dimension: CGFloat = 58
    var freeClip = false
    var charging = false
    var light = false
    var monochrome = false
    private var accent: Color { monochrome ? ink : Color(red: 0.20, green: 0.88, blue: 0.30) }
    private var ink: Color { light ? .black : .white }
    var body: some View {
        ZStack {
            Circle().stroke(ink.opacity(0.16), lineWidth: dimension * 0.095)
            Circle().trim(from: 0, to: CGFloat(min(100, max(0, value ?? 0))) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: dimension * 0.095, lineCap: .round)).rotationEffect(.degrees(-90))
            if freeClip {
                FreeClipIcon().frame(width: dimension * 0.50, height: dimension * 0.53).foregroundStyle(ink)
            } else if !symbol.isEmpty {
                Image(systemName: symbol == "laptopcomputer" ? DeviceService.nativeMacSymbol : symbol)
                    .font(.system(size: dimension * 0.39, weight: .regular)).foregroundColor(ink)
            }
            if charging {
                ZStack {
                    // A silhouette outline follows the bolt, without a circular badge.
                    ForEach(0..<8, id: \.self) { step in
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(CardPalette.base(light: light))
                            .offset(x: cos(Double(step) * .pi / 4) * 1.5,
                                    y: sin(Double(step) * .pi / 4) * 1.5)
                    }
                    Image(systemName: "bolt.fill").foregroundStyle(accent)
                }
                .font(.system(size: dimension * 0.23, weight: .semibold))
                .offset(y: -dimension * 0.49)
                .accessibilityHidden(true)
            }
        }.frame(width: dimension, height: dimension)
    }
}

/// Uses the compositor's native backdrop, with no wallpaper capture or polling.
/// A transparent desktop panel lets behindWindow sample the wallpaper underneath.
private struct FrostIntensityKey: EnvironmentKey { static let defaultValue: Double = 0.7 }
extension EnvironmentValues {
    var frostIntensity: Double {
        get { self[FrostIntensityKey.self] }
        set { self[FrostIntensityKey.self] = newValue }
    }
}
struct FrostedWidgetBackground: NSViewRepresentable {
    @Environment(\.frostIntensity) private var intensity
    var light: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassiveMaterialView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 23
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        // Public APIs do not expose a blur-radius knob. Blend the native material
        // instead, leaving foreground text/icons fully opaque.
        view.alphaValue = min(1, max(0, intensity))
        view.isHidden = intensity <= 0
        // AppKit handles Reduce Transparency and appearance changes itself.
    }
    private final class PassiveMaterialView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Ventura-compatible transition, scheduled only when the displayed value changes.
struct AnimatedValue: View {
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack { Text(value).id(value).transition(reduceMotion ? .identity : .asymmetric(
            insertion: .modifier(active: NumberBlur(amount: 1), identity: NumberBlur(amount: 0)),
            removal: .opacity)) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: value)
    }
}
private struct NumberBlur: ViewModifier {
    var amount: Double
    func body(content: Content) -> some View {
        content.blur(radius: amount * 5).opacity(1 - amount).offset(y: amount * 5)
    }
}


enum CardPalette {
    static func base(light: Bool) -> Color { Color(white: light ? 0.97 : 0.125) }
}
/// Solid cards share a neutral palette; frosted cards retain the native backdrop
/// without an opaque tint, preserving wallpaper colors and individual intensity.
struct HarmonizedCardBackground: View {
    var light: Bool
    var frosted: Bool
    var body: some View {
        if frosted {
            FrostedWidgetBackground(light: light).allowsHitTesting(false)
        } else { CardPalette.base(light: light) }
    }
}

/// Isolates entrance updates from live widget content and keeps one animation owner.
final class WidgetEntranceState: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var isUnlock = false
    private(set) var prepared = false
    private var hasAppeared = false
    /// SwiftUI may restart its task after a Space transition. Only a new widget gets an entrance.
    func appear(reduceMotion: Bool) {
        guard !hasAppeared, !prepared else { return }
        hasAppeared = true
        play(unlock: false, reduceMotion: reduceMotion)
    }
    private var task: Task<Void, Never>?
    private var generation = 0
    func prepareUnlock() {
        cancel()
        prepared = true
        reset(unlock: true)
    }
    func finish() {
        cancel(); prepared = false
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 1 }
    }
    private func cancel() { generation += 1; task?.cancel(); task = nil }
    private func reset(unlock: Bool) {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { isUnlock = unlock; progress = 0 }
    }
    func play(unlock: Bool, delay: Double = 0, reduceMotion: Bool) {
        cancel()
        if reduceMotion { finish(); return }
        if !prepared || !unlock { reset(unlock: unlock) }
        prepared = false
        let current = generation
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(max(0.016, delay) * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.generation == current else { return }
            withAnimation(.timingCurve(0.18, 0.72, 0.22, 1, duration: unlock ? 0.48 : 0.38)) { self.progress = 1 }
            self.task = nil
        }
    }
    func withdraw(reduceMotion: Bool) {
        cancel(); prepared = false
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { progress = 0 }
    }
    deinit { task?.cancel() }
}
struct WidgetEntranceEffect: ViewModifier {
    @ObservedObject var state: WidgetEntranceState
    func body(content: Content) -> some View {
        content
            .scaleEffect(state.isUnlock ? 0.975 + 0.025 * state.progress : 1)
            .blur(radius: (1 - state.progress) * (state.isUnlock ? 3 : 9))
            .opacity(state.progress)
    }
}
