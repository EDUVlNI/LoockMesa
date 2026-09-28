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
                case .large:
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
                ForEach(agenda.entries.prefix(limit)) { event in
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
