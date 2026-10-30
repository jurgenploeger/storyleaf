import CoreGraphics
import Foundation

/// What you lose in a fight you lose is left where you fell (playtesting 2026-10-25: "If you die,
/// anything that was lost will be shown on the map and for other players to grab"), as RuneScape
/// leaves it: a pile on the ground there, marked on the minimap and the world map. For a while only you
/// can take it back (`pileYoursAlone`); after that any adventurer passing by may pick it up, and it's
/// gone for good once `pileLasts` is up. When is rolled as it's dropped (`takenAt`).
extension GameSession {
    /// How long a pile is yours alone, in seconds.
    static let pileYoursAlone: TimeInterval = 5 * 60
    /// How long it lies there at most, in seconds.
    static let pileLasts: TimeInterval = 20 * 60
    /// Once it's anyone's, how long an adventurer takes to come by and pick it up, on average.
    static let pileFoundIn: TimeInterval = 5 * 60
    /// How many piles lie about at once: a sixth fall takes the oldest away.
    static let maxPiles = 5
    /// How near you have to stand to pick one up, in points.
    static let pickUpReach: CGFloat = 60

    var lostPiles: [LostPile] { data.lostPiles ?? [] }

    func piles(on mapID: String) -> [LostPile] { lostPiles.filter { $0.mapID == mapID } }

    /// Whether anyone may take a pile yet, not just you.
    static func isOpen(_ pile: LostPile, at now: Date = Date()) -> Bool {
        now >= pile.droppedAt.addingTimeInterval(pileYoursAlone)
    }

    /// Leaves what you lost on the ground where you are, with when it'll be gone: picked up by an
    /// adventurer some while after it's anyone's, unless it's just gone first.
    func dropPile(items: [String: Int], now: Date = Date(), roll: Double = .random(in: 0..<1)) {
        guard !items.isEmpty else { return }
        let found = now.addingTimeInterval(Self.pileYoursAlone - Self.pileFoundIn * Foundation.log(max(1e-6, 1 - roll)))
        let pile = LostPile(id: UUID(), mapID: data.mapID, position: playerPosition.map { [Double($0.x), Double($0.y)] },
                            items: items, gold: 0, droppedAt: now,
                            takenAt: min(found, now.addingTimeInterval(Self.pileLasts)))
        data.lostPiles = Array((lostPiles + [pile]).suffix(Self.maxPiles))
    }

    /// Drops `amount` of a kind you carry at your feet (playtesting 2026-10-25: "I should be able to drop
    /// items"), RuneScape's way: onto the pile you're standing by, else a new one, lying there as what
    /// you lose when you fall does, yours to pick back up for a while, then anyone's, then gone. Not
    /// what a quest you're on needs (`questKeepsakes`). False when there's none to drop.
    @discardableResult
    func drop(_ id: String, _ amount: Int, now: Date = Date()) -> Bool {
        let held = count(of: id)
        let amount = min(amount, held)
        guard amount > 0, !questKeepsakes.contains(id) else { return false }
        data.inventory[id] = held > amount ? held - amount : nil
        if held == amount, data.forTrade != nil { data.forTrade = forTrade.map(\.id) }
        var piles = lostPiles
        // Onto the pile you're by (one about to go takes nothing more).
        if let index = piles.firstIndex(where: { $0.takenAt > now && ($0.id == nearbyPile || isWithinReach($0)) }) {
            piles[index].items[id, default: 0] += amount
            data.lostPiles = piles
        } else {
            dropPile(items: [id: amount], now: now)
        }
        let name = content.item(id)?.name ?? id
        post(L("You dropped {item}.", ["item": amount > 1 ? "\(name) ×\(amount)" : name]))
        SoundEffects.shared.play(.equip)
        return true
    }

    /// Whether a pile lies on this map within reach of where you stand (both nowhere in particular, the
    /// map's middle, counts).
    private func isWithinReach(_ pile: LostPile) -> Bool {
        guard pile.mapID == data.mapID else { return false }
        guard let here = playerPosition, let at = pile.position, at.count == 2 else { return playerPosition == nil && pile.position == nil }
        return CGPoint(x: at[0], y: at[1]).distance(to: here) <= Self.pickUpReach
    }

    /// Takes away the piles whose time is up, and says so: picked up by an adventurer, or gone.
    func watchPiles(now: Date = Date()) {
        let gone = lostPiles.filter { $0.takenAt <= now }
        guard !gone.isEmpty else { return }
        data.lostPiles = lostPiles.filter { $0.takenAt > now }
        if nearbyPile.map({ id in gone.contains { $0.id == id } }) == true { nearbyPile = nil }
        for pile in gone {
            let place = content.map(pile.mapID)?.name ?? L("town")
            if pile.takenAt < pile.droppedAt.addingTimeInterval(Self.pileLasts),
               let name = content.crowd.adventurerNames.randomElement() {
                post(L("{name} picked up what you lost in {place}.", ["name": name, "place": place]))
            } else {
                post(L("What you lost in {place} is gone.", ["place": place]))
            }
        }
    }

    /// Picks a pile up: as much as the bag has room for, coins too; the rest stays where it lies.
    /// False when there's no such pile or nothing fit.
    @discardableResult
    func pickUp(_ id: UUID) -> Bool {
        guard var pile = lostPiles.first(where: { $0.id == id }) else { return false }
        var got = false
        for (item, amount) in pile.items.sorted(by: { $0.key < $1.key }) {
            let taken = min(amount, bagSlotsFree)
            guard taken > 0 else { continue }
            data.inventory[item, default: 0] += taken
            pile.items[item] = amount > taken ? amount - taken : nil
            got = true
        }
        // Coins in a pile from before they were never lost (0.9.4 and earlier).
        if pile.gold > 0 {
            data.gold += pile.gold
            pile.gold = 0
            got = true
        }
        let left = !pile.items.isEmpty || pile.gold > 0
        data.lostPiles = left ? lostPiles.map { $0.id == id ? pile : $0 } : lostPiles.filter { $0.id != id }
        if !left, nearbyPile == id { nearbyPile = nil }
        if got {
            SoundEffects.shared.play(.coins)
            post(left ? L("You picked up what your bag had room for. The rest is still here.")
                      : L("You picked up everything you lost."), .reward)
        } else {
            post(L("Your bag is full. Put something in the bank first."), .system)
        }
        return got
    }
}
