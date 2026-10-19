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
    /// Follow the supplied timestamp without imposing one global offset on every recording.
    static func presentationTime(_ elapsed: TimeInterval, playing: Bool) -> TimeInterval {
        elapsed
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
    /// Remove only edition/guest annotations; live, remix and acoustic remain significant.
    static func searchTitle(_ value: String) -> String {
        var result = value
        for pattern in [#"(?i)\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]+[\)\]]"#,
                        #"(?i)\s*[\(\[]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?\s*[\)\]]"#,
                        #"(?i)\s*[-–—]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?\s*$"#,
                        #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+.*$"#] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func leadArtist(_ value: String) -> String {
        value.components(separatedBy: ",").first!.replacingOccurrences(
            of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
    }
    var searchURLs: [URL] {
        guard let original = searchURL else { return [] }
        var urls = [original]
        let cleaned = Self.searchTitle(title)
        if cleaned != title {
            var alternate = URLComponents(string: "https://lrclib.net/api/search")!
            alternate.queryItems = [URLQueryItem(name: "track_name", value: cleaned), URLQueryItem(name: "artist_name", value: Self.leadArtist(artist))]
            if let url = alternate.url { urls.append(url) }
        }
        return urls
    }
    func acceptsArtist(_ candidate: String) -> Bool {
        let actual = Self.normalized(candidate)
        guard !actual.isEmpty else { return false }
        return Self.normalized(artist) == actual || Self.normalized(Self.leadArtist(artist)) == Self.normalized(Self.leadArtist(candidate))
    }
    func bestDocument(in records: [LyricsRecord]) -> LyricsDocument? {
        var best: (Double, LyricsDocument)?
        for record in records {
            guard Self.normalized(Self.searchTitle(record.trackName ?? "")) == Self.normalized(Self.searchTitle(title)),
                  acceptsArtist(record.artistName ?? ""), record.instrumental != true else { continue }
            let knownDuration = duration.isFinite && duration > 0
            let candidateDuration = record.duration ?? 0
            let delta = abs(candidateDuration - duration)
            // Very different lengths usually indicate a different recording.
            if knownDuration && candidateDuration > 0 && delta > 10 { continue }
            let document = record.document
            guard document.available else { continue }
            // Keep supplied line timestamps even when duration metadata is absent
            // or differs by a few seconds. Duration ranks candidates; it must not
            // silently turn a synchronized document into a static text view.
            let score = (document.lines.isEmpty ? 0.0 : 100.0)
                + (Self.normalized(record.albumName ?? "") == Self.normalized(album) ? 10 : 0)
                + (Self.normalized(record.trackName ?? "") == Self.normalized(title) ? 5 : 0)
                - (knownDuration && candidateDuration > 0 ? delta : 0)
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
