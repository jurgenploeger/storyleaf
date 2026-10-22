import AVFoundation
import UIKit

/// The player's settings (the Settings tab), kept in UserDefaults. The Settings screen edits the
/// same keys with @AppStorage, so the defaults here and there must match.
nonisolated enum GameSettings {
    static let musicVolumeKey = "musicVolume"
    static let soundVolumeKey = "soundVolume"
    /// Sound effects on or off (Settings), apart from their volume.
    static let soundEffectsKey = "soundEffects"
    static let footstepsKey = "footsteps"
    static let hapticsKey = "haptics"
    /// The light follows the clock through night and day; off, it's always daytime (`Sky`).
    static let dayAndNightKey = "dayAndNight"
    /// The weather comes and goes; off, the sky stays clear (`Weather.on`).
    static let weatherKey = "weather"
    /// The top-left HUD folds a party of three or more into one row (WorldHUD); the player can unfold it.
    static let partyFoldedKey = "partyFolded"
    /// Battles ask what your companion should do after the hero's choice; off, it fights on its own.
    static let commandCompanionKey = "commandCompanion"
    /// How fast fights play, 1 or 2 (the 2× button in a fight), kept from fight to fight.
    static let battleSpeedKey = "battleSpeed"
    /// Auto, switched on in a fight, stays on for the next fights it's allowed in.
    static let autoBattleKey = "autoBattle"
    /// Seconds to choose each move in a fight before the hero attacks on their own (0: no clock).
    static let turnTimerKey = "turnTimer"
    /// What Settings offers for it, Off first.
    static let turnTimerChoices: [Double] = [0, 10, 20, 30]
    /// The newest release notes opened from the title screen (What's new); newer ones get its gold dot.
    static let seenReleaseKey = "seenRelease"

    static var musicVolume: Double { value(musicVolumeKey, fallback: 1) }
    static var soundVolume: Double { value(soundVolumeKey, fallback: 1) }
    static var soundEffects: Bool { value(soundEffectsKey, fallback: true) }
    static var footsteps: Bool { value(footstepsKey, fallback: true) }
    static var haptics: Bool { value(hapticsKey, fallback: true) }
    static var dayAndNight: Bool { value(dayAndNightKey, fallback: true) }
    static var weather: Bool { value(weatherKey, fallback: true) }
    static var commandCompanion: Bool { value(commandCompanionKey, fallback: true) }
    static var battleSpeed: Double { value(battleSpeedKey, fallback: 1) }
    static var autoBattle: Bool { value(autoBattleKey, fallback: false) }
    static var turnTimer: Double { value(turnTimerKey, fallback: 10) }

    private static func value<T>(_ key: String, fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }
}

/// Short sound effects from sound/*.wav (made by tools/make_sounds.py), played over the music.
/// Uses the same "ambient" audio session as the music, so the silent switch mutes them too.
final class SoundEffects {
    static let shared = SoundEffects()

    enum Sound: String, CaseIterable {
        case tap, close, talk, step
        case hit, crit, magic, heal, potion, shield = "guard", capture, breakFree = "break_free", run, poof, faint, lose
        case levelUp = "level_up", coins, questAccept = "quest_accept", questDone = "quest_done"
        case chest, hatch, equip, learn, whoosh, encounter
        // Skills in battle: blows, each element's spells, buffs and curses, and the swell and the
        // grand chord of the strongest.
        case strike, spellFire = "spell_fire", spellWater = "spell_water", spellWood = "spell_wood"
        case spellEarth = "spell_earth", spellLight = "spell_light", spellDark = "spell_dark", spellMetal = "spell_metal"
        case buff, curse, surge, ultimate

        /// What a skill sounds like as it lands: a blow strikes, a spell sounds like its element.
        static func landing(_ skill: SkillDef) -> Sound {
            switch skill.kind {
            case .heal, .revive: .heal
            case .buff, .field: .buff
            case .curse: .curse
            case .physical: .strike
            case .magic:
                switch skill.element ?? .neutral {
                case .fire: .spellFire
                case .water: .spellWater
                case .wood: .spellWood
                case .earth: .spellEarth
                case .light: .spellLight
                case .dark: .spellDark
                case .metal: .spellMetal
                case .neutral: .magic
                }
            }
        }
    }

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var turn: [Sound: Int] = [:]
    /// Unit tests don't need sound.
    private let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    private init() {}

    func play(_ sound: Sound, volume: Float = 1) {
        let level = Float(GameSettings.soundVolume) * volume
        guard isEnabled, GameSettings.soundEffects, level > 0.001, let player = nextPlayer(for: sound) else { return }
        player.volume = min(1, level)
        player.currentTime = 0
        player.play()
    }

    /// Loads every sound ahead of time, so the first of each plays without a hitch.
    func preload() {
        guard isEnabled else { return }
        for sound in Sound.allCases where players[sound] == nil {
            players[sound] = load(sound)
        }
    }

    private func nextPlayer(for sound: Sound) -> AVAudioPlayer? {
        if players[sound] == nil { players[sound] = load(sound) }
        guard let pool = players[sound], !pool.isEmpty else { return nil }
        let index = (turn[sound] ?? 0) % pool.count
        turn[sound] = index + 1
        return pool[index]
    }

    private func load(_ sound: Sound) -> [AVAudioPlayer] {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "sound") else { return [] }
        // A few copies, so quick repeats (footsteps, hits) overlap instead of cutting each other off.
        return (0..<3).compactMap { _ in
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            return player
        }
    }
}

/// Little taps of the Taptic Engine on hits and rewards (off in Settings → Haptics).
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard GameSettings.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard GameSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
