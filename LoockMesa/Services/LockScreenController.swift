import AppKit
import SwiftUI
import Combine

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
    var needsServices: Bool { !sleeping && (previewing || (locked && store.preferences.lockScreenEnabled == true)) }
    var activityChanged: (() -> Void)?

    init(store: DeskStore, devices: DeviceService, weather: WeatherService, bluetooth: BluetoothBatteryService) {
        self.store = store; self.devices = devices; self.weather = weather; self.bluetooth = bluetooth
        store.$preferences.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh(); self?.activityChanged?() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .loockPreviewLockScreen).sink { [weak self] _ in self?.preview() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }
    func setLocked(_ value: Bool) {
        previewTask?.cancel(); previewTask = nil; previewing = false
        locked = value; refresh(); activityChanged?()
    }
    func setSleeping(_ value: Bool) { sleeping = value; refresh(); activityChanged?() }
    func preview() {
        guard !locked else { return }
        previewTask?.cancel(); previewing = true; refresh(); activityChanged?()
        previewTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            self?.previewing = false; self?.refresh(); self?.activityChanged?()
        }
    }
    func dismiss() { previewTask?.cancel(); previewTask = nil; previewing = false; locked = false; removePanels() }
    private func removePanels() { panels.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() }; panels.removeAll() }
    private func refresh() {
        removePanels()
        guard needsServices, let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }) ?? NSScreen.main else { return }
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
        panel.alphaValue = 0; panel.orderFrontRegardless(); panels.append(panel)
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
