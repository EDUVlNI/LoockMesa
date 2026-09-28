import SwiftUI
import AppKit

@main
struct LoockMesaApp: App {
    @NSApplicationDelegateAdaptor(MesaDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
@MainActor final class MesaDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = DeskStore()
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
    private var lastReveal = Date.distantPast
    private var asleep = false
    private var screenAsleep = false
    private func updateActivity() {
        let paused = asleep || screenAsleep
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
    private func revealDesktop() {
        guard Date().timeIntervalSince(lastReveal) > 2 else { return }
        lastReveal = Date()
        desktop?.animateUnlock()
    }
    func applicationWillTerminate(_ notification: Notification) {
        activityObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let musicSettingsObserver { NotificationCenter.default.removeObserver(musicSettingsObserver) }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
    }
    @objc func openGallery() {
        if gallery == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.title = "Loock Mesa"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentMinSize = NSSize(width: 850, height: 650)
            window.contentView = NSHostingView(rootView: GalleryView(store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda, finishEditing: { [weak self] in self?.hideGallery() }))
            window.center(); gallery = window
        }
        if gallery?.isMiniaturized == true { gallery?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true); gallery?.makeKeyAndOrderFront(nil)
        desktop?.setEditing(true)
    }
    @objc private func toggleWidgets() { showingWidgets.toggle(); desktop?.setVisible(showingWidgets) }
    @objc private func resetPositions() { store.resetPositions() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openGallery(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func hideGallery() { gallery?.orderOut(nil); desktop?.setEditing(false) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideGallery(); return false }
    func windowDidMiniaturize(_ notification: Notification) { desktop?.setEditing(false) }
    func windowDidDeminiaturize(_ notification: Notification) { desktop?.setEditing(true) }
    func applicationDidHide(_ notification: Notification) { desktop?.setEditing(false) }
    func applicationDidUnhide(_ notification: Notification) {
        desktop?.setEditing(gallery?.isVisible == true && gallery?.isMiniaturized == false)
    }
}
