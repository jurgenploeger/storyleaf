import SpriteKit

/// Background life on a map: adventurers (standing in for Fairyland's other players until there's
/// online play, and tagged BOT, some with a companion trotting behind), market traders about a
/// town's main square, and villagers pottering around town. They stroll, pause, look around and chat
/// now and then. They never block the way. Walk up to an adventurer to see their card: befriend
/// them, invite them along, trade, or (in danger zones) duel.
final class Crowd {
    private final class Member {
        let name: String
        let kind: GameSession.ChatLine.Kind
        let walker: Walker
        let pet: Walker?
        let home: GridPoint
        let roam: Int
        let lines: [String]
        /// Adventurers have a level, class and companion like you.
        let profile: Adventurer?
        /// A market trader: stays at their spot, and calls out their deals.
        let trades: Bool
        var wait: TimeInterval
        var chat: TimeInterval
        /// Hostile adventurers wait a while between picking fights.
        var calm: TimeInterval = 8

        init(name: String, kind: GameSession.ChatLine.Kind, walker: Walker, pet: Walker?, home: GridPoint, roam: Int,
             lines: [String], profile: Adventurer? = nil, trades: Bool = false) {
            self.profile = profile
            self.trades = trades
            self.name = name
            self.kind = kind
            self.walker = walker
            self.pet = pet
            self.home = home
            self.roam = roam
            self.lines = lines
            wait = .random(in: 0.5...4)
            chat = .random(in: 6...30)
        }
    }

    static let adventurerColor = UIColor(red: 0.62, green: 0.93, blue: 1, alpha: 1)
    static let hostileColor = UIColor(red: 1, green: 0.42, blue: 0.4, alpha: 1)

    /// What a town's market traders have: the sign over their heads and what they call out (their
    /// real deals of the day, `GameSession.marketSign` and `marketShout`), and the level their wares
    /// are around (yours, so they suit you).
    struct Market {
        let sign: (Adventurer) -> String?
        let shout: (Adventurer) -> String?
        let level: Int
    }

    /// Everything anyone says goes to the map's chat log.
    var onChat: ((String, String, GameSession.ChatLine.Kind) -> Void)?
    /// A red-named adventurer in a danger zone walks up and picks a fight.
    var onChallenge: ((Adventurer) -> Void)?
    /// Whether a troublemaker dares take you on (`GameSession.dares`): the weaker ones leave you be.
    var dares: ((Adventurer) -> Bool)?

    private let map: WorldMap
    private var members: [Member] = []
    private let replies = Content.shared.crowd.replies
    private var rng = SystemRandomNumberGenerator()
    private let market: Market?
    /// How much longer everyone waits between chats on a busy map, so the chat stays readable.
    private var pace: TimeInterval = 1
    /// Where you were last frame (for who's near enough to be heard).
    private var player = CGPoint.zero

    /// Friends you've made (and who aren't travelling with you) now and then turn up on a map with
    /// other adventurers about, if it suits their level, so you can meet them again and invite them.
    /// `heroLevel`: yours, which a town's adventurers are about. `market`: what the town's traders
    /// (`crowd.traders`) have, if it has any.
    init(def: MapDef, map: WorldMap, world: SKNode, heroLevel: Int = 1, friends: [Adventurer] = [], market: Market? = nil) {
        self.map = map
        self.market = market
        let options = Content.shared.crowd
        let town = def.fence == true
        let spread = max(map.columns, map.rows) / 2
        var adventurerNames = options.adventurerNames.shuffled()
        var villagerNames = options.villagerNames.shuffled()

        // Out in the wild adventurers suit the monsters; a town draws all sorts, about your level
        // (so they wear the armour of your stage of the game, and anyone you invite fits in).
        let levels = def.encounters.map { ($0.levels.first ?? 1)...(($0.levels.last ?? 1) + 3) }
            ?? max(1, heroLevel - 12)...max(8, heroLevel + 8)
        // Fewer computer-run adventurers as real players arrive (crowd.json `botDensity`).
        let density = max(0, options.botDensity ?? 1)
        let count = Int((Double(def.crowd?.adventurers ?? 0) * density).rounded())
        let traders = market == nil ? 0 : Int((Double(def.crowd?.traders ?? 0) * density).rounded())
        pace = max(1, Double(count + traders) / 8)
        // Towns welcome anyone; out in the wild, friends roam where the monsters suit them.
        let nearLevel = (levels.lowerBound - 10)...(levels.upperBound + 10)
        let visitors: [Adventurer] = count == 0 ? [] : Array(friends
            .filter { town || nearLevel.contains($0.level) }
            .filter { _ in Double.random(in: 0..<1) < Self.friendVisitChance }
            .shuffled()
            .prefix(min(2, count)))
        for index in 0..<count {
            guard let home = map.strollTarget(near: map.center, radius: spread, using: &rng) else { continue }
            let profile = index < visitors.count
                ? visitors[index]
                : Self.profile(named: adventurerNames.popLast() ?? L("Traveller"), levels: levels, danger: def.danger == true)
            addAdventurer(profile, home: home, roam: town ? 9 : 14, world: world)
        }
        if let market, traders > 0 {
            placeTraders(traders, market: market, names: &adventurerNames, avoiding: def, world: world)
        }
        for _ in 0..<(def.crowd?.villagers ?? 0) {
            guard let home = map.strollTarget(near: map.center, radius: spread, using: &rng) else { continue }
            let name = villagerNames.popLast() ?? L("Villager")
            let race = Content.shared.races.randomElement()?.id ?? "human"
            let walker = Self.person(name, art: GameSession.registerPerson(race: race, look: Self.randomLook(race: race)), color: .white)
            walker.walkSpeed = .random(in: 50...66)
            add(Member(name: name, kind: .villager, walker: walker, pet: nil, home: home, roam: 5, lines: options.villagerLines), to: world)
        }
    }

    /// How likely each friend is to be on a map you enter.
    static let friendVisitChance = 0.35

    private func addAdventurer(_ profile: Adventurer, home: GridPoint, roam: Int, world: SKNode, trades: Bool = false) {
        let walker = Self.person(profile.name, art: GameSession.registerAdventurer(profile),
                                 color: profile.hostile ? Self.hostileColor : Self.adventurerColor, badge: .bot)
        // A weapon in hand for their class and level, like yours (`GameSession.weapon(for:)`).
        walker.setGear(weapon: GameSession.weapon(for: profile), accessory: nil)
        walker.setTitle(GameSession.botTitle(level: profile.level, id: profile.id))
        walker.walkSpeed = .random(in: 72...92)
        var pet: Walker?
        if let species = profile.petSpecies.flatMap(Content.shared.monster) {
            pet = Walker(cycle: ArtLibrary.shared.walkCycle(species.art), label: nil)
            pet?.walkSpeed = 110
            pet?.motion = IdleMotion.of(art: species.art)
        }
        add(Member(name: profile.name, kind: .adventurer, walker: walker, pet: pet, home: home, roam: roam,
                   lines: Content.shared.crowd.adventurerLines, profile: profile, trades: trades), to: world)
    }

    /// Market traders about the main square: a step apart, clear of the middle where you arrive and
    /// of the townsfolk with jobs, each under a sign with something they're selling today.
    private func placeTraders(_ count: Int, market: Market, names: inout [String], avoiding def: MapDef, world: SKNode) {
        let middle = map.center(of: map.center)
        let townsfolk = (def.npcs ?? []).map { map.center(of: map.offset($0.x, $0.y)) }
        var spots: [CGPoint] = []
        for _ in 0..<(count * 20) where spots.count < count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let reach = Double.random(in: 0.3...1, using: &rng)
            let spot = middle + CGVector(dx: cos(angle) * 290 * reach, dy: sin(angle) * 160 * reach)
            guard map.isWalkable(map.rawCell(at: spot)), spot.distance(to: middle) > 70,
                  townsfolk.allSatisfy({ $0.distance(to: spot) > 56 }),
                  spots.allSatisfy({ $0.distance(to: spot) > 46 }) else { continue }
            spots.append(spot)
        }
        let levels = max(1, market.level - 6)...max(1, market.level + 10)
        for spot in spots {
            let profile = Self.profile(named: names.popLast() ?? L("Trader"), levels: levels, danger: false)
            addAdventurer(profile, home: map.cell(at: spot), roam: 0, world: world, trades: true)
            guard let member = members.last else { continue }
            member.walker.position = spot
            member.pet?.position = spot + CGVector(dx: -26, dy: -6)
            if let text = market.sign(profile) {
                let sign = Nodes.shopSign(text)
                sign.position = CGPoint(x: 0, y: member.walker.sprite.size.height + 24)
                sign.zPosition = 5_100
                member.walker.addChild(sign)
            }
        }
    }

    /// A friend who left your party stays on this map, strolling around where they stood.
    func rejoin(_ friend: Adventurer, at point: CGPoint, world: SKNode) {
        guard !members.contains(where: { $0.profile?.id == friend.id }) else { return }
        addAdventurer(friend, home: map.cell(at: point), roam: 9, world: world)
        if let member = members.last {
            member.walker.position = point
            member.pet?.position = point + CGVector(dx: -30, dy: 0)
        }
    }

    /// A random adventurer: level to suit the area, a class once they're past Novice (and armour
    /// to match, `GameSession.armor(for:)`), and often a companion to suit their level
    /// (`companion(forLevel:)`). In danger zones some are troublemakers.
    private static func profile(named name: String, levels: ClosedRange<Int>, danger: Bool) -> Adventurer {
        let content = Content.shared
        let level = Int.random(in: levels)
        let classID = level < content.classChoiceLevel ? "novice" : (content.classes.filter { $0.id != "novice" }.randomElement()?.id ?? "novice")
        let race = content.races.randomElement()?.id ?? "human"
        return Adventurer(name: name, raceID: race, classID: classID, level: level,
                          look: randomLook(race: race), petSpecies: Bool.random() ? companion(forLevel: level) : nil,
                          hostile: danger && Int.random(in: 0..<5) < 2)
    }

    /// How far below an adventurer's level the wild monsters they might have caught live.
    static let companionReach = 30

    /// A companion for an adventurer of `level`: a monster they could have caught on the way, one
    /// that can be caught (no bosses) and roams the wild (maps.json encounters) where monsters
    /// start at most `companionReach` levels below theirs. A level-90 mage walks something from
    /// the snowy north, not a starter bunny. The starter companions (crowd.json `companions`)
    /// fill in where nothing fits.
    static func companion(forLevel level: Int) -> String? {
        let content = Content.shared
        let near = content.maps.compactMap(\.encounters).filter { encounters in
            guard let lowest = encounters.levels.first else { return false }
            return lowest <= level && lowest >= level - companionReach
        }
        let catchable = Set(near.flatMap { $0.monsters.keys }).filter { id in
            guard let monster = content.monster(id) else { return false }
            return monster.captureRate > 0 && monster.boss != true
        }
        if let pick = catchable.randomElement() { return pick }
        return content.crowd.companions.compactMap { art in content.monsters.first { $0.art == art }?.id }.randomElement()
    }

    /// Colours, gender and a hairstyle that suits that race and gender's walk sheet.
    private static func randomLook(race raceID: String) -> Look {
        let options = Content.shared.appearance
        let gender = options.genders.randomElement()?.id
        let sheet = Content.shared.race(raceID).sheet(for: gender)
        return Look(hair: options.hair.randomElement()?.id ?? Look.standard.hair,
                    outfit: options.outfits.randomElement()?.id ?? Look.standard.outfit,
                    skin: options.skin.randomElement()?.id ?? Look.standard.skin,
                    gender: gender, style: options.styles(for: sheet).randomElement()?.id)
    }

    /// A walker for someone drawn like a customised hero (art from `GameSession.registerPerson`).
    private static func person(_ name: String, art id: String, color: UIColor, badge: PlayerBadge? = nil) -> Walker {
        let walker = Walker(cycle: ArtLibrary.shared.walkCycle(id), label: name, labelColor: color, badge: badge)
        walker.tagMode = .onDemand
        return walker
    }

    private func add(_ member: Member, to world: SKNode) {
        member.walker.position = map.center(of: member.home)
        member.walker.face(Direction.allCases.randomElement() ?? .down)
        // On a busy map they chat less often each, and traders less often still; the first lines
        // come spread over that, so the chat is lively from the start without a burst.
        member.chat = .random(in: 5...(45 * pace * (member.trades ? 2.5 : 1)))
        world.addChild(member.walker)
        if let pet = member.pet {
            pet.position = member.walker.position + CGVector(dx: -30, dy: 0)
            world.addChild(pet)
        }
        members.append(member)
    }

    // MARK: - Every frame

    func update(dt: TimeInterval, player: CGPoint) {
        self.player = player
        for member in members {
            let walker = member.walker
            walker.isNear = walker.position.distance(to: player) < Walker.nameRange
            // Adventurers stop to chat when you walk up to them.
            if member.profile?.hostile == false, walker.position.distance(to: player) < 90 {
                walker.path = []
                walker.face(Direction(player - walker.position, current: walker.facing))
                member.wait = max(member.wait, 1.5)
            }
            if !walker.path.isEmpty {
                walker.followPath(dt: dt)
                walker.setWalking(true)
            } else {
                walker.setWalking(false)
                member.wait -= dt
                if member.wait <= 0 { decide(member) }
            }
            member.chat -= dt
            if member.chat <= 0 {
                member.chat = .random(in: 20...45) * pace * (member.trades ? 2.5 : 1)
                // Adventurers talk on the map channel; villagers only chat to those nearby. Traders
                // call out their deals.
                let near = walker.position.distance(to: player) < 420
                let deal = member.trades ? member.profile.flatMap { market?.shout($0) } : nil
                if near || member.kind == .adventurer, let line = deal ?? member.lines.randomElement() {
                    speak(line, by: member, bubble: near)
                }
            }
            if let profile = member.profile, profile.hostile {
                member.calm -= dt
                let distance = walker.position.distance(to: player)
                if member.calm <= 0, distance < 170, dares?(profile) != false {
                    member.calm = 25
                    walker.path = []
                    walker.setWalking(false)
                    walker.face(Direction(player - walker.position, current: walker.facing))
                    speak([L("Hey! You there!"), L("Fight me!"), L("This is my turf!"), L("Let's see what you've got!")].randomElement() ?? L("Fight me!"),
                          by: member, bubble: true)
                    onChallenge?(profile)
                }
            }
            walker.zPosition = -walker.position.y
            if let pet = member.pet {
                walker.markFootstep()
                pet.follow(walker, dt: dt, footstep: walker.footstep(behind: 36)) { self.map.isWalkable(self.map.rawCell(at: $0)) }
                pet.zPosition = -pet.position.y
            }
        }
    }

    /// Standing around is over: look about, or stroll somewhere near home (traders mind their spot).
    private func decide(_ member: Member) {
        if member.trades || Int.random(in: 0..<3, using: &rng) == 0 {
            member.walker.face(Direction.allCases.randomElement(using: &rng) ?? .down)
            member.wait = .random(in: 1.5...3.5, using: &rng)
            return
        }
        member.wait = .random(in: 2...7, using: &rng)
        guard let target = map.strollTarget(near: member.home, radius: member.roam, using: &rng) else { return }
        let path = map.path(from: member.walker.position, to: map.center(of: target))
        // Skip long detours around ponds and fences; they'll pick somewhere else next time.
        if path.count <= member.roam * 3 { member.walker.path = path }
    }

    // MARK: - Meeting people

    #if DEBUG
    /// Debug launches (`invite=n`): the `count` friendly adventurers nearest `point` walk straight
    /// over to stand around it, so they're near enough to befriend and invite.
    func summonForDebug(_ count: Int, to point: CGPoint) -> [Adventurer] {
        let chosen = members
            .filter { member in member.profile.map { !$0.hostile } == true }
            .sorted { $0.walker.position.distance(to: point) < $1.walker.position.distance(to: point) }
            .prefix(count)
        for (index, member) in chosen.enumerated() {
            let angle = Double(index) * 2 * .pi / Double(max(1, chosen.count)) + 0.4
            member.walker.path = []
            member.walker.position = point + CGVector(dx: cos(angle) * 70, dy: sin(angle) * 45)
            member.pet?.position = member.walker.position + CGVector(dx: -26, dy: -6)
        }
        return chosen.compactMap(\.profile)
    }
    #endif

    /// The adventurer standing closest to `point`, if anyone is within reach.
    func adventurer(near point: CGPoint, within reach: CGFloat) -> Adventurer? {
        members
            .compactMap { member in member.profile.map { (profile: $0, distance: member.walker.position.distance(to: point)) } }
            .filter { $0.distance < reach }
            .min { $0.distance < $1.distance }?
            .profile
    }

    /// The adventurer you tapped (or their companion), if any.
    func adventurer(at point: CGPoint) -> Adventurer? {
        func hit(_ node: SKNode) -> Bool { (node.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 30 }
        return members.first { member in
            member.profile != nil && (hit(member.walker) || member.pet.map { hit($0) } == true)
        }?.profile
    }

    /// Every adventurer within reach of `point`.
    func adventurers(near point: CGPoint, within reach: CGFloat) -> Set<UUID> {
        Set(members.compactMap { member in
            member.walker.position.distance(to: point) < reach ? member.profile?.id : nil
        })
    }

    /// Every adventurer on the map and where they stand, for the minimap.
    var adventurerPositions: [(profile: Adventurer, position: CGPoint)] {
        members.compactMap { member in member.profile.map { ($0, member.walker.position) } }
    }

    func position(of id: UUID) -> CGPoint? {
        members.first { $0.profile?.id == id }?.walker.position
    }

    /// They left: joined your party, or ran off after a duel.
    func remove(_ id: UUID, poof: Bool) {
        guard let index = members.firstIndex(where: { $0.profile?.id == id }) else { return }
        let member = members.remove(at: index)
        for node in [member.walker, member.pet].compactMap({ $0 }) {
            if poof, let parent = node.parent { SkillEffects.smoke(at: node.position, in: parent) }
            node.run(.sequence([.fadeOut(withDuration: poof ? 0.3 : 0), .removeFromParent()]))
        }
    }

    func say(_ line: String, from id: UUID) {
        guard let member = members.first(where: { $0.profile?.id == id }) else { return }
        speak(line, by: member, bubble: true)
    }

    // MARK: - Tapping

    /// Tapping someone makes them turn to you and say something. Returns whether anyone was hit.
    @discardableResult
    func greet(at point: CGPoint, from player: CGPoint) -> Bool {
        guard let member = members.first(where: { ($0.walker.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 30 }) else {
            return false
        }
        member.walker.path = []
        member.walker.setWalking(false)
        member.walker.revealTag()
        member.walker.face(Direction(player - member.walker.position, current: member.walker.facing))
        member.wait = 3
        member.chat = .random(in: 20...45)
        if let line = member.lines.randomElement() { speak(line, by: member, bubble: true) }
        return true
    }

    /// After you say something, someone nearby (or on the map) may answer.
    func reply(near point: CGPoint) {
        guard Int.random(in: 0..<3, using: &rng) > 0 else { return }
        let nearby = members.filter { $0.walker.position.distance(to: point) < 420 }
        guard let member = (nearby.isEmpty ? members.filter { $0.kind == .adventurer } : nearby).randomElement(),
              let line = replies.randomElement() else { return }
        member.chat = .random(in: 20...45)
        let near = !nearby.isEmpty
        member.walker.run(.wait(forDuration: .random(in: 1.2...3))) { [weak self] in
            self?.speak(line, by: member, bubble: near)
        }
    }

    private func speak(_ line: String, by member: Member, bubble: Bool) {
        if bubble { member.walker.say(line) }
        onChat?(member.name, line, member.kind)
    }
}
