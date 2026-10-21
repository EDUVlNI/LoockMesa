import AppKit

@main
struct CursorChecks {
    static func main() throws {
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
        print("Cursor artwork: 42 variants, Retina, animation frames, hotspot round trips and invalid input passed; no system cursors changed.")
    }
}
