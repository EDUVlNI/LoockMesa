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
}
