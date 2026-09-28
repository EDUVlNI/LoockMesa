import Foundation

final class BluetoothBatteryService: ObservableObject {
    @Published private(set) var devices: [BluetoothReading] = []
    @Published private(set) var status = "Consultando Bluetooth…"
    @Published private(set) var updated: Date?
    @Published private(set) var refreshing = false
    private var timer: Timer?
    private var paused = false
    func setPaused(_ value: Bool) { paused = value; if !value && (updated == nil || Date().timeIntervalSince(updated!) >= 120) { refresh() } }
    init(automatic: Bool = true) {
        if automatic {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
            timer?.tolerance = 20
        }
    }
    deinit { timer?.invalidate() }
    var freeClip: BluetoothReading? { devices.first(where: \.isFreeClip) }
    func refresh() {
        guard !refreshing, !paused else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini", "-timeout", "10"]
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
            let values = result; let valid = success
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshing = false
                if self.devices != values { self.devices = values } // Never keep a stale level after disconnect/failure.
                self.updated = valid ? Date() : nil
                if !valid { self.status = "Leitura Bluetooth indisponível" }
                else if let clip = values.first(where: \.isFreeClip) {
                    self.status = clip.hasBattery ? "Leitura do macOS" : "FreeClip conectado; bateria não informada pelo macOS"
                } else { self.status = values.contains(where: \.hasBattery) ? "Baterias dos dispositivos conectados" : "Nenhuma bateria Bluetooth informada pelo macOS" }
            }
        }
    }
}
