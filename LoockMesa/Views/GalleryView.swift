import SwiftUI
import AppKit

struct GalleryView: View {
    @ObservedObject var store: DeskStore
    @ObservedObject var devices: DeviceService
    @ObservedObject var weather: WeatherService
    @ObservedObject var bluetooth: BluetoothBatteryService
    @ObservedObject var agenda: AgendaService
    var finishEditing: () -> Void = {}
    @StateObject private var login = LoginService()
    @StateObject private var previewEntrance = WidgetEntranceState()
    @State private var previewEntryID = UUID()
    @State private var selected: WidgetKind = .headphones
    @State private var general = true
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    settingsIcon("square.grid.2x2.fill", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loock Mesa").font(.headline)
                        Text("Ajustes dos widgets").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 20).padding(.horizontal, 10)
                sidebarRow("Geral", symbol: "gearshape.fill", color: .gray, active: general) { general = true }
                Text("Widgets").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 20).padding(.leading, 10).padding(.bottom, 5)
                ForEach(WidgetKind.allCases) { kind in
                    sidebarRow(kind.title, symbol: kind.symbol, color: iconColor(kind), active: !general && selected == kind) {
                        selected = kind; general = false
                    }
                }
                Spacer()
                Text("Loock Mesa 0.18 · Ventura").font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
            }.padding(10).frame(width: 220).frame(maxHeight: .infinity).background(SettingsSidebarMaterial())
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(general ? "Geral" : selected.title).font(.system(size: 21, weight: .bold))
                    Spacer()
                    Button("Concluído", action: finishEditing).keyboardShortcut(.defaultAction)
                }.padding(22)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if general { generalSettings } else { widgetSettings }
                    }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 850, minHeight: 650).buttonStyle(GalleryButtonStyle())
            .onReceive(NotificationCenter.default.publisher(for: .loockSelectMusic)) { _ in selected = .music; general = false }
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
                settingToggle("Preto e branco", value: $store.preferences.monochrome)
                Divider()
                settingToggle("Fundo fosco", value: Binding(get: { store.preferences.unifiedFrost != false }, set: { store.preferences.unifiedFrost = $0 }))
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Intensidade padrão"); Spacer(); Text("\(Int((store.preferences.unifiedFrostIntensity ?? 0.7) * 100))%").foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { store.preferences.unifiedFrostIntensity ?? 0.7 }, set: { store.preferences.unifiedFrostIntensity = $0; store.preferences.unifiedFrost = true }), in: 0...1)
                    HStack { Text("Transparente"); Spacer(); Text("Fosco") }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Padrão para widgets sem personalização. Cada widget pode ter seu próprio fosco. O clima mantém o fundo meteorológico.").font(.caption).foregroundStyle(.secondary)
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
            settingsGroup("Na Mesa") {
                Toggle("Mostrar " + selected.title, isOn: Binding(get: { store.item(selected).enabled }, set: { value in store.update(selected) { $0.enabled = value } })).toggleStyle(.switch)
                Divider()
                Picker("Tamanho", selection: Binding(get: { store.item(selected).size }, set: { value in store.update(selected) { $0.size = value } })) {
                    ForEach(WidgetSize.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if selected != .weather {
                settingsGroup("Fundo deste widget") {
                    settingToggle("Fosco", value: Binding(get: { store.preferences.usesFrost(selected) }, set: { value in
                        var values = store.preferences.individualFrost ?? [:]; values[selected.rawValue] = value; store.preferences.individualFrost = values
                    }))
                    HStack { Text("Intensidade"); Spacer(); Text("\(Int(store.preferences.frostAmount(selected) * 100))%") }
                    Slider(value: Binding(get: { store.preferences.frostAmount(selected) }, set: { value in
                        var values = store.preferences.individualIntensity ?? [:]; values[selected.rawValue] = value; store.preferences.individualIntensity = values
                        var flags = store.preferences.individualFrost ?? [:]; flags[selected.rawValue] = true; store.preferences.individualFrost = flags
                    }), in: 0...1)
                    HStack { Text("Transparente").font(.caption); Spacer(); Button("Usar padrão geral") {
                        store.preferences.individualFrost?.removeValue(forKey: selected.rawValue)
                        store.preferences.individualIntensity?.removeValue(forKey: selected.rawValue)
                    } }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.035))
                WidgetFace(entryID: previewEntryID, entrance: previewEntrance, kind: selected, size: store.item(selected).size, store: store, devices: devices, weather: weather, bluetooth: bluetooth, agenda: agenda)
                    .overlay(alignment: .topLeading) {
                        Button { store.update(selected) { $0.enabled = true } } label: {
                            Image(systemName: store.item(selected).enabled ? "checkmark" : "plus")
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 27, height: 27).background(store.item(selected).enabled ? Color.gray : Color.green, in: Circle())
                        }.buttonStyle(.plain).disabled(store.item(selected).enabled).offset(x: -8, y: -8)
                            .accessibilityLabel("Adicionar " + selected.title)
                    }
            }.frame(height: store.item(selected).size == .large ? 382 : 216)
            settingsGroup("Opções") { options }
            HStack { Button("Abrir app do Mac") { openWidgetApp(selected) }; Spacer(); Button("Ajustar aparência") { general = true } }
            if !store.layoutMessage.isEmpty { Text(store.layoutMessage).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 13, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
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
        switch kind { case .music: return .pink; case .headphones, .macBattery: return .green; case .weather: return .blue; case .clock: return .gray; case .calendar: return .red; case .reminders: return .orange; case .notes: return .yellow }
    }
    @ViewBuilder private var options: some View {
        switch selected {
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
