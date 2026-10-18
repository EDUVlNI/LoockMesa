import Foundation

struct ForecastHour { var label: String; var temperature: Int; var code: Int; var isDay: Bool = true; var date: Date? = nil; var eventSymbol: String? = nil
    var symbol: String { eventSymbol ?? WeatherSnapshot.symbol(code, isDay: isDay) }
}
struct ForecastDay { var label: String; var low: Int; var high: Int; var code: Int }
struct WeatherSnapshot {
    var temperature: Int
    var code: Int
    var low: Int
    var high: Int
    var hours: [ForecastHour]
    var days: [ForecastDay]
    var isDay = true
    var precipitation: Double? = nil
    var uv: Double? = nil
    var wind: Double? = nil
    var windDirection: Double? = nil
    var airQuality: Double? = nil
    var sunrise: Date? = nil
    var sunset: Date? = nil
    var nextSunrise: Date? = nil
    var timezoneIdentifier: String = "America/Sao_Paulo"
    func solarEvent(at now: Date) -> (label: String, date: Date?) {
        if let sunrise, now < sunrise { return ("NASCER DO SOL", sunrise) }
        if let sunset, now < sunset { return ("PÔR DO SOL", sunset) }
        return ("NASCER DO SOL", nextSunrise)
    }
    func solarProgress(at now: Date) -> Double? {
        guard let sunrise, let sunset, sunset > sunrise else { return nil }
        return min(1, max(0, now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)))
    }
    func localTime(_ date: Date?) -> String {
        guard let date else { return "—:—" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static let demo: WeatherSnapshot = {
        var value = WeatherSnapshot(temperature: 21, code: 2, low: 16, high: 24,
        hours: [ForecastHour(label: "Agora", temperature: 21, code: 2), ForecastHour(label: "15", temperature: 23, code: 2), ForecastHour(label: "16", temperature: 24, code: 0), ForecastHour(label: "17", temperature: 22, code: 0), ForecastHour(label: "18", temperature: 20, code: 3)],
        days: [ForecastDay(label: "Hoje", low: 16, high: 24, code: 2), ForecastDay(label: "Amanhã", low: 15, high: 22, code: 61), ForecastDay(label: "Qua", low: 14, high: 23, code: 2), ForecastDay(label: "Qui", low: 17, high: 26, code: 0)])
        value.precipitation = 20; value.uv = 3; value.wind = 12; value.windDirection = 45; value.airQuality = 32
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: value.timezoneIdentifier)!
        let start = calendar.startOfDay(for: Date())
        value.sunrise = calendar.date(byAdding: .hour, value: 6, to: start)
        value.sunset = calendar.date(byAdding: .hour, value: 18, to: start)
        value.nextSunrise = calendar.date(byAdding: .hour, value: 30, to: start)
        return value
    }()

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        if !isDay {
            switch code { case 0, 1: return "moon.stars.fill"; case 2: return "cloud.moon.fill"; case 45, 48: return "moon.haze.fill"; default: break }
        }
        switch code { case 0, 1: return "sun.max.fill"; case 2: return "cloud.sun.fill"; case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.rain.fill" }
    }
    static func description(_ code: Int) -> String {
        switch code { case 0: return "Céu limpo"; case 1: return "Predominantemente ensolarado"; case 2: return "Parcialmente nublado"; case 3: return "Predominantemente nublado"
        case 45, 48: return "Névoa"; case 71...77, 85, 86: return "Neve"; case 95...99: return "Trovoadas"; default: return "Chuva" }
    }
}
struct ForecastResponse: Decodable {
    struct Current: Decodable { let time: String; let temperature_2m: Double; let weather_code: Int; let is_day: Int?; var wind_speed_10m: Double?; var wind_direction_10m: Double? }
    struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int]?; var precipitation_probability: [Double?]?; var uv_index: [Double?]? }
    struct Daily: Decodable { let time: [String]; let temperature_2m_min: [Double]; let temperature_2m_max: [Double]; let weather_code: [Int]; var sunrise: [String]?; var sunset: [String]? }
    var timezone: String?
    var utc_offset_seconds: Int?
    let current: Current; let hourly: Hourly; let daily: Daily
    func snapshot() throws -> WeatherSnapshot {
        guard let low = daily.temperature_2m_min.first, let high = daily.temperature_2m_max.first,
              low.isFinite, high.isFinite, current.temperature_2m.isFinite else { throw URLError(.cannotParseResponse) }
        let start = hourly.time.firstIndex { String($0.prefix(13)) >= String(current.time.prefix(13)) } ?? 0
        let hourEnd = min(start + 6, hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count)
        guard hourEnd >= start else { throw URLError(.cannotParseResponse) }
        let solar = DateFormatter(); solar.locale = Locale(identifier: "en_US_POSIX")
        solar.timeZone = timezone.flatMap { TimeZone(identifier: $0) } ?? TimeZone(secondsFromGMT: utc_offset_seconds ?? 0)
        solar.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var hours = (start..<hourEnd).compactMap { i -> ForecastHour? in
            guard hourly.temperature_2m[i].isFinite else { return nil }
            return ForecastHour(label: String(hourly.time[i].dropFirst(11).prefix(2)), temperature: Int(hourly.temperature_2m[i].rounded()), code: hourly.weather_code[i], isDay: hourly.is_day.flatMap { $0.indices.contains(i) ? $0[i] == 1 : nil } ?? (current.is_day != 0), date: solar.date(from: hourly.time[i]))
        }
        if let now = solar.date(from: current.time), let last = hours.last?.date {
            let events = [(daily.sunrise ?? [], "sunrise.fill"), (daily.sunset ?? [], "sunset.fill")]
            for (times, symbol) in events {
                for raw in times {
                    guard let date = solar.date(from: raw), date > now, date <= last else { continue }
                    let before = hours.last { ($0.date ?? .distantFuture) <= date }
                    let after = hours.first { ($0.date ?? .distantPast) >= date }
                    let temperature: Int
                    if let before, let after, let a = before.date, let b = after.date, b > a {
                        let fraction = date.timeIntervalSince(a) / b.timeIntervalSince(a)
                        temperature = Int((Double(before.temperature) + Double(after.temperature - before.temperature) * fraction).rounded())
                    } else { temperature = before?.temperature ?? after?.temperature ?? Int(current.temperature_2m.rounded()) }
                    hours.append(ForecastHour(label: String(raw.suffix(5)), temperature: temperature, code: 0, date: date, eventSymbol: symbol))
                }
            }
            hours = Array(hours.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }.prefix(6))
        }
        let count = min(7, daily.time.count, daily.temperature_2m_min.count, daily.temperature_2m_max.count, daily.weather_code.count)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "pt_BR"); formatter.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter(); output.locale = Locale(identifier: "pt_BR"); output.dateFormat = "EEE"
        let days = (0..<count).compactMap { i -> ForecastDay? in
            guard daily.temperature_2m_min[i].isFinite, daily.temperature_2m_max[i].isFinite else { return nil }
            let name = i == 0 ? "Hoje" : (formatter.date(from: daily.time[i]).map { output.string(from: $0).capitalized } ?? "—")
            return ForecastDay(label: name, low: Int(daily.temperature_2m_min[i].rounded()), high: Int(daily.temperature_2m_max[i].rounded()), code: daily.weather_code[i])
        }
        var result = WeatherSnapshot(temperature: Int(current.temperature_2m.rounded()), code: current.weather_code, low: Int(low.rounded()), high: Int(high.rounded()), hours: hours, days: days, isDay: current.is_day != 0)
        func sample(_ values: [Double?]?) -> Double? {
            guard let values, values.indices.contains(start), let value = values[start], value.isFinite else { return nil }
            return value
        }
        result.precipitation = sample(hourly.precipitation_probability)
        result.uv = sample(hourly.uv_index)
        result.wind = current.wind_speed_10m
        result.windDirection = current.wind_direction_10m
        result.timezoneIdentifier = timezone ?? "America/Sao_Paulo"
        result.sunrise = daily.sunrise?.first.flatMap { solar.date(from: $0) }
        result.sunset = daily.sunset?.first.flatMap { solar.date(from: $0) }
        result.nextSunrise = daily.sunrise?.dropFirst().first.flatMap { solar.date(from: $0) }
        return result
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

struct AirQualityResponse: Decodable {
    struct Current: Decodable { var us_aqi: Double? }
    var current: Current?
}
