import SwiftUI

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case headphones, macBattery, weather, clock, calendar, reminders, notes, music
    static var allCases: [WidgetKind] { [.headphones, .weather, .clock, .calendar, .reminders, .notes, .music] }
    var id: String { rawValue }
    var title: String { switch self { case .music: return "Música"; case .headphones: return "Baterias"; case .weather: return "Clima"; case .clock: return "Relógio"; case .macBattery: return "Bateria do Mac"; case .reminders: return "Lembretes"; case .notes: return "Notas"; case .calendar: return "Calendário" } }
    var symbol: String { switch self { case .music: return "music.note"; case .headphones: return "headphones"; case .weather: return "cloud.sun.fill"; case .clock: return "clock"; case .macBattery: return "laptopcomputer"; case .reminders: return "list.bullet"; case .notes: return "note.text"; case .calendar: return "calendar" } }
}
enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case small = "P", medium = "M", large = "G"
    var id: String { rawValue }
    var dimensions: CGSize {
        switch self { case .small: return CGSize(width: 164, height: 164)
        case .medium: return CGSize(width: 344, height: 164)
        case .large: return CGSize(width: 344, height: 344) }
    }
}
struct WidgetItem: Codable, Equatable, Identifiable {
    let kind: WidgetKind
    var size: WidgetSize = .small
    var enabled = true
    var x: Double?
    var y: Double?
    var id: String { kind.rawValue }
}
enum WeatherCity: String, CaseIterable, Codable, Identifiable {
    case curitiba = "Curitiba", saoPaulo = "São Paulo", rio = "Rio de Janeiro", lisboa = "Lisboa"
    var id: String { rawValue }
    var coordinates: (Double, Double) {
        switch self { case .curitiba: return (-25.43, -49.27); case .saoPaulo: return (-23.55, -46.63)
        case .rio: return (-22.91, -43.17); case .lisboa: return (38.72, -9.14) }
    }
}
enum WidgetAppearance: String, Codable, CaseIterable, Identifiable {
    case original = "Original", light = "Branco", dark = "Preto"
    var id: String { rawValue }
}
struct DeskPreferences: Codable, Equatable {
    var widgets = [WidgetItem(kind: .headphones, size: .medium), WidgetItem(kind: .weather, size: .medium), WidgetItem(kind: .clock), WidgetItem(kind: .calendar), WidgetItem(kind: .reminders, enabled: false), WidgetItem(kind: .notes, enabled: false), WidgetItem(kind: .music, size: .medium, enabled: false)]
    var automaticSpotifyCovers: Bool? = nil
    var musicProvider: MusicProvider? = nil
    var musicShortcuts: [MusicShortcut]? = nil
    var city: WeatherCity = .curitiba
    var liveWeather = true
    var demoHeadphones = false
    var localNoteTitle: String? = nil
    var localNoteBody: String? = nil
    var localNoteModified: Date? = nil
    var individualFrost: [String: Bool]? = nil
    var individualIntensity: [String: Double]? = nil
    func usesFrost(_ kind: WidgetKind) -> Bool { individualFrost?[kind.rawValue] ?? (unifiedFrost != false) }
    func frostAmount(_ kind: WidgetKind) -> Double { individualIntensity?[kind.rawValue] ?? unifiedFrostIntensity ?? 0.7 }
    var unifiedFrost: Bool? = nil
    var unifiedFrostIntensity: Double? = nil
    var opensAppsOnClick: Bool? = nil
    var materialIntensities: [String: Double]? = nil
    var frostedOthers: [String: Bool]? = nil
    var frostedClock: Bool? = nil
    var frostedBattery: Bool? = nil
    var appearance: WidgetAppearance? = nil
    var monochrome = false
    var positionsLocked = false
    mutating func normalize() {
        if let mac = widgets.first(where: { $0.kind == .macBattery }),
           !widgets.contains(where: { $0.kind == .headphones && $0.enabled }) {
            widgets.removeAll { $0.kind == .headphones }
            widgets.append(WidgetItem(kind: .headphones, size: mac.size, enabled: mac.enabled, x: mac.x, y: mac.y))
        }
        widgets.removeAll { $0.kind == .macBattery }
        var seen = Set<WidgetKind>()
        widgets = widgets.filter { seen.insert($0.kind).inserted }
        widgets += WidgetKind.allCases.filter { !seen.contains($0) }.map { WidgetItem(kind: $0, enabled: $0 != .reminders && $0 != .notes && $0 != .music) }
        for i in widgets.indices {
            if widgets[i].x?.isFinite == false || widgets[i].y?.isFinite == false { widgets[i].x = nil; widgets[i].y = nil }
        }
    }
}
final class DeskStore: ObservableObject {
    @Published var preferences: DeskPreferences { didSet { persist() } }
    private let defaults: UserDefaults
    private let key = "LoockMesa.preferences.v4"
    @Published var layoutMessage = ""
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let old = defaults.data(forKey: key) == nil && defaults.data(forKey: "LoockMesa.preferences.v3") == nil
        var value = (defaults.data(forKey: key) ?? defaults.data(forKey: "LoockMesa.preferences.v3") ?? defaults.data(forKey: "LoockMesa.preferences.v2") ?? defaults.data(forKey: "LoockMesa.preferences.v1")).flatMap { try? JSONDecoder().decode(DeskPreferences.self, from: $0) } ?? DeskPreferences()
        if old { value.liveWeather = true; value.demoHeadphones = false }
        value.normalize(); preferences = value
    }
    func item(_ kind: WidgetKind) -> WidgetItem { preferences.widgets.first { $0.kind == kind } ?? WidgetItem(kind: kind) }
    func update(_ kind: WidgetKind, _ mutate: (inout WidgetItem) -> Void) {
        guard let i = preferences.widgets.firstIndex(where: { $0.kind == kind }) else { return }
        var value = preferences; mutate(&value.widgets[i]); preferences = value
    }
    func resetPositions() {
        var value = preferences
        for i in value.widgets.indices { value.widgets[i].x = nil; value.widgets[i].y = nil }
        preferences = value
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
/// Keep the whole widget reachable when resizing or disconnecting a monitor.
func clampedFrame(_ frame: CGRect, within bounds: CGRect) -> CGRect {
    var result = frame
    result.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
    result.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
    return result
}

enum MacGlyph: String {
    case classicNotebook, notchedNotebook, desktop, generic
    static func resolve(model: String, builtInNotch: Bool) -> MacGlyph {
        if builtInNotch { return .notchedNotebook }
        let knownNotched: Set<String> = ["MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", "Mac14,2", "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10", "Mac14,15"]
        if knownNotched.contains(model) { return .notchedNotebook }
        if model.hasPrefix("MacBook") || model == "Mac14,7" { return .classicNotebook }
        if model.hasPrefix("iMac") || model.hasPrefix("Macmini") || model.hasPrefix("MacPro") { return .desktop }
        return .generic
    }
}
