import SwiftUI

struct WeatherBackground: View {
    let snapshot: WeatherSnapshot?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var mood: WeatherMood { WeatherMood.resolve(code: snapshot?.code ?? 3, isDay: snapshot?.isDay ?? false) }
    var colors: [Color] {
                switch mood {
        case .sunny: return [Color(red: 0.12, green: 0.39, blue: 0.72), Color(red: 0.30, green: 0.62, blue: 0.87)]
        case .cloudy: return [Color(red: 0.30, green: 0.39, blue: 0.48), Color(red: 0.53, green: 0.58, blue: 0.60)]
        case .rain: return [Color(red: 0.19, green: 0.26, blue: 0.33), Color(red: 0.35, green: 0.43, blue: 0.49)]
        case .clearNight: return [Color(red: 0.06, green: 0.09, blue: 0.21), Color(red: 0.16, green: 0.20, blue: 0.34)]
        case .cloudyNight: return [Color(white: 0.12), Color(red: 0.22, green: 0.23, blue: 0.24)]
        case .fogNight: return [Color(red: 0.13, green: 0.14, blue: 0.14), Color(red: 0.20, green: 0.20, blue: 0.16)]
        case .storm: return [Color(red: 0.17, green: 0.18, blue: 0.25), Color(red: 0.30, green: 0.30, blue: 0.35)]
        case .snow: return [Color(red: 0.34, green: 0.45, blue: 0.54), Color(red: 0.58, green: 0.64, blue: 0.69)]
        }
    }
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                GeometryReader { g in
                    if mood == .sunny {
                        RadialGradient(colors: [.yellow.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: g.size.width * 0.8)
                    } else if mood == .cloudy || mood == .cloudyNight || mood == .rain || mood == .fogNight {
                        RadialGradient(colors: [.white.opacity(mood == .cloudy ? 0.18 : 0.06), .clear], center: .bottomLeading, startRadius: 0, endRadius: max(g.size.width, g.size.height))
                    }
                }.allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: mood)
            .overlay(LinearGradient(colors: [.clear, .white.opacity(0.025), .clear], startPoint: .leading, endPoint: .trailing))
    }
}
struct TemperatureRange: View {
    let low: Int; let high: Int; let minimum: Int; let maximum: Int
    var body: some View {
        GeometryReader { g in
            let range = CGFloat(max(1, maximum - minimum))
            let left = CGFloat(low - minimum) / range * g.size.width
            let width = max(5, CGFloat(high - low) / range * g.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [.cyan, high > 23 ? .yellow : .mint, high > 27 ? .orange : .yellow.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: min(g.size.width - left, width)).offset(x: left)
            }
        }.frame(height: 4)
    }
}
