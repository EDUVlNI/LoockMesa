import SwiftUI
import AppKit

@main struct ClockRenderingChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let colorFixture = NSImage(size: NSSize(width: 48, height: 48))
        colorFixture.lockFocus()
        NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 24, height: 48).fill()
        NSColor.blue.setFill(); NSRect(x: 24, y: 0, width: 24, height: 48).fill()
        colorFixture.unlockFocus()
        let palette = ArtworkPalette.colors(from: colorFixture)
        precondition(palette.contains { $0.redComponent > 0.5 && $0.blueComponent < 0.1 })
        precondition(palette.contains { $0.blueComponent > 0.5 && $0.redComponent < 0.1 })
        precondition(palette.allSatisfy { $0.greenComponent < 0.1 }, "Palette must not invent complementary colors")
        let neutralFixture = NSImage(size: NSSize(width: 24, height: 24))
        neutralFixture.lockFocus(); NSColor.gray.setFill(); NSRect(x: 0, y: 0, width: 24, height: 24).fill(); neutralFixture.unlockFocus()
        precondition(ArtworkPalette.colors(from: neutralFixture).allSatisfy { abs($0.redComponent - $0.greenComponent) < 0.02 && abs($0.greenComponent - $0.blueComponent) < 0.02 })
        print("PASS: artwork palette preserves real colors and neutral covers")
        let migrationDefaults = UserDefaults(suiteName: "Gergelim.MigrationTest")!
        migrationDefaults.removePersistentDomain(forName: "Gergelim.MigrationTest")
        GergelimMigration.run(defaults: migrationDefaults, readDomain: { domain in
            domain == "com.eduvini.LoockMesa" ? ["LoockMesa.preferences.v4": Data([1, 2, 3])] : ["CapsuleScale": 1.25, "ElementOrderV4": ["time", "music", "battery"]]
        })
        precondition(migrationDefaults.data(forKey: "LoockMesa.preferences.v4") == Data([1, 2, 3]))
        precondition(migrationDefaults.double(forKey: "CapsuleScale") == 1.25)
        precondition(migrationDefaults.stringArray(forKey: "ElementOrderV4") == ["time", "battery"])
        migrationDefaults.set(1.4, forKey: "CapsuleScale")
        GergelimMigration.run(defaults: migrationDefaults, readDomain: { _ in ["CapsuleScale": 0.8] })
        precondition(migrationDefaults.double(forKey: "CapsuleScale") == 1.4)
        migrationDefaults.removePersistentDomain(forName: "Gergelim.MigrationTest")
        precondition(GergelimSeed.image().isTemplate)
        print("PASS: Gergelim one-time preference migration preserves customization and removes capsule music")
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        func analog(_ inactive: Bool) -> some View {
            ModernClockWidget(size: .small, digital: false, dark: true, frosted: false, desktopInactive: inactive)
                .frame(width: 164, height: 164)
        }
        func capture<V: View>(_ host: NSHostingView<V>, _ file: String) throws -> Data {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = rep.representation(using: .png, properties: [:])!
            try data.write(to: outputDirectory.appendingPathComponent(file))
            return data
        }
        let analogHost = NSHostingView(rootView: analog(false))
        analogHost.frame = CGRect(x: 0, y: 0, width: 164, height: 164)
        let analogWindow = NSWindow(contentRect: analogHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        analogWindow.contentView = analogHost
        analogHost.layoutSubtreeIfNeeded()
        let digitalHost = NSHostingView(rootView: ModernClockWidget(size: .medium, digital: true, dark: false, frosted: false).frame(width: 344, height: 164))
        digitalHost.frame = CGRect(x: 0, y: 0, width: 344, height: 164)
        let digitalWindow = NSWindow(contentRect: digitalHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        digitalWindow.contentView = digitalHost
        digitalHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let firstAnalog = try capture(analogHost, "clock029-live-a.png")
        let firstDigital = try capture(digitalHost, "clock029-digital-a.png")
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        let secondAnalog = try capture(analogHost, "clock029-live-b.png")
        let secondDigital = try capture(digitalHost, "clock029-digital-b.png")
        precondition(firstAnalog != secondAnalog, "Rendered analog clock must move without interaction")
        precondition(firstDigital != secondDigital, "Rendered digital second markers must advance without interaction")
        analogHost.rootView = analog(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let pausedA = try capture(analogHost, "clock029-paused-a.png")
        RunLoop.main.run(until: Date().addingTimeInterval(1.3))
        let pausedB = try capture(analogHost, "clock029-paused-b.png")
        precondition(pausedA == pausedB, "Rendered analog clock must stop outside desktop")
        analogHost.rootView = analog(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let recovering = try capture(analogHost, "clock029-recovering.png")
        // Wait for observable advancement, allowing CI scheduling jitter while
        // still requiring recovery AND a later distinct rendered frame.
        let recoveryDeadline = Date().addingTimeInterval(4)
        var resumed = recovering
        repeat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            resumed = try capture(analogHost, "clock029-resumed.png")
        } while (resumed == pausedB || resumed == recovering) && Date() < recoveryDeadline
        precondition(resumed != pausedB && resumed != recovering, "Rendered clock must recover and continue ticking")
        print("PASS: actual NSHostingView renders analog movement, digital marker movement, outside-desktop freeze and animated recovery")
        var weatherFixture = WeatherSnapshot.demo
        weatherFixture.days += [ForecastDay(label: "Sex.", low: 16, high: 24, code: 61), ForecastDay(label: "Sáb.", low: 13, high: 21, code: 3), ForecastDay(label: "Dom.", low: 14, high: 22, code: 2)]
        weatherFixture.hours = [ForecastHour(label: "14", temperature: 21, code: 2), ForecastHour(label: "15", temperature: 20, code: 2), ForecastHour(label: "16", temperature: 20, code: 2), ForecastHour(label: "17", temperature: 19, code: 2), ForecastHour(label: "18", temperature: 18, code: 2), ForecastHour(label: "18:24", temperature: 17, code: 0, eventSymbol: "sunset.fill")]
        let weather = WeatherService(preview: weatherFixture)
        var previewWindows: [NSWindow] = []
        for variant in ["standard", "daily", "details", "sun"] {
            for size in WidgetSize.allCases {
                let host = NSHostingView(rootView: WeatherWidget(size: size, city: "Curitiba", service: weather, variant: variant)
                    .frame(width: size.dimensions.width, height: size.dimensions.height)
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous)))
                host.frame = CGRect(origin: .zero, size: size.dimensions)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host; previewWindows.append(window)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                _ = try capture(host, "weather-\(variant)-\(size.rawValue).png")
            }
        }
        for charging in [false, true] {
            let host = NSHostingView(rootView: HStack(spacing: 25) {
                ForEach([0, 20, 75, 100], id: \.self) { level in
                    BatteryRing(symbol: "laptopcomputer", value: level, dimension: 65, charging: charging, lowPower: !charging)
                }
            }.padding(25).background(Color(white: 0.12)))
            host.frame = CGRect(x: 0, y: 0, width: 390, height: 120)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; previewWindows.append(window)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            _ = try capture(host, "battery-\(charging).png")
        }
        let artwork = NSImage(size: NSSize(width: 32, height: 32))
        artwork.lockFocus(); NSColor.systemPurple.setFill(); NSRect(x: 0, y: 0, width: 32, height: 32).fill(); artwork.unlockFocus()
        let media = MusicService(api: MediaSourceAPI(pid: { _, done in done(42) }, info: { _, done in
            done(["kMRMediaRemoteNowPlayingInfoTitle": "Cores do álbum", "kMRMediaRemoteNowPlayingInfoArtist": "Prévia visual", "kMRMediaRemoteNowPlayingInfoArtworkData": artwork.tiffRepresentation!, "kMRMediaRemoteNowPlayingInfoDuration": 200, "kMRMediaRemoteNowPlayingInfoElapsedTime": 80] as CFDictionary)
        }, playing: { _, done in done(false) }, bundle: { _ in "com.spotify.client" }))
        media.configure(provider: .automatic, enabled: true)
        let musicHost = NSHostingView(rootView: LyricsWidget(size: .medium, media: media, appearance: .original, frosted: false).clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous)))
        musicHost.frame = CGRect(x: 0, y: 0, width: 344, height: 164)
        let musicWindow = NSWindow(contentRect: musicHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        musicWindow.contentView = musicHost; previewWindows.append(musicWindow)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        _ = try capture(musicHost, "music-matte.png")
        media.stop()
        let imported = LumeCoordinator.shared
        for page in IntegrationSettingsView.Page.allCases {
            let host = NSHostingView(rootView: IntegrationSettingsView(coordinator: imported, model: imported.capsule.model, hud: imported.hud, corners: imported.corners, player: imported.player, selected: page).padding(24).frame(width: 650, height: 850, alignment: .topLeading))
            host.frame = CGRect(x: 0, y: 0, width: 650, height: 850)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; previewWindows.append(window)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            _ = try capture(host, "gergelim-\(page.id).png")
        }
        withExtendedLifetime((analogWindow, digitalWindow, previewWindows)) {}

    }
}
