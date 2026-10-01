import Foundation

@main
struct Checks {
    static func main() throws {
        let suite = "LoockMesa.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeskStore(defaults: defaults)
        store.update(.headphones) { $0.size = .large; $0.x = -1200; $0.y = 700 }
        store.update(.weather) { $0.enabled = false }
        store.preferences.positionsLocked = true
        store.preferences.city = .lisboa
        assert(DeskStore(defaults: defaults).preferences == store.preferences)
        store.resetPositions()
        assert(store.preferences.widgets.allSatisfy { $0.x == nil && $0.y == nil })
        var broken = DeskPreferences()
        broken.widgets = [WidgetItem(kind: .clock), WidgetItem(kind: .clock)]
        broken.normalize()
        assert(Set(broken.widgets.map(\.kind)) == Set(WidgetKind.allCases))
        assert(broken.widgets.count == WidgetKind.allCases.count)
        var legacyClock = DeskPreferences()
        legacyClock.widgets[2].variant = "digital"
        legacyClock.widgets[2].size = .large
        legacyClock.normalize()
        assert(legacyClock.widgets[2].size == .medium)
        defaults.set(Data("invalid".utf8), forKey: "LoockMesa.preferences.v4")
        assert(DeskStore(defaults: defaults).preferences == DeskPreferences())
        let focusScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let focusWindow = DesktopFocusWindow(ownerPID: 42, layer: 0, alpha: 1, bounds: CGRect(x: 20, y: 20, width: 900, height: 700))
        assert(!DesktopFocusPolicy.isDesktop(frontmostID: "com.apple.Safari", ownID: "loock", frontmostPID: 42, windows: [focusWindow], screens: [focusScreen]))
        assert(DesktopFocusPolicy.isDesktop(frontmostID: "com.apple.Safari", ownID: "loock", frontmostPID: 42, windows: [], screens: [focusScreen]))
        assert(DesktopFocusPolicy.isDesktop(frontmostID: "com.apple.finder", ownID: "loock", frontmostPID: 42, windows: [focusWindow], screens: [focusScreen]))
        let offscreen = DesktopFocusWindow(ownerPID: 42, layer: 0, alpha: 1, bounds: focusWindow.bounds.offsetBy(dx: 1600, dy: 0))
        let overlay = DesktopFocusWindow(ownerPID: 42, layer: 25, alpha: 1, bounds: focusWindow.bounds)
        assert(DesktopFocusPolicy.isDesktop(frontmostID: "com.apple.Safari", ownID: "loock", frontmostPID: 42, windows: [offscreen, overlay], screens: [focusScreen]))
        print("PASS: desktop focus follows visible foreground windows, ignores overlays and offscreen windows")
        let before = ClockHandAngles(hour: 6.2, minute: 6.25, second: 6.26)
        let after = ClockHandAngles(hour: 0.05, minute: 0.06, second: 0.07)
        let forward = before.forward(to: after)
        assert(forward.hour >= before.hour && forward.hour < before.hour + 2 * .pi)
        assert(forward.minute >= before.minute && forward.second >= before.second)
        assert(abs(forward.second.truncatingRemainder(dividingBy: 2 * .pi) - after.second) < 0.000001)
        let middle = before.interpolated(to: forward, progress: 0.5)
        assert(middle.second > before.second && middle.second < forward.second)
        assert(before.interpolated(to: forward, progress: 1) == forward)
        print("PASS: clock recovery crosses twelve clockwise, interpolates and reaches the correct angles")
        var styles = DeskPreferences()
        styles.surface = .transparent
        styles.individualSurface = [WidgetKind.clock.rawValue: .original]
        styles.individualAppearance = [WidgetKind.clock.rawValue: .light]
        styles.widgets[2].variant = "digital"
        let restoredStyles = try! JSONDecoder().decode(DeskPreferences.self, from: JSONEncoder().encode(styles))
        assert(restoredStyles.surfaceStyle(.clock) == .original)
        assert(restoredStyles.surfaceStyle(.weather) == .transparent)
        assert(restoredStyles.appearanceStyle(.clock) == .light)
        assert(restoredStyles.widgets[2].variant == "digital")
        var weatherColors = DeskPreferences()
        weatherColors.appearance = .dark
        assert(weatherColors.appearanceStyle(.weather) == .original)
        weatherColors.individualAppearance = [WidgetKind.weather.rawValue: .light]
        assert(weatherColors.appearanceStyle(.weather) == .light)
        var retired = DeskPreferences()
        retired.widgets.append(WidgetItem(kind: .screenTime, size: .medium))
        retired.surface = .transparent
        retired.individualSurface = [WidgetKind.clock.rawValue: .transparent]
        retired.monochrome = true
        retired.normalize()
        assert(!retired.widgets.contains(where: { $0.kind == .screenTime }))
        assert(retired.surface == .frosted && retired.surfaceStyle(.clock) == .frosted && !retired.monochrome)
        assert(WidgetSurface.allCases == [.original, .frosted])
        print("PASS: surface overrides, variant persistence, retired modes and Screen Time migration")
        let screen = CGRect(x: -1440, y: 50, width: 1440, height: 850)
        let outside = CGRect(x: -2000, y: 2000, width: 344, height: 344)
        let clamped = clampedFrame(outside, within: screen)
        assert(screen.contains(clamped))
        assert(clamped.maxY == screen.maxY)
        for size in WidgetSize.allCases {
            let frame = clampedFrame(CGRect(origin: CGPoint(x: 5000, y: -3000), size: size.dimensions), within: CGRect(x: 0, y: 0, width: 1280, height: 800))
            assert(frame.minY == 0 && frame.maxX == 1280)
        }
        let data = Data(#"{"current":{"time":"2026-09-22T14:15","temperature_2m":21.4,"weather_code":2},"hourly":{"time":["2026-09-22T13:00","2026-09-22T14:00","2026-09-22T15:00"],"temperature_2m":[20,21,22],"weather_code":[0,2,3]},"daily":{"time":["2026-09-22"],"temperature_2m_min":[16],"temperature_2m_max":[24],"weather_code":[2]}}"#.utf8)
        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data).snapshot()
        assert(forecast.temperature == 21 && forecast.hours.first?.temperature == 21 && forecast.hours.count == 2)
        assert(forecast.days.first?.label == "Hoje")
        let empty = Data(#"{"current":{"time":"2026-09-22T14:15","temperature_2m":21,"weather_code":2},"hourly":{"time":[],"temperature_2m":[],"weather_code":[]},"daily":{"time":[],"temperature_2m_min":[],"temperature_2m_max":[],"weather_code":[]}}"#.utf8)
        do { _ = try JSONDecoder().decode(ForecastResponse.self, from: empty).snapshot(); assertionFailure("Empty daily must be rejected") } catch {}
        let nightData = Data(String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"weather_code\":2}", with: "\"weather_code\":45,\"is_day\":0}").utf8)
        let night = try JSONDecoder().decode(ForecastResponse.self, from: nightData).snapshot()
        assert(!night.isDay && WeatherMood.resolve(code: night.code, isDay: night.isDay) == .fogNight)
        assert(WeatherMood.resolve(code: 0, isDay: true) == .sunny)
        assert(WeatherMood.resolve(code: 0, isDay: false) == .clearNight)
        assert(WeatherSnapshot.symbol(45, isDay: false) == "moon.haze.fill")
        assert(WeatherMood.resolve(code: 95, isDay: true) == .storm)
        assert(!DeskPreferences().demoHeadphones && DeskPreferences().liveWeather)
        let bt = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"HUAWEI FreeClip 2":{"device_batteryLevelMain":"83%","device_batteryLevelLeft":"82%","device_batteryLevelRight":"0%","device_batteryLevelCase":"255%"}}],"device_not_connected":[{"Old":{"device_batteryLevelMain":"99%"}}]}]}"#.utf8)
        let readings = try BluetoothReport.parse(bt)
        assert(readings.count == 1 && readings[0].isFreeClip && readings[0].overall == 83 && readings[0].right == 0 && readings[0].caseLevel == nil)
        assert(BluetoothReport.percent("-1%") == nil && BluetoothReport.percent("unknown") == nil)
        let disconnected = Data(#"{"SPBluetoothDataType":[{"device_not_connected":[{"FreeClip 2":{"device_batteryLevelMain":"99%"}}]}]}"#.utf8)
        let absent = try BluetoothReport.parse(disconnected)
        assert(absent.isEmpty)
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let preferred = CGRect(x: 20, y: 676, width: 164, height: 164)
        let requests = WidgetKind.allCases.map { PlacementRequest(kind: $0, size: WidgetSize.small.dimensions, preferred: preferred) }
        let layout = DesktopGrid.arrange(requests, screens: [bounds])
        assert(layout.count == requests.count)
        let frames = Array(layout.values)
        for i in frames.indices {
            assert(bounds.contains(frames[i]))
            assert(abs((frames[i].minX - 20).truncatingRemainder(dividingBy: 180)) < 0.1)
            for j in frames.indices where i != j { assert(!DesktopGrid.conflicts(frames[i], frames[j])) }
        }
        let larger = DesktopGrid.nearest(size: WidgetSize.large.dimensions, to: preferred, screens: [bounds], occupied: [preferred])!
        assert(!DesktopGrid.conflicts(larger, preferred))
        assert(DesktopGrid.nearest(size: WidgetSize.large.dimensions, to: preferred, screens: [CGRect(x: 0, y: 0, width: 300, height: 200)], occupied: []) == nil)
        let leftScreen = CGRect(x: -1440, y: -100, width: 1440, height: 860)
        let left = DesktopGrid.nearest(size: WidgetSize.large.dimensions, to: CGRect(x: -1400, y: 300, width: 344, height: 344), screens: [bounds, leftScreen], occupied: [])!
        assert(leftScreen.contains(left))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let feb = cal.date(from: DateComponents(year: 2024, month: 2, day: 15))!
        let cells = MonthLayout.days(containing: feb, calendar: cal)
        assert(cells.compactMap(\.number).count == 29 && cells.count % 7 == 0)
        let migration = "LoockMesa.migration.\(UUID().uuidString)"
        let oldDefaults = UserDefaults(suiteName: migration)!
        var oldPrefs = DeskPreferences(); oldPrefs.demoHeadphones = true; oldPrefs.liveWeather = false
        oldPrefs.widgets = [WidgetItem(kind: .headphones, x: 200, y: 600)]
        oldDefaults.set(try JSONEncoder().encode(oldPrefs), forKey: "LoockMesa.preferences.v1")
        let migrated = DeskStore(defaults: oldDefaults)
        assert(!migrated.preferences.demoHeadphones && migrated.preferences.liveWeather && migrated.preferences.widgets.count == WidgetKind.allCases.count)
        assert(migrated.item(.headphones).x == 200)
        oldDefaults.removePersistentDomain(forName: migration)
        var legacy = DeskPreferences()
        legacy.widgets = [WidgetItem(kind: .macBattery, size: .large, x: 200, y: 700), WidgetItem(kind: .weather)]
        legacy.normalize()
        assert(!legacy.widgets.contains { $0.kind == .macBattery })
        assert(legacy.widgets.first { $0.kind == .headphones }?.x == 200)
        let moved = CGRect(x: 560, y: 496, width: 164, height: 164)
        let original = [PlacementRequest(kind: .headphones, size: preferred.size, preferred: preferred), PlacementRequest(kind: .clock, size: moved.size, preferred: moved)]
        let stable = DesktopGrid.arrange(original, screens: [bounds])
        for _ in 0..<50 {
            let restored = original.map { PlacementRequest(kind: $0.kind, size: $0.size, preferred: stable[$0.kind]!) }
            assert(DesktopGrid.arrange(restored, screens: [bounds]) == stable)
        }
        let connected = [BluetoothReading(name: "FreeClip", overall: 100, left: nil, right: nil, caseLevel: nil),
            BluetoothReading(name: "Keyboard", deviceType: "Keyboard", overall: 45, left: nil, right: nil, caseLevel: nil),
            BluetoothReading(name: "Mouse", overall: 0, left: nil, right: nil, caseLevel: nil),
            BluetoothReading(name: "Sem carga", overall: nil, left: nil, right: nil, caseLevel: nil)]
        let entries = BatteryEntry.entries(mac: 82, charging: false, readings: connected)
        assert(entries.count == 4 && entries.map(\.value) == [82, 100, 45, 0])
        assert(entries[1].freeClip && entries[2].symbol == "keyboard" && entries[3].symbol == "computermouse")
        let separate = BluetoothReading(name: "Fones", overall: 80, left: 80, right: 70, caseLevel: 50)
        let split = BatteryEntry.entries(mac: nil, charging: false, readings: [separate, separate])
        assert(split.count == 3 && split.map(\.value) == [80, 70, 50])
        assert(BatteryEntry.entries(mac: nil, charging: false, readings: []).isEmpty)
        assert(WeatherMood.resolve(code: 3, isDay: true) == .cloudy)
        assert(WeatherMood.resolve(code: 3, isDay: false) == .cloudyNight)
        assert(WeatherMood.resolve(code: 61, isDay: true) == .rain)
        var previous = DeskPreferences(); previous.appearance = nil
        defaults.removeObject(forKey: "LoockMesa.preferences.v4")
        defaults.set(try JSONEncoder().encode(previous), forKey: "LoockMesa.preferences.v3")
        let themeMigration = DeskStore(defaults: defaults)
        assert(themeMigration.preferences.appearance == nil)
        themeMigration.preferences.appearance = .light
        assert(DeskStore(defaults: defaults).preferences.appearance == .light)
        let finishStore = DeskStore(defaults: defaults)
        assert(finishStore.preferences.frostedClock == nil && finishStore.preferences.frostedBattery == nil)
        finishStore.preferences.frostedClock = false
        finishStore.preferences.frostedBattery = true
        let finishes = DeskStore(defaults: defaults).preferences
        assert(finishes.frostedClock == false && finishes.frostedBattery == true)
        let additions = DeskStore(defaults: defaults)
        assert(!additions.item(.music).enabled)
        assert(MusicProvider.automatic.accepts("com.deezer.deezer-desktop"))
        assert(!MusicProvider.spotify.accepts("com.apple.Music"))
        assert(!MusicProvider.automatic.accepts("com.apple.Safari"))
        assert(MusicShortcut(link: "https://open.spotify.com/playlist/example").url != nil)
        assert(MusicShortcut(link: "https://open.spotify.com.evil.test/").url == nil)
        assert(MusicShortcut(link: "file:///tmp/test").url == nil)
        for size in WidgetSize.allCases {
            let layout = MusicLayout(size: size)
            let bounds = CGRect(origin: .zero, size: size.dimensions)
            assert(bounds.contains(layout.play) && bounds.contains(layout.artwork))
            assert(!layout.play.intersects(layout.metadata))
            if size != .small { for index in 0..<4 { assert(bounds.contains(layout.shortcut(index))) } }
        }
        assert(!additions.item(.notes).enabled && !additions.item(.reminders).enabled)
        additions.preferences.localNoteTitle = "Minha nota"
        additions.preferences.localNoteBody = "Texto persistido"
        additions.update(.notes) { $0.enabled = true }
        let reopened = DeskStore(defaults: defaults)
        assert(reopened.item(.notes).enabled && reopened.preferences.localNoteBody == "Texto persistido")
        reopened.update(.notes) { $0.enabled = false }
        assert(reopened.preferences.localNoteTitle == "Minha nota")
        let pushScreen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let slots = DesktopGrid.candidates(size: WidgetSize.small.dimensions, screen: pushScreen)
        let pushed = DesktopGrid.arrange([
            PlacementRequest(kind: .clock, size: slots[0].size, preferred: slots[1]),
            PlacementRequest(kind: .calendar, size: slots[1].size, preferred: slots[1]),
            PlacementRequest(kind: .notes, size: slots[2].size, preferred: slots[2])], screens: [pushScreen])
        assert(pushed[.clock] == slots[1])
        assert(pushed.count == 3 && pushed[.calendar] != slots[1])
        for (kind, frame) in pushed { for (other, otherFrame) in pushed where other != kind { assert(!DesktopGrid.conflicts(frame, otherFrame)) } }
        let materialStore = DeskStore(defaults: defaults)
        materialStore.preferences.materialIntensities = ["clock": 0, "headphones": 0.85]
        let materialReload = DeskStore(defaults: defaults)
        assert(materialReload.preferences.materialIntensities?["clock"] == 0)
        assert(materialReload.preferences.materialIntensities?["headphones"] == 0.85)
        materialStore.update(.calendar) { $0.enabled = false }
        materialStore.update(.calendar) { $0.enabled = true }
        assert(materialStore.preferences.widgets.filter { $0.kind == .calendar && $0.enabled }.count == 1)
        materialStore.preferences.unifiedFrostIntensity = 0.4
        materialStore.preferences.unifiedFrost = true
        materialStore.preferences.opensAppsOnClick = false
        let generalReload = DeskStore(defaults: defaults).preferences
        assert(generalReload.unifiedFrostIntensity == 0.4 && generalReload.unifiedFrost == true && generalReload.opensAppsOnClick == false)
        var individual = DeskPreferences()
        individual.unifiedFrostIntensity = 0.7
        individual.individualFrost = ["clock": false, "reminders": true]
        individual.individualIntensity = ["reminders": 0.3]
        assert(!individual.usesFrost(.clock) && individual.usesFrost(.reminders))
        assert(individual.frostAmount(.reminders) == 0.3 && individual.frostAmount(.headphones) == 0.7)
        assert(MacGlyph.resolve(model: "MacBookPro14,3", builtInNotch: false) == .classicNotebook)
        assert(MacGlyph.resolve(model: "Mac14,7", builtInNotch: false) == .classicNotebook)
        assert(MacGlyph.resolve(model: "MacBookPro18,3", builtInNotch: false) == .notchedNotebook)
        assert(MacGlyph.resolve(model: "future", builtInNotch: true) == .notchedNotebook)
        assert(MacGlyph.resolve(model: "iMac18,3", builtInNotch: false) == .desktop)
        assert(MacGlyph.resolve(model: "unknown", builtInNotch: false) == .generic)
        var history = SpotifyRecentHistory()
        history.record(album: "Álbum", artist: "Artista", artwork: Data([1]), playing: true)
        history.record(album: "álbum", artist: "Artista", artwork: nil, playing: true)
        assert(history.albums.count == 1 && history.albums[0].artwork == Data([1]))
        history.record(album: "Não ouvido", artist: "Artista", artwork: nil, playing: false)
        assert(history.albums.count == 1)
        for n in 1...5 { history.record(album: "Album \(n)", artist: "A", artwork: nil, playing: true) }
        assert(history.albums.count == 4 && history.albums.first?.title == "Album 5")
        history.record(album: "Album 3", artist: "A", artwork: Data([2]), playing: false)
        assert(history.albums.first?.title == "Album 5")
        let restored = try! JSONDecoder().decode(SpotifyRecentHistory.self, from: JSONEncoder().encode(history))
        assert(restored == history)
        print("PASS: recent albums deduplicate, preserve covers, cap at four and round-trip")
        print("PASS: persistence, reset, corrupt data, normalization, multi-monitor clamp, P/M/G geometry, weather decoding, night themes, Bluetooth validity/disconnection, non-overlap grid, monitor placement, leap-year calendar and v1 migration")
    }
}
