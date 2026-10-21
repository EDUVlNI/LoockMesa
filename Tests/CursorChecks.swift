import AppKit

@main
struct CursorChecks {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: "Resources/GoldenGate.cape")
        let data = try Data(contentsOf: url)
        let root = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let entries = root["Cursors"] as! [String: [String: Any]]
        precondition(entries.count == 42)
        for (name, entry) in entries {
            let art = try CursorArtwork(dictionary: entry)
            let recovered = try CursorArtwork(dictionary: art.dictionary())
            precondition(recovered.size == art.size && recovered.hotspot == art.hotspot, name)
            precondition(recovered.frames == art.frames && recovered.duration == art.duration, name)
            precondition(recovered.images.count == art.images.count, name)
        }
        let arrow = try CursorArtwork(dictionary: entries["com.apple.coregraphics.Arrow"]!)
        precondition(arrow.hotspot == CGPoint(x: 5, y: 5))
        precondition(arrow.size == CGSize(width: 28, height: 40))
        let wait = try CursorArtwork(dictionary: entries["com.apple.coregraphics.Wait"]!)
        precondition(wait.frames == 30)
        for (key, invalid) in [("FrameCount", 0.0), ("FrameCount", 1.5), ("HotSpotX", -1.0), ("PointsWide", 0.0), ("HotSpotY", 999.0)] {
            var entry = entries["com.apple.coregraphics.Arrow"]!
            entry[key] = invalid
            do { _ = try CursorArtwork(dictionary: entry); fatalError("Accepted invalid \(key)") }
            catch { }
        }
        try checkVenturaRecovery(entries: entries, themeURL: url)
        print("Cursor artwork: 42 variants, Retina, animation frames, hotspot round trips and invalid input passed; no system cursors changed.")
    }
}


private final class VenturaCursorRegistry: CursorRegistry {
    var writes: [String] = []
    var current: [String: CursorArtwork] = [:]
    var rejectThemedIBeam = false
    var rejectOriginalArrow = false
    let original: CursorArtwork
    init(original: CursorArtwork) { self.original = original }
    func read(_ name: String) -> CursorArtwork? { original }
    func write(_ name: String, _ artwork: CursorArtwork) throws {
        writes.append(name)
        if name == "com.apple.coregraphics.Wait" ||
            (rejectThemedIBeam && name == "com.apple.coregraphics.IBeam" && artwork.hotspot != .zero) ||
            (rejectOriginalArrow && name == "com.apple.coregraphics.Arrow" && artwork.hotspot == .zero) {
            throw NSError(domain: "VenturaCursorRegistry", code: 1000)
        }
        current[name] = artwork
    }
}

@MainActor
private func checkVenturaRecovery(entries: [String: [String: Any]], themeURL: URL) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let backup = folder.appendingPathComponent("CursorOriginals.plist")
    let suite = "CursorChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let arrowName = "com.apple.coregraphics.Arrow"
    let waitName = "com.apple.coregraphics.Wait"
    var originalDictionary = entries[arrowName]!
    originalDictionary["HotSpotX"] = 0; originalDictionary["HotSpotY"] = 0
    let original = try CursorArtwork(dictionary: originalDictionary)
    let registry = VenturaCursorRegistry(original: original)
    let service = CursorThemeService(registryFactory: { registry }, backupURL: backup, themeURL: themeURL, defaults: defaults)

    // Reproduce the 1.4.0 snapshot that got stuck on Wait error 1000.
    let legacy = try PropertyListSerialization.data(fromPropertyList: ["Cursors": [arrowName: originalDictionary, waitName: entries[waitName]!]], format: .binary, options: 0)
    try legacy.write(to: backup)
    service.start()
    precondition(registry.writes == [arrowName], "Legacy recovery must never register Wait")
    precondition(!FileManager.default.fileExists(atPath: backup.path))
    precondition(registry.current[arrowName]?.hotspot == .zero)

    service.setEnabled(true)
    precondition(service.enabled && defaults.bool(forKey: "GergelimGoldenGateCursor"))
    precondition(registry.current.count == 41 && !registry.writes.contains(waitName))
    precondition(registry.current[arrowName]?.hotspot == CGPoint(x: 5, y: 5))
    let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: backup), format: nil) as! [String: Any]
    precondition((saved["Cursors"] as! [String: Any])[waitName] == nil)
    service.setEnabled(false)
    precondition(!service.enabled && !FileManager.default.fileExists(atPath: backup.path))
    precondition(registry.current[arrowName]?.hotspot == .zero)

    // A different registration error must still roll back the preceding writes.
    registry.rejectThemedIBeam = true
    service.setEnabled(true)
    precondition(!service.enabled && !FileManager.default.fileExists(atPath: backup.path))
    precondition(registry.current[arrowName]?.hotspot == .zero)
    registry.rejectThemedIBeam = false

    // Genuine restore failures must retain their recovery snapshot.
    service.setEnabled(true)
    registry.rejectOriginalArrow = true
    service.setEnabled(false)
    precondition(FileManager.default.fileExists(atPath: backup.path))
    precondition(service.status.contains("Restauração pendente"))
    registry.rejectOriginalArrow = false
    service.stop()
    precondition(!FileManager.default.fileExists(atPath: backup.path))
    precondition(!registry.writes.contains(waitName))
    print("Ventura Wait 1000 recovery, 41 compatible registrations, opt-out, rollback and durable recovery passed with an injected registry.")
}
