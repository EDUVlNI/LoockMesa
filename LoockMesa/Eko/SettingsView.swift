import SwiftUI

@MainActor
struct IntegrationSettingsView: View {
    @ObservedObject var coordinator: LumeCoordinator
    @ObservedObject var model: StatusModel
    @ObservedObject var hud: HUDManager
    @ObservedObject var corners: OverlayManager
    @ObservedObject var player: MediaRemoteWrapper
    @ObservedObject private var keys = MediaKeyManager.shared
    @ObservedObject private var native = NativeHUDController.shared
    let selected: Page
    enum Page: String, CaseIterable, Identifiable {
        case capsule = "Capsule", indicators = "Indicadores", hud = "Volume e brilho", music = "Música", appearance = "Tela", permissions = "Permissões"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .capsule: return .blue
            case .indicators: return .purple
            case .hud: return .pink
            case .music: return .red
            case .appearance: return .cyan
            case .permissions: return .blue
            }
        }
        var symbol: String {
            switch self {
            case .capsule: return "capsule"
            case .indicators: return "slider.horizontal.3"
            case .hud: return "speaker.wave.2"
            case .music: return "music.note"
            case .appearance: return "macwindow"
            case .permissions: return "hand.raised"
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(selected == .music ? "Player flutuante" : selected.rawValue).font(.title2.bold())
            detail
        }.frame(maxWidth: .infinity, alignment: .leading).toggleStyle(.switch)
    }
    @ViewBuilder private var detail: some View {
        switch selected {
        case .capsule:
            Text("Hora, conexão e bateria, discretamente no topo da tela.").foregroundStyle(.secondary)
            card("Visibilidade") {
                Toggle("Ativar Capsule", isOn: $coordinator.capsuleEnabled)
                Text("Some quando a barra de menus aparece ou ao passar o mouse. A Siri permanece clicável.").font(.caption).foregroundStyle(.secondary)
            }
            card("Dimensões e fundo") {
                HStack { Text("Tamanho"); Spacer(); Text("\(Int(model.scale * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $model.scale, in: 0.75...1.6, step: 0.05)
                HStack { Text("Opacidade do fundo"); Spacer(); Text("\(Int(model.backgroundOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $model.backgroundOpacity, in: 0...1, step: 0.01)
                Text("0% deixa o fundo transparente; 100% mantém todo o efeito de desfoque.").font(.caption).foregroundStyle(.secondary)
                Button("Restaurar tamanho e fundo") { model.scale = 1; model.backgroundOpacity = 0.92 }
            }
            card("Porcentagem da bateria") {
                Toggle("Mostrar porcentagem sempre", isOn: $model.showsPercentage)
                Toggle("Mostrar porcentagem ao carregar", isOn: $model.showsPercentageWhileCharging)
                Text("Com a primeira opção desativada, a porcentagem aparece ao conectar o carregador e some ao desconectar.").font(.caption).foregroundStyle(.secondary)
            }
        case .indicators:
            Text("Escolha os indicadores e arraste os itens para organizar sua ordem.").foregroundStyle(.secondary)
            ArrangementView(model: model).frame(maxWidth: .infinity)
            card("Fones de ouvido") {
                Text(model.headphoneName ?? "Nenhum fone conectado").font(.headline)
                Text("O Huawei FreeClip usa o seu vetor. Outros fones recebem o símbolo de fone de ouvido.").foregroundStyle(.secondary)
                Button("Associar saída de áudio atual ao FreeClip") { AudioDeviceManager.shared.associateCurrentDeviceAsFreeClip() }
                Button("Remover associação manual") { AudioDeviceManager.shared.clearFreeClipAssociation() }
            }
        case .hud:
            Text("Indicadores de volume, brilho da tela e iluminação do teclado.").foregroundStyle(.secondary)
            card("Controles") {
                Toggle("Ativar indicadores de volume e brilho", isOn: $coordinator.hudEnabled)
                Picker("Posição das barras", selection: $hud.position) {
                    ForEach(HUDPosition.allCases) { position in Text(position.rawValue).tag(position) }
                }.pickerStyle(.segmented)
                Text("No centro, as barras ficam na horizontal e aparecem pela parte inferior da tela.").font(.caption).foregroundStyle(.secondary)
                Picker("Barra de volume e brilho", selection: $hud.presentationMode) {
                    ForEach(HUDPresentationMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Text("Automática: até três ajustes usa a barra fina; no quarto ajuste seguido ela se expande. Intervalo máximo de 0,8 segundo.").font(.caption).foregroundStyle(.secondary)
                Picker("Animação de entrada e saída", selection: $hud.transitionMode) {
                    ForEach(HUDTransitionMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Text("A animação também vale para a iluminação do teclado.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Testar volume") { hud.showVolume(0.65) }
                    Button("Testar tela") { hud.showDisplayBrightness(0.65) }
                    Button("Testar teclado") { hud.showKeyboardBrightness(0.65) }
                }.disabled(!coordinator.hudEnabled)
                Text("Os testes só mostram o indicador; não alteram volume ou brilho.").font(.caption).foregroundStyle(.secondary)
            }
            card("Touch Bar") {
                Toggle("Preferir os indicadores do Gergelim", isOn: Binding(get: { native.preferred }, set: { native.setEnabled($0) }))
                    .disabled(!coordinator.hudEnabled)
                Text(native.status).font(.caption).foregroundStyle(.secondary)
                Text("A preferência fica salva e é retomada ao abrir o Gergelim. Ao sair do app, o indicador nativo é restaurado.").font(.caption).foregroundStyle(.secondary)
            }
        case .music:
            Text("O player acompanha apenas seus aplicativos de música.").foregroundStyle(.secondary)
            card("Player") {
                Toggle("Player flutuante", isOn: Binding(
                    get: { player.enabled && player.floatingPlayerEnabled },
                    set: { value in
                        player.floatingPlayerEnabled = value
                        if value { player.enabled = true }
                    }
                ))
                Text("O player maior que aparece no topo da tela.").font(.caption).foregroundStyle(.secondary)
                Text(player.status).foregroundStyle(.secondary)
                if !player.songTitle.isEmpty {
                    Text(player.songTitle).font(.headline)
                    Text(player.artistName).foregroundStyle(.secondary)
                    HStack {
                        Button("Anterior") { player.previousTrack() }
                        Button(player.isPlaying ? "Pausar" : "Reproduzir") { player.togglePlayPause() }
                        Button("Próxima") { player.nextTrack() }
                    }
                }
            }
            card("Aplicativos aceitos") {
                Label("Spotify", systemImage: "checkmark.circle.fill")
                Label("Deezer", systemImage: "checkmark.circle.fill")
                Label("Apple Music", systemImage: "checkmark.circle.fill")
                Text("Use os aplicativos instalados. Navegadores, chamadas e outras fontes de áudio não aparecem no player.").font(.caption).foregroundStyle(.secondary)
            }
        case .appearance:
            card("Cantos da tela") {
                Toggle("Arredondar cantos", isOn: $corners.isEnabled)
                HStack { Text("Raio dos cantos"); Spacer(); Text("\(Int(corners.radius)) pt").monospacedDigit() }
                Slider(value: $corners.radius, in: 0...120, step: 1).disabled(!corners.isEnabled)
            }
        case .permissions:
            card("Acessibilidade") {
                Label(keys.isAccessibilityGranted ? "Acesso concedido" : "Acesso necessário para as teclas", systemImage: keys.isAccessibilityGranted ? "checkmark.circle" : "keyboard")
                Text("Autorize o Gergelim para usar as teclas de volume e brilho com seus indicadores.").foregroundStyle(.secondary)
                Button("Autorizar Acessibilidade") { keys.checkAccessibility(prompt: true) }
                Button("Verificar novamente") { coordinator.updateHUD() }
                if let error = keys.eventTapError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            card("Bluetooth e Siri") {
                Text("O macOS pode pedir acesso ao Bluetooth para identificar fones. O botão da Siri abre a assistente instalada no Mac.").foregroundStyle(.secondary)
            }
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 14) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.13), lineWidth: 0.7))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
