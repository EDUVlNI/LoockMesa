import AppKit
import Combine

extension Notification.Name {
    static let gergelimPlayerSettingsChanged = Notification.Name("Gergelim.playerSettingsChanged")
}

/// Eko's floating player uses the same playback source and commands as desktop widgets.
final class MediaRemoteWrapper: ObservableObject {
    static let shared = MediaRemoteWrapper()
    @Published private(set) var track = MusicService.Track()
    @Published private(set) var status = "Aguardando Spotify, Deezer ou Apple Music"
    @Published var floatingPlayerEnabled = (UserDefaults.standard.object(forKey: "FloatingPlayerEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(floatingPlayerEnabled, forKey: "FloatingPlayerEnabled"); settingsChanged() }
    }
    @Published var enabled = (UserDefaults.standard.object(forKey: "PlayerEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "PlayerEnabled"); settingsChanged() }
    }
    var wantsPlayback: Bool { enabled && floatingPlayerEnabled }
    var songTitle: String { track.title }
    var artistName: String { track.artist }
    var albumName: String { track.album }
    var isPlaying: Bool { track.playing }
    var albumArtwork: NSImage? { track.artwork }
    private var subscriptions = Set<AnyCancellable>()
    private func settingsChanged() {
        if !wantsPlayback { HUDManager.shared.hideNowPlaying() }
        NotificationCenter.default.post(name: .gergelimPlayerSettingsChanged, object: nil)
    }
    func start() {
        guard subscriptions.isEmpty else { return }
        MusicService.shared.$track.receive(on: RunLoop.main).sink { [weak self] next in
            guard let self else { return }
            let changed = self.track.identity != next.identity || self.track.playing != next.playing
            self.track = next
            if next.title.isEmpty { HUDManager.shared.hideNowPlaying() }
            else if changed && self.wantsPlayback { HUDManager.shared.showNowPlaying() }
        }.store(in: &subscriptions)
        MusicService.shared.$status.receive(on: RunLoop.main).sink { [weak self] in self?.status = $0 }.store(in: &subscriptions)
    }
    func stop() { subscriptions.removeAll(); HUDManager.shared.hideNowPlaying() }
    func togglePlayPause() { MusicService.shared.togglePlayPause() }
    func nextTrack() { MusicService.shared.nextTrack() }
    func previousTrack() { MusicService.shared.previousTrack() }
}
