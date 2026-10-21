import Foundation
import IOBluetooth
import IOKit

final class BluetoothBatteryService: NSObject, ObservableObject {
    @Published private(set) var devices: [BluetoothReading] = []
    @Published private(set) var status = "Consultando Bluetooth…"
    @Published private(set) var updated: Date?
    @Published private(set) var refreshing = false
    var onUpdated: (([BluetoothReading]) -> Void)?
    var onConnected: ((BluetoothReading) -> Void)?
    private var tracker = BluetoothConnectionTracker()
    private var timer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var retry: DispatchWorkItem?
    private var hidPort: IONotificationPortRef?
    private var hidIterators: [io_iterator_t] = []
    private var hardwareRefresh: DispatchWorkItem?
    private var paused = false
    private var epoch = 0
    private var rerun = false
    private var firstReport = true

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value; epoch += 1
        if value { retry?.cancel() }
        else { refresh() }
    }
    init(automatic: Bool = true) {
        super.init()
        if automatic {
            let native = nativeDevices()
            publish(native, announce: false)
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
            startHIDNotifications()
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
            timer?.tolerance = 20
        }
    }
    deinit {
        timer?.invalidate(); retry?.cancel(); hardwareRefresh?.cancel(); connectNotification?.unregister()
        hidIterators.forEach { IOObjectRelease($0) }
        if let hidPort { IONotificationPortDestroy(hidPort) }
        disconnectNotifications.values.forEach { $0.unregister() }
    }
    private func startHIDNotifications() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        hidPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        for event in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, event, IOServiceMatching("IOHIDDevice"), { context, iterator in
                var object = IOIteratorNext(iterator)
                var changed = false
                while object != 0 { changed = true; IOObjectRelease(object); object = IOIteratorNext(iterator) }
                guard changed, let context else { return }
                let owner = Unmanaged<BluetoothBatteryService>.fromOpaque(context).takeUnretainedValue()
                owner.hardwareChanged()
            }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
            if result == KERN_SUCCESS {
                hidIterators.append(iterator)
                // Drain once to arm; existing HID devices are not new connections.
                var object = IOIteratorNext(iterator)
                while object != 0 { IOObjectRelease(object); object = IOIteratorNext(iterator) }
            }
        }
    }
    private func hardwareChanged() {
        guard !paused else { return }
        epoch += 1
        hardwareRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        hardwareRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    var freeClip: BluetoothReading? { devices.first(where: \.isFreeClip) }
    private func reading(_ device: IOBluetoothDevice) -> BluetoothReading {
        let major = (device.classOfDevice >> 8) & 0x1f
        return BluetoothReading(name: device.name ?? device.addressString ?? "Dispositivo Bluetooth",
            deviceType: major == 4 ? "headphones" : "", address: device.addressString ?? "", overall: nil, left: nil, right: nil, caseLevel: nil)
    }
    private func watch(_ device: IOBluetoothDevice) {
        let key = BluetoothConnectionTracker.key(reading(device).name)
        guard disconnectNotifications[key] == nil else { return }
        disconnectNotifications[key] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
    }
    private func nativeDevices() -> [BluetoothReading] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }.map { watch($0); return reading($0) }
    }
    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, device.isConnected() else { return }
            self.watch(device); self.epoch += 1
            let item = self.reading(device)
            let key = BluetoothConnectionTracker.key(item.name)
            if !self.devices.contains(where: { BluetoothConnectionTracker.key($0.name) == key }) {
                self.publish(self.devices + [item], announce: !self.paused)
            }
            self.refresh()
            // Many headsets expose their battery a few seconds after connection.
            self.retry?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self.retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
    }
    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.epoch += 1
            let key = BluetoothConnectionTracker.key(self.reading(device).name)
            self.disconnectNotifications.removeValue(forKey: key)?.unregister()
            self.publish(self.devices.filter { BluetoothConnectionTracker.key($0.name) != key }, announce: false)
            self.refresh()
        }
    }
    private func publish(_ values: [BluetoothReading], announce: Bool) {
        let additions = tracker.update(values, announce: announce)
        if devices != values { devices = values; onUpdated?(values) }
        for item in additions { onConnected?(item) }
    }
    func refresh() {
        guard !paused else { return }
        guard !refreshing else { rerun = true; return }
        refreshing = true
        let generation = epoch
        let native = nativeDevices()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "full", "-timeout", "10"]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            var result: [BluetoothReading] = []
            var success = false
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit(); timeout.cancel()
                if process.terminationStatus == 0 { result = try BluetoothReport.parse(data); success = true }
            } catch { timeout.cancel() }
            let hid = Self.hidReadings()
            let values = Self.merge(report: result, connected: native + hid)
            let valid = success
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshing = false
                if self.paused { return }
                if generation == self.epoch {
                    // A failed query is not a disconnect and must not create reconnection popups.
                    if valid {
                        self.publish(values, announce: !self.firstReport)
                        self.firstReport = false; self.updated = Date()
                        self.status = values.isEmpty ? "Nenhum dispositivo conectado" : "Dispositivos conectados · — indica bateria não informada"
                    } else { self.status = "Leitura de bateria indisponível; aguardando atualização" }
                } else { self.rerun = true }
                if self.rerun { self.rerun = false; self.refresh() }
            }
        }
    }
    static func merge(report: [BluetoothReading], connected: [BluetoothReading]) -> [BluetoothReading] {
        var merged: [BluetoothReading] = []
        for item in report + connected {
            if let index = merged.firstIndex(where: {
                (!$0.address.isEmpty && !item.address.isEmpty && $0.id == item.id) ||
                BluetoothConnectionTracker.key($0.name) == BluetoothConnectionTracker.key(item.name)
            }) {
                let old = merged[index]
                merged[index] = BluetoothReading(name: old.name, deviceType: old.deviceType.isEmpty ? item.deviceType : old.deviceType,
                    address: old.address.isEmpty ? item.address : old.address,
                    overall: old.overall ?? item.overall, left: old.left ?? item.left,
                    right: old.right ?? item.right, caseLevel: old.caseLevel ?? item.caseLevel)
            } else { merged.append(item) }
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Read connected HID services only; never query cached Bluetooth preferences.
    private static func hidReadings() -> [BluetoothReading] {
        var result: [BluetoothReading] = []
        for name in ["IOHIDDevice", "AppleDeviceManagementHIDEventService"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let info = properties?.takeRetainedValue() as? [String: Any],
                   let transport = info["Transport"] as? String, transport.lowercased().contains("bluetooth"),
                   (info["Connected"] as? NSNumber)?.boolValue != false,
                   let product = (info["Product"] ?? info["ProductName"]) as? String {
                    let usage = (info["PrimaryUsage"] as? NSNumber)?.intValue
                    let kind = usage == 2 ? "mouse" : usage == 6 ? "keyboard" : ""
                    let address = (info["DeviceAddress"] ?? info["BluetoothDeviceAddress"] ?? info["BD_ADDR"]) as? String ?? ""
                    result.append(BluetoothReading(name: product, deviceType: kind, address: address,
                        overall: BluetoothReport.percent(info["BatteryPercent"] ?? info["BatteryLevel"]), left: nil, right: nil, caseLevel: nil))
                }
                IOObjectRelease(service); service = IOIteratorNext(iterator)
            }
        }
        return result
    }
}
