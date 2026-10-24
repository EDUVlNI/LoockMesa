import Foundation

struct BluetoothReading: Equatable, Identifiable {
    let name: String
    var deviceType: String = ""
    var address: String = ""
    let overall: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    var id: String { address.isEmpty ? BluetoothConnectionTracker.key(name) : Self.normalizedAddress(address) }
    static func normalizedAddress(_ value: String) -> String { value.lowercased().filter { $0.isHexDigit } }
    func matches(_ other: BluetoothReading) -> Bool {
        (!address.isEmpty && !other.address.isEmpty && id == other.id) ||
        BluetoothConnectionTracker.key(name) == BluetoothConnectionTracker.key(other.name)
    }
    var isFreeClip: Bool { name.lowercased().replacingOccurrences(of: " ", with: "").contains("freeclip") }
    var isArcMouse: Bool { let text = name.lowercased(); return text.contains("arc") && (text.contains("microsoft") || text.contains("surface")) }
    var symbol: String {
        let text = (deviceType + " " + name).lowercased()
        if text.contains("keyboard") || text.contains("teclado") { return "keyboard" }
        if text.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if isArcMouse || text.contains("mouse") { return "computermouse" }
        if isFreeClip || text.contains("head") || text.contains("airpod") || text.contains("buds") || text.contains("fone") { return "headphones" }
        if text.contains("speaker") { return "hifispeaker" }
        if text.contains("gamepad") || text.contains("controller") { return "gamecontroller" }
        return "battery.100"
    }
    var hasBattery: Bool { overall != nil || left != nil || right != nil || caseLevel != nil }
    var primary: Int? { overall ?? [left, right].compactMap { $0 }.min() }
}
enum BluetoothReport {
    static func percent(_ value: Any?) -> Int? {
        let number: Int?
        if let text = value as? String { number = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) }
        else if let n = value as? NSNumber { number = n.intValue }
        else { number = nil }
        guard let number, (0...100).contains(number) else { return nil }; return number
    }
    static func parse(_ data: Data) throws -> [BluetoothReading] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var readings: [BluetoothReading] = []
        func add(_ name: String, _ info: [String: Any]) {
            readings.append(BluetoothReading(name: name, deviceType: info["device_minorType"] as? String ?? info["device_type"] as? String ?? "",
                address: info["device_address"] as? String ?? "",
                overall: percent(info["device_batteryLevelMain"] ?? info["device_batteryLevel"]),
                left: percent(info["device_batteryLevelLeft"]), right: percent(info["device_batteryLevelRight"]),
                caseLevel: percent(info["device_batteryLevelCase"])))
        }
        for report in json?["SPBluetoothDataType"] as? [[String: Any]] ?? [] {
            // Only devices explicitly in the connected section. Cached disconnected
            // percentages are deliberately excluded, even if their values look valid.
            for group in report["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in group { if let info = value as? [String: Any] { add(name, info) } }
            }
            for group in report["devices_list"] as? [[String: Any]] ?? [] {
                for (name, value) in group {
                    guard let info = value as? [String: Any], let connected = info["device_isconnected"] as? String,
                          ["attrib_Yes", "Yes", "yes"].contains(connected) else { continue }
                    add(name, info)
                }
            }
        }
        return readings.sorted { $0.name < $1.name }
    }
}

/// Connected devices remain visible when their battery is unavailable.
struct BatteryEntry: Identifiable, Equatable {
    let id: String
    let label: String
    let symbol: String
    let value: Int?
    var arcMouse = false
    var freeClip = false
    var charging = false
    var simulated = false
    static func entries(mac: Int?, charging: Bool, readings: [BluetoothReading]) -> [BatteryEntry] {
        var result: [BatteryEntry] = []
        if let mac { result.append(.init(id: "mac", label: "Mac", symbol: "laptopcomputer", value: mac, charging: charging)) }
        var seen = Set<String>()
        for r in readings where seen.insert(r.id).inserted {
            if r.symbol == "computermouse" { continue }
            if r.left != nil || r.right != nil {
                if let value = r.left { result.append(.init(id: r.id + ".left", label: r.name + " E", symbol: r.symbol, value: value, freeClip: r.isFreeClip)) }
                if let value = r.right { result.append(.init(id: r.id + ".right", label: r.name + " D", symbol: r.symbol, value: value, freeClip: r.isFreeClip)) }
            } else {
                result.append(.init(id: r.id + ".main", label: r.isFreeClip ? "FreeClip" : r.name, symbol: r.symbol, value: r.overall, arcMouse: r.isArcMouse, freeClip: r.isFreeClip))
            }
            if let value = r.caseLevel { result.append(.init(id: r.id + ".case", label: r.name + " · Estojo", symbol: "case", value: value)) }
        }
        return result
    }
}


struct BluetoothConnectionTracker {
    private var known: [BluetoothReading] = []
    private var initialized = false
    private(set) var removed: [BluetoothReading] = []
    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    mutating func update(_ readings: [BluetoothReading], announce: Bool = true) -> [BluetoothReading] {
        removed = initialized && announce ? known.filter { old in !readings.contains { $0.matches(old) } } : []
        var emitted = Set<String>()
        let added = initialized && announce ? readings.filter { item in
            let existed = known.contains { $0.id == item.id || Self.key($0.name) == Self.key(item.name) }
            return !existed && emitted.insert(item.id).inserted
        } : []
        known = readings; initialized = true
        return added
    }
}
