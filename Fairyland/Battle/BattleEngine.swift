import Foundation

nonisolated enum BattleSide: Sendable {
    case party, enemies

    var opposite: BattleSide { self == .party ? .enemies : .party }
}

/// A stat that spells raise or lower for a few rounds in battle (Bless, Protection, a curse...).
nonisolated enum BattleStat: String, CaseIterable, Sendable {
    case attack, defense, magic, speed

    /// Its short name, as the menus write it.
    var short: String {
        switch self {
        case .attack: L("ATK")
        case .defense: L("DEF")
        case .magic: L("MAG")
        case .speed: L("SPD")
        }
    }
}

/// A change to a stat: +0.25 raises it by a quarter, -0.2 lowers it by a fifth.
nonisolated struct StatChange: Equatable, Sendable {
    let stat: BattleStat
    let amount: Double
}

/// A stat raised or lowered for a while: by how much (0.25 = 25%) and the rounds it has left,
/// counting the one it's in.
nonisolated struct StatEffect: Equatable, Sendable {
    var amount: Double
    var rounds: Int
}

/// One fighter in a battle: the hero, a companion, or a wild monster.
struct Combatant: Identifiable {
    enum Source: Equatable {
        case hero
        case pet(UUID)
        case wild(String)
        /// A befriended adventurer fighting on your side.
        case ally(UUID)
        /// An adventurer you're duelling.
        case rival(UUID)
    }

    let id: Int
    let side: BattleSide
    let source: Source
    var name: String
    let art: String
    let level: Int
    let element: Element
    let stats: Stats
    var hp: Int
    var mp: Int
    let skills: [String]
    let captureRate: Double
    var isDefending = false
    var isCaptured = false
    /// A wild monster that ran away.
    var hasFled = false
    /// A rarer colour variant (tougher, harder to catch).
    var isRare = false
    /// Skill id → level for the hero; monsters and companions scale with their own level.
    var skillLevels: [String: Int] = [:]
    /// Stats raised for a while (Bless, Protection, Boost...) and lowered (a curse, Berserk's
    /// guard), each by how much and for how many rounds.
    var raised: [BattleStat: StatEffect] = [:]
    var lowered: [BattleStat: StatEffect] = [:]
    /// Poison: bites left (one at the end of each round), and how much each takes.
    var poisonRounds = 0
    var poisonDamage = 0
    /// Frozen solid (Frost Breath): turns it still has to sit out.
    var frozenRounds = 0
    /// People only: their class and race, so each fights in their own style (BattleScene).
    var classID: String?
    var raceID: String?
    /// Which wave of a boss fight it comes in with (1 for everyone else).
    var wave = 1
    /// A companion: the fighter it came with, who it stands behind.
    var ownerID: Int?

    /// How spells change a stat now: ×1.25 raised by a quarter, ×0.8 cursed by a fifth.
    func factor(_ stat: BattleStat) -> Double {
        (1 + (raised[stat]?.amount ?? 0)) * (1 - (lowered[stat]?.amount ?? 0))
    }

    /// The stats as they stand, raised and lowered.
    var attack: Double { Double(stats.attack) * factor(.attack) }
    var defense: Double { Double(stats.defense) * factor(.defense) }
    var magic: Double { Double(stats.magic) * factor(.magic) }
    var speed: Double { Double(stats.speed) * factor(.speed) }
    /// Rounds left on its longest raise and its longest drop (the marks by the HP bar).
    var raisedRounds: Int { raised.values.map(\.rounds).max() ?? 0 }
    var loweredRounds: Int { lowered.values.map(\.rounds).max() ?? 0 }

    /// Raises and lowers stats for `rounds`, counting this one. A second spell on a stat doesn't
    /// stack: it lasts as long, and works as hard, as the stronger of the two. A drop never takes
    /// more than half a stat (`BattleEngine.maxCurse`).
    mutating func change(_ changes: [StatChange], rounds: Int) {
        for change in changes where change.amount != 0 {
            if change.amount > 0 {
                let old = raised[change.stat]
                raised[change.stat] = StatEffect(amount: max(old?.amount ?? 0, change.amount), rounds: max(old?.rounds ?? 0, rounds))
            } else {
                let old = lowered[change.stat]
                lowered[change.stat] = StatEffect(amount: min(BattleEngine.maxCurse, max(old?.amount ?? 0, -change.amount)),
                                                  rounds: max(old?.rounds ?? 0, rounds))
            }
        }
    }

    /// A new round: every raise and drop has one fewer to go, and the spent ones end.
    mutating func countDownStats() {
        for (stat, effect) in raised {
            raised[stat] = effect.rounds > 1 ? StatEffect(amount: effect.amount, rounds: effect.rounds - 1) : nil
        }
        for (stat, effect) in lowered {
            lowered[stat] = effect.rounds > 1 ? StatEffect(amount: effect.amount, rounds: effect.rounds - 1) : nil
        }
    }
    /// Fainted, but still on the field to be revived (not sealed or run off).
    var isFallen: Bool { hp <= 0 && !isCaptured && !hasFled }

    func skillLevel(_ id: String) -> Int {
        skillLevels[id] ?? Self.naturalSkillLevel(for: level)
    }

    /// Monsters and companions grow into their skills with their own level, mastering them at 18.
    static func naturalSkillLevel(for level: Int) -> Int {
        min(GameSession.maxSkillLevel, 1 + level / 2)
    }

    var isAlive: Bool { hp > 0 && !isCaptured && !hasFled }
    var isHero: Bool { source == .hero }
    /// A friend fighting on your side.
    var isAlly: Bool {
        if case .ally = source { return true }
        return false
    }
    var hpFraction: Double { stats.hp > 0 ? Double(hp) / Double(stats.hp) : 0 }
    var mpFraction: Double { stats.mp > 0 ? Double(mp) / Double(stats.mp) : 0 }

    var speciesID: String? {
        switch source {
        case .wild(let id): id
        default: nil
        }
    }

    var petID: UUID? {
        switch source {
        case .pet(let id): id
        default: nil
        }
    }
}

enum BattleAction {
    case attack(target: Int)
    /// For skills that hit everyone, `target` is ignored.
    case skill(String, target: Int)
    case item(String, target: Int)
    /// `stone`: the Seal Stone thrown (an item id); a plain one if nil.
    case capture(target: Int, stone: String? = nil)
    case defend
    case escape
    /// Wild monsters only: run away when nearly beaten.
    case flee

    /// Running away: nobody else needs telling what to do.
    var isEscape: Bool {
        if case .escape = self { return true }
        return false
    }
}

struct Hit {
    let target: Int
    let amount: Int
    /// Element multiplier: 1.5 weak spot, 0.75 resisted.
    let effectiveness: Double
    let critical: Bool
    /// Caught in the blast around the chosen target of a big spell.
    var splash = false
}

/// What happened, in order, so the scene can animate it.
enum BattleEvent {
    case attack(actor: Int, hit: Hit)
    case skill(actor: Int, skill: SkillDef, level: Int, hits: [Hit])
    case item(actor: Int, item: ItemDef, target: Int, hp: Int, mp: Int)
    case defend(actor: Int)
    /// `wobbles` is how many times the Seal Stone shakes before it seals or bursts open; `stone` is
    /// the one thrown (an item id; a plain Seal Stone if nil), used up either way.
    case capture(actor: Int, target: Int, success: Bool, wobbles: Int, stone: String? = nil)
    case escape(actor: Int, success: Bool)
    case fled(Int)
    case defeated(Int)
    case message(String)
    /// A poison or curse took hold: poison bites `rounds` times, a curse lasts `rounds` rounds after this one.
    case afflicted(target: Int, effect: Ailment, rounds: Int)
    /// A poison's bite at the end of a round.
    case ailmentDamage(target: Int, effect: Ailment, amount: Int)
    /// A frozen fighter's turn comes and goes: it can't move, and the ice thaws a little.
    case frozen(target: Int)
    /// Spells changed a fighter's stats (a buff raises them, a curse lowers them): where each
    /// stands now (+0.3 = 30% up), for `rounds` more rounds after this one.
    case statsChanged(target: Int, changes: [StatChange], rounds: Int)
    /// A boss fight's next wave steps onto the field (`number` of `of`), the last with the boss.
    case wave(number: Int, of: Int, arrivals: [Combatant])
}

enum BattleOutcome: Equatable {
    /// `fled`: the last monster ran away (you still get paid for the ones you beat).
    case ongoing, victory, fled, defeat, escaped
}

enum CaptureStatus: Equatable {
    case ready(chance: Double)
    /// Not a wild monster on the field: a boss, someone on your side, or one already gone.
    case impossible
}

/// Fairyland-style turn-based battle rules, with no UI. Each round the player picks the hero's
/// action and can give their companion orders; everyone else decides for themselves. Your side
/// acts in the order its moves were chosen, then the monsters by speed.
final class BattleEngine {
    private(set) var combatants: [Combatant]
    private(set) var outcome: BattleOutcome = .ongoing
    private let content: Content
    private let captureBonus: Double
    private var rng: SeededRandom
    /// Rounds played so far; long fights make monsters warier.
    private(set) var round = 0
    /// The monster the hero throws a Seal Stone at this round: everyone on your side leaves it be.
    private var sealTarget: Int?
    /// The skill you use this round: friends steer clear of echoing it (`adventurerAction`).
    private var heroSkill: String?
    /// A boss fight comes in waves: the waves still to come, each stepping in once the one on the
    /// field is beaten. The last brings the boss.
    private var waves: [[Combatant]]
    /// The wave on the field, and how many there are in all (1 for an ordinary fight).
    private(set) var wave = 1
    let waveCount: Int
    /// No monster runs from a fight with a boss or an adventurer in it, or still to come.
    private let standsGround: Bool

    /// How many rounds a buff lasts after the one it's cast in, unless the skill says.
    static let buffLength = 3

    /// A curse (or any drop) never takes more than half a stat.
    static let maxCurse = 0.5

    /// Below this share of its HP a monster's odds of being sealed climb fast (Fairyland's capsules
    /// only worked down here), and one left on its own may bolt.
    static let captureThreshold = 0.2

    /// `enemies` is the first wave; `waves` are the ones still to come (a boss fight's).
    init(party: [Combatant], enemies: [Combatant], content: Content, captureBonus: Double = 1,
         seed: UInt64 = .random(in: 0...UInt64.max), waves: [[Combatant]] = []) {
        combatants = party + enemies
        self.content = content
        self.captureBonus = captureBonus
        rng = SeededRandom(seed: seed)
        self.waves = waves
        // Numbered by the fighters themselves, so a fight can open at a later wave (debug launches).
        let first = enemies.first?.wave ?? 1
        wave = first
        waveCount = first + waves.count
        standsGround = (enemies + waves.joined()).contains { $0.captureRate == 0 }
    }

    var hero: Combatant? { combatants.first(where: \.isHero) }

    func combatant(_ id: Int) -> Combatant? { combatants.first { $0.id == id } }

    func alive(on side: BattleSide) -> [Combatant] {
        combatants.filter { $0.side == side && $0.isAlive }
    }

    /// Sealing: any wild monster on the field, at any HP (Fairyland wanted the last one standing,
    /// below 20%; players asked for more). The weaker it is the better your odds; tougher,
    /// higher-level monsters and long fights make it harder. A stronger `stone` multiplies the odds
    /// by its `sealPower` and lifts their ceiling (75% for a plain Seal Stone, up to 95%); a sure one
    /// (the Wishing Seal) never fails. Nothing seals a boss.
    func captureStatus(of id: Int, with stone: ItemDef? = nil) -> CaptureStatus {
        guard let target = combatant(id), target.isAlive, target.side == .enemies, target.captureRate > 0 else { return .impossible }
        if stone?.sure == true { return .ready(chance: 1) }
        let power = max(1, stone?.sealPower ?? 1)
        let weakness = Self.captureWeakness(atHP: target.hpFraction)
        let above = Double(target.level - (hero?.level ?? 1))
        let levelFactor = above > 0 ? max(0.4, 1 - 0.06 * above) : min(1.3, 1 - 0.03 * above)
        let fatigue = pow(0.92, Double(max(0, round - 1)))
        let chance = target.captureRate * 0.3 * weakness * levelFactor * fatigue * captureBonus * power
        return .ready(chance: min(Self.captureCeiling(power: power), max(0.03 * power, chance)))
    }

    /// The best odds a stone of this `sealPower` can have: 75% for a plain Seal Stone, ten points more
    /// for each step of power, up to 95%.
    static func captureCeiling(power: Double) -> Double { min(0.95, 0.75 + 0.1 * (power - 1)) }

    /// How much a monster's wounds help a Seal Stone, by the share of HP it has left: ×0.25 at full
    /// HP, ×1 at 20%, and on up to ×3 as it nears 0.
    static func captureWeakness(atHP fraction: Double) -> Double {
        let hp = min(1, max(0, fraction))
        if hp <= captureThreshold { return 1 + 2 * (captureThreshold - hp) / captureThreshold }
        return 1 - 0.75 * (hp - captureThreshold) / (1 - captureThreshold)
    }

    /// How much stronger a skill is at `level`: ×1 when learned, ×1.8 when mastered (level 10).
    static func skillBoost(_ level: Int) -> Double {
        1 + 0.8 * Double(min(level, GameSession.maxSkillLevel) - 1) / Double(GameSession.maxSkillLevel - 1)
    }

    /// Share of a spell's damage that also hits everyone else on the target's side: from
    /// skill level 5 up (60% of `splash`), growing to the full `splash` when mastered.
    static func splashFraction(of skill: SkillDef, level: Int) -> Double {
        guard let splash = skill.splash, level >= 5 else { return 0 }
        return splash * (0.6 + 0.4 * Double(min(level, GameSession.maxSkillLevel) - 5) / Double(GameSession.maxSkillLevel - 5))
    }

    /// What a buff does at `level`, in stat order: what it raises, by more as the skill grows (×1.8
    /// mastered, like damage), and what it lowers in return (Berserk's guard), which stays put.
    static func statChanges(of skill: SkillDef, level: Int) -> [StatChange] {
        BattleStat.allCases.compactMap { stat in
            if let up = skill.raises?[stat.rawValue] { return StatChange(stat: stat, amount: up * skillBoost(level)) }
            if let down = skill.lowers?[stat.rawValue] { return StatChange(stat: stat, amount: -down) }
            return nil
        }
    }

    /// A nearly beaten monster on its own may bolt.
    private func fleeChance(of monster: Combatant) -> Double {
        // Bosses (who can't be captured) stand their ground, and so do the monsters in their waves,
        // so beating the boss always wins the fight.
        guard monster.captureRate > 0, !standsGround,
              alive(on: .enemies).count == 1, monster.hpFraction <= Self.captureThreshold else { return 0 }
        let panic = (Self.captureThreshold - monster.hpFraction) / Self.captureThreshold
        return min(0.4, 0.05 + 0.15 * panic + 0.02 * Double(round))
    }

    /// `orders`: what the player told their companion to do, by fighter id (Fairyland let you
    /// command your pet each round). A companion without orders decides for itself.
    /// `heroChoseAt`: how far into the time to choose you locked in your move (0 at once, 1 at the
    /// bell), which sets your place among your friends this round.
    func resolveRound(heroAction: BattleAction, orders: [Int: BattleAction] = [:], heroChoseAt: Double = 0) -> [BattleEvent] {
        guard outcome == .ongoing else { return [] }
        round += 1
        if case .capture(let target, _) = heroAction { sealTarget = target } else { sealTarget = nil }
        if case .skill(let id, _) = heroAction { heroSkill = id } else { heroSkill = nil }
        for index in combatants.indices {
            combatants[index].isDefending = false
            combatants[index].countDownStats()
        }
        // Guarding protects for the whole round, even against faster monsters (a companion told to
        // guard too).
        if case .defend = heroAction, let heroID = hero?.id {
            mutate(heroID) { $0.isDefending = true }
        }
        for (id, order) in orders {
            if case .defend = order { mutate(id) { $0.isDefending = true } }
        }

        // Your side goes first, in the order everyone chose their move: you when you locked yours in,
        // each friend at a moment of their own somewhere in the time to choose (so choose quickly and
        // you go before them), every companion right after whoever it came with.
        let standing = combatants.filter(\.isAlive)
        let yourSide = hero?.side ?? .party
        var lockedIn: [(id: Int, at: Double)] = []
        for fighter in standing where fighter.side == yourSide && fighter.ownerID == nil {
            let at = fighter.isHero ? heroChoseAt : Double.random(in: 0..<1, using: &rng)
            lockedIn.append((fighter.id, at))
        }
        var order: [Int] = []
        for leader in lockedIn.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            order.append(leader.id)
            order += standing.filter { $0.ownerID == leader.id }.map(\.id)
        }
        // A companion whose owner is down still fights, after the rest.
        order += standing.filter { $0.side == yourSide && !order.contains($0.id) }.map(\.id)
        // Then the monsters, shuffled anew every round and weighted by speed: the faster go earlier
        // more often (twice the speed, first two rounds in three). Each draws u^(1/speed) and the
        // highest goes first; compared as log(u)/speed, the same order without underflow.
        var initiative: [(id: Int, roll: Double)] = []
        for fighter in standing where fighter.side != yourSide {
            let draw = Double.random(in: Double.ulpOfOne..<1, using: &rng)
            initiative.append((fighter.id, log(draw) / max(1, fighter.speed)))
        }
        order += initiative.sorted { $0.roll > $1.roll }.map { $0.id }

        var events: [BattleEvent] = []
        // Everyone already frozen sits this round out together at its start, so their shivers play
        // at once instead of one by one between the others' turns; the ice thaws a little.
        var sittingOut: Set<Int> = []
        for actorID in order {
            guard let actor = combatant(actorID), actor.frozenRounds > 0 else { continue }
            mutate(actorID) { $0.frozenRounds -= 1 }
            events.append(.frozen(target: actorID))
            sittingOut.insert(actorID)
        }
        for actorID in order where !sittingOut.contains(actorID) {
            // A wave beaten mid-round: nobody's left to fight until the next one steps in.
            if !waves.isEmpty, alive(on: .enemies).isEmpty { break }
            guard outcome == .ongoing, let actor = combatant(actorID), actor.isAlive else { continue }
            // Frozen earlier this round: this turn is lost (your choice for it too), and the ice thaws.
            if actor.frozenRounds > 0 {
                mutate(actorID) { $0.frozenRounds -= 1 }
                events.append(.frozen(target: actorID))
                continue
            }
            let action: BattleAction = switch actor.source {
            case .hero: heroAction
            case .pet: orders[actor.id] ?? companionAction(for: actor)
            case .wild: monsterAction(for: actor)
            case .ally, .rival: adventurerAction(for: actor)
            }
            perform(action, by: actor, events: &events)
            updateOutcome()
        }
        // Poison bites at the end of the round.
        for fighter in combatants where outcome == .ongoing && fighter.isAlive && fighter.poisonRounds > 0 {
            events.append(.ailmentDamage(target: fighter.id, effect: .poison, amount: fighter.poisonDamage))
            mutate(fighter.id) { $0.poisonRounds -= 1 }
            applyDamage(Hit(target: fighter.id, amount: fighter.poisonDamage, effectiveness: 1, critical: false), events: &events)
            updateOutcome()
        }
        // The wave on the field is beaten: the next one steps in for the next round.
        if outcome == .ongoing, alive(on: .enemies).isEmpty, !waves.isEmpty {
            let arrivals = waves.removeFirst()
            wave += 1
            combatants += arrivals
            events.append(.wave(number: wave, of: waveCount, arrivals: arrivals))
        }
        return events
    }

    // MARK: - Actions

    private func perform(_ action: BattleAction, by actor: Combatant, events: inout [BattleEvent]) {
        switch action {
        case .attack(let targetID):
            guard let target = opponent(of: actor, preferring: targetID) else { return }
            let hit = physicalHit(from: actor, to: target, power: 1)
            events.append(.attack(actor: actor.id, hit: hit))
            applyDamage(hit, events: &events)

        case .skill(let skillID, let targetID):
            let level = actor.skillLevel(skillID)
            guard let skill = content.skill(skillID), actor.mp >= GameSession.mpCost(of: skill, level: level) else {
                perform(.attack(target: targetID), by: actor, events: &events)
                return
            }
            mutate(actor.id) { $0.mp -= GameSession.mpCost(of: skill, level: level) }
            // A mastered skill hits 80% harder than a fresh one, a little more each step.
            let boost = Self.skillBoost(level)
            let chosen = targets(for: skill, actor: actor, preferring: targetID)
            var hits = chosen.map { target -> Hit in
                switch skill.kind {
                case .physical: return physicalHit(from: actor, to: target, power: skill.power * boost)
                case .magic: return magicHit(from: actor, to: target, skill: skill, boost: boost)
                case .heal: return Hit(target: target.id, amount: Int(Double(healAmount(actor, skill)) * boost), effectiveness: 1, critical: false)
                // Revive: back on their feet with a share of their HP (more at higher levels).
                case .revive: return Hit(target: target.id, amount: max(1, Int(Double(target.stats.hp) * skill.power * boost)), effectiveness: 1, critical: false)
                case .buff, .curse, .field: return Hit(target: target.id, amount: 0, effectiveness: 1, critical: false)
                }
            }
            // Big spells spill over: the chosen target takes the full blast, the rest a share.
            let splash = Self.splashFraction(of: skill, level: level)
            if splash > 0, skill.target == .enemy, let main = chosen.first {
                for other in alive(on: main.side) where other.id != main.id {
                    var hit = magicHit(from: actor, to: other, skill: skill, boost: boost * splash)
                    hit.splash = true
                    hits.append(hit)
                }
            }
            events.append(.skill(actor: actor.id, skill: skill, level: level, hits: hits))
            for hit in hits {
                switch skill.kind {
                case .heal, .revive:
                    mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                case .buff:
                    // This round and the next ones (three unless the skill says).
                    changeStats(of: hit.target, Self.statChanges(of: skill, level: level),
                                rounds: (skill.rounds ?? Self.buffLength) + 1, events: &events)
                case .physical, .magic:
                    applyDamage(hit, events: &events)
                case .curse, .field:
                    break
                }
            }
            // What it leaves behind on everyone it reached (the splash only hurts).
            if let affliction = skill.inflicts {
                for target in chosen {
                    afflict(target.id, with: affliction, from: actor, skill: skill, boost: boost, events: &events)
                }
            }

        case .item(let itemID, let targetID):
            guard let item = content.item(itemID) else { return }
            // If they fainted before your turn came, the item stays in the bag.
            guard let target = combatant(targetID), target.isAlive, target.side == actor.side else {
                events.append(.message(combatant(targetID).map { L("{name} fainted first, so the {item} stays in your bag.", ["name": $0.name, "item": item.name]) } ?? L("They fainted first, so the {item} stays in your bag.", ["item": item.name])))
                return
            }
            let hp = min(item.heal ?? 0, target.stats.hp - target.hp)
            let mp = min(item.mp ?? 0, target.stats.mp - target.mp)
            mutate(target.id) {
                $0.hp += hp
                $0.mp += mp
            }
            events.append(.item(actor: actor.id, item: item, target: target.id, hp: hp, mp: mp))

        case .capture(let targetID, let stoneID):
            guard let target = combatant(targetID), target.isAlive else {
                events.append(.message(L("There's nothing left to capture.")))
                return
            }
            guard case .ready(let chance) = captureStatus(of: targetID, with: stoneID.flatMap(content.item)) else {
                events.append(.message(L("{name} can't be captured.", ["name": target.name])))
                return
            }
            let success = Double.random(in: 0..<1, using: &rng) < chance
            if success { mutate(targetID) { $0.isCaptured = true } }
            // Three wobbles means it held; a near miss shakes longer before bursting open.
            let wobbles = success ? 3 : Int.random(in: 0...2, using: &rng)
            events.append(.capture(actor: actor.id, target: targetID, success: success, wobbles: wobbles, stone: stoneID))

        case .flee:
            mutate(actor.id) { $0.hasFled = true }
            events.append(.fled(actor.id))

        case .defend:
            // On guard for the rest of the round (the hero's guard is up from the start of it).
            mutate(actor.id) { $0.isDefending = true }
            events.append(.defend(actor: actor.id))

        case .escape:
            let foes = alive(on: actor.side.opposite)
            let foeSpeed = foes.isEmpty ? 0 : foes.map(\.stats.speed).reduce(0, +) / foes.count
            let chance = min(0.95, max(0.25, 0.55 + Double(actor.stats.speed - foeSpeed) * 0.04))
            let success = Double.random(in: 0..<1, using: &rng) < chance
            events.append(.escape(actor: actor.id, success: success))
            if success { outcome = .escaped }
        }
    }

    private func companionAction(for pet: Combatant) -> BattleAction {
        // The monster you're sealing is left to you; the others are fair game.
        guard let weakest = alive(on: .enemies).filter({ $0.id != sealTarget }).min(by: { $0.hp < $1.hp }) else { return .defend }
        if let buff = selfBuff(for: pet) { return buff }
        let attacks = usableSkills(of: pet).filter { $0.kind.isHostile && !reaches(sealTarget, with: $0, by: pet) }
        if let skill = attacks.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.35 {
            return .skill(skill.id, target: weakest.id)
        }
        return .attack(target: weakest.id)
    }

    private func monsterAction(for monster: Combatant) -> BattleAction {
        guard let target = alive(on: .party).randomElement(using: &rng) else { return .defend }
        if Double.random(in: 0..<1, using: &rng) < fleeChance(of: monster) { return .flee }
        if let buff = selfBuff(for: monster) { return buff }
        if let skill = usableSkills(of: monster).filter(\.kind.isHostile).randomElement(using: &rng),
           Double.random(in: 0..<1, using: &rng) < 0.3 {
            return .skill(skill.id, target: target.id)
        }
        return .attack(target: target.id)
    }

    /// Monsters and companions power themselves up now and then (Boost, Berserk): a buff they have
    /// the MP for, on themselves, while it would raise something not raised already.
    private func selfBuff(for fighter: Combatant) -> BattleAction? {
        let buffs = usableSkills(of: fighter).filter { skill in
            skill.kind == .buff && Self.statChanges(of: skill, level: 1).contains { $0.amount > 0 && fighter.raised[$0.stat] == nil }
        }
        guard let skill = buffs.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.3 else { return nil }
        return .skill(skill.id, target: fighter.id)
    }

    /// What the hero does on Auto: what a friend in your party would.
    func autoAction(for id: Int) -> BattleAction {
        guard let fighter = combatant(id), fighter.isAlive else { return .defend }
        return adventurerAction(for: fighter)
    }

    /// Adventurers fight like thoughtful players. First the musts: wake a fallen friend (you
    /// first), and heal whoever is in trouble (everyone at once when several are). Then they weigh
    /// every move by what it's worth (`worth(of:by:)`): a plain blow to finish a monster off rather
    /// than MP spent on it, a sweep when the field is crowded, a spell's element on a weak spot and
    /// never where it's resisted, their strongest skill on the toughest foe, a buff while the fight
    /// has rounds to go, a curse on whoever hits hardest, and MP kept back by those who heal. A
    /// friend seldom echoes the skill you just used, and two moves worth about the same are a
    /// toss-up, so a party of one class doesn't act as one.
    private func adventurerAction(for fighter: Combatant) -> BattleAction {
        let skills = usableSkills(of: fighter)
        let fallen = combatants.filter { $0.side == .party && $0.isFallen && ($0.isHero || $0.isAlly) }
        if fighter.side == .party, let revive = skills.first(where: { $0.kind == .revive }),
           let down = fallen.first(where: \.isHero) ?? fallen.first {
            return .skill(revive.id, target: down.id)
        }
        let heals = skills.filter { $0.kind == .heal }
        let inTrouble = alive(on: fighter.side).filter { $0.hpFraction < 0.4 }
        if inTrouble.count >= 2, let group = heals.filter({ $0.target == .allAllies }).max(by: { $0.power < $1.power }) {
            return .skill(group.id, target: fighter.id)
        }
        if let heal = heals.filter({ $0.target != .allAllies }).max(by: { $0.power < $1.power }),
           let hurt = inTrouble.min(by: { $0.hpFraction < $1.hpFraction }) {
            return .skill(heal.id, target: hurt.id)
        }
        // Friends leave the monster you're sealing to you, and fight on against the rest.
        let spared = fighter.side == .party ? sealTarget : nil
        guard let weakest = alive(on: fighter.side.opposite).filter({ $0.id != spared }).min(by: { $0.hp < $1.hp }) else { return .defend }
        let options = worth(of: skills, by: fighter).filter { !aims(at: spared, $0.action, by: fighter) }
        return pick(from: options) ?? .attack(target: weakest.id)
    }

    /// Whether `action` would hurt the monster `id` (aimed at it, or a sweep or a splash that reaches it).
    private func aims(at id: Int?, _ action: BattleAction, by fighter: Combatant) -> Bool {
        guard let id else { return false }
        switch action {
        case .attack(let target): return target == id
        case .skill(let skillID, let target):
            guard let skill = content.skill(skillID), skill.kind.isHostile else { return false }
            return target == id || reaches(id, with: skill, by: fighter)
        default: return false
        }
    }

    /// Whether a hostile `skill` reaches the monster `id` wherever it's aimed: a sweep over every
    /// foe, or a spell big enough to splash.
    private func reaches(_ id: Int?, with skill: SkillDef, by fighter: Combatant) -> Bool {
        guard let id, combatant(id)?.isAlive == true else { return false }
        return skill.target == .allEnemies || Self.splashFraction(of: skill, level: fighter.skillLevel(skill.id)) > 0
    }

    /// Every move an adventurer could make now, with what it's worth in HP: taken off the other
    /// side, given back to this one, or saved by a buff or a curse over the rounds the fight has
    /// left, less the MP it costs.
    private func worth(of skills: [SkillDef], by fighter: Combatant) -> [(action: BattleAction, value: Double)] {
        let foes = alive(on: fighter.side.opposite)
        let friends = alive(on: fighter.side)
        guard let weakest = foes.min(by: { $0.hp < $1.hp }) else { return [] }
        // A plain blow's worth of damage: what MP is priced in.
        let blow = foes.map { expectedDamage(from: fighter, to: $0, skill: nil) }.reduce(0, +) / Double(foes.count)
        let rounds = roundsLeft(for: fighter.side)
        let reserve = mpReserve(of: fighter)
        var options = foes.map { foe in
            (action: BattleAction.attack(target: foe.id), value: blowValue(expectedDamage(from: fighter, to: foe, skill: nil), on: foe, by: fighter))
        }
        for skill in skills {
            let level = fighter.skillLevel(skill.id)
            let boost = Self.skillBoost(level)
            var choices: [(action: BattleAction, value: Double)] = []
            switch skill.kind {
            case .physical, .magic:
                if skill.target == .allEnemies {
                    let value = foes.map { blowValue(expectedDamage(from: fighter, to: $0, skill: skill), on: $0, by: fighter) }.reduce(0, +)
                    choices.append((action: .skill(skill.id, target: weakest.id), value: value))
                } else {
                    let splash = Self.splashFraction(of: skill, level: level)
                    for foe in foes {
                        var value = blowValue(expectedDamage(from: fighter, to: foe, skill: skill), on: foe, by: fighter)
                        for other in foes where splash > 0 && other.id != foe.id {
                            value += min(Double(other.hp), expectedDamage(from: fighter, to: other, skill: skill) * splash)
                        }
                        choices.append((action: .skill(skill.id, target: foe.id), value: value))
                    }
                }
            case .curse:
                guard let affliction = skill.inflicts else { break }
                let lasting = min(Double(affliction.rounds), rounds)
                let reached = skill.target == .allEnemies ? foes : nil
                func value(on foe: Combatant) -> Double {
                    switch affliction.effect {
                    case .poison:
                        guard foe.poisonRounds == 0 else { return 0 }
                        let bite = Double(poisonDamage(from: fighter, to: foe, skill: skill, power: affliction.power * boost))
                        return min(Double(foe.hp), bite * lasting)
                    case .curse:
                        guard foe.lowered[.attack] == nil else { return 0 }
                        return min(Self.maxCurse, affliction.power * boost) * expectedDamage(from: foe, to: fighter, skill: nil) * lasting
                    case .freeze:
                        // A turn lost is a hit not taken.
                        guard foe.frozenRounds == 0 else { return 0 }
                        return expectedDamage(from: foe, to: fighter, skill: nil) * Double(affliction.rounds)
                    }
                }
                if let reached {
                    choices.append((action: .skill(skill.id, target: weakest.id), value: reached.map(value(on:)).reduce(0, +) * (affliction.chance ?? 1)))
                } else {
                    for foe in foes { choices.append((action: .skill(skill.id, target: foe.id), value: value(on: foe) * (affliction.chance ?? 1))) }
                }
            case .heal:
                // Topping up someone hurt but not yet in trouble (that's handled first).
                let amount = Double(healAmount(fighter, skill)) * boost
                func value(for friend: Combatant) -> Double {
                    guard friend.hpFraction < 0.7 else { return 0 }
                    return min(amount, Double(friend.stats.hp - friend.hp)) * (0.6 + (0.7 - friend.hpFraction))
                }
                if skill.target == .allAllies {
                    choices.append((action: .skill(skill.id, target: fighter.id), value: friends.map(value(for:)).reduce(0, +)))
                } else if let friend = friends.max(by: { value(for: $0) < value(for: $1) }) {
                    choices.append((action: .skill(skill.id, target: friend.id), value: value(for: friend)))
                }
            case .buff:
                let changes = Self.statChanges(of: skill, level: level)
                let lasting = min(Double((skill.rounds ?? Self.buffLength) + 1), rounds)
                func value(for friend: Combatant) -> Double {
                    changes.map { change -> Double in
                        // What's raised already counts for nothing; a drop in return costs.
                        let gain = change.amount > 0 ? max(0, change.amount - (friend.raised[change.stat]?.amount ?? 0)) : change.amount
                        return gain * statWorth(change.stat, of: friend, against: foes, among: friends)
                    }.reduce(0, +) * lasting
                }
                if skill.target == .allAllies {
                    choices.append((action: .skill(skill.id, target: fighter.id), value: friends.map(value(for:)).reduce(0, +)))
                } else if let friend = friends.max(by: { value(for: $0) < value(for: $1) }) {
                    choices.append((action: .skill(skill.id, target: friend.id), value: value(for: friend)))
                }
            case .revive, .field:
                break
            }
            // MP costs a little (a skill should beat a plain blow by more than it spends), and a
            // lot once it eats into what a healer keeps back for healing.
            let cost = Double(GameSession.mpCost(of: skill, level: level))
            let dips = skill.kind != .heal && Double(fighter.mp) - cost < reserve
            let price = cost * blow * (dips ? 0.4 : 0.08)
            for choice in choices where choice.value > 0 {
                // A friend seldom echoes the skill you just used.
                let echo = fighter.isAlly && skill.id == heroSkill ? 0.6 : 1
                options.append((action: choice.action, value: (choice.value - price) * echo))
            }
        }
        return options
    }

    /// The best move, or now and then the next best when it's worth nearly as much.
    private func pick(from options: [(action: BattleAction, value: Double)]) -> BattleAction? {
        let ranked = options.sorted { $0.value > $1.value }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, best.value > 0, ranked[1].value >= best.value * 0.85, Double.random(in: 0..<1, using: &rng) < 0.35 {
            return ranked[1].action
        }
        return best.action
    }

    /// What a blow is worth: the HP it takes (no more than the foe has left), a little more on a
    /// foe already worn down (better to finish one off than scratch them all), and for one that
    /// finishes the foe off, half as much again as the foe would hit back with each round.
    private func blowValue(_ damage: Double, on foe: Combatant, by fighter: Combatant) -> Double {
        let hp = Double(foe.hp)
        let focus = 1 + 0.3 * (1 - foe.hpFraction)
        return min(damage, hp) * focus + (damage >= hp ? expectedDamage(from: foe, to: fighter, skill: nil) * 1.5 : 0)
    }

    /// What a round of a raised stat is worth to a fighter, per point of the raise (1 = +100%).
    private func statWorth(_ stat: BattleStat, of friend: Combatant, against foes: [Combatant], among friends: [Combatant]) -> Double {
        guard !foes.isEmpty else { return 0 }
        let count = Double(foes.count)
        let hitting = foes.map { expectedDamage(from: friend, to: $0, skill: nil) }.reduce(0, +) / count
        switch stat {
        case .attack:
            return hitting
        case .magic:
            // Only to someone who casts.
            let casts = friend.skills.contains { content.skill($0).map { $0.kind == .magic || $0.kind == .heal } == true }
            return casts ? foes.map { magicPower(of: friend, against: $0) }.reduce(0, +) / count : 0
        case .defense:
            // The monsters' blows shared out among the party.
            let incoming = foes.map { expectedDamage(from: $0, to: friend, skill: nil) }.reduce(0, +) / Double(max(1, friends.count))
            return incoming * 0.6
        case .speed:
            return hitting * 0.3
        }
    }

    /// About how many more rounds the fight has in it: the other side's HP over what this side
    /// deals in a round with plain blows (at least one).
    private func roundsLeft(for side: BattleSide) -> Double {
        let ours = alive(on: side)
        let theirs = alive(on: side.opposite)
        guard !ours.isEmpty, !theirs.isEmpty else { return 1 }
        let left = theirs.map { Double($0.hp) }.reduce(0, +)
        let perRound = ours.map { fighter in
            theirs.map { expectedDamage(from: fighter, to: $0, skill: nil) }.reduce(0, +) / Double(theirs.count)
        }.reduce(0, +)
        return max(1, left / max(1, perRound))
    }

    /// The MP a healer keeps back: enough for two of their cheapest heals or revives.
    private func mpReserve(of fighter: Combatant) -> Double {
        let support = fighter.skills.compactMap { content.skill($0) }.filter { $0.kind == .heal || $0.kind == .revive }
        guard let cheapest = support.map({ GameSession.mpCost(of: $0, level: fighter.skillLevel($0.id)) }).min() else { return 0 }
        return Double(cheapest * 2)
    }

    private func usableSkills(of fighter: Combatant) -> [SkillDef] {
        fighter.skills.compactMap { content.skill($0) }.filter { GameSession.mpCost(of: $0, level: fighter.skillLevel($0.id)) <= fighter.mp }
    }

    // MARK: - Targeting

    private func opponent(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isAlive, preferred.side != actor.side { return preferred }
        return alive(on: actor.side.opposite).randomElement(using: &rng)
    }

    private func ally(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isAlive, preferred.side == actor.side { return preferred }
        return alive(on: actor.side).min { $0.hpFraction < $1.hpFraction }
    }

    private func targets(for skill: SkillDef, actor: Combatant, preferring id: Int) -> [Combatant] {
        switch skill.target {
        case .enemy: opponent(of: actor, preferring: id).map { [$0] } ?? []
        case .ally: ally(of: actor, preferring: id).map { [$0] } ?? []
        case .allEnemies: alive(on: actor.side.opposite)
        case .allAllies: alive(on: actor.side)
        case .fallenAlly: fallen(of: actor, preferring: id).map { [$0] } ?? []
        }
    }

    /// A fainted fighter on `actor`'s side to revive: the one chosen if they're still down.
    private func fallen(of actor: Combatant, preferring id: Int) -> Combatant? {
        if let preferred = combatant(id), preferred.isFallen, preferred.side == actor.side { return preferred }
        return combatants.first { $0.side == actor.side && $0.isFallen && !$0.isHero }
    }

    // MARK: - Numbers

    /// Defence softens hits against a constant that grows past level 30, so fights take about
    /// as many hits at level 100 as at level 30 (stats grow with level; a fixed 30 would not).
    private func armorConstant(for defender: Combatant) -> Double {
        30 * max(1, Double(defender.level) / 30)
    }

    /// What a blow (`skill` nil) or a skill would do on average, without luck or criticals: for
    /// weighing choices. Magic counts its element against the target's.
    private func expectedDamage(from attacker: Combatant, to defender: Combatant, skill: SkillDef?) -> Double {
        let k = armorConstant(for: defender)
        var damage: Double
        if let skill, skill.kind == .magic {
            let effectiveness = (skill.element ?? .neutral).multiplier(against: defender.element)
            damage = attacker.magic * skill.power * Self.skillBoost(attacker.skillLevel(skill.id)) * effectiveness * k / (k + defender.defense / 2)
        } else {
            let power = skill.map { $0.power * Self.skillBoost(attacker.skillLevel($0.id)) } ?? 1
            damage = attacker.attack * power * k / (k + defender.defense)
        }
        if defender.isDefending { damage *= 0.5 }
        return max(1, damage)
    }

    /// A caster's spells against `defender`, roughly: their magic through its guard.
    private func magicPower(of attacker: Combatant, against defender: Combatant) -> Double {
        let k = armorConstant(for: defender)
        return attacker.magic * 1.5 * k / (k + defender.defense / 2)
    }

    private func physicalHit(from attacker: Combatant, to defender: Combatant, power: Double) -> Hit {
        let k = armorConstant(for: defender)
        var damage = attacker.attack * power * k / (k + defender.defense)
        damage *= Double.random(in: 0.9...1.1, using: &rng)
        let critical = Double.random(in: 0..<1, using: &rng) < 0.08
        if critical { damage *= 1.5 }
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: 1, critical: critical)
    }

    private func magicHit(from attacker: Combatant, to defender: Combatant, skill: SkillDef, boost: Double) -> Hit {
        let effectiveness = (skill.element ?? .neutral).multiplier(against: defender.element)
        let k = armorConstant(for: defender)
        var damage = attacker.magic * skill.power * boost * k / (k + defender.defense / 2)
        damage *= effectiveness * Double.random(in: 0.9...1.1, using: &rng)
        if defender.isDefending { damage *= 0.5 }
        return Hit(target: defender.id, amount: max(1, Int(damage.rounded())), effectiveness: effectiveness, critical: false)
    }

    /// Lays a poison, curse or freeze on a fighter still standing, if it takes hold. A second dose
    /// doesn't stack: it lasts as long, and bites as hard, as the stronger of the two.
    private func afflict(_ id: Int, with affliction: Affliction, from caster: Combatant, skill: SkillDef, boost: Double,
                         events: inout [BattleEvent]) {
        guard let target = combatant(id), target.isAlive,
              Double.random(in: 0..<1, using: &rng) < (affliction.chance ?? 1) else { return }
        switch affliction.effect {
        case .poison:
            let damage = poisonDamage(from: caster, to: target, skill: skill, power: affliction.power * boost)
            mutate(id) {
                $0.poisonRounds = max($0.poisonRounds, affliction.rounds)
                $0.poisonDamage = max($0.poisonDamage, damage)
            }
        case .curse:
            break
        case .freeze:
            mutate(id) { $0.frozenRounds = max($0.frozenRounds, affliction.rounds) }
        }
        events.append(.afflicted(target: id, effect: affliction.effect, rounds: affliction.rounds))
        if affliction.effect == .curse {
            // It lowers the stats behind its target's hits (attack and magic, unless it names
            // others), like a buff the other way: the rest of this round and the ones after.
            let stats = affliction.stats?.compactMap(BattleStat.init(rawValue:)) ?? [.attack, .magic]
            let power = affliction.power * boost
            changeStats(of: id, stats.map { StatChange(stat: $0, amount: -power) }, rounds: affliction.rounds + 1, events: &events)
        }
    }

    /// Raises and lowers a fighter's stats for `rounds` (counting this one), and tells the scene
    /// where they stand now (a weaker second spell leaves the stronger first one in place).
    private func changeStats(of id: Int, _ changes: [StatChange], rounds: Int, events: inout [BattleEvent]) {
        guard !changes.isEmpty, combatant(id)?.isAlive == true else { return }
        mutate(id) { $0.change(changes, rounds: rounds) }
        guard let fighter = combatant(id) else { return }
        let now = changes.map { change in
            StatChange(stat: change.stat, amount: change.amount > 0
                ? fighter.raised[change.stat]?.amount ?? 0
                : -(fighter.lowered[change.stat]?.amount ?? 0))
        }
        events.append(.statsChanged(target: id, changes: now, rounds: rounds - 1))
    }

    /// Each round's poison bite, fixed when it lands: a share of a hit from the caster, magic for
    /// spells and strength for bites, of the skill's element. Guard doesn't keep it out.
    private func poisonDamage(from caster: Combatant, to target: Combatant, skill: SkillDef, power: Double) -> Int {
        let k = armorConstant(for: target)
        let force = skill.kind == .physical ? caster.attack : caster.magic
        let effectiveness = (skill.element ?? .neutral).multiplier(against: target.element)
        let damage = force * power * effectiveness * k / (k + target.defense / 2)
        return max(1, Int(damage.rounded()))
    }

    private func healAmount(_ caster: Combatant, _ skill: SkillDef) -> Int {
        Int((caster.magic * skill.power + 8).rounded())
    }

    private func applyDamage(_ hit: Hit, events: inout [BattleEvent]) {
        guard let index = combatants.firstIndex(where: { $0.id == hit.target }), combatants[index].hp > 0 else { return }
        combatants[index].hp = max(0, combatants[index].hp - hit.amount)
        if combatants[index].hp == 0 {
            // Fainting ends poison, curses, ice and blessings; a revived fighter starts clean.
            combatants[index].poisonRounds = 0
            combatants[index].frozenRounds = 0
            combatants[index].raised = [:]
            combatants[index].lowered = [:]
            events.append(.defeated(hit.target))
        }
    }

    private func mutate(_ id: Int, _ change: (inout Combatant) -> Void) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        change(&combatants[index])
    }

    private func updateOutcome() {
        guard outcome == .ongoing else { return }
        // A beaten wave with another to come isn't a win yet (the next one steps in at the round's end).
        if alive(on: .enemies).isEmpty, waves.isEmpty {
            outcome = combatants.contains { $0.side == .enemies && $0.hasFled } ? .fled : .victory
        } else if !combatants.contains(where: { ($0.isHero || $0.isAlly) && $0.isAlive }) {
            // Your friends fight on after you fall; it's lost once nobody is left standing
            // (companions don't fight on by themselves).
            outcome = .defeat
        }
    }

    #if DEBUG
    /// Debug launches (`win`): every monster drops at once, the waves still to come too.
    func defeatEnemiesForDebug() -> [BattleEvent] {
        for arrivals in waves { combatants += arrivals }
        waves = []
        var events: [BattleEvent] = []
        for index in combatants.indices where combatants[index].side == .enemies && combatants[index].isAlive {
            combatants[index].hp = 0
            events.append(.defeated(combatants[index].id))
        }
        updateOutcome()
        return events
    }

    /// Debug launches (`herodown`): the hero faints where they stand.
    func knockOutHeroForDebug() -> [BattleEvent] {
        guard let hero, hero.isAlive else { return [] }
        var events: [BattleEvent] = []
        applyDamage(Hit(target: hero.id, amount: hero.hp, effectiveness: 1, critical: false), events: &events)
        updateOutcome()
        return events
    }

    /// Debug launches (`afflict`): the first monster is poisoned, the next one cursed, and the
    /// hero poisoned and protected (DEF up), so the screenshot shows the marks.
    func afflictForDebug() {
        let foes = alive(on: .enemies)
        if let first = foes.first {
            mutate(first.id) {
                $0.poisonRounds = 3
                $0.poisonDamage = 6
            }
        }
        if foes.count > 1 {
            mutate(foes[1].id) { $0.change([StatChange(stat: .attack, amount: -0.2), StatChange(stat: .magic, amount: -0.2)], rounds: 3) }
        }
        if let hero {
            mutate(hero.id) {
                $0.poisonRounds = 2
                $0.poisonDamage = 4
                $0.change([StatChange(stat: .defense, amount: 0.4)], rounds: 3)
            }
        }
    }

    /// Debug launches (`cast=`): what the hero's `skill` at `level` does to each of `targets` on
    /// average (no luck, no criticals), so a frozen cast shows the numbers a real one would.
    func expectedHitsForDebug(_ skill: SkillDef, level: Int, on targets: [Int]) -> [Hit] {
        guard var caster = hero else { return [] }
        caster.skillLevels[skill.id] = level
        return targets.compactMap { combatant($0) }.map { foe in
            let effectiveness = skill.kind == .magic ? (skill.element ?? .neutral).multiplier(against: foe.element) : 1
            let amount = Int(expectedDamage(from: caster, to: foe, skill: skill).rounded())
            return Hit(target: foe.id, amount: amount, effectiveness: effectiveness, critical: false)
        }
    }
    #endif
}
