import Foundation

/// Dyeing armour (Dyes.swift): Orla the Weaver or a barber dyes one piece you carry or wear with a dye
/// you mixed (playtesting 2026-10-30: "I want to be able to dye armor in some way. Maybe by combining
/// items and then going to a character to do that"). One dye colours one piece: of three Copper Plates,
/// one turns Crimson (`copper_plate~crimson_dye`) and two stay as they were. Washing it out is free.
extension GameSession {
    /// A piece that can be dyed, and where it is: on the hero, or in the bag.
    struct DyePiece: Identifiable, Hashable {
        let itemID: String
        let worn: Bool
        var id: String { (worn ? "worn:" : "bag:") + itemID }
    }

    /// The dyed pieces in the bag (`Content.item` makes them, so `content.items` hasn't them).
    var dyedInBag: [ItemDef] {
        data.inventory.keys.filter { $0.contains(ItemDef.dyeMark) && count(of: $0) > 0 }.sorted().compactMap { content.item($0) }
    }

    /// What you could dye: what you wear first, then the bag's, in its order.
    var dyeablePieces: [DyePiece] {
        let worn = ItemType.equipmentSlots.compactMap { slot in
            equipped(slot).flatMap { $0.canBeDyed ? DyePiece(itemID: $0.id, worn: true) : nil }
        }
        return worn + bagItems.filter(\.canBeDyed).map { DyePiece(itemID: $0.id, worn: false) }
    }

    /// The dyes in the bag, as the game lists them.
    var dyesCarried: [ItemDef] {
        content.items.filter { $0.dye != nil && count(of: $0.id) > 0 }
    }

    /// Dyes one piece (`piece`: on the hero or one of a kind in the bag) with one of `dyeID`, used up.
    /// Returns the dyed piece, or nil if it can't be: no such dye in the bag, not a piece that takes one,
    /// or that colour already.
    @discardableResult
    func dye(_ piece: DyePiece, with dyeID: String) -> ItemDef? {
        guard let item = content.item(piece.itemID), item.canBeDyed, content.item(dyeID)?.dye != nil, count(of: dyeID) > 0,
              item.dyeID != dyeID, let dyed = content.item(ItemDef.dyedID(item.baseID, with: dyeID)),
              swap(piece, to: dyed.id) else { return nil }
        data.inventory[dyeID] = count(of: dyeID) > 1 ? count(of: dyeID) - 1 : nil
        tidyItemOrders()
        return dyed
    }

    /// Washes a dyed piece back to the piece it was, free. Returns it, or nil if it isn't dyed.
    @discardableResult
    func washOut(_ piece: DyePiece) -> ItemDef? {
        guard let item = content.item(piece.itemID), item.isDyed, let plain = content.item(item.baseID),
              swap(piece, to: plain.id) else { return nil }
        tidyItemOrders()
        return plain
    }

    /// Puts `id` where the piece was: in its slot on the hero, or one of it in the bag (in its place in
    /// your order of the bag). The number of things in the bag stays the same.
    private func swap(_ piece: DyePiece, to id: String) -> Bool {
        guard let item = content.item(piece.itemID) else { return false }
        if piece.worn {
            guard data.hero.equipment[item.type] == piece.itemID else { return false }
            data.hero.equipment[item.type] = id
            applyLook()
            return true
        }
        let held = count(of: piece.itemID)
        guard held > 0 else { return false }
        data.inventory[piece.itemID] = held > 1 ? held - 1 : nil
        data.inventory[id, default: 0] += 1
        if var order = data.bagOrder, let at = order.firstIndex(of: piece.itemID), !order.contains(id) {
            order.insert(id, at: at + 1)
            data.bagOrder = order
        }
        return true
    }
}
