import Foundation

// MARK: - Stats & elements

nonisolated struct Stats: Codable, Equatable, Sendable {
    var hp: Int
    var mp: Int
    var attack: Int
    var defense: Int
    var magic: Int
    var speed: Int

    enum CodingKeys: String, CodingKey {
        case hp, mp, attack, defense, magic, speed
    }

    static let zero = Stats()

    init(hp: Int = 0, mp: Int = 0, attack: Int = 0, defense: Int = 0, magic: Int = 0, speed: Int = 0) {
        self.hp = hp
        self.mp = mp
        self.attack = attack
        self.defense = defense
        self.magic = magic
        self.speed = speed
    }

    /// One stat by its name in the content (hp, mp, attack, defense, magic or speed); none for
    /// any other name.
    init(named stat: String, _ amount: Int) {
        self.init()
        switch stat {
        case "hp": hp = amount
        case "mp": mp = amount
        case "attack": attack = amount
        case "defense": defense = amount
        case "magic": magic = amount
        case "speed": speed = amount
        default: break
        }
    }

    /// Fields missing from the JSON count as 0, so content only lists what matters.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = try container.decodeIfPresent(Int.self, forKey: .hp) ?? 0
        mp = try container.decodeIfPresent(Int.self, forKey: .mp) ?? 0
        attack = try container.decodeIfPresent(Int.self, forKey: .attack) ?? 0
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 0
        magic = try container.decodeIfPresent(Int.self, forKey: .magic) ?? 0
        speed = try container.decodeIfPresent(Int.self, forKey: .speed) ?? 0
    }

    static func + (lhs: Stats, rhs: Stats) -> Stats {
        Stats(
            hp: lhs.hp + rhs.hp, mp: lhs.mp + rhs.mp, attack: lhs.attack + rhs.attack,
            defense: lhs.defense + rhs.defense, magic: lhs.magic + rhs.magic, speed: lhs.speed + rhs.speed
        )
    }

    static func * (lhs: Stats, factor: Int) -> Stats {
        Stats(
            hp: lhs.hp * factor, mp: lhs.mp * factor, attack: lhs.attack * factor,
            defense: lhs.defense * factor, magic: lhs.magic * factor, speed: lhs.speed * factor
        )
    }
}

/// Fairyland's seven elements. The classic five-element cycle — each element overcomes the
/// next — plus light and dark, which overcome each other. Strong hits deal 1.5×, resisted 0.75×.
nonisolated enum Element: String, Codable, CaseIterable, Sendable {
    case neutral, metal, wood, water, fire, earth, light, dark

    /// water → fire → metal → wood → earth → water
    private static let cycle: [Element] = [.water, .fire, .metal, .wood, .earth]

    func multiplier(against defender: Element) -> Double {
        if (self == .light && defender == .dark) || (self == .dark && defender == .light) { return 1.5 }
        guard let attacker = Self.cycle.firstIndex(of: self), let target = Self.cycle.firstIndex(of: defender) else { return 1 }
        if (attacker + 1) % Self.cycle.count == target { return 1.5 }
        if (target + 1) % Self.cycle.count == attacker { return 0.75 }
        return 1
    }

    var displayName: String {
        switch self {
        case .neutral: L("Neutral")
        case .metal: L("Metal")
        case .wood: L("Wood")
        case .water: L("Water")
        case .fire: L("Fire")
        case .earth: L("Earth")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }

    /// Elements this one hits harder (×1.5), and the ones that hit it harder.
    var strongAgainst: [Element] { Element.allCases.filter { multiplier(against: $0) > 1 } }
    var weakTo: [Element] { Element.allCases.filter { $0.multiplier(against: self) > 1 } }
}

// MARK: - Definitions (one per JSON file in content/)

nonisolated struct RaceDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let base: Stats
    /// This race's walk sheet in art/assets.json.
    let art: String?
    /// Gender id → its own walk sheet; genders without one use `art`.
    let sheets: [String: String]?
    /// The hairstyle a hero of this race starts with (an AppearanceOptions `styles` id).
    let hair: String?

    var sheet: String { art ?? "player_walk" }

    func sheet(for gender: String?) -> String {
        gender.flatMap { sheets?[$0] } ?? sheet
    }
}

nonisolated struct ClassDef: Decodable, Identifiable, Sendable {
    nonisolated struct SkillUnlock: Decodable, Sendable {
        let skill: String
        let level: Int
    }

    let id: String
    let name: String
    let guild: String?
    let description: String
    let growth: Stats
    let skills: [SkillUnlock]
    /// Multiplies capture chance (Beast Tamers are better at taming).
    let captureBonus: Double?
    /// Share of battle EXP the active companion receives (default 0.5).
    let petExpShare: Double?
}

nonisolated enum SkillKind: String, Decodable, Sendable {
    /// `revive` wakes a fainted ally, `buff` raises the stats in its `raises` for a few rounds,
    /// `curse` lays its `inflicts` on foes without hurting them (Curse, Poison), and `field` spells
    /// are cast from the Character screen outside battle (Bridge of Light).
    case physical, magic, heal, revive, buff, curse, field

    /// Hurts the other side with a hit.
    var isAttack: Bool { self == .physical || self == .magic }
    /// Aimed at the other side: an attack or a curse (what monsters and companions pick to fight with).
    var isHostile: Bool { isAttack || self == .curse }
}

/// What a skill leaves on the fighters it reaches, for a few rounds (`inflicts` in skills.json).
nonisolated struct Affliction: Decodable, Sendable {
    let effect: Ailment
    /// Poison: how many times it bites, at the end of the round it lands in and the ones after.
    /// Curse: how many rounds it lasts after the one it lands in. Freeze: how many turns it loses.
    let rounds: Int
    /// Poison: each round's bite, as a share of a hit from the caster (magic for spells, strength
    /// for bites). Curse: how much it lowers the target's stats (0.2 = 20%, at most half). Both
    /// grow with the skill's level, like its damage would.
    let power: Double
    /// The odds it takes hold (always, unless set).
    let chance: Double?
    /// Curse: the stats it lowers ("attack", "defense", "magic", "speed"); attack and magic, the
    /// force behind every hit, unless set.
    let stats: [String]?
}

/// Fairyland's dark arts (the Acolyte of Dark's Curse and Poison): lingering harm, not a hit.
nonisolated enum Ailment: String, Decodable, Sendable {
    /// Loses HP at the end of every round.
    case poison
    /// Hits for less.
    case curse
    /// Frozen solid (snow and ice): loses its next `rounds` turns.
    case freeze
}

nonisolated enum SkillTarget: String, Decodable, Sendable {
    case enemy, allEnemies, ally, allAllies
    /// A fainted fighter on your own side (Revive).
    case fallenAlly
}

nonisolated struct SkillDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let mp: Int
    let kind: SkillKind
    let element: Element?
    let power: Double
    let target: SkillTarget
    let description: String?
    /// Battle effect: slash | whirlwind | fire | stone | leaves | water | heal | holy | wild | needles | bounce | bite
    let animation: String?
    /// A GameIcon name for menus.
    let icon: String?
    /// Its pixel-art icon (art/sprites/skill_<id>.png, drawn by tools/skill_art.py).
    let art: String?
    /// Spells: the share of damage that also hits the target's neighbours once mastered (level 10);
    /// 60% of that from level 5, growing each step, none below.
    let splash: Double?
    /// A poison or curse it leaves on whoever it reaches (not the splash).
    let inflicts: Affliction?
    /// Buffs: the stats it raises and by how much at skill level 1 ("attack": 0.25 = +25%), more
    /// as the skill grows like damage does; and any it lowers in return (Berserk's guard), which
    /// stay put.
    let raises: [String: Double]?
    let lowers: [String: Double]?
    /// Buffs: how many rounds it lasts after the one it's cast in (3 unless set).
    let rounds: Int?
}

nonisolated struct MonsterDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let art: String
    let element: Element
    /// The Monster Book's entry, unlocked by meeting it in battle.
    let lore: String?
    let base: Stats
    let growth: Stats
    let exp: Int
    let gold: Int
    let captureRate: Double
    let skills: [String]
    /// A rarer colour variant: tougher, worth more, harder to catch.
    let rare: Bool?
    /// The species this is a colour variant of.
    let variantOf: String?
    /// How it fidgets standing still: breathe | squish | hop | sway | bounce.
    let motion: String?
    /// Bosses can't be captured and never run away.
    let boss: Bool?
    /// Rare spoils, rolled every time it's beaten (bosses come back for rematches).
    let drops: [Drop]?

    nonisolated struct Drop: Decodable, Sendable {
        let item: String
        /// 0...1, rolled on each win.
        let chance: Double
    }

    func stats(at level: Int) -> Stats { base + growth * (level - 1) }
}

nonisolated enum ItemType: String, Decodable, Sendable {
    /// `material`: wood, metal, gems and hides that monsters drop, for the blacksmith.
    /// `accessory`: rings, charms and bands; `gloves`, `necklace` and `boots` have slots of their own.
    case consumable, weapon, armor, gloves, necklace, boots, accessory, material

    /// Every slot the hero wears something in, in the order lists show them.
    static let equipmentSlots: [ItemType] = [.weapon, .armor, .gloves, .boots, .necklace, .accessory]

    /// The small pieces worn next to a weapon and armour: few next to dozens of weapons and
    /// armours, so they drop on a share of their own (`GameSession.accessoryShare`).
    var isTrinket: Bool { [.gloves, .necklace, .boots, .accessory].contains(self) }

    var displayName: String {
        switch self {
        case .consumable: L("Consumable")
        case .weapon: L("Weapon")
        case .armor: L("Armor")
        case .gloves: L("Gloves")
        case .necklace: L("Necklace")
        case .boots: L("Boots")
        case .accessory: L("Accessory")
        case .material: L("Material")
        }
    }
}

nonisolated struct ItemDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: ItemType
    let price: Int
    let heal: Int?
    let mp: Int?
    let stats: Stats?
    let classes: [String]?
    let level: Int?
    let description: String?
    /// For eggs: the species that can hatch from it.
    let hatches: [String]?
    /// Its sprite in art/assets.json (item_<id>, drawn by tools/item_art.py).
    let art: String?
    /// A GameIcon name for the bag and shops when there's no sprite.
    let icon: String?
    /// Seal Stones: thrown in battle to befriend a weakened monster.
    let capture: Bool?
    /// Seal Stones: how many times likelier than a plain one to seal a monster (1 unless set), and
    /// for a Wishing Seal, `sure`: it never fails on a monster that can be befriended.
    let sealPower: Double?
    let sure: Bool?
    /// Homeward Feathers: used from the bag outside battle, they carry you to your checkpoint like
    /// Bridge of Light, for any class.
    let travel: Bool?
    /// Companion toys (Fairyland Online's Pet Toys): given to a companion from the bag, they raise
    /// its `stats` for good, up to `GameSession.toysPerCompanion` toys each.
    let toy: Bool?
    /// Armour: how it recolours the hero's outfit while worn (same rules as looks).
    let recolor: [RecolorRule]?
    /// Materials: wood | metal | gem | hide. Monsters of at least `level` drop them.
    let material: String?
    /// What a blacksmith needs to forge it: material id → how many.
    let recipe: [String: Int]?
    /// How it changes the hero's sprite (see GearOverlay): armour's cut (vest | mail | plate | robe |
    /// cloak), or "boots" for footwear.
    let wear: String?
    /// Finer work drawn on stronger armour: engraved | scales | fur | runes | pockets.
    let pattern: String?
    /// Whole walk sheets (art/sprites) per race id, worn instead of the paper-doll layers.
    let sheets: [String: String]?
    /// A rare colour variant's recolour of those sheets.
    let tint: [RecolorRule]?
    /// Trim colour on the sprite (buttons, clasps, hems) and an accessory's sparkle, "#RRGGBB".
    let accent: String?
    /// Magic weapons: a soft light while held, "#RRGGBB", centred on `glowAt` ([x, y] in the 32×32 art).
    let glow: String?
    let glowAt: [Double]?
}

nonisolated struct QuestDef: Decodable, Identifiable, Sendable {
    nonisolated enum ObjectiveType: String, Decodable, Sendable {
        /// `cards`: kinds of monster card in the Monster Book, `count` of them.
        case defeat, capture, reachLevel, chooseClass, collect, hatch, cards
    }

    /// Asked when accepting; the answer decides which companion hatches from the egg.
    nonisolated struct Question: Decodable, Sendable {
        nonisolated struct Answer: Decodable, Sendable {
            let text: String
            let egg: String
        }

        let text: String
        let answers: [Answer]
    }

    nonisolated struct Objective: Decodable, Sendable {
        let type: ObjectiveType
        let target: String?
        let count: Int?
    }

    nonisolated struct Reward: Decodable, Sendable {
        let gold: Int?
        let exp: Int?
        let items: [String]?
    }

    let id: String
    let title: String
    let giver: String
    let description: String
    let requires: [String]?
    let minLevel: Int?
    let question: Question?
    let objective: Objective
    let reward: Reward
    /// Items handed over when you accept (e.g. Seal Stones for the capture quest).
    let starterItems: [String]?
}

nonisolated enum Edge: String, Codable, Sendable {
    case north, south, east, west

    var opposite: Edge {
        switch self {
        case .north: .south
        case .south: .north
        case .east: .west
        case .west: .east
        }
    }
}

nonisolated enum NPCRole: String, Decodable, Sendable {
    /// `boss`: a mighty monster waiting on the map; talk to it to fight.
    /// `smith`: forges weapons from materials (the item's `recipe`).
    case healer, shop, quests, guild, chest, boss, smith
}

nonisolated struct NPCDef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let role: NPCRole
    let art: String
    let x: Int
    let y: Int
    let greeting: String
    let stock: [String]?
    let classId: String?
    /// Chests: the item inside, and the quest that unlocks them.
    let gives: String?
    let quest: String?
    /// Bosses: which monster, at what level, and how many of the map's own monsters fight at its
    /// side in its own wave (9 unless set, so the wave is 10 strong; 0 for none).
    let monster: String?
    let level: Int?
    let minions: Int?
    /// Bosses: how many waves the fight comes in (3 unless set): waves of the map's monsters,
    /// then the boss with its minions. 1 is the boss alone with its minions.
    let waves: Int?
    /// Bosses: what beating it means, told the first time you win (and kept in the Monster Book).
    let victory: Victory?
    /// Offers rebirth once you're strong enough (Elder Oak).
    let rebirth: Bool?

    nonisolated struct Victory: Decodable, Sendable {
        let title: String
        /// A few short paragraphs, shown one after another.
        let story: [String]
    }
}

nonisolated struct MapDef: Decodable, Identifiable, Sendable {
    nonisolated struct Theme: Decodable, Sendable {
        let ground: String
        let path: String
        let accent: String?
        /// Number of accent patches (flower meadows etc.); without it accents are scattered.
        let accentPatches: Int?
        /// Ground outside a fenced town.
        let border: String?
        /// Water tile for ponds.
        let water: String?
        let ponds: Int?
        let fairyRings: FairyRings?
        let props: [PropPlacement]
        /// The map's colour mood for ground, scenery and buildings.
        let palette: MapPalette?
        /// Caves are solid rock with tunnels and chambers dug out of it.
        let cave: Cave?
        /// Grassy hills to climb, out in the fields (not towns or caves).
        let hills: Hills?
    }

    /// Raised ground you walk up a ramp to: a bank along the sides facing you, the top like the
    /// ground around it.
    nonisolated struct Hills: Decodable, Sendable {
        let count: Int
        /// Radius in cells, [smallest, biggest] (3 to 6 when not given).
        let size: [Int]?
        /// How high they stand, in points (22 when not given).
        let height: Double?
        /// The tile their banks are drawn in (tile_scree when not given).
        let bank: String?
    }

    /// Solid rock everywhere except galleries along the roads and trails, chambers off them and
    /// dead-end tunnels, drawn as raised walls you walk between (and behind).
    nonisolated struct Cave: Decodable, Sendable {
        /// Tile for the tops and faces of the walls.
        let rock: String
        /// How tall the walls stand, in points (40 by default).
        let height: Double?
        /// Half-width of the galleries around roads and trails, in cells (3 by default; 0.5 or more).
        let width: Double?
        /// Extra chambers dug off the galleries.
        let chambers: Int?
        /// Dead-end tunnels branching off, for a bit of a maze.
        let branches: Int?
        /// Narrow zigzag passages linking parts of the cave.
        let zigzags: Int?
        /// A maze of narrow passages over the whole cave, with junctions about this many cells apart.
        let maze: Int?
    }

    nonisolated struct PropPlacement: Decodable, Sendable {
        let art: String
        let count: Int
        let blocking: Bool
        /// Grow in groups of about this many (groves, rock piles) instead of evenly.
        let cluster: Int?
        /// How far (in cells) a group spreads from its centre; smaller packs a grove tighter.
        let spread: Int?
        /// Each one is drawn at a random size in this range ([0.8, 1.25] = 80% to 125%).
        let size: [Double]?
        /// A soft glow around each one (crystals, glowing mushrooms, lanterns), e.g. "#9FE8FF".
        let glow: String?
        /// A soft shadow on the ground under each one (trees, big rocks).
        let shadow: Bool?
        /// Sways gently in the breeze.
        let sway: Bool?
        /// Floats gently up and down (magic lanterns, floating crystals).
        let bob: Bool?
        /// Plant only within this many cells of the map's centre, inside a town's fence too
        /// (flower beds around the square). Otherwise props go anywhere free (in towns: the border).
        let within: Int?
    }

    nonisolated struct FairyRings: Decodable, Sendable {
        let count: Int
        let art: String
    }

    nonisolated struct Decor: Decodable, Sendable {
        let art: String
        let x: Int
        let y: Int
        let blocking: Bool?
    }

    /// Whimsy: floating particles, butterflies, cloud shadows and a colour mood.
    nonisolated struct Ambience: Decodable, Sendable {
        /// petals | leaves | fireflies | sparkles | snow | dust | motes | bubbles | dandelions | sprinkles |
        /// lanterns | zzz | notes, or several joined with "+".
        let particles: String?
        let butterflies: Int?
        /// Little animals living on the map that hop off when you come close. See `Critters`.
        let critters: [Critter]?
        /// A flock crossing the sky now and then: songbirds | gulls | bats.
        let birds: String?
        let clouds: Bool?
        /// Hex colour laid over the map, e.g. "#3A2A6B".
        let tint: String?
        let tintAlpha: Double?
        let vignette: Double?
        /// Soft pools of light on the ground (dappled sunlight, moonlight). See `Lighting`.
        let lightPatches: Lights?
        /// Long soft sunbeams slanting across the map.
        let sunbeams: Lights?
        /// A big soft glow in the top corner of the screen, as if the sun were just out of view.
        let sun: String?
        /// Distance haze: the top of the screen fades toward this colour, by `hazeAlpha`.
        let haze: String?
        let hazeAlpha: Double?
        /// Depth of field on the map's own scenery (on by default). See `DepthOfField`.
        let focus: Focus?
        /// A dark map (a cave): you see only as far as your light reaches, and the minimap shows only
        /// what you've seen. See `Lantern`.
        let darkness: Darkness?
        /// How likely each weather is here (clear | cloudy | rain | storm | fog | snow), by weight; it
        /// changes every few in-game hours. Unset: mostly clear, sometimes cloudy, rainy or foggy. `{}`
        /// keeps the sky out. A dark map has neither weather nor day and night. See `Weather` and `Sky`.
        let weather: [String: Double]?

        nonisolated struct Critter: Decodable, Sendable {
            /// bunny | frog | crab | songbird | chick | squirrel | lizard | mouse | crow | spider | rat |
            /// scorpion | wisp
            let kind: String
            let count: Int
        }

        nonisolated struct Lights: Decodable, Sendable {
            let color: String
            let count: Int
            /// Width range in points.
            let size: [Double]?
            let alpha: Double?
        }

        nonisolated struct Darkness: Decodable, Sendable {
            /// How far your light reaches, in points (default 190).
            let radius: Double?
            /// How dark it is beyond, 0...1 (default 0.9).
            let alpha: Double?
            /// The dark's colour (default "#03040A").
            let color: String?
            /// Your light's soft glow on the ground around you (none if unset).
            let light: String?
        }

        nonisolated struct Focus: Decodable, Sendable {
            /// Strongest blur in points, at the top of the screen (default 1.5; 0 turns it off).
            let blur: Double?
            /// Half-height of the sharp band around the hero, as a fraction of half the screen (default 0.4).
            let band: Double?
            /// How soft the bottom of the screen gets compared with the top (default 0.5).
            let near: Double?
        }
    }

    nonisolated struct Exit: Decodable, Sendable {
        let edge: Edge
        let to: String
        /// A quest you must finish before this road opens.
        let requires: String?
        /// Where along its edge the road leaves, in cells from the middle of the edge (east/north positive).
        let at: Int?
        /// Waypoints the road winds through on its way out, as [x, y] cell offsets from the centre.
        let via: [[Int]]?
    }

    /// A narrower path off the roads, to somewhere worth visiting (a boss's lair, an oasis).
    nonisolated struct Trail: Decodable, Sendable {
        /// [x, y] cell offsets from the centre. Starts at the hub unless `from` is set.
        let to: [Int]
        let from: [Int]?
        let via: [[Int]]?
    }

    nonisolated struct Building: Decodable, Sendable {
        let art: String
        let x: Int
        let y: Int
    }

    nonisolated struct Encounters: Decodable, Sendable {
        let rate: Double
        let graceSteps: Int
        let levels: [Int]
        let groupSize: [Int]
        let monsters: [String: Int]
    }

    let id: String
    let name: String
    let width: Int
    let height: Int
    let music: String?
    /// Song for random battles here (content/music.json); "battle" when unset.
    let battleMusic: String?
    let theme: Theme
    let fence: Bool?
    let exits: [Exit]
    /// Where this place sits on the world map, in steps [east, north] from the start town.
    let world: [Int]?
    /// Where the roads meet, as an [x, y] cell offset from the centre (the centre by default).
    let hub: [Int]?
    let trails: [Trail]?
    let buildings: [Building]?
    let decor: [Decor]?
    let npcs: [NPCDef]?
    let encounters: Encounters?
    let ambience: Ambience?
    /// Background characters wandering the map (see content/crowd.json).
    let crowd: Crowd?
    /// A danger zone: adventurers can duel here, and some will pick a fight.
    let danger: Bool?
    /// Town planning: streets, a plaza, shops along the streets and raised terraces.
    let town: Town?

    nonisolated struct Town: Decodable, Sendable {
        /// Straight streets as [x1, y1, x2, y2] offsets from the centre.
        let streets: [[Int]]?
        /// Radius of the cobbled plaza in the middle.
        let plaza: Int?
        /// Buildings placed along the streets, in order.
        let lots: [String]?
        /// Street furniture: art id → how many.
        let streetDecor: [String: Int]?
        /// Raised stone terraces (layered walls with balustrades and stairs).
        let terraces: [Terrace]?
    }

    nonisolated struct Terrace: Decodable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    nonisolated struct Crowd: Decodable, Sendable {
        let adventurers: Int?
        let villagers: Int?
        /// Market traders standing about the main square, their wares on a sign over their heads.
        let traders: Int?
        /// What only this town's villagers say (its own places and people), besides crowd.json's.
        let villagerLines: [String]?
    }
}

nonisolated struct SongDef: Decodable, Identifiable, Sendable {
    nonisolated struct Track: Decodable, Sendable {
        /// An instrument from music.json "instruments" (or "drums").
        let instrument: String?
        /// Old chiptune tracks: square, triangle or noise.
        let wave: String?
        let duty: Double?
        let volume: Double
        /// -1 left ... 1 right.
        let pan: Double?
        /// How much of this track goes to the reverb (0...1, default 1).
        let reverb: Double?
        let notes: String
    }

    let id: String
    let title: String
    let tempo: Double
    let loops: Bool?
    /// The hall reverb's level for the whole song.
    let reverb: Double?
    let tracks: [Track]
}

/// An additive instrument (content/music.json "instruments"): sine partials, each
/// [frequency ratio, level, decay per second], plus envelope and colour.
nonisolated struct InstrumentDef: Decodable, Sendable {
    let id: String
    let partials: [[Double]]?
    /// Held notes (winds, strings) don't decay; struck ones do.
    let held: Bool?
    let attack: Double?
    let release: Double?
    /// [depth in semitones, rate in Hz, delay in seconds]
    let vibrato: [Double]?
    let voices: Int?
    /// Cents between the chorus voices.
    let detune: Double?
    let breath: Double?
    let click: Double?
    let gain: Double?
}

/// A colour choice in the look customiser (content/appearance.json).
nonisolated struct LookPreset: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let swatch: String
    let recolor: [RecolorRule]
}

/// Names and chatter for the background characters (content/crowd.json).
nonisolated struct CrowdOptions: Decodable, Sendable {
    let adventurerNames: [String]
    let adventurerLines: [String]
    let villagerNames: [String]
    /// What villagers say in any town: {town} for its name and {healer} for its healer's (a line
    /// with {healer} is left out where there's none). A town's own lines are its `crowd.villagerLines`.
    let villagerLines: [String]
    /// Answers when you say something in chat.
    let replies: [String]
    let companions: [String]
    /// How many of each map's adventurers and traders turn up (1: all of them). Turn it down as real
    /// players arrive.
    let botDensity: Double?
    /// What market traders call out: {item} and {price} for what they sell, {buy} and {price} for
    /// what they'd buy from you.
    let traderLines: [String]?
}

/// The game's own notices in the chat (content/announcements.json): what's happening where and when.
nonisolated struct AnnouncementOptions: Decodable, Sendable {
    /// Real seconds between notices while you play: [shortest, longest].
    let every: [Double]
    /// When the calendar's hour turns 6 (dawn) or 18 (dusk).
    let dawn: [String]
    let dusk: [String]
    /// When you come to a map, by map id.
    let arrival: [String: [String]]
    /// When you come to a map with a boss you've never beaten: {boss}, {map}.
    let bossNearby: [String]?
    /// What other adventurers have been up to: {bot}, {level}, {boss}, {rare}, {item}, {map}.
    let community: [String]
    let sighting: Sighting?

    /// A map's rare monster turns up `boost` times as often there for `minutes` real minutes.
    nonisolated struct Sighting: Decodable, Sendable {
        /// {monster}, {map}, {minutes}.
        let text: String
        /// When it's over: {monster}, {map}.
        let end: String
        let minutes: Int
        let boost: Int
        /// How often a notice is a sighting rather than news of another adventurer.
        let chance: Double
    }
}

/// A title you earn and wear over your name (content/titles.json): what earns it is `kind`, with
/// `count` of it (nil for lands, book and cards: every one), or `target` for one boss.
nonisolated struct TitleDef: Decodable, Identifiable, Sendable {
    nonisolated enum Kind: String, Decodable, Sendable {
        case level, lands, book, quests, bosses, boss, companions, friends, rebirths, bounties, days, cards
    }
    let id: String
    let name: String
    let kind: Kind
    let count: Int?
    /// `boss`: the boss's NPC id.
    let target: String?
    /// How much honour it carries, 1 to 5 (`TitleBadge`: bronze, silver, gold, ruby, prismatic).
    let rank: Int?

    /// `rank`, kept to 1...5.
    var tier: Int { min(5, max(1, rank ?? 1)) }
}

/// Reasons to come back (content/rewards.json): the daily gift's round, the daily bounties' rules,
/// the least a quest pays and the Monster Book's milestones.
nonisolated struct RewardsDef: Decodable, Sendable {
    nonisolated struct Gift: Decodable, Sendable {
        /// Gold: this many times your level.
        let goldPerLevel: Int?
        let items: [String]?
    }
    nonisolated struct Bounties: Decodable, Sendable {
        nonisolated struct Bonus: Decodable, Sendable {
            /// A share of the EXP your level needs.
            let exp: Double
            let items: [String]?
        }
        let perDay: Int
        /// Each kind (`Bounty.Kind`) with its count's [low, high].
        let kinds: [String: [Int]]
        /// Each bounty pays this share of the EXP your level needs, and `goldPerLevel` × your level.
        let exp: Double
        let goldPerLevel: Int
        /// Once all the day's bounties are claimed.
        let bonus: Bonus
    }
    /// The least a quest pays when you hand it in, for your level then (a bit more than a bounty),
    /// so one you've outgrown is still worth doing. Its own reward when that's more.
    nonisolated struct Quests: Decodable, Sendable {
        /// A share of the EXP your level needs.
        let exp: Double
        /// Gold: this many times your level.
        let goldPerLevel: Int
    }
    nonisolated struct Milestone: Decodable, Sendable {
        /// Kinds of monster met; nil: every one.
        let count: Int?
        let gold: Int
        let items: [String]?
    }
    /// Monster cards (Fairyland Online's card collection): a beaten monster leaves its card one
    /// time in `chance` (`rareChance` for a rare one, `bossChance` for a boss). The first of each
    /// goes in the Monster Book and raises the hero's stat for its element (`gains`) for good:
    /// `perStep` for each step, one step and another for every `levelsPerStep` levels of where the
    /// monster lives (`Content.cardLevel`), times `rare` or `boss` for theirs. A spare is sold on the
    /// spot for `spareGold` times the gold the monster pays.
    nonisolated struct Cards: Decodable, Sendable {
        nonisolated struct Gain: Decodable, Sendable {
            /// hp, mp, attack, defense, magic or speed.
            let stat: String
            let perStep: Double
        }
        let chance: Double
        let rareChance: Double
        let bossChance: Double
        let levelsPerStep: Int
        let rare: Double
        let boss: Double
        /// By element (`Element`'s raw value).
        let gains: [String: Gain]
        let spareGold: Int
    }
    /// Seal Stones won in hard fights: the highest `tiers` rule whose `above` the strongest beaten
    /// monster's level is over yours, one time in `chance`, one of its `items` (repeats weigh more);
    /// `boss` for a boss fight.
    nonisolated struct Seals: Decodable, Sendable {
        nonisolated struct Rule: Decodable, Sendable {
            /// Levels the strongest monster stood over yours, at least.
            let above: Int
            let chance: Double
            let items: [String]
        }
        let tiers: [Rule]
        let boss: Rule
    }
    let dailyGifts: [Gift]
    let bounties: Bounties
    let quests: Quests
    let bookMilestones: [Milestone]
    let cards: Cards
    let seals: Seals
}

/// One entry in content/changelog.json, shown under "What's new" on the title screen.
nonisolated struct ReleaseNote: Decodable, Identifiable, Sendable {
    let version: String
    let date: String
    let title: String
    let notes: [String]
    var id: String { version }
}

nonisolated struct GenderOption: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// A hairstyle: art/sprites/hair_<id>_<race>.png, drawn over the bald body_<race>.png.
nonisolated struct HairStyle: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    /// The walk sheet this is the own hair of (a gender's: a ponytail, braids): the hair that sheet
    /// starts with. Anyone can wear any style, so a girl can have a boy's hair and the other way round.
    let sheet: String?
}

nonisolated struct AppearanceOptions: Decodable, Sendable {
    let genders: [GenderOption]
    let styles: [HairStyle]
    /// The window a hair preset's rules widen to on the hero's hair and locks layers, which hold
    /// nothing but hair (only `hue`, the saturations and the values are read).
    let hairLayer: RecolorRule?
    let hair: [LookPreset]
    let outfits: [LookPreset]
    let skin: [LookPreset]

    /// The hairstyles a walk sheet can wear: its own hair first, then every other.
    func styles(for sheet: String) -> [HairStyle] {
        styles.filter { $0.sheet == sheet } + styles.filter { $0.sheet != sheet }
    }
}

// MARK: - Loading

private nonisolated struct ClassesFile: Decodable {
    let classChoiceLevel: Int
    let races: [RaceDef]
    let classes: [ClassDef]
}

private nonisolated struct SkillsFile: Decodable { let skills: [SkillDef] }
private nonisolated struct MonstersFile: Decodable { let monsters: [MonsterDef] }
private nonisolated struct ItemsFile: Decodable { let items: [ItemDef] }
private nonisolated struct QuestsFile: Decodable { let quests: [QuestDef] }
private nonisolated struct MapsFile: Decodable { let start: String; let maps: [MapDef] }
private nonisolated struct MusicFile: Decodable { let songs: [SongDef]; let instruments: [InstrumentDef]? }
private nonisolated struct ChangelogFile: Decodable { let releases: [ReleaseNote] }
private nonisolated struct TitlesFile: Decodable { let titles: [TitleDef] }

/// All game data from the bundled content/ folder. Edit the JSON, rebuild, done. Text is read in
/// the player's language (`Localizer`): the fields content/i18n/fields.json names are swapped for
/// their translations as each file loads, and `reload()` reads it all again after a switch.
final class Content {
    static let shared = Content()

    private struct Loaded {
        let classChoiceLevel: Int
        let races: [RaceDef]
        let classes: [ClassDef]
        let skills: [SkillDef]
        let monsters: [MonsterDef]
        let items: [ItemDef]
        let quests: [QuestDef]
        let maps: [MapDef]
        let startMap: String
        let songs: [SongDef]
        let instruments: [InstrumentDef]
        let appearance: AppearanceOptions
        let crowd: CrowdOptions
        let announcements: AnnouncementOptions
        let releases: [ReleaseNote]
        let titles: [TitleDef]
        let rewards: RewardsDef
        /// Each monster's card level (`cardLevel`), worked out once.
        let cardLevels: [String: Int]
    }

    private let bundle: Bundle
    private var loaded: Loaded

    var classChoiceLevel: Int { loaded.classChoiceLevel }
    var races: [RaceDef] { loaded.races }
    var classes: [ClassDef] { loaded.classes }
    var skills: [SkillDef] { loaded.skills }
    var monsters: [MonsterDef] { loaded.monsters }
    var items: [ItemDef] { loaded.items }
    var quests: [QuestDef] { loaded.quests }
    var maps: [MapDef] { loaded.maps }
    var startMap: String { loaded.startMap }
    var songs: [SongDef] { loaded.songs }
    var instruments: [InstrumentDef] { loaded.instruments }
    var appearance: AppearanceOptions { loaded.appearance }
    var crowd: CrowdOptions { loaded.crowd }
    var announcements: AnnouncementOptions { loaded.announcements }
    /// Newest first.
    var releases: [ReleaseNote] { loaded.releases }
    var titles: [TitleDef] { loaded.titles }
    var rewards: RewardsDef { loaded.rewards }

    /// `strings`: read the data with these translations instead of the chosen language's (tests).
    init(bundle: Bundle = .main, strings: [String: String]? = nil) {
        self.bundle = bundle
        if let strings {
            loaded = Self.read(bundle, strings: strings)
        } else {
            // The chosen language's strings are loaded with the Localizer.
            _ = Localizer.shared
            loaded = Self.read(bundle, strings: Strings.table)
        }
    }

    /// Reads everything again in the language now chosen (`Localizer.choose`).
    func reload() {
        loaded = Self.read(bundle, strings: Strings.table)
    }

    private static func read(_ bundle: Bundle, strings: [String: String]) -> Loaded {
        let fields = strings.isEmpty ? [:] : translatedFields(bundle)
        func load<T: Decodable>(_ name: String) -> T {
            Self.load(name, from: bundle, translating: fields[name], with: strings)
        }
        let classFile: ClassesFile = load("classes")
        let mapFile: MapsFile = load("maps")
        let musicFile: MusicFile = load("music")
        // Where each monster lives, at its gentlest: the middle of the lowest band of levels it
        // turns up in, or a boss's own level.
        var cardLevels: [String: Int] = [:]
        for map in mapFile.maps {
            if let encounters = map.encounters, let low = encounters.levels.first, let high = encounters.levels.last {
                for id in encounters.monsters.keys { cardLevels[id] = min(cardLevels[id] ?? .max, (low + high) / 2) }
            }
            for npc in map.npcs ?? [] where npc.role == .boss {
                if let id = npc.monster, let level = npc.level { cardLevels[id] = min(cardLevels[id] ?? .max, level) }
            }
        }
        return Loaded(
            classChoiceLevel: classFile.classChoiceLevel,
            races: classFile.races,
            classes: classFile.classes,
            skills: (load("skills") as SkillsFile).skills,
            monsters: (load("monsters") as MonstersFile).monsters,
            items: (load("items") as ItemsFile).items,
            quests: (load("quests") as QuestsFile).quests,
            maps: mapFile.maps,
            startMap: mapFile.start,
            songs: musicFile.songs,
            instruments: musicFile.instruments ?? [],
            appearance: load("appearance"),
            crowd: load("crowd"),
            announcements: load("announcements"),
            releases: (load("changelog") as ChangelogFile).releases,
            titles: (load("titles") as TitlesFile).titles,
            rewards: load("rewards"),
            cardLevels: cardLevels
        )
    }

    /// Which keys hold text, per file (content/i18n/fields.json): a list of key names, or "*" for
    /// every string in the file.
    private static func translatedFields(_ bundle: Bundle) -> [String: Set<String>] {
        guard let url = bundle.url(forResource: "fields", withExtension: "json", subdirectory: "content/i18n"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var fields: [String: Set<String>] = [:]
        for (file, keys) in raw where !file.hasPrefix("_") {
            if let all = keys as? String, all == "*" { fields[file] = ["*"] }
            if let list = keys as? [String] { fields[file] = Set(list) }
        }
        return fields
    }

    private static func load<T: Decodable>(_ name: String, from bundle: Bundle, translating keys: Set<String>?,
                                           with strings: [String: String]) -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "content") else {
            fatalError("content/\(name).json is missing from the app bundle")
        }
        do {
            var data = try Data(contentsOf: url)
            if let keys, !strings.isEmpty {
                let json = try JSONSerialization.jsonObject(with: data)
                data = try JSONSerialization.data(withJSONObject: translate(json, keys: keys, key: nil, strings: strings))
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("content/\(name).json couldn't be read: \(error)")
        }
    }

    /// Swaps every string under one of `keys` (in a list, or alone) for its translation.
    private static func translate(_ value: Any, keys: Set<String>, key: String?, strings: [String: String]) -> Any {
        switch value {
        case let object as [String: Any]:
            var out: [String: Any] = [:]
            for (name, child) in object {
                out[name] = name.hasPrefix("_") ? child : translate(child, keys: keys, key: name, strings: strings)
            }
            return out
        case let list as [Any]:
            return list.map { translate($0, keys: keys, key: key, strings: strings) }
        case let text as String:
            guard keys.contains("*") || key.map(keys.contains) == true else { return text }
            return strings[text] ?? text
        default:
            return value
        }
    }

    func race(_ id: String) -> RaceDef { races.first { $0.id == id } ?? races[0] }
    func classDef(_ id: String) -> ClassDef { classes.first { $0.id == id } ?? classes[0] }
    func skill(_ id: String) -> SkillDef? { skills.first { $0.id == id } }
    func monster(_ id: String) -> MonsterDef? { monsters.first { $0.id == id } }
    func item(_ id: String) -> ItemDef? { items.first { $0.id == id } }
    func quest(_ id: String) -> QuestDef? { quests.first { $0.id == id } }
    func title(_ id: String) -> TitleDef? { titles.first { $0.id == id } }
    func map(_ id: String) -> MapDef? { maps.first { $0.id == id } }
    func song(_ id: String) -> SongDef? { songs.first { $0.id == id } }

    func npc(_ id: String) -> NPCDef? {
        maps.lazy.compactMap { $0.npcs?.first { $0.id == id } }.first
    }

    /// The boss that fights as this monster, if it's one.
    func boss(fighting monsterID: String) -> NPCDef? {
        maps.lazy.compactMap { $0.npcs?.first { $0.role == .boss && $0.monster == monsterID } }.first
    }

    /// The map a character lives on.
    func home(ofNPC id: String) -> MapDef? {
        maps.first { $0.npcs?.contains { $0.id == id } == true }
    }

    /// The level a monster's card is worth (`RewardsDef.Cards`): the middle of the gentlest band
    /// of levels it lives in, or a boss's own level; 1 for one that lives nowhere.
    func cardLevel(_ monsterID: String) -> Int { max(1, loaded.cardLevels[monsterID] ?? 1) }
}
