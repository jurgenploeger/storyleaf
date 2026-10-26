import Foundation

/// Which side of the bank something is on: in the bag, or in the bank.
nonisolated enum BankSide: String, Sendable {
    case bag, bank
}

/// Where things sit in the bag and the bank (playtesting 2026-10-26: "In the bank and inventory I
/// should be able to reorder any items. Also add sorting and filtering to the bank."): your order of
/// each, by item id (`SaveData.bagOrder`, `bankOrder`). Hold a thing to lift it and move it where
/// another is (`ItemSlotGrid`). What you've never placed follows what you have, in the game's order, so
/// something new turns up at the end; a kind gone from its side drops out of the order as the game
/// saves (`tidyItemOrders`), and comes back at the end. A game that's never moved anything keeps the
/// game's order. Sorting (`ItemSort`) is a way of looking: moving something while sorted another way
/// keeps the order you see from then on.
extension GameSession {
    /// How many of a kind there are on one side.
    func held(_ id: String, on side: BankSide) -> Int { side == .bag ? count(of: id) : banked(id) }

    /// Everything on one side, in your order.
    func items(on side: BankSide) -> [ItemDef] {
        let found = content.items.filter { held($0.id, on: side) > 0 }
        return Self.arrange(found, by: side == .bag ? data.bagOrder : data.bankOrder)
    }

    /// Everything in the bag, in your order.
    var bagItems: [ItemDef] { items(on: .bag) }

    /// `items` in `order`: those it names first, as placed, then the rest as they come.
    static func arrange(_ items: [ItemDef], by order: [String]?) -> [ItemDef] {
        guard let order, !order.isEmpty else { return items }
        let place = Dictionary(order.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        let placed = items.filter { place[$0.id] != nil }.sorted { place[$0.id]! < place[$1.id]! }
        return placed + items.filter { place[$0.id] == nil }
    }

    /// Puts `id` where `target` is on `side`, the things between shifting along one: before it moving
    /// up, after it moving down. `sort`: the order you see them in, kept as yours from now on. False
    /// when either isn't there, or they're the same.
    @discardableResult
    func moveItem(_ id: String, onto target: String, on side: BankSide, sortedBy sort: ItemSort = .standard) -> Bool {
        var order = ItemFinder.arrange(items(on: side), search: "", sort: sort, session: self, on: side).map(\.id)
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return false }
        order.remove(at: from)
        order.insert(id, at: to)
        switch side {
        case .bag: data.bagOrder = order
        case .bank: data.bankOrder = order
        }
        SoundEffects.shared.play(.tap, volume: 0.7)
        return true
    }

    /// Drops what's no longer on its side from your orders, so a kind that comes back turns up at the
    /// end, as something new does.
    func tidyItemOrders() {
        if let order = data.bagOrder {
            let kept = order.filter { count(of: $0) > 0 }
            data.bagOrder = kept.isEmpty ? nil : kept
        }
        if let order = data.bankOrder {
            let kept = order.filter { banked($0) > 0 }
            data.bankOrder = kept.isEmpty ? nil : kept
        }
    }
}
