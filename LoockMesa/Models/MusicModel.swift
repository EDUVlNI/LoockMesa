import Foundation

enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, appleMusic, spotify, deezer
    var id: String { rawValue }
    var title: String { switch self { case .automatic: return "Automático"; case .appleMusic: return "Apple Music"; case .spotify: return "Spotify"; case .deezer: return "Deezer" } }
    var bundleID: String? { switch self { case .automatic: return nil; case .appleMusic: return "com.apple.Music"; case .spotify: return "com.spotify.client"; case .deezer: return "com.deezer.deezer-desktop" } }
    static func from(bundle: String) -> MusicProvider? { allCases.first { $0.bundleID == bundle } }
    func accepts(_ bundle: String?) -> Bool {
        guard let bundle, Self.from(bundle: bundle) != nil else { return false }
        return self == .automatic || bundleID == bundle
    }
}
struct MusicShortcut: Codable, Equatable {
    var title = ""
    var link = ""
    var artwork: Data? = nil
    var url: URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if url.scheme == "spotify" { return url }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let allowed = ["music.apple.com", "open.spotify.com", "deezer.com", "www.deezer.com", "deezer.page.link"]
        return allowed.contains(host) ? url : nil
    }
}

/// Shared geometry for SwiftUI and the desktop's native accessible hit targets.
struct MusicLayout {
    let size: WidgetSize
    var artwork: CGRect {
        switch size {
        case .small: return CGRect(x: 15, y: 15, width: 76, height: 76)
        case .medium: return CGRect(x: 16, y: 15, width: 48, height: 48)
        case .large: return CGRect(x: 20, y: 23, width: 100, height: 100)
        }
    }
    var play: CGRect {
        switch size {
        case .small: return CGRect(x: 111, y: 109, width: 38, height: 38)
        case .medium: return CGRect(x: 258, y: 19, width: 40, height: 40)
        case .large: return CGRect(x: 274, y: 59, width: 48, height: 48)
        }
    }
    var source: CGRect { CGRect(x: size.dimensions.width - 33, y: 13, width: 19, height: 19) }
    var metadata: CGRect {
        switch size {
        case .small: return CGRect(x: 15, y: 105, width: 90, height: 48)
        case .medium: return CGRect(x: 76, y: 22, width: 169, height: 41)
        case .large: return CGRect(x: 135, y: 49, width: 127, height: 69)
        }
    }
    var dividerY: CGFloat { size == .large ? 151 : 76 }
    func shortcut(_ index: Int) -> CGRect {
        let edge: CGFloat = size == .large ? 20 : 16
        let gap: CGFloat = 12
        let side = (size.dimensions.width - 2 * edge - 3 * gap) / 4
        return CGRect(x: edge + CGFloat(index) * (side + gap), y: size == .large ? 192 : 87, width: side, height: side)
    }
}
extension Notification.Name {
    static let loockMusicSettings = Notification.Name("LoockMusicSettings")
    static let loockSelectMusic = Notification.Name("LoockSelectMusic")
}

struct SpotifyRecentAlbum: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var artist: String
    var artwork: Data?
}
struct SpotifyRecentHistory: Codable, Equatable {
    private(set) var albums: [SpotifyRecentAlbum] = []
    mutating func record(album: String, artist: String, artwork: Data?, playing: Bool) {
        let title = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let id = (title + "\u{001F}" + artist.trimmingCharacters(in: .whitespacesAndNewlines)).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let existing = albums.firstIndex { $0.id == id }
        guard playing || existing != nil else { return }
        let old = existing.map { albums[$0] }
        let item = SpotifyRecentAlbum(id: id, title: title, artist: artist, artwork: artwork ?? old?.artwork)
        if let existing { albums[existing] = item }
        if playing {
            albums.removeAll { $0.id == id }
            albums.insert(item, at: 0)
        }
        albums = Array(albums.prefix(4))
    }
}
