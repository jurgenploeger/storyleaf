import Foundation

nonisolated struct Equipment: Codable, Equatable, Sendable {
    var weapon: String?
    var armor: String?
    /// Saves from before these slots simply don't have them (nil).
    var gloves: String?
    var necklace: String?
    var boots: String?
    var accessory: String?

    subscript(slot: ItemType) -> String? {
        get {
            switch slot {
            case .weapon: weapon
            case .armor: armor
            case .gloves: gloves
            case .necklace: necklace
            case .boots: boots
            case .accessory: accessory
            case .consumable, .material: nil
            }
        }
        set {
            switch slot {
            case .weapon: weapon = newValue
            case .armor: armor = newValue
            case .gloves: gloves = newValue
            case .necklace: necklace = newValue
            case .boots: boots = newValue
            case .accessory: accessory = newValue
            case .consumable, .material: break
            }
        }
    }
}

nonisolated struct Hero: Codable, Equatable, Sendable {
    var name: String
    var raceID: String
    var classID: String
    var level: Int
    var exp: Int
    var hp: Int
    var mp: Int
    var equipment: Equipment
    /// Skill id → level (1 when learned; raised with skill points).
    var skillLevels: [String: Int]?
    var look: Look?
    /// Skills learned with skill points (nil in saves from before skills had to be learned).
    var learnedSkills: [String]?
    /// Extra points, e.g. for skills older saves got for free.
    var bonusSkillPoints: Int?
    /// Times reborn (Fairyland Online's 轉生): back to level 1, keeping skills and some strength.
    var rebirths: Int?
}

/// The hero's chosen colours and hairstyle (ids from content/appearance.json).
nonisolated struct Look: Codable, Equatable, Sendable {
    var hair: String
    var outfit: String
    var skin: String
    /// male | female (content/appearance.json `genders`); nil in older saves, which keep their
    /// race's original sheet, as does "other" from before it was dropped.
    var gender: String? = nil
    /// Hairstyle; nil means the walk sheet's own hair, else the race's (GameSession.style).
    var style: String? = nil

    static let standard = Look(hair: "ginger", outfit: "green", skin: "fair")

    var key: String { "\(hair)/\(outfit)/\(skin)/\(style ?? "-")" + (gender.map { "/" + $0 } ?? "") }
}

/// A captured monster travelling with the hero.
nonisolated struct Pet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var speciesID: String
    var name: String
    var level: Int
    var exp: Int
    var hp: Int
    var mp: Int
    /// Toys it has played with (`GameSession.giveToy`), and what they've raised for good.
    var toys: Int?
    var toyStats: Stats?
}

nonisolated struct QuestProgress: Codable, Equatable, Sendable {
    nonisolated enum State: String, Codable, Sendable {
        case active, completed
    }

    var state: State
    var count: Int
    /// What handing it in paid. Quests pay more at higher levels, so the Completed list shows what
    /// you really got; nil for quests handed in before 0.3.63, which paid their own reward.
    var paidGold: Int?
    var paidEXP: Int?
}

/// Everything that's written to disk.
nonisolated struct SaveData: Codable, Sendable {
    /// 2: the elder hands out the starter gifts (1: they were gift boxes around Meadowbrook).
    var version = 2
    var hero: Hero
    var pets: [Pet]
    var activePetID: UUID?
    var gold: Int
    var inventory: [String: Int]
    var quests: [String: QuestProgress]
    var mapID: String
    var position: [Double]?
    /// When this hero's story began; drives the in-game calendar.
    var startedAt: Date?
    /// Gift boxes already opened.
    var openedChests: [String]?
    /// What will hatch from the pet egg (from the elder's question).
    var eggSpecies: String?
    /// Where you wake up after fainting.
    var checkpoint: Checkpoint?
    /// Adventurers you've befriended, and which of them travel with you.
    var friends: [Adventurer]?
    var partyIDs: [UUID]?
    /// Bosses you've ever beaten (their NPC ids). They're back for a rematch on your next visit
    /// (`GameSession.bossesBeatenHere`).
    var defeatedBosses: [String]?
    /// Maps you've set foot on, for the world map.
    var visitedMaps: [String]?
    /// Levels were stretched from 1–33 to 1–105 (Fairyland Online's long climb); older saves are
    /// scaled up once so the hero still matches the zones they were in.
    var levelsRescaled: Bool?
    /// Skill levels were doubled when mastering went from 5 steps to 10 (see `rescaleSkillLevelsIfNeeded`).
    var skillLevelsDoubled: Bool?
    /// Your order of the battle buttons (see `GameSession.battleButtons`).
    var battleButtons: [String]?
    /// Trades already made with adventurers (`GameSession.TradeOffer.id`), so each offer is done once.
    var tradesDone: [String]?
    /// The Monster Book: every species met in battle, by id.
    var monsterBook: [String: MonsterSighting]?
    /// Monster cards found, by monster id: the first of each is kept in the Book, and the spares
    /// (sold as they turned up) are counted too.
    var cards: [String: Int]?
    /// Dark maps (caves): the cells you've seen by your light, one bit per cell (row by row from the
    /// south-west corner), by map id. The minimap shows only these.
    var explored: [String: Data]?
    /// Which save file this game lives in (SaveStore keeps one per game).
    var slot: String?
    /// When the game was last saved; the title screen shows it so you can tell your games apart.
    var savedAt: Date?
    /// Titles earned (content/titles.json ids), and the one worn over your name.
    var titles: [String]?
    var title: String?
    /// The Monster Book's milestones already paid (kinds of monster met).
    var bookRewards: [Int]?
    /// Today's bounties, and how many you've ever finished.
    var bounties: BountyBoard?
    var bountiesDone: Int?
    /// The daily gift: the day it was last given ("2026-10-06" on the phone's calendar), and on how
    /// many days it's been given (its place in the round).
    var giftDay: String?
    var giftDays: Int?
}

/// A day's bounties (the Quests tab): a few small jobs, new each calendar day.
nonisolated struct BountyBoard: Codable, Equatable, Sendable {
    /// The calendar day it's for ("2026-10-06").
    var day: String
    var bounties: [Bounty]
    /// The bonus for claiming them all.
    var bonusClaimed = false
}

nonisolated struct Bounty: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Sendable, CaseIterable {
        /// Monsters beaten on the land `target` (a map id).
        case defeatOnMap
        /// Monsters of the element `target` (an `Element`), anywhere.
        case defeatElement
        /// Fights won.
        case wins
        /// Rare monsters beaten.
        case rare
        /// Monsters sealed with a Seal Stone.
        case seal
    }
    /// The kind's name. A plain string, so a save never fails to load over a kind that's gone: such a
    /// bounty just stops counting.
    var kind: String
    var target: String?
    var count: Int
    var progress = 0
    var exp: Int
    var gold: Int
    var claimed = false

    init(kind: Kind, target: String? = nil, count: Int, exp: Int, gold: Int) {
        self.kind = kind.rawValue
        self.target = target
        self.count = count
        self.exp = exp
        self.gold = gold
    }

    var type: Kind? { Kind(rawValue: kind) }
    var isDone: Bool { progress >= count }
}

/// A Monster Book entry: how many you've beaten and the levels you've met it at.
nonisolated struct MonsterSighting: Codable, Equatable, Sendable {
    var defeated = 0
    var lowestLevel: Int
    var highestLevel: Int
}

/// Another adventurer (Fairyland's other players): met on the map, befriended, and maybe
/// invited to travel and fight alongside you.
nonisolated struct Adventurer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var raceID: String
    var classID: String
    var level: Int
    var look: Look
    var petSpecies: String?
    /// Red-named troublemakers in danger zones pick fights.
    var hostile = false
    /// A friend in your party who isn't at your side: where they wait for you to come back for them
    /// (where a fight you fainted in was, or their own checkpoint after one they fainted in).
    var waitingAt: Spot?
    /// Where they wake up after fainting: the last checkpoint they reached with you.
    var checkpoint: Checkpoint?
    /// A friend's HP and MP as their last fight at your side left them (they carry over, like
    /// yours); nil: full. Their own heals in a fight, and the healer, top them up.
    var hp: Int? = nil
    var mp: Int? = nil
    /// Plain Seal Stones they carry: one without a companion throws them in a fight to catch one
    /// (`BattleEngine.sealAttempt`). nil: the two everyone set out with.
    var sealStones: Int? = nil

    var stonesLeft: Int { sealStones ?? 2 }
}

/// A town square, or the entrance you last walked into a map through.
nonisolated struct Checkpoint: Codable, Equatable, Sendable {
    var mapID: String
    /// nil: the map's centre (towns); otherwise just inside this edge.
    var entry: Edge?
}

/// Somewhere on a map: a point on it, or a checkpoint's spot (an entrance, or a town's square).
nonisolated struct Spot: Codable, Equatable, Sendable {
    var mapID: String
    /// Where on the map, in scene points like `SaveData.position`; nil: `entry`'s spot.
    var position: [Double]?
    /// Just inside this edge; with no position either, the map's centre.
    var entry: Edge?
}

/// One file per game, so starting a new game never overwrites another (the title screen lists them).
enum SaveStore {
    /// Tests and debug launches use their own names so they never touch your real games.
    static var fileName = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        ? "fairyland-tests-save.json"
        : "fairyland-save.json"
    /// The games live in a folder named after `fileName`.
    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: String(fileName.dropLast(".json".count)), directoryHint: .isDirectory)
    }
    /// The single save from before there were several (moved into the folder on first look).
    static var legacyURL: URL { URL.applicationSupportDirectory.appending(path: fileName) }

    static func url(for slot: String) -> URL { folder.appending(path: "\(slot).json") }

    static var exists: Bool { !all().isEmpty }

    /// The slot the save from before the folder moves into, when it had none.
    static let legacySlot = "first-game"

    /// Every saved game, the most recently played first.
    static func all() -> [SaveData] {
        moveLegacySave()
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var games = files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> (file: URL, data: SaveData, played: Date)? in
                guard let raw = try? Data(contentsOf: file), var data = try? JSONDecoder().decode(SaveData.self, from: raw) else { return nil }
                data.slot = data.slot ?? file.deletingPathExtension().lastPathComponent
                let played = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return (file, data, played)
            }
            .sorted { $0.played < $1.played }
        // Until 0.3.14 the save from before the folder moved in again every time the title screen
        // looked, each time as a "new" game. Of games that are the same but for their slot, only the
        // oldest copy stays, so it doesn't push ahead of the games you actually played.
        var seen = Set<Data>()
        games.removeAll { game in
            var plain = game.data
            plain.slot = nil
            plain.savedAt = nil
            guard let key = try? comparer.encode(plain) else { return false }
            if seen.insert(key).inserted { return false }
            try? manager.removeItem(at: game.file)
            return true
        }
        return games.reversed().map { game in
            var data = game.data
            data.savedAt = data.savedAt ?? game.played
            return data
        }
    }

    /// Sorted keys, so two copies of one game encode exactly alike.
    private static let comparer: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// The most recently played game.
    static func load() -> SaveData? { all().first }

    static func save(_ data: SaveData) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: url(for: data.slot ?? "game"), options: .atomic)
        } catch {
            print("⚠️ Couldn't save the game: \(error)")
        }
    }

    /// A backup brought back (the title screen's Import a backup) as a game of its own, in a new
    /// slot so it never overwrites one. Throws when the file isn't a Fairyland save.
    static func imported(_ raw: Data) throws -> SaveData {
        var data = try JSONDecoder().decode(SaveData.self, from: raw)
        data.slot = "imported-" + UUID().uuidString.prefix(8).lowercased()
        return data
    }

    static func delete(slot: String) {
        try? FileManager.default.removeItem(at: url(for: slot))
    }

    /// Moves the single save from before the folder into it, once. It always lands in the same slot
    /// and never over a game that's already there, and the old file goes as soon as it has.
    private static func moveLegacySave() {
        let manager = FileManager.default
        // `path()` would escape the space in "Application Support" and find nothing: that's how the
        // old file used to stay behind and move in again and again.
        guard manager.fileExists(atPath: legacyURL.path(percentEncoded: false)),
              let raw = try? Data(contentsOf: legacyURL), var data = try? JSONDecoder().decode(SaveData.self, from: raw) else { return }
        let slot = data.slot ?? legacySlot
        data.slot = slot
        let destination = url(for: slot).path(percentEncoded: false)
        if !manager.fileExists(atPath: destination) { save(data) }
        if manager.fileExists(atPath: destination) {
            try? manager.removeItem(at: legacyURL)
        }
    }
}
