import SwiftUI

struct WidgetFace: View {
    var variant: String? = nil
    private var chosenVariant: String { variant ?? store.item(kind).variant ?? "analog" }
    private var outsideDesktopEffect: Bool { !preview && desktopInactive && store.preferences.frostedOutsideDesktop == true }
    private var frost: Bool { store.preferences.surfaceStyle(kind) == .frosted || outsideDesktopEffect }
    private var appearance: WidgetAppearance { store.preferences.appearanceStyle(kind) }
    private var styleToken: String {
        "\(appearance.rawValue)-\(store.preferences.surfaceStyle(kind).rawValue)"
    }
    var withdrawing = false
    var entryID = UUID()
    var entrance = WidgetEntranceState()
    var preview = false
    var desktopInactive = false
    var music = MusicService.shared
    let kind: WidgetKind
    let size: WidgetSize
    @ObservedObject var store: DeskStore
    @ObservedObject var devices: DeviceService
    let weather: WeatherService
    let bluetooth: BluetoothBatteryService
    let agenda: AgendaService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            switch kind {
            case .music: MusicWidget(size: size, store: store, media: music, appearance: appearance, forcedFrosted: frost)
            case .headphones: HeadphonesWidget(size: size, demo: store.preferences.demoHeadphones, bluetooth: bluetooth, devices: devices, light: appearance == .light, frosted: frost, monochrome: false)
            case .weather: WeatherWidget(size: size, city: store.preferences.city.rawValue, service: weather, appearance: appearance, frosted: frost)
            case .clock: ModernClockWidget(size: size, digital: chosenVariant == "digital", dark: appearance != .light, frosted: frost, lowPower: devices.lowPower, desktopInactive: outsideDesktopEffect)
            case .macBattery: MacBatteryWidget(size: size, devices: devices, light: appearance == .light, frosted: frost)
            case .reminders: RemindersWidget(size: size, agenda: agenda, light: appearance == .light, frosted: frost)
            case .notes: NotesWidget(size: size, store: store, agenda: agenda, light: appearance == .light, frosted: frost)
            case .screenTime: EmptyView()
            case .calendar: if chosenVariant == "date" { DateCardWidget(size: size, dark: appearance != .light, frosted: frost) } else { CalendarWidget(size: size, agenda: agenda, dark: appearance != .light, frosted: frost) }
            }
        }.environment(\.clearWidgetSurface, false)
            .environment(\.widgetPreview, preview)
            .saturation(store.preferences.monochrome ? 0 : (outsideDesktopEffect ? 0.94 : 1))
            .opacity(1)
            .frame(width: size.dimensions.width, height: size.dimensions.height)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: outsideDesktopEffect)
            .modifier(WidgetStyleChangeEffect(token: styleToken))
            .modifier(WidgetEntranceEffect(state: entrance))
            .environment(\.frostIntensity, outsideDesktopEffect ? min(0.82, max(0.58, store.preferences.frostAmount(kind))) : store.preferences.frostAmount(kind))
            .task(id: preview ? "preview-" + kind.rawValue + size.rawValue : entryID.uuidString + String(withdrawing)) {
                if preview { if entrance.progress != 1 { entrance.finish() } }
                else if withdrawing { entrance.withdraw(reduceMotion: reduceMotion) }
                else { entrance.appear(reduceMotion: reduceMotion) }
            }
            .onDisappear { if !preview { entrance.finish() } }
            .accessibilityElement(children: .contain)
    }
}

private struct WidgetStyleChangeEffect: ViewModifier {
    let token: String
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .blur(radius: reduceMotion ? 0 : (1 - progress) * 4)
            .scaleEffect(reduceMotion ? 1 : 0.985 + progress * 0.015)
            .opacity(0.76 + progress * 0.24)
            .onChange(of: token) { _ in
                guard !reduceMotion else { progress = 1; return }
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { progress = 0 }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.32)) { progress = 1 }
                }
            }
    }
}
struct HeadphonesWidget: View {
    let size: WidgetSize
    let demo: Bool
    let bluetooth: BluetoothBatteryService
    @ObservedObject var devices: DeviceService
    var light = false
    var frosted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var entries: [BatteryEntry] {
        BatteryEntry.entries(mac: devices.macBattery, charging: devices.charging, readings: demo
            ? [BluetoothReading(name: "FreeClip 2", overall: 86, left: nil, right: nil, caseLevel: nil)] : bluetooth.devices)
    }
    var monochrome = false
    private let capacity = 4
    private var visible: [BatteryEntry] { Array(entries.prefix(capacity)) }
    private var dimension: CGFloat { size == .small ? 57 : size == .medium ? 60 : 96 }
    var body: some View {
        Group {
            if size == .small && devices.lowPower && entries.count == 1 {
                VStack(alignment: .leading, spacing: 17) {
                    BatteryRing(symbol: "laptopcomputer", value: devices.macBattery, dimension: 55, charging: devices.charging, light: light, lowPower: true)
                    AnimatedValue(value: "\(devices.macBattery ?? 0)%").font(.system(size: 36, weight: .regular))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            } else if size == .medium {
                HStack(spacing: 0) {
                    ForEach(0..<capacity, id: \.self) { slot($0).frame(maxWidth: .infinity) }
                }.padding(.horizontal, 17)
            } else if size == .large {
                GeometryReader { geometry in
                    ForEach(0..<4, id: \.self) { index in
                        slot(index)
                            .position(x: geometry.size.width * (index % 2 == 0 ? 0.25 : 0.75),
                                      y: geometry.size.height * (index < 2 ? 0.25 : 0.75) + 20)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 17) {
                    ForEach(0..<capacity, id: \.self) { slot($0) }
                }.padding(.horizontal, 15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if demo { Text("DEMO").font(.system(size: 7)).opacity(0.55).padding(10) }
            else if entries.count > capacity { Text("+\(entries.count - capacity)").font(.system(size: 9)).padding(10) }
        }
        .foregroundStyle(light ? .black : .white)
        .background(HarmonizedCardBackground(light: light, frosted: frosted))
    }
    private func slot(_ index: Int) -> some View {
        let entry = index < visible.count ? visible[index] : nil
        return VStack(spacing: size == .large ? 12 : 14) {
            BatteryRing(symbol: entry?.symbol ?? "", value: entry?.value, dimension: dimension,
                freeClip: entry?.freeClip ?? false, charging: entry?.charging ?? false,
                light: light, monochrome: monochrome, lowPower: entry?.symbol == "laptopcomputer" && devices.lowPower)
            if size != .small {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    AnimatedValue(value: entry.map { String($0.value) } ?? "0")
                        .font(.system(size: size == .large ? 23 : 21, weight: .regular))
                        .monospacedDigit().tracking(-0.4)
                    Text("%")
                        .font(.system(size: size == .large ? 19 : 17, weight: .regular))
                }
                // Identical metrics for occupied and empty slots keep both rows centered.
                .frame(height: size == .large ? 28 : 26, alignment: .center)
                .opacity(entry == nil ? 0 : 1)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.map { "\($0.label), \($0.value) por cento" } ?? "Posição livre")
    }
}

struct MacBatteryWidget: View {
    let size: WidgetSize
    @ObservedObject var devices: DeviceService
    var light = false
    var frosted = false
    var body: some View {
        Group {
            if size == .medium {
                HStack(spacing: 23) {
                    BatteryRing(symbol: "laptopcomputer", value: devices.macBattery, dimension: 98, charging: devices.charging, light: light)
                    VStack(alignment: .leading, spacing: 6) { details }
                    Spacer(minLength: 0)
                }.padding(23)
            } else {
                VStack(alignment: .leading, spacing: size == .large ? 18 : 6) {
                    BatteryRing(symbol: "laptopcomputer", value: devices.macBattery, dimension: size == .large ? 166 : 65, charging: devices.charging, light: light)
                        .frame(maxWidth: .infinity).padding(.top, size == .large ? 12 : 0)
                    details
                }.padding(size == .large ? 26 : 17)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).foregroundStyle(light ? .black : .white)
            .background(HarmonizedCardBackground(light: light, frosted: frosted))
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(devices.macBattery.map { "\($0)%" } ?? "—").font(.system(size: size == .large ? 48 : 32, weight: .light, design: .rounded))
                if size == .small { Spacer(); Text("MAC").font(.system(size: 8, weight: .semibold)).opacity(0.6) }
            }
            if size != .small { Text("MacBook Pro").font(.system(size: 14, weight: .medium)) }
            Text(devices.powerStatus).font(.system(size: size == .small ? 9 : 11)).opacity(0.65).lineLimit(1)
        }
    }
}
struct ClockWidget: View {
    let size: WidgetSize
    var dark = false
    var frosted = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Group {
                if size == .small {
                    AnalogClock(date: timeline.date, dark: frosted ? false : dark).padding(7)
                } else if size == .medium {
                    HStack(spacing: 19) {
                        AnalogClock(date: timeline.date, dark: frosted ? false : dark).frame(width: 140, height: 140)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("HORA LOCAL").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                            AnimatedValue(value: timeline.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())).font(.system(size: 32, weight: .light)).monospacedDigit()
                            Text(timeline.date, format: .dateTime.day().month(.abbreviated)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(12)
                } else {
                    VStack(spacing: 9) {
                        AnalogClock(date: timeline.date, dark: frosted ? false : dark).frame(width: 265, height: 265)
                        Text(timeline.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }.padding(15)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(dark ? .white : .black).background(HarmonizedCardBackground(light: !dark, frosted: frosted)).environment(\.locale, Locale(identifier: "pt_BR"))
    }
}
struct WeatherWidget: View {
    let size: WidgetSize
    let city: String
    @ObservedObject var service: WeatherService
    var appearance: WidgetAppearance = .original
    var frosted = false
    private var light: Bool { appearance == .light }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = service.snapshot {
                if size == .small {
                    Text(city).font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text("\(data.temperature)°").font(.system(size: 44, weight: .light)).padding(.top, -1)
                    Spacer(minLength: 2)
                    Image(systemName: WeatherSnapshot.symbol(data.code, isDay: data.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 17))
                    Text(WeatherSnapshot.description(data.code)).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("Máx. \(data.high)°  Mín. \(data.low)°").font(.system(size: 10, weight: .medium))
                    sourceLabel.padding(.top, 4)
                } else {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(city).font(.system(size: 18, weight: .medium))
                            Text("\(data.temperature)°").font(.system(size: size == .large ? 45 : 32, weight: .light))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Image(systemName: WeatherSnapshot.symbol(data.code, isDay: data.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 22))
                            Text(WeatherSnapshot.description(data.code)).font(.system(size: 10)).lineLimit(1)
                            Text("Máx. \(data.high)°  Mín. \(data.low)°").font(.system(size: 10))
                        }.padding(.top, 2)
                    }
                    if size == .large { Divider().overlay((light ? Color.black : .white).opacity(0.2)).padding(.vertical, 9) }
                    HStack {
                        ForEach(Array(data.hours.enumerated()), id: \.offset) { _, hour in
                            VStack(spacing: 5) {
                                Text(hour.label).font(.system(size: 10, weight: .medium)).foregroundStyle((light ? Color.black : .white).opacity(0.75))
                                Image(systemName: WeatherSnapshot.symbol(hour.code, isDay: hour.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 15))
                                Text("\(hour.temperature)°").font(.system(size: 13, weight: .medium))
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    if size == .large {
                        Divider().overlay((light ? Color.black : .white).opacity(0.2)).padding(.vertical, 10)
                        VStack(spacing: 10) {
                            ForEach(Array((data.days.count > 4 ? Array(data.days.dropFirst().prefix(4)) : data.days).enumerated()), id: \.offset) { _, day in
                                HStack(spacing: 10) {
                                    Text(day.label).frame(width: 56, alignment: .leading)
                                    Image(systemName: WeatherSnapshot.symbol(day.code)).symbolRenderingMode(.multicolor).frame(width: 22)
                                    Text("\(day.low)°").foregroundStyle((light ? Color.black : .white).opacity(0.65)).frame(width: 26)
                                    TemperatureRange(low: day.low, high: day.high, minimum: data.days.map(\.low).min() ?? day.low, maximum: data.days.map(\.high).max() ?? day.high)
                                    Text("\(day.high)°").frame(width: 26)
                                }.font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                    Spacer(minLength: 2)
                    sourceLabel.padding(.top, 4)
                }
            } else {
                Text(city).font(.headline)
                Spacer()
                Image(systemName: "cloud").font(.largeTitle)
                Text("—").font(.largeTitle)
                Text(service.status).font(.caption)
                Spacer()
            }
        }.padding(size == .small ? 15 : 16).foregroundStyle(light ? .black : .white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if frosted { HarmonizedCardBackground(light: light, frosted: true).transition(.opacity) }
                else if appearance == .original { WeatherBackground(snapshot: service.snapshot).transition(.opacity) }
                else { HarmonizedCardBackground(light: light, frosted: false).transition(.opacity) }
            }
    }
    private var sourceLabel: some View {
        Text(service.status).font(.system(size: 8, weight: .medium)).foregroundStyle((light ? Color.black : .white).opacity(0.65)).lineLimit(1)
    }
}

struct RemindersWidget: View {
    let size: WidgetSize
    let agenda: AgendaService
    var light = false
    var frosted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "list.bullet").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white).frame(width: 39, height: 39).background(.orange, in: Circle())
                Spacer()
                Text(agenda.remindersConnected ? "\(agenda.reminders.count)" : "—")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
            if size != .small && agenda.remindersConnected {
                ForEach(Array(agenda.reminders.prefix(size == .large ? 6 : 1).enumerated()), id: \.offset) { _, title in
                    HStack(spacing: 8) {
                        Circle().stroke(.gray.opacity(0.5), lineWidth: 1).frame(width: 13, height: 13)
                        Text(title).font(.system(size: 12)).lineLimit(1)
                    }
                }
            }
            Text("Lembretes").font(.system(size: 14, weight: .bold)).foregroundStyle(.orange)
            Text(agenda.remindersStatus).font(.system(size: 11, weight: .medium)).opacity(0.6).lineLimit(1)
        }.padding(17).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(light ? .black : .white).background(HarmonizedCardBackground(light: light, frosted: frosted))
    }
}
struct NotesWidget: View {
    @Environment(\.clearWidgetSurface) private var clearSurface
    let size: WidgetSize
    @ObservedObject var store: DeskStore
    let agenda: AgendaService
    var light = false
    var frosted = false
    private var title: String { let t = agenda.notesConnected ? agenda.noteTitle : store.preferences.localNoteTitle ?? ""; return t.isEmpty ? "Nova Nota" : t }
    private var text: String { let t = agenda.notesConnected ? agenda.noteText : store.preferences.localNoteBody ?? ""; return t.isEmpty ? "Nenhum texto adicional" : t }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                Text("Notas").fontWeight(.semibold)
                Spacer()
            }.font(.system(size: 12)).foregroundStyle(.white).padding(.horizontal, 16)
                .frame(height: size == .large ? 52 : 40)
                .background { if !clearSurface { LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)], startPoint: .top, endPoint: .bottom) } }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(text).font(.system(size: 12)).opacity(0.6).lineLimit(size == .large ? 10 : size == .medium ? 2 : 3)
                Spacer(minLength: 0)
                if agenda.notesConnected {
                    Text("Notas da Apple").font(.system(size: 10)).opacity(0.55)
                } else if let date = store.preferences.localNoteModified {
                    Text(date, format: .dateTime.day().month().year()).font(.system(size: 10)).opacity(0.55)
                } else {
                    Text("Edite no Loock").font(.system(size: 10)).opacity(0.55)
                }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.foregroundStyle(light ? .black : .white).background(HarmonizedCardBackground(light: light, frosted: frosted))
    }
}
