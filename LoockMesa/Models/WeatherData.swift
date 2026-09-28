import Foundation

struct ForecastHour { var label: String; var temperature: Int; var code: Int; var isDay: Bool = true }
struct ForecastDay { var label: String; var low: Int; var high: Int; var code: Int }
struct WeatherSnapshot {
    var temperature: Int
    var code: Int
    var low: Int
    var high: Int
    var hours: [ForecastHour]
    var days: [ForecastDay]
    var isDay = true
    static let demo = WeatherSnapshot(temperature: 21, code: 2, low: 16, high: 24,
        hours: [ForecastHour(label: "Agora", temperature: 21, code: 2), ForecastHour(label: "15", temperature: 23, code: 2), ForecastHour(label: "16", temperature: 24, code: 0), ForecastHour(label: "17", temperature: 22, code: 0), ForecastHour(label: "18", temperature: 20, code: 3)],
        days: [ForecastDay(label: "Hoje", low: 16, high: 24, code: 2), ForecastDay(label: "Amanhã", low: 15, high: 22, code: 61), ForecastDay(label: "Qua", low: 14, high: 23, code: 2), ForecastDay(label: "Qui", low: 17, high: 26, code: 0)])
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        if !isDay {
            switch code { case 0, 1: return "moon.stars.fill"; case 2: return "cloud.moon.fill"; case 45, 48: return "moon.haze.fill"; default: break }
        }
        switch code { case 0, 1: return "sun.max.fill"; case 2: return "cloud.sun.fill"; case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"; case 71...77, 85, 86: return "cloud.snow.fill"; case 95...99: return "cloud.bolt.rain.fill"; default: return "cloud.rain.fill" }
    }
    static func description(_ code: Int) -> String {
        switch code { case 0, 1: return "Céu limpo"; case 2: return "Parcialmente nublado"; case 3: return "Nublado"
        case 45, 48: return "Névoa"; case 71...77, 85, 86: return "Neve"; case 95...99: return "Trovoadas"; default: return "Chuva" }
    }
}
struct ForecastResponse: Decodable {
    struct Current: Decodable { let time: String; let temperature_2m: Double; let weather_code: Int; let is_day: Int? }
    struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int]? }
    struct Daily: Decodable { let time: [String]; let temperature_2m_min: [Double]; let temperature_2m_max: [Double]; let weather_code: [Int] }
    let current: Current; let hourly: Hourly; let daily: Daily
    func snapshot() throws -> WeatherSnapshot {
        guard let low = daily.temperature_2m_min.first, let high = daily.temperature_2m_max.first,
              low.isFinite, high.isFinite, current.temperature_2m.isFinite else { throw URLError(.cannotParseResponse) }
        let start = hourly.time.firstIndex { String($0.prefix(13)) >= String(current.time.prefix(13)) } ?? 0
        let hourEnd = min(start + 6, hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count)
        guard hourEnd >= start else { throw URLError(.cannotParseResponse) }
        let hours = (start..<hourEnd).compactMap { i -> ForecastHour? in
            guard hourly.temperature_2m[i].isFinite else { return nil }
            return ForecastHour(label: i == start ? "Agora" : String(hourly.time[i].dropFirst(11).prefix(2)), temperature: Int(hourly.temperature_2m[i].rounded()), code: hourly.weather_code[i], isDay: hourly.is_day.flatMap { $0.indices.contains(i) ? $0[i] == 1 : nil } ?? (current.is_day != 0))
        }
        let count = min(5, daily.time.count, daily.temperature_2m_min.count, daily.temperature_2m_max.count, daily.weather_code.count)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "pt_BR"); formatter.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter(); output.locale = Locale(identifier: "pt_BR"); output.dateFormat = "EEE"
        let days = (0..<count).compactMap { i -> ForecastDay? in
            guard daily.temperature_2m_min[i].isFinite, daily.temperature_2m_max[i].isFinite else { return nil }
            let name = i == 0 ? "Hoje" : (formatter.date(from: daily.time[i]).map { output.string(from: $0).capitalized } ?? "—")
            return ForecastDay(label: name, low: Int(daily.temperature_2m_min[i].rounded()), high: Int(daily.temperature_2m_max[i].rounded()), code: daily.weather_code[i])
        }
        return WeatherSnapshot(temperature: Int(current.temperature_2m.rounded()), code: current.weather_code, low: Int(low.rounded()), high: Int(high.rounded()), hours: hours, days: days, isDay: current.is_day != 0)
    }
}

enum WeatherMood: String {
    case sunny, cloudy, rain, clearNight, cloudyNight, fogNight, storm, snow
    static func resolve(code: Int, isDay: Bool) -> WeatherMood {
        if (95...99).contains(code) { return .storm }
        if (71...77).contains(code) || [85, 86].contains(code) { return .snow }
        if !isDay {
            if [45, 48].contains(code) { return .fogNight }
            return [0, 1].contains(code) ? .clearNight : .cloudyNight
        }
        if [0, 1, 2].contains(code) { return .sunny }
        if [3, 45, 48].contains(code) { return .cloudy }
        return .rain
    }
}
