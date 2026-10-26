import Foundation

/// Things to collect that make you stronger, after Fairyland Online's card collection and Pet Toys:
/// every monster's card for the Monster Book (content/rewards.json `cards`), and toys that raise a
/// companion's stats for good.
extension GameSession {
    // MARK: - Monster cards

    /// How many of a monster's cards you've found: one once it's in the Book (saves from before
    /// 0.7.20 counted the spares, sold as they turned up, too).
    func cards(of monsterID: String) -> Int { data.cards?[monsterID] ?? 0 }

    func hasCard(_ monsterID: String) -> Bool { cards(of: monsterID) > 0 }

    /// Kinds of monster card in the Book.
    var cardCount: Int { data.cards?.values.filter { $0 > 0 }.count ?? 0 }

    /// What a monster's card gives the hero for good: a stat for its element, more for a monster
    /// that lives among higher levels, twice that for a rare one and three times for a boss.
    func cardGain(of monster: MonsterDef) -> Stats {
        let rules = content.rewards.cards
        guard let gain = rules.gains[monster.element.rawValue] else { return .zero }
        let steps = 1 + content.cardLevel(monster.id) / max(1, rules.levelsPerStep)
        let worth = monster.boss == true ? rules.boss : monster.rare == true ? rules.rare : 1
        return Stats(named: gain.stat, max(1, Int(gain.perStep * Double(steps) * worth)))
    }

    /// Every card in the Book together.
    var cardBonus: Stats {
        guard let cards = data.cards, !cards.isEmpty else { return .zero }
        return content.monsters.filter { (cards[$0.id] ?? 0) > 0 }.map(cardGain(of:)).reduce(Stats.zero, +)
    }

    /// How likely a beaten monster is to leave its card.
    func cardChance(for monster: MonsterDef) -> Double {
        let rules = content.rewards.cards
        return monster.boss == true ? rules.bossChance : monster.rare == true ? rules.rareChance : rules.chance
    }

    /// A monster's card turns up, for the Book. Only one you haven't got: a monster whose card is in
    /// the Book leaves no other (playtesting 2026-10-16: spares were sold on the spot, and shouldn't
    /// come at all). Returns the line to show, or nil with its card already in the Book.
    @discardableResult
    func findCard(of monster: MonsterDef) -> String? {
        guard !hasCard(monster.id) else { return nil }
        var cards = data.cards ?? [:]
        cards[monster.id] = 1
        data.cards = cards
        return L("New card for your Monster Book: {monster}! {bonus} for good.",
                 ["monster": monster.name, "bonus": cardGain(of: monster).bonusSummary])
    }

    // MARK: - Companion toys

    /// Toys a companion can play with, each raising a stat for good. Ten of Fairyland Online's
    /// +5 toys make its 50 points.
    static let toysPerCompanion = 10

    /// Toys in the bag.
    var bagToys: [ItemDef] {
        content.items.filter { $0.toy == true && count(of: $0.id) > 0 }
    }

    /// Gives a companion a toy from the bag. Returns a message, or nil when it isn't a toy you have.
    @discardableResult
    func giveToy(_ id: String, to petID: UUID) -> String? {
        guard let item = content.item(id), item.toy == true, let raise = item.stats, count(of: id) > 0,
              let index = data.pets.firstIndex(where: { $0.id == petID }) else { return nil }
        let pet = data.pets[index]
        guard (pet.toys ?? 0) < Self.toysPerCompanion else {
            return L("{name} has all the toys it can play with.", ["name": pet.name])
        }
        removeItem(id)
        data.pets[index].toys = (pet.toys ?? 0) + 1
        data.pets[index].toyStats = (pet.toyStats ?? .zero) + raise
        // More HP and MP to fill, and a companion that's up gets them now; a fainted one waits for its healer.
        if pet.hp > 0 {
            data.pets[index].hp += raise.hp
            data.pets[index].mp += raise.mp
        }
        save()
        return L("{name} loves the {toy}! {bonus} for good.", ["name": pet.name, "toy": item.name, "bonus": raise.bonusSummary])
    }

    /// How many more toys a companion would play with.
    func toysWanted(by petID: UUID) -> Int {
        guard let pet = data.pets.first(where: { $0.id == petID }) else { return 0 }
        return max(0, Self.toysPerCompanion - (pet.toys ?? 0))
    }

    /// Gives a companion up to `times` of a toy, stopping once it has all it can play with or there's
    /// none left. How many were given, and a message.
    @discardableResult
    func giveToy(_ id: String, to petID: UUID, times: Int) -> (given: Int, note: String?) {
        var given = 0
        var note: String?
        while given < times, count(of: id) > 0 {
            let before = count(of: id)
            let result = giveToy(id, to: petID)
            guard count(of: id) < before else {
                if given == 0 { note = result }
                break
            }
            given += 1
            note = result
        }
        if given > 1, let item = content.item(id), let raise = item.stats,
           let pet = data.pets.first(where: { $0.id == petID }) {
            return (given, L("{name} loves the {toy} ×{count}! {bonus} for good.",
                             ["name": pet.name, "toy": item.name, "count": given, "bonus": (raise * given).bonusSummary]))
        }
        return (given, note)
    }
}
