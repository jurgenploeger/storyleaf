import Foundation

/// What you've put up for trade (playtesting 2026-10-25: "I should be able to set items up for trade,
/// and then when a bot goes up to me, they can trade with me and then I can decide if I accept the
/// offer or decline"): marked in the Bag, and while there's something, now and then an adventurer
/// about walks over (`Crowd.onOffer`) and offers for one of them (`receiveBid`). What they'd pay is
/// around what it's worth, from a little under what a shop pays to twice that; you set a price for
/// one and how many you'd sell (playtesting 2026-10-26: "determine the price of the item (prefilled
/// with default price/value) and then how many you want to set up for trade"): one who'd pay your
/// price offers it, one who wouldn't offers what they would. Take it or leave it.
extension GameSession {
    /// How many kinds of thing can be up for trade at once.
    static let maxForTrade = 8
    /// The most you can ask for one.
    static let maxTradePrice = 999_999

    /// An adventurer's offer for one of what you've put up for trade.
    struct Bid: Identifiable, Equatable {
        let id = UUID()
        let buyer: Adventurer
        let item: ItemDef
        let price: Int

        static func == (a: Bid, b: Bid) -> Bool { a.id == b.id }
    }

    /// What you've put up for trade and still have some of to sell, in the order you put it up.
    var forTrade: [ItemDef] {
        (data.forTrade ?? []).compactMap { content.item($0) }.filter { forSale($0.id) > 0 }
    }

    func isForTrade(_ id: String) -> Bool { data.forTrade?.contains(id) == true && forSale(id) > 0 }

    /// Whether `item` can go up for trade: something with a price you carry, not a quest's.
    func canPutUpForTrade(_ item: ItemDef) -> Bool {
        item.price > 0 && count(of: item.id) > 0 && !questKeepsakes.contains(item.id)
    }

    /// The price an asking price starts at: the middle of what adventurers pay for one, 0.8 to 2
    /// times what a shop does (`receiveBid`).
    static func tradeValue(of item: ItemDef) -> Int {
        max(1, Int((Double(sellPrice(of: item)) * 1.4).rounded()))
    }

    /// The most an adventurer pays for one.
    static func topTradePrice(of item: ItemDef) -> Int { sellPrice(of: item) * 2 }

    /// What you ask for one of what you've put up for trade, and how many you'd still sell (no more
    /// than you carry); for something not up for trade, what it would start at: all you carry at
    /// the going price.
    func tradeAsk(_ id: String) -> TradeAsk {
        let held = count(of: id)
        let value = content.item(id).map(Self.tradeValue) ?? 1
        guard data.forTrade?.contains(id) == true, let ask = data.tradeAsks?[id] else { return TradeAsk(price: value, count: held) }
        return TradeAsk(price: ask.price, count: min(ask.count, held))
    }

    /// How many of it you'd still sell.
    func forSale(_ id: String) -> Int {
        guard data.forTrade?.contains(id) == true else { return 0 }
        return tradeAsk(id).count
    }

    /// Puts `count` of it (nil: all you carry) up for trade at `price` for one (nil: `tradeValue`),
    /// or changes what you ask for what's up already.
    func putUpForTrade(_ id: String, count wanted: Int? = nil, price: Int? = nil) {
        guard let item = content.item(id), canPutUpForTrade(item) else { return }
        let listed = isForTrade(id)
        guard listed || forTrade.count < Self.maxForTrade else { return }
        let held = count(of: id)
        let ask = TradeAsk(price: min(max(1, price ?? Self.tradeValue(of: item)), Self.maxTradePrice),
                           count: min(max(1, wanted ?? held), held))
        var asks = data.tradeAsks ?? [:]
        asks[id] = ask
        data.tradeAsks = asks
        // What's gone from the bag since drops off the list as this goes on.
        let ids = forTrade.map(\.id)
        data.forTrade = ids.contains(id) ? ids : ids + [id]
        pruneTradeAsks()
        SoundEffects.shared.play(.tap, volume: 0.7)
    }

    func takeOffTrade(_ id: String) {
        data.forTrade = forTrade.map(\.id).filter { $0 != id }
        pruneTradeAsks()
        SoundEffects.shared.play(.tap, volume: 0.7)
    }

    /// Forgets the asks for what's no longer up for trade.
    private func pruneTradeAsks() {
        guard let asks = data.tradeAsks else { return }
        let listed = Set(data.forTrade ?? [])
        data.tradeAsks = asks.filter { listed.contains($0.key) }
    }

    /// Whether an adventurer might come over to buy: something's up for trade, and no offer's waiting.
    var awaitsBuyer: Bool { pendingBid == nil && !forTrade.isEmpty }

    /// `buyer` has walked up to you: their offer for one of what you've put up for trade, waiting for
    /// your answer (`acceptBid`, `declineBid`): your price if they'd pay that much, else what they
    /// would. `roll`: the dice, 0 to 1.
    func receiveBid(from buyer: Adventurer, roll: Double = .random(in: 0..<1)) {
        guard pendingBid == nil, let item = forTrade.randomElement() else { return }
        let worth = max(1, Int((Double(Self.sellPrice(of: item)) * (0.8 + 1.2 * roll)).rounded()))
        pendingBid = Bid(buyer: buyer, item: item, price: min(worth, tradeAsk(item.id).price))
        SoundEffects.shared.play(.talk)
    }

    /// Takes the offer waiting: one of the item for its price. False when you can't (you no longer
    /// have it, or the bag has no room for the coins); the offer's gone either way.
    @discardableResult
    func acceptBid() -> Bool {
        guard let bid = pendingBid else { return false }
        pendingBid = nil
        // The coins go in the slot it leaves, if they need one.
        guard removeItem(bid.item.id) else { return false }
        gainGold(bid.price)
        // One fewer to sell; sold out, it's off the list.
        if let ask = data.tradeAsks?[bid.item.id] {
            data.tradeAsks?[bid.item.id]?.count = max(0, ask.count - 1)
        }
        data.forTrade = forTrade.map(\.id)
        pruneTradeAsks()
        SoundEffects.shared.play(.coins)
        post(L("Sold {item} to {name} for {gold} gold.", ["item": bid.item.name, "name": bid.buyer.name, "gold": bid.price]), .reward)
        return true
    }

    func declineBid() {
        pendingBid = nil
    }
}
