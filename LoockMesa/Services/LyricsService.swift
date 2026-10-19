import Foundation
import Combine

/// Shared lookup with exact metadata first, then verified search candidates.
final class LyricsService: ObservableObject {
    static let shared = LyricsService(media: .shared)
    @Published private(set) var document = LyricsDocument()
    @Published private(set) var loading = false
    @Published private(set) var lookupFailed = false
    var status: String {
        if loading { return "Procurando letra…" }
        if document.available { return document.lines.isEmpty ? "Letra disponível sem sincronização · LRCLIB" : "Letra sincronizada · LRCLIB" }
        return lookupFailed ? "Não foi possível carregar a letra. Nova tentativa automática." : "Letra não encontrada nesta fonte. O catálogo pode diferir do Spotify."
    }
    private var trackKey = ""
    @Published var showingLyrics = false {
        didSet {
            guard showingLyrics != oldValue else { return }
            media.synchronizeSpotifyClock(enabled: enabled && showingLyrics)
        }
    }
    private let media: MusicService
    private let session: URLSession
    private var subscription: AnyCancellable?
    private var request: URLSessionDataTask?
    private var generation = UUID()
    private var key = ""
    private var enabled = false
    private var cache: [String: LyricsDocument] = [:]
    private var cacheOrder: [String] = []
    private var retryAfter = Date.distantPast
    init(media: MusicService, session: URLSession = .shared) {
        self.media = media; self.session = session
        subscription = media.$track.combineLatest(media.$position).receive(on: RunLoop.main).sink { [weak self] _, _ in self?.refresh() }
    }
    deinit { request?.cancel() }
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        media.synchronizeSpotifyClock(enabled: enabled && showingLyrics)
        refresh()
    }
    func toggle() { guard document.available else { return }; showingLyrics.toggle() }
    private func refresh() {
        let track = media.track
        let query = LyricsQuery(title: track.title, artist: track.artist, album: track.album, duration: media.position.duration)
        let nextKey = enabled && track.pid > 0 && query.searchURL != nil ? query.key : ""
        guard key != nextKey || (!loading && Date() >= retryAfter && !key.isEmpty && cache[key] == nil) else { return }
        let changed = key != nextKey
        key = nextKey
        generation = UUID(); request?.cancel(); request = nil; loading = false
        if changed {
            let identity = enabled ? track.identity : ""
            if identity != trackKey { document = LyricsDocument(); showingLyrics = false }
            trackKey = identity; retryAfter = .distantPast
        }
        guard !nextKey.isEmpty else { document = LyricsDocument(); showingLyrics = false; return }
        if let saved = cache[nextKey] { document = saved; lookupFailed = false; return }
        loading = true; lookupFailed = false
        let token = generation
        guard let url = query.url else { search(query, token: token, fallback: LyricsDocument()); return }
        fetch(url, token: token) { [weak self] data, status in
            guard let self else { return }
            if status == 200, let data, let record = try? JSONDecoder().decode(LyricsRecord.self, from: data) {
                let result = query.bestDocument(in: [record]) ?? LyricsDocument()
                if !result.lines.isEmpty { self.finish(result, cacheable: true); return }
                self.search(query, token: token, fallback: result)
            } else if status == 404 {
                self.search(query, token: token, fallback: LyricsDocument())
            } else {
                self.finish(LyricsDocument(), cacheable: false)
            }
        }
    }
    private func search(_ query: LyricsQuery, token: UUID, fallback: LyricsDocument, index: Int = 0) {
        let urls = query.searchURLs
        guard index < urls.count else { finish(fallback, cacheable: true); return }
        fetch(urls[index], token: token) { [weak self] data, status in
            guard let self else { return }
            if status == 200, let data, let records = try? JSONDecoder().decode([LyricsRecord].self, from: data) {
                let candidate = query.bestDocument(in: records)
                if let candidate, !candidate.lines.isEmpty { self.finish(candidate, cacheable: true); return }
                self.search(query, token: token, fallback: candidate ?? fallback, index: index + 1)
            } else {
                self.finish(fallback, cacheable: false)
            }
        }
    }
    private func fetch(_ url: URL, token: UUID, completion: @escaping (Data?, Int?) -> Void) {
        var urlRequest = URLRequest(url: url, timeoutInterval: 12)
        urlRequest.setValue("LoockMesa/0.38 (https://github.com/EDUVlNI/LoockMesa)", forHTTPHeaderField: "User-Agent")
        request = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            let safeData = data.flatMap { $0.count <= 4_000_000 ? $0 : nil }
            DispatchQueue.main.async {
                guard let self, self.enabled, self.generation == token else { return }
                self.request = nil
                completion(error == nil ? safeData : nil, error == nil ? status : nil)
            }
        }
        request?.resume()
    }
    private func finish(_ result: LyricsDocument, cacheable: Bool) {
        document = result; loading = false; lookupFailed = !cacheable
        if !result.available { showingLyrics = false }
        // A network failure is not a permanent missing lyric; negative matches expire too.
        retryAfter = Date().addingTimeInterval(cacheable ? 300 : 60)
        guard cacheable, result.available else { return }
        cache[key] = result
        cacheOrder.removeAll { $0 == key }; cacheOrder.append(key)
        if cacheOrder.count > 32 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }
}
