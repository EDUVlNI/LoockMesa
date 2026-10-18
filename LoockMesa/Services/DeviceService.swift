import Foundation
import CoreAudio
import IOKit.ps
import IOKit
import AppKit

final class DeviceService: ObservableObject {
    static let modelIdentifier: String = {
        let platform = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if platform != 0 {
            defer { IOObjectRelease(platform) }
            if let data = IORegistryEntryCreateCFProperty(platform, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters), !name.isEmpty { return name }
        }
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown" }
        return String(cString: bytes)
    }()
    static let detectedGlyph: MacGlyph = MacGlyph.resolve(model: modelIdentifier, builtInNotch: NSScreen.screens.contains { screen in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0 && screen.safeAreaInsets.top > 0
    })
    static let nativeMacSymbol: String = {
        if detectedGlyph == .desktop { return "desktopcomputer" }
        let candidate = detectedGlyph == .notchedNotebook ? "macbook.gen2" : "macbook.gen1"
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil ? candidate : "laptopcomputer"
    }()
    var macModelDescription: String {
        if Self.modelIdentifier == "MacBookPro14,3" { return "MacBook Pro 15″ · Intel · 2017 · sem notch" }
        return Self.modelIdentifier + (Self.detectedGlyph == .notchedNotebook ? " · com notch" : "")
    }
    @Published private(set) var outputName = "Saída de áudio"
    @Published private(set) var macBattery: Int?
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lowPowerObserver: NSObjectProtocol?
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    @Published private(set) var powerStatus = "Consultando bateria"
    private var powerSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var paused = false
    func setPaused(_ value: Bool) { guard paused != value else { return }; paused = value; if !value { refresh() } }
    init() {
        refresh()
        lowPowerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<DeviceService>.fromOpaque(context).takeUnretainedValue()
            service.refresh()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 10
    }
    deinit {
        timer?.invalidate()
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    func refresh() {
        guard !paused else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0); var length = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &length, &device) == noErr {
            address.mSelector = kAudioObjectPropertyName
            var name: Unmanaged<CFString>?
            length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &length, &name) == noErr, let name { let value = name.takeRetainedValue() as String; if outputName != value { outputName = value } }
        }
        var nextBattery: Int?; var nextCharging = false; var nextPlugged = false
        var nextStatus = "Bateria indisponível"
        defer {
            if macBattery != nextBattery { macBattery = nextBattery }
            if charging != nextCharging { charging = nextCharging }
            if pluggedIn != nextPlugged { pluggedIn = nextPlugged }
            if powerStatus != nextStatus { powerStatus = nextStatus }
        }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            nextCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            nextPlugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            nextStatus = nextCharging ? "Carregando" : (nextPlugged ? "Conectado à energia" : "Usando bateria")
            nextBattery = min(100, Swift.max(0, Int(Double(now) / Double(max) * 100)))
        }
    }
}
