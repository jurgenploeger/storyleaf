import Foundation

/// The bag's room and the bank (playtesting 2026-10-25: "I want to add a bank to the game [...] so the
/// item limit is 50 items you can hold"). The bag holds 50 slots, RuneScape-style: each kind of item
/// one slot however many you carry, the coins one more. What doesn't fit is left behind (`addItem`,
/// `gainGold`). The bank, at a banker in each town and in Glimmerbough, holds everything else, coins too,
/// and nothing there is ever lost. What you carry is: beaten by monsters you lose the bag (coins and all),
/// beaten in a duel your gear too (`loseBelongings`), left where you fell for a while
/// (`GameSession+LostPiles`); what a quest you're on needs stays with you.
extension GameSession {
    static let bagSlots = 50

    /// Slots the bag's things take: each kind of item one, however many; the coins one.
    var bagSlotsUsed: Int { data.inventory.values.filter { $0 > 0 }.count + (data.gold > 0 ? 1 : 0) }
    var bagSlotsFree: Int { max(0, Self.bagSlots - bagSlotsUsed) }

    /// Whether these would fit in the bag: a kind you carry already stacks on it, a new one takes a slot.
    func hasRoom(for ids: [String], gold: Int = 0) -> Bool {
        let new = Set(ids).filter { count(of: $0) == 0 }.count + (gold > 0 && data.gold == 0 ? 1 : 0)
        return new <= bagSlotsFree
    }

    /// Coins into the bag, if there's a slot for them (or coins there already). False, and a note,
    /// when the bag is full: they're left behind.
    @discardableResult
    func gainGold(_ amount: Int) -> Bool {
        guard amount > 0 else { return true }
        guard data.gold > 0 || bagSlotsFree > 0 else {
            post(L("Your bag is full: {gold} gold left behind.", ["gold": amount]), .reward)
            return false
        }
        data.gold += amount
        return true
    }

    // MARK: - The bank

    var bank: [String: Int] { data.bank ?? [:] }
    var bankGold: Int { data.bankGold ?? 0 }
    func banked(_ id: String) -> Int { bank[id] ?? 0 }

    /// What the bank holds, in the game's order of items.
    var bankItems: [ItemDef] { content.items.filter { banked($0.id) > 0 } }

    /// Puts all of a kind you carry in the bank.
    func deposit(_ id: String) {
        let amount = count(of: id)
        guard amount > 0 else { return }
        data.inventory[id] = nil
        data.bank = bank.merging([id: amount]) { $0 + $1 }
        SoundEffects.shared.play(.equip)
    }

    /// Everything you carry into the bank, coins too (RuneScape's "Deposit all").
    func depositAll() {
        for id in data.inventory.keys { deposit(id) }
        depositGold(data.gold)
    }

    /// Takes all of a kind out of the bank, if the bag has room for it. False when it hasn't.
    @discardableResult
    func withdraw(_ id: String) -> Bool {
        let amount = banked(id)
        guard amount > 0 else { return false }
        guard hasRoom(for: [id]) else {
            post(L("Your bag is full. Put something in the bank first."), .system)
            return false
        }
        data.bank?[id] = nil
        data.inventory[id, default: 0] += amount
        SoundEffects.shared.play(.equip)
        return true
    }

    func depositGold(_ amount: Int) {
        let amount = min(amount, data.gold)
        guard amount > 0 else { return }
        data.gold -= amount
        data.bankGold = bankGold + amount
        SoundEffects.shared.play(.coins)
    }

    /// Takes coins out of the bank, if the bag has a slot for them. False when it hasn't.
    @discardableResult
    func withdrawGold(_ amount: Int) -> Bool {
        let amount = min(amount, bankGold)
        guard amount > 0 else { return false }
        guard hasRoom(for: [], gold: amount) else {
            post(L("Your bag is full. Put something in the bank first."), .system)
            return false
        }
        data.bankGold = bankGold - amount
        data.gold += amount
        SoundEffects.shared.play(.coins)
        return true
    }

    // MARK: - What a defeat costs

    /// What a quest you're on needs or gave you: never lost (a parcel to deliver, its pieces, the
    /// things to bring, the gifts it starts with), so a defeat can't break a quest.
    var questKeepsakes: Set<String> {
        var keep = Set<String>()
        for quest in activeQuests {
            keep.formUnion(quest.starterItems ?? [])
            keep.formUnion((quest.drops ?? []).map(\.item))
            switch quest.objective.type {
            case .bring:
                if let id = quest.objective.target {
                    keep.insert(id)
                    keep.formUnion(content.item(id)?.recipe.map { Array($0.keys) } ?? [])
                }
            case .deliver:
                keep.formUnion([quest.objective.item, quest.objective.returns].compactMap { $0 })
            default:
                break
            }
        }
        return keep
    }

    /// Lost a fight: everything you carry is gone, coins and all, but what a quest you're on needs;
    /// beaten by another adventurer (a duel), what you wear too. It's left where you fell
    /// (`dropPile`), for you to come back for before someone else picks it up. The bank keeps what's
    /// in it. Returns what it cost, for the battle log.
    @discardableResult
    func loseBelongings(worn: Bool) -> [String] {
        let keep = questKeepsakes
        var lost: [String] = []
        var dropped: [String: Int] = [:]
        for (id, amount) in data.inventory where amount > 0 && !keep.contains(id) {
            data.inventory[id] = nil
            dropped[id, default: 0] += amount
            lost.append(amount > 1 ? "\(content.item(id)?.name ?? id) ×\(amount)" : content.item(id)?.name ?? id)
        }
        let gold = data.gold
        data.gold = 0
        if worn {
            for slot in ItemType.equipmentSlots {
                guard let id = data.hero.equipment[slot] else { continue }
                data.hero.equipment[slot] = nil
                dropped[id, default: 0] += 1
                lost.append(content.item(id)?.name ?? id)
            }
            clampHero()
            applyLook()
        }
        dropPile(items: dropped, gold: gold)
        var lines: [String] = []
        if gold > 0 { lines.append(L("You lost the {gold} gold you carried.", ["gold": gold])) }
        if !lost.isEmpty {
            lines.append(worn ? L("You lost everything you carried and wore: {items}.", ["items": lost.sorted().joined(separator: ", ")])
                              : L("You lost everything you carried: {items}.", ["items": lost.sorted().joined(separator: ", ")]))
        }
        if !lines.isEmpty {
            lines.append(L("It's all left where you fell: go back for it before someone else picks it up."))
            lines.append(L("What's in the bank is safe."))
        }
        return lines
    }

    /// Games begun before the bank (0.8.0) start with what they carried in it, once (playtesting
    /// 2026-10-25: "automatically place items in my bank already just for this time"): the bag and the
    /// coins go in, all but what a quest you're on needs. What's worn stays on.
    func stockBankOnce() {
        guard data.bankStocked != true else { return }
        data.bankStocked = true
        let keep = questKeepsakes
        for (id, amount) in data.inventory where amount > 0 && !keep.contains(id) {
            data.inventory[id] = nil
            data.bank = bank.merging([id: amount]) { $0 + $1 }
        }
        data.bankGold = bankGold + data.gold
        data.gold = 0
    }
}
