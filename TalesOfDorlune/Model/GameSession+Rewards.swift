import Foundation

/// Reasons to come back: titles to earn and wear (content/titles.json), the Monster Book's
/// milestones, and a gift each day you play and the day's bounties (content/rewards.json).
extension GameSession {
    // MARK: - Titles

    /// How far along a title is: what you have, and what it takes.
    func titleProgress(_ title: TitleDef) -> (have: Int, need: Int) {
        let need = title.count ?? 1
        let have: Int
        switch title.kind {
        case .level: have = data.hero.level
        case .lands: return (have: content.maps.filter { hasVisited($0.id) }.count, need: title.count ?? content.maps.count)
        case .book: return (have: data.monsterBook?.count ?? 0, need: title.count ?? content.monsters.count)
        case .quests: have = completedQuests.count
        case .bosses: have = Set(data.defeatedBosses ?? []).count
        case .boss: return (have: title.target.map { data.defeatedBosses?.contains($0) == true ? 1 : 0 } ?? 0, need: 1)
        case .companions: have = data.pets.count
        case .friends: have = friends.count
        case .bounties: have = data.bountiesDone ?? 0
        case .days: have = data.giftDays ?? 0
        case .cards: return (have: cardCount, need: title.count ?? content.monsters.count)
        }
        return (have: have, need: need)
    }

    func hasEarned(_ title: TitleDef) -> Bool { data.titles?.contains(title.id) == true }

    /// The title worn over your name, if any.
    var wornTitle: TitleDef? { data.title.flatMap { content.title($0) } }

    /// Wears an earned title over your name (nil: none).
    func wear(_ title: TitleDef?) {
        if let title, !hasEarned(title) { return }
        data.title = title?.id
        save()
    }

    /// Earns every title whose goal is met, and says so. Earned titles stay earned. `quietly`: one
    /// line for the lot, without a fanfare (an older save earning what it already deserved).
    @discardableResult
    func checkTitles(quietly: Bool = false) -> [TitleDef] {
        // And the capes newly earned, which the weaver weaves.
        defer { tellOfCapes(quietly: quietly) }
        let new = content.titles.filter { title in
            guard !hasEarned(title) else { return false }
            let progress = titleProgress(title)
            return progress.have >= progress.need
        }
        guard !new.isEmpty else { return [] }
        data.titles = (data.titles ?? []) + new.map(\.id)
        if quietly, new.count > 1 {
            post(L("You've earned {count} titles! Wear one from Character → Titles.", ["count": new.count]), .reward)
        } else {
            for title in new {
                post(L("New title: {title}! Wear it from Character → Titles.", ["title": title.name]), .reward)
            }
        }
        if !quietly { SoundEffects.shared.play(.questDone) }
        return new
    }

    /// What a title takes, in words.
    func titleRequirement(_ title: TitleDef) -> String {
        let need = titleProgress(title).need
        return switch title.kind {
        case .level: L("Reach level {count}", ["count": need])
        case .lands: L("Set foot in {count} lands", ["count": need])
        case .book: L("Meet {count} kinds of monster", ["count": need])
        case .quests: L("Finish {count} quests", ["count": need])
        case .bosses: L("Beat {count} different bosses", ["count": need])
        case .boss: L("Beat {boss}", ["boss": title.target.flatMap { bossName($0) } ?? "?"])
        case .companions: L("Travel with {count} companions", ["count": need])
        case .friends: L("Make {count} friends", ["count": need])
        case .bounties: L("Finish {count} daily bounties", ["count": need])
        case .days: L("Collect the daily gift on {count} days", ["count": need])
        case .cards: L("Find {count} kinds of monster card", ["count": need])
        }
    }

    /// A boss by its NPC id, named as the monster it is.
    private func bossName(_ npcID: String) -> String? {
        guard let npc = content.npc(npcID) else { return nil }
        return npc.monster.flatMap { content.monster($0)?.name } ?? npc.name
    }

    /// A computer-run adventurer now and then wears a title that fits their level: the same one each
    /// time you meet them.
    static func botTitle(level: Int, id: UUID) -> TitleDef? {
        let fitting = Content.shared.titles.filter { $0.kind == .level && ($0.count ?? 1) <= level }
        guard let best = fitting.max(by: { ($0.count ?? 1) < ($1.count ?? 1) }) else { return nil }
        let coin = id.uuidString.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 7 }
        return coin < 3 ? best : nil
    }

    // MARK: - Status capes

    /// The capes the weaver weaves (rewards.json `prizes`), like RuneScape's capes for a skill at 99.
    var prizes: [RewardsDef.Prize] { content.rewards.prizes ?? [] }

    /// A land's monsters, as the Monster Book says where each lives: those in its wilds, and its bosses.
    func monsters(of landID: String) -> [String] {
        guard let land = content.map(landID) else { return [] }
        var ids = Set((land.encounters?.monsters ?? [:]).keys)
        for npc in land.npcs ?? [] where npc.role == .boss {
            if let monster = npc.monster { ids.insert(monster) }
        }
        return ids.sorted()
    }

    private func hasBeaten(_ monsterID: String) -> Bool { (data.monsterBook?[monsterID]?.defeated ?? 0) > 0 }

    /// How far along a cape is: what you have toward it, and what it takes.
    func prizeProgress(_ prize: RewardsDef.Prize) -> (have: Int, need: Int) {
        switch prize.kind {
        case .land:
            let species = prize.land.map { monsters(of: $0) } ?? []
            return (have: species.filter { hasBeaten($0) }.count, need: species.count)
        case .book:
            return (have: content.monsters.filter { hasBeaten($0.id) }.count, need: content.monsters.count)
        case .cards:
            return (have: cardCount, need: content.monsters.count)
        case .quests:
            return (have: completedQuests.count, need: content.quests.count)
        case .bosses:
            let bosses = Set(content.maps.flatMap { $0.npcs ?? [] }.filter { $0.role == .boss }.map(\.id))
            return (have: bosses.intersection(data.defeatedBosses ?? []).count, need: bosses.count)
        case .lands:
            return (have: content.maps.filter { hasVisited($0.id) }.count, need: content.maps.count)
        case .companion:
            // Your highest companion's level; once you've been told you earned it, it stays earned,
            // though that companion is let go.
            let need = prize.level ?? Self.levelCap
            if (data.capesTold ?? []).contains(prize.item) { return (have: need, need: need) }
            return (have: min(need, data.pets.map(\.level).max() ?? 0), need: need)
        case .capes:
            let others = prizes.filter { $0.kind != .capes }
            return (have: others.filter { hasEarned($0) }.count, need: others.count)
        }
    }

    func hasEarned(_ prize: RewardsDef.Prize) -> Bool {
        let progress = prizeProgress(prize)
        return progress.need > 0 && progress.have >= progress.need
    }

    /// Whether you have a cape, in the bag, on or in the bank (playtesting 2026-10-25: banked, the
    /// weaver wove them all again).
    func hasCape(_ prize: RewardsDef.Prize) -> Bool {
        count(of: prize.item) > 0 || data.hero.equipment.cape == prize.item || banked(prize.item) > 0
    }

    /// The capes you've earned and don't have (or no longer have): the weaver weaves them for you.
    var capesWaiting: [RewardsDef.Prize] { prizes.filter { hasEarned($0) && !hasCape($0) } }

    /// The weaver weaves you a cape you've earned.
    @discardableResult
    func takeCape(_ prize: RewardsDef.Prize) -> Bool {
        guard hasEarned(prize), !hasCape(prize), let item = content.item(prize.item) else { return false }
        // Woven only into a bag with room: it waits for you otherwise.
        guard hasRoom(for: [item.id]) else {
            post(L("Your bag is full. Put something in the bank first."), .system)
            return false
        }
        addItem(item.id)
        capeReady = !capesWaiting.isEmpty
        post(L("Received {items}.", ["items": item.name]), .reward)
        SoundEffects.shared.play(.questDone)
        save()
        return true
    }

    /// What a cape takes, in words.
    func prizeRequirement(_ prize: RewardsDef.Prize) -> String {
        switch prize.kind {
        case .land: L("Beat every monster in {land}", ["land": prize.land.flatMap { content.map($0)?.name } ?? "?"])
        case .book: L("Beat every kind of monster")
        case .cards: L("Find every monster card")
        case .quests: L("Finish every quest")
        case .bosses: L("Beat every boss")
        case .lands: L("Set foot in every land")
        case .companion: L("Raise a companion to level {level}", ["level": prize.level ?? Self.levelCap])
        case .capes: L("Earn every other cape")
        }
    }

    /// The weaver who weaves the capes, and the land she's in.
    var weaver: (npc: NPCDef, land: MapDef)? {
        for land in content.maps {
            if let npc = land.npcs?.first(where: { $0.role == .weaver }) { return (npc, land) }
        }
        return nil
    }

    /// Tells you of each cape you've newly earned, once: who weaves it, and where. `quietly`: one
    /// line for the lot (an older save that had already earned some).
    func tellOfCapes(quietly: Bool = false) {
        capeReady = !capesWaiting.isEmpty
        let told = Set(data.capesTold ?? [])
        let new = prizes.filter { !told.contains($0.item) && hasEarned($0) }
        guard !new.isEmpty, let weaver else { return }
        data.capesTold = (data.capesTold ?? []) + new.map(\.item)
        if quietly, new.count > 1 {
            post(L("You've earned {count} capes! {weaver} in {town} will weave them for you.",
                   ["count": new.count, "weaver": weaver.npc.name, "town": weaver.land.name]), .reward)
            return
        }
        for prize in new {
            guard let cape = content.item(prize.item) else { continue }
            post(L("You've earned the {cape}! {weaver} in {town} will weave it for you.",
                   ["cape": cape.name, "weaver": weaver.npc.name, "town": weaver.land.name]), .reward)
        }
    }

    // MARK: - The Monster Book's milestones

    /// The Book's rewards, each with how many kinds of monster it takes, fewest first.
    var bookMilestones: [(count: Int, reward: RewardsDef.Milestone)] {
        content.rewards.bookMilestones
            .map { (count: $0.count ?? content.monsters.count, reward: $0) }
            .sorted { $0.count < $1.count }
    }

    /// The next reward ahead (the Book's header); nil once they're all paid.
    var nextBookMilestone: (count: Int, reward: RewardsDef.Milestone)? {
        bookMilestones.first { !(data.bookRewards ?? []).contains($0.count) }
    }

    /// Pays every milestone reached and not yet paid.
    func claimBookMilestones() {
        let met = data.monsterBook?.count ?? 0
        for milestone in bookMilestones where met >= milestone.count && !(data.bookRewards ?? []).contains(milestone.count) {
            data.bookRewards = (data.bookRewards ?? []) + [milestone.count]
            gainGold(milestone.reward.gold)
            let got = (milestone.reward.items ?? []).filter { addItem($0) }
            post(L("Monster Book: {count} kinds of monster met! +{gold} gold", ["count": milestone.count, "gold": milestone.reward.gold]), .reward)
            if let list = itemList(got) {
                post(L("Received {items}.", ["items": list]), .reward)
            }
            SoundEffects.shared.play(.chest)
        }
    }

    /// "3 Seal Stones and Hi-Potion": items to read out, nil for none.
    func itemList(_ ids: [String]) -> String? {
        var unique: [String] = []
        for id in ids where !unique.contains(id) { unique.append(id) }
        let names = unique.map { id -> String in
            let name = content.item(id)?.name ?? id
            let count = ids.filter { $0 == id }.count
            return count > 1 ? L("{count} {item}s", ["count": count, "item": name]) : name
        }
        guard let last = names.last else { return nil }
        return names.count > 1 ? L("{names} and {last}", ["names": names.dropLast().joined(separator: ", "), "last": last]) : last
    }

    // MARK: - The daily gift

    /// A day on the phone's calendar, as saved ("2026-10-06").
    static func dayKey(_ date: Date = Date()) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// What a day's gift held.
    struct DailyGift: Equatable {
        /// Its place in the round, from 1, of `days`.
        let day: Int
        let days: Int
        let gold: Int
        let items: [String]
        /// A festive season's greeting, the first gift of the season (its hat is in `items`).
        var greeting: String? = nil
    }

    /// The place in the round of the next gift, from 1.
    var nextGiftDay: Int { (data.giftDays ?? 0) % max(1, content.rewards.dailyGifts.count) + 1 }

    /// Whether today's gift has been given.
    func hasCollectedGift(on date: Date = GameSession.today) -> Bool { data.giftDay == Self.dayKey(date) }

    /// Gives the day's gift, once a calendar day: the next in the round each day you play (missing
    /// a day costs nothing), and the first day of a festive season, one of its hats too
    /// (`seasonGift`). Nil when today's was given already.
    @discardableResult
    func collectDailyGift(on date: Date = GameSession.today) -> DailyGift? {
        let gifts = content.rewards.dailyGifts
        guard !gifts.isEmpty, !hasCollectedGift(on: date) else { return nil }
        let place = (data.giftDays ?? 0) % gifts.count
        let gift = gifts[place]
        let gold = (gift.goldPerLevel ?? 0) * data.hero.level
        // What doesn't fit in the bag is left behind.
        let paid = gainGold(gold) ? gold : 0
        var items = (gift.items ?? []).filter { addItem($0) }
        let festive = seasonGift(on: date)
        if let festive { items.append(festive.hat) }
        data.giftDay = Self.dayKey(date)
        data.giftDays = (data.giftDays ?? 0) + 1
        SoundEffects.shared.play(.chest)
        checkTitles()
        save()
        return DailyGift(day: place + 1, days: gifts.count, gold: paid, items: items, greeting: festive?.greeting)
    }

    // MARK: - Festive seasons

    /// Today: the phone's, or the day a debug launch says it is (`date=`).
    static var today: Date { DebugLaunch.today ?? Date() }

    /// Easter Sunday in the Gregorian calendar, by the anonymous algorithm (tools/check_content.py
    /// `easter_sunday` is the same): its month and day in `year`.
    static func easter(year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// The festive season on `date` (rewards.json `seasons`), if one is on, with the key its gift is
    /// saved under: its id and the year it began ("party-2026" on New Year's Day 2027). Counted on
    /// the Gregorian calendar, whatever the phone's.
    static func season(on date: Date = GameSession.today) -> (season: RewardsDef.Season, key: String)? {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let today = month * 100 + day
        /// "10-31" as 1031.
        func monthDay(_ text: String?) -> Int? {
            let numbers = (text ?? "").split(separator: "-").compactMap { Int($0) }
            return numbers.count == 2 ? numbers[0] * 100 + numbers[1] : nil
        }
        for festive in Content.shared.rewards.seasons ?? [] {
            if let around = festive.easter, around.count == 2 {
                let sunday = easter(year: year)
                guard let easterDay = calendar.date(from: DateComponents(year: year, month: sunday.month, day: sunday.day)),
                      let thisDay = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                      let offset = calendar.dateComponents([.day], from: easterDay, to: thisDay).day else { continue }
                if around[0] <= offset, offset <= around[1] { return (festive, "\(festive.id)-\(year)") }
            } else if let start = monthDay(festive.from), let end = monthDay(festive.to) {
                let on = start <= end ? (start...end).contains(today) : (today >= start || today <= end)
                // Round the new year, one that's on in January began the year before.
                if on { return (festive, "\(festive.id)-\(start > end && today <= end ? year - 1 : year)") }
            }
        }
        return nil
    }

    /// Whether the hero has the item, in the bag, on or in the bank.
    func owns(_ id: String) -> Bool {
        count(of: id) > 0 || ItemType.equipmentSlots.contains { data.hero.equipment[$0] == id } || banked(id) > 0
    }

    /// The festive season's gift, once a season (`seasonGifts`): one of its hats, one you haven't
    /// got if there's one, and its greeting. Nil when no season's on or its gift was given.
    private func seasonGift(on date: Date) -> (hat: String, greeting: String)? {
        guard let festive = Self.season(on: date), !(data.seasonGifts ?? []).contains(festive.key) else { return nil }
        let missing = festive.season.hats.filter { !owns($0) }
        guard let hat = (missing.isEmpty ? festive.season.hats : missing).randomElement() else { return nil }
        // Not into a full bag: the season's gift waits for a day with room.
        guard hasRoom(for: [hat]) else { return nil }
        addItem(hat)
        data.seasonGifts = (data.seasonGifts ?? []) + [festive.key]
        return (hat, festive.season.greeting)
    }

    /// What a won fight leaves in a festive season, if anything: one of its treats `chance` of the
    /// time, one of its hats instead `hatChance` of those.
    func seasonDrop(on date: Date = GameSession.today) -> ItemDef? {
        guard let festive = Self.season(on: date)?.season, Double.random(in: 0..<1) < festive.chance else { return nil }
        let pool = Double.random(in: 0..<1) < festive.hatChance ? festive.hats : festive.treats
        return pool.randomElement().flatMap(content.item)
    }

    // MARK: - Daily bounties

    /// Today's board: a new one each calendar day. Yesterday's finished bounties left unclaimed are
    /// paid as the day turns, so nothing earned is lost.
    @discardableResult
    func refreshBounties(on date: Date = Date()) -> BountyBoard {
        let today = Self.dayKey(date)
        if let board = data.bounties, board.day == today { return board }
        if let old = data.bounties {
            for index in old.bounties.indices where old.bounties[index].isDone && !old.bounties[index].claimed {
                claimBounty(index)
            }
            if canClaimBountyBonus { claimBountyBonus() }
        }
        let board = BountyBoard(day: today, bounties: makeBounties(seed: "\(today)|\(data.slot ?? "")"))
        data.bounties = board
        return board
    }

    /// Lands you've been to whose monsters suit your level: where the day's hunting is. With none
    /// quite right, the nearest to your level.
    func huntingGrounds(level: Int) -> [MapDef] {
        let wild = content.maps.filter { $0.encounters != nil && hasVisited($0.id) }
        func distance(_ map: MapDef) -> Int {
            let levels = map.encounters?.levels ?? []
            let middle = ((levels.first ?? 0) + (levels.last ?? 0)) / 2
            return abs(middle - level)
        }
        let suited = wild.filter { map in
            guard let levels = map.encounters?.levels, let low = levels.first, let high = levels.last else { return false }
            return low <= level + 2 && high >= level - 6
        }
        if !suited.isEmpty { return suited }
        return wild.min { distance($0) < distance($1) }.map { [$0] } ?? []
    }

    /// The day's bounties, the same all day (`seed`: the day and this game's slot).
    private func makeBounties(seed: String) -> [Bounty] {
        let rules = content.rewards.bounties
        var rng = SeededRandom(text: seed)
        let level = data.hero.level
        let exp = max(1, Int((Double(Self.expToNext(level: level)) * rules.exp).rounded()))
        let gold = rules.goldPerLevel * level
        let grounds = huntingGrounds(level: level).sorted { $0.id < $1.id }
        var species: [String] = []
        for map in grounds { species += map.encounters.map { Array($0.monsters.keys) } ?? [] }
        let elements = Set(species.compactMap { content.monster($0)?.element }).subtracting([.neutral]).map(\.rawValue).sorted()
        var kinds = Bounty.Kind.allCases.filter { rules.kinds[$0.rawValue] != nil }
        if grounds.isEmpty { kinds.removeAll { $0 == .defeatOnMap } }
        if elements.isEmpty { kinds.removeAll { $0 == .defeatElement } }
        kinds.shuffle(using: &rng)
        var bounties: [Bounty] = []
        for kind in kinds.prefix(max(0, rules.perDay)) {
            let range = rules.kinds[kind.rawValue] ?? [1]
            let low = max(1, range.first ?? 1)
            let count = Int.random(in: low...max(low, range.last ?? low), using: &rng)
            let target: String? = switch kind {
            case .defeatOnMap: grounds.randomElement(using: &rng)?.id
            case .defeatElement: elements.randomElement(using: &rng)
            case .wins, .rare, .seal: nil
            }
            bounties.append(Bounty(kind: kind, target: target, count: count, exp: exp, gold: gold))
        }
        return bounties
    }

    /// A won fight counts toward today's bounties: the monsters beaten, how many were sealed, and
    /// where it was.
    func noteBounties(beaten: [MonsterDef], sealed: Int, on mapID: String) {
        refreshBounties()
        guard var board = data.bounties else { return }
        var finished: [Bounty] = []
        for index in board.bounties.indices where !board.bounties[index].isDone {
            let bounty = board.bounties[index]
            let gained: Int = switch bounty.type {
            case .defeatOnMap?: bounty.target == mapID ? beaten.count : 0
            case .defeatElement?: beaten.filter { $0.element.rawValue == bounty.target }.count
            case .wins?: 1
            case .rare?: beaten.filter { $0.rare == true }.count
            case .seal?: sealed
            case nil: 0
            }
            board.bounties[index].progress = min(bounty.count, bounty.progress + gained)
            if board.bounties[index].isDone { finished.append(board.bounties[index]) }
        }
        data.bounties = board
        for bounty in finished {
            post(L("Bounty done: {bounty}. Claim it in Quests!", ["bounty": describe(bounty)]), .quest)
        }
    }

    /// What a bounty asks, in words.
    func describe(_ bounty: Bounty) -> String {
        switch bounty.type {
        case .defeatOnMap?:
            L("Defeat {count} monsters in {map}", ["count": bounty.count, "map": bounty.target.flatMap { content.map($0)?.name } ?? "?"])
        case .defeatElement?:
            L("Defeat {count} {element} monsters", ["count": bounty.count, "element": bounty.target.flatMap(Element.init(rawValue:))?.displayName ?? "?"])
        case .wins?:
            L("Win {count} fights", ["count": bounty.count])
        case .rare?:
            bounty.count == 1 ? L("Defeat a rare monster") : L("Defeat {count} rare monsters", ["count": bounty.count])
        case .seal?:
            bounty.count == 1 ? L("Seal a monster with a Seal Stone") : L("Seal {count} monsters with Seal Stones", ["count": bounty.count])
        case nil:
            L("An old bounty")
        }
    }

    /// Pays a finished bounty. Returns what it paid.
    @discardableResult
    func claimBounty(_ index: Int) -> [String] {
        guard var board = data.bounties, board.bounties.indices.contains(index) else { return [] }
        let bounty = board.bounties[index]
        guard bounty.isDone, !bounty.claimed else { return [] }
        board.bounties[index].claimed = true
        data.bounties = board
        data.bountiesDone = (data.bountiesDone ?? 0) + 1
        var lines = gainGold(bounty.gold) ? [L("+{gold} gold", ["gold": bounty.gold])] : []
        lines.append(L("+{exp} EXP", ["exp": bounty.exp]))
        if gainHeroEXP(bounty.exp) > 0 { lines.append(L("Level up! You're now level {level}.", ["level": data.hero.level])) }
        SoundEffects.shared.play(.coins)
        checkTitles()
        save()
        return lines
    }

    /// All of today's bounties claimed, and their bonus not yet.
    var canClaimBountyBonus: Bool {
        guard let board = data.bounties, !board.bonusClaimed, !board.bounties.isEmpty else { return false }
        return board.bounties.allSatisfy(\.claimed)
    }

    /// The bonus for claiming all of a day's bounties. Returns what it paid.
    @discardableResult
    func claimBountyBonus() -> [String] {
        guard canClaimBountyBonus, var board = data.bounties else { return [] }
        board.bonusClaimed = true
        data.bounties = board
        let bonus = content.rewards.bounties.bonus
        let exp = max(1, Int((Double(Self.expToNext(level: data.hero.level)) * bonus.exp).rounded()))
        var lines = [L("+{exp} EXP", ["exp": exp])]
        if gainHeroEXP(exp) > 0 { lines.append(L("Level up! You're now level {level}.", ["level": data.hero.level])) }
        for id in bonus.items ?? [] where addItem(id) {
            lines.append(L("Got {item}", ["item": content.item(id)?.name ?? id]))
        }
        SoundEffects.shared.play(.questDone)
        save()
        return lines
    }
}

// MARK: - Seal Stones from hard fights

extension GameSession {
    /// The rule a won fight's Seal Stone is rolled on (content/rewards.json `seals`): a boss fight's,
    /// or the highest tier whose `above` the strongest monster stood over your level (`gap`). None
    /// in an ordinary fight.
    func sealRule(gap: Int, boss: Bool) -> RewardsDef.Seals.Rule? {
        let seals = content.rewards.seals
        if boss { return seals.boss }
        return seals.tiers.filter { gap >= $0.above }.max { $0.above < $1.above }
    }

    /// The Seal Stone a hard win leaves, if any: rolled on `sealRule`.
    func sealDrop(gap: Int, boss: Bool) -> ItemDef? {
        guard let rule = sealRule(gap: gap, boss: boss), Double.random(in: 0..<1) < rule.chance,
              let id = rule.items.randomElement() else { return nil }
        return content.item(id)
    }
}
