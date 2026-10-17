import AppKit
import SwiftUI

@main struct DragChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let payload = GalleryWidgetPayload(kind: .clock, size: .large, variant: "digital")
        let restoredPayload = try! JSONDecoder().decode(GalleryWidgetPayload.self, from: JSONEncoder().encode(payload))
        precondition(restoredPayload.kind == .clock && restoredPayload.size == .large && restoredPayload.variant == "digital")
        print("PASS: gallery drag payload preserves widget, variant and size")
        for size in WidgetSize.allCases {
            let dimensions = size.dimensions
            let rect = CGRect(x: 7, y: 7, width: dimensions.width - 14, height: dimensions.height - 14)
            for index in 0..<60 {
                let mark = ClockPerimeter.mark(index: index, in: rect, corner: 16)
                precondition(mark.point.x >= rect.minX - 0.001 && mark.point.x <= rect.maxX + 0.001)
                precondition(mark.point.y >= rect.minY - 0.001 && mark.point.y <= rect.maxY + 0.001)
                precondition(abs(hypot(mark.normal.dx, mark.normal.dy) - 1) < 0.001)
            }
            precondition(abs(ClockPerimeter.mark(index: 0, in: rect, corner: 16).point.x - rect.midX) < 0.001)
            precondition(abs(ClockPerimeter.mark(index: 15, in: rect, corner: 16).point.y - rect.midY) < 0.001)
        }
        print("PASS: clock tick marks follow all P/M/G contours with a seven-point edge margin")
        let liveClock = ClockPlaybackState()
        liveClock.configure(live: true, inactive: false, lowPower: false, reduceMotion: true)
        let initialDate = liveClock.snapshot.date
        let initialAngles = liveClock.angles
        liveClock.configure(live: true, inactive: false, lowPower: false, reduceMotion: true)
        precondition(liveClock.timerStarts == 1 && liveClock.isTicking, "Repeated view updates must not restart or duplicate timers")
        RunLoop.main.run(until: Date().addingTimeInterval(1.25))
        precondition(liveClock.snapshot.date > initialDate && liveClock.angles != initialAngles, "A live clock must advance without TimelineView callbacks")
        liveClock.setSystemPaused(true)
        let sleepingDate = liveClock.snapshot.date
        precondition(!liveClock.isTicking)
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        precondition(liveClock.snapshot.date == sleepingDate, "Sleeping/hidden clocks must not wake for ticks")
        liveClock.setSystemPaused(false)
        precondition(liveClock.isTicking && liveClock.snapshot.date > sleepingDate)
        liveClock.configure(live: true, inactive: true, lowPower: false, reduceMotion: true)
        precondition(!liveClock.isTicking)
        liveClock.configure(live: true, inactive: false, lowPower: false, reduceMotion: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        precondition(liveClock.isTicking)
        liveClock.stop()
        precondition(!liveClock.isTicking)
        let previewClock = ClockPlaybackState()
        previewClock.configure(live: false, inactive: false, lowPower: false, reduceMotion: false)
        precondition(!previewClock.isTicking && previewClock.timerStarts == 0)
        print("PASS: live clock timer advances actual time, starts once, pauses for sleep/hidden/desktop focus and keeps previews static")
        let clock = ClockPlaybackState()
        clock.setInactive(true, reduceMotion: false)
        let frozen = clock.angles
        clock.tick(Date().addingTimeInterval(120))
        precondition(clock.angles == frozen, "Inactive clocks must keep their displayed hand positions")
        clock.setInactive(false, at: Date().addingTimeInterval(20), reduceMotion: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        precondition(clock.angles != frozen, "Returning must animate from the frozen positions")
        clock.setInactive(true, reduceMotion: false)
        let interrupted = clock.angles
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        precondition(clock.angles == interrupted, "Leaving again cancels the recovery without stale updates")
        let resumeDate = Date()
        clock.setInactive(false, at: resumeDate, reduceMotion: true)
        let expected = ClockHandAngles.at(resumeDate)
        precondition(abs(clock.angles.second.truncatingRemainder(dividingBy: 2 * .pi) - expected.second) < 0.00001)
        print("PASS: clock freezes, recovers, cancels recovery and respects Reduce Motion")
        let defaults = UserDefaults(suiteName: "LoockMesa.dragChecks")!
        defer { defaults.removePersistentDomain(forName: "LoockMesa.dragChecks") }
        let host = WidgetHost(rootView: WidgetFace(kind: .headphones, size: .medium,
            store: DeskStore(defaults: defaults), devices: DeviceService(),
            weather: WeatherService(preview: .demo), bluetooth: BluetoothBatteryService(automatic: false), agenda: AgendaService()))
        let galleryHost = GalleryDragHost(rootView: host.rootView, payload: payload)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        galleryHost.frame = CGRect(x: 40, y: 70, width: 344, height: 164)
        container.addSubview(galleryHost)
        galleryHost.layoutSubtreeIfNeeded()
        precondition(galleryHost.hitTest(CGPoint(x: 100, y: 100)) === galleryHost, "Gallery must capture pointer over hosted SwiftUI content")
        precondition(galleryHost.hitTest(CGPoint(x: 10, y: 10)) == nil, "Outside gallery bounds must not capture input")
        print("PASS: gallery native drag host owns preview hit target and rejects outside points")
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
        let spaceEntrance = WidgetEntranceState()
        spaceEntrance.appear(reduceMotion: true)
        spaceEntrance.finish()
        spaceEntrance.appear(reduceMotion: false)
        precondition(spaceEntrance.progress == 1, "Space reappearance must not restart the entrance")
        print("PASS: Space reappearance preserves entrance visibility")
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
        let lyricMedia = MusicService(api: MediaSourceAPI(
            pid: { _, done in done(42) },
            info: { _, done in done(["kMRMediaRemoteNowPlayingInfoTitle": "Test Song",
                "kMRMediaRemoteNowPlayingInfoArtist": "Test Artist", "kMRMediaRemoteNowPlayingInfoAlbum": "Deluxe",
                "kMRMediaRemoteNowPlayingInfoDuration": 180.0] as CFDictionary) },
            playing: { _, done in done(true) }, bundle: { _ in "com.spotify.client" }))
        let lyricConfig = URLSessionConfiguration.ephemeral
        lyricConfig.protocolClasses = [LyricsFixtureProtocol.self]
        let lyricSession = URLSession(configuration: lyricConfig)
        lyricMedia.configure(provider: .automatic, enabled: true)
        let lyricService = LyricsService(media: lyricMedia, session: lyricSession)
        lyricService.configure(enabled: true)
        let lyricDeadline = Date().addingTimeInterval(3)
        while !lyricService.document.available && Date() < lyricDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(lyricService.document.lines.first?.text == "Test lyric",
                     "An exact-match 404 must fall back to verified search lyrics")
        lyricService.configure(enabled: false)
        precondition(!lyricService.document.available && !lyricService.loading)
        lyricMedia.stop(); lyricSession.invalidateAndCancel()
        print("PASS: exact-match miss falls back to search and disable clears lyric state")
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
        let lyricsHost = WidgetHost(rootView: WidgetFace(music: music, kind: .musicLyrics, size: .medium,
            store: source.store, devices: source.devices, weather: source.weather, bluetooth: source.bluetooth, agenda: source.agenda))
        window.contentView = lyricsHost
        lyricsHost.frame = CGRect(x: 0, y: 0, width: 344, height: 164)
        lyricsHost.observeLyricsControls(); lyricsHost.layoutSubtreeIfNeeded()
        let bubble = lyricsHost.subviews.compactMap { $0 as? NSButton }.first { $0.isTransparent && $0.tag == 0 }!
        let bubblePoint = lyricsHost.convert(NSPoint(x: bubble.frame.midX, y: bubble.frame.midY), to: lyricsHost.superview)
        precondition(!bubble.isEnabled && lyricsHost.hitTest(bubblePoint) === bubble, "Missing lyrics must disable the bubble without falling through to open the player")
        bubble.performClick(nil)
        precondition(!LyricsService.shared.showingLyrics)
        let scrubSurface = lyricsHost.subviews.first { $0.accessibilityRole() == .slider }!
        precondition(!scrubSurface.isHidden)
        LyricsService.shared.showingLyrics = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        lyricsHost.layoutSubtreeIfNeeded()
        let scrubPoint = lyricsHost.convert(NSPoint(x: scrubSurface.frame.midX, y: scrubSurface.frame.midY), to: lyricsHost.superview)
        precondition(scrubSurface.isHidden && lyricsHost.hitTest(scrubPoint) !== scrubSurface,
                     "Lyric mode must hide native seek controls as well as the SwiftUI bar")
        LyricsService.shared.showingLyrics = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        lyricsHost.layoutSubtreeIfNeeded()
        precondition(!scrubSurface.isHidden)
        lyricsHost.editing = true; lyricsHost.layoutSubtreeIfNeeded()
        precondition(bubble.isHidden && lyricsHost.hitTest(bubblePoint) === lyricsHost)
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
        var seekTargets: [Double] = []
        var seekPID: Int32 = 42
        var seekTitle = "Seek fixture"
        let seeking = MusicService(api: MediaSourceAPI(
            pid: { _, done in done(seekPID) },
            info: { _, done in done(["kMRMediaRemoteNowPlayingInfoTitle": seekTitle,
                "kMRMediaRemoteNowPlayingInfoDuration": 200,
                "kMRMediaRemoteNowPlayingInfoElapsedTime": 20] as CFDictionary) },
            playing: { _, done in done(false) },
            seek: { seekTargets.append($0) },
            bundle: { $0 == 42 ? "com.spotify.client" : "com.apple.Safari" }))
        seeking.configure(provider: .automatic, enabled: true)
        precondition(seeking.canSeek)
        seeking.beginScrub(fraction: 0.4)
        seeking.updateScrub(fraction: 0.6)
        precondition(seekTargets.isEmpty && seeking.scrubPosition == 120, "Dragging previews locally without spamming the player")
        seeking.finishScrub()
        precondition(seekTargets == [120] && seeking.position.elapsed == 120 && seeking.position.rate == 0)
        seeking.beginScrub(fraction: 2); seeking.finishScrub()
        precondition(seekTargets.last == 200)
        seeking.beginScrub(fraction: 0.2)
        seekTitle = "Other track"; seeking.refreshAll(); seeking.finishScrub()
        precondition(seekTargets.count == 2 && seeking.scrubPosition == nil, "A drag from a previous track must not seek the new track")
        seekPID = 99; seeking.seek(to: 70)
        precondition(seekTargets.count == 2, "Verify source before seeking")
        seeking.stop()
        for size in WidgetSize.allCases {
            let geometry = LyricsLayout(size: size)
            precondition(!geometry.progress.intersects(geometry.control(1)))
        }
        print("PASS: scrub clamping, one command on release, pause preservation, track/source change protection")
        print("PASS: music source filtering, native playback hit targets, edit drag, stale callback cancellation")
        print("PASS: mouse-up persistence, final coordinates, duplicate release, locked and settling guards")
    }
}

private final class LyricsFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "lrclib.net" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let search = request.url!.path == "/api/search"
        let response = HTTPURLResponse(url: request.url!, statusCode: search ? 200 : 404, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let payload = search ? #"[{"trackName":"Test Song","artistName":"Test Artist","albumName":"Original","duration":181,"syncedLyrics":"[00:01.00]Test lyric"}]"# : "{}"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
