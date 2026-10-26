import Foundation

/// The chat's moderation (playtesting 2026-10-25: "Have moderation in the game chat"): what you type is
/// checked against content/moderation.json before anyone sees it, and every rude word is starred out,
/// in your speech bubble and the chat alike. The game's chat is your own and its bots' (nothing you
/// type leaves the phone), so this keeps the bubbles and the log clean, for a screenshot or a younger
/// player, rather than guarding anyone else.
///
/// A word is rude when, read without case or accents and with the usual stand-ins (0 for o, 4 or @
/// for a, $ for s...) read as letters, it's one of `words` or starts with one of `stems`, or does so
/// with its repeated letters squeezed when a letter's held (fuuuck); and anything in `anywhere` is starred out wherever it
/// appears, for scripts written without spaces and for phrases.
struct ChatFilter {
    private let words: Set<String>
    private let stems: [String]
    private let anywhere: [String]
    /// `words` and `stems` with their repeated letters squeezed, for the squeezed reading of a word:
    /// only those still four letters or more, so a short one squeezed (ass, as) can't catch a word.
    private let squeezedWords: Set<String>
    private let squeezedStems: [String]

    init(words: [String], stems: [String], anywhere: [String]) {
        let words = words.map(Self.fold)
        let stems = stems.map(Self.fold)
        self.words = Set(words)
        self.stems = stems
        self.anywhere = anywhere
        squeezedWords = Set(words.map(Self.squeeze).filter { $0.count >= 4 })
        squeezedStems = stems.map(Self.squeeze).filter { $0.count >= 4 }
    }

    init(_ def: ModerationDef) {
        self.init(words: def.words, stems: def.stems, anywhere: def.anywhere)
    }

    /// The filter on content/moderation.json.
    static let shared = ChatFilter(Content.shared.moderation)

    /// `text` with every rude word in it starred out, one star a letter, and whether there was any.
    func clean(_ text: String) -> (text: String, rude: Bool) {
        var out = ""
        var word = ""
        var rude = false
        func flush() {
            guard !word.isEmpty else { return }
            if isRude(word) {
                out += String(repeating: "*", count: word.count)
                rude = true
            } else {
                out += word
            }
            word = ""
        }
        for character in text {
            if character.isLetter || character.isNumber || character == "@" || character == "$" {
                word.append(character)
            } else {
                flush()
                out.append(character)
            }
        }
        flush()
        for phrase in anywhere {
            while let found = out.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
                out.replaceSubrange(found, with: String(repeating: "*", count: out[found].count))
                rude = true
            }
        }
        return (out, rude)
    }

    private func isRude(_ word: String) -> Bool {
        let folded = Self.fold(word)
        if words.contains(folded) || stems.contains(where: { folded.hasPrefix($0) }) { return true }
        // Squeezed only when a letter's held (fuuuck): plenty of harmless words double a letter, and
        // squeezed they'd meet a rude one (cazo, a saucepan, and cazzo; rappelle and rape).
        guard Self.holdsALetter(folded) else { return false }
        let squeezed = Self.squeeze(folded)
        return squeezedWords.contains(squeezed) || squeezedStems.contains(where: { squeezed.hasPrefix($0) })
    }

    /// Lower case, no accents, and the usual stand-ins for letters read as the letters.
    private static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(plain.map { stand[$0] ?? $0 })
    }

    private static let stand: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"]

    /// Whether some letter runs three times or more in a row.
    private static func holdsALetter(_ text: String) -> Bool {
        var run = 0
        var last: Character?
        for character in text {
            run = character == last ? run + 1 : 1
            last = character
            if run >= 3 { return true }
        }
        return false
    }

    /// Each run of the same letter as one (fuuuck: fuck).
    private static func squeeze(_ text: String) -> String {
        var out = ""
        for character in text where character != out.last { out.append(character) }
        return out
    }
}
