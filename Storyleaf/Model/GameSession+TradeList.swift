import Foundation

/// What you've put up for trade (playtesting 2026-10-25: "I should be able to set items up for trade,
/// and then when a bot goes up to me, they can trade with me and then I can decide if I accept the
/// offer or decline"): marked in the Bag, and while there's something, now and then an adventurer
/// about walks over (`Crowd.onOffer`) and offers for one of them (`receiveBid`). Their offer is
/// around what it's worth, from a little under what a shop pays to twice that: take it or leave it.
extension GameSession {
    /// How many kinds of thing can be up for trade at once.
    static let maxForTrade = 8

    /// An adventurer's offer for one of what you've put up for trade.
    struct Bid: Identifiable, Equatable {
        let id = UUID()
        let buyer: Adventurer
        let item: ItemDef
        let price: Int

        static func == (a: Bid, b: Bid) -> Bool { a.id == b.id }
    }

    /// What you've put up for trade and still have, in the order you put it up.
    var forTrade: [ItemDef] {
        (data.forTrade ?? []).compactMap { content.item($0) }.filter { count(of: $0.id) > 0 }
    }

    func isForTrade(_ id: String) -> Bool { data.forTrade?.contains(id) == true && count(of: id) > 0 }

    /// Whether `item` can go up for trade: something with a price you carry, not a quest's.
    func canPutUpForTrade(_ item: ItemDef) -> Bool {
        item.price > 0 && count(of: item.id) > 0 && !questKeepsakes.contains(item.id)
    }

    func putUpForTrade(_ id: String) {
        guard let item = content.item(id), canPutUpForTrade(item), !isForTrade(id), forTrade.count < Self.maxForTrade else { return }
        // What's gone from the bag since drops off the list as this goes on.
        data.forTrade = forTrade.map(\.id) + [id]
        SoundEffects.shared.play(.tap, volume: 0.7)
    }

    func takeOffTrade(_ id: String) {
        data.forTrade = forTrade.map(\.id).filter { $0 != id }
        SoundEffects.shared.play(.tap, volume: 0.7)
    }

    /// Whether an adventurer might come over to buy: something's up for trade, and no offer's waiting.
    var awaitsBuyer: Bool { pendingBid == nil && !forTrade.isEmpty }

    /// `buyer` has walked up to you: their offer for one of what you've put up for trade, waiting for
    /// your answer (`acceptBid`, `declineBid`). `roll`: the dice, 0 to 1.
    func receiveBid(from buyer: Adventurer, roll: Double = .random(in: 0..<1)) {
        guard pendingBid == nil, let item = forTrade.randomElement() else { return }
        let price = max(1, Int((Double(Self.sellPrice(of: item)) * (0.8 + 1.2 * roll)).rounded()))
        pendingBid = Bid(buyer: buyer, item: item, price: price)
        SoundEffects.shared.play(.talk)
    }

    /// Takes the offer waiting: one of the item for its price. False when you can't (you no longer
    /// have it, or the bag has no room for the coins); the offer's gone either way.
    @discardableResult
    func acceptBid() -> Bool {
        guard let bid = pendingBid else { return false }
        pendingBid = nil
        // The coins need a slot, unless you carry some or this was the last of its kind.
        guard data.gold > 0 || count(of: bid.item.id) == 1 || bagSlotsFree > 0 else {
            post(L("Your bag is full. Put something in the bank first."), .system)
            return false
        }
        guard removeItem(bid.item.id) else { return false }
        gainGold(bid.price)
        if count(of: bid.item.id) == 0 { data.forTrade = forTrade.map(\.id) }
        SoundEffects.shared.play(.coins)
        post(L("Sold {item} to {name} for {gold} gold.", ["item": bid.item.name, "name": bid.buyer.name, "gold": bid.price]), .reward)
        return true
    }

    func declineBid() {
        pendingBid = nil
    }
}
