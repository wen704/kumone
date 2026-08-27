import Foundation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
    var translation: String?
    var romaji: String?
}

struct ParsedLyrics: Hashable {
    var lines: [LyricLine] = []
    var isInstrumental = false
    var contributor: String?
    var translationContributor: String?

    var isEmpty: Bool { lines.isEmpty }

    /// Index of the active line for a playback position.
    func activeIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0, high = lines.count - 1, result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}

enum LyricsParser {
    /// `NSRegularExpression` 而非 Swift Regex:后者是 iOS 16+ API。
    private static let timeTag = try? NSRegularExpression(pattern: #"\[(\d+):(\d+)(?:[.:](\d+))?\]"#)

    /// Parses an LRC body into (time, text) pairs. Handles multiple timestamps
    /// per line and both `.` / `:` millisecond separators.
    static func parseLRC(_ lrc: String) -> [(time: TimeInterval, text: String)] {
        var result: [(TimeInterval, String)] = []
        guard let timeTag else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let matches = timeTag.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard let lastMatch = matches.last else { continue }
            let content = nsLine
                .substring(from: lastMatch.range.location + lastMatch.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let min = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let sec = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                var frac = 0.0
                let msRange = match.range(at: 3)
                if msRange.location != NSNotFound {
                    let msStr = nsLine.substring(with: msRange)
                    if let ms = Double(msStr) {
                        frac = ms / pow(10, Double(msStr.count))
                    }
                }
                result.append((min * 60 + sec + frac, content))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    static func parse(_ response: LyricResponse) -> ParsedLyrics {
        var out = ParsedLyrics()
        out.contributor = response.lyricUser?.nickname
        out.translationContributor = response.transUser?.nickname

        guard let raw = response.lrc?.lyric, !raw.isEmpty else { return out }
        var main = parseLRC(raw)

        // Instrumental marker handling (mirrors YesPlayMusic).
        let instrumentalMarker = "纯音乐，请欣赏"
        if main.count <= 10, main.contains(where: { $0.text.contains(instrumentalMarker) }) {
            out.isInstrumental = true
            main.removeAll { line in
                line.text.contains(instrumentalMarker)
                    || line.text.range(of: #"^作(词|曲)\s*[:：]"#, options: .regularExpression) != nil
            }
            if main.isEmpty {
                return out
            }
        }
        main.removeAll { $0.text.range(of: #"^作(词|曲)\s*[:：]\s*无$"#, options: .regularExpression) != nil }

        var lines = main.enumerated().map { idx, pair in
            LyricLine(id: idx, time: pair.time, text: pair.text)
        }

        func merge(_ body: String?, into keyPath: WritableKeyPath<LyricLine, String?>) {
            guard let body, !body.isEmpty else { return }
            let secondary = parseLRC(body)
            guard !secondary.isEmpty else { return }
            var byTime: [Int: String] = [:]
            for (time, text) in secondary where !text.isEmpty {
                byTime[Int(time * 100)] = text
            }
            for i in lines.indices {
                if let text = byTime[Int(lines[i].time * 100)] {
                    lines[i][keyPath: keyPath] = text
                }
            }
        }

        merge(response.tlyric?.lyric, into: \.translation)
        merge(response.romalrc?.lyric, into: \.romaji)

        // Romaji is only meaningful for Japanese lyrics: fill the gaps Netease
        // left, and drop stray annotations on everything else.
        if RomajiTranscriber.isJapanese(lines.map(\.text)) {
            for i in lines.indices where lines[i].romaji == nil {
                lines[i].romaji = RomajiTranscriber.transcribe(lines[i].text)
            }
        } else {
            for i in lines.indices {
                lines[i].romaji = nil
            }
        }

        out.lines = lines
        return out
    }
}
