import SpriteKit

/// Background life on a map: adventurers (standing in for Fairyland's other players until there's
/// online play, and tagged BOT, some with a companion trotting behind), market traders about a
/// town's main square, villagers pottering around town, and the locals who live out on the maps
/// (`MapDef.Local`), each with a story they tell a line at a time as you stop by. They stroll, pause,
/// look around and chat now and then. They never block the way. Walk up to an adventurer to see
/// their card: befriend them, invite them along, trade, or (in danger zones) duel. Some adventurers
/// travel together, as you do with your party (crowd.json `groupChance`): one leads, the rest walk
/// behind in single file, their companions at their sides. Now and then one heads off on their own,
/// or joins a group near them with room (crowd.json `groupMinutes`). Ask whoever leads a group and
/// you can join it (`GameSession.askToJoin`): you walk at the back of their line as they lead you
/// about (`lead(you:)`).
final class Crowd {
    private final class Member {
        let name: String
        let kind: GameSession.ChatLine.Kind
        let walker: Walker
        let pet: Walker?
        var home: GridPoint
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
        /// A local: tells their lines in order (`nextLine`), starting as you come by.
        let story: Bool
        /// How many lines of their story they've told.
        var told = 0
        /// Whether they've started on their story since you came near.
        var noticed = false
        /// A local out on an errand: where they walk to and back home from, and whether they're on
        /// their way there.
        let route: GridPoint?
        var outward = true
        /// Which way a local likes to look while standing (out over the water).
        let facing: Direction?
        /// In a group of adventurers travelling together: the one walking ahead of them (nil for
        /// whoever leads, or someone on their own), their place in the line (0 leading), and
        /// whether anyone walks behind them.
        var ahead: Member?
        var place = 0
        var leads = false
        /// How much longer they keep to how they travel, alone or in a group, before they leave
        /// their group or join one near them (`mingle`).
        var mingle: TimeInterval = 0

        init(name: String, kind: GameSession.ChatLine.Kind, walker: Walker, pet: Walker?, home: GridPoint, roam: Int,
             lines: [String], profile: Adventurer? = nil, trades: Bool = false, story: Bool = false,
             route: GridPoint? = nil, facing: Direction? = nil) {
            self.profile = profile
            self.trades = trades
            self.story = story
            self.route = route
            self.facing = facing
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

        /// What they say next: a local the next line of their story (then from the start again),
        /// anyone else any of their lines.
        func nextLine() -> String? {
            guard story, !lines.isEmpty else { return lines.randomElement() }
            defer { told += 1 }
            return lines[told % lines.count]
        }
    }

    /// Someone who lives on the map (`MapDef.Local`), as the scene set them down: where they live and
    /// walk to, and their place in the map's list (which draws the parts of their look not given).
    struct Local {
        let def: MapDef.Local
        let index: Int
        let home: GridPoint
        let walk: GridPoint?
    }

    /// How near you come before a local starts on their story, in points.
    static let storyRange: CGFloat = 160

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
    /// Whoever leads the party you've joined, if it's here (`lead(you:)`).
    private var host: Member?
    /// How long anyone keeps to how they travel (`Member.mingle`), in seconds, and how many there
    /// can be in a group.
    private let mingleSpan: ClosedRange<TimeInterval>
    private let largestGroup: Int
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
    /// (`crowd.traders`) have, if it has any. `locals`: the map's own people, where the scene set them.
    /// `mingle`: how long anyone keeps to how they travel, in seconds (tests; crowd.json `groupMinutes`).
    init(def: MapDef, map: WorldMap, world: SKNode, heroLevel: Int = 1, friends: [Adventurer] = [], market: Market? = nil,
         locals: [Local] = [], mingle: ClosedRange<TimeInterval>? = nil) {
        self.map = map
        self.market = market
        let options = Content.shared.crowd
        let minutes = options.groupMinutes ?? [3, 10]
        let shortest = (minutes.first ?? 3) * 60
        mingleSpan = mingle ?? Self.mingleOverride ?? shortest...max(shortest, (minutes.last ?? 3) * 60)
        largestGroup = max(2, options.groupSize?.last ?? 2)
        let town = def.fence == true
        // In a town, about its square (its countryside round it is no place for a crowd).
        let spread = (town ? max(map.townSquare.width, map.townSquare.height) : max(map.columns, map.rows)) / 2
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
        let groupChance = Self.groupChanceOverride ?? options.groupChance ?? 0
        let fewest = max(1, options.groupSize?.first ?? 2)
        let sizes = fewest...max(fewest, options.groupSize?.last ?? fewest)
        let roam = town ? 9 : 14
        var left = count
        var slot = 0
        while left > 0 {
            defer { slot += 1 }
            left -= 1
            // In a town, every other one out in its countryside, roaming as widely as in the wild
            // (playtesting 2026-10-20: the land round a city stood empty).
            let outside = town && slot % 2 == 1
            let reach = outside ? 14 : roam
            guard let home = map.strollTarget(near: map.center, radius: outside ? max(map.columns, map.rows) / 2 : spread,
                                              using: &rng) else { continue }
            let profile = slot < visitors.count
                ? visitors[slot]
                : Self.profile(named: adventurerNames.popLast() ?? L("Traveller"), levels: levels, danger: def.danger == true, climate: def.climate)
            addAdventurer(profile, home: home, roam: reach, world: world)
            // Now and then a few travel together, as you do with your party: friends about the
            // leader's level, counted among the map's adventurers. Never troublemakers.
            guard slot >= visitors.count, !profile.hostile, left > 0, var ahead = members.last,
                  Double.random(in: 0..<1, using: &rng) < groupChance else { continue }
            let near = max(1, profile.level - 3)...(profile.level + 3)
            let size = Int.random(in: sizes, using: &rng)
            for place in 1..<max(1, min(size, left + 1)) {
                left -= 1
                addAdventurer(Self.profile(named: adventurerNames.popLast() ?? L("Traveller"), levels: near, danger: false, climate: def.climate),
                              home: home, roam: reach, world: world)
                guard let member = members.last else { break }
                member.ahead = ahead
                member.place = place
                ahead.leads = true
                // Quicker than whoever leads, so they keep up (as your friends do).
                member.walker.walkSpeed = 105
                ahead = member
            }
        }
        if let market, traders > 0 {
            placeTraders(traders, market: market, names: &adventurerNames, avoiding: def, world: world)
        }
        // Everyone's lines and the town's own, with its name and its healer's filled in.
        let healer = def.npcs?.first { $0.role == .healer }?.name
        let villagerLines = (options.villagerLines + (def.crowd?.villagerLines ?? []))
            .filter { healer != nil || !$0.contains("{healer}") }
            .map { $0.replacingOccurrences(of: "{town}", with: def.name).replacingOccurrences(of: "{healer}", with: healer ?? "") }
        for _ in 0..<(def.crowd?.villagers ?? 0) {
            guard let home = map.strollTarget(near: map.center, radius: spread, using: &rng) else { continue }
            let name = villagerNames.popLast() ?? L("Villager")
            let race = Content.shared.races.randomElement()?.id ?? "human"
            let walker = Self.person(name, art: GameSession.registerPerson(race: race, look: Self.randomLook(race: race)), color: .white)
            walker.walkSpeed = .random(in: 50...66)
            add(Member(name: name, kind: .villager, walker: walker, pet: nil, home: home, roam: 5, lines: villagerLines), to: world)
        }
        for local in locals { addLocal(local, on: def.id, world: world) }
    }

    /// How likely each friend is to be on a map you enter.
    static let friendVisitChance = 0.35

    /// Debug launches (`group`): how often adventurers travel together, in place of crowd.json's.
    static var groupChanceOverride: Double?
    /// Debug launches (`mingle=s`) and tests: how long anyone keeps to how they travel, in seconds,
    /// in place of crowd.json's `groupMinutes`.
    static var mingleOverride: ClosedRange<TimeInterval>?

    private func addAdventurer(_ profile: Adventurer, home: GridPoint, roam: Int, world: SKNode, trades: Bool = false) {
        let walker = Self.person(profile.name, art: GameSession.registerAdventurer(profile),
                                 color: profile.hostile ? Self.hostileColor : Self.adventurerColor, badge: .bot)
        // A weapon in hand for their class and level, like yours (`GameSession.weapon(for:)`).
        walker.setWeapon(GameSession.weapon(for: profile))
        walker.setTitle(GameSession.botTitle(level: profile.level, id: profile.id))
        walker.walkSpeed = .random(in: 72...92)
        // Their own level where a line has one ("Just hit level {level}"), and no such boast at level 1.
        let lines = Content.shared.crowd.adventurerLines
            .filter { profile.level > 1 || !$0.contains("{level}") }
            .map { $0.replacingOccurrences(of: "{level}", with: String(profile.level)) }
        add(Member(name: profile.name, kind: .adventurer, walker: walker, pet: Self.pet(profile.petSpecies), home: home, roam: roam,
                   lines: lines, profile: profile, trades: trades), to: world)
    }

    /// A monster trotting along behind someone (a monsters.json species), if they have one.
    private static func pet(_ species: String?) -> Walker? {
        guard let monster = species.flatMap(Content.shared.monster) else { return nil }
        let pet = Walker(cycle: ArtLibrary.shared.walkCycle(monster.art), label: nil)
        pet.walkSpeed = 110
        pet.motion = IdleMotion.of(art: monster.art)
        return pet
    }

    /// One of the map's own people, looking as their entry says, the rest of their look drawn from
    /// where they are in the map's list so they look the same on every visit (and in every language).
    private func addLocal(_ local: Local, on mapID: String, world: SKNode) {
        let content = Content.shared
        let def = local.def
        // Every part drawn whether it's given or not, so giving one leaves the others as they were.
        var draw = SeededRandom(text: "\(mapID)/local/\(local.index)")
        let options = content.appearance
        let race = content.races.randomElement(using: &draw)?.id
        let gender = options.genders.randomElement(using: &draw)?.id
        let hair = options.hair.randomElement(using: &draw)?.id
        let outfit = options.outfits.randomElement(using: &draw)?.id
        let skin = options.skin.randomElement(using: &draw)?.id
        let style = options.styles.randomElement(using: &draw)?.id
        let look = Look(hair: def.hair ?? hair ?? Look.standard.hair, outfit: def.outfit ?? outfit ?? Look.standard.outfit,
                        skin: def.skin ?? skin ?? Look.standard.skin, gender: def.gender ?? gender, style: def.style ?? style)
        // In the hat that goes with their armour too, as they looked when it was part of it.
        let armor = def.wear.flatMap(content.item)
        let art = GameSession.registerPerson(race: def.race ?? race ?? "human", look: look, armor: armor,
                                             worn: [armor?.headpiece.flatMap(content.item)].compactMap { $0 })
        let walker = Self.person(def.name, art: art, color: .white)
        walker.setWeapon(def.hold.flatMap(content.item))
        walker.walkSpeed = .random(in: 44...56, using: &draw)
        let facing = def.face.flatMap(Direction.init(rawValue:))
        add(Member(name: def.name, kind: .villager, walker: walker, pet: Self.pet(def.pet), home: local.home, roam: def.roam ?? 0,
                   lines: def.lines, story: true, route: local.walk, facing: facing), to: world)
        if let facing { walker.face(facing) }
    }

    /// Market traders about the main square: a step apart, clear of the middle where you arrive and
    /// of the townsfolk with jobs, each under a sign with something they're selling today.
    private func placeTraders(_ count: Int, market: Market, names: inout [String], avoiding def: MapDef, world: SKNode) {
        let middle = map.center(of: map.center)
        let townsfolk = (def.npcs ?? []).map { map.center(of: map.spot(of: $0)) }
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
            let profile = Self.profile(named: names.popLast() ?? L("Trader"), levels: levels, danger: false, climate: def.climate)
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
    /// (`companion(forLevel:climate:)`, at home in a land like `climate`). In danger zones some are
    /// troublemakers.
    private static func profile(named name: String, levels: ClosedRange<Int>, danger: Bool, climate: MapDef.Climate?) -> Adventurer {
        let content = Content.shared
        let level = Int.random(in: levels)
        let classID = level < content.classChoiceLevel ? "novice" : (content.classes.filter { $0.id != "novice" }.randomElement()?.id ?? "novice")
        let race = content.races.randomElement()?.id ?? "human"
        return Adventurer(name: name, raceID: race, classID: classID, level: level,
                          look: randomLook(race: race), petSpecies: Bool.random() ? companion(forLevel: level, climate: climate) : nil,
                          hostile: danger && Int.random(in: 0..<5) < 2, sealStones: Int.random(in: 0...3))
    }

    /// How far below an adventurer's level the wild monsters they might have caught live.
    static let companionReach = 30

    /// A companion for an adventurer of `level`: a monster they could have caught on the way, one
    /// that can be caught (no bosses) and roams the wild (maps.json encounters) where monsters
    /// start at most `companionReach` levels below theirs. A level-90 mage walks something from
    /// the snowy north, not a starter bunny. Where it can be, one at home in a land of `climate`,
    /// the land they roam's (playtesting 2026-10-16: a frost-maned lion walked the desert). The
    /// starter companions (crowd.json `companions`) fill in where nothing fits.
    static func companion(forLevel level: Int, climate: MapDef.Climate? = nil) -> String? {
        let content = Content.shared
        let near = content.maps.compactMap(\.encounters).filter { encounters in
            guard let lowest = encounters.levels.first else { return false }
            return lowest <= level && lowest >= level - companionReach
        }
        let catchable = Set(near.flatMap { $0.monsters.keys }).filter { id in
            guard let monster = content.monster(id) else { return false }
            return monster.captureRate > 0 && monster.boss != true
        }
        var homes: Set<String> = []
        for land in content.maps where land.climate == climate {
            if let monsters = land.encounters?.monsters { homes.formUnion(monsters.keys) }
        }
        let suited = catchable.filter { homes.contains($0) }
        if let pick = (suited.isEmpty ? catchable : suited).randomElement() { return pick }
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
        member.mingle = .random(in: mingleSpan, using: &rng)
        member.walker.position = map.center(of: member.home)
        member.walker.face(Direction.allCases.randomElement() ?? .down)
        // On a busy map they chat less often each, and traders less often still; the first lines
        // come spread over that, so the chat is lively from the start without a burst.
        member.chat = .random(in: 5...(45 * pace * (member.trades ? 2.5 : 1)))
        world.addChild(member.walker)
        member.walker.settle()
        if let pet = member.pet {
            pet.position = member.walker.position + CGVector(dx: -30, dy: 0)
            world.addChild(pet)
            pet.settle()
        }
        members.append(member)
    }

    // MARK: - Every frame

    func update(dt: TimeInterval, player: CGPoint) {
        self.player = player
        let standable: (CGPoint) -> Bool = { [map] in map.isWalkable(map.rawCell(at: $0)) }
        // A group is as near you as the nearest of them: their names show together, and they all
        // stop and turn to you as you walk up to any of them.
        var nearest: [ObjectIdentifier: CGFloat] = [:]
        for member in members where member.ahead != nil || member.leads {
            let key = ObjectIdentifier(Self.head(of: member))
            nearest[key] = min(nearest[key] ?? .infinity, member.walker.position.distance(to: player))
        }
        for member in members {
            let walker = member.walker
            let distance = walker.position.distance(to: player)
            let head = Self.head(of: member)
            let together = nearest[ObjectIdentifier(head)] ?? distance
            walker.isNear = together < Walker.nameRange
            // Adventurers and locals stop to chat when you walk up to them; not the party you've
            // joined, with you among them.
            let hosting = host != nil && head === host
            if !hosting, member.profile?.hostile == false || member.story, together < 90 {
                walker.path = []
                walker.face(Direction(player - walker.position, current: walker.facing))
                member.wait = max(member.wait, 1.5)
            }
            walker.markFootstep()
            if let ahead = member.ahead {
                // In line behind the one ahead, on the trail of whoever leads.
                walker.follow(ahead.walker, dt: dt, footstep: head.walker.footstep(behind: CGFloat(member.place) * 36), canStand: standable)
                if !hosting, together < 90 { walker.face(Direction(player - walker.position, current: walker.facing)) }
            } else if !walker.path.isEmpty {
                walker.followPath(dt: dt)
                walker.setWalking(true)
            } else {
                walker.setWalking(false)
                member.wait -= dt
                if member.wait <= 0 { decide(member) }
            }
            // A local starts on their story as you come by, and goes on while you stay about.
            if member.story {
                if distance < Self.storyRange, !member.noticed {
                    member.noticed = true
                    member.chat = min(member.chat, .random(in: 0.5...1.5))
                } else if distance > 420 {
                    member.noticed = false
                }
            }
            member.chat -= dt
            if member.chat <= 0 {
                member.chat = member.story ? .random(in: 9...14) : .random(in: 20...45) * pace * (member.trades ? 2.5 : 1)
                // Adventurers talk on the map channel; villagers only chat to those nearby, and locals
                // only once you've come by. Traders call out their deals.
                let near = distance < 420 && (member.noticed || !member.story)
                let deal = member.trades ? member.profile.flatMap { market?.shout($0) } : nil
                if near || member.kind == .adventurer, let line = deal ?? member.nextLine() {
                    speak(line, by: member, bubble: near)
                }
            }
            if let profile = member.profile, !profile.hostile, !member.trades {
                member.mingle -= dt
                if member.mingle <= 0 {
                    member.mingle = .random(in: mingleSpan, using: &rng)
                    mingle(member)
                }
            }
            if let profile = member.profile, profile.hostile {
                member.calm -= dt
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
                // In a group at their side, with the next of them walking behind (as your friends'
                // companions do); on their own, behind them.
                if member.ahead != nil || member.leads {
                    let behind = CGFloat(member.place) * 36 + 18
                    pet.follow(walker, dt: dt, footstep: head.walker.footstep(behind: behind), canStand: standable, beside: true)
                } else {
                    pet.follow(walker, dt: dt, footstep: walker.footstep(behind: 36), canStand: standable)
                }
                pet.zPosition = -pet.position.y
            }
        }
    }

    /// Whoever leads the group `member` walks in (them, if they lead or walk alone).
    private static func head(of member: Member) -> Member {
        var head = member
        while let ahead = head.ahead { head = ahead }
        return head
    }

    /// Takes someone out of their group (joining your party, or leaving after a duel): whoever
    /// walked behind them follows whoever was ahead of them, or leads the rest from where they
    /// stand, and the line closes up.
    private func leaveGroup(_ member: Member) {
        guard member.ahead != nil || member.leads else { return }
        for next in members where next.ahead === member {
            next.ahead = member.ahead
            if member.ahead == nil {
                next.home = map.cell(at: next.walker.position)
                next.walker.walkSpeed = .random(in: 72...92)
                next.wait = .random(in: 1...3)
            }
        }
        member.ahead = nil
        for someone in members {
            var place = 0
            var ahead = someone.ahead
            while let next = ahead {
                place += 1
                ahead = next.ahead
            }
            someone.place = place
            someone.leads = members.contains { $0.ahead === someone }
        }
    }

    /// The adventurers travelling together with the one `id`, them among them, whoever leads first
    /// and the rest in their places in line; just them on their own.
    func group(of id: UUID) -> [Adventurer] {
        guard let member = members.first(where: { $0.profile?.id == id }) else { return [] }
        guard member.ahead != nil || member.leads else { return member.profile.map { [$0] } ?? [] }
        let head = Self.head(of: member)
        return members.filter { Self.head(of: $0) === head }.sorted { $0.place < $1.place }.compactMap(\.profile)
    }

    /// How many travel together with the adventurer `id`, them among them: 1 on their own.
    func groupSize(of id: UUID) -> Int { max(1, group(of: id).count) }

    // MARK: - The party you've joined

    /// Takes you along in the group `leader` leads, the party you've joined
    /// (`GameSession.joinedParty`): at the back of their line, they no longer stop to face you, and
    /// whoever leads goes further afield each time instead of keeping near home. Returns whether
    /// they lead a group here.
    @discardableResult
    func lead(you leader: UUID) -> Bool {
        guard let member = members.first(where: { $0.profile?.id == leader }), member.ahead == nil, member.leads else { return false }
        host = member
        member.wait = min(member.wait, 1)
        return true
    }

    /// You've left the party you'd joined: they keep about where they've got to.
    func letYouGo() {
        guard let host else { return }
        host.home = map.cell(at: host.walker.position)
        self.host = nil
    }

    /// Who leads the party you've joined, if they're here (`lead(you:)`).
    var yourLeader: UUID? { host?.profile?.id }

    /// Where you walk in the party you've joined, on the trail of whoever leads it behind the last
    /// of them, and whether they're on the move; where whoever leads stands.
    var yourPlace: (spot: CGPoint, going: Bool, leader: CGPoint)? {
        guard let host else { return nil }
        let count = members.filter { Self.head(of: $0) === host }.count
        return (host.walker.footstep(behind: CGFloat(count) * 36), host.walker.isWalking, host.walker.position)
    }

    // MARK: - Coming and going

    /// What someone says as they leave their group, and as they join one.
    static var partings: [String] {
        [L("I'm heading off on my own. See you!"), L("Thanks for the company, everyone!"), L("I'll go my own way from here. Bye!")]
    }
    static var joinings: [String] {
        [L("Mind if I tag along?"), L("Room for one more?"), L("Hey, wait for me!")]
    }

    /// Someone's had a while travelling as they do (`Member.mingle`): one walking behind in a group
    /// heads off on their own; one on their own joins a group near them with room, of about their
    /// level, at the back of its line. Never the party you've joined, nor whoever leads a group.
    private func mingle(_ member: Member) {
        guard host == nil || Self.head(of: member) !== host else { return }
        let heard = member.walker.position.distance(to: player) < 420
        if member.ahead != nil {
            leaveGroup(member)
            member.home = map.cell(at: member.walker.position)
            member.walker.walkSpeed = .random(in: 72...92)
            member.wait = .random(in: 1...3)
            if let line = Self.partings.randomElement() { speak(line, by: member, bubble: heard) }
            return
        }
        guard !member.leads, let profile = member.profile else { return }
        let levels = max(1, profile.level - 5)...(profile.level + 5)
        var joining: (last: Member, distance: CGFloat)?
        for leader in members where leader.leads && leader.ahead == nil && leader !== host {
            guard let theirs = leader.profile, !theirs.hostile, levels.contains(theirs.level) else { continue }
            let distance = leader.walker.position.distance(to: member.walker.position)
            guard distance < 260, distance < (joining?.distance ?? .infinity) else { continue }
            let line = members.filter { Self.head(of: $0) === leader }
            guard line.count < largestGroup, let last = line.max(by: { $0.place < $1.place }) else { continue }
            joining = (last, distance)
        }
        guard let last = joining?.last else { return }
        member.ahead = last
        member.place = last.place + 1
        last.leads = true
        member.walker.path = []
        // Quicker than whoever leads, so they keep up (as your friends do).
        member.walker.walkSpeed = 105
        if let line = Self.joinings.randomElement() { speak(line, by: member, bubble: heard) }
    }

    /// Standing around is over: look about, or stroll somewhere near home (traders and locals who
    /// stand mind their spot; locals out on an errand go on to where they're going).
    private func decide(_ member: Member) {
        if member === host {
            // Leading you about: on somewhere further afield each time, from wherever they've got to.
            member.home = map.cell(at: member.walker.position)
            member.wait = .random(in: 1...3, using: &rng)
            guard let target = map.strollTarget(near: member.home, radius: member.roam * 2, using: &rng) else { return }
            let path = map.path(from: member.walker.position, to: map.center(of: target))
            if path.count <= member.roam * 6 { member.walker.path = path }
            return
        }
        if let route = member.route {
            let goal = member.outward ? route : member.home
            if member.walker.position.distance(to: map.center(of: goal)) < 30 {
                // There: a while to look about, then back the other way.
                let glance = Direction.allCases.randomElement(using: &rng) ?? .down
                member.outward.toggle()
                member.walker.face(member.facing ?? glance)
                member.wait = .random(in: 8...16, using: &rng)
            } else {
                member.walker.path = map.path(from: member.walker.position, to: map.center(of: goal))
                // Somewhere they can't get to: they stay put a good while rather than keep trying.
                member.wait = member.walker.path.isEmpty ? 30 : .random(in: 1...2, using: &rng)
            }
            return
        }
        if member.trades || member.roam == 0 || Int.random(in: 0..<3, using: &rng) == 0 {
            // A local standing at their spot mostly looks the way they like to.
            var look = Direction.allCases.randomElement(using: &rng) ?? .down
            if let facing = member.facing, Int.random(in: 0..<4, using: &rng) > 0 { look = facing }
            member.walker.face(look)
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
    /// over to stand around it, so they're near enough to befriend and invite. `count` 0 (`group`):
    /// the group travelling together nearest it instead, in line, whoever leads a few steps off.
    func summonForDebug(_ count: Int, to point: CGPoint) -> [Adventurer] {
        if count == 0 {
            let heads = members.filter { $0.leads && $0.ahead == nil }
            guard let head = heads.min(by: { $0.walker.position.distance(to: point) < $1.walker.position.distance(to: point) }) else { return [] }
            let group = members.filter { Self.head(of: $0) === head }.sorted { $0.place < $1.place }
            for member in group {
                let step = CGFloat(member.place)
                member.walker.path = []
                member.walker.position = point + CGVector(dx: 70 + step * 32, dy: 10 - step * 16)
                member.pet?.position = member.walker.position + CGVector(dx: 24, dy: 8)
            }
            head.walker.face(.left)
            head.wait = 600
            return group.compactMap(\.profile)
        }
        let chosen = members
            .filter { member in member.profile.map { !$0.hostile } == true }
            .sorted { $0.walker.position.distance(to: point) < $1.walker.position.distance(to: point) }
            .prefix(count)
        for member in chosen { leaveGroup(member) }
        for (index, member) in chosen.enumerated() {
            let angle = Double(index) * 2 * .pi / Double(max(1, chosen.count)) + 0.4
            member.walker.path = []
            member.walker.position = point + CGVector(dx: cos(angle) * 70, dy: sin(angle) * 45)
            member.pet?.position = member.walker.position + CGVector(dx: -26, dy: -6)
        }
        return chosen.compactMap(\.profile)
    }

    /// Debug launches (`local=n`): the local nearest `point` turns to it and starts on their story,
    /// the first line in a bubble that stays, for screenshots.
    func tellForDebug(near point: CGPoint) {
        guard let member = members.filter(\.story).min(by: { $0.walker.position.distance(to: point) < $1.walker.position.distance(to: point) })
        else { return }
        member.told = 0
        guard let line = member.nextLine() else { return }
        member.walker.path = []
        member.wait = 600
        member.chat = 600
        member.noticed = true
        member.walker.face(Direction(point - member.walker.position, current: member.walker.facing))
        member.walker.say(line, for: 600)
        onChat?(member.name, line, member.kind)
    }
    #endif

    /// The adventurer standing closest to `point`, if anyone is within reach: not one in the party
    /// you've joined, who you walk among (their card would never close).
    func adventurer(near point: CGPoint, within reach: CGFloat) -> Adventurer? {
        members
            .filter { host == nil || Self.head(of: $0) !== host }
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

    /// Where the folk who live here stand (villagers and locals), for the minimap.
    var folkPositions: [CGPoint] {
        members.filter { $0.profile == nil }.map(\.walker.position)
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
        guard let found = members.first(where: { $0.profile?.id == id }) else { return }
        if found === host { host = nil }
        leaveGroup(found)
        guard let index = members.firstIndex(where: { $0 === found }) else { return }
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
        let head = Self.head(of: member)
        for mate in members where Self.head(of: mate) === head { mate.walker.revealTag() }
        member.walker.face(Direction(player - member.walker.position, current: member.walker.facing))
        member.wait = 3
        member.chat = member.story ? .random(in: 9...14) : .random(in: 20...45)
        member.noticed = true
        if let line = member.nextLine() { speak(line, by: member, bubble: true) }
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
        // Long enough to read: a longer line stays up longer.
        if bubble { member.walker.say(line, for: max(3.5, Double(line.count) / 14)) }
        onChat?(member.name, line, member.kind)
    }
}
