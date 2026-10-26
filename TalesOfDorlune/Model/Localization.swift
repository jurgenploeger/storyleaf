import Foundation
import Observation

/// Looks `english` up in the chosen language's table (content/i18n/<code>.json) and fills its
/// `{name}` placeholders from `args`. A string with no translation yet stays English. Keys are the
/// English text itself, so `tools/i18n.py extract` finds every `L("…")` in the code.
nonisolated func L(_ english: String, _ args: [String: Any] = [:]) -> String {
    var text = Strings.table[english] ?? english
    for (key, value) in args {
        text = text.replacingOccurrences(of: "{\(key)}", with: "\(value)")
    }
    return text
}

/// The current language's strings, readable from anywhere (battle code runs off the main actor).
nonisolated enum Strings {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: [String: String] = [:]

    static var table: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    static func use(_ table: [String: String]) {
        lock.lock()
        current = table
        lock.unlock()
    }
}

/// A language the game is translated into (content/i18n/languages.json).
nonisolated struct GameLanguage: Decodable, Identifiable, Equatable, Sendable {
    /// "en", "pt-BR", "zh-Hans"…: also the name of its table, content/i18n/<code>.json.
    let code: String
    /// Its own name for itself ("Deutsch", "日本語").
    let name: String
    var id: String { code }
}

/// The language the game speaks, picked on the title screen or in Settings (kept in
/// UserDefaults). Until the player picks one it follows the phone's language, if the game has it.
/// Switching loads that language's table and re-reads the game data in it (`Content.reload`).
@Observable
final class Localizer {
    static let shared = Localizer()
    static let languageKey = "language"

    let languages: [GameLanguage]
    private(set) var language: String

    var current: GameLanguage { languages.first { $0.code == language } ?? GameLanguage(code: "en", name: "English") }
    /// For dates and numbers.
    var locale: Locale { Locale(identifier: language) }

    private init(bundle: Bundle = .main) {
        languages = Self.loadLanguages(bundle) ?? [GameLanguage(code: "en", name: "English")]
        let codes = languages.map(\.code)
        let saved = UserDefaults.standard.string(forKey: Self.languageKey)
        language = saved.flatMap { codes.contains($0) ? $0 : nil } ?? Self.preferred(among: codes)
        Strings.use(Self.table(for: language, bundle: bundle))
    }

    /// Speak `code` from now on: its strings, and the game data re-read in it. `remember: false`
    /// (debug launches) leaves the player's own choice alone.
    func choose(_ code: String, remember: Bool = true) {
        guard code != language, languages.contains(where: { $0.code == code }) else { return }
        language = code
        if remember { UserDefaults.standard.set(code, forKey: Self.languageKey) }
        Strings.use(Self.table(for: code, bundle: .main))
        Content.shared.reload()
    }

    /// The phone's first preferred language the game has: an exact match ("pt-BR"), else the same
    /// language and script ("zh-Hant" for zh-Hant-TW), else the language alone ("es" for es-MX).
    static func preferred(among codes: [String], preferences: [String] = Locale.preferredLanguages) -> String {
        for preference in preferences {
            if codes.contains(preference) { return preference }
            let parts = preference.split(separator: "-").map(String.init)
            if parts.count > 1, codes.contains("\(parts[0])-\(parts[1])") { return "\(parts[0])-\(parts[1])" }
            // Chinese written without a script: Taiwan, Hong Kong and Macau read Traditional.
            if parts.first == "zh" {
                let traditional = parts.contains { ["TW", "HK", "MO", "Hant"].contains($0) }
                let code = traditional ? "zh-Hant" : "zh-Hans"
                if codes.contains(code) { return code }
            }
            if let first = parts.first, let match = codes.first(where: { $0 == first || $0.hasPrefix(first + "-") }) { return match }
        }
        return "en"
    }

    /// A language's strings: English text to translation. English has none (its keys are its text).
    static func table(for code: String, bundle: Bundle) -> [String: String] {
        guard code != "en", let url = bundle.url(forResource: code, withExtension: "json", subdirectory: "content/i18n"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(StringsFile.self, from: data)
        else { return [:] }
        return file.strings.filter { !$0.value.isEmpty }
    }

    private static func loadLanguages(_ bundle: Bundle) -> [GameLanguage]? {
        guard let url = bundle.url(forResource: "languages", withExtension: "json", subdirectory: "content/i18n"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(LanguagesFile.self, from: data).languages
    }

    private nonisolated struct StringsFile: Decodable { let strings: [String: String] }
    private nonisolated struct LanguagesFile: Decodable { let languages: [GameLanguage] }
}

extension String {
    /// A name dropped into the middle of a sentence: lowercased in English ("the gift box is
    /// empty"), left as it is in other languages, whose own rules decide (German capitalises nouns).
    var midSentence: String { Localizer.shared.language == "en" ? lowercased() : self }
}
