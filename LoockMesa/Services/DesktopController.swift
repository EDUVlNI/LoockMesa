import AppKit
import SwiftUI
import Combine
import QuartzCore

final class DesktopPanel: NSPanel {
    var coversWholeScreen = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        coversWholeScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class MenuAction: NSObject {
    let invoke: () -> Void
    init(_ invoke: @escaping () -> Void) { self.invoke = invoke }
    @objc func run() { invoke() }
}
private final class EditRemoveButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class WidgetHost: NSHostingView<WidgetFace> {
    var dragStarted: (() -> Void)?
    var dragMoved: (() -> Void)?
    var openApp: (() -> Void)?
    private lazy var musicButtons: [NSButton] = (0..<6).map { index in
        let button = EditRemoveButton(title: "", target: self, action: #selector(musicControl(_:)))
        button.tag = index; button.isTransparent = true; button.isBordered = false
        button.setAccessibilityLabel(index == 0 ? "Reproduzir ou pausar" : index == 1 ? "Abrir player" : "Atalho de música \(index - 1)")
        addSubview(button)
        return button
    }
    @objc private func musicControl(_ sender: NSButton) {
        guard rootView.kind == .music, !editing else { return }
        if sender.tag == 0 { rootView.music.togglePlayPause() }
        else if sender.tag == 1 { rootView.music.openSource() }
        else {
            rootView.music.openLowerSlot(sender.tag - 2, preferences: rootView.store.preferences)
        }
    }
    private var didDrag = false
    var dragEnded: (() -> Void)?
    private lazy var removeButton: NSButton = {
        let button = EditRemoveButton(title: "−", target: self, action: #selector(removeFromDesktop))
        button.isBordered = false
        button.font = .systemFont(ofSize: 17, weight: .medium)
        button.contentTintColor = .darkGray
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.lightGray.cgColor
        button.layer?.cornerRadius = 10
        button.setAccessibilityLabel("Remover widget da Mesa")
        button.toolTip = "Remover da Mesa"
        button.isHidden = true
        addSubview(button)
        return button
    }()
    var editing = false { didSet { removeButton.isHidden = !editing; needsLayout = true; updateWiggle() } }
    private func updateWiggle() {
        wantsLayer = true
        let active = editing && !movementLocked && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !active { layer?.removeAnimation(forKey: "editWiggle"); return }
        guard layer?.animation(forKey: "editWiggle") == nil else { return }
        guard let layer else { return }
        // AppKit can create hosting layers with a corner anchor. Preserve the frame
        // while moving the animation pivot to the visual center of the card.
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let oldFrame = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.frame = oldFrame
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, 0.0055, 0, -0.0055, 0]
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        animation.calculationMode = .linear
        animation.duration = 0.84 + Double(rootView.kind.rawValue.count % 3) * 0.04
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "editWiggle")
    }
    @objc private func removeFromDesktop() { removeWidget?() }
    override func layout() {
        super.layout()
        let geometry = MusicLayout(size: rootView.size)
        if rootView.kind == .music {
        for (index, button) in musicButtons.enumerated() {
            button.isHidden = rootView.kind != .music || editing || (index >= 2 && rootView.size == .small)
            var rect = index == 0 ? geometry.play : index == 1 ? geometry.source : geometry.shortcut(index - 2)
            if !isFlipped { rect.origin.y = bounds.height - rect.maxY }
            button.frame = rect
        }
        }
        removeButton.frame = CGRect(x: 0, y: isFlipped ? 0 : bounds.height - 20, width: 20, height: 20)
    }
    var settling = false
    private var dragAnchor: CGPoint?
    private var windowAnchor: CGPoint?
    var resizeWidget: ((WidgetSize) -> Void)?
    var removeWidget: (() -> Void)?
    var configure: (() -> Void)?
    var movementLocked = false { didSet { updateWiggle() } }
    private var menuActions: [MenuAction] = []
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !removeButton.isHidden && removeButton.frame.contains(local) { return removeButton }
        if rootView.kind == .music && !editing,
           let control = musicButtons.first(where: { !$0.isHidden && $0.frame.contains(local) }) { return control }
        // Desktop faces are read-only outside explicit music controls. Native material/SwiftUI descendants must
        // not consume the drag; only the explicit remove control is interactive.
        return bounds.contains(local) ? self : nil
    }
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {
        guard !settling, let window else { return }
        dragAnchor = NSEvent.mouseLocation; windowAnchor = window.frame.origin
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) { moveDrag(to: NSEvent.mouseLocation) }
    func moveDrag(to now: CGPoint) {
        guard !movementLocked, let start = dragAnchor, let origin = windowAnchor else { return }
        guard didDrag || hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        if !didDrag { didDrag = true; dragStarted?() }
        window?.setFrameOrigin(CGPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
        dragMoved?()
    }
    override func mouseUp(with event: NSEvent) {
        guard dragAnchor != nil else { return }
        dragAnchor = nil; windowAnchor = nil
        if didDrag { dragEnded?() }
        else if !editing && rootView.store.preferences.opensAppsOnClick != false { openApp?() }
        didDrag = false
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(); menu.autoenablesItems = false; menuActions.removeAll()
        func add(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
            let target = MenuAction(action); menuActions.append(target)
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = target; item.state = checked ? .on : .off; menu.addItem(item)
        }
        for size in WidgetSize.allCases {
            add("Tamanho \(size.rawValue)", checked: rootView.size == size) { [weak self] in self?.resizeWidget?(size) }
        }
        menu.addItem(.separator())
        for style in WidgetAppearance.allCases {
            add(style.rawValue, checked: rootView.store.preferences.appearanceStyle(rootView.kind) == style && rootView.store.preferences.surfaceStyle(rootView.kind) == .original) { [weak self] in
                guard let self else { return }
                var value = self.rootView.store.preferences
                var colors = value.individualAppearance ?? [:]; colors[self.rootView.kind.rawValue] = style; value.individualAppearance = colors
                var surfaces = value.individualSurface ?? [:]; surfaces[self.rootView.kind.rawValue] = .original; value.individualSurface = surfaces
                self.rootView.store.preferences = value
            }
        }
        add("Fosco", checked: rootView.store.preferences.surfaceStyle(rootView.kind) == .frosted) { [weak self] in
            guard let self else { return }
            var value = self.rootView.store.preferences
            var surfaces = value.individualSurface ?? [:]; surfaces[self.rootView.kind.rawValue] = .frosted; value.individualSurface = surfaces
            self.rootView.store.preferences = value
        }
        menu.addItem(.separator())
        add("Personalizar widgets…") { [weak self] in self?.configure?() }
        add("Remover da Mesa") { [weak self] in self?.removeWidget?() }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
@MainActor final class DesktopController {
    let store: DeskStore
    let devices: DeviceService
    let weather: WeatherService
    let bluetooth: BluetoothBatteryService
    let agenda: AgendaService
    var showSettings: (() -> Void)?
    private var panels: [WidgetKind: DesktopPanel] = [:]
    private var guides: [DesktopPanel] = []
    private var guidesVisible = false
    private var guideGeneration = 0
    private var guideFade: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var isVisible = true
    private var editing = false
    private var desktopActive = true
    private var changedKind: WidgetKind?
    private var reconciling = false
    private var dragging = false
    private var dragKind: WidgetKind?
    private var dragBase: [WidgetItem] = []
    private var dragLayout: [WidgetKind: CGRect] = [:]
    private var lastDragCell: CGRect?
    private var targets: [WidgetKind: CGRect] = [:]
    init(store: DeskStore, devices: DeviceService, weather: WeatherService, bluetooth: BluetoothBatteryService, agenda: AgendaService) {
        self.store = store; self.devices = devices; self.weather = weather; self.bluetooth = bluetooth; self.agenda = agenda
        subscription = store.$preferences.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildGuides(); self?.reconcile() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restoreAfterSpaceChange() }
        }
        reconcile()
    }
    deinit {
        guideFade?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }
    /// Reorder existing desktop panels without recreating views or replaying entrance effects.
    func restoreAfterSpaceChange() {
        guard isVisible else { return }
        finishEntrances()
        panels.values.forEach { $0.orderFrontRegardless() }
        updateGuides()
    }
    /// Prepare under the native lock screen instead of visibly resetting at unlock.
    func prepareUnlock() {
        guard isVisible, !editing, !dragging else { return }
        for panel in panels.values {
            (panel.contentView as? WidgetHost)?.rootView.entrance.prepareUnlock()
        }
    }
    private func finishEntrances() {
        panels.values.forEach { ($0.contentView as? WidgetHost)?.rootView.entrance.finish() }
    }
    /// Reuses every existing host/material; never recreates SwiftUI roots at unlock.
    @discardableResult func animateUnlock() -> Int {
        guard isVisible, !editing, !dragging else { finishEntrances(); return 0 }
        let ordered = panels.values.filter(\.isVisible).sorted {
            if abs($0.frame.maxY - $1.frame.maxY) > 1 { return $0.frame.maxY > $1.frame.maxY }
            return $0.frame.minX < $1.frame.minX
        }
        var count = 0
        for (index, panel) in ordered.enumerated() {
            guard let host = panel.contentView as? WidgetHost else { continue }
            host.rootView.entrance.play(unlock: true, delay: 0.04 + Double(index) * 0.045,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            count += 1
        }
        return count
    }
    func setVisible(_ visible: Bool) { finishEntrances(); isVisible = visible; reconcile() }
    func setEditing(_ enabled: Bool) { finishEntrances(); editing = enabled; panels.values.forEach { ($0.contentView as? WidgetHost)?.editing = enabled }; updateGuides() }
    func setDesktopActive(_ active: Bool) {
        guard desktopActive != active else { return }
        desktopActive = active
        for panel in panels.values {
            guard let host = panel.contentView as? WidgetHost else { continue }
            var face = host.rootView
            face.desktopInactive = !active
            host.rootView = face
        }
    }
    private func rebuildGuides() {
        guideFade?.cancel()
        guideGeneration += 1
        guides.forEach { $0.orderOut(nil) }; guides.removeAll(); guidesVisible = false
        updateGuides()
    }
    private func updateGuides() {
        let show = editing && isVisible && !store.preferences.positionsLocked
        guard show else {
            guard guidesVisible else { return }
            guidesVisible = false; guideGeneration += 1
            fadeGuides(to: 0)
            return
        }
        if guides.count != NSScreen.screens.count {
            guideGeneration += 1
            guides.forEach { $0.orderOut(nil) }; guides.removeAll(); guidesVisible = false
            for _ in NSScreen.screens {
                let panel = DesktopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.coversWholeScreen = true
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                let view = DesktopGuideView(frame: .zero)
                view.autoresizingMask = [.width, .height]
                panel.contentView = view
                panel.alphaValue = 0
                guides.append(panel)
            }
        }
        for (panel, screen) in zip(guides, NSScreen.screens) {
            panel.setFrame(screen.frame, display: true)
            if let view = panel.contentView as? DesktopGuideView {
                view.frame = CGRect(origin: .zero, size: screen.frame.size)
                view.topInset = screen.frame.maxY - screen.visibleFrame.maxY
                view.leftInset = screen.visibleFrame.minX - screen.frame.minX
                view.needsDisplay = true
            }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        guard !guidesVisible else { return }
        guidesVisible = true; guideGeneration += 1
        guides.forEach { $0.contentView?.displayIfNeeded() }
        fadeGuides(to: 1)
    }
    private func fadeGuides(to target: CGFloat) {
        guideFade?.cancel()
        let generation = guideGeneration
        let panels = guides
        let starts = panels.map(\.alphaValue)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32
        guideFade = Task { @MainActor [weak self] in
            let start = Date()
            while let self, !Task.isCancelled, self.guideGeneration == generation {
                let fraction = duration == 0 ? 1 : min(1, Date().timeIntervalSince(start) / duration)
                let progress = CGFloat(fraction * fraction * (3 - 2 * fraction))
                for (panel, alpha) in zip(panels, starts) { panel.alphaValue = alpha + (target - alpha) * progress }
                if fraction >= 1 {
                    if target == 0 { panels.forEach { $0.orderOut(nil) } }
                    self.guideFade = nil
                    return
                }
                do { try await Task.sleep(nanoseconds: 16_666_667) } catch { return }
            }
        }
    }
    func reconcile() {
        guard !reconciling, !dragging else { return }
        reconciling = true; defer { reconciling = false }
        MusicService.shared.collectsSpotifyCovers = store.preferences.automaticSpotifyCovers != false
        MusicService.shared.configure(provider: store.preferences.musicProvider ?? .automatic, enabled: isVisible && store.item(.music).enabled)
        weather.configure(city: store.preferences.city, live: store.preferences.liveWeather)
        updateGuides()
        guard isVisible else { panels.values.forEach { ($0.contentView as? WidgetHost)?.editing = false; $0.orderOut(nil) }; return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let main = NSScreen.main?.visibleFrame ?? screens.first else { return }
        let enabled = store.preferences.widgets.filter(\.enabled)
        // Place unchanged widgets first so moving/resizing one never displaces the rest.
        var changing = Set<WidgetKind>()
        for item in enabled {
            let previousSize = targets[item.kind]?.size
            if changedKind == item.kind || previousSize != item.size.dimensions { changing.insert(item.kind) }
        }
        let sorted = enabled.sorted { a, b in
            let ca = changing.contains(a.kind), cb = changing.contains(b.kind)
            if ca != cb { return !ca }
            return store.preferences.widgets.firstIndex(where: { $0.kind == a.kind })! < store.preferences.widgets.firstIndex(where: { $0.kind == b.kind })!
        }
        let requests = sorted.enumerated().map { index, item in
            PlacementRequest(kind: item.kind, size: item.size.dimensions,
                preferred: CGRect(x: item.x ?? main.minX + DesktopGrid.inset + CGFloat(index) * DesktopGrid.pitch,
                                  y: (item.y ?? main.maxY - DesktopGrid.inset) - item.size.dimensions.height,
                                  width: item.size.dimensions.width, height: item.size.dimensions.height))
        }
        let layout = DesktopGrid.arrange(requests, screens: screens)
        changedKind = nil
        let missing = enabled.filter { layout[$0.kind] == nil }.map(\.kind.title)
        let notice = missing.isEmpty ? "" : "Sem espaço para \(missing.joined(separator: ", ")). Diminua um tamanho ou remova outro widget."
        if store.layoutMessage != notice { store.layoutMessage = notice }
        var preferences = store.preferences
        for (index, item) in preferences.widgets.enumerated() {
            guard item.enabled, let frame = layout[item.kind] else {
                if let old = panels.removeValue(forKey: item.kind) {
                    if let oldHost = old.contentView as? WidgetHost, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        oldHost.editing = false
                        var closingFace = oldHost.rootView; closingFace.withdrawing = true; oldHost.rootView = closingFace
                        old.ignoresMouseEvents = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { old.orderOut(nil); old.close() }
                    } else { old.orderOut(nil); old.close() }
                }
                targets.removeValue(forKey: item.kind)
                continue
            }
            let panel: DesktopPanel
            let host: WidgetHost
            let isNew = panels[item.kind] == nil
            if let existing = panels[item.kind], let existingHost = existing.contentView as? WidgetHost {
                panel = existing; host = existingHost
                if host.rootView.size != item.size { host.rootView = face(item) }
            } else {
                panel = DesktopPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
                panel.animationBehavior = .none
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                panel.isExcludedFromWindowsMenu = true
                host = WidgetHost(rootView: face(item)); panel.contentView = host
                host.openApp = { openWidgetApp(item.kind) }
                host.dragStarted = { [weak self] in
                    guard let self else { return }
                    self.finishEntrances()
                    self.dragging = true; self.dragKind = item.kind
                    self.dragBase = self.store.preferences.widgets.filter(\.enabled)
                    self.lastDragCell = nil; self.dragLayout = [:]
                }
                host.dragMoved = { [weak self] in self?.previewPush() }
                host.dragEnded = { [weak self] in
                    guard let self else { return }
                    self.previewPush()
                    self.dragging = false
                    var value = self.store.preferences
                    for i in value.widgets.indices {
                        if let frame = self.dragLayout[value.widgets[i].kind] {
                            value.widgets[i].x = frame.minX; value.widgets[i].y = frame.maxY
                        }
                    }
                    self.dragKind = nil; self.dragBase = []; self.lastDragCell = nil
                    self.store.preferences = value
                    self.reconcile()
                }
                host.resizeWidget = { [weak self] size in
                    self?.changedKind = item.kind
                    self?.store.update(item.kind) { $0.size = size }
                }
                host.removeWidget = { [weak self] in self?.store.update(item.kind) { $0.enabled = false } }
                host.configure = { [weak self] in self?.showSettings?() }
                panels[item.kind] = panel
            }
            host.editing = editing && !preferences.positionsLocked
            host.movementLocked = preferences.positionsLocked
            let appearing = !panel.isVisible
            let targetChanged = targets[item.kind] != frame || panel.frame != frame
            targets[item.kind] = frame
            // Persist the intended destination below, never an in-flight frame.
            if appearing || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.setFrame(frame, display: true)
            } else if targetChanged, !host.settling {
                host.settling = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(frame, display: true)
                } completionHandler: { [weak self, weak host] in
                    host?.settling = false
                    Task { @MainActor [weak self] in self?.reconcile() }
                }
            }
            if appearing {
                // A window temporarily omitted by Spaces is not a newly added widget.
                if !isNew { host.rootView.entrance.finish() }
                panel.orderFrontRegardless()
            }
            preferences.widgets[index].x = frame.minX; preferences.widgets[index].y = frame.maxY
        }
        // Equality guard prevents a persistence/reconcile feedback loop.
        if preferences != store.preferences { store.preferences = preferences }
    }
    func placeFromGallery(_ payload: GalleryWidgetPayload, at point: CGPoint) {
        let size = payload.size.dimensions
        let frame = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        var requests = [PlacementRequest(kind: payload.kind, size: size, preferred: frame)]
        for item in store.preferences.widgets where item.enabled && item.kind != payload.kind {
            if let existing = targets[item.kind] { requests.append(PlacementRequest(kind: item.kind, size: item.size.dimensions, preferred: existing)) }
        }
        let frames = DesktopGrid.arrange(requests, screens: NSScreen.screens.map(\.visibleFrame))
        guard frames.count == requests.count else { store.layoutMessage = "Sem espaço. Escolha um tamanho menor ou remova um widget."; return }
        var value = store.preferences
        for i in value.widgets.indices {
            let kind = value.widgets[i].kind
            if kind == payload.kind { value.widgets[i].enabled = true; value.widgets[i].size = payload.size; value.widgets[i].variant = payload.variant }
            if let frame = frames[kind] { value.widgets[i].x = frame.minX; value.widgets[i].y = frame.maxY }
        }
        store.preferences = value
        reconcile()
    }
    /// Reflow only when the dragged widget enters a different grid cell.
    /// Preferences are committed once at release, not on every pointer event.
    private func previewPush() {
        guard let kind = dragKind, let panel = panels[kind],
              let item = dragBase.first(where: { $0.kind == kind }) else { return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let cell = DesktopGrid.nearest(size: item.size.dimensions, to: panel.frame, screens: screens, occupied: []), cell != lastDragCell else { return }
        lastDragCell = cell
        let remaining = dragBase.filter { $0.kind != kind }
        let requests = [PlacementRequest(kind: kind, size: item.size.dimensions, preferred: cell)] + remaining.map {
            PlacementRequest(kind: $0.kind, size: $0.size.dimensions,
                preferred: CGRect(x: $0.x ?? cell.minX, y: ($0.y ?? cell.maxY) - $0.size.dimensions.height, width: $0.size.dimensions.width, height: $0.size.dimensions.height))
        }
        let layout = DesktopGrid.arrange(requests, screens: screens)
        guard layout.count == dragBase.count else { return } // No room: retain the last valid arrangement.
        dragLayout = layout
        for (other, frame) in layout where other != kind {
            guard let window = panels[other], targets[other] != frame else { continue }
            targets[other] = frame
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { window.setFrame(frame, display: true) }
            else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(frame, display: true)
                }
            }
        }
    }
    private func face(_ item: WidgetItem) -> WidgetFace {
        WidgetFace(desktopInactive: !desktopActive, kind: item.kind, size: item.size, store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda)
    }
}
