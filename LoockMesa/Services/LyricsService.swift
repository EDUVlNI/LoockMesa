import Foundation
import Combine

/// One request per track, shared by desktop and gallery. No lyric requests for previews alone.
final class LyricsService: ObservableObject {
    static let shared = LyricsService(media: .shared)
    @Published private(set) var document = LyricsDocument()
    @Published private(set) var loading = false
    @Published var showingLyrics = false
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
        refresh()
    }
    func toggle() { guard document.available else { return }; showingLyrics.toggle() }
    private func refresh() {
        let track = media.track
        let query = LyricsQuery(title: track.title, artist: track.artist, album: track.album, duration: media.position.duration)
        let nextKey = enabled && track.pid > 0 && query.url != nil ? query.key : ""
        guard key != nextKey || (!loading && Date() >= retryAfter && !key.isEmpty && cache[key] == nil) else { return }
        let changed = key != nextKey
        key = nextKey
        generation = UUID(); request?.cancel(); request = nil; loading = false
        if changed { document = LyricsDocument(); showingLyrics = false }
        guard !nextKey.isEmpty, let url = query.url else { document = LyricsDocument(); showingLyrics = false; return }
        if let saved = cache[nextKey] { document = saved; return }
        loading = true
        let token = generation
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("LoockMesa/0.31 (https://github.com/EDUVlNI/LoockMesa)", forHTTPHeaderField: "User-Agent")
        self.request = session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            let record: Record? = data.flatMap { bytes in
                guard bytes.count <= 1_000_000 else { return nil }
                return try? JSONDecoder().decode(Record.self, from: bytes)
            }
            DispatchQueue.main.async {
                guard let self, self.enabled, self.generation == token, self.key == nextKey else { return }
                self.loading = false; self.request = nil
                let result: LyricsDocument
                if status == 404 { result = LyricsDocument() }
                else if error == nil, status == 200, let record {
                    result = record.instrumental == true ? LyricsDocument() : LyricsDocument.parse(synced: record.syncedLyrics, plain: record.plainLyrics)
                } else {
                    self.retryAfter = Date().addingTimeInterval(60)
                    return // A timeout is not a permanent "no lyrics" result.
                }
                self.document = result
                if !result.available { self.showingLyrics = false }
                self.cache[nextKey] = result
                self.cacheOrder.removeAll { $0 == nextKey }; self.cacheOrder.append(nextKey)
                if self.cacheOrder.count > 32 { self.cache.removeValue(forKey: self.cacheOrder.removeFirst()) }
            }
        }
        self.request?.resume()
    }
    private struct Record: Decodable {
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }
}
