// Adapted from the user’s Eko MediaPlayer.swift. MediaRemote is private and best-effort on Ventura.
import AppKit
import Combine
import ImageIO

enum MusicSourcePolicy {
    static let allowed: [String: String] = [
        "com.spotify.client": "Spotify",
        "com.deezer.deezer-desktop": "Deezer",
        "com.apple.Music": "Apple Music"
    ]
    static func allows(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return allowed[bundleID] != nil
    }
}

struct MediaSourceAPI {
    var pid: ((DispatchQueue, @escaping (Int32) -> Void) -> Void)?
    var info: ((DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void)?
    var playing: ((DispatchQueue, @escaping (Bool) -> Void) -> Void)?
    var command: ((UInt32, CFDictionary?) -> Bool)?
    var bundle: (Int32) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
}

final class MusicService: ObservableObject {
    static let shared = MusicService()
    struct Track {
        var title = ""
        var artist = ""
        var album = ""
        var playing = false
        var artwork: NSImage?
        var source = ""
        var pid: Int32 = 0
        var bundle = ""
        var identity: String { "\(bundle)|\(title)|\(artist)|\(album)" }
    }
    @Published private(set) var track = Track()
    @Published private(set) var spotifyHistory = SpotifyRecentHistory()
    private let historyDefaults: UserDefaults?
    private let historyKey = "LoockMesa.spotifyRecentAlbums.v1"
    var collectsSpotifyCovers = true
    func clearSpotifyHistory() {
        spotifyHistory = SpotifyRecentHistory()
        historyDefaults?.removeObject(forKey: historyKey)
    }
    func usesSpotifyRecents(_ preferences: DeskPreferences) -> Bool {
        guard preferences.automaticSpotifyCovers != false else { return false }
        let selected = preferences.musicProvider ?? .automatic
        return selected == .spotify || (selected == .automatic && (track.bundle.isEmpty || track.bundle == "com.spotify.client"))
    }
    func recentSlot(_ index: Int) -> MusicShortcut {
        guard spotifyHistory.albums.indices.contains(index) else { return MusicShortcut() }
        let item = spotifyHistory.albums[index]
        // Search opens the actual album results; it does not pretend a guessed URI is an album ID.
        let query = (item.title + " " + item.artist).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return MusicShortcut(title: item.title, link: "https://open.spotify.com/search/" + query, artwork: item.artwork)
    }
    func lowerSlot(_ index: Int, preferences: DeskPreferences) -> MusicShortcut {
        usesSpotifyRecents(preferences) ? recentSlot(index) : (preferences.musicShortcuts ?? []).dropFirst(index).first ?? MusicShortcut()
    }
    func openLowerSlot(_ index: Int, preferences: DeskPreferences) {
        let shortcut = lowerSlot(index, preferences: preferences)
        if let url = shortcut.url { NSWorkspace.shared.open(url) }
        else if usesSpotifyRecents(preferences) {
            if let url = Self.applicationURL("com.spotify.client") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
        } else { NotificationCenter.default.post(name: .loockMusicSettings, object: nil) }
    }
    @Published private(set) var status = "Aguardando Spotify, Deezer ou Apple Music"
    private(set) var enabled = false
    private(set) var provider: MusicProvider = .automatic
    private var paused = false
    private var lastCommand = Date.distantPast
    func configure(provider: MusicProvider, enabled: Bool) {
        let changed = self.provider != provider
        self.provider = provider
        if self.enabled != enabled {
            self.enabled = enabled
            if enabled && !paused { start() } else { stop() }
        } else if changed { refreshAll() }
    }
    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        if paused { stop() } else if enabled { start() }
    }
    func openSource() {
        let bundle = provider.bundleID ?? (track.bundle.isEmpty ? "com.apple.Music" : track.bundle)
        guard let url = Self.applicationURL(bundle) else {
            status = "Abra ou instale o aplicativo de música escolhido"; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
    static func applicationURL(_ bundle: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return url }
        let paths = ["com.spotify.client": "/Applications/Spotify.app", "com.deezer.deezer-desktop": "/Applications/Deezer.app", "com.apple.Music": "/System/Applications/Music.app"]
        guard let path = paths[bundle] else { return nil }
        let url = URL(fileURLWithPath: path)
        return Bundle(url: url)?.bundleIdentifier == bundle ? url : nil
    }
    var songTitle: String { track.title }
    var artistName: String { track.artist }
    var albumName: String { track.album }
    var isPlaying: Bool { track.playing }
    var albumArtwork: NSImage? { track.artwork }

    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias PlayingFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias CommandFunction = @convention(c) (UInt32, CFDictionary?) -> Bool
    private var getPID: ((DispatchQueue, @escaping (Int32) -> Void) -> Void)?
    private var getInfo: ((DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void)?
    private var getPlaying: ((DispatchQueue, @escaping (Bool) -> Void) -> Void)?
    private var sendCommand: ((UInt32, CFDictionary?) -> Bool)?
    private var resolveBundle: (Int32) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    private var register: (@convention(c) (DispatchQueue) -> Void)?
    private var unregister: (@convention(c) () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var artworkData: Data?
    private var handle: UnsafeMutableRawPointer?

    private init() {
        historyDefaults = .standard
        if let data = historyDefaults?.data(forKey: historyKey), let saved = try? JSONDecoder().decode(SpotifyRecentHistory.self, from: data) { spotifyHistory = saved }

        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        guard let handle else { return }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") { let function = unsafeBitCast(symbol, to: PIDFunction.self); getPID = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") { let function = unsafeBitCast(symbol, to: InfoFunction.self); getInfo = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") { let function = unsafeBitCast(symbol, to: PlayingFunction.self); getPlaying = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteSendCommand") { let function = unsafeBitCast(symbol, to: CommandFunction.self); sendCommand = { function($0, $1) } }
        if let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") { register = unsafeBitCast(symbol, to: (@convention(c) (DispatchQueue) -> Void).self) }
        if let symbol = dlsym(handle, "MRMediaRemoteUnregisterForNowPlayingNotifications") { unregister = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self) }
    }

    init(api: MediaSourceAPI, defaults: UserDefaults? = nil) {
        historyDefaults = defaults
        if let data = defaults?.data(forKey: historyKey), let saved = try? JSONDecoder().decode(SpotifyRecentHistory.self, from: data) { spotifyHistory = saved }

        getPID = api.pid
        getInfo = api.info
        getPlaying = api.playing
        sendCommand = api.command
        resolveBundle = api.bundle
    }

    func start() {
        guard timer == nil, enabled, !paused else { return }
        register?(.main)
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.refreshAll() })
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.refreshAll() }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshAll()
    }

    func stop() {
        generation &+= 1
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        unregister?()
        clear()
    }

    func refreshAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        let request = generation
        guard enabled, !paused else { clear(); return }
        guard let getPID, let getInfo, let getPlaying else {
            clear(); status = "Player indisponível nesta versão do macOS"; return
        }
        getPID(.main) { [weak self] pid in
            guard let self, self.generation == request, self.enabled else { return }
            guard let bundle = self.resolveBundle(pid),
                  self.provider.accepts(bundle) else { self.clear(); return }
            getInfo(.main) { [weak self] dictionary in
                guard let self, self.generation == request, self.enabled else { return }
                let info = dictionary as? [String: Any] ?? [:]
                getPlaying(.main) { [weak self] playing in
                    guard let self, self.generation == request, self.enabled else { return }
                    // Metadata and playback callbacks can outlive a source change.
                    getPID(.main) { [weak self] verifiedPID in
                        guard let self, self.generation == request, self.enabled else { return }
                        guard verifiedPID == pid,
                              self.resolveBundle(verifiedPID) == bundle else { self.clear(); return }
                        self.apply(info: info, playing: playing, pid: pid, bundle: bundle)
                    }
                }
            }
        }
    }

    static func thumbnail(_ data: Data) -> NSImage? {
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    private func apply(info: [String: Any], playing: Bool, pid: Int32, bundle: String) {
        // Playback notifications may omit artwork or other metadata. Preserve the
        // current snapshot only while PID, source and track identity still agree.
        let sameSource = track.pid == pid && track.bundle == bundle
        let reportedTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let title = reportedTitle?.isEmpty == false ? reportedTitle! : (sameSource ? track.title : "")
        guard !title.isEmpty else { clear(); return }
        let sameTitle = sameSource && title == track.title
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? (sameTitle ? track.artist : "")
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? (sameTitle ? track.album : "")
        let identityChanged = !sameSource || track.title != title || track.artist != artist || track.album != album
        let newData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data ?? (!identityChanged ? artworkData : nil)
        let shouldPresent = identityChanged || track.playing != playing
        let image = !identityChanged && newData == artworkData ? track.artwork : newData.flatMap(Self.thumbnail)
        if shouldPresent || newData != artworkData {
            if bundle == "com.spotify.client", collectsSpotifyCovers {
                var history = spotifyHistory
                let jpeg = image?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
                history.record(album: album, artist: info["kMRMediaRemoteNowPlayingInfoAlbumArtist"] as? String ?? artist, artwork: jpeg, playing: playing)
                if history != spotifyHistory {
                    spotifyHistory = history
                    if let data = try? JSONEncoder().encode(history) { historyDefaults?.set(data, forKey: historyKey) }
                }
            }
            track = Track(title: title, artist: artist, album: album, playing: playing, artwork: image, source: MusicSourcePolicy.allowed[bundle] ?? "", pid: pid, bundle: bundle)
            artworkData = newData
        }
        status = "\(track.source) · \(playing ? "Reproduzindo" : "Pausado")"

    }

    private func clear() {
        if track.pid != 0 || !track.title.isEmpty { track = Track(); artworkData = nil }
        status = enabled ? "Aguardando Spotify, Deezer ou Apple Music" : "Player desativado"
    }

    private func command(_ command: UInt32) {
        let expected = track.pid
        guard enabled, !paused, expected > 0, Date().timeIntervalSince(lastCommand) > 0.2 else { return }
        lastCommand = Date()
        let expectedBundle = track.bundle
        getPID?(.main) { [weak self] pid in
            guard let self, self.enabled, pid == expected, self.track.pid == expected,
                  self.resolveBundle(pid) == expectedBundle, self.provider.accepts(expectedBundle) else { return }
            if self.sendCommand?(command, nil) != true { self.status = "O aplicativo não aceitou o comando" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refreshAll() }
        }
    }
    func togglePlayPause() { command(2) }
    func nextTrack() { command(4) }
    func previousTrack() { command(5) }
}
