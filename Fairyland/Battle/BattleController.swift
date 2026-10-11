import Foundation
import Observation
import UIKit

struct BattleResult {
    let outcome: BattleOutcome
    let lines: [String]
    /// The hero's new level, if they levelled up (the result screen then offers skill choices).
    var newLevel: Int?
    /// The pay: EXP, gold, and what was found (item id and how many), shown as icons.
    var exp = 0
    var gold = 0
    var loot: [(id: String, count: Int)] = []
    /// How many levels the win was worth (the level-up banner adds up what they raised).
    var levelsGained = 0
    /// Friends and your companion who went up a level with the win.
    var others: [LevelUp] = []
    /// A boss beaten for the first time: what it means, told before the pay.
    var story: BossStory?
    /// Monster cards new to the Book (monster ids), shown face up.
    var newCards: [String] = []
}

/// Someone else in the party who went up a level with a win: a friend or your companion.
struct LevelUp {
    let name: String
    let level: Int
    /// What the log says about it.
    let line: String
    /// Their fighter, to celebrate on the field (nil when they weren't standing at the end).
    let fighterID: Int?
}

/// A boss's `victory` story (content/maps.json), with the boss to draw above it.
struct BossStory {
    let art: String
    let title: String
    let paragraphs: [String]
}

/// Runs one battle: turns the player's menu choices into engine actions, feeds the
/// resulting events to the scene for animation, and pays out rewards at the end.
@Observable
final class BattleController {
    enum Phase: Equatable {
        /// `stones`: choosing which Seal Stone to throw (Capture, with more than one kind in the bag).
        case command, skills, items, stones, target, animating, finished
    }

    private enum Pending {
        /// `capture`: the Seal Stone being aimed.
        case attack, skill(SkillDef), item(ItemDef), capture(ItemDef)
    }

    private(set) var phase: Phase = .command
    private(set) var message: String
    /// Display copy of the fighters; updates event by event as the scene animates.
    private(set) var combatants: [Combatant]
    private(set) var prompt = ""
    private(set) var validTargets: [Int] = []
    private(set) var result: BattleResult?
    /// A boss fight comes in waves: the one on the field, out of how many (1 of 1 otherwise).
    private(set) var wave = 1
    let waveCount: Int

    let session: GameSession
    /// What plays during the fight: the map's battle theme, or the boss theme.
    @ObservationIgnored var music: String
    @ObservationIgnored weak var scene: BattleScene?
    @ObservationIgnored var onFinish: (@MainActor (BattleOutcome) -> Void)?
    private let engine: BattleEngine
    @ObservationIgnored private var pending: Pending?
    /// The adventurer you're duelling: beaten, they drop what they carry.
    @ObservationIgnored private var rival: Adventurer?
    /// A boss you've never beaten: winning tells its story.
    @ObservationIgnored private var story: BossStory?
    /// The opening march is over and the first turn has started (`begin`).
    @ObservationIgnored private(set) var hasBegun = false

    init(engine: BattleEngine, session: GameSession, intro: String? = nil) {
        self.engine = engine
        self.session = session
        wave = engine.wave
        waveCount = engine.waveCount
        // Like Fairyland Online, a foe 5+ levels above you gets the tougher battle theme.
        let toughest = engine.alive(on: .enemies).map(\.level).max() ?? 0
        music = toughest >= session.data.hero.level + 5
            ? "battle_dark"
            : session.content.map(session.data.mapID)?.battleMusic ?? "battle"
        combatants = engine.combatants
        let names = engine.alive(on: .enemies).map(\.name)
        message = intro ?? (names.count == 1 ? L("A wild {monster} appears!", ["monster": names[0]]) : L("{count} monsters appear!", ["count": names.count]))
        if let rare = engine.alive(on: .enemies).first(where: \.isRare) {
            message += " ✦ " + L("A rare {monster}!", ["monster": rare.name])
        }
        for foe in engine.alive(on: .enemies) {
            if let id = foe.speciesID { session.sawMonster(id, level: foe.level) }
        }
    }

    /// You, your companion and the friends in your party who are at your side.
    private static func party(for session: GameSession) -> [Combatant] {
        var hero = Combatant(
            id: 0, side: .party, source: .hero, name: session.data.hero.name, art: GameSession.heroArt,
            level: session.data.hero.level, element: .neutral, stats: session.heroStats,
            hp: max(1, session.data.hero.hp), mp: session.data.hero.mp,
            skills: session.heroSkills.map(\.id), captureRate: 0
        )
        hero.skillLevels = Dictionary(uniqueKeysWithValues: session.heroSkills.map { ($0.id, session.skillLevel($0.id)) })
        hero.classID = session.data.hero.classID
        hero.raceID = session.data.hero.raceID
        var party: [Combatant] = [hero]
        if let pet = session.activePet, pet.hp > 0, let species = session.species(of: pet) {
            var companion = Combatant(
                id: 1, side: .party, source: .pet(pet.id), name: pet.name, art: session.artID(for: pet),
                level: pet.level, element: species.element, stats: session.stats(of: pet),
                hp: pet.hp, mp: pet.mp, skills: species.skills, captureRate: 0
            )
            // It stands beside you, or right behind you when friends fight with you (BattleScene.arrange).
            companion.ownerID = hero.id
            party.append(companion)
        }
        for (index, friend) in session.friendsAtYourSide.enumerated() {
            party.append(adventurer(friend, id: 2 + index, side: .party, session: session))
            // A friend's companion fights behind them (a step below their level, like a rival's),
            // named for its owner so it's never mistaken for yours.
            if let speciesID = friend.petSpecies, let species = session.content.monster(speciesID) {
                let level = max(1, friend.level - 1)
                let stats = species.stats(at: level)
                var companion = Combatant(
                    id: 2 + GameSession.maxAllies + index, side: .party, source: .pet(UUID()), name: L("{owner}'s {monster}", ["owner": friend.name, "monster": species.name]), art: species.art,
                    level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
                )
                companion.ownerID = 2 + index
                party.append(companion)
            }
        }
        return party
    }

    /// An adventurer as a fighter, at full strength.
    private static func adventurer(_ person: Adventurer, id: Int, side: BattleSide, session: GameSession) -> Combatant {
        let stats = session.stats(of: person)
        let skills = session.skills(of: person)
        // A friend at your side comes in with what their last fight left them; a rival is fresh.
        let hp = side == .party ? min(stats.hp, max(1, person.hp ?? stats.hp)) : stats.hp
        let mp = side == .party ? min(stats.mp, max(0, person.mp ?? stats.mp)) : stats.mp
        var fighter = Combatant(
            id: id, side: side, source: side == .party ? .ally(person.id) : .rival(person.id), name: person.name,
            art: session.artID(for: person), level: person.level, element: .neutral, stats: stats,
            hp: hp, mp: mp, skills: skills.map(\.id), captureRate: 0
        )
        fighter.skillLevels = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, Combatant.naturalSkillLevel(for: person.level)) })
        fighter.classID = person.classID
        fighter.raceID = person.raceID
        // A friend still without a companion brings their Seal Stones to catch one with.
        if side == .party, person.petSpecies == nil { fighter.sealStones = person.stonesLeft }
        return fighter
    }

    /// The adventurer a fighter is: a friend at your side or the rival you're duelling (not their
    /// companions, who come from the same person).
    func person(behind fighter: Combatant) -> Adventurer? {
        guard fighter.art.hasPrefix("adv:") else { return nil }
        switch fighter.source {
        case .ally(let id): return session.friends.first { $0.id == id }
        case .rival(let id): return rival?.id == id ? rival : nil
        default: return nil
        }
    }

    /// A duel with another adventurer (and their companion) in a danger zone.
    static func duel(with rival: Adventurer, session: GameSession) -> BattleController {
        var enemies = [adventurer(rival, id: 10, side: .enemies, session: session)]
        if let speciesID = rival.petSpecies, let species = session.content.monster(speciesID) {
            let level = max(1, rival.level - 1)
            let stats = species.stats(at: level)
            var companion = Combatant(
                id: 11, side: .enemies, source: .rival(rival.id), name: L("{owner}'s {monster}", ["owner": rival.name, "monster": species.name]), art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp, skills: species.skills, captureRate: 0
            )
            companion.ownerID = 10
            enemies.append(companion)
        }
        let engine = BattleEngine(party: party(for: session), enemies: enemies, content: session.content)
        let intro = rival.hostile ? L("{name} picks a fight with you!", ["name": rival.name]) : L("You challenge {name} to a duel!", ["name": rival.name])
        let controller = BattleController(engine: engine, session: session, intro: intro)
        controller.rival = rival
        return controller
    }

    /// A boss waiting on the map. The fight comes in waves (`waves` on the NPC, 3 unless it says
    /// otherwise): first waves of `waveSize` of the map's own monsters, then the boss with its
    /// minions (`minions`, enough to make `waveSize` unless set), standing at the back. Each wave is a little stronger than the
    /// one before, and the boss outranks them all. Your HP and MP carry from wave to wave.
    static func boss(_ npc: NPCDef, encounters: MapDef.Encounters? = nil, session: GameSession) -> BattleController? {
        guard let id = npc.monster, let species = session.content.monster(id),
              var waves = bossWaves(npc, encounters: encounters, session: session), !waves.isEmpty else { return nil }
        // Debug launches (`wave=n`, screenshots): the fight opens at that wave.
        if let start = DebugLaunch.bossWave, start > 1 { waves.removeFirst(min(start - 1, waves.count - 1)) }
        let engine = BattleEngine(party: party(for: session), enemies: waves[0], content: session.content,
                                  captureBonus: session.heroClass.captureBonus ?? 1, waves: Array(waves.dropFirst()))
        let intro = if engine.waveCount > 1 && engine.wave < engine.waveCount {
            L("{monster} sends its followers! Wave {number} of {total}.", ["monster": species.name, "number": engine.wave, "total": engine.waveCount])
        } else if engine.waveCount > 1 {
            L("Final wave: {monster} steps forward!", ["monster": species.name])
        } else if waves[0].count > 1 {
            L("{monster} and its followers block your way!", ["monster": species.name])
        } else {
            L("{monster} blocks your way!", ["monster": species.name])
        }
        let controller = BattleController(engine: engine, session: session, intro: intro)
        controller.music = "boss"
        if !session.isDefeated(npc), let victory = npc.victory {
            controller.story = BossStory(art: species.art, title: victory.title, paragraphs: victory.story)
        }
        return controller
    }

    /// How many fighters each wave of a boss fight has, the boss's own included.
    static let waveSize = 10
    /// How many levels lower each earlier wave of a boss fight stands, so ten at a time stays fair.
    static let levelStep = 6

    /// A boss fight's waves, in order: `waveSize` of the map's monsters in each wave before the
    /// boss's own, where it stands in the middle of the back row, behind its minions. Levels climb
    /// `levelStep` a wave: the boss's minions are 1 to 8 levels below it, the wave before 7 to 14,
    /// the one before that 13 to 20, within the map's range but never up to the boss's level. Wave n's fighters have ids from 100 × n.
    static func bossWaves(_ npc: NPCDef, encounters: MapDef.Encounters?, session: GameSession) -> [[Combatant]]? {
        guard let id = npc.monster, let species = session.content.monster(id) else { return nil }
        let level = npc.level ?? 10
        let followers = max(0, npc.minions ?? waveSize - 1)
        // Waves of monsters need the map's own; without them the boss stands alone.
        let count = (encounters?.monsters.isEmpty ?? true) ? 1 : max(1, npc.waves ?? 3)
        // The map's level range, kept below the boss's own.
        let mapTop = encounters.map { max($0.levels.first ?? 1, $0.levels.last ?? 1) } ?? level
        let highest = max(1, min(mapTop, level - 1))
        let lowest = min(encounters?.levels.first ?? 1, highest)

        func monsters(_ amount: Int, wave: Int) -> [Combatant] {
            guard let encounters, amount > 0 else { return [] }
            let back = levelStep * (count - wave)
            let top = max(lowest, min(highest, level - 1 - back))
            let bottom = max(lowest, min(top, level - 8 - back))
            var group: [Combatant] = []
            for index in 0..<amount {
                guard let kindID = pick(from: encounters.monsters), let kind = session.content.monster(kindID) else { continue }
                let kindLevel = Int.random(in: bottom...top)
                let stats = kind.stats(at: kindLevel)
                var monster = Combatant(
                    id: 100 * wave + 1 + index, side: .enemies, source: .wild(kindID), name: kind.name, art: kind.art,
                    level: kindLevel, element: kind.element, stats: stats, hp: stats.hp, mp: stats.mp,
                    skills: kind.skills, captureRate: kind.captureRate
                )
                monster.isRare = kind.rare == true
                monster.wave = wave
                group.append(monster)
            }
            return group
        }

        var waves: [[Combatant]] = (1..<count).map { monsters(waveSize, wave: $0) }
        let stats = species.stats(at: level)
        var boss = Combatant(id: 100 * count, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                             level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                             skills: species.skills, captureRate: 0)
        boss.wave = count
        var lastWave = monsters(followers, wave: count)
        // The battle stands a side in rows of five, the first one furthest from you: the boss takes
        // the middle of that row, behind its minions.
        lastWave.insert(boss, at: min(5, lastWave.count + 1) / 2)
        waves.append(lastWave)
        return waves
    }

    /// How often each monster turns up on the current map: its encounter table, with a rare one
    /// sighted here (an announcement, `GameSession.sighting`) `boost` times as often until it's over.
    static func encounterWeights(_ encounters: MapDef.Encounters, session: GameSession) -> [String: Int] {
        var weights = encounters.monsters
        if let sighting = session.sighting, sighting.mapID == session.data.mapID, sighting.until > Date(),
           let weight = weights[sighting.monsterID] {
            weights[sighting.monsterID] = weight * sighting.boost
        }
        return weights
    }

    /// Builds a random encounter for the current map.
    static func encounter(_ encounters: MapDef.Encounters, session: GameSession) -> BattleController {
        let content = session.content
        let party = party(for: session)
        let weights = encounterWeights(encounters, session: session)

        let low = encounters.groupSize.first ?? 1
        let high = max(low, encounters.groupSize.last ?? low)
        let minLevel = encounters.levels.first ?? 1
        let maxLevel = max(minLevel, encounters.levels.last ?? minLevel)
        // Small groups are common, the biggest rare (squaring the roll leans it low).
        let count = min(high, low + Int(pow(Double.random(in: 0..<1), 2) * Double(high - low + 1)))
        var enemies: [Combatant] = []
        for index in 0..<count {
            guard let id = pick(from: weights), let species = content.monster(id) else { continue }
            let level = Int.random(in: minLevel...maxLevel)
            let stats = species.stats(at: level)
            var enemy = Combatant(
                id: 10 + index, side: .enemies, source: .wild(id), name: species.name, art: species.art,
                level: level, element: species.element, stats: stats, hp: stats.hp, mp: stats.mp,
                skills: species.skills, captureRate: species.captureRate
            )
            enemy.isRare = species.rare == true
            enemies.append(enemy)
        }
        let engine = BattleEngine(party: party, enemies: enemies, content: content, captureBonus: session.heroClass.captureBonus ?? 1)
        let controller = BattleController(engine: engine, session: session)
        controller.isWild = true
        controller.isAuto = GameSettings.autoBattle && controller.canAuto
        return controller
    }

    private static func pick(from weights: [String: Int]) -> String? {
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Int.random(in: 0..<total)
        for (id, weight) in weights.sorted(by: { $0.key < $1.key }) {
            if roll < weight { return id }
            roll -= weight
        }
        return nil
    }

    // MARK: - Reading

    /// Set when the hero levels up during the victory payout.
    private var newLevel: Int?
    private var levelsGained = 0
    /// Friends and your companion who went up a level with the win.
    private var othersLevelled: [LevelUp] = []
    private var rewardEXP = 0
    private var rewardGold = 0
    /// Item id → how many were found after a win.
    private var loot: [String: Int] = [:]
    /// Monster cards new to the Book after a win (monster ids), and the lines that told of them.
    private var newCards: [String] = []
    private var newCardLines: Set<String> = []

    var hero: Combatant? { combatants.first(where: \.isHero) }
    var party: [Combatant] { combatants.filter { $0.side == .party } }
    var enemies: [Combatant] { combatants.filter { $0.side == .enemies } }
    /// The wave on the field (a boss fight's beaten waves have left it).
    var enemiesOnField: [Combatant] { enemies.filter { $0.wave == wave } }
    /// Skills usable in battle (Bridge of Light and other field spells are cast from the menu).
    var skills: [SkillDef] { session.heroSkills.filter { $0.kind != .field } }
    /// Potions and the like, then Seal Stones (thrown at a monster, like Capture).
    var items: [ItemDef] { session.battleItems + stones }

    /// The Seal Stones in the bag, plainest first and a Wishing Seal last.
    var stones: [ItemDef] { session.sealStoneKinds }

    /// True when a hurt party member could use a healing item, so Items moves out from under "More".
    var needsHealing: Bool {
        guard items.contains(where: { ($0.heal ?? 0) > 0 }) else { return false }
        return party.contains { $0.isAlive && Double($0.hp) <= Double($0.stats.hp) * 0.35 }
    }

    /// True when you have a Seal Stone, a monster here could be sealed, and there's room for it
    /// (the Capture button lights up then).
    var canCapture: Bool {
        session.sealStones > 0 && hasRoomToSeal && !sealableIDs.isEmpty
    }

    /// The monsters a Seal Stone could hold (not a boss).
    private var sealableIDs: [Int] {
        enemies.filter { enemy in
            if case .ready = engine.captureStatus(of: enemy.id) { return true }
            return false
        }
        .map(\.id)
    }

    /// Room for one more companion from this fight: a full party can still take one (the result
    /// screen asks who stays behind), but not two.
    private var hasRoomToSeal: Bool {
        session.data.pets.count + sealedByYou.count <= GameSession.maxPets
    }

    /// The monsters you sealed this fight (a friend's catch goes home with them).
    private var sealedByYou: [Combatant] {
        engine.combatants.filter { $0.isCaptured && $0.capturedBy == engine.hero?.id }
    }

    func name(_ id: Int) -> String { combatants.first { $0.id == id }?.name ?? "?" }

    private var aliveEnemyIDs: [Int] { enemies.filter(\.isAlive).map(\.id) }
    private var aliveAllyIDs: [Int] { party.filter(\.isAlive).map(\.id) }

    // MARK: - Your companion's turn

    /// Your own companion while it's standing (friends' companions fight on their own).
    var companion: Combatant? {
        guard let id = session.activePet?.id else { return nil }
        return combatants.first { $0.petID == id && $0.isAlive }
    }

    /// True while you choose what your companion does, after the hero's choice. Like Fairyland,
    /// you command your pet every round (unless `GameSettings.commandCompanion` is off). The hero's
    /// choice stands: there's no taking it back on the companion's turn.
    private(set) var choosingForCompanion = false
    /// The hero's choice, waiting while you choose the companion's.
    @ObservationIgnored private var heroChoice: BattleAction?
    /// When this round's time to choose began, and how far into it (0...1) you locked in your
    /// hero's move: your place among your friends this round (`BattleEngine.resolveRound`).
    @ObservationIgnored private var choosingSince: Date?
    @ObservationIgnored private var heroChoseAt: Double = 0

    /// Its skills, for the Skills list on its turn.
    var companionSkills: [SkillDef] { companion?.skills.compactMap { session.content.skill($0) } ?? [] }
    func companionLevel(of skill: SkillDef) -> Int { companion?.skillLevel(skill.id) ?? 1 }
    func companionCost(of skill: SkillDef) -> Int { GameSession.mpCost(of: skill, level: companionLevel(of: skill)) }

    /// Auto: the companion decides for itself this round.
    func letCompanionDecide() {
        guard choosingForCompanion else { return }
        stopTurnClock()
        clearTargets()
        choosingForCompanion = false
        resolve(heroChoice ?? .defend, orders: [:])
    }

    // MARK: - Pace

    /// How fast the fight plays (the 2× button): its animations and the pauses between rounds that
    /// play by themselves, never your time to choose. Kept for the next fights.
    private(set) var speed = GameSettings.battleSpeed

    func toggleSpeed() {
        speed = speed > 1 ? 1 : 2
        UserDefaults.standard.set(speed, forKey: GameSettings.battleSpeedKey)
        scene?.setPace(speed)
    }

    /// Auto: the hero fights by themselves, as a friend in your party would
    /// (`BattleEngine.autoAction`), your companion decides for itself, and the rounds play on their
    /// own until you switch it off. Only in a wild fight against monsters well below you, never a
    /// boss or a duel; it hands back to you when you're badly hurt. Left on, it's on in the next
    /// fight it's allowed in.
    private(set) var isAuto = false
    /// A wild encounter (not a boss or a duel), where Auto may play.
    @ObservationIgnored private(set) var isWild = false
    /// How many levels below you every monster must be for Auto.
    static let autoLevelGap = 5
    /// Below this share of HP, Auto stops and you choose again.
    static let autoStopsBelow = 0.3

    /// Auto is allowed here: a wild fight where every monster standing is well below you.
    var canAuto: Bool {
        guard isWild, let hero, hero.isAlive else { return false }
        let standing = enemies.filter(\.isAlive)
        return !standing.isEmpty && standing.allSatisfy { $0.level <= hero.level - Self.autoLevelGap }
    }

    /// Auto plays the next round: it's on, allowed here, and you're not badly hurt.
    private var autoPlays: Bool {
        isAuto && canAuto && (hero?.hpFraction ?? 0) >= Self.autoStopsBelow
    }

    func toggleAuto() {
        guard phase != .finished else { return }
        if isAuto {
            isAuto = false
            UserDefaults.standard.set(false, forKey: GameSettings.autoBattleKey)
            return
        }
        guard canAuto else {
            message = isWild
                ? L("Auto fights only monsters at least {count} levels below you.", ["count": Self.autoLevelGap])
                : L("No Auto against a boss or in a duel.")
            return
        }
        isAuto = true
        UserDefaults.standard.set(true, forKey: GameSettings.autoBattleKey)
        // Mid-choice, it plays on at once (with your choice, if you'd made it and were on your companion's).
        if isChoosing { autoRound() }
    }

    /// Everyone has marched in (`BattleScene.enter`): your first turn's clock starts, or on Auto
    /// the first round plays.
    func begin() {
        guard !hasBegun else { return }
        hasBegun = true
        if autoPlays, phase == .command, !choosingForCompanion {
            playOnAuto(after: 300)
        } else {
            if phase == .command { armAttack() }
            startTurnClock()
        }
    }

    /// Plays the next round on Auto after a short pause (or hands back to you if Auto was switched
    /// off meanwhile). The chat holds it, as it holds the turn clock.
    private func playOnAuto(after milliseconds: Int = 500) {
        phase = .animating
        message = L("Auto: {hero} fights on…", ["hero": hero?.name ?? L("you")])
        Task { [weak self] in
            await self?.breather(milliseconds)
            while self?.holds.isEmpty == false { try? await Task.sleep(for: .milliseconds(250)) }
            guard let self, self.phase == .animating, self.result == nil else { return }
            if self.autoPlays { self.autoRound() } else { self.awaitCommand() }
        }
    }

    /// One round on Auto: the hero acts as a friend would (or as you'd chosen, mid-choice), and your
    /// companion decides for itself.
    private func autoRound() {
        stopTurnClock()
        clearTargets()
        let action = heroChoice ?? hero.map { engine.autoAction(for: $0.id) } ?? .defend
        choosingForCompanion = false
        resolve(action, orders: [:])
    }

    /// Your turn to choose; the turn clock starts.
    private func awaitCommand(note: String? = nil) {
        phase = .command
        armAttack()
        let ask = L("What will {hero} do?", ["hero": hero?.name ?? L("you")])
        message = note.map { "\($0) \(ask)" } ?? ask
        startTurnClock()
    }

    /// Attack is already chosen when a turn starts, yours or your companion's, as in Fairyland: the
    /// monsters show as targets, and tapping one attacks it, without the Attack button first. A
    /// skill, an item or Capture takes over the targets when you pick it.
    private func armAttack() {
        pending = .attack
        validTargets = aliveEnemyIDs
        scene?.showTargets(validTargets)
    }

    /// A pause before something that plays by itself, shorter at 2×. None without a scene (tests).
    private func breather(_ milliseconds: Int) async {
        guard scene != nil else { return }
        try? await Task.sleep(for: .milliseconds(Int(Double(milliseconds) / speed)))
    }

    // MARK: - Commands

    func attack() {
        let prompt = choosingForCompanion ? L("{companion} attacks which monster?", ["companion": companion?.name ?? L("It")]) : L("Attack which monster?")
        beginTargeting(.attack, targets: aliveEnemyIDs, prompt: prompt)
    }

    func openSkills() {
        guard phase == .command else { return }
        clearTargets()
        phase = .skills
    }

    func openItems() {
        guard phase == .command else { return }
        clearTargets()
        phase = .items
    }

    func back() {
        // Out of time just as you backed out: the round is already playing.
        guard isChoosing else { return }
        clearTargets()
        phase = .command
        armAttack()
    }

    func level(of skill: SkillDef) -> Int { session.skillLevel(skill.id) }

    /// Saves a new order for the battle buttons (from holding one down).
    func arrangeButtons(_ order: [String]) {
        session.data.battleButtons = order
        session.save()
    }

    func cost(of skill: SkillDef) -> Int { GameSession.mpCost(of: skill, level: level(of: skill)) }

    func useSkill(_ skill: SkillDef) {
        let user = choosingForCompanion ? companion : hero
        let price = choosingForCompanion ? companionCost(of: skill) : cost(of: skill)
        guard let user, user.mp >= price else {
            message = L("Not enough MP for {skill}.", ["skill": skill.name])
            return
        }
        switch skill.target {
        case .enemy: beginTargeting(.skill(skill), targets: aliveEnemyIDs, prompt: L("{skill}: choose a monster", ["skill": skill.name]))
        case .ally: beginTargeting(.skill(skill), targets: aliveAllyIDs, prompt: L("{skill}: choose who", ["skill": skill.name]))
        case .fallenAlly:
            let fallen = party.filter { $0.isFallen && !$0.isHero }.map(\.id)
            guard !fallen.isEmpty else {
                message = L("Nobody has fainted. {skill} can wait.", ["skill": skill.name])
                return
            }
            beginTargeting(.skill(skill), targets: fallen, prompt: L("{skill}: wake who?", ["skill": skill.name]))
        case .allEnemies, .allAllies: submit(.skill(skill.id, target: -1))
        }
    }

    func useItem(_ item: ItemDef) {
        // A Seal Stone is thrown at a monster, as with Capture.
        if item.capture == true { return capture(with: item) }
        beginTargeting(.item(item), targets: aliveAllyIDs, prompt: L("Use {item} on…", ["item": item.name]))
    }

    /// The Capture button: with one kind of Seal Stone in the bag it's thrown; with more (a Moon
    /// Seal, a Heart Seal...) you choose which. A Wishing Seal is never thrown without asking, so
    /// with only those left you choose too.
    func capture() {
        if stones.isEmpty {
            message = L("You need a Seal Stone. Trader Bo in Meadowbrook sells them.")
        } else if stones.count == 1, let stone = stones.first, stone.sure != true {
            capture(with: stone)
        } else {
            guard phase == .command else { return }
            clearTargets()
            phase = .stones
        }
    }

    /// Aims a Seal Stone: the monsters it could hold light up, each with the odds of this stone
    /// holding it.
    func capture(with stone: ItemDef) {
        guard session.count(of: stone.id) > 0 else {
            message = L("You need a Seal Stone. Trader Bo in Meadowbrook sells them.")
            return
        }
        guard hasRoomToSeal else {
            message = L("Your party is full, and a new friend is already waiting to join.")
            return
        }
        guard !sealableIDs.isEmpty else {
            message = L("{name} can't be captured.", ["name": enemies.first(where: \.isAlive)?.name ?? L("The monster")])
            return
        }
        var odds: [Int: String] = [:]
        for id in sealableIDs {
            if case .ready(let chance) = engine.captureStatus(of: id, with: stone) {
                odds[id] = L("{chance}%", ["chance": Int((chance * 100).rounded())])
            }
        }
        beginTargeting(.capture(stone), targets: sealableIDs, prompt: L("Throw a {stone} at…", ["stone": stone.name]), labels: odds)
    }

    func defend() { submit(.defend) }

    func escape() { submit(.escape) }

    /// A target was tapped in the scene or picked in the menu (on a turn's command menu, a monster
    /// tapped is attacked: `armAttack`, unless the chat or rearranging the buttons has your attention).
    func select(_ id: Int) {
        guard phase == .target || (phase == .command && holds.isEmpty), validTargets.contains(id), let pending else { return }
        switch pending {
        case .attack:
            submit(.attack(target: id))
        case .skill(let skill):
            submit(.skill(skill.id, target: id))
        case .item(let item):
            submit(.item(item.id, target: id))
        case .capture(let stone):
            switch engine.captureStatus(of: id, with: stone) {
            case .ready: submit(.capture(target: id, stone: stone.id))
            case .impossible: message = L("{name} can't be captured.", ["name": name(id)])
            }
        }
    }

    func leave() {
        onFinish?(engine.outcome)
    }

    /// `labels`: a word over some targets (a Seal Stone's odds on each monster). With only one to
    /// choose (one monster left, or only you to heal) there's nothing to pick: it goes straight
    /// there, unless that one can't be chosen after all (a monster no stone can hold), which still
    /// shows why.
    private func beginTargeting(_ command: Pending, targets: [Int], prompt: String, labels: [Int: String] = [:]) {
        guard !targets.isEmpty else { return }
        pending = command
        validTargets = targets
        self.prompt = prompt
        phase = .target
        if targets.count == 1 {
            select(targets[0])
            guard phase == .target else { return }
        }
        scene?.showTargets(targets, labels: labels)
    }

    /// The choice for whoever's turn it is. After the hero's, your companion gets its turn (unless
    /// it fights on its own, or you're running away); after the companion's, the round plays.
    private func submit(_ action: BattleAction, askCompanion: Bool = true) {
        stopTurnClock()
        clearTargets()
        if !choosingForCompanion {
            // Measured against the time to choose (ten seconds when there's no clock).
            let window = Self.turnSeconds ?? 10
            heroChoseAt = min(1, max(0, Date().timeIntervalSince(choosingSince ?? Date()) / window))
        }
        if choosingForCompanion {
            choosingForCompanion = false
            resolve(heroChoice ?? .defend, orders: companion.map { [$0.id: action] } ?? [:])
            return
        }
        switch action {
        case .attack(let target): lastTarget = target
        case .skill(_, let target) where aliveEnemyIDs.contains(target): lastTarget = target
        default: break
        }
        if askCompanion, GameSettings.commandCompanion, let companion, !action.isEscape {
            heroChoice = action
            choosingForCompanion = true
            phase = .command
            armAttack()
            message = L("What will {hero} do?", ["hero": companion.name])
            startTurnClock()
            return
        }
        resolve(action, orders: [:])
    }

    private func clearTargets() {
        pending = nil
        validTargets = []
        scene?.showTargets([])
    }

    /// Plays the round with everyone's choices.
    private func resolve(_ heroAction: BattleAction, orders: [Int: BattleAction]) {
        heroChoice = nil
        choosingSince = nil
        phase = .animating
        let events = engine.resolveRound(heroAction: heroAction, orders: orders, heroChoseAt: heroChoseAt)
        heroChoseAt = 0
        Task {
            if let scene {
                await scene.play(events)
            } else {
                for event in events { apply(event) }
            }
            roundFinished()
        }
    }

    // MARK: - Turn clock

    /// Seconds you get to choose each turn before the hero just attacks: Settings' Time to choose
    /// (Off, 10, 20 or 30). None with VoiceOver or Switch Control on, since a target is picked on the
    /// battle field, which they can't reach in time. None in tests and debug launches (screenshots
    /// wait in battle for a while), unless `turntimer=` sets one.
    static var turnSeconds: TimeInterval? {
        if let seconds = DebugLaunch.turnSeconds { return seconds }
        if DebugLaunch.isActive || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning { return nil }
        let seconds = GameSettings.turnTimer
        return seconds > 0 ? seconds : nil
    }

    /// When the time to choose runs out; nil while no clock is ticking.
    private(set) var turnDeadline: Date?
    @ObservationIgnored private var turnClock: Task<Void, Never>?
    /// Time left on a clock that's on hold, and what's holding it (the chat, moving the buttons).
    @ObservationIgnored private var heldTime: TimeInterval?
    @ObservationIgnored private var holds: Set<String> = []
    /// The monster you last went for: a timed-out attack goes for it again.
    @ObservationIgnored private var lastTarget: Int?

    private var isChoosing: Bool { [.command, .skills, .items, .stones, .target].contains(phase) }

    /// Starts the clock for a turn: each new one, and the first once the battle is on screen.
    func startTurnClock() {
        if !choosingForCompanion, choosingSince == nil, isChoosing { choosingSince = Date() }
        guard let seconds = Self.turnSeconds, isChoosing, turnClock == nil, heldTime == nil else { return }
        if holds.isEmpty {
            runTurnClock(seconds)
        } else {
            heldTime = seconds
        }
    }

    /// Holds the clock while something else has your attention, and starts it again where it was.
    func holdTurnClock(_ held: Bool, for reason: String) {
        if held {
            let running = holds.isEmpty
            holds.insert(reason)
            guard running, let deadline = turnDeadline else { return }
            heldTime = max(1, deadline.timeIntervalSinceNow)
            turnClock?.cancel()
            turnClock = nil
            turnDeadline = nil
        } else {
            holds.remove(reason)
            guard holds.isEmpty, let left = heldTime, isChoosing else { return }
            heldTime = nil
            runTurnClock(left)
        }
    }

    private func runTurnClock(_ seconds: TimeInterval) {
        turnClock?.cancel()
        turnDeadline = Date().addingTimeInterval(seconds)
        turnClock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.timeIsUp()
        }
    }

    private func stopTurnClock() {
        turnClock?.cancel()
        turnClock = nil
        turnDeadline = nil
        heldTime = nil
    }

    /// Out of time: the hero attacks the monster they last went for, or the first one standing, and
    /// the companion fights on its own. On the companion's turn, it decides for itself.
    private func timeIsUp() {
        turnClock = nil
        guard isChoosing, holds.isEmpty else { return }
        if choosingForCompanion {
            message = L("Time's up! {companion} fights on its own.", ["companion": companion?.name ?? L("Your companion")])
            letCompanionDecide()
            return
        }
        let standing = aliveEnemyIDs
        guard let target = lastTarget.flatMap({ standing.contains($0) ? $0 : nil }) ?? standing.first else { return }
        message = L("Time's up! {hero} attacks.", ["hero": hero?.name ?? L("You")])
        submit(.attack(target: target), askCompanion: false)
    }

    // MARK: - Playback

    /// Updates the display state and battle log for one event (called by the scene mid-animation).
    func apply(_ event: BattleEvent) {
        switch event {
        case .attack(let actor, let hit):
            damage(hit)
            SoundEffects.shared.play(hit.critical ? .crit : .hit)
            Haptics.impact(hit.critical ? .medium : .light)
            message = L("{attacker} attacks {target}!", ["attacker": name(actor), "target": name(hit.target)]) + (hit.critical ? " " + L("Critical hit!") : "")
        case .skill(let actor, let skill, let level, let hits):
            mutate(actor) { $0.mp = max(0, $0.mp - GameSession.mpCost(of: skill, level: level)) }
            // It sounds like what it is, and fuller in each of the five tiers its effects grow in.
            SoundEffects.shared.play(.landing(skill), volume: 0.75 + 0.05 * Float((level + 1) / 2))
            for hit in hits {
                switch skill.kind {
                case .heal, .revive: mutate(hit.target) { $0.hp = min($0.stats.hp, $0.hp + hit.amount) }
                case .physical, .magic: damage(hit)
                case .buff, .curse, .field: break
                }
            }
            var text = L("{attacker} uses {skill}!", ["attacker": name(actor), "skill": skill.name])
            if skill.kind == .revive, let hit = hits.first { text += " " + L("{target} is back on their feet!", ["target": name(hit.target)]) }
            if hits.contains(where: { $0.effectiveness > 1 }) { text += " " + L("A weak spot!") }
            if hits.contains(where: { $0.effectiveness < 1 }) { text += " " + L("It was resisted…") }
            message = text
        case .item(let actor, let item, let target, let hp, let mp):
            // Only used up once it actually reaches someone.
            session.removeItem(item.id)
            SoundEffects.shared.play(.potion)
            mutate(target) {
                $0.hp += hp
                $0.mp += mp
            }
            message = L("{attacker} uses a {item} on {target}.", ["attacker": name(actor), "item": item.name, "target": name(target)])
        case .defend(let actor):
            SoundEffects.shared.play(.shield)
            message = L("{name} is on guard.", ["name": name(actor)])
        case .capture(let actor, let target, let success, _, let stoneID):
            SoundEffects.shared.play(success ? .capture : .breakFree)
            if success {
                Haptics.success()
                mutate(target) { $0.isCaptured = true }
            }
            // Every throw uses the stone up, whether it holds or not: yours from the bag, a friend's
            // from their own.
            let thrower = engine.combatant(actor)
            let stone = stoneID.flatMap(session.content.item) ?? (thrower?.isHero == true ? stones.first : nil)
            if case .ally(let friendID)? = thrower?.source,
               let index = session.data.friends?.firstIndex(where: { $0.id == friendID }) {
                // Counted first: an optional-chained write starts changing `session.data` before its
                // right-hand side runs, so reading it there too is a simultaneous access, and a crash.
                let left = max(0, (session.data.friends?[index].stonesLeft ?? 1) - 1)
                session.data.friends?[index].sealStones = left
            } else if let stone {
                session.removeItem(stone.id)
            }
            message = success ? L("Sealed! {name} was captured!", ["name": name(target)])
                : L("Oh no! {name} broke free, and the {stone} crumbled away.", ["name": name(target), "stone": stone?.name ?? L("Seal Stone")])
        case .fled(let id):
            SoundEffects.shared.play(.run)
            mutate(id) { $0.hasFled = true }
            message = L("{name} ran away!", ["name": name(id)])
        case .escape(_, let success):
            SoundEffects.shared.play(success ? .run : .breakFree)
            message = success ? L("Got away safely!") : L("Couldn't get away!")
        case .defeated(let id):
            let fighter = combatants.first { $0.id == id }
            SoundEffects.shared.play(fighter?.side == .enemies ? .poof : .faint)
            message = fighter?.side == .enemies ? L("{name} is defeated!", ["name": name(id)]) : L("{name} fainted!", ["name": name(id)])
        case .message(let text):
            message = text
        case .afflicted(let target, let effect, let rounds):
            // A curse's drops come in the event after this one (`statsChanged`).
            if effect == .poison {
                mutate(target) { $0.poisonRounds = max($0.poisonRounds, rounds) }
            }
            if effect == .freeze {
                mutate(target) { $0.frozenRounds = max($0.frozenRounds, rounds) }
            }
            SoundEffects.shared.play(.faint, volume: 0.5)
            message = switch effect {
            case .poison: L("{name} is poisoned!", ["name": name(target)])
            case .curse: L("{name} is cursed!", ["name": name(target)])
            case .freeze: L("{name} is frozen solid!", ["name": name(target)])
            }
        case .frozen(let target):
            mutate(target) { $0.frozenRounds = max(0, $0.frozenRounds - 1) }
            message = L("{name} is frozen and can't move!", ["name": name(target)])
        case .statsChanged(let target, let changes, let rounds):
            mutate(target) { $0.change(changes, rounds: rounds + 1) }
            message = Self.statLine(name(target), changes, rounds: rounds)
        case .ailmentDamage(let target, _, let amount):
            mutate(target) {
                $0.hp = max(0, $0.hp - amount)
                $0.poisonRounds = max(0, $0.poisonRounds - 1)
            }
            SoundEffects.shared.play(.hit, volume: 0.6)
            Haptics.impact(.light)
            message = L("{name} is hurt by the poison!", ["name": name(target)])
        case .wave(let number, let total, let arrivals):
            combatants += arrivals
            wave = number
            for foe in arrivals {
                if let id = foe.speciesID { session.sawMonster(id, level: foe.level) }
            }
            SoundEffects.shared.play(.encounter)
            Haptics.impact(.medium)
            if number == total, let boss = arrivals.first(where: { $0.captureRate == 0 }) {
                message = L("Final wave: {monster} steps forward!", ["monster": boss.name])
            } else {
                message = arrivals.count == 1
                    ? L("Wave {number} of {total}: 1 more monster!", ["number": number, "total": total])
                    : L("Wave {number} of {total}: {count} more monsters!", ["number": number, "total": total, "count": arrivals.count])
            }
            if let rare = arrivals.first(where: \.isRare) { message += " ✦ " + L("A rare {monster}!", ["monster": rare.name]) }
        }
    }

    func announce(_ text: String) {
        message = text
    }

    /// Everyone one blow knocked out, at once: one sound and one line for them all.
    func applyDefeats(_ ids: [Int]) {
        guard ids.count > 1 else {
            if let id = ids.first { apply(.defeated(id)) }
            return
        }
        let foes = ids.filter { id in combatants.first { $0.id == id }?.side == .enemies }
        let friends = ids.filter { !foes.contains($0) }
        SoundEffects.shared.play(foes.isEmpty ? .faint : .poof)
        var lines: [String] = []
        if !foes.isEmpty {
            let names = Self.tally(foes.map { name($0) })
            lines.append(foes.count == 1 ? L("{names} is defeated!", ["names": names]) : L("{names} are defeated!", ["names": names]))
        }
        if !friends.isEmpty { lines.append(L("{names} fainted!", ["names": Self.tally(friends.map { name($0) })])) }
        message = lines.joined(separator: " ")
    }

    /// "Maple's ATK +25% and DEF +25% for 3 rounds!"
    static func statLine(_ name: String, _ changes: [StatChange], rounds: Int) -> String {
        let parts = changes.map { "\($0.stat.short) \(percent($0.amount))" }
        let stats = GameSession.listed(parts)
        return rounds == 1
            ? L("{name}'s {stats} for 1 round!", ["name": name, "stats": stats])
            : L("{name}'s {stats} for {rounds} rounds!", ["name": name, "stats": stats, "rounds": rounds])
    }

    /// A stat change as the battle shows it: "+25%", "−20%".
    static func percent(_ amount: Double) -> String {
        let value = Int((abs(amount) * 100).rounded())
        return amount >= 0 ? "+\(value)%" : "\u{2212}\(value)%"
    }

    /// Names in the order they fell, a repeated one counted: "Dark Beetle ×2 and Fire Rat".
    static func tally(_ names: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return GameSession.listed(order.map { name in
            let count = counts[name, default: 1]
            return count > 1 ? "\(name) ×\(count)" : name
        })
    }

    private func damage(_ hit: Hit) {
        mutate(hit.target) { $0.hp = max(0, $0.hp - hit.amount) }
    }

    private func mutate(_ id: Int, _ change: (inout Combatant) -> Void) {
        guard let index = combatants.firstIndex(where: { $0.id == id }) else { return }
        change(&combatants[index])
    }

    private func roundFinished() {
        combatants = engine.combatants
        // The marks count down at the start of a round (curses) as well as with each bite.
        scene?.refreshBars()
        switch engine.outcome {
        case .ongoing where heroIsDown:
            fightOnWithoutYou()
        case .ongoing where heroIsFrozen:
            sitOutFrozen()
        case .ongoing where autoPlays:
            playOnAuto()
        case .ongoing where isAuto && canAuto:
            // Badly hurt: Auto hands back to you (and comes on again in the next fight).
            isAuto = false
            awaitCommand(note: L("Auto stops: you're badly hurt!"))
        case .ongoing:
            awaitCommand()
        case .victory:
            finish(.victory, lines: concludeVictory() + afterTheFight())
        case .fled:
            let runaway = engine.combatants.first { $0.hasFled }?.name ?? L("The monster")
            finish(.fled, lines: [L("{name} ran away!", ["name": runaway])] + concludeVictory() + afterTheFight())
        case .defeat:
            finish(.defeat, lines: [L("{hero} fainted…", ["hero": hero?.name ?? L("You")])] + handOverSealed() + afterTheFight())
        case .escaped:
            syncParty()
            finish(.escaped, lines: [L("You got away safely.")] + handOverSealed() + afterTheFight())
        }
    }

    /// The hero has fainted: the fight goes on without them while a friend still stands.
    var heroIsDown: Bool { engine.hero?.isAlive == false }

    /// Frozen solid (Frost Breath): the hero loses their next turn, so there's nothing to choose.
    var heroIsFrozen: Bool { (engine.hero?.frozenRounds ?? 0) > 0 }

    /// The hero is frozen: the round plays without a command from you (your companion decides for
    /// itself), and the ice thaws when the hero's turn comes and goes.
    private func sitOutFrozen() {
        message = L("{hero} is frozen solid and can't move this round!", ["hero": hero?.name ?? L("You")])
        Task {
            await breather(1100)
            while !holds.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            // The engine skips a frozen fighter's turn, whatever it was told to do.
            resolve(.attack(target: aliveEnemyIDs.first ?? 0), orders: [:])
        }
    }

    /// While you lie fainted, the friends still standing fight on. The rounds play by themselves
    /// (your companion decides for itself), a moment apart so you can follow, until the fight is won
    /// or lost or someone wakes you. The chat holds them, as it holds the turn clock.
    private func fightOnWithoutYou() {
        let standing = party.filter { $0.isAlly && $0.isAlive }.map(\.name)
        let fallen = hero?.name ?? L("You")
        let friends = GameSession.listed(standing)
        message = standing.count == 1
            ? L("{hero} fainted! {names} fights on…", ["hero": fallen, "names": friends])
            : L("{hero} fainted! {names} fight on…", ["hero": fallen, "names": friends])
        Task {
            await breather(900)
            while !holds.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            resolve(.defend, orders: [:])
        }
    }

    /// Whoever fainted wakes up at their own checkpoint, you included even when your friends won,
    /// and friends still standing when you fell stay where the fight was (`GameSession.partWays`).
    private func afterTheFight() -> [String] {
        let fainted = Set(engine.combatants.compactMap { fighter -> UUID? in
            guard case .ally(let id) = fighter.source, !fighter.isAlive else { return nil }
            return id
        })
        let lines = session.partWays(fainted: fainted, heroFainted: heroIsDown)
        session.save()
        return lines
    }

    private func finish(_ outcome: BattleOutcome, lines: [String]) {
        stopTurnClock()
        let found = loot.sorted { $0.key < $1.key }.map { (id: $0.key, count: $0.value) }
        // The card shows level-ups as banners of their own; their lines go to the log.
        let levelText = newLevel.map { levelLine($0) }
        // New cards too: the card shows them face up.
        let othersText = Set(othersLevelled.map(\.line)).union(newCardLines)
        result = BattleResult(outcome: outcome, lines: lines.filter { $0 != levelText && !othersText.contains($0) }, newLevel: newLevel,
                              exp: rewardEXP, gold: rewardGold, loot: found, levelsGained: levelsGained,
                              others: othersLevelled, story: outcome == .victory ? story : nil, newCards: newCards)
        let won = outcome == .victory || outcome == .fled
        // The log gets it all in words; the result card shows the pay as icons.
        var logged = lines
        var pay: [String] = []
        if rewardEXP > 0 { pay.append(L("+{exp} EXP", ["exp": rewardEXP])) }
        if rewardGold > 0 { pay.append(L("+{gold} gold", ["gold": rewardGold])) }
        if !pay.isEmpty { logged.insert(pay.joined(separator: "    "), at: min(1, logged.count)) }
        for item in found {
            let name = session.content.item(item.id)?.name ?? item.id
            logged.append(item.count > 1 ? L("Found {item} ×{count}!", ["item": name, "count": item.count]) : L("Found {item}!", ["item": name]))
        }
        for line in logged { session.post(line, won ? .reward : .battle) }
        MusicPlayer.shared.play(won ? "victory" : nil)
        if outcome == .defeat { SoundEffects.shared.play(.lose) }
        guard newLevel != nil || !othersLevelled.isEmpty else {
            phase = .finished
            return
        }
        // A level-up gets its own moment on the field before the card: after the first notes of
        // the victory fanfare, light pours down on the hero with the level-up jingle, and on every
        // friend and companion who went up with them.
        message = ([newLevel.map { levelLine($0) }].compactMap { $0 } + othersLevelled.map(\.line)).joined(separator: " ")
        let others = othersLevelled
        Task {
            await breather(450)
            if let newLevel { scene?.celebrateLevelUp(to: newLevel) }
            for other in others {
                if let id = other.fighterID { scene?.celebrateLevelUp(of: id, to: other.level) }
            }
            SoundEffects.shared.play(.levelUp)
            Haptics.success()
            await breather(1500)
            phase = .finished
        }
    }

    private func levelLine(_ level: Int) -> String {
        L("{name} reached level {level}!", ["name": session.data.hero.name, "level": level])
    }

    #if DEBUG
    /// Debug launches (`win`): every monster falls at once (no falling animation: a CI simulator
    /// draws a frame every couple of seconds), and the win plays out as usual.
    func winForDebug() {
        guard phase == .command else { return }
        phase = .animating
        let events = engine.defeatEnemiesForDebug()
        // The later waves of a boss fight join the field all at once, so they have names in the log.
        combatants = engine.combatants
        for event in events { apply(event) }
        roundFinished()
    }

    /// Debug launches (`afflict`): poison and a curse on the field, so their marks show.
    func afflictForDebug() {
        engine.afflictForDebug()
        combatants = engine.combatants
        scene?.refreshBars()
    }

    /// Debug launches (`cast=`): what the hero's `skill` at `level` would do to each of `targets`.
    func expectedHitsForDebug(_ skill: SkillDef, level: Int, on targets: [Int]) -> [Hit] {
        engine.expectedHitsForDebug(skill, level: level, on: targets)
    }

    /// Debug launches (`herodown`): the hero faints where they stand, and any friends fight on.
    func knockOutHeroForDebug() {
        guard phase == .command, !choosingForCompanion else { return }
        stopTurnClock()
        phase = .animating
        let events = engine.knockOutHeroForDebug()
        Task {
            if let scene {
                await scene.play(events)
            } else {
                for event in events { apply(event) }
            }
            roundFinished()
        }
    }
    #endif

    /// Writes battle damage back to the hero, their companion and the friends at their side.
    private func syncParty() {
        if let hero = engine.hero {
            session.data.hero.hp = max(1, hero.hp)
            session.data.hero.mp = hero.mp
        }
        for fighter in engine.combatants {
            guard case .ally(let friendID) = fighter.source,
                  let index = session.data.friends?.firstIndex(where: { $0.id == friendID }) else { continue }
            // One who fainted is bruised when they wake (GameSession.partWays); the rest keep this.
            session.data.friends?[index].hp = max(1, fighter.hp)
            session.data.friends?[index].mp = fighter.mp
        }
        for fighter in engine.combatants {
            guard let petID = fighter.petID, let index = session.data.pets.firstIndex(where: { $0.id == petID }) else { continue }
            // A companion that fainted stays down until a potion or a healer wakes it up.
            session.data.pets[index].hp = max(0, fighter.hp)
            session.data.pets[index].mp = fighter.mp
        }
    }

    private func concludeVictory() -> [String] {
        syncParty()
        let content = session.content
        var lines: [String] = []
        // How hard the fight was is measured against the level you fought it at.
        let levelBefore = session.data.hero.level

        var exp = 0
        var gold = 0
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured && !foe.hasFled {
            if case .rival = foe.source {
                // The adventurer pays out for the duel, and drops everything they carry; their
                // companion comes along for free.
                if foe.art.hasPrefix("adv:") {
                    exp += 14 * foe.level
                    gold += 10 * foe.level
                    lines.append(L("You won the duel against {name}!", ["name": foe.name]))
                    if let rival {
                        let spoils = session.takeSpoils(from: rival)
                        for item in spoils { loot[item.id, default: 0] += 1 }
                        if !spoils.isEmpty { lines.append(L("{name} dropped everything they carried!", ["name": foe.name])) }
                    }
                }
                continue
            }
            guard let id = foe.speciesID, let species = content.monster(id) else { continue }
            exp += Int((Double(species.exp) * (1 + 0.35 * Double(foe.level - 1))).rounded())
            gold += Int((Double(species.gold) * (1 + 0.25 * Double(foe.level - 1))).rounded())
            session.record(.defeat, target: id)
            session.beatMonster(id, level: foe.level)
        }
        // Reborn heroes climb back faster.
        exp = Int((Double(exp) * session.rebirthEXPBoost).rounded())
        session.data.gold += gold
        rewardGold = gold

        if heroIsDown {
            // Out cold, you learn nothing from it, like a fainted companion. The spoils are shared.
            lines.append(L("Your friends won while you were out cold: no EXP for you this time."))
        } else {
            rewardEXP = exp
            let learnableBefore = Set(session.learnableSkills.map(\.id))
            let levels = session.gainHeroEXP(exp)
            if levels > 0 {
                newLevel = session.data.hero.level
                levelsGained = levels
                lines.append(levelLine(session.data.hero.level))
                for skill in session.learnableSkills where !learnableBefore.contains(skill.id) {
                    lines.append(L("New skill to learn: {skill}!", ["skill": skill.name]))
                }
                if session.canChooseClass {
                    lines.append(L("You can choose a path now! Visit a guild master in town."))
                }
            }
        }

        // Your friends still standing keep up with you, a level behind: whoever went up celebrates
        // with you.
        let standing = Set(engine.combatants.compactMap { fighter -> UUID? in
            guard case .ally(let id) = fighter.source, fighter.isAlive else { return nil }
            return id
        })
        for friend in session.growParty(standing: standing) {
            let fighter = engine.combatants.first { $0.source == .ally(friend.id) }
            let line = L("{name} reached level {level}!", ["name": friend.name, "level": friend.level])
            othersLevelled.append(LevelUp(name: friend.name, level: friend.level, line: line, fighterID: fighter?.id))
            lines.append(line)
        }

        if let fighter = engine.combatants.first(where: { $0.petID != nil }), let petID = fighter.petID,
           let pet = session.data.pets.first(where: { $0.id == petID }) {
            if fighter.hp <= 0 {
                // Fainted companions earn nothing and sit out until they're healed.
                lines.append(L("{name} needs rest: use a potion or visit a healer.", ["name": pet.name]))
            } else {
                let share = Int((Double(exp) * (session.heroClass.petExpShare ?? 0.5)).rounded())
                if session.gainPetEXP(petID, share) > 0, let updated = session.data.pets.first(where: { $0.id == petID }) {
                    let line = L("{name} grew to level {level}!", ["name": pet.name, "level": updated.level])
                    othersLevelled.append(LevelUp(name: pet.name, level: updated.level, line: line, fighterID: fighter.id))
                    lines.append(line)
                }
            }
        }

        lines += handOverSealed()

        if Double.random(in: 0..<1) < 0.25 {
            session.addItem("potion")
            loot["potion", default: 0] += 1
        }

        // Now and then a Homeward Feather for the way back to town; a boss always leaves one.
        let bossBeaten = engine.combatants.contains { $0.side == .enemies && $0.speciesID.flatMap { content.monster($0) }?.boss == true }
        if Double.random(in: 0..<1) < GameSession.featherDropChance(boss: bossBeaten),
           content.item(GameSession.featherID) != nil {
            session.addItem(GameSession.featherID)
            loot[GameSession.featherID, default: 0] += 1
        }

        // A hard fight (the strongest monster 5 or more levels over you, when the tougher theme
        // plays) or a boss now and then leaves a Seal Stone, a better one the harder it was.
        let wildFoes = engine.combatants.filter { foe in
            guard foe.side == .enemies, case .wild = foe.source else { return false }
            return true
        }
        if let toughest = wildFoes.map(\.level).max(),
           let seal = session.sealDrop(gap: toughest - levelBefore, boss: bossBeaten) {
            session.addItem(seal.id)
            loot[seal.id, default: 0] += 1
            lines.append(L("A hard-won {item}!", ["item": seal.name]))
        }

        // Materials for the blacksmith: about one wild monster in three drops something, bosses three.
        for foe in engine.combatants where foe.side == .enemies && !foe.isCaptured && !foe.hasFled {
            guard case .wild = foe.source, let id = foe.speciesID else { continue }
            let isBoss = content.monster(id)?.boss == true
            for _ in 0..<(isBoss ? 3 : 1) where isBoss || Double.random(in: 0..<1) < 0.35 {
                guard let material = session.materialDrop(level: foe.level) else { continue }
                session.addItem(material.id)
                loot[material.id, default: 0] += 1
            }
        }

        // Equipment: now and then a beaten monster drops gear from up to its own level, more often
        // the stronger it is next to you; a rare one often, a boss always. Two pieces at most a fight.
        // A boss rolls first: it stands behind two waves of followers, and their drops used to use up
        // the two before its turn came.
        var gearFound = 0
        let beaten = engine.combatants.filter { $0.side == .enemies && !$0.isCaptured && !$0.hasFled }
        let leads = { (foe: Combatant) in foe.speciesID.flatMap { content.monster($0) }?.boss == true }
        for foe in beaten.filter(leads) + beaten.filter({ !leads($0) }) {
            guard gearFound < 2 else { break }
            guard case .wild = foe.source, let id = foe.speciesID else { continue }
            let isBoss = content.monster(id)?.boss == true
            let chance = GameSession.equipmentDropChance(level: foe.level, heroLevel: session.data.hero.level,
                                                         rare: foe.isRare, boss: isBoss)
            guard Double.random(in: 0..<1) < chance,
                  let gear = session.equipmentDrop(level: foe.level, best: foe.isRare || isBoss) else { continue }
            session.addItem(gear.id)
            loot[gear.id, default: 0] += 1
            gearFound += 1
            lines.append(L("{name} dropped {item}!", ["name": foe.name, "item": gear.name]))
        }

        // Monster cards (Fairyland Online's card collection): now and then a beaten monster leaves
        // its card, a rare one or a boss more often.
        for foe in beaten {
            guard case .wild = foe.source, let id = foe.speciesID, let species = content.monster(id),
                  Double.random(in: 0..<1) < (DebugLaunch.dropsCards ? 1 : session.cardChance(for: species)) else { continue }
            let isNew = !session.hasCard(id)
            let line = session.findCard(of: species)
            if isNew {
                newCards.append(id)
                newCardLines.insert(line)
            }
            lines.append(line)
        }

        // Today's bounties, the Monster Book's milestones, and any title the win earned.
        let wildBeaten = beaten.compactMap { foe -> MonsterDef? in
            guard case .wild = foe.source else { return nil }
            return foe.speciesID.flatMap { content.monster($0) }
        }
        session.noteBounties(beaten: wildBeaten, sealed: sealedByYou.count, on: session.data.mapID)
        session.claimBookMilestones()
        session.checkTitles()
        session.save()
        return lines
    }

    /// Every monster you sealed in this fight joins you, however the fight ended: the stone holds it.
    /// With a full party the result screen asks who stays behind (`hasRoomToSeal` keeps it to one).
    /// One a friend sealed is their companion now, walking and fighting at their side.
    private func handOverSealed() -> [String] {
        var lines: [String] = []
        for captured in engine.combatants where captured.isCaptured {
            if case .ally(let friendID)? = captured.capturedBy.flatMap(engine.combatant)?.source {
                guard let id = captured.speciesID, let species = session.content.monster(id),
                      let index = session.data.friends?.firstIndex(where: { $0.id == friendID }),
                      let friend = session.data.friends?[index], friend.petSpecies == nil else { continue }
                session.data.friends?[index].petSpecies = id
                lines.append(L("{monster} is {name}'s companion now!", ["monster": species.name, "name": friend.name]))
                continue
            }
            guard let id = captured.speciesID, var pet = session.makePet(species: id, level: captured.level) else { continue }
            pet.hp = max(1, captured.hp)
            if session.addPet(pet) {
                lines.append(L("{name} joined your party!", ["name": pet.name]))
            } else {
                session.record(.capture, target: id)
                session.pendingPet = pet
                lines.append(L("{name} wants to join, but your party is full!", ["name": pet.name]))
            }
        }
        return lines
    }
}
