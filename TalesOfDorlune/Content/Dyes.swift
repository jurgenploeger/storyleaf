import Foundation

// Dyeing armour, a piece at a time (playtesting 2026-10-30: "I want to be able to dye armor in some
// way. Maybe by combining items and then going to a character to do that"). A dye is mixed in the Bag
// from a gem and a Sheepskin (items.json `dye`, `make` mix); Orla the Weaver or a barber dyes one piece
// with it (`GameSession.dye`). The bag counts things by id and a slot holds an id, so a dyed piece is a
// kind of its own: "<its id>~<the dye's id>" (`copper_plate~crimson_dye`), which `Content.item` reads as
// a copy of the piece in the dye's colour (`ItemDef.dyed`).

/// A dye's colour (items.json `dye`).
nonisolated struct DyeDef: Decodable, Sendable {
    /// The colour word on a dyed piece ("Copper Plate (Crimson)").
    let name: String
    /// "#RRGGBB": gloves, boots and a hide cloak (or hood) are painted in it.
    let color: String
    /// The same colour in HSV, as a tier's `color` is: hue in degrees, saturation and value 0 to 1.
    let hue: Double
    let saturation: Double
    let value: Double
}

nonisolated extension DyeDef {
    /// How it recolours an armour sheet, or the hat cut from one, of `kind` (the `armor_<kind>_<race>`
    /// sheets, a hat's `headgear`): the sheet's main material (tools/wear_art.py MATERIAL, brought to one
    /// colour on every race) taken to the dye's colour, as the armour tiers' `tint`s take it to theirs.
    /// Their numbers are the tiers' own, worked back from each tier's `color`: a plate's steel in bands by
    /// saturation (its palest pixels need the most), its shadows a little darker; a robe's, a hide hood's,
    /// a mail's, a dragon mail's, a snow or a ranger's cloak's in one rule each.
    func rules(for kind: String) -> [RecolorRule] {
        let s = saturation
        let v = value
        switch kind {
        case "iron_plate":
            let m = 1.43 * s
            let lit = 0.63 + 0.5 * v
            let shade = lit * 0.91
            let steel: [Double] = [140, 260]
            return [rule(steel, min: 0.05, max: 0.15, maxValue: 0.7, saturation: 4.22 * m, value: shade),
                    rule(steel, min: 0.05, max: 0.15, saturation: 2.88 * m, value: lit),
                    rule(steel, min: 0.05, max: 0.25, maxValue: 0.7, saturation: 2.61 * m, value: shade),
                    rule(steel, min: 0.05, max: 0.25, saturation: 1.79 * m, value: lit),
                    rule(steel, min: 0.05, maxValue: 0.7, saturation: 1.46 * m, value: shade),
                    rule(steel, min: 0.05, saturation: m, value: lit)]
        case "mage_robe":
            return [rule([190, 260], min: 0.2, spread: 1, saturation: 1.29 * s, value: 0.5 + 0.83 * v)]
        case "hide_hood":
            return [rule([180, 260], min: 0.2, spread: 1, saturation: 1.68 * s, value: 1.82 * v)]
        case "dragon_mail":
            return [rule([335, 25], min: 0.55, saturation: s / 0.85, value: 0.3 + 0.8 * v)]
        case "snow_cloak":
            return [rule([180, 250], min: 0.1, saturation: 0.3 + 1.5 * s, value: 0.35 + 0.75 * v)]
        case "ranger_cloak":
            return [rule([70, 170], min: 0.2, saturation: 1.25 * s, value: 0.58 + 0.6 * v)]
        default:   // chain mail, and any sheet to come: its greyish steel
            return [rule([150, 260], min: 0.03, saturation: 5 * s, value: 0.45 + 1.1 * v)]
        }
    }

    /// How it recolours the hero's own outfit under armour drawn on it (`ItemDef.recolor`, the tunic's
    /// green), as a tier's armour does: a hide cloak a shade darker.
    func outfitRules(cloak: Bool) -> [RecolorRule] {
        [rule([85, 170], min: 0.3, saturation: 1.16 * s, value: (cloak ? 0.4 : 0.5) + 0.68 * value)]
    }

    private var s: Double { saturation }

    private func rule(_ hues: [Double], min: Double, max: Double? = nil, maxValue: Double? = nil, spread: Double? = nil,
                      saturation: Double, value: Double) -> RecolorRule {
        RecolorRule(hue: hues, minSaturation: min, maxSaturation: max, minValue: nil, maxValue: maxValue,
                    to: hue, shift: nil, spread: spread, saturation: saturation, value: value)
    }
}

nonisolated extension ItemDef {
    /// What joins a dyed piece's id to its dye's: "copper_plate~crimson_dye".
    static let dyeMark: Character = "~"

    /// The piece a dyed one was dyed from, or the id itself.
    static func baseID(of id: String) -> String {
        guard let mark = id.firstIndex(of: dyeMark) else { return id }
        return String(id[..<mark])
    }

    /// The dye a dyed piece was dyed with, or nil.
    static func dyeID(of id: String) -> String? {
        guard let mark = id.firstIndex(of: dyeMark) else { return nil }
        return String(id[id.index(after: mark)...])
    }

    /// The id of `baseID` dyed with `dyeID`.
    static func dyedID(_ baseID: String, with dyeID: String) -> String {
        baseID + String(dyeMark) + dyeID
    }

    /// The piece it was dyed from (its own id if it isn't dyed): what an armour's `headpiece` names.
    var baseID: String { Self.baseID(of: id) }
    /// The dye it's dyed with, if it is.
    var dyeID: String? { Self.dyeID(of: id) }
    var isDyed: Bool { dyeID != nil }

    /// Armour, a hat that goes with armour, gloves and boots take a dye; a festive hat (`hat`), a cape,
    /// a weapon or a trinket doesn't.
    var canBeDyed: Bool {
        switch type {
        case .armor, .gloves, .boots: true
        case .head: hat == nil
        default: false
        }
    }

    /// The kind of armour sheet it is, or whose hat it is, for `DyeDef.rules`: a hat's `headgear` (but a
    /// hide cloak's painted `hood`), else its sheets' (`armor_<kind>_<race>`).
    var sheetKind: String? {
        if let headgear { return headgear == "hood" ? nil : headgear }
        guard let entry = sheets?.first else { return nil }
        var kind = entry.value
        if kind.hasPrefix("armor_") { kind.removeFirst("armor_".count) }
        if kind.hasSuffix("_" + entry.key) { kind.removeLast(entry.key.count + 1) }
        return kind
    }

    /// This piece in a dye's colour (`Content.item` makes it for "<id>~<dye id>"): the same piece, its
    /// name with the colour after it, its sheet or hat recoloured to the dye (`tint`, in place of a rare
    /// variant's: a dyed piece no longer shows its tier by its colour), the outfit under drawn-on armour
    /// too (`recolor`), and painted in it where it's painted (`color`: gloves, boots, a hide cloak). Its
    /// icon is its own recoloured the same way (`ArtLibrary`, the art "<art>~<dye id>").
    func dyed(with dye: DyeDef, dyeID: String) -> ItemDef {
        var copy = self
        copy.id = Self.dyedID(id, with: dyeID)
        copy.name = L("{item} ({colour})", ["item": name, "colour": dye.name])
        if let kind = sheetKind { copy.tint = dye.rules(for: kind) }
        if type == .armor { copy.recolor = dye.outfitRules(cloak: wear == "cloak") }
        if color != nil || type == .gloves || type == .boots || headgear == "hood" { copy.color = dye.color }
        copy.art = art.map { $0 + String(Self.dyeMark) + dyeID }
        return copy
    }
}
