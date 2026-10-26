import Foundation

/// The game's own notices in the chat and the message log (content/announcements.json): dawn and
/// dusk, a word when you come to a map, news of other adventurers, and rare monster sightings that
/// really do make one turn up more often on a map for a while.
final class Announcer {
    private let session: GameSession
    private var options: AnnouncementOptions { Content.shared.announcements }
    private var content: Content { .shared }
    private var task: Task<Void, Never>?
    private var wasDaytime: Bool?
    /// The last map you were welcomed to, so waking up there again after fainting isn't news.
    private var welcomed: String?

    init(session: GameSession) {
        self.session = session
    }

    /// Checks the clock and any sighting every ten seconds, and now and then has some news.
    func start() {
        task?.cancel()
        task = Task { [weak self] in
            var next = Date().addingTimeInterval(self?.pause() ?? 180)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                self.checkTheClock()
                self.endSighting()
                if Date() >= next {
                    self.someNews()
                    next = Date().addingTimeInterval(self.pause())
                }
            }
        }
    }

    /// Real seconds until the next bit of news.
    private func pause() -> TimeInterval {
        let low = options.every.first ?? 120
        let high = max(low, options.every.last ?? low)
        return .random(in: low...high)
    }

    /// Dawn and dusk, when the calendar's hour turns 6 or 18 (not with night and day switched off).
    private func checkTheClock() {
        let daytime = GameClock.moment(since: session.data.startedAt).isDaytime
        let before = wasDaytime
        wasDaytime = daytime
        guard let before, before != daytime, GameSettings.dayAndNight,
              let line = (daytime ? options.dawn : options.dusk).randomElement() else { return }
        session.announce(line)
    }

    /// A word when you come to a map: what's on there, and any boss on it you've never beaten.
    func arrived(at map: MapDef) {
        guard map.id != welcomed else { return }
        welcomed = map.id
        if let line = options.arrival[map.id]?.randomElement() {
            session.announce(line)
        }
        if let boss = map.npcs?.first(where: { $0.role == .boss && !session.isDefeated($0) }),
           let line = options.bossNearby?.randomElement() {
            let name = boss.monster.flatMap { content.monster($0)?.name } ?? boss.name
            session.announce(line.replacingOccurrences(of: "{boss}", with: name).replacingOccurrences(of: "{map}", with: map.name))
        }
    }

    /// Now and then: a rare monster sighted somewhere, or what another adventurer has been up to.
    private func someNews() {
        if let sighting = options.sighting, session.sighting == nil, Double.random(in: 0..<1) < sighting.chance,
           startSighting(sighting) {
            return
        }
        community()
    }

    /// Every map's rare monsters, from the encounter tables.
    private var rareSpots: [(map: MapDef, monster: MonsterDef)] {
        var spots: [(map: MapDef, monster: MonsterDef)] = []
        for map in content.maps {
            for id in map.encounters?.monsters.keys.sorted() ?? [] {
                if let monster = content.monster(id), monster.rare == true { spots.append((map: map, monster: monster)) }
            }
        }
        return spots
    }

    /// A rare monster turns up far more often on one map for a while, near your level if one fits.
    @discardableResult
    private func startSighting(_ sighting: AnnouncementOptions.Sighting) -> Bool {
        let spots = rareSpots
        let level = session.data.hero.level
        let near = spots.filter { spot in
            guard let low = spot.map.encounters?.levels.first, let high = spot.map.encounters?.levels.last else { return false }
            return level >= low - 10 && level <= high + 10
        }
        guard let pick = (near.isEmpty ? spots : near).randomElement() else { return false }
        session.sighting = GameSession.Sighting(mapID: pick.map.id, monsterID: pick.monster.id, boost: max(1, sighting.boost),
                                                until: Date().addingTimeInterval(Double(sighting.minutes) * 60))
        session.announce(sighting.text
            .replacingOccurrences(of: "{monster}", with: pick.monster.name)
            .replacingOccurrences(of: "{map}", with: pick.map.name)
            .replacingOccurrences(of: "{minutes}", with: "\(sighting.minutes)"))
        return true
    }

    /// A sighting's time is up: the rare monster goes back into hiding.
    private func endSighting() {
        guard let current = session.sighting, current.until <= Date() else { return }
        session.sighting = nil
        guard let end = options.sighting?.end, let monster = content.monster(current.monsterID),
              let map = content.map(current.mapID) else { return }
        session.announce(end.replacingOccurrences(of: "{monster}", with: monster.name).replacingOccurrences(of: "{map}", with: map.name))
    }

    /// News of another adventurer: computer-run for now, and tagged BOT like on the map.
    private func community() {
        guard let line = options.community.randomElement() else { return }
        var text = line
            .replacingOccurrences(of: "{bot}", with: L("{name} [BOT]", ["name": content.crowd.adventurerNames.randomElement() ?? "Momo"]))
            .replacingOccurrences(of: "{level}", with: "\(Int.random(in: 10...150))")
        if text.contains("{boss}") {
            var bosses: [(map: MapDef, npc: NPCDef)] = []
            for map in content.maps {
                for npc in map.npcs ?? [] where npc.role == .boss { bosses.append((map: map, npc: npc)) }
            }
            guard let boss = bosses.randomElement() else { return }
            let name = boss.npc.monster.flatMap { content.monster($0)?.name } ?? boss.npc.name
            text = text.replacingOccurrences(of: "{boss}", with: name).replacingOccurrences(of: "{map}", with: boss.map.name)
        }
        if text.contains("{rare}") {
            guard let rare = rareSpots.randomElement() else { return }
            text = text.replacingOccurrences(of: "{rare}", with: rare.monster.name).replacingOccurrences(of: "{map}", with: rare.map.name)
        }
        if let weapon = content.items.filter({ $0.type == .weapon }).randomElement() {
            text = text.replacingOccurrences(of: "{item}", with: weapon.name)
        }
        if let map = content.maps.randomElement() {
            text = text.replacingOccurrences(of: "{map}", with: map.name)
        }
        guard !text.contains("{") else { return }
        session.announce(text)
    }

    /// Debug launches (`announce`): a sighting and news of another adventurer, so the chat shows them.
    func showOffForDebug() {
        if session.sighting == nil, let sighting = options.sighting { startSighting(sighting) }
        community()
    }
}
