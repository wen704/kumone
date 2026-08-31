import Foundation

/// Turns a lyric line into base text plus furigana.
///
/// Readings come from the Japanese morphological analyser built into the OS
/// (the one behind the Japanese input method), reached through
/// CFStringTokenizer's Latin transcription attribute and transliterated back to
/// hiragana. No dictionary needs to be bundled.
enum Furigana {
    private static let locale = Locale(identifier: "ja")

    /// Segments for a line, or nil when there is nothing to annotate — a line
    /// of pure kana, Latin or punctuation is better left to plain `Text`.
    static func segments(for line: String) -> [RubySegment]? {
        guard Kana.containsKanji(line) else { return nil }
        let result = merged(annotate(line))
        guard result.contains(where: { $0.ruby != nil }) else { return nil }
        return result
    }

    // MARK: - Annotation

    private static func annotate(_ line: String) -> [RubySegment] {
        var result: [RubySegment] = []
        var pending = ""
        let characters = Array(line)
        var index = 0

        func flushPending() {
            guard !pending.isEmpty else { return }
            result.append(contentsOf: tokenize(pending))
            pending = ""
        }

        while index < characters.count {
            if let hit = ReadingOverrides.match(characters, at: index) {
                flushPending()
                result.append(contentsOf: RubyAligner.align(surface: hit.surface, reading: hit.reading))
                index += hit.surface.count
            } else {
                pending.append(characters[index])
                index += 1
            }
        }
        flushPending()
        return result
    }

    private static func tokenize(_ text: String) -> [RubySegment] {
        guard Kana.containsKanji(text) else { return [RubySegment(text)] }

        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cfText, CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary, locale as CFLocale
        ) else { return [RubySegment(text)] }
        let nsText = text as NSString

        var result: [RubySegment] = []
        var consumed = 0

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // The tokenizer can skip characters it does not consider words.
            if range.location > consumed {
                let gap = nsText.substring(with: NSRange(location: consumed, length: range.location - consumed))
                result.append(RubySegment(gap))
            }
            consumed = range.location + range.length

            let surface = nsText.substring(with: NSRange(location: range.location, length: range.length))
            guard Kana.containsKanji(surface) else {
                result.append(RubySegment(surface))
                continue
            }
            guard let reading = reading(from: tokenizer), Kana.isKanaOnly(reading) else {
                result.append(RubySegment(surface))
                continue
            }
            result.append(contentsOf: RubyAligner.align(surface: surface, reading: reading))
        }

        if consumed < length {
            result.append(RubySegment(nsText.substring(from: consumed)))
        }
        return result
    }

    private static func reading(from tokenizer: CFStringTokenizer) -> String? {
        guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription
        ) as? String, !latin.isEmpty else { return nil }
        return latin.applyingTransform(StringTransform("Latin-Hiragana"), reverse: false)
    }

    /// Collapses runs of unannotated text so the renderer draws fewer pieces.
    private static func merged(_ segments: [RubySegment]) -> [RubySegment] {
        var result: [RubySegment] = []
        for segment in segments {
            if segment.ruby == nil, let last = result.last, last.ruby == nil {
                result[result.count - 1] = RubySegment(last.text + segment.text)
            } else {
                result.append(segment)
            }
        }
        return result
    }
}
