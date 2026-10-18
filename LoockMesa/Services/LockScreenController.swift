import AppKit
import SwiftUI
import Combine
import OSLog

extension Notification.Name {
    static let loockPreviewLockScreen = Notification.Name("LoockMesa.previewLockScreen")
}

/// Separate, small panels leave the native authentication surface untouched.
/// Visibility on the login window is best effort; this never authenticates a user.
@MainActor final class LockScreenController {
    private let store: DeskStore
    private let devices: DeviceService
    private let weather: WeatherService
    private let bluetooth: BluetoothBatteryService
    private var panels: [NSPanel] = []
    private var subscriptions = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?
    private var locked = false
    private var previewing = false
    private var sleeping = false
    private var monitor: Timer?
    private var suppressUntil = Date.distantPast
    private var lastReassert = Date.distantPast
    private var presenter: LockScreenSpace?
    private let log = Logger(subsystem: "com.eduvini.LoockMesa", category: "LockScreen")
    var isLocked: Bool { locked }
    var needsServices: Bool { !sleeping && (previewing || (locked && store.preferences.lockScreenEnabled == true)) }
    var activityChanged: (() -> Void)?

    init(store: DeskStore, devices: DeviceService, weather: WeatherService, bluetooth: BluetoothBatteryService) {
        self.store = store; self.devices = devices; self.weather = weather; self.bluetooth = bluetooth
        store.$preferences.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.synchronize(rebuild: true) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .loockPreviewLockScreen).sink { [weak self] _ in self?.preview() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in self?.synchronize(rebuild: true) }.store(in: &subscriptions)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.synchronize() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common); monitor = timer
    }
    deinit { monitor?.invalidate() }

    /// Notifications are hints; a delayed lock notification must not display on the desktop.
    func synchronize(rebuild: Bool = false) {
        if previewing && rebuild { refresh(); activityChanged?() }
        guard store.preferences.lockScreenEnabled == true || locked else { return }
        guard Date() >= suppressUntil else { return }
        let next = LockSessionState.current
        let value = next.shouldPresent
        let changed = locked != value
        if changed { previewTask?.cancel(); previewing = false; locked = value }
        if changed || rebuild { refresh(); activityChanged?() }
        if locked && needsServices && Date().timeIntervalSince(lastReassert) >= 1 {
            if panels.isEmpty { refresh() }
            lastReassert = Date()
            // Loginwindow may replace its visible spaces after display wake.
            if presenter?.show(windows: panels.map { $0.windowNumber }) != true { removePanels() }
        }
    }
    func setLocked(_ value: Bool) {
        // Read the session instead of trusting ordering of distributed notifications.
        if !value {
            suppressUntil = Date().addingTimeInterval(1)
            locked = false; previewing = false; previewTask?.cancel()
            removePanels(); activityChanged?(); return
        }
        suppressUntil = .distantPast
        synchronize(rebuild: true)
    }
    func setSleeping(_ value: Bool) {
        sleeping = value
        if value { removePanels() } else { synchronize(rebuild: true) }
        activityChanged?()
    }
    func preview() {
        guard !LockSessionState.current.shouldPresent else { synchronize(); return }
        previewTask?.cancel(); previewing = true; refresh(); activityChanged?()
        previewTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            self?.previewing = false; self?.refresh(); self?.activityChanged?()
        }
    }
    func dismiss() { monitor?.invalidate(); monitor = nil; previewTask?.cancel(); previewTask = nil; previewing = false; locked = false; removePanels() }
    private func removePanels() { presenter?.hide(); panels.forEach { $0.alphaValue = 0; $0.orderOut(nil); $0.contentView = nil; $0.close() }; panels.removeAll() }
    private func refresh() {
        removePanels()
        guard needsServices, let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }) ?? NSScreen.main else { return }
        if !previewing {
            guard LockSessionState.current.shouldPresent else { return }
            if presenter == nil { presenter = LockScreenSpace() }
            guard presenter != nil else { log.error("Lock screen presentation unavailable"); return }
        }
        let p = store.preferences
        let frames = LockScreenLayout.frames(screen: screen.frame, infoOffset: p.lockInfoOffset ?? 0, playerOffset: p.lockPlayerOffset ?? 0)
        if p.lockShowInformation != false {
            let row = LockScreenInformation(store: store, devices: devices, weather: weather, bluetooth: bluetooth)
            addPanel(frame: frames.info, content: row, interactive: false)
        }
        if p.lockShowPlayer != false {
            let player = LockScreenPlayer(media: MusicService.shared, onlyPlaying: p.lockPlayerOnlyPlaying == true)
            addPanel(frame: frames.player, content: player, interactive: true)
        }
    }
    private func addPanel<V: View>(frame: CGRect, content: V, interactive: Bool) {
        let panel = LockWidgetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.canBecomeVisibleWithoutLogin = !previewing
        panel.level = previewing ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = !interactive; panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: content)
        panel.alphaValue = 0
        if !previewing {
            // Adopt before ordering, so no frame can leak into the ordinary desktop space.
            guard LockSessionState.current.shouldPresent,
                  presenter?.show(windows: [panel.windowNumber]) == true else { panel.close(); return }
        }
        panel.orderFrontRegardless(); panels.append(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            panel.animator().alphaValue = 1
        }
    }
}
private final class LockWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum LockScreenLayout {
    static func frames(screen: CGRect, infoOffset: Double, playerOffset: Double) -> (info: CGRect, player: CGRect) {
        // Relative to the Ventura reference: avatar begins at 34% from the top.
        let infoY = screen.minY + screen.height * 0.69 + CGFloat(infoOffset.isFinite ? infoOffset : 0)
        let playerY = screen.minY + screen.height * 0.34 - 164 + CGFloat(playerOffset.isFinite ? playerOffset : 0)
        func frame(width: CGFloat, height: CGFloat, y: CGFloat) -> CGRect {
            CGRect(x: screen.midX - width / 2, y: min(screen.maxY - height - 16, max(screen.minY + 56, y)), width: width, height: height)
        }
        return (frame(width: min(440, screen.width - 32), height: 30, y: infoY), frame(width: 344, height: 164, y: playerY))
    }
}

private struct LockScreenInformation: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var devices: DeviceService
    @ObservedObject var weather: WeatherService
    @ObservedObject var bluetooth: BluetoothBatteryService
    var body: some View {
        HStack(spacing: 18) {
            if store.preferences.lockShowBattery != false, let level = devices.macBattery {
                Label("\(level)%", systemImage: devices.charging ? "bolt.fill" : devices.pluggedIn ? "powerplug.fill" : "battery.100")
                    .accessibilityLabel("Bateria do Mac, \(level) por cento, \(devices.powerStatus)")
            }
            if store.preferences.lockShowHeadphones != false,
               let device = bluetooth.devices.first(where: { $0.symbol == "headphones" && $0.primary != nil }), let level = device.primary {
                Label("\(level)%", systemImage: "headphones").accessibilityLabel("\(device.name), \(level) por cento")
            }
            if store.preferences.lockShowWeather != false, store.preferences.liveWeather, let current = weather.snapshot {
                Label("\(current.temperature)°", systemImage: WeatherSnapshot.symbol(current.code, isDay: current.isDay))
                    .accessibilityLabel("\(store.preferences.city.rawValue), \(current.temperature) graus")
            }
        }.font(.system(size: 13, weight: .medium)).monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.88)).shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct LockScreenPlayer: View {
    @ObservedObject var media: MusicService
    var onlyPlaying: Bool
    var body: some View {
        Group {
            if !onlyPlaying || media.isPlaying {
                LyricsWidget(size: .medium, media: media, appearance: .original, frosted: true)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }
        }.frame(width: 344, height: 164)
    }
}


struct LockSessionState {
    var screenLocked: Bool
    var ownConsole: Bool
    var shouldPresent: Bool { screenLocked && ownConsole }
    static var current: LockSessionState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return LockSessionState(screenLocked: false, ownConsole: false)
        }
        let owner = (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value
        let console = (session[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue ?? false
        let locked = (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
        return LockSessionState(screenLocked: locked, ownConsole: console && owner == getuid())
    }
}

/// SkyLight space call sequence adapted from Lakr233/SkyLightWindow (MIT).
/// See Resources/SkyLightWindow-LICENSE.txt. All symbols and return values are checked.
/// Only our small non-key panels are adopted; authentication stays entirely with macOS.
private final class LockScreenSpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Level = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias Adopt = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias Destroy = @convention(c) (Int32, Int32) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: Int32
    private let showSpaces: Spaces
    private let hideSpaces: Spaces
    private let adopt: Adopt
    private let destroy: Destroy
    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW | RTLD_LOCAL) else { return nil }
        guard let c = dlsym(h, "SLSMainConnectionID"), let n = dlsym(h, "SLSSpaceCreate"),
              let l = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let s = dlsym(h, "SLSShowSpaces"),
              let a = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces"), let hide = dlsym(h, "SLSHideSpaces"),
              let d = dlsym(h, "SLSSpaceDestroy") else { dlclose(h); return nil }
        let cid = unsafeBitCast(c, to: Connection.self)()
        let sid = unsafeBitCast(n, to: Create.self)(cid, 1, 0)
        let cleanup = unsafeBitCast(d, to: Destroy.self)
        guard sid > 0 else { dlclose(h); return nil }
        guard unsafeBitCast(l, to: Level.self)(cid, sid, 400) == 0 else {
            _ = cleanup(cid, sid); dlclose(h); return nil
        }
        handle = h; connection = cid; space = sid
        showSpaces = unsafeBitCast(s, to: Spaces.self); hideSpaces = unsafeBitCast(hide, to: Spaces.self)
        adopt = unsafeBitCast(a, to: Adopt.self); destroy = cleanup
    }
    func show(windows: [Int]) -> Bool {
        guard !windows.isEmpty, LockSessionState.current.shouldPresent else { hide(); return false }
        guard adopt(connection, space, windows.map { NSNumber(value: $0) } as CFArray, 7) == 0 else { hide(); return false }
        guard showSpaces(connection, [NSNumber(value: space)] as CFArray) == 0 else { hide(); return false }
        return true
    }
    func hide() { _ = hideSpaces(connection, [NSNumber(value: space)] as CFArray) }
    deinit { hide(); _ = destroy(connection, space); dlclose(handle) }
}
