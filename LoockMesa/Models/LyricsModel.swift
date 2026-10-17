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
    func activeIndex(at time: TimeInterval) -> Int? {
        guard time.isFinite else { return nil }
        return lines.lastIndex { $0.time <= time }
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
    var url: URL? {
        guard !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0 else { return nil }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
                         URLQueryItem(name: "album_name", value: album), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        return url.url
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
