import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MusicWidget: View {
    let size: WidgetSize
    @ObservedObject var store: DeskStore
    @ObservedObject var media: MusicService
    var appearance: WidgetAppearance? = nil
    var forcedFrosted: Bool? = nil
    @Environment(\.clearWidgetSurface) private var clearSurface
    private var light: Bool { !clearSurface && (appearance ?? store.preferences.appearanceStyle(.music)) == .light }
    private var layout: MusicLayout { MusicLayout(size: size) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            HarmonizedCardBackground(light: light, frosted: forcedFrosted ?? (store.preferences.surfaceStyle(.music) == .frosted))
            if size != .small {
                Rectangle().fill(Color.black.opacity(light ? 0.035 : 0.09))
                    .frame(height: size.dimensions.height - layout.dividerY).offset(y: layout.dividerY)
            }
            placed(layout.artwork) { MusicArtwork(media: media).clipShape(RoundedRectangle(cornerRadius: size == .large ? 10 : 6)) }
            placed(layout.metadata) {
                VStack(alignment: .leading, spacing: size == .small ? 4 : 3) {
                    Text(media.songTitle.isEmpty ? "Sua música" : media.songTitle)
                        .font(.system(size: size == .large ? 18 : 13, weight: .semibold))
                        .lineLimit(size == .medium ? 1 : 2)
                    Text(media.artistName.isEmpty ? "Abra um player" : media.artistName)
                        .font(.system(size: size == .large ? 15 : 12)).opacity(0.60).lineLimit(1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            placed(layout.play) {
                Button { media.togglePlayPause() } label: {
                    ZStack {
                        Circle().fill(light ? Color.black.opacity(0.85) : .white)
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: layout.play.width * 0.39, weight: .bold))
                            .foregroundStyle(light ? .white : Color(white: 0.25))
                    }
                }.buttonStyle(.plain).disabled(media.track.pid == 0)
                    .accessibilityLabel(media.isPlaying ? "Pausar" : "Reproduzir")
            }
            placed(layout.source) {
                Button { media.openSource() } label: { MusicSourceIcon(provider: MusicProvider.from(bundle: media.track.bundle) ?? store.preferences.musicProvider ?? .automatic) }
                    .buttonStyle(.plain).help(media.track.source.isEmpty ? "Abrir player" : media.track.source)
            }
            if size != .small {
                ForEach(0..<4, id: \.self) { index in
                    let shortcut = media.lowerSlot(index, preferences: store.preferences)
                    placed(layout.shortcut(index)) {
                        Button { media.openLowerSlot(index, preferences: store.preferences) } label: {
                            ZStack {
                                Color.primary.opacity(0.07)
                                if let data = shortcut.artwork, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFill()
                                } else { Image(systemName: shortcut.url == nil && !media.usesSpotifyRecents(store.preferences) ? "plus" : "music.note.list").font(.system(size: 21, weight: .light)).opacity(0.6) }
                            }.clipShape(RoundedRectangle(cornerRadius: index == 0 ? layout.shortcut(index).width / 2 : 8))
                        }.buttonStyle(.plain).help(shortcut.title.isEmpty ? (media.usesSpotifyRecents(store.preferences) ? "Ouça um álbum no Spotify para preencher" : "Configurar atalho") : shortcut.title)
                            .accessibilityLabel(shortcut.title.isEmpty ? "Abrir Spotify para preencher os recentes" : shortcut.title)
                    }
                    if size == .large {
                        Text(shortcut.title.isEmpty ? (media.usesSpotifyRecents(store.preferences) ? "Aguardando" : "Adicionar") : shortcut.title)
                            .font(.system(size: 11, weight: .medium)).lineLimit(2)
                            .frame(width: layout.shortcut(index).width, height: 30, alignment: .topLeading)
                            .offset(x: layout.shortcut(index).minX, y: layout.shortcut(index).maxY + 9)
                    }
                }
            }
        }.frame(width: size.dimensions.width, height: size.dimensions.height)
            .foregroundStyle(light ? .black : .white)
    }
    private func placed<Content: View>(_ rect: CGRect, @ViewBuilder content: () -> Content) -> some View {
        content().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}
struct MusicSourceIcon: View {
    private static var cache: [URL: NSImage] = [:]
    private static func icon(_ url: URL) -> NSImage {
        if let cached = cache[url] { return cached }
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "AppIcon"
        let file = name.hasSuffix(".icns") ? name : name + ".icns"
        let image = NSImage(contentsOf: url.appendingPathComponent("Contents/Resources").appendingPathComponent(file)) ?? NSWorkspace.shared.icon(forFile: url.path)
        cache[url] = image
        return image
    }
    let provider: MusicProvider
    var body: some View {
        if let bundle = provider.bundleID,
           let url = MusicService.applicationURL(bundle) {
            Image(nsImage: Self.icon(url)).resizable().scaledToFit()
        } else { Image(systemName: "music.note").resizable().scaledToFit().padding(2) }
    }
}
enum MusicActions {
    static func open(_ shortcut: MusicShortcut) {
        if let url = shortcut.url { NSWorkspace.shared.open(url) }
        else { NotificationCenter.default.post(name: .loockMusicSettings, object: nil) }
    }
}

/// Eko's 0.18s / 0.30s flip and 0.82 scale, without its pause overlay.
struct MusicArtwork: View {
    @ObservedObject var media: MusicService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var angle = 0.0
    @State private var scale: CGFloat = 1
    @State private var identity: String?
    @State private var flipping = false
    @State private var flipGeneration = UUID()
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.primary.opacity(0.08)
                if let image { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "music.note").font(.system(size: proxy.size.width * 0.35)).opacity(0.5) }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .blur(radius: media.isPlaying || media.track.title.isEmpty ? 0 : 3)
                .animation(.easeInOut(duration: reduceMotion ? 0 : 0.24), value: media.isPlaying)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .scaleEffect(scale)
        }
        .task(id: media.track.identity) {
            let next = media.track.identity
            let generation = UUID(); flipGeneration = generation
            defer { if flipGeneration == generation { flipping = false } }
            guard identity != nil, identity != next, !reduceMotion, !media.songTitle.isEmpty else {
                reset(); identity = next; image = media.albumArtwork; return
            }
            identity = next; flipping = true
            withAnimation(.easeIn(duration: 0.18)) { angle = 90; scale = 0.82 }
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            guard !Task.isCancelled, flipGeneration == generation else { return }
            var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
            withTransaction(transaction) { image = media.albumArtwork; angle = -90 }
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled, flipGeneration == generation else { return }
            withAnimation(.easeInOut(duration: 0.30)) { angle = 0; scale = 1 }
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            if !Task.isCancelled { image = media.albumArtwork }
        }
        .onReceive(media.$track) { track in
            if !flipping && (identity == nil || identity == track.identity), image !== track.artwork {
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { image = track.artwork }
            }
        }
        .onDisappear { flipGeneration = UUID(); flipping = false; reset(); identity = nil }
        .accessibilityLabel("Capa do álbum")
    }
    private func reset() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { angle = 0; scale = 1 }
    }
}

struct MusicOptions: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var media: MusicService
    @State private var imageError = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Player", selection: Binding(get: { store.preferences.musicProvider ?? .automatic }, set: { store.preferences.musicProvider = $0 })) {
                ForEach(MusicProvider.allCases) { Text($0.title).tag($0) }
            }
            Text(media.status).font(.caption).foregroundStyle(.secondary)
            HStack { Button("Abrir player") { media.openSource() }; Button("Atualizar") { media.refreshAll() } }
            Text("Automático acompanha o player ativo. Inicie uma faixa no app escolhido. Os quatro atalhos abaixo abrem seus links de álbuns ou playlists; não são recomendações automáticas.").font(.caption).foregroundStyle(.secondary)
            Toggle("Capas recentes do Spotify automaticamente", isOn: Binding(get: { store.preferences.automaticSpotifyCovers != false }, set: { store.preferences.automaticSpotifyCovers = $0 }))
            Text("Guarda neste Mac até quatro álbuns que o Spotify informar enquanto o widget estiver ativo. Começa vazio e se preenche conforme você escuta. Clicar na capa abre a busca pelo álbum no Spotify.").font(.caption).foregroundStyle(.secondary)
            Button("Limpar álbuns recentes") { media.clearSpotifyHistory() }
            Text("Atalhos manuais (usados quando as capas automáticas estão desativadas ou outro player está ativo)").font(.caption.weight(.semibold))
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Atalho \(index + 1)").font(.caption.weight(.semibold))
                    TextField("Nome do álbum ou playlist", text: binding(index, \.title))
                    TextField("Link do Apple Music, Spotify ou Deezer", text: binding(index, \.link))
                    if !item(index).link.isEmpty && item(index).url == nil { Text("Use um link https do serviço ou um URI spotify.").font(.caption).foregroundStyle(.red) }
                    HStack {
                        Button("Escolher capa…") { chooseArtwork(index) }
                        Button("Limpar") { update(index) { $0 = MusicShortcut() } }
                    }
                }
            }
            if !imageError.isEmpty { Text(imageError).font(.caption).foregroundStyle(.red) }
            Text("Integração experimental do Ventura, baseada no player do Eko. Depende dos dados publicados pelo aplicativo no Reproduzindo Agora.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func item(_ index: Int) -> MusicShortcut { (store.preferences.musicShortcuts ?? []).dropFirst(index).first ?? MusicShortcut() }
    private func update(_ index: Int, _ mutate: (inout MusicShortcut) -> Void) {
        var items = store.preferences.musicShortcuts ?? []
        while items.count < 4 { items.append(MusicShortcut()) }
        mutate(&items[index]); store.preferences.musicShortcuts = items
    }
    private func binding(_ index: Int, _ path: WritableKeyPath<MusicShortcut, String>) -> Binding<String> {
        Binding(get: { item(index)[keyPath: path] }, set: { value in update(index) { $0[keyPath: path] = value } })
    }
    private func chooseArtwork(_ index: Int) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000, let image = MusicService.thumbnail(try Data(contentsOf: url)),
                      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { imageError = "Não foi possível ler a imagem (limite: 20 MB)."; return }
                update(index) { $0.artwork = data }; imageError = ""
            } catch { imageError = "Não foi possível abrir essa imagem." }
        }
    }
}
