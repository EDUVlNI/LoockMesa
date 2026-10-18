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
    private var repairTask: Task<Void, Never>?
    private var repairGeneration = 0
    private var lastMonitorRead = Date.distantPast
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
        // Keep idle polling inexpensive; notifications still handle transitions immediately.
        if !rebuild && !locked && Date().timeIntervalSince(lastMonitorRead) < 2 { return }
        lastMonitorRead = Date()
        guard Date() >= suppressUntil else { return }
        let next = LockSessionState.current
        let value = next.shouldPresent
        let changed = locked != value
        if changed { previewTask?.cancel(); previewing = false; locked = value }
        if changed || rebuild {
            cancelRepairs(); refresh(); activityChanged?()
            if value && !sleeping { scheduleRepairs() }
        }
        if locked && needsServices && Date().timeIntervalSince(lastReassert) >= 5 {
            if panels.isEmpty { refresh() }
            lastReassert = Date()
            // Loginwindow may replace its visible spaces after display wake.
            repairPresentation()
        }
    }
    func setLocked(_ value: Bool) {
        // Read the session instead of trusting ordering of distributed notifications.
        if !value {
            cancelRepairs()
            LockScreenDiagnostics.shared.record("Oculto após desbloquear")
            suppressUntil = Date().addingTimeInterval(1)
            locked = false; previewing = false; previewTask?.cancel()
            removePanels(); activityChanged?(); return
        }
        suppressUntil = .distantPast
        synchronize(rebuild: true)
    }
    func setSleeping(_ value: Bool) {
        sleeping = value
        cancelRepairs()
        if value { removePanels(); LockScreenDiagnostics.shared.record("Pausado enquanto a tela está apagada") } else { synchronize(rebuild: true) }
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
    func dismiss() { cancelRepairs(); monitor?.invalidate(); monitor = nil; previewTask?.cancel(); previewTask = nil; previewing = false; locked = false; removePanels() }
    private func cancelRepairs() {
        repairGeneration += 1; repairTask?.cancel(); repairTask = nil
    }
    private func scheduleRepairs() {
        guard locked && needsServices && !previewing else { return }
        let generation = repairGeneration
        repairTask = Task { [weak self] in
            // Bounded retries cover loginwindow rebuilding its spaces after lock/wake.
            for delay in [UInt64(120_000_000), 230_000_000, 400_000_000, 750_000_000, 1_500_000_000] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, self.repairGeneration == generation, self.locked,
                      self.needsServices, !self.previewing, LockSessionState.current.shouldPresent else { return }
                if self.panels.isEmpty { self.refresh() }
                self.repairPresentation()
            }
        }
    }
    private func repairPresentation() {
        guard locked && needsServices && !previewing && LockSessionState.current.shouldPresent else {
            removePanels(); return
        }
        guard !panels.isEmpty else { return }
        if presenter?.show(windows: panels.map { $0.windowNumber }) == true {
            panels.forEach { $0.orderFrontRegardless() }
            LockScreenDiagnostics.shared.record("Painéis enviados à tela de bloqueio")
        } else {
            LockScreenDiagnostics.shared.record("Não foi possível exibir os painéis", detail: presenter?.lastError ?? "Presenter unavailable")
            removePanels()
        }
    }
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
            guard presenter != nil else { log.error("Lock screen presentation unavailable"); LockScreenDiagnostics.shared.record("Recurso indisponível neste macOS", detail: LockScreenSpace.initializationError); return }
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
        panel.canHide = false
        panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.canBecomeVisibleWithoutLogin = !previewing
        panel.level = previewing ? .floating : LockWidgetPanel.lockLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = !interactive; panel.animationBehavior = .none
        panel.contentView = LockHostingView(rootView: content)
        panel.alphaValue = 0
        if !previewing {
            // Adopt before ordering, so no frame can leak into the ordinary desktop space.
            guard LockSessionState.current.shouldPresent,
                  presenter?.show(windows: [panel.windowNumber]) == true else {
                LockScreenDiagnostics.shared.record("Falha ao posicionar na tela de bloqueio", detail: presenter?.lastError ?? "Session changed")
                panel.close(); return
            }
        }
        panel.orderFrontRegardless(); panels.append(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            panel.animator().alphaValue = 1
        }
    }
}
final class LockWidgetPanel: NSPanel {
    // Match SkyLightWindow's topmost window level, in addition to space level 400.
    static let lockLevel = NSWindow.Level(rawValue: Int(Int32.max - 2))
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class LockScreenDiagnostics: ObservableObject {
    static let shared = LockScreenDiagnostics()
    @Published private(set) var status = "Aguardando teste na tela bloqueada"
    private var lastDetail = ""
    private var lastFailure = "Nenhuma falha registrada"
    private var lastUpdate = Date()
    func record(_ value: String, detail: String = "") {
        guard status != value || lastDetail != detail else { return }
        status = value; lastDetail = detail; lastUpdate = Date()
        if !detail.isEmpty { lastFailure = "\(value): \(detail)" }
    }
    func copyReport() {
        let session = LockSessionState.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let report = "LoockMesa \(version)\n\(ProcessInfo.processInfo.operatingSystemVersionString)\nEstado: \(status)\nDetalhe: \(lastDetail)\nÚltima falha: \(lastFailure)\nAtualizado: \(lastUpdate)\nBloqueada: \(session.screenLocked)\nSessão própria: \(session.ownConsole)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
    }
}
struct LockScreenDiagnosticView: View {
    @ObservedObject private var diagnostics = LockScreenDiagnostics.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(diagnostics.status).font(.caption).foregroundStyle(.secondary)
            Button("Copiar diagnóstico do último teste") { diagnostics.copyReport() }.font(.caption)
        }
    }
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
final class LockScreenSpace {
    // Space IDs are 64-bit on Intel. Setters with undocumented return contracts
    // are invoked as Void; success is verified through independent query APIs.
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> UInt64
    private typealias Level = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias GetLevel = @convention(c) (Int32, UInt64) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Void
    private typealias Adopt = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Void
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: UInt64
    private let showSpaces: Spaces
    private let hideSpaces: Spaces
    private let adopt: Adopt
    private let copySpaces: CopySpaces
    private let destroy: Destroy?
    private(set) var lastError = ""
    static private(set) var initializationError = "Not attempted"
    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW | RTLD_LOCAL) else {
            Self.initializationError = "dlopen SkyLight: " + (dlerror().map { String(cString: $0) } ?? "unknown error")
            return nil
        }
        func resolve(_ name: String) -> UnsafeMutableRawPointer? {
            let legacy = name.replacingOccurrences(of: "SLS", with: "CGS", options: .anchored)
            if let address = dlsym(h, name) ?? dlsym(h, legacy) { return address }
            Self.initializationError = "Missing symbol: \(name) / \(legacy)"
            return nil
        }
        guard let c = resolve("SLSMainConnectionID"), let n = resolve("SLSSpaceCreate"),
              let l = resolve("SLSSpaceSetAbsoluteLevel"), let get = resolve("SLSSpaceGetAbsoluteLevel"),
              let s = resolve("SLSShowSpaces"), let a = resolve("SLSSpaceAddWindowsAndRemoveFromSpaces"),
              let hide = resolve("SLSHideSpaces"), let query = resolve("SLSCopySpacesForWindows") else { dlclose(h); return nil }
        let d = dlsym(h, "SLSSpaceDestroy") ?? dlsym(h, "CGSSpaceDestroy")
        let cleanup = d.map { unsafeBitCast($0, to: Destroy.self) }
        let cid = unsafeBitCast(c, to: Connection.self)()
        guard cid != 0 else { Self.initializationError = "Main connection ID is zero"; dlclose(h); return nil }
        let sid = unsafeBitCast(n, to: Create.self)(cid, 1, nil)
        guard sid != 0 else { Self.initializationError = "SpaceCreate returned zero (connection \(cid))"; dlclose(h); return nil }
        unsafeBitCast(l, to: Level.self)(cid, sid, 400)
        let actualLevel = unsafeBitCast(get, to: GetLevel.self)(cid, sid)
        guard actualLevel == 400 else {
            Self.initializationError = "Space level readback: expected 400, got \(actualLevel); space \(sid)"
            cleanup?(cid, sid); dlclose(h); return nil
        }
        handle = h; connection = cid; space = sid
        showSpaces = unsafeBitCast(s, to: Spaces.self); hideSpaces = unsafeBitCast(hide, to: Spaces.self)
        adopt = unsafeBitCast(a, to: Adopt.self); copySpaces = unsafeBitCast(query, to: CopySpaces.self); destroy = cleanup
        Self.initializationError = "Ready; space level verified as 400"
    }
    func show(windows: [Int]) -> Bool {
        guard !windows.isEmpty, LockSessionState.current.shouldPresent else { hide(); return false }
        let ids = windows.map { NSNumber(value: $0) } as CFArray
        adopt(connection, space, ids, 7)
        // Verify each window individually; a union query could hide a partial failure.
        for window in windows {
            guard let result = copySpaces(connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue(),
                  let memberships = result as? [NSNumber], memberships.contains(where: { $0.uint64Value == space }) else {
                lastError = "Window \(window) was not associated with lock space \(space)"
                hide(); return false
            }
        }
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
        lastError = ""; return true
    }
    func hide() { hideSpaces(connection, [NSNumber(value: space)] as CFArray) }
    deinit { hide(); destroy?(connection, space); dlclose(handle) }
}
