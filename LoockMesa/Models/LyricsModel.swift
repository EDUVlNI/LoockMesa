import Foundation

struct LyricLine: Equatable, Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}
struct LyricsDocument: Equatable {
    var lines: [LyricLine] = []
    var plain = ""
    var available: Bool { !lines.isEmpty || !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Start the visual transition slightly before the lyric timestamp so emphasis lands on the beat.
    static func presentationTime(_ elapsed: TimeInterval, playing: Bool) -> TimeInterval {
        elapsed + (playing ? 0.18 : 0)
    }
    func activeIndex(at time: TimeInterval) -> Int? {
        guard time.isFinite else { return nil }
        var lower = 0, upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= time { lower = middle + 1 } else { upper = middle }
        }
        return lower > 0 ? lower - 1 : nil
    }
    static func parse(synced: String?, plain: String?) -> Self {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2}(?:\.\d{1,3})?)\]"#)
        let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let source = synced ?? ""
        let ns = source as NSString
        let offset = offsetRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var entries: [(TimeInterval, String)] = []
        for raw in source.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let text = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(line.substring(with: match.range(at: 1))),
                      let seconds = Double(line.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                entries.append((max(0, minutes * 60 + seconds - offset), text))
            }
        }
        entries.sort { $0.0 < $1.0 }
        // Preserve empty timed entries so instrumental gaps don't keep highlighting a sung line.
        let lines = entries.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
        return Self(lines: lines.contains(where: { !$0.text.isEmpty }) ? lines : [], plain: plain ?? "")
    }
}

struct LyricsQuery: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var key: String { [title, artist, album, String(duration.rounded())].joined(separator: "\u{001F}") }
    var searchURL: URL? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              !artist.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        // Search without the album; releases and deluxe editions often differ.
        url.queryItems = [URLQueryItem(name: "track_name", value: title)]
        return url.url
    }
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    func acceptsArtist(_ candidate: String) -> Bool {
        let expected = Self.normalized(artist), actual = Self.normalized(candidate)
        guard !actual.isEmpty else { return false }
        if expected == actual { return true }
        // Spotify can publish multiple artists while LRCLIB lists just the lead.
        let lead = artist.components(separatedBy: ",").first ?? artist
        return Self.normalized(lead) == actual
    }
    func bestDocument(in records: [LyricsRecord]) -> LyricsDocument? {
        var best: (Double, LyricsDocument)?
        for record in records {
            guard Self.normalized(record.trackName ?? "") == Self.normalized(title),
                  acceptsArtist(record.artistName ?? ""), record.instrumental != true else { continue }
            let knownDuration = duration.isFinite && duration > 0
            let delta = abs((record.duration ?? 0) - duration)
            if knownDuration {
                guard let candidateDuration = record.duration, candidateDuration.isFinite,
                      candidateDuration > 0, delta <= 3 else { continue }
            }
            var document = record.document
            guard document.available else { continue }
            if !knownDuration {
                // Without duration we can show text but cannot verify matching timing.
                if document.plain.isEmpty { document.plain = document.lines.map(\.text).joined(separator: "\n") }
                document.lines = []
            }
            let score = (document.lines.isEmpty ? 0.0 : 100.0)
                + (Self.normalized(record.albumName ?? "") == Self.normalized(album) ? 10 : 0)
                - (knownDuration ? delta : 0)
            if best == nil || score > best!.0 { best = (score, document) }
        }
        return best?.1
    }
    var url: URL? {
        guard !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0 else { return nil }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
                         URLQueryItem(name: "album_name", value: album), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        return url.url
    }
}

struct LyricsRecord: Decodable {
    var trackName: String? = nil
    var artistName: String? = nil
    var albumName: String? = nil
    var duration: Double? = nil
    var instrumental: Bool? = nil
    var plainLyrics: String? = nil
    var syncedLyrics: String? = nil
    var document: LyricsDocument {
        instrumental == true ? LyricsDocument() : LyricsDocument.parse(synced: syncedLyrics, plain: plainLyrics)
    }
}

struct PlaybackPosition {
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var sampledAt = Date()
    var rate: Double = 0
    var known = false
    func at(_ date: Date) -> TimeInterval {
        let value = max(0, elapsed + max(0, date.timeIntervalSince(sampledAt)) * rate)
        return duration > 0 ? min(duration, value) : value
    }
}

/// Reject slow/stale native samples instead of moving the lyric clock backwards.
extension PlaybackPosition {
    static func nativeSample(elapsed: Double, duration: Double, playing: Bool, started: Date, ended: Date) -> PlaybackPosition? {
        let latency = ended.timeIntervalSince(started)
        guard elapsed.isFinite, elapsed >= 0, duration.isFinite, duration > 0,
              latency >= 0, latency < 1 else { return nil }
        return PlaybackPosition(elapsed: min(elapsed, duration), duration: duration,
            sampledAt: started.addingTimeInterval(latency / 2), rate: playing ? 1 : 0, known: true)
    }
}
