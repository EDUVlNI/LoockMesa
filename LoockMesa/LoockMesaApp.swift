import SwiftUI
import AppKit
import QuartzCore

@main
struct LoockMesaApp: App {
    @NSApplicationDelegateAdaptor(MesaDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
@MainActor final class MesaDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = DeskStore()
    private var galleryObservers: [NSObjectProtocol] = []
    private var dropPanels: [NSPanel] = []
    private var galleryGeneration = 0
    private var galleryFrame: NSRect = .zero

    private let devices = DeviceService()
    private let weather = WeatherService()
    private let bluetooth = BluetoothBatteryService()
    private let agenda = AgendaService()
    private var desktop: DesktopController?
    private var status: NSStatusItem?
    private var gallery: NSWindow?
    private var showingWidgets = true
    private var activityObservers: [NSObjectProtocol] = []
    private var unlockObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var musicSettingsObserver: NSObjectProtocol?
    private var desktopFocusTimer: Timer?
    private var lastReveal = Date.distantPast
    private var asleep = false
    private var screenAsleep = false
    private var lastClockPause: Bool?
    private func updateActivity() {
        let paused = asleep || screenAsleep || (!showingWidgets && gallery?.isVisible != true)
        let clocksPaused = asleep || screenAsleep || !showingWidgets
        if lastClockPause != clocksPaused {
            lastClockPause = clocksPaused
            NotificationCenter.default.post(name: .loockClockActivity, object: clocksPaused)
        }
        MusicService.shared.setPaused(paused)
        devices.setPaused(paused); bluetooth.setPaused(paused)
        agenda.setPaused(paused); weather.setPaused(paused)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            activityObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let eventName = note.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch eventName {
                    case NSWorkspace.willSleepNotification: self.asleep = true
                    case NSWorkspace.didWakeNotification: self.asleep = false
                    case NSWorkspace.screensDidSleepNotification: self.screenAsleep = true
                    default: self.screenAsleep = false
                    }
                    self.updateActivity()
                }
            })
        }
        desktop = DesktopController(store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda)
        refreshDesktopFocus(NSWorkspace.shared.frontmostApplication)
        activityObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in self?.refreshDesktopFocus(app) }
        })
        // Window metadata only: no screenshots, Accessibility or window titles.
        desktopFocusTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.asleep, !self.screenAsleep, self.showingWidgets,
                      self.store.preferences.frostedOutsideDesktop == true else { return }
                self.refreshDesktopFocus(NSWorkspace.shared.frontmostApplication)
            }
        }
        desktopFocusTimer?.tolerance = 0.25
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            activityObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshDesktopFocus(NSWorkspace.shared.frontmostApplication) }
            })
        }
        musicSettingsObserver = NotificationCenter.default.addObserver(forName: .loockMusicSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openGallery()
                DispatchQueue.main.async { NotificationCenter.default.post(name: .loockSelectMusic, object: nil) }
            }
        }
        desktop?.showSettings = { [weak self] in self?.openGallery() }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Loock Mesa")
        let menu = NSMenu()
        menu.addItem(withTitle: "Personalizar widgets…", action: #selector(openGallery), keyEquivalent: "")
        menu.addItem(withTitle: "Mostrar/ocultar widgets", action: #selector(toggleWidgets), keyEquivalent: "")
        menu.addItem(withTitle: "Reorganizar posições", action: #selector(resetPositions), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Encerrar Loock Mesa", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; status.menu = menu; self.status = status
        NotificationCenter.default.addObserver(self, selector: #selector(galleryDragStarted(_:)), name: .loockGalleryDragStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(galleryDropReceived(_:)), name: .loockGalleryDrop, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(galleryDragEnded(_:)), name: .loockGalleryDragEnded, object: nil)
        // Login launches should leave the desktop unobstructed.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !loginLaunch { openGallery() }
        // Best-effort notification observed on Ventura; not a public authentication API.
        // Never drives authentication or treats the event as a security guarantee.
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastReveal = .distantPast
                self?.desktop?.prepareUnlock()
            }
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.revealDesktop() }
        }
        activityObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.revealDesktop() }
        })
    }
    private func refreshDesktopFocus(_ app: NSRunningApplication?) {
        guard let app else { desktop?.setDesktopActive(true); return }
        if app.bundleIdentifier == "com.apple.finder" || app.bundleIdentifier == Bundle.main.bundleIdentifier {
            desktop?.setDesktopActive(true); return
        }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = raw.compactMap { entry -> DesktopFocusWindow? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return DesktopFocusWindow(ownerPID: pid.int32Value, layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                      alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1, bounds: rect)
        }
        let screens = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        desktop?.setDesktopActive(DesktopFocusPolicy.isDesktop(frontmostID: app.bundleIdentifier,
            ownID: Bundle.main.bundleIdentifier, frontmostPID: app.processIdentifier, windows: windows, screens: screens))
    }
    private func revealDesktop() {
        guard Date().timeIntervalSince(lastReveal) > 2 else { return }
        lastReveal = Date()
        desktop?.animateUnlock()
    }
    func applicationWillTerminate(_ notification: Notification) {
        desktopFocusTimer?.invalidate()
        galleryObservers.forEach { NotificationCenter.default.removeObserver($0) }
        dropPanels.forEach { $0.close() }
        activityObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let musicSettingsObserver { NotificationCenter.default.removeObserver(musicSettingsObserver) }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
    }
    @objc func openGallery() {
        if gallery == nil {
            let window = GalleryPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.hidesOnDeactivate = false; window.animationBehavior = .none
            window.title = "Loock Mesa"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = makeGalleryContent()
            gallery = window
        }
        guard let gallery, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        galleryGeneration += 1
        gallery.contentView?.layer?.removeAllAnimations()
        if gallery.contentView == nil { gallery.contentView = makeGalleryContent() }
        NSApp.unhide(nil)
        let bounds = screen.visibleFrame
        let width = min(1100, bounds.width - 32); let height = min(620, bounds.height * 0.78)
        galleryFrame = NSRect(x: bounds.midX - width / 2, y: bounds.minY + 12, width: width, height: height)
        let appearing = !gallery.isVisible
        gallery.setFrame(galleryFrame, display: false)
        gallery.alphaValue = appearing ? 0 : 1
        NSApp.activate(ignoringOtherApps: true); gallery.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            gallery.animator().alphaValue = 1
        }
        desktop?.setEditing(true)
        updateActivity()
    }
    // Native drag notifications are posted synchronously by AppKit on the main thread.
    @objc private func galleryDragStarted(_ note: Notification) { beginGalleryDrag() }
    @objc private func galleryDropReceived(_ note: Notification) {
        guard let payload = note.object as? GalleryWidgetPayload, let point = note.userInfo?["point"] as? CGPoint else { return }
        desktop?.placeFromGallery(payload, at: point)
    }
    @objc private func galleryDragEnded(_ note: Notification) { endGalleryDrag() }
    private func beginGalleryDrag() {
        galleryGeneration += 1
        gallery?.orderOut(nil)
        dropPanels.forEach { $0.close() }; dropPanels.removeAll()
    }
    private func endGalleryDrag() {
        dropPanels.forEach { $0.orderOut(nil); $0.close() }; dropPanels.removeAll()
        openGallery()
    }
    @objc private func toggleWidgets() { showingWidgets.toggle(); desktop?.setVisible(showingWidgets); updateActivity() }
    @objc private func resetPositions() { store.resetPositions() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openGallery(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func hideGallery() {
        guard let gallery else { return }
        galleryGeneration += 1
        desktop?.setEditing(false)
        gallery.orderOut(nil)
        gallery.alphaValue = 1
        // Release previews and their observers while the panel is closed.
        gallery.contentView = nil
        updateActivity()
    }
    private func makeGalleryContent() -> NSView {
        NSHostingView(rootView: GalleryView(store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda, finishEditing: { [weak self] in self?.hideGallery() }))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hideGallery(); return false }
    func windowDidMiniaturize(_ notification: Notification) { desktop?.setEditing(false) }
    func windowDidDeminiaturize(_ notification: Notification) { desktop?.setEditing(true) }
    func applicationDidHide(_ notification: Notification) { desktop?.setEditing(false) }
    func applicationDidUnhide(_ notification: Notification) {
        desktop?.setEditing(gallery?.isVisible == true && gallery?.isMiniaturized == false)
    }
}
