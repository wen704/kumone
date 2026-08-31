import Foundation

/// One timed word (or short run) inside a verbatim (yrc) lyric line.
struct LyricWord: Hashable {
    let text: String
    let start: TimeInterval
    let duration: TimeInterval
    var end: TimeInterval { start + duration }
}

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
    var translation: String?
    var romaji: String?
    /// Base text split so each reading sits over the kanji it belongs to.
    /// Nil when there is nothing to annotate.
    var furigana: [RubySegment]?
    /// Per-word timings for karaoke highlighting; nil when only line-level
    /// (lrc) timing is available.
    var words: [LyricWord]?
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

    /// `NSRegularExpression` 而非 Swift Regex:后者是 iOS 16+ API。
    private static let yrcLineTag = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
    private static let yrcWordTag = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)([^(]*)"#)

    /// Parses NetEase verbatim `yrc` lyrics: each content line is
    /// `[lineStartMs,lineDurMs](wStartMs,wDurMs,0)word(...)word…`. JSON metadata
    /// (credits) lines at the top don't match the `[num,num]` head and are
    /// skipped.
    static func parseYRC(_ yrc: String) -> [LyricLine] {
        guard let lineTag = yrcLineTag, let wordTag = yrcWordTag else { return [] }
        var lines: [LyricLine] = []
        var idx = 0
        for raw in yrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let nsLine = line as NSString
            guard let head = lineTag.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else { continue }
            let lineStart = (Double(nsLine.substring(with: head.range(at: 1))) ?? 0) / 1000
            var words: [LyricWord] = []
            var text = ""
            for w in wordTag.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let start = (Double(nsLine.substring(with: w.range(at: 1))) ?? 0) / 1000
                let duration = (Double(nsLine.substring(with: w.range(at: 2))) ?? 0) / 1000
                let piece = nsLine.substring(with: w.range(at: 3))
                words.append(LyricWord(text: piece, start: start, duration: duration))
                text += piece
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !words.isEmpty else { continue }
            lines.append(LyricLine(id: idx, time: lineStart, text: trimmed, words: words))
            idx += 1
        }
        return lines
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
        // Prefer verbatim (word-by-word) lines when the song has them.
        if let yrcRaw = response.yrc?.lyric, !yrcRaw.isEmpty {
            let yrcLines = parseYRC(yrcRaw)
            if !yrcLines.isEmpty { lines = yrcLines }
        }

        func merge(_ body: String?, into keyPath: WritableKeyPath<LyricLine, String?>) {
            guard let body, !body.isEmpty else { return }
            let secondary = parseLRC(body).filter { !$0.text.isEmpty }
            guard !secondary.isEmpty else { return }
            for i in lines.indices {
                // Nearest secondary line within 0.3s: verbatim (yrc) line times
                // can differ from the lrc-based translation/romaji by a few ms.
                var best: (delta: TimeInterval, text: String)?
                for (time, text) in secondary {
                    let delta = abs(time - lines[i].time)
                    if best == nil || delta < best!.delta { best = (delta, text) }
                }
                if let best, best.delta < 0.3 {
                    lines[i][keyPath: keyPath] = best.text
                }
            }
        }

        merge(response.ytlrc?.lyric ?? response.tlyric?.lyric, into: \.translation)
        merge(response.yromalrc?.lyric ?? response.romalrc?.lyric, into: \.romaji)

        // Readings are only meaningful for Japanese lyrics: fill the romaji
        // gaps Netease left, annotate the kanji, and drop stray annotations on
        // everything else. Both are done here rather than in the view so a line
        // is analysed once per track instead of once per frame.
        if RomajiTranscriber.isJapanese(lines.map(\.text)) {
            for i in lines.indices {
                if lines[i].romaji == nil {
                    lines[i].romaji = RomajiTranscriber.transcribe(lines[i].text)
                }
                lines[i].furigana = Furigana.segments(for: lines[i].text)
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
