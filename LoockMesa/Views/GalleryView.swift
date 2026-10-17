import SwiftUI
import AppKit

struct GalleryView: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var devices: DeviceService
    let weather: WeatherService
    @ObservedObject var bluetooth: BluetoothBatteryService
    @ObservedObject var agenda: AgendaService
    var finishEditing: () -> Void = {}
    @StateObject private var login = LoginService()
    @StateObject private var previewEntrance = WidgetEntranceState()
    @State private var previewEntryID = UUID()
    @State private var selected: WidgetKind = .headphones
    @State private var general = false
    @State private var allWidgets = true
    @State private var search = ""
    private var categories: [WidgetKind] { WidgetKind.allCases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Buscar widgets", text: $search).textFieldStyle(.roundedBorder)
                    ScrollView {
                        VStack(spacing: 5) {
                            sidebarRow("Todos os widgets", symbol: "square.grid.2x2", color: .blue, active: allWidgets && !general) { allWidgets = true; general = false }
                            ForEach(categories) { kind in
                                sidebarRow(kind.title, symbol: kind.symbol, color: iconColor(kind), active: !general && !allWidgets && selected == kind) {
                                    selected = kind; general = false; allWidgets = false
                                }
                            }
                            Divider().padding(.vertical, 8)
                            sidebarRow("Ajustes gerais", symbol: "gearshape.fill", color: .gray, active: general) { general = true }
                        }
                    }
                }.padding(16).frame(width: 190)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if general { Text("Ajustes gerais").font(.title2.bold()); generalSettings }
                        else {
                            ForEach(allWidgets ? categories : categories.filter { $0 == selected }) { kind in
                                catalogue(kind)
                            }
                            if categories.isEmpty { Text("Nenhum widget encontrado.").foregroundStyle(.secondary) }
                            if !allWidgets {
                                DisclosureGroup("Personalizar " + selected.title) { widgetSettings.padding(.top, 16) }
                            }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 22)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
                    }
                }
            }
            Divider()
            HStack {
                Text(store.layoutMessage.isEmpty ? "Arraste um widget para a Mesa. Escolha o tamanho pela prévia." : store.layoutMessage)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: finishEditing) { Text("Concluído").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 15).padding(.vertical, 7).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }.background(SettingsSidebarMaterial())
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onAppear { previewEntrance.finish() }
            .onReceive(NotificationCenter.default.publisher(for: .loockSelectMusic)) { _ in selected = .music; general = false; allWidgets = false }
    }
    private func catalogue(_ kind: WidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).font(.headline)
            ForEach(variants(kind), id: \.self) { variant in
                Text(variantTitle(kind, variant)).font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { proxy in
                    let scale = min(0.75, max(0.25, (proxy.size.width - 32) / 852))
                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach(availableSizes(kind, variant)) { size in
                            VStack(spacing: 10) {
                                DraggableWidgetPreview(face: WidgetFace(variant: variant, entrance: previewEntrance, preview: true, kind: kind, size: size, store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda), payload: GalleryWidgetPayload(kind: kind, size: size, variant: variant))
                                    .frame(width: size.dimensions.width, height: size.dimensions.height)
                                    .scaleEffect(scale).frame(width: size.dimensions.width * scale, height: size.dimensions.height * scale)
                                    .accessibilityLabel("Arrastar " + kind.title + " " + size.rawValue)
                                    .overlay(alignment: .topLeading) {
                                        Button {
                                            let screen = NSScreen.main?.visibleFrame ?? .zero
                                            let point = CGPoint(x: screen.minX + size.dimensions.width / 2 + 24, y: screen.maxY - size.dimensions.height / 2 - 24)
                                            NotificationCenter.default.post(name: .loockGalleryDrop, object: GalleryWidgetPayload(kind: kind, size: size, variant: variant), userInfo: ["point": point])
                                        } label: {
                                            Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                                .frame(width: 26, height: 26).background(Color.green, in: Circle())
                                        }.buttonStyle(.plain).offset(x: -6, y: -6)
                                            .accessibilityLabel("Adicionar " + kind.title + " " + size.rawValue)
                                    }

                                Text(size.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }.frame(height: 285)
            }
            Divider()
        }
    }
    private func variants(_ kind: WidgetKind) -> [String] {
        kind == .clock ? ["analog", "digital"] : kind == .calendar ? ["month", "date"] : ["standard"]
    }
    private func availableSizes(_ kind: WidgetKind, _ variant: String) -> [WidgetSize] {
        if kind == .calendar && variant == "date" { return [.medium] }
        if kind == .clock && variant == "digital" { return [.small, .medium] }
        return WidgetSize.allCases
    }
    private func variantTitle(_ kind: WidgetKind, _ variant: String) -> String {
        switch variant { case "analog": return "Analógico"; case "digital": return "Digital"; case "month": return "Mês e eventos"; case "date": return "Data"; default: return kind.title }
    }
    private func settingToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack { Text(title); Spacer(); Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch) }
    }
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("Inicialização") {
                settingToggle("Abrir ao iniciar sessão", value: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                Text("Inicia os widgets automaticamente ao entrar na sua conta do Mac.").font(.caption).foregroundStyle(.secondary)
                if login.needsApproval {
                    Text("Aguardando autorização nos Ajustes do Sistema.").font(.caption)
                    Button("Abrir Itens de Início") { login.openSettings() }
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.onAppear { login.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
            settingsGroup("Aparência") {
                Picker("Estilo", selection: Binding(get: { store.preferences.appearance ?? .original }, set: { store.preferences.appearance = $0 })) {
                    ForEach(WidgetAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Picker("Superfície", selection: Binding(get: { store.preferences.surface ?? .frosted }, set: { store.preferences.surface = $0 })) {
                    ForEach(WidgetSurface.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Original mantém o fundo sólido. Fosco usa o material translúcido nativo do macOS.").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { store.preferences.unifiedFrostIntensity ?? 0.7 }, set: { store.preferences.unifiedFrostIntensity = $0 }), in: 0...1) { Text("Intensidade do fundo") }
                Divider()
                settingToggle("Fosco fora da Mesa", value: Binding(get: { store.preferences.frostedOutsideDesktop == true }, set: { store.preferences.frostedOutsideDesktop = $0 }))
                Text("Ao usar outro app, aplica uma camada fosca translúcida e suaviza as cores sem transformar os widgets em preto e branco.").font(.caption).foregroundStyle(.secondary)
            }
            settingsGroup("Interação") {
                settingToggle("Abrir o app ao clicar no widget", value: Binding(get: { store.preferences.opensAppsOnClick != false }, set: { store.preferences.opensAppsOnClick = $0 }))
                Divider()
                settingToggle("Travar posições", value: $store.preferences.positionsLocked)
                Divider()
                HStack { Text("Posições na Mesa"); Spacer(); Button("Reorganizar") { store.resetPositions() } }
            }
            Text("Desativar a abertura dos apps mantém o arrasto e o botão de remover funcionando. Conclua a edição para ocultar a grade.").font(.caption).foregroundStyle(.secondary)
        }.toggleStyle(.switch)
    }
    private var widgetSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("Aparência individual") {
                Picker("Cores", selection: Binding<WidgetAppearance?>(get: { store.preferences.individualAppearance?[selected.rawValue] }, set: { style in
                    var values = store.preferences.individualAppearance ?? [:]
                    values[selected.rawValue] = style
                    store.preferences.individualAppearance = values
                })) {
                    Text(selected == .weather ? "Cores do tempo" : "Usar cores gerais").tag(Optional<WidgetAppearance>.none)
                    ForEach(WidgetAppearance.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Divider()
                Picker("Fundo", selection: Binding<WidgetSurface?>(get: { store.preferences.individualSurface?[selected.rawValue] }, set: { style in
                    var values = store.preferences.individualSurface ?? [:]
                    values[selected.rawValue] = style
                    store.preferences.individualSurface = values
                })) {
                    Text("Usar fundo geral").tag(Optional<WidgetSurface>.none)
                    ForEach(WidgetSurface.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                if store.preferences.surfaceStyle(selected) == .frosted {
                    Slider(value: Binding(get: { store.preferences.frostAmount(selected) }, set: { amount in
                        var values = store.preferences.individualIntensity ?? [:]; values[selected.rawValue] = amount; store.preferences.individualIntensity = values
                    }), in: 0...1) { Text("Intensidade") }
                }
                Text("Escolha Branco ou Preto nas cores e Original ou Fosco no fundo. O Clima Original mantém as cores do tempo.").font(.caption).foregroundStyle(.secondary)
            }
            settingsGroup("Opções") { options }
            Text("Arraste outra prévia para substituir o tamanho ou modelo deste widget. Há uma instância por categoria na Mesa.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 13, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }.font(.system(size: 13))
    }
    private func settingsIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 27, height: 27).background(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 6))
    }
    private func sidebarRow(_ title: String, symbol: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { settingsIcon(symbol, color: color); Text(title).font(.system(size: 13)); Spacer() }
                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(active ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
    private func iconColor(_ kind: WidgetKind) -> Color {
        switch kind { case .screenTime: return .purple; case .music: return .pink; case .headphones, .macBattery: return .green; case .weather: return .blue; case .clock: return .gray; case .calendar: return .red; case .reminders: return .orange; case .notes: return .yellow }
    }
    @ViewBuilder private var options: some View {
        switch selected {
        case .screenTime:
            Text("O Ventura não fornece ao Loock o relatório geral do Tempo de Uso. Este widget indica a indisponibilidade, sem dados fictícios.").font(.caption)
            Button("Abrir Tempo de Uso") { openWidgetApp(.screenTime) }
        case .music: MusicOptions(store: store, media: MusicService.shared)
        case .headphones:
            VStack(alignment: .leading, spacing: 9) {
                Text(devices.macModelDescription).font(.caption).foregroundStyle(.secondary)
                Text("Mac: " + devices.powerStatus + " · " + bluetooth.status).font(.system(size: 12, weight: .medium))
                Text("Leitura de bateria dos dispositivos conectados informada pelo macOS. Só aparecem dispositivos e partes com carga disponível.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(bluetooth.refreshing ? "Consultando…" : "Atualizar bateria") { bluetooth.refresh() }.disabled(bluetooth.refreshing)
                    Toggle("Prévia com dados simulados", isOn: $store.preferences.demoHeadphones).font(.caption)
                }
                if let updated = bluetooth.updated { Text("Consulta: \(updated.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
            }
        case .macBattery:
            VStack(alignment: .leading, spacing: 9) {
                Text(devices.powerStatus).font(.headline)
                Text("Dados reais do Mac. Atualiza ao mudar o estado da energia e a cada 15 segundos.").font(.caption).foregroundStyle(.secondary)
                Button("Atualizar") { devices.refresh() }
            }
        case .weather:
            VStack(alignment: .leading, spacing: 9) {
                Picker("Cidade", selection: $store.preferences.city) { ForEach(WeatherCity.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 270)
                Toggle("Usar previsão online", isOn: $store.preferences.liveWeather).font(.caption)
                Text("As cores acompanham dia/noite, nuvens, chuva e névoa na cidade selecionada.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Atualizar") { weather.refresh() }; Link("Dados: Open-Meteo ↗", destination: URL(string: "https://open-meteo.com/")!).foregroundStyle(.blue) }
            }
        case .calendar:
            VStack(alignment: .leading, spacing: 9) {
                Text(agenda.status).font(.caption).foregroundStyle(.secondary)
                Button(agenda.connected ? "Atualizar eventos" : "Conectar agenda do Mac…") { if agenda.connected { agenda.refresh() } else { agenda.connect() } }
                Text("O mês e a data funcionam sem permissão. Eventos são opcionais e somente lidos.").font(.caption).foregroundStyle(.secondary)
            }
        case .reminders:
            VStack(alignment: .leading, spacing: 9) {
                Text(agenda.remindersStatus).font(.caption)
                Button(agenda.remindersConnected ? "Atualizar lembretes" : "Conectar Lembretes do Mac…") {
                    if agenda.remindersConnected { agenda.refreshReminders() } else { agenda.connectReminders() }
                }
                Text("Mostra lembretes pendentes de todas as listas. Somente leitura.").font(.caption).foregroundStyle(.secondary)
            }
        case .notes:
            VStack(alignment: .leading, spacing: 9) {
                Text(agenda.notesStatus).font(.caption).foregroundStyle(.secondary)
                Button(agenda.notesConnected ? "Atualizar nota do Mac" : "Conectar Notas da Apple…") { agenda.connectNotes() }
                if agenda.notesConnected { Button("Usar nota local") { agenda.disconnectNotes() } }
                TextField("Título local", text: Binding(get: { store.preferences.localNoteTitle ?? "" }, set: { store.preferences.localNoteTitle = $0; store.preferences.localNoteModified = Date() }))
                TextEditor(text: Binding(get: { store.preferences.localNoteBody ?? "" }, set: { store.preferences.localNoteBody = $0; store.preferences.localNoteModified = Date() }))
                    .frame(height: 110).overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))
                Text("Salvo automaticamente neste Mac.").font(.caption).foregroundStyle(.secondary)
            }
        case .clock:
            Text("Hora, data e fuso horário do Mac. Os ponteiros atualizam a cada segundo.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct GalleryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.primary).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.18), lineWidth: 0.5)).opacity(enabled ? 1 : 0.45)
    }
}

private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
