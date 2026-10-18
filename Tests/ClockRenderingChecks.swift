import SwiftUI
import AppKit

@main struct ClockRenderingChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
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
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        let resumed = try capture(analogHost, "clock029-resumed.png")
        precondition(resumed != pausedB && resumed != recovering, "Rendered clock must recover and continue ticking")
        print("PASS: actual NSHostingView renders analog movement, digital marker movement, outside-desktop freeze and animated recovery")
        let weather = WeatherService(preview: .demo)
        var previewWindows: [NSWindow] = []
        for variant in ["daily", "details", "sun"] {
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
        withExtendedLifetime((analogWindow, digitalWindow, previewWindows)) {}

    }
}
