import SwiftUI

struct CalendarWidget: View {
    let size: WidgetSize
    @ObservedObject var agenda: AgendaService
    var dark = false
    var frosted = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                switch size {
                case .small: month(context.date, compact: true)
                case .medium:
                    HStack(alignment: .top, spacing: 17) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.date, format: .dateTime.weekday(.wide)).textCase(.uppercase).font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                            Text(context.date, format: .dateTime.day()).font(.system(size: 47, weight: .light))
                            events(limit: 1)
                        }.frame(width: 132, alignment: .leading)
                        month(context.date, compact: true)
                    }
                case .large, .wide, .extraWide:
                    VStack(alignment: .leading, spacing: 13) {
                        month(context.date, compact: false)
                        Divider()
                        events(limit: 2)
                    }
                }
            }.padding(size == .small ? 14 : 18)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HarmonizedCardBackground(light: !dark, frosted: frosted)).foregroundStyle(dark ? .white : .black).environment(\.locale, Locale(identifier: "pt_BR"))
    }
    private func month(_ date: Date, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text(date, format: .dateTime.month(.wide)).textCase(.uppercase)
                .font(.system(size: compact ? 11 : 15, weight: .semibold)).foregroundStyle(.red)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: compact ? 3 : 6) {
                ForEach(Array(["S", "T", "Q", "Q", "S", "S", "D"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: compact ? 8 : 10, weight: .medium)).foregroundStyle(.gray)
                }
                ForEach(MonthLayout.days(containing: date)) { cell in
                    let today = cell.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                    Text(cell.number.map(String.init) ?? " ")
                        .font(.system(size: compact ? 10 : 13, weight: today ? .bold : .regular)).monospacedDigit()
                        .frame(maxWidth: .infinity).frame(height: compact ? 15 : 23)
                        .foregroundStyle(today || dark ? .white : .black)
                        .background { if today { Circle().fill(.red).frame(width: compact ? 17 : 25, height: compact ? 17 : 25) } }
                }
            }
        }
    }
    @ViewBuilder private func events(limit: Int) -> some View {
        if agenda.entries.isEmpty {
            Text(agenda.status).font(.system(size: 10)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agenda.entries.filter { $0.end > Date() }.prefix(limit)) { event in
                    HStack(alignment: .top, spacing: 7) {
                        Capsule().fill(.red).frame(width: 3, height: limit == 1 ? 30 : 29)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text(event.allDay ? "Dia inteiro" : event.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

private extension CalendarEntry {
    var tint: Color { Color(red: red, green: green, blue: blue) }
}

struct DateAgendaWidget: View {
    let size: WidgetSize
    @ObservedObject var agenda: AgendaService
    var dark: Bool
    var frosted: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { time in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(time.date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(.red)
                        Text(time.date, format: .dateTime.month(.abbreviated)).foregroundStyle(.secondary)
                    }.font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(time.date, format: .dateTime.day()).font(.system(size: 91, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.7)
                }.frame(maxWidth: size == .small ? .infinity : 122, alignment: size == .small ? .center : .leading)
                if size != .small {
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(time.date, format: .dateTime.month(.wide).year()).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        week(time.date)
                        Spacer(minLength: 0)
                        if let next = agenda.entries.first(where: { $0.end > time.date }) {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(next.tint).frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(next.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    Text(next.allDay ? "Dia inteiro" : next.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if !next.allDay && next.start > time.date && next.start.timeIntervalSince(time.date) < 3600 {
                                    Text("\(max(1, Int(next.start.timeIntervalSince(time.date) / 60))) min")
                                        .font(.system(size: 8, weight: .semibold)).padding(4).background(next.tint.opacity(0.15), in: Capsule())
                                }
                            }.frame(height: 32)
                        } else {
                            Text(agenda.connected ? "Sem próximos eventos" : "Conecte sua agenda")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }.padding(17)
        }.foregroundStyle(dark ? .white : .black)
            .background(HarmonizedCardBackground(light: !dark, frosted: frosted))
            .environment(\.locale, Locale(identifier: "pt_BR"))
    }
    private func week(_ now: Date) -> some View {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: now) + 5) % 7), to: calendar.startOfDay(for: now))!
        return HStack(spacing: 1) {
            ForEach(0..<7) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                let today = calendar.isDate(day, inSameDayAs: now)
                VStack(spacing: 5) {
                    Text(["S", "T", "Q", "Q", "S", "S", "D"][offset]).font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(day, format: .dateTime.day()).font(.system(size: 10, weight: today ? .bold : .regular))
                        .frame(width: 19, height: 19).background { if today { Circle().fill(.red) } }.foregroundStyle(today ? .white : (dark ? .white : .black))
                    Circle().fill(agenda.entries.contains { $0.start < calendar.date(byAdding: .day, value: 1, to: day)! && $0.end > day } ? Color.secondary : .clear).frame(width: 3, height: 3)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

struct ScheduleWidget: View {
    let size: WidgetSize
    @ObservedObject var agenda: AgendaService
    var dark: Bool
    var frosted: Bool
    private var count: Int { size == .extraWide ? 5 : size == .wide ? 4 : size == .small ? 1 : 2 }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { time in
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    if index > 0 { Divider() }
                    dayColumn(Calendar.current.date(byAdding: .day, value: index, to: time.date)!, now: time.date, index: index)
                }
            }.padding(14)
        }.foregroundStyle(dark ? .white : .black)
            .background(HarmonizedCardBackground(light: !dark, frosted: frosted))
            .environment(\.locale, Locale(identifier: "pt_BR"))
    }
    private func dayColumn(_ day: Date, now: Date, index: Int) -> some View {
        let events = AgendaTimeline.events(on: day, entries: agenda.entries)
        let hour = AgendaTimeline.startHour(day: day, now: now, entries: events)
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let end = start.addingTimeInterval(3 * 3600)
        let timed = events.filter { !$0.allDay && $0.start < end && $0.end > start }
        return VStack(alignment: .leading, spacing: 3) {
            Text(index == 1 && count == 2 ? "AMANHÃ" : day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "pt_BR"))).uppercased())
                .font(.system(size: 8, weight: .bold)).foregroundStyle(index == 0 ? Color.red : .secondary).lineLimit(1)
            Text(day, format: .dateTime.day()).font(.system(size: 25, weight: .medium))
            if let allDay = events.first(where: { $0.allDay }) {
                Text(allDay.title).font(.system(size: 8, weight: .medium)).lineLimit(1).padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading).background(allDay.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
            }
            GeometryReader { geometry in
                let height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<3) { row in
                        HStack(alignment: .top, spacing: 3) {
                            Text("\(hour + row)").font(.system(size: 7)).foregroundStyle(.secondary).frame(width: 12)
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                        }.offset(y: CGFloat(row) * height / 3)
                    }
                    ForEach(timed) { event in
                        let lane = AgendaTimeline.lane(for: event, among: timed)
                        let width = max(1, (geometry.size.width - 17) / CGFloat(lane.count))
                        let top = max(0, event.start.timeIntervalSince(start) / 10800) * height
                        let bottom = min(1, event.end.timeIntervalSince(start) / 10800) * height
                        HStack(spacing: 3) {
                            Rectangle().fill(event.tint).frame(width: 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(.system(size: 8, weight: .semibold)).lineLimit(1)
                                if bottom - top >= 22 { Text(event.start, style: .time).font(.system(size: 7)).lineLimit(1) }
                            }
                            Spacer(minLength: 0)
                        }.frame(width: width - 2, height: max(12, bottom - top - 2), alignment: .leading)
                            .background(event.tint.opacity(dark ? 0.30 : 0.14), in: RoundedRectangle(cornerRadius: 3))
                            .offset(x: 16 + CGFloat(lane.index) * width, y: min(top, max(0, height - 12)))
                    }
                    if index == 0 {
                        let fraction = now.timeIntervalSince(start) / 10800
                        if fraction >= 0 && fraction <= 1 {
                            HStack(spacing: 0) { Circle().fill(.red).frame(width: 4, height: 4); Rectangle().fill(.red).frame(height: 1) }
                                .offset(y: fraction * height)
                        }
                    }
                    if events.isEmpty {
                        Text(agenda.connected ? "Sem eventos" : "Conecte sua agenda")
                            .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.clipped()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
