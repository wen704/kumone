import Foundation

/// Character classification and kana normalisation helpers.
enum Kana {
    static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005,                    // 々 iteration mark
             0x3400...0x4DBF,           // CJK Ext A
             0x4E00...0x9FFF,           // CJK Unified
             0xF900...0xFAFF,           // CJK Compatibility
             0x20000...0x2FA1F:         // CJK Ext B and beyond
            return true
        default:
            return false
        }
    }

    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041...0x309F,           // hiragana (incl. ゝ ゞ)
             0x30A0...0x30FF,           // katakana (incl. ー)
             0xFF66...0xFF9F:           // halfwidth katakana
            return true
        default:
            return false
        }
    }

    static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isKanji)
    }

    static func isKanaOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(isKana)
    }

    /// Katakana to hiragana, leaving everything else untouched. ー is kept as
    /// is because it is valid in both scripts.
    static func toHiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value)
                ? Unicode.Scalar(scalar.value - 0x60)!
                : scalar
        }))
    }

    /// Compares kana ignoring the hiragana/katakana distinction, so that a
    /// katakana surface still matches a hiragana reading.
    static func equalIgnoringScript(_ left: some StringProtocol, _ right: some StringProtocol) -> Bool {
        toHiragana(String(left)) == toHiragana(String(right))
    }
}
