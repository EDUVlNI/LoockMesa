import AppKit
import Combine
import Darwin

// Native cursor registration: ABI documented by CGSInternal/CGSCursor.h.
// Independent implementation; no mouse tracking, cursor warping or overlay window.
struct CursorArtwork {
    let size: CGSize
    let hotspot: CGPoint
    let frames: Int
    let duration: Double
    let images: [CGImage]

    init(dictionary: [String: Any]) throws {
        func number(_ key: String) throws -> Double {
            guard let n = dictionary[key] as? NSNumber, n.doubleValue.isFinite else {
                throw CursorThemeError.invalid(key)
            }
            return n.doubleValue
        }
        size = try CGSize(width: number("PointsWide"), height: number("PointsHigh"))
        hotspot = try CGPoint(x: number("HotSpotX"), y: number("HotSpotY"))
        let count = try number("FrameCount")
        guard count >= 1, count <= 120, count.rounded() == count else { throw CursorThemeError.invalid("FrameCount") }
        frames = Int(count)
        duration = try number("FrameDuration")
        guard size.width > 0, size.height > 0, size.width <= 256, size.height <= 256,
              hotspot.x >= 0, hotspot.x < size.width, hotspot.y >= 0, hotspot.y < size.height,
              duration >= 0, frames == 1 || duration > 0,
              let reps = dictionary["Representations"] as? [Data], !reps.isEmpty else {
            throw CursorThemeError.invalid("dimensões ou ponto de clique")
        }
        images = try reps.map { data in
            guard let rep = NSBitmapImageRep(data: data), let image = rep.cgImage,
                  image.height % frames == 0,
                  abs(Double(image.width) / size.width - Double(image.height / frames) / size.height) < 0.01 else {
                throw CursorThemeError.invalid("imagem ou animação")
            }
            return image
        }.sorted { $0.width < $1.width }
    }

    init(size: CGSize, hotspot: CGPoint, frames: Int, duration: Double, images: [CGImage]) {
        self.size = size; self.hotspot = hotspot; self.frames = frames
        self.duration = duration; self.images = images
    }

    func dictionary() throws -> [String: Any] {
        let reps = try images.map { image -> Data in
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CursorThemeError.invalid("cópia do ponteiro original")
            }
            return data
        }
        return ["PointsWide": size.width, "PointsHigh": size.height,
                "HotSpotX": hotspot.x, "HotSpotY": hotspot.y,
                "FrameCount": frames, "FrameDuration": duration, "Representations": reps]
    }
}

private enum CursorThemeError: LocalizedError {
    case invalid(String), unavailable(String), operation(String, Int32)
    var errorDescription: String? {
        switch self {
        case .invalid(let item): return "Tema de ponteiro inválido: \(item)."
        case .unavailable(let item): return "Ponteiro indisponível neste macOS: \(item)."
        case .operation(let name, let code): return "Não foi possível aplicar \(name) (erro \(code))."
        }
    }
}

private final class NativeCursorRegistry {
    typealias Connection = @convention(c) () -> Int32
    typealias Register = @convention(c) (Int32, UnsafePointer<CChar>, Bool, Bool, CGSize, CGPoint, UInt, Double, CFArray, UnsafeMutablePointer<Int32>) -> Int32
    typealias CopyNamed = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<UInt>, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Unmanaged<CFArray>?>) -> Int32
    typealias CopyCore = @convention(c) (Int32, Int32, UnsafeMutablePointer<Unmanaged<CFArray>?>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<UInt>, UnsafeMutablePointer<Double>) -> Int32
    let connection: Int32
    let register: Register
    let copyNamed: CopyNamed
    let copyCore: CopyCore
    // Keep the frameworks loaded for the lifetime of the function pointers.
    private let handles: [UnsafeMutableRawPointer]

    init() throws {
        let paths: [String] = ["/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                   "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                   "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                   "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"]
        let loadedHandles = paths.compactMap { path in path.withCString { dlopen($0, RTLD_LAZY | RTLD_LOCAL) } }
        handles = loadedHandles
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            for handle in loadedHandles {
                if let address = dlsym(handle, name) { return unsafeBitCast(address, to: type) }
            }
            throw CursorThemeError.unavailable(name)
        }
        let main = try symbol("CGSMainConnectionID", Connection.self)
        connection = main()
        guard connection != 0 else { throw CursorThemeError.unavailable("WindowServer") }
        register = try symbol("CGSRegisterCursorWithImages", Register.self)
        copyNamed = try symbol("CGSCopyRegisteredCursorImages", CopyNamed.self)
        copyCore = try symbol("CoreCursorCopyImages", CopyCore.self)
    }

    func read(_ name: String) -> CursorArtwork? {
        var size = CGSize.zero, hotspot = CGPoint.zero
        var frames: UInt = 0, duration = 0.0
        var array: Unmanaged<CFArray>?
        let result: Int32
        if name.hasPrefix("com.apple.cursor."), let id = Int32(name.split(separator: ".").last ?? "") {
            result = copyCore(connection, id, &array, &size, &hotspot, &frames, &duration)
        } else {
            result = name.withCString { copyNamed(connection, $0, &size, &hotspot, &frames, &duration, &array) }
        }
        guard let array else { return nil }
        let value = array.takeRetainedValue()
        guard result == 0, frames > 0, size.width > 0, size.height > 0,
              let images = value as? [CGImage], !images.isEmpty else { return nil }
        return CursorArtwork(size: size, hotspot: hotspot, frames: Int(frames), duration: duration, images: images)
    }

    func write(_ name: String, _ artwork: CursorArtwork) throws {
        var seed: Int32 = 0
        let result = name.withCString {
            register(connection, $0, true, true, artwork.size, artwork.hotspot,
                     UInt(artwork.frames), artwork.duration, artwork.images as CFArray, &seed)
        }
        guard result == 0 else { throw CursorThemeError.operation(name, result) }
    }
}

@MainActor
final class CursorThemeService: ObservableObject {
    static let shared = CursorThemeService()
    @Published private(set) var enabled = false
    @Published private(set) var status = "Use os ponteiros Golden Gate no macOS."
    private let preference = "GergelimGoldenGateCursor"
    private var registry: NativeCursorRegistry?
    private var originals: [String: CursorArtwork] = [:]
    private var theme: [String: CursorArtwork] = [:]
    private var observers: [NSObjectProtocol] = []
    private var reapplyWork: DispatchWorkItem?
    private var started = false
    private var backupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gergelim/CursorOriginals.plist")
    }

    func start() {
        guard !started else { return }; started = true
        // Recover the original image set if the preceding process did not exit cleanly.
        if FileManager.default.fileExists(atPath: backupURL.path) {
            do { try prepareRegistry(); originals = try load(backupURL); try restore() }
            catch { status = error.localizedDescription; return }
        }
        if UserDefaults.standard.bool(forKey: preference) { setEnabled(true) }
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleReapply() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReapply() }
        })
    }

    func setEnabled(_ value: Bool) {
        reapplyWork?.cancel()
        do {
            try prepareRegistry()
            if value {
                // Never overwrite an existing recovery snapshot with themed cursors.
                if !originals.isEmpty { try restore() }
                guard let url = Bundle.main.url(forResource: "GoldenGate", withExtension: "cape") else {
                    throw CursorThemeError.unavailable("arquivo GoldenGate.cape")
                }
                let loaded = try load(url)
                theme.removeAll()
                for (name, artwork) in loaded {
                    if let original = registry?.read(name) {
                        originals[name] = original; theme[name] = artwork
                    }
                }
                guard originals["com.apple.coregraphics.Arrow"] != nil else {
                    throw CursorThemeError.unavailable("cópia do ponteiro original")
                }
                try saveOriginals() // durable before the first global mutation
                try apply()
                enabled = true
                status = "Golden Gate ativo: \(theme.count) de \(loaded.count) ponteiros compatíveis."
            } else {
                try restore()
                enabled = false; status = "Ponteiros originais restaurados."
            }
            UserDefaults.standard.set(value, forKey: preference)
        } catch {
            let message = error.localizedDescription
            do { try restore(); enabled = false; UserDefaults.standard.set(false, forKey: preference); status = message }
            catch { status = "\(message) Restauração pendente: \(error.localizedDescription)" }
        }
    }

    func stop() {
        reapplyWork?.cancel()
        do { try restore(); enabled = false }
        catch { status = error.localizedDescription } // keep the durable recovery snapshot
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll(); started = false
    }

    private func prepareRegistry() throws {
        if registry == nil { registry = try NativeCursorRegistry() }
    }
    private func load(_ url: URL) throws -> [String: CursorArtwork] {
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let cursors = root["Cursors"] as? [String: [String: Any]], !cursors.isEmpty else {
            throw CursorThemeError.invalid("Cursors")
        }
        return try cursors.mapValues { try CursorArtwork(dictionary: $0) }
    }
    private func saveOriginals() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Cursors": originals.mapValues { try $0.dictionary() }], format: .binary, options: 0)
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: backupURL, options: .atomic)
    }
    private func apply() throws {
        guard let registry else { throw CursorThemeError.unavailable("registro") }
        for name in theme.keys.sorted() { try registry.write(name, theme[name]!) }
    }
    private func restore() throws {
        guard !originals.isEmpty else { return }
        guard let registry else { throw CursorThemeError.unavailable("restauração") }
        var failure: Error?
        for name in originals.keys.sorted() {
            do { try registry.write(name, originals[name]!) } catch { failure = error }
        }
        if let failure { throw failure }
        try? FileManager.default.removeItem(at: backupURL)
        originals.removeAll(); theme.removeAll()
    }
    private func scheduleReapply() {
        guard enabled else { return }
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled else { return }
            do { try self.apply() }
            catch { self.setEnabled(false); self.status = error.localizedDescription }
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
