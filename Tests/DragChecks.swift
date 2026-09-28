import AppKit
import SwiftUI

@main struct DragChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "LoockMesa.dragChecks")!
        defer { defaults.removePersistentDomain(forName: "LoockMesa.dragChecks") }
        let host = WidgetHost(rootView: WidgetFace(kind: .headphones, size: .medium,
            store: DeskStore(defaults: defaults), devices: DeviceService(),
            weather: WeatherService(preview: .demo), bluetooth: BluetoothBatteryService(automatic: false), agenda: AgendaService()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 344, height: 164), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        var starts = 0
        var commits: [CGPoint] = []
        host.dragStarted = { starts += 1 }
        host.dragEnded = { commits.append(window.frame.origin) }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        host.mouseDown(with: event(.leftMouseDown))
        precondition(starts == 0 && commits.isEmpty, "Mouse-down alone must not drag")
        let cursor = NSEvent.mouseLocation
        host.moveDrag(to: CGPoint(x: cursor.x + 20, y: cursor.y + 20))
        precondition(starts == 1 && commits.isEmpty)
        window.setFrameOrigin(CGPoint(x: 300, y: 400))
        host.mouseUp(with: event(.leftMouseUp))
        precondition(commits == [CGPoint(x: 300, y: 400)], "Save final position on mouse-up")
        host.mouseUp(with: event(.leftMouseUp))
        precondition(commits.count == 1, "No duplicate commit")
        host.movementLocked = true
        host.mouseDown(with: event(.leftMouseDown)); host.mouseUp(with: event(.leftMouseUp))
        host.movementLocked = false; host.settling = true
        host.mouseDown(with: event(.leftMouseDown)); host.mouseUp(with: event(.leftMouseUp))
        precondition(starts == 1 && commits.count == 1, "Locked/animating widgets must not start a drag")
        host.settling = false
        var opened = 0
        host.openApp = { opened += 1 }
        host.mouseDown(with: event(.leftMouseDown)); host.mouseUp(with: event(.leftMouseUp))
        precondition(opened == 1)
        host.editing = true
        host.mouseDown(with: event(.leftMouseDown)); host.mouseUp(with: event(.leftMouseUp))
        precondition(opened == 1, "Edit clicks must not open apps")
        host.editing = false
        host.rootView.store.preferences.opensAppsOnClick = false
        host.mouseDown(with: event(.leftMouseDown)); host.mouseUp(with: event(.leftMouseUp))
        precondition(opened == 1, "Disabled opening must not launch apps")
        host.mouseDown(with: event(.leftMouseDown))
        let nextCursor = NSEvent.mouseLocation
        host.moveDrag(to: CGPoint(x: nextCursor.x + 25, y: nextCursor.y))
        host.mouseUp(with: event(.leftMouseUp))
        precondition(commits.count == 2, "Disabling app launch must preserve dragging")
        var removed = false
        host.removeWidget = { removed = true }
        host.editing = true
        host.layoutSubtreeIfNeeded()
        let removeButton = host.subviews.compactMap { $0 as? NSButton }.first!
        precondition(!removeButton.isHidden)
        precondition(host.acceptsFirstMouse(for: nil))
        precondition(host.hitTest(host.convert(NSPoint(x: removeButton.frame.midX, y: removeButton.frame.midY), to: host.superview)) === removeButton, "Remove badge must receive the pointer")
        removeButton.performClick(nil)
        precondition(removed)
        host.editing = false
        precondition(removeButton.isHidden)
        let remindersHost = WidgetHost(rootView: WidgetFace(kind: .reminders, size: .small,
            store: host.rootView.store, devices: host.rootView.devices, weather: host.rootView.weather,
            bluetooth: host.rootView.bluetooth, agenda: host.rootView.agenda))
        window.contentView = remindersHost
        remindersHost.frame = CGRect(x: 0, y: 0, width: 164, height: 164)
        for frosted in [true, false] {
            remindersHost.rootView.store.preferences.unifiedFrost = frosted
            let point = remindersHost.convert(NSPoint(x: 80, y: 80), to: remindersHost.superview)
            precondition(remindersHost.hitTest(point) === remindersHost, "Reminders content must route pointer to drag host")
        }
        let guide = DesktopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        guide.coversWholeScreen = true
        if let screen = NSScreen.main { precondition(guide.constrainFrameRect(screen.frame, to: screen) == screen.frame) }
        let entrance = WidgetEntranceState()
        entrance.prepareUnlock()
        precondition(entrance.prepared && entrance.progress == 0)
        entrance.play(unlock: true, delay: 0.05, reduceMotion: false)
        entrance.withdraw(reduceMotion: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(entrance.progress == 0, "Cancelled entrance must not resurrect removed widgets")
        entrance.prepareUnlock()
        entrance.play(unlock: true, reduceMotion: true)
        precondition(entrance.progress == 1 && !entrance.prepared, "Reduce Motion restores visibility immediately")
        entrance.play(unlock: true, delay: 0.05, reduceMotion: false)
        entrance.finish()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(entrance.progress == 1, "Finishing must cancel pending entrance")
        print("PASS: entrance cancellation, prepared state, Reduce Motion and visibility recovery")
        let source = host.rootView
        let controller = DesktopController(store: source.store, devices: source.devices, weather: source.weather, bluetooth: source.bluetooth, agenda: source.agenda)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let saved = source.store.preferences
        let revealed = controller.animateUnlock()
        precondition(source.store.preferences == saved, "Unlock reveal must not modify saved positions or preferences")
        if NSScreen.screens.isEmpty {
            print("SKIP: visible desktop reveal requires a GUI screen; NSScreen.screens is empty")
        } else {
            precondition(revealed > 0, "Visible desktop cards receive unlock reveal")
        }
        controller.setEditing(true)
        precondition(controller.animateUnlock() == 0, "Editing must suppress unlock reveal")
        controller.setEditing(false)
        controller.setVisible(false)
        precondition(controller.animateUnlock() == 0, "Hidden cards must remain hidden without replay")
        print("PASS: unlock reveal preserves layout, suppresses editing/hidden cards")
        var activePID: Int32 = 42
        var commands: [UInt32] = []
        let music = MusicService(api: MediaSourceAPI(
            pid: { _, done in done(activePID) },
            info: { _, done in done(["kMRMediaRemoteNowPlayingInfoTitle": "Faixa de teste", "kMRMediaRemoteNowPlayingInfoArtist": "Artista"] as CFDictionary) },
            playing: { _, done in done(true) },
            command: { value, _ in commands.append(value); return true },
            bundle: { $0 == 42 ? "com.spotify.client" : "com.apple.Safari" }))
        music.configure(provider: .automatic, enabled: true)
        precondition(music.track.title == "Faixa de teste" && music.track.source == "Spotify")
        let musicHost = WidgetHost(rootView: WidgetFace(music: music, kind: .music, size: .medium,
            store: source.store, devices: source.devices, weather: source.weather, bluetooth: source.bluetooth, agenda: source.agenda))
        window.contentView = musicHost
        musicHost.frame = CGRect(x: 0, y: 0, width: 344, height: 164)
        musicHost.layoutSubtreeIfNeeded()
        let playButton = musicHost.subviews.compactMap { $0 as? NSButton }.first { $0.isTransparent && $0.tag == 0 }!
        let controlPoint = musicHost.convert(NSPoint(x: playButton.frame.midX, y: playButton.frame.midY), to: musicHost.superview)
        precondition(musicHost.hitTest(controlPoint) === playButton, "Music controls must receive desktop clicks")
        playButton.performClick(nil)
        precondition(commands == [2], "Play/pause must target media service once")
        musicHost.editing = true; musicHost.layoutSubtreeIfNeeded()
        precondition(playButton.isHidden && musicHost.hitTest(controlPoint) === musicHost, "Editing preserves dragging instead of playback")
        music.configure(provider: .deezer, enabled: true)
        precondition(music.track.title.isEmpty, "Selected source must filter unrelated playback")
        activePID = 99
        music.refreshAll()
        precondition(music.track.pid == 0, "Unsupported apps must not populate the widget")
        music.stop()
        var pendingInfo: ((CFDictionary?) -> Void)?
        let delayed = MusicService(api: MediaSourceAPI(pid: { _, done in done(42) }, info: { _, done in pendingInfo = done }, playing: { _, done in done(true) }, bundle: { _ in "com.apple.Music" }))
        delayed.configure(provider: .automatic, enabled: true)
        delayed.configure(provider: .automatic, enabled: false)
        pendingInfo?(["kMRMediaRemoteNowPlayingInfoTitle": "Stale"] as CFDictionary)
        precondition(delayed.track.title.isEmpty, "Late metadata must not revive a disabled widget")
        let fixture = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }.tiffRepresentation!
        var snapshot: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "First", "kMRMediaRemoteNowPlayingInfoArtist": "Artist", "kMRMediaRemoteNowPlayingInfoAlbum": "Album", "kMRMediaRemoteNowPlayingInfoArtworkData": fixture]
        var playing = true
        let stable = MusicService(api: MediaSourceAPI(pid: { _, done in done(42) }, info: { _, done in done(snapshot as CFDictionary) }, playing: { _, done in done(playing) }, bundle: { _ in "com.spotify.client" }))
        stable.configure(provider: .automatic, enabled: true)
        let originalArtwork = stable.albumArtwork
        let originalIdentity = stable.track.identity
        precondition(originalArtwork != nil && stable.spotifyHistory.albums.count == 1)
        snapshot = [:]; playing = false
        stable.refreshAll()
        precondition(stable.albumArtwork === originalArtwork && stable.track.identity == originalIdentity && !stable.isPlaying, "Pause without metadata must preserve the same image and identity")
        playing = true; stable.refreshAll()
        precondition(stable.albumArtwork === originalArtwork && stable.spotifyHistory.albums.count == 1)
        snapshot = ["kMRMediaRemoteNowPlayingInfoTitle": "Second", "kMRMediaRemoteNowPlayingInfoAlbum": "Other"]
        stable.refreshAll()
        precondition(stable.albumArtwork == nil && stable.track.identity != originalIdentity, "A different track must not inherit the old cover")
        precondition(stable.spotifyHistory.albums.count == 2)
        stable.clearSpotifyHistory(); precondition(stable.spotifyHistory.albums.isEmpty)
        stable.stop()
        print("PASS: pause/resume keeps artwork identity, new tracks clear stale art, Spotify recents populate")
        print("PASS: music source filtering, native playback hit targets, edit drag, stale callback cancellation")
        print("PASS: mouse-up persistence, final coordinates, duplicate release, locked and settling guards")
    }
}
