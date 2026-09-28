import Foundation
import Network

@MainActor final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot? = .demo
    @Published private(set) var status = "Demonstração"
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var city: WeatherCity = .curitiba
    private var live = false
    private var paused = false
    private var lastAttempt: Date?
    private var lastSuccess: Date?
    private let network = NWPathMonitor()
    func setPaused(_ value: Bool) {
        paused = value
        if value { task?.cancel(); task = nil }
        else { refreshIfNeeded() }
    }
    private func refreshIfNeeded() {
        guard live, !paused, task == nil else { return }
        let now = Date()
        guard lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        if lastSuccess.map({ now.timeIntervalSince($0) >= 900 }) ?? true { refresh() }
    }
    init(preview: WeatherSnapshot? = nil) {
        if let preview { snapshot = preview; status = "Prévia visual" }
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIfNeeded() }
        }
        timer?.tolerance = 90
        if preview == nil {
            network.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.refreshIfNeeded() }
            }
            network.start(queue: DispatchQueue(label: "LoockMesa.network", qos: .utility))
        }
    }
    deinit { network.cancel(); timer?.invalidate(); task?.cancel() }
    func configure(city: WeatherCity, live: Bool) {
        guard city != self.city || live != self.live else { return }
        self.city = city; self.live = live; snapshot = nil; lastSuccess = nil; refresh()
    }
    func refresh() {
        guard !paused else { return }
        task?.cancel(); task = nil
        guard live else { snapshot = .demo; status = "Demonstração"; return }
        lastAttempt = Date()
        status = snapshot == nil ? "Atualizando…" : "Open-Meteo · atualizando"
        let coordinates = city.coordinates
        task = Task { [weak self] in
            do {
                var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                let fields = ["latitude": "\(coordinates.0)", "longitude": "\(coordinates.1)", "current": "temperature_2m,weather_code,is_day", "hourly": "temperature_2m,weather_code,is_day", "daily": "temperature_2m_min,temperature_2m_max,weather_code", "timezone": "auto", "forecast_days": "5"]
                url.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
                var request = URLRequest(url: url.url!); request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let value = try JSONDecoder().decode(ForecastResponse.self, from: data).snapshot()
                try Task.checkCancellation()
                self?.lastSuccess = Date(); self?.task = nil
                self?.snapshot = value; self?.status = "Open-Meteo · " + Date().formatted(date: .omitted, time: .shortened)
            } catch {
                guard !Task.isCancelled else { return }
                self?.task = nil
                self?.status = self?.snapshot == nil ? "Sem conexão · tente atualizar" : "Dados anteriores · sem conexão"
            }
        }
    }
}
