import SwiftUI
import AppKit
import CoreText

private struct WidgetPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var widgetPreview: Bool {
        get { self[WidgetPreviewKey.self] }
        set { self[WidgetPreviewKey.self] = newValue }
    }
}

private struct ClearWidgetSurfaceKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var clearWidgetSurface: Bool {
        get { self[ClearWidgetSurfaceKey.self] }
        set { self[ClearWidgetSurfaceKey.self] = newValue }
    }
}
struct ClearWidgetBackground: View {
    @Environment(\.frostIntensity) private var intensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(red: 0.10, green: 0.17, blue: 0.26) }
            else {
                FrostedWidgetBackground(light: false)
                Color(red: 0.10, green: 0.20, blue: 0.34).opacity(0.12 + intensity * 0.38)
            }
            RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
        }.allowsHitTesting(false)
    }
}
enum ClockTypography {
    private static let digitalFonts = NSCache<NSNumber, NSFont>()
    static func analog(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func digital(size: CGFloat) -> Font {
        let key = NSNumber(value: Double(size))
        if let cached = digitalFonts.object(forKey: key) { return Font(cached) }
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        let features: [[String: Any]] = [
            [kCTFontOpenTypeFeatureTag as String: "ss04", kCTFontOpenTypeFeatureValue as String: 1],
            [kCTFontOpenTypeFeatureTag as String: "cv09", kCTFontOpenTypeFeatureValue as String: 1]
        ]
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontFeatureSettingsAttribute as String): features
        ])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        digitalFonts.setObject(font, forKey: key)
        return Font(font)
    }
}

struct ClockDisplaySnapshot {
    var date: Date
    var angles: ClockHandAngles
    init(date: Date) { self.date = date; self.angles = .at(date) }
}

final class ClockPlaybackState: ObservableObject {
    @Published private(set) var snapshot = ClockDisplaySnapshot(date: Date())
    private(set) var angles: ClockHandAngles {
        get { snapshot.angles }
        set { var value = snapshot; value.angles = newValue; snapshot = value }
    }
    private(set) var inactive = false
    private(set) var timerStarts = 0
    var isTicking: Bool { timer?.isValid == true }
    private var timer: Timer?
    private var live = false
    private var systemPaused = false
    private var lowPower = false
    private var reduceMotion = false
    private var recovery: Task<Void, Never>?
    private var generation = 0
    func configure(live: Bool, inactive: Bool, lowPower: Bool, reduceMotion: Bool) {
        self.live = live; self.lowPower = lowPower; self.reduceMotion = reduceMotion
        guard live else { stop(); return }
        setInactive(inactive, reduceMotion: reduceMotion)
        if !inactive && !systemPaused { startTimer() }
    }
    func setSystemPaused(_ value: Bool) {
        guard systemPaused != value else { return }
        systemPaused = value
        if value { stop() }
        else if live && !inactive { startTimer() }
    }
    private func startTimer() {
        guard timer == nil, live, !inactive, !systemPaused else { return }
        tick(Date(), reduceMotion: reduceMotion || lowPower)
        let nextSecond = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1)
        let timer = Timer(fire: nextSecond, interval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick(Date(), reduceMotion: self.reduceMotion || self.lowPower)
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer; timerStarts += 1
    }
    func tick(_ date: Date, reduceMotion: Bool = false) {
        guard !inactive, !systemPaused, recovery == nil else { return }
        var value = snapshot
        value.date = date; value.angles = angles.forward(to: .at(date))
        withAnimation(reduceMotion ? nil : .linear(duration: 0.18)) { snapshot = value }
    }
    func setInactive(_ value: Bool, at date: Date = Date(), reduceMotion: Bool) {
        guard inactive != value else { return }
        inactive = value; stop()
        guard !value, !systemPaused else { return }
        if reduceMotion { tick(date, reduceMotion: true); return }
        let from = angles
        let duration = 0.7
        let target = from.forward(to: .at(date.addingTimeInterval(duration)))
        let current = generation
        recovery = Task { @MainActor [weak self] in
            let start = Date()
            while let self, !Task.isCancelled, current == self.generation {
                let progress = min(1, Date().timeIntervalSince(start) / duration)
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { self.angles = from.interpolated(to: target, progress: 1 - pow(1 - progress, 3)) }
                if progress >= 1 {
                    var value = self.snapshot
                    value.date = Date(); value.angles = self.angles.forward(to: .at(value.date))
                    self.snapshot = value; self.recovery = nil
                    return
                }
                do { try await Task.sleep(nanoseconds: self.lowPower ? 33_333_333 : 16_666_667) } catch { return }
            }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        generation += 1; recovery?.cancel(); recovery = nil
    }
    deinit { timer?.invalidate(); recovery?.cancel() }
}

extension Notification.Name {
    static let loockClockActivity = Notification.Name("Loock.clockActivity")
}

struct ClockConfiguration: Equatable {
    let live: Bool
    let inactive: Bool
    let lowPower: Bool
    let reduceMotion: Bool
}

/// Drive lifecycle from AppKit as desktop panels may suspend SwiftUI view callbacks.
struct ClockLifecycleBridge: NSViewRepresentable {
    let playback: ClockPlaybackState
    let configuration: ClockConfiguration
    func makeNSView(context: Context) -> ClockLifecycleView { ClockLifecycleView(frame: .zero) }
    func updateNSView(_ view: ClockLifecycleView, context: Context) { view.update(playback: playback, configuration: configuration) }
    static func dismantleNSView(_ view: ClockLifecycleView, coordinator: ()) { view.detach() }
}

final class ClockLifecycleView: NSView {
    private weak var playback: ClockPlaybackState?
    private var configuration: ClockConfiguration?
    private var generation = 0
    private var activityObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        activityObserver = NotificationCenter.default.addObserver(forName: .loockClockActivity, object: nil, queue: .main) { [weak self] note in
            self?.playback?.setSystemPaused(note.object as? Bool ?? false)
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(playback: ClockPlaybackState, configuration: ClockConfiguration) {
        guard self.playback !== playback || self.configuration != configuration else { return }
        self.playback = playback; self.configuration = configuration
        scheduleConfiguration()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detach() } else { scheduleConfiguration() }
    }
    private func scheduleConfiguration() {
        generation += 1
        let expected = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == expected, self.window != nil,
                  let configuration = self.configuration, let playback = self.playback else { return }
            playback.configure(live: configuration.live, inactive: configuration.inactive,
                               lowPower: configuration.lowPower, reduceMotion: configuration.reduceMotion)
        }
    }
    func detach() { generation += 1; playback?.stop() }
    deinit {
        if let activityObserver { NotificationCenter.default.removeObserver(activityObserver) }
        playback?.stop()
    }
}

struct ModernClockWidget: View {
    let size: WidgetSize
    let digital: Bool
    var dark: Bool
    var frosted: Bool
    var lowPower = false
    var desktopInactive = false
    @StateObject private var playback = ClockPlaybackState()
    @Environment(\.widgetPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let ink: Color = dark ? .white : .black
            ZStack {
                ClockDialDrawing(size: size, digital: digital, ink: ink, angles: playback.angles)
                if digital {
                    AnimatedValue(value: playback.snapshot.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(ClockTypography.digital(size: side * (size == .medium ? 0.70 : 0.64)))
                        .fontWidth(.condensed).monospacedDigit()
                        .tracking(-side * 0.004).foregroundStyle(ink)
                        .fixedSize(horizontal: true, vertical: true)
                        .scaleEffect(x: size == .medium ? 0.76 : 0.54, y: 1, anchor: .center)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .background(ClockLifecycleBridge(playback: playback, configuration: ClockConfiguration(
            live: !preview, inactive: !digital && desktopInactive, lowPower: lowPower, reduceMotion: reduceMotion)))
        .background(HarmonizedCardBackground(light: !dark, frosted: frosted))
    }
}

struct ClockFaceGeometry {
    let dial: CGRect
    let corner: CGFloat
    let marks: [ClockPerimeter.Mark]
    private static func make(_ size: WidgetSize) -> Self {
        let dimensions = size.dimensions
        let dial = CGRect(x: 7, y: 7, width: dimensions.width - 14, height: dimensions.height - 14)
        return Self(dial: dial, corner: 16, marks: (0..<60).map { ClockPerimeter.mark(index: $0, in: dial, corner: 16) })
    }
    private static let small = make(.small)
    private static let medium = make(.medium)
    private static let large = make(.large)
    static func forSize(_ size: WidgetSize) -> Self {
        switch size { case .small: return small; case .medium: return medium; case .large: return large }
    }
}

struct ClockDialDrawing: View, Animatable {
    let size: WidgetSize
    let digital: Bool
    let ink: Color
    var angles: ClockHandAngles
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(angles.hour, AnimatablePair(angles.minute, angles.second)) }
        set { angles = ClockHandAngles(hour: newValue.first, minute: newValue.second.first, second: newValue.second.second) }
    }
    var body: some View {
        Canvas { context, dimensions in
            let side = min(dimensions.width, dimensions.height)
            let center = CGPoint(x: dimensions.width / 2, y: dimensions.height / 2)
            let geometry = ClockFaceGeometry.forSize(size)
            let dial = geometry.dial
            let corner = geometry.corner
            let second = (angles.second * 30 / .pi).truncatingRemainder(dividingBy: 60)
            for i in 0..<60 {
                let mark = geometry.marks[i]
                let active = max(0, 1 - abs(second - Double(i)))
                let elapsed = Double(i) <= second
                let baseLength = side * (digital ? 0.040 : (i % 5 == 0 ? 0.050 : 0.027))
                let length = baseLength + side * CGFloat(active) * 0.016
                var path = Path()
                path.move(to: CGPoint(x: mark.point.x - mark.normal.dx * length, y: mark.point.y - mark.normal.dy * length))
                path.addLine(to: mark.point)
                let baseOpacity = digital ? (elapsed ? 0.78 : 0.18) : (i % 5 == 0 ? 0.72 : 0.30)
                let opacity = baseOpacity + active * (1 - baseOpacity)
                context.stroke(path, with: .color(ink.opacity(opacity)),
                    style: StrokeStyle(lineWidth: side * (digital ? 0.008 : (i % 5 == 0 ? 0.008 : 0.005)), lineCap: .round))
            }
            if !digital {
                for n in [12, 3, 6, 9] {
                    let a = Double(n) * .pi / 6
                    let horizontal = max(0, (dimensions.width - side) / 2)
                    let radiusX = side * 0.31 + horizontal * 0.72
                    context.draw(Text("\(n)").font(ClockTypography.analog(size: side * (size == .large ? 0.115 : 0.13))).foregroundColor(ink),
                                 at: CGPoint(x: center.x + sin(a) * radiusX, y: center.y - cos(a) * side * 0.30))
                }
                func hand(_ angle: Double, _ length: Double, _ width: Double, _ color: Color) {
                    let dx = sin(angle), dy = -cos(angle)
                    let radius = ClockPerimeter.rayDistance(dx: dx, dy: dy, in: dial, corner: corner)
                    var p = Path(); p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + dx * radius * length, y: center.y + dy * radius * length))
                    context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: side * width, lineCap: .round))
                }
                hand(angles.hour, 0.48, 0.035, ink)
                hand(angles.minute, 0.72, 0.026, ink)
                hand(angles.second, 0.78, 0.009, Color(red: 1, green: 0.60, blue: 0))
                context.fill(Path(ellipseIn: CGRect(x: center.x - side * 0.024, y: center.y - side * 0.024, width: side * 0.048, height: side * 0.048)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: center.x - side * 0.012, y: center.y - side * 0.012, width: side * 0.024, height: side * 0.024)), with: .color(.orange))
            }
        }
    }
}

enum ClockPerimeter {
    struct Mark { let point: CGPoint; let normal: CGVector }
    static func mark(index: Int, in rect: CGRect, corner r: CGFloat) -> Mark {
        let horizontal = rect.width - 2 * r
        let vertical = rect.height - 2 * r
        let arc = .pi * r / 2
        let perimeter = 2 * horizontal + 2 * vertical + 4 * arc
        var distance = perimeter * CGFloat(index) / 60
        let parts: [(CGFloat, (CGFloat) -> Mark)] = [
            (horizontal / 2, { Mark(point: CGPoint(x: rect.midX + $0, y: rect.minY), normal: CGVector(dx: 0, dy: -1)) }),
            (arc, { arcMark(center: CGPoint(x: rect.maxX-r, y: rect.minY+r), radius: r, angle: -.pi/2 + $0/r) }),
            (vertical, { Mark(point: CGPoint(x: rect.maxX, y: rect.minY+r+$0), normal: CGVector(dx: 1, dy: 0)) }),
            (arc, { arcMark(center: CGPoint(x: rect.maxX-r, y: rect.maxY-r), radius: r, angle: $0/r) }),
            (horizontal, { Mark(point: CGPoint(x: rect.maxX-r-$0, y: rect.maxY), normal: CGVector(dx: 0, dy: 1)) }),
            (arc, { arcMark(center: CGPoint(x: rect.minX+r, y: rect.maxY-r), radius: r, angle: .pi/2 + $0/r) }),
            (vertical, { Mark(point: CGPoint(x: rect.minX, y: rect.maxY-r-$0), normal: CGVector(dx: -1, dy: 0)) }),
            (arc, { arcMark(center: CGPoint(x: rect.minX+r, y: rect.minY+r), radius: r, angle: .pi + $0/r) }),
            (horizontal / 2, { Mark(point: CGPoint(x: rect.minX+r+$0, y: rect.minY), normal: CGVector(dx: 0, dy: -1)) })
        ]
        for (length, value) in parts {
            if distance <= length { return value(distance) }
            distance -= length
        }
        return Mark(point: CGPoint(x: rect.midX, y: rect.minY), normal: CGVector(dx: 0, dy: -1))
    }
    private static func arcMark(center: CGPoint, radius: CGFloat, angle: CGFloat) -> Mark {
        let normal = CGVector(dx: cos(angle), dy: sin(angle))
        return Mark(point: CGPoint(x: center.x + normal.dx * radius,
                                   y: center.y + normal.dy * radius), normal: normal)
    }
    static func rayDistance(dx: CGFloat, dy: CGFloat, in rect: CGRect, corner: CGFloat) -> CGFloat {
        let halfWidth = rect.width / 2, halfHeight = rect.height / 2
        var lo: CGFloat = 0, hi = hypot(halfWidth, halfHeight)
        for _ in 0..<18 {
            let t = (lo + hi) / 2
            let qx = max(abs(dx * t) - (halfWidth - corner), 0)
            let qy = max(abs(dy * t) - (halfHeight - corner), 0)
            if hypot(qx, qy) <= corner { lo = t } else { hi = t }
        }
        return lo
    }
}
struct DateCardWidget: View {
    let size: WidgetSize
    var dark: Bool
    var frosted: Bool
    @Environment(\.clearWidgetSurface) private var glass
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { time in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(time.date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(glass ? .white : .red)
                    Text(time.date, format: .dateTime.month(.abbreviated)).foregroundStyle(.secondary)
                }.font(.system(size: size == .large ? 32 : 21, weight: .semibold))
                Text(time.date, format: .dateTime.day()).font(.system(size: size == .large ? 205 : 95, weight: .medium, design: .rounded)).minimumScaleFactor(0.6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(19)
        }.foregroundStyle(dark ? .white : .black).background(HarmonizedCardBackground(light: !dark, frosted: frosted))
            .environment(\.locale, Locale(identifier: "pt_BR"))
    }
}
struct ScreenTimeUnavailableWidget: View {
    let size: WidgetSize
    var light: Bool
    var frosted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tempo de Uso", systemImage: "hourglass").font(.headline)
            Text("—").font(.system(size: 38, weight: .light))
            Text("Relatório do macOS indisponível no Loock.").font(.caption)
            if size != .small { Text("Consulte os dados em Ajustes do Sistema → Tempo de Uso.").font(.caption).foregroundStyle(.secondary) }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(light ? .black : .white).background(HarmonizedCardBackground(light: light, frosted: frosted))
    }
}

extension Notification.Name {
    static let loockGalleryDragStarted = Notification.Name("Loock.galleryDragStarted")
    static let loockGalleryDragEnded = Notification.Name("Loock.galleryDragEnded")
    static let loockGalleryDrop = Notification.Name("Loock.galleryDrop")
}
struct GalleryWidgetPayload: Codable {
    let kind: WidgetKind
    let size: WidgetSize
    let variant: String
    static let pasteboardType = NSPasteboard.PasteboardType("com.eduvini.LoockMesa.widget")
}
struct DraggableWidgetPreview: NSViewRepresentable {
    let face: WidgetFace
    let payload: GalleryWidgetPayload
    func makeNSView(context: Context) -> GalleryDragHost { GalleryDragHost(rootView: face, payload: payload) }
    func updateNSView(_ view: GalleryDragHost, context: Context) { view.rootView = face; view.payload = payload }
}
final class GalleryDragHost: NSView {
    private let hosted: NSHostingView<WidgetFace>
    var rootView: WidgetFace { get { hosted.rootView } set { hosted.rootView = newValue } }
    var payload: GalleryWidgetPayload
    init(rootView: WidgetFace, payload: GalleryWidgetPayload) {
        self.payload = payload; hosted = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hosted)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layout() { super.layout(); hosted.frame = bounds }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { return }
            if hypot(next.locationInWindow.x - event.locationInWindow.x,
                     next.locationInWindow.y - event.locationInWindow.y) >= 4 {
                trackDrag(startingWith: next, in: window)
                return
            }
        }
    }
    private func trackDrag(startingWith event: NSEvent, in window: NSWindow) {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size); image.addRepresentation(bitmap)
        let preview = NSPanel(contentRect: CGRect(origin: .zero, size: bounds.size),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isOpaque = false; preview.backgroundColor = .clear; preview.hasShadow = true
        preview.ignoresMouseEvents = true; preview.level = .floating
        preview.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: bounds.size))
        imageView.image = image; imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.alphaValue = 0.90
        preview.contentView = imageView
        func screenPoint(_ input: NSEvent) -> CGPoint { window.convertPoint(toScreen: input.locationInWindow) }
        func position(_ point: CGPoint) {
            preview.setFrameOrigin(CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
        }
        position(screenPoint(event)); preview.orderFrontRegardless()
        NotificationCenter.default.post(name: .loockGalleryDragStarted, object: nil)
        defer {
            preview.orderOut(nil); preview.close()
            NotificationCenter.default.post(name: .loockGalleryDragEnded, object: nil)
        }
        var next: NSEvent? = event
        while let input = next {
            let point = screenPoint(input)
            position(point)
            if input.type == .leftMouseUp {
                if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) {
                    NotificationCenter.default.post(name: .loockGalleryDrop, object: payload, userInfo: ["point": point])
                }
                return
            }
            next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true)
        }
    }
}
final class GalleryDropView: NSView {
    private var destination: CGRect?
    override func draw(_ dirtyRect: NSRect) {
        guard let destination else { return }
        let path = NSBezierPath(roundedRect: destination, xRadius: 23, yRadius: 23)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill(); path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke(); path.lineWidth = 2; path.stroke()
    }
    private func updateDestination(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let window, let data = sender.draggingPasteboard.data(forType: GalleryWidgetPayload.pasteboardType),
              let payload = try? JSONDecoder().decode(GalleryWidgetPayload.self, from: data) else { return [] }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        let size = payload.size.dimensions
        let proposed = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }),
           let snapped = DesktopGrid.nearest(size: size, to: proposed, screens: NSScreen.screens.map(\.visibleFrame), occupied: []) {
            destination = window.convertFromScreen(snapped); needsDisplay = true; return .copy
        }
        destination = nil; needsDisplay = true; return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { destination = nil; needsDisplay = true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([GalleryWidgetPayload.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDestination(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDestination(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = sender.draggingPasteboard.data(forType: GalleryWidgetPayload.pasteboardType),
              let payload = try? JSONDecoder().decode(GalleryWidgetPayload.self, from: data),
              let window else { return false }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) else { return false }
        NotificationCenter.default.post(name: .loockGalleryDrop, object: payload, userInfo: ["point": point])
        return true
    }
}
final class GalleryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { _ = delegate?.windowShouldClose?(self) }
}
