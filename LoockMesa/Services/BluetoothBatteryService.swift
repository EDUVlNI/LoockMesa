import Foundation
import IOBluetooth
import IOKit
import CoreBluetooth
import ObjectiveC

final class BluetoothBatteryService: NSObject, ObservableObject {
    @Published private(set) var devices: [BluetoothReading] = []
    @Published private(set) var status = "Consultando Bluetooth…"
    @Published private(set) var updated: Date?
    @Published private(set) var refreshing = false
    var onUpdated: (([BluetoothReading]) -> Void)?
    var onDisconnected: ((BluetoothReading) -> Void)?
    private var batteryCache: [String: (Int, Date)] = [:]
    private var batteryReader: ConnectedBatteryReader?
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
        if value { retry?.cancel(); batteryReader?.pause() }
        else { refresh() }
    }
    init(automatic: Bool = true) {
        super.init()
        if automatic {
            batteryReader = ConnectedBatteryReader { [weak self] name, level in
                guard let self, !self.paused,
                      let index = self.devices.firstIndex(where: { BluetoothConnectionTracker.key($0.name) == BluetoothConnectionTracker.key(name) }) else { return }
                self.batteryCache[BluetoothConnectionTracker.key(name)] = (level, Date())
                let old = self.devices[index]
                var values = self.devices
                values[index] = BluetoothReading(name: old.name, deviceType: old.deviceType, address: old.address,
                    overall: level, left: old.left, right: old.right, caseLevel: old.caseLevel)
                self.publish(values, announce: false)
            }
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
            deviceType: major == 4 ? "headphones" : "", address: device.addressString ?? "",
            overall: Self.nativePercent(device, selectors: ["batteryPercentSingle", "batteryPercentCombined", "headsetBattery"]),
            left: Self.nativePercent(device, selectors: ["batteryPercentLeft"]),
            right: Self.nativePercent(device, selectors: ["batteryPercentRight"]),
            caseLevel: Self.nativePercent(device, selectors: ["batteryPercentCase"]))
    }
    /// Runtime checked because these read-only accessors are not public SDK API.
    /// Zero means unavailable for these native fields; explicit 0% reports remain
    /// supported by the system_profiler and standard BLE readers.
    static func nativePercent(_ object: NSObject, selectors: [String]) -> Int? {
        for name in selectors {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector),
                  let method = class_getInstanceMethod(type(of: object), selector),
                  method_getNumberOfArguments(method) == 2,
                  let type = method_copyReturnType(method) else { continue }
            let encoding = String(cString: type); free(type)
            let implementation = method_getImplementation(method)
            let value: Int64
            switch encoding {
            case "C":
                typealias Read = @convention(c) (AnyObject, Selector) -> UInt8
                value = Int64(unsafeBitCast(implementation, to: Read.self)(object, selector))
            case "q":
                typealias Read = @convention(c) (AnyObject, Selector) -> Int64
                value = unsafeBitCast(implementation, to: Read.self)(object, selector)
            case "Q":
                typealias Read = @convention(c) (AnyObject, Selector) -> UInt64
                let raw = unsafeBitCast(implementation, to: Read.self)(object, selector)
                value = raw <= 100 ? Int64(raw) : -1
            default: continue
            }
            if (1...100).contains(value) { return Int(value) }
        }
        return nil
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
            guard let self, !device.isConnected() else { return }
            self.epoch += 1
            let key = BluetoothConnectionTracker.key(self.reading(device).name)
            self.batteryCache.removeValue(forKey: key)
            self.disconnectNotifications.removeValue(forKey: key)?.unregister()
            self.publish(self.devices.filter { BluetoothConnectionTracker.key($0.name) != key }, announce: !self.paused)
            self.refresh()
        }
    }
    private func publish(_ values: [BluetoothReading], announce: Bool) {
        let additions = tracker.update(values, announce: announce)
        if devices != values { devices = values; onUpdated?(values) }
        for item in tracker.removed { onDisconnected?(item) }
        for item in additions { onConnected?(item) }
    }
    func refresh() {
        guard !paused else { return }
        guard !refreshing else { rerun = true; return }
        batteryReader?.refresh()
        refreshing = true
        let generation = epoch
        let native = nativeDevices()
        // Make native headset values visible even if system_profiler is slow or fails.
        let updatedNative = Self.merge(report: native, connected: devices)
        publish(updatedNative, announce: !firstReport)
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
                        let currentNames = Set(values.map { BluetoothConnectionTracker.key($0.name) })
                        self.batteryCache = self.batteryCache.filter { currentNames.contains($0.key) && Date().timeIntervalSince($0.value.1) < 300 }
                        let enriched = values.map { item -> BluetoothReading in
                            guard let cached = self.batteryCache[BluetoothConnectionTracker.key(item.name)] else { return item }
                            return BluetoothReading(name: item.name, deviceType: item.deviceType, address: item.address,
                                overall: item.overall ?? cached.0, left: item.left, right: item.right, caseLevel: item.caseLevel)
                        }
                        self.publish(enriched, announce: !self.firstReport)
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

/// Reads the standard Battery Service only from peripherals already connected
/// to macOS. No discovery scan, pairing, writes or persistent connection lease.
private final class ConnectedBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private let battery = CBUUID(string: "180F")
    private let level = CBUUID(string: "2A19")
    private var active: [UUID: CBPeripheral] = [:]
    private var deadlines: [UUID: DispatchWorkItem] = [:]
    private var paused = false
    private let received: (String, Int) -> Void
    init(received: @escaping (String, Int) -> Void) {
        self.received = received; super.init()
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && !paused { refresh() }
    }
    func refresh() {
        paused = false
        guard central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [battery, CBUUID(string: "1812")]) {
            guard active[peripheral.identifier] == nil else { continue }
            active[peripheral.identifier] = peripheral; peripheral.delegate = self
            let work = DispatchWorkItem { [weak self, weak peripheral] in
                if let peripheral { self?.finish(peripheral) }
            }
            deadlines[peripheral.identifier] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
            central.connect(peripheral, options: nil)
        }
    }
    func pause() {
        paused = true
        for peripheral in Array(active.values) { finish(peripheral) }
    }
    private func finish(_ peripheral: CBPeripheral) {
        deadlines.removeValue(forKey: peripheral.identifier)?.cancel()
        guard active.removeValue(forKey: peripheral.identifier) != nil else { return }
        peripheral.delegate = nil
        central.cancelPeripheralConnection(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !paused, active[peripheral.identifier] != nil else { finish(peripheral); return }
        peripheral.discoverServices([battery])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { finish(peripheral) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { finish(peripheral) }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == battery }) else { finish(peripheral); return }
        peripheral.discoverCharacteristics([level], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == level }),
              characteristic.properties.contains(.read) else { finish(peripheral); return }
        peripheral.readValue(for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if !paused, active[peripheral.identifier] != nil, error == nil, characteristic.uuid == level,
           let value = characteristic.value, value.count == 1, let byte = value.first, byte <= 100,
           let name = peripheral.name { received(name, Int(byte)) }
        finish(peripheral)
    }
}
