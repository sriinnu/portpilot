// TextWidth.swift — display-column width (a wcwidth approximation)
//
// Terminals render some code points across two columns: CJK ideographs,
// fullwidth forms, most emoji. Layout helpers that count `String.count`
// (grapheme clusters) or UTF-16 units drift against what the user actually
// sees — right-aligned numbers jitter, centered titles lean left.
//
// This is a pragmatic table, not full Unicode EastAsianWidth: it covers the
// ranges that show up in real terminal output (process names, paths, git
// branches from anywhere). Zero-width scalars (combining marks, variation
// selectors, ZWJ) count 0 so composed characters keep their base width.

import Foundation

public enum TextWidth {

    // MARK: - Public API

    /// Columns a character occupies on screen: 0, 1, or 2.
    public static func width(of char: Character) -> Int {
        var total = 0
        for scalar in char.unicodeScalars {
            total += width(of: scalar)
        }
        // ZWJ emoji sequences stack several wide bases; every terminal
        // renders the composed cluster as one double-width cell.
        return min(total, 2)
    }

    /// Columns a string occupies on screen.
    public static func displayWidth(_ string: String) -> Int {
        var total = 0
        for char in string {
            total += width(of: char)
        }
        return total
    }

    /// Truncate to at most `width` display columns. Never splits a
    /// double-width glyph across the boundary.
    public static func truncate(_ string: String, toWidth maxWidth: Int) -> String {
        guard maxWidth > 0 else { return "" }
        var used = 0
        var out = ""
        for char in string {
            let w = width(of: char)
            if used + w > maxWidth { break }
            out.append(char)
            used += w
        }
        return out
    }

    // MARK: - Per-Scalar Table

    public static func width(of scalar: Unicode.Scalar) -> Int {
        let v = scalar.value

        // Zero-width: combining diacritics, zero-width spaces/joiners,
        // variation selectors (emoji presentation), skin-tone modifiers.
        switch v {
        case 0x0300...0x036F,   // combining diacritical marks
             0x20D0...0x20FF,   // combining marks for symbols
             0x1AB0...0x1AFF,
             0x1DC0...0x1DFF,
             0xFE00...0xFE0F,   // variation selectors
             0xFE20...0xFE2F,
             0x200B...0x200F,   // zero-width space..LRM
             0x200D,            // zero-width joiner
             0x2060...0x2064,
             0x1F3FB...0x1F3FF: // emoji skin-tone modifiers
            return 0
        default:
            break
        }

        // Double-width: East Asian Wide/Fullwidth + emoji presentation.
        switch v {
        case 0x1100...0x115F,       // Hangul Jamo leading consonants
             0x2E80...0x303E,       // CJK radicals, Kangxi, symbols
             0x3041...0x33FF,       // Hiragana through CJK compatibility
             0x3400...0x4DBF,       // CJK ext A
             0x4E00...0x9FFF,       // CJK unified ideographs
             0xA000...0xA4CF,       // Yi
             0xA960...0xA97F,       // Hangul Jamo extended A
             0xAC00...0xD7A3,       // Hangul syllables
             0xF900...0xFAFF,       // CJK compatibility ideographs
             0xFE10...0xFE19,       // vertical forms
             0xFE30...0xFE6F,       // CJK compatibility forms
             0xFF00...0xFF60,       // fullwidth forms
             0xFFE0...0xFFE6,       // fullwidth signs
             0x16FE0...0x16FFF,
             0x17000...0x187F7,     // Tangut
             0x18800...0x18AFF,
             0x1B000...0x1B2FF,     // Kana supplements
             0x1F004,               // mahjong tile
             0x1F0CF,               // playing card joker
             0x1F18E,               // AB button
             0x1F191...0x1F19A,
             0x1F200...0x1F320,     // enclosed ideographs, early emoji
             0x1F32D...0x1F335,
             0x1F337...0x1F37C,
             0x1F37E...0x1F393,
             0x1F3A0...0x1F3CA,
             0x1F3CF...0x1F3D3,
             0x1F3E0...0x1F3F0,
             0x1F3F4,
             0x1F3F8...0x1F43E,
             0x1F440,
             0x1F442...0x1F4FC,
             0x1F4FF...0x1F53D,
             0x1F54B...0x1F54E,
             0x1F550...0x1F567,
             0x1F57A,
             0x1F595...0x1F596,
             0x1F5A4,
             0x1F5FB...0x1F64F,
             0x1F680...0x1F6C5,
             0x1F6CC,
             0x1F6D0...0x1F6D2,
             0x1F6D5...0x1F6D7,
             0x1F6EB...0x1F6EC,
             0x1F6F4...0x1F6FC,
             0x1F7E0...0x1F7EB,
             0x1F90C...0x1F93A,
             0x1F93C...0x1F945,
             0x1F947...0x1F9FF,
             0x1FA70...0x1FAFF,     // extended-A symbols (chess, symbols)
             0x20000...0x2FFFD,     // CJK ext B+
             0x30000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}
