import Foundation

struct MonthDay: Identifiable {
    let index: Int
    let date: Date?
    let number: Int?
    var id: String { "day-\(index)" }
}
enum MonthLayout {
    static func days(containing date: Date, calendar: Calendar = .current) -> [MonthDay] {
        guard let interval = calendar.dateInterval(of: .month, for: date), let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        // ISO-style Monday first, independent of a user's system language.
        let leading = (weekday + 5) % 7
        let count = ((leading + range.count + 6) / 7) * 7
        return (0..<count).map { index in
            let day = index - leading + 1
            guard range.contains(day), let d = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return MonthDay(index: index, date: nil, number: nil) }
            return MonthDay(index: index, date: d, number: day)
        }
    }
}
struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    var red: Double = 0.95
    var green: Double = 0.25
    var blue: Double = 0.25
}

/// The visible interval follows today's time or the first upcoming appointment.
enum AgendaTimeline {
    static func events(on day: Date, entries: [CalendarEntry], calendar: Calendar = .current) -> [CalendarEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return entries.filter { $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
    }
    static func startHour(day: Date, now: Date, entries: [CalendarEntry], calendar: Calendar = .current) -> Int {
        if calendar.isDate(day, inSameDayAs: now) { return min(21, calendar.component(.hour, from: now)) }
        return min(21, entries.first(where: { !$0.allDay }).map { calendar.component(.hour, from: $0.start) } ?? 9)
    }
    static func lane(for event: CalendarEntry, among events: [CalendarEntry]) -> (index: Int, count: Int) {
        var ends: [Date] = []
        var assigned = 0
        for item in events.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
            let lane = ends.firstIndex(where: { $0 <= item.start }) ?? ends.count
            if lane == ends.count { ends.append(item.end) } else { ends[lane] = item.end }
            if item.id == event.id { assigned = lane }
        }
        return (assigned, max(1, ends.count))
    }
}
