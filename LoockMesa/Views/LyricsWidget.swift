import SwiftUI
import AppKit

/// Shared coordinates keep native hit targets exactly over the SwiftUI glyphs.
struct LyricsLayout {
    let size: WidgetSize
    var progress: CGRect { CGRect(x: size == .small ? 13 : 18, y: size.dimensions.height - 73, width: size.dimensions.width - (size == .small ? 26 : 36), height: 24) }
    var bubble: CGRect { CGRect(x: size.dimensions.width - 43, y: 10, width: 32, height: 32) }
    func control(_ index: Int) -> CGRect {
        let center = size.dimensions.width / 2 + CGFloat(index - 1) * (size == .small ? 45 : 66)
        return CGRect(x: center - 20, y: size.dimensions.height - 48, width: 40, height: 36)
    }
}
struct LyricsWidget: View {
    let size: WidgetSize
    @ObservedObject var media: MusicService
    var appearance: WidgetAppearance
    var frosted: Bool
    @ObservedObject private var lyrics = LyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.widgetPreview) private var preview
    @State private var progressHovered = false
    private var layout: LyricsLayout { LyricsLayout(size: size) }
    private var light: Bool { appearance == .light }
    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.32) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            HarmonizedCardBackground(light: light, frosted: frosted)
            AlbumColorGradient(media: media)
                .opacity(appearance == .original ? (frosted ? 0.62 : 0.94) : 0.12)
                .allowsHitTesting(false)
            TimelineView(.animation(minimumInterval: 0.1, paused: preview || !media.isPlaying)) { timeline in
                let elapsed = media.scrubPosition ?? media.position.at(timeline.date)
                ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if lyrics.showingLyrics && lyrics.document.available {
                            lyricContent(elapsed: elapsed).transition(.opacity.combined(with: .offset(y: 5)))
                        } else {
                            metadata.transition(.opacity.combined(with: .offset(y: -5)))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                    Color.clear.frame(height: lyrics.showingLyrics ? 43 : 67)
                }.padding(.horizontal, size == .small ? 13 : 18).padding(.top, 15).padding(.bottom, 9)
                if !lyrics.showingLyrics {
                    placed(layout.progress) { progress(elapsed: elapsed) }.transition(.opacity)
                }
                }
            }
            placed(layout.bubble) {
                Button { lyrics.toggle() } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((light ? Color.black : Color.white).opacity(lyrics.showingLyrics ? 0.12 : 0.04), in: Circle())
                }.buttonStyle(.plain)
                    .opacity(lyrics.document.available ? 0.9 : 0.25)
                    .disabled(!lyrics.document.available)
                    .accessibilityLabel(lyrics.document.available ? "Mostrar ou ocultar letras" : "Letra indisponível")
            }
            ForEach(0..<3, id: \.self) { index in
                placed(layout.control(index)) {
                    Button {
                        if index == 0 { media.previousTrack() }
                        else if index == 1 { media.togglePlayPause() }
                        else { media.nextTrack() }
                    } label: {
                        PlaybackControlGlyph(media: media, index: index, light: light)
                    }.buttonStyle(.plain).disabled(media.track.pid == 0)
                        .opacity(media.track.pid == 0 ? 0.3 : 1)
                        .accessibilityLabel(index == 0 ? "Faixa anterior" : index == 2 ? "Próxima faixa" : media.isPlaying ? "Pausar" : "Reproduzir")
                }
            }
        }.foregroundStyle(light ? Color.black : Color.white)
            .frame(width: size.dimensions.width, height: size.dimensions.height)
            .animation(animation, value: lyrics.showingLyrics)
            .onChange(of: lyrics.showingLyrics) { showing in
                progressHovered = false
                if showing { media.cancelScrub() }
            }

    }
    private var metadata: some View {
        HStack(alignment: .center, spacing: 12) {
            if size != .small {
                MusicArtwork(media: media)
                    .frame(width: size == .large ? 92 : 54, height: size == .large ? 92 : 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(media.songTitle.isEmpty ? "Sua música" : media.songTitle)
                    .font(.system(size: size == .large ? 19 : 14, weight: .semibold)).lineLimit(2)
                Text(media.artistName.isEmpty ? "Abra um player" : media.artistName)
                    .font(.system(size: 12)).opacity(0.6).lineLimit(1)
                if size == .large { Text(media.albumName).font(.system(size: 12)).opacity(0.5).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.trailing, 29).padding(.top, size == .large ? 50 : 0)
            .animation(animation, value: media.track.identity)
    }
    @ViewBuilder private func lyricContent(elapsed: TimeInterval) -> some View {
        if !lyrics.document.lines.isEmpty && media.position.known {
            let active = lyrics.document.activeIndex(at: elapsed) ?? -1
            let rowHeight: CGFloat = size == .large ? 57 : 31
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Keep a fixed local window of rows; SwiftUI interpolates their offsets when the active index changes.
                    ForEach(lyrics.document.lines.filter { abs($0.id - max(0, active)) <= 3 }) { line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: size == .large ? 20 : size == .small ? 12 : 15, weight: .semibold))
                            .lineLimit(2).minimumScaleFactor(0.85)
                            .frame(width: geometry.size.width - 26, height: rowHeight, alignment: .leading)
                            .scaleEffect(line.id == active ? 1 : 0.84, anchor: .leading)
                            .opacity(line.id == active ? 1 : 0.3)
                            .shadow(color: line.id == active && !light ? Color.white.opacity(0.45) : .clear, radius: 4)
                            .shadow(color: line.id == active && !light ? Color.white.opacity(0.16) : .clear, radius: 9)
                            .blur(radius: reduceMotion || line.id == active ? 0 : 1.0)
                            .position(x: (geometry.size.width - 26) / 2,
                                      y: geometry.size.height / 2 + CGFloat(line.id - max(0, active)) * rowHeight)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .animation(animation, value: active)
            }
        } else {
            ScrollView {
                Text(lyrics.document.plain.isEmpty ? lyrics.document.lines.map(\.text).joined(separator: "\n") : lyrics.document.plain)
                    .font(.system(size: size == .large ? 18 : 13, weight: .medium))
                    .lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 27)
            }
        }
    }
    private func progress(elapsed: TimeInterval) -> some View {
        let expanded = progressHovered || media.scrubPosition != nil
        return VStack(spacing: 4) {
            GeometryReader { proxy in
                let fraction = media.position.duration > 0 ? min(1, max(0, elapsed / media.position.duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill((light ? Color.black : Color.white).opacity(0.18))
                    Capsule().fill((light ? Color.black : Color.white).opacity(0.75))
                        .frame(width: proxy.size.width * fraction)
                }.frame(height: expanded ? 6 : 1)
                    .frame(height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
            }.frame(height: 8)
            HStack {
                Text(media.position.known ? time(elapsed) : "—:—")
                Spacer()
                Text(media.position.duration > 0 && media.position.known ? "−" + time(max(0, media.position.duration - elapsed)) : "—:—")
            }.font(.system(size: 8)).monospacedDigit().opacity(0.5)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MusicProgressHover(hovered: $progressHovered).padding(.vertical, -8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !preview, media.canSeek else { return }
                let fraction = Double(value.location.x / layout.progress.width)
                if media.scrubPosition == nil { media.beginScrub(fraction: fraction) }
                else { media.updateScrub(fraction: fraction) }
            }.onEnded { _ in media.finishScrub() })
            .accessibilityLabel("Posição da música")
            .accessibilityValue(time(elapsed))
            .accessibilityAdjustableAction { direction in
                guard !preview else { return }
                switch direction {
                case .increment: media.seek(to: elapsed + 5)
                case .decrement: media.seek(to: elapsed - 5)
                @unknown default: break
                }
            }
    }
    private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func placed<Content: View>(_ rect: CGRect, @ViewBuilder content: () -> Content) -> some View {
        content().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}

/// Tracking works even beneath the desktop's native scrub hit surface.
/// Each widget owns its hover state, so hovering one does not expand the others.
private struct MusicProgressHover: NSViewRepresentable {
    @Binding var hovered: Bool
    func makeNSView(context: Context) -> HoverView {
        let view = HoverView()
        view.changed = { hovered = $0 }
        return view
    }
    func updateNSView(_ view: HoverView, context: Context) {
        view.changed = { hovered = $0 }
    }
    static func dismantleNSView(_ view: HoverView, coordinator: ()) {
        view.changed = nil
    }
    final class HoverView: NSView {
        var changed: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(next); area = next
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { changed?(true) }
        override func mouseExited(with event: NSEvent) { changed?(false) }
    }
}

/// Two polygons interpolate from a single triangle to parallel pause bars on macOS 13.
struct PlaybackMorphShape: Shape {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        let play: [[CGPoint]] = [
            [CGPoint(x: 0.08, y: 0), CGPoint(x: 0.5, y: 0.25), CGPoint(x: 0.5, y: 0.75), CGPoint(x: 0.08, y: 1)],
            [CGPoint(x: 0.5, y: 0.25), CGPoint(x: 0.92, y: 0.5), CGPoint(x: 0.92, y: 0.5), CGPoint(x: 0.5, y: 0.75)]]
        let pause: [[CGPoint]] = [
            [CGPoint(x: 0.08, y: 0), CGPoint(x: 0.38, y: 0), CGPoint(x: 0.38, y: 1), CGPoint(x: 0.08, y: 1)],
            [CGPoint(x: 0.62, y: 0), CGPoint(x: 0.92, y: 0), CGPoint(x: 0.92, y: 1), CGPoint(x: 0.62, y: 1)]]
        var path = Path()
        let t = min(1, max(0, progress))
        for half in 0..<2 {
            var vertices: [(CGPoint, CGFloat)] = []
            for index in 0..<4 {
                let a = play[half][index], b = pause[half][index]
                let point = CGPoint(x: rect.minX + (a.x + (b.x - a.x) * t) * rect.width,
                                    y: rect.minY + (a.y + (b.y - a.y) * t) * rect.height)
                let seam = half == 0 ? (index == 1 || index == 2) : (index == 0 || index == 3)
                let radius = min(rect.width, rect.height) * 0.09 * (seam ? t : 1)
                if vertices.last?.0 != point { vertices.append((point, radius)) }
            }
            for index in vertices.indices {
                let point = vertices[index].0
                let previous = vertices[(index + vertices.count - 1) % vertices.count].0
                let next = vertices[(index + 1) % vertices.count].0
                let before = hypot(point.x - previous.x, point.y - previous.y)
                let after = hypot(next.x - point.x, next.y - point.y)
                let radius = min(vertices[index].1, min(before, after) * 0.45)
                let entry = CGPoint(x: point.x + (previous.x - point.x) * radius / max(before, 0.001),
                                    y: point.y + (previous.y - point.y) * radius / max(before, 0.001))
                let exit = CGPoint(x: point.x + (next.x - point.x) * radius / max(after, 0.001),
                                   y: point.y + (next.y - point.y) * radius / max(after, 0.001))
                if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
                path.addQuadCurve(to: exit, control: point)
            }
            path.closeSubpath()
        }
        return path
    }
}
struct PlaybackMorphIcon: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PlaybackMorphShape(progress: playing ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: playing)
    }
}
private struct PlaybackControlGlyph: View {
    @ObservedObject var media: MusicService
    let index: Int
    let light: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().fill((light ? Color.black : Color.white).opacity(Double(pulse) * 0.17))
                .blur(radius: 7).frame(width: 33, height: 33)
            Group {
                if index == 1 { PlaybackMorphIcon(playing: media.isPlaying).frame(width: 21, height: 24) }
                else { Image(systemName: index == 0 ? "backward.fill" : "forward.fill").font(.system(size: 21, weight: .semibold)) }
            }
            .offset(x: reduceMotion ? 0 : (index == 0 ? -3 : index == 2 ? 3 : 0) * pulse)
            .scaleEffect(reduceMotion ? 1 : 1 - pulse * 0.08)
            .shadow(color: (light ? Color.black : Color.white).opacity(Double(pulse) * 0.5), radius: 5)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: media.controlFeedback.id) {
                let command: UInt32 = index == 0 ? 5 : index == 1 ? 2 : 4
                guard media.controlFeedback.command == command else { return }
                withAnimation(.easeOut(duration: 0.08)) { pulse = 1 }
                do { try await Task.sleep(nanoseconds: 90_000_000) } catch { pulse = 0; return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.28, dampingFraction: 0.78)) { pulse = 0 }
            }
    }
}
