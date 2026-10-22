import AppKit
import Combine

private final class NativeBatteryFixture: NSObject {
    @objc dynamic var batteryPercentSingle: UInt8 { 10 }
    @objc dynamic var unavailable: UInt8 { 0 }
    @objc dynamic var invalid: UInt8 { 255 }
    @objc dynamic var wide: Int64 { 73 }
    @objc dynamic var wrongType: String { "50" }
}

@main
struct MenuChecks {
    @MainActor static func main() {
        precondition(!NotesRefreshPolicy.shouldRead(userInitiated: false, running: false, elapsed: 300), "Closed Notes must not be launched by a widget refresh")
        precondition(!NotesRefreshPolicy.shouldRead(userInitiated: false, running: true, elapsed: 1), "Calendar notifications must not trigger repeated Notes queries")
        precondition(NotesRefreshPolicy.shouldRead(userInitiated: false, running: true, elapsed: 300))
        precondition(NotesRefreshPolicy.shouldRead(userInitiated: true, running: false, elapsed: 0), "Explicit connection may open Notes")
        let nativeBattery = NativeBatteryFixture()
        precondition(BluetoothBatteryService.nativePercent(nativeBattery, selectors: ["batteryPercentSingle"]) == 10)
        precondition(BluetoothBatteryService.nativePercent(nativeBattery, selectors: ["missing", "unavailable", "invalid", "wrongType"]) == nil)
        precondition(BluetoothBatteryService.nativePercent(nativeBattery, selectors: ["invalid", "wide"]) == 73)
        let named = BluetoothReading(name: "Microsoft Arc de Eduardo", address: "AA-BB-CC-DD-EE-FF", overall: nil, left: nil, right: nil, caseLevel: nil)
        let hid = BluetoothReading(name: "Surface Arc Mouse", deviceType: "mouse", address: "aa:bb:cc:dd:ee:ff", overall: 63, left: nil, right: nil, caseLevel: nil)
        let merged = BluetoothBatteryService.merge(report: [named], connected: [named, hid])
        precondition(merged.count == 1 && merged[0].name == named.name && merged[0].overall == 63)
        let reported = BluetoothReading(name: named.name, address: named.address, overall: 10, left: nil, right: nil, caseLevel: nil)
        precondition(BluetoothBatteryService.merge(report: [reported], connected: [hid])[0].overall == 10)
        precondition(HUDStyle.deviceConnection.atTop && HUDStyle.nowPlayingClassic.atTop && !HUDStyle.iOSVolume.atTop)
        var connections = BluetoothConnectionTracker()
        precondition(connections.update([named]).isEmpty && connections.removed.isEmpty)
        precondition(connections.update([reported]).isEmpty && connections.removed.isEmpty)
        precondition(connections.update([]).isEmpty && connections.removed == [reported])
        precondition(connections.update([]).isEmpty && connections.removed.isEmpty)
        precondition(connections.update([named]) == [named])
        _ = connections.update([], announce: false)
        precondition(connections.removed.isEmpty)
        var burst = HUDBurstPolicy()
        for index in 1...3 {
            precondition(burst.compact(style: .iOSVolume, value: Double(index) / 10, visible: index > 1, mode: .automatic, now: Double(index) * 0.15))
        }
        precondition(!burst.compact(style: .iOSVolume, value: 0.4, visible: true, mode: .automatic, now: 0.6))
        precondition(!burst.compact(style: .iOSVolume, value: 0.5, visible: true, mode: .automatic, now: 2), "Expanded HUD stays expanded until dismissal")
        precondition(burst.compact(style: .iOSVolume, value: 0.6, visible: false, mode: .automatic, now: 3))
        precondition(burst.compact(style: .iOSDisplay, value: 0.7, visible: true, mode: .automatic, now: 3.1), "Switching controls starts a new burst")
        precondition(!burst.compact(style: .iOSKeyboard, value: 0.5, visible: true, mode: .thin, now: 3.2), "Keyboard never uses the thin mode")
        burst.reset()
        for index in 0..<20 {
            precondition(burst.compact(style: .iOSVolume, value: 0.5, visible: true, mode: .automatic, now: Double(index) * 0.01), "Duplicate callbacks must not expand")
        }
        burst.reset()
        for index in 0..<6 {
            precondition(burst.compact(style: .iOSDisplay, value: Double(index) / 10, visible: true, mode: .automatic, now: Double(index)), "Separated taps reset the burst")
        }
        precondition(!burst.compact(style: .iOSVolume, value: 0.5, visible: false, mode: .full, now: 10))
        precondition(burst.compact(style: .iOSVolume, value: 0.5, visible: false, mode: .thin, now: 10))
        print("PASS: adaptive HUD thresholds, duplicates, spacing, dismissal, modes and keyboard exclusion")
        let now = Date()
        let overlapping = [CalendarEntry(id: "a", title: "A", start: now, end: now.addingTimeInterval(3600), allDay: false), CalendarEntry(id: "b", title: "B", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400), allDay: false), CalendarEntry(id: "c", title: "C", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), allDay: false)]
        precondition(AgendaTimeline.lane(for: overlapping[0], among: overlapping).index == 0)
        precondition(AgendaTimeline.lane(for: overlapping[1], among: overlapping).index == 1)
        precondition(AgendaTimeline.lane(for: overlapping[2], among: overlapping).index == 0)
        var preferences = DeskPreferences()
        preferences.widgets = [WidgetItem(kind: .calendar, variant: "date", size: .medium, x: 42, y: 100)]
        preferences.normalize()
        precondition(preferences.widgets.first!.x == 42 && preferences.widgets.first!.size == .medium)
        preferences.widgets[0].size = .small; preferences.normalize()
        precondition(preferences.widgets[0].size == .small)
        let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let size = CGSize(width: 300, height: 300)
        precondition(HUDPosition.left.origin(screen: screen, size: size).x == -1920)
        precondition(HUDPosition.right.origin(screen: screen, size: size).x == -300)
        precondition(HUDPosition.center.origin(screen: screen, size: size) == CGPoint(x: -1110, y: -100))
        let state = HUDState()
        var updates = 0
        let token = state.$value.dropFirst().sink { _ in updates += 1 }
        for _ in 0..<100 { state.show(style: .iOSVolume, value: 0.65) }
        precondition(updates == 1, "Repeated levels must not invalidate the view")
        withExtendedLifetime(token) {}
        precondition(IOSHUDView(value: 0.7, icon: "speaker", isVisible: true).currentIcon == "speaker.wave.3.fill", "Volume glyph must use the latest level before fill animation starts")
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 1440, height: 24), display: display))
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -18, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -24, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 300, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 60, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 1440, y: 0, width: 1920, height: 24), display: display))
        let second = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: -1920, y: -100, width: 1920, height: 24), display: second))
        print("PASS menu visible, entering, hidden, unrelated windows and multiple-display coordinates")
    }
}
