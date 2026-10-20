import SwiftUI

import AppKit
import Combine

enum HUDStyle: String, CaseIterable, Identifiable {
    case iOSVolume = "iOS Volume"
    case iOSDisplay = "iOS Tela"
    case iOSKeyboard = "iOS Teclado"
    case nowPlayingClassic = "Now Playing Classic"
    var id: String { self.rawValue }
}


enum HUDPresentationMode: String, CaseIterable, Identifiable {
    case automatic = "Automática", thin = "Sempre fina", full = "Sempre completa"
    var id: String { rawValue }
}
enum HUDTransitionMode: String, CaseIterable, Identifiable {
    case slide = "Deslizar", blur = "Desfoque da Capsule"
    var id: String { rawValue }
}
struct HUDBurstPolicy {
    private var lastStyle: HUDStyle?
    private var lastTime: TimeInterval = -.infinity
    private var lastValue: Double?
    private var count = 0
    private var expanded = false
    mutating func reset() { lastStyle = nil; lastTime = -.infinity; lastValue = nil; count = 0; expanded = false }
    mutating func compact(style: HUDStyle, value: Double, visible: Bool, mode: HUDPresentationMode, now: TimeInterval) -> Bool {
        guard style == .iOSVolume || style == .iOSDisplay else { reset(); return false }
        if !visible || lastStyle != style { reset() }
        if mode == .thin { return true }
        if mode == .full { return false }
        if !expanded && now - lastTime > 0.8 { count = 0 }
        // Hardware callbacks can report the same adjustment more than once.
        if lastValue != value || lastStyle != style {
            count += 1
            lastTime = now
            lastValue = value
        }
        lastStyle = style
        if count >= 4 { expanded = true }
        return !expanded
    }
}

enum HUDPosition: String, CaseIterable, Identifiable {
    case left = "Esquerda", right = "Direita", center = "Centro"
    var id: String { rawValue }
    var horizontal: Bool { self == .center }
    var alignment: Alignment { self == .left ? .leading : self == .right ? .trailing : .bottom }
    func offset(visible: Bool) -> CGSize {
        switch self {
        case .left: return CGSize(width: visible ? 16 : -80, height: 0)
        case .right: return CGSize(width: visible ? -16 : 80, height: 0)
        case .center: return CGSize(width: 0, height: visible ? -110 : 80)
        }
    }
    func origin(screen: CGRect, size: CGSize) -> CGPoint {
        switch self {
        case .left: return CGPoint(x: screen.minX, y: screen.midY - size.height / 2)
        case .right: return CGPoint(x: screen.maxX - size.width, y: screen.midY - size.height / 2)
        case .center: return CGPoint(x: screen.midX - size.width / 2, y: screen.minY)
        }
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HUDView: View {
    @ObservedObject var state = HUDState.shared

    var body: some View {
        Group {
            switch state.style {
            case .iOSVolume, .iOSDisplay, .iOSKeyboard:
                IOSHUDView(value: state.value, icon: state.style == .iOSVolume ? "speaker.wave.3.fill" : state.style == .iOSDisplay ? "sun.max.fill" : "keyboard", isVisible: state.isVisible, setLevel: state.setLevel, editing: state.editing, position: state.position, compact: state.compact, transition: state.transition, hovering: state.hovering)
            case .nowPlayingClassic:
                NowPlayingClassicView(value: state.value, icon: "music.note", isVisible: state.isVisible)
            }
        }
    }
}

struct BezelPillShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct IOSHUDView: View {
    var value: Double
    var icon: String
    var isVisible: Bool

    var setLevel: ((Double) -> Void)? = nil
    var editing: ((Bool) -> Void)? = nil
    var position: HUDPosition = .left
    var compact = false
    var transition: HUDTransitionMode = .slide
    var hovering: ((Bool) -> Void)? = nil
    @State private var isHovered = false
    private var isCompact: Bool { compact && !isHovered && !isDragging }
    private var thickness: CGFloat { isCompact ? 8 : 48 }
    @State private var animatedValue: Double = 0.0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared

    // Ícones dinâmicos baseados no tipo (pelo ícone passado) e no valor
    var currentIcon: String {
        if icon.contains("speaker") {
            if audioDeviceManager.isHeadphonesActive { return "headphones" }
            if value <= 0.01 { return "speaker.slash.fill" }
            if value <= 0.33 { return "speaker.wave.1.fill" }
            if value <= 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        } else if icon.contains("sun") {
            if animatedValue <= 0.33 { return "sun.min.fill" }
            return "sun.max.fill"
        } else if icon.contains("macwindow") || icon.contains("keyboard") {
            if animatedValue <= 0.01 { return "light.min" }
            return "light.max"
        }
        return icon
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Fundo escuro nativo (Blur da Apple - HUD)
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .environment(\.colorScheme, .dark)

            Group {
            // 2. Ícone base transparente (visível apenas onde NÃO há preenchimento branco)
            if icon.contains("speaker") && audioDeviceManager.isFreeClipActive {
                FreeClipIconView()
                    .frame(width: 22, height: 22)
                    .foregroundColor(Color.white.opacity(0.4))
                    .rotationEffect(.degrees(position.horizontal ? -90 : 0))
                    .transaction { $0.animation = nil }
                    .padding(.bottom, 16)

                if value <= 0.01 {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.4))
                        .rotationEffect(.degrees(position.horizontal ? -90 : 0))
                    .transaction { $0.animation = nil }
                    .padding(.bottom, 16)
                }
            } else {
                Image(systemName: currentIcon)
                    .font(.system(size: 16, weight: .medium)) // Menor e mais delicado
                    .foregroundColor(Color.white.opacity(0.4))
                    .rotationEffect(.degrees(position.horizontal ? -90 : 0))
                    .transaction { $0.animation = nil }
                    .padding(.bottom, 16) // Ajuste para equilibrar a nova altura
            }

            }.opacity(isCompact ? 0 : 1)

            // 3. Preenchimento (Volume) Branco com "Furo" para o ícone
            Color.white
                // Leve transparência para dar o tom off-white da imagem
                .opacity(0.95)
                .mask(
                    ZStack(alignment: .bottom) {
                        // A barra que preenche de baixo pra cima
                        Color.white
                            .scaleEffect(y: CGFloat(animatedValue), anchor: .bottom)

                        if !isCompact {
                        // O furo exato na posição do ícone
                        if icon.contains("speaker") && audioDeviceManager.isFreeClipActive {
                            ZStack {
                                FreeClipIconView()
                                    .frame(width: 22, height: 22)
                                if value <= 0.01 {
                                    Image(systemName: "line.diagonal")
                                        .font(.system(size: 24, weight: .bold))
                                }
                            }
                            .rotationEffect(.degrees(position.horizontal ? -90 : 0))
                    .transaction { $0.animation = nil }
                    .padding(.bottom, 16)
                            .blendMode(.destinationOut)
                        } else {
                            Image(systemName: currentIcon)
                                .font(.system(size: 16, weight: .medium))
                                .rotationEffect(.degrees(position.horizontal ? -90 : 0))
                    .transaction { $0.animation = nil }
                    .padding(.bottom, 16)
                                .blendMode(.destinationOut)
                        }
                        }
                    }
                    .compositingGroup()
                )
        }
        // Mais fino e mais longo (Retangular com bordas arredondadas)
        .frame(width: thickness, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4 : 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 4 : 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: isCompact ? 5 : 20, x: 0, y: 10)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard let setLevel = setLevel else { return }
                if !isDragging { isDragging = true; editing?(true) }
                let level = min(1, max(0, 1 - Double(drag.location.y / 230)))
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { animatedValue = level }
                setLevel(level)
            }
            .onEnded { drag in
                setLevel?(min(1, max(0, 1 - Double(drag.location.y / 230))))
                isDragging = false
                editing?(false)
            })
        .accessibilityLabel(icon.contains("speaker") ? "Volume" : "Brilho")
        .accessibilityValue("\(Int(animatedValue * 100)) por cento")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            setLevel?(min(1, max(0, animatedValue + step)))
        }
        .compositingGroup()
        // Os três indicadores usam exatamente a mesma entrada e saída.
        .rotationEffect(.degrees(position.horizontal ? 90 : 0))
        .frame(width: position.horizontal ? 230 : thickness, height: position.horizontal ? thickness : 230)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.92), value: isCompact)
        .frame(width: position.horizontal ? 230 : 48, height: position.horizontal ? 48 : 230, alignment: position.alignment)
        .contentShape(Rectangle())
        .onHover { active in
            guard isVisible, isHovered != active else { return }
            isHovered = active
            hovering?(active)
        }
        .onChange(of: isVisible) { visible in
            if !visible { isHovered = false; isDragging = false; hovering?(false) }
        }
        .onDisappear { isHovered = false; hovering?(false) }
        .blur(radius: transition == .blur && !isVisible && !reduceMotion ? 5 : 0)
        .scaleEffect(transition == .blur && !isVisible && !reduceMotion ? 0.96 : 1, anchor: position.horizontal ? .bottom : position == .left ? .leading : .trailing)
        .offset(position.offset(visible: transition == .blur ? true : isVisible))
        .opacity(isVisible ? 1.0 : 0.0)
        // Manter a entrada ancorada à borda escolhida.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : transition == .blur ? .timingCurve(0.22, 0.8, 0.25, 1, duration: 0.3) : .spring(response: 0.38, dampingFraction: 0.9), value: isVisible)
        .onChange(of: value) { newValue in
            let safeValue = min(1, max(0, newValue.isFinite ? newValue : 0))
            guard !isDragging else { return }
            withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 1)) { animatedValue = safeValue }
        }
        .onAppear {
            animatedValue = min(1, max(0, value.isFinite ? value : 0))
        }

    }
}

struct NowPlayingClassicView: View {
    var value: Double
    var icon: String
    var isVisible: Bool

    @State private var animatedValue: Double = 0.0

    @ObservedObject var media = MediaRemoteWrapper.shared

    @State private var visualTitle: String = ""
    @State private var visualArtist: String = ""
    @State private var visualArtwork: NSImage? = nil
    @State private var visualIsPlaying: Bool = true

    @State private var currentTask: Task<Void, Never>? = nil
    @State private var lastVisibleTime: Date = .distantPast
    @State private var animatedTextWidth: CGFloat = 100

    var body: some View {
        HStack(spacing: 14) {
            // Arte do álbum com transição tipo Dynamic Island
            ZStack {
                ZStack {
                    if let img = visualArtwork {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(red: 0.2, green: 0.2, blue: 0.22)
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .blur(radius: isVisible && !visualIsPlaying ? 6 : 0)

                if isVisible && !visualIsPlaying {
                    Color.black.opacity(0.3)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            .padding(.leading, 6)
            .id(visualTitle + visualArtist) // Chave para disparar transição de Flip
            .transition(.coverFlip) // Efeito Flip da Dynamic Island
            .onTapGesture {
                media.togglePlayPause()
            }

            ZStack(alignment: .leading) {
                // Ancora invisível que mede o texto livremente
                VStack(alignment: .leading, spacing: 2) {
                    Text(visualTitle.isEmpty ? "Nenhuma música" : visualTitle)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .lineLimit(1)

                    Text(visualArtist)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()

                // O texto visível que faz o crossfade
                VStack(alignment: .leading, spacing: 2) {
                    Text(visualTitle.isEmpty ? "Nenhuma música" : visualTitle)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(visualArtist)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                .id(visualTitle + visualArtist)
                .transition(.textBlur)
            }
            .frame(width: min(max(animatedTextWidth, 10), 300), alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: animatedTextWidth)
            .onPreferenceChange(WidthPreferenceKey.self) { width in
                animatedTextWidth = width
            }
        }
        .padding(.trailing, 16) // Espaço na direita do texto
        .frame(height: 64) // Altura fixa, largura dinâmica!
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).environment(\.colorScheme, .dark))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 15)
            .onEnded { drag in
                if drag.translation.width < -15 {
                    media.nextTrack()
                } else if drag.translation.width > 15 {
                    media.previousTrack()
                }
            }
        )
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
        // Animação saindo do topo da tela (Bezel top)
        .offset(y: isVisible ? 30 : -100)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isVisible)
        // Fixar o elemento no topo da janela que agora toca a borda da tela
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: value) { newValue in
            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8)) {
                animatedValue = newValue
            }
        }
        .onChange(of: isVisible) { newVisible in
            if newVisible {
                lastVisibleTime = Date()
                syncVisualState()
            } else {
                currentTask?.cancel()
            }
        }
        .onChange(of: media.songTitle) { _ in if isVisible { syncVisualState() } }
        .onChange(of: media.artistName) { _ in if isVisible { syncVisualState() } }
        .onChange(of: media.albumArtwork) { _ in if isVisible { syncVisualState() } }
        .onChange(of: media.isPlaying) { _ in if isVisible { syncVisualState() } }
        .onAppear {
            if isVisible {
                lastVisibleTime = Date()
                syncVisualState()
            } else {
                // Initialize state silently
                visualTitle = media.songTitle.isEmpty ? "Nenhuma música" : media.songTitle
                visualArtist = media.artistName
                visualArtwork = media.albumArtwork
                visualIsPlaying = media.isPlaying
            }
        }
    }

    private func syncVisualState() {
        let targetTitle = media.songTitle.isEmpty ? "Nenhuma música" : media.songTitle
        let targetArtist = media.artistName
        let targetArtwork = media.albumArtwork
        let targetIsPlaying = media.isPlaying

        let needsTrackChange = (visualTitle != targetTitle || visualArtist != targetArtist)
        let needsPlayPauseChange = (visualIsPlaying != targetIsPlaying)
        let needsArtworkChange = (visualArtwork != targetArtwork)

        guard needsTrackChange || needsPlayPauseChange || needsArtworkChange else { return }

        currentTask?.cancel()
        currentTask = Task {
            // How much of the 0.4s entrance is left?
            let elapsed = Date().timeIntervalSince(lastVisibleTime)
            let remainingDelay = max(0, 0.4 - elapsed)

            if remainingDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
            }
            if Task.isCancelled { return }

            if visualTitle.isEmpty {
                // First appearance ever, no animation needed
                visualTitle = targetTitle
                visualArtist = targetArtist
                visualArtwork = targetArtwork
                visualIsPlaying = targetIsPlaying
                return
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                if needsTrackChange {
                    visualTitle = targetTitle
                    visualArtist = targetArtist
                    visualArtwork = targetArtwork
                } else if needsArtworkChange {
                    visualArtwork = targetArtwork
                }
                if needsPlayPauseChange {
                    visualIsPlaying = targetIsPlaying
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    final class Material: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = Material()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
    }
}


struct BlurModifier: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    var scale: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

struct FlipModifier: ViewModifier {
    var angle: Double
    var scale: CGFloat
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(Angle(degrees: angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(scale)
    }
}

extension AnyTransition {
    static var textBlur: AnyTransition {
        AnyTransition.modifier(
            active: BlurModifier(radius: 12, opacity: 0, scale: 0.95),
            identity: BlurModifier(radius: 0, opacity: 1, scale: 1.0)
        )
    }

    static var coverFlip: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90, scale: 0.8), identity: FlipModifier(angle: 0, scale: 1.0)).combined(with: .opacity),
            removal: .modifier(active: FlipModifier(angle: 90, scale: 0.8), identity: FlipModifier(angle: 0, scale: 1.0)).combined(with: .opacity)
        )
    }
}

class HUDState: ObservableObject {
    static let shared = HUDState()

    @Published var compact = false
    @Published var transition: HUDTransitionMode = .slide
    var presentationMode: HUDPresentationMode = .automatic
    private var burst = HUDBurstPolicy()
    @Published var position: HUDPosition = .left
    @Published var style: HUDStyle = .iOSVolume
    @Published var value: Double = 0.5
    @Published var isVisible: Bool = false
    var setLevel: ((Double) -> Void)?
    var editing: ((Bool) -> Void)?
    var hovering: ((Bool) -> Void)?
    func show(style: HUDStyle, value: Double, animateLevel: Bool = false) {
        guard value.isFinite else { return }
        let nextCompact = burst.compact(style: style, value: value, visible: isVisible, mode: presentationMode, now: ProcessInfo.processInfo.systemUptime)
        if compact != nextCompact { compact = nextCompact }
        let animate = animateLevel && isVisible && self.style == style
        var transaction = Transaction(animation: animate ? .easeOut(duration: 0.16) : nil)
        transaction.disablesAnimations = !animate
        withTransaction(transaction) {
            if self.style != style { self.style = style }
            let level = min(1, max(0, value))
            if self.value != level { self.value = level }
        }
        // Mostrar imediatamente. Adiar isso para a próxima passagem da fila
        // fazia uma sequência contínua de brilho manter o HUD invisível até o
        // usuário parar de arrastar.
        if !isVisible { isVisible = true }
    }

    func hide() {
        self.isVisible = false
        burst.reset()
    }
}


struct FreeClipIconView: View {
    var body: some View { EkoFreeClipIcon() }
}
