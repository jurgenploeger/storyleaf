import Foundation

// Dyeing armour, a piece at a time (playtesting 2026-10-30: "I want to be able to dye armor in some
// way. Maybe by combining items and then going to a character to do that"). A dye is mixed in the Bag
// from a gem and a Sheepskin (items.json `dye`, `make` mix); Orla the Weaver or a barber dyes one piece
// with it (`GameSession.dye`). The bag counts things by id and a slot holds an id, so a dyed piece is a
// kind of its own: "<its id>~<the dye's id>" (`copper_plate~crimson_dye`), which `Content.item` reads as
// a copy of the piece in the dye's colour (`ItemDef.dyed`). A second dye colours its trim (playtesting
// 2026-10-30): "<its id>~<main dye>~<trim dye>", or "<its id>~~<trim dye>" for the trim alone; a piece
// dyed one colour keeps the id it always had, so saved games read as before.

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
    /// Its shadows' own colour, where it has one (playtesting 2026-10-31: "the white and yellow weapons lose
    /// their depth"): their hue (gold's warmer, toward amber; white's a cool blue grey) and saturation, so
    /// the ramp turns as it darkens, as drawn shading does; and how much contrast they keep (`shadowGain`).
    var shadowHue: Double? = nil
    var shadowSaturation: Double? = nil
    var shadowContrast: Double? = nil

    private enum CodingKeys: String, CodingKey {
        case name, color, hue, saturation, value, shadowHue, shadowSaturation
        case shadowContrast = "shadowGain"
    }
}

/// What a dye recolours: a material on a sheet or a picture (where it is, as a `RecolorRule` window) and
/// its own colour, measured (tools/dye_art.py `cut`): its middle saturation and brightness, and the
/// brightness of its lightest (the 95th in a hundred).
nonisolated struct DyeMaterial: Sendable {
    var hue: [Double]? = nil
    var minSaturation: Double = 0
    var maxSaturation: Double? = nil
    var minValue: Double? = nil
    let saturation: Double
    let value: Double
    let light: Double
}

nonisolated extension DyeDef {
    /// The main material of each kind of armour sheet (tools/wear_art.py MATERIAL, one colour on every
    /// race), as the tiers' `tint`s find it, over its sheets and hats; then on each sheet and hat of
    /// its own (a dwarf's robe is lighter than a human's); and the outfit under drawn-on armour
    /// (`outfit`, the tunic's green). Outlines and the darkest shadows (`minValue`) keep their colour.
    /// tools/dye_art.py `cut` measures them and reads this table back: run its `check` after a change.
    static let mains: [String: DyeMaterial] = [
        "iron_plate": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.26, value: 0.45, light: 1.0),
        "chain_mail": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.19, value: 0.4, light: 0.88),
        "dragon_mail": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.99),
        "mage_robe": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.8, value: 0.5, light: 0.98),
        "ranger_cloak": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.55, value: 0.33, light: 0.66),
        "snow_cloak": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.53, value: 0.75, light: 0.97),
        "hide_hood": DyeMaterial(hue: [180, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.6, value: 0.55, light: 1.0),
        "outfit": DyeMaterial(hue: [85, 170], minSaturation: 0.3, minValue: 0.2, saturation: 0.78, value: 0.33, light: 0.82),
        "armor_iron_plate_human": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.25, value: 0.45, light: 1.0),
        "hat_iron_plate_human": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.25, value: 0.62, light: 1.0),
        "armor_iron_plate_elf": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.28, value: 0.45, light: 1.0),
        "hat_iron_plate_elf": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.11, value: 0.81, light: 1.0),
        "armor_iron_plate_dwarf": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.28, value: 0.45, light: 1.0),
        "hat_iron_plate_dwarf": DyeMaterial(hue: [140, 260], minSaturation: 0.05, minValue: 0.2, saturation: 0.28, value: 0.45, light: 1.0),
        "armor_chain_mail_human": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.17, value: 0.6, light: 1.0),
        "hat_chain_mail_human": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.17, value: 0.6, light: 0.88),
        "armor_chain_mail_elf": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.19, value: 0.33, light: 0.82),
        "hat_chain_mail_elf": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.22, value: 0.55, light: 0.82),
        "armor_chain_mail_dwarf": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.2, value: 0.4, light: 0.75),
        "hat_chain_mail_dwarf": DyeMaterial(hue: [150, 260], minSaturation: 0.03, minValue: 0.2, saturation: 0.2, value: 0.4, light: 0.92),
        "armor_dragon_mail_human": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.98),
        "hat_dragon_mail_human": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.98),
        "armor_dragon_mail_elf": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.99),
        "hat_dragon_mail_elf": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.99),
        "armor_dragon_mail_dwarf": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.71, light: 0.97),
        "hat_dragon_mail_dwarf": DyeMaterial(hue: [335, 25], minSaturation: 0.55, minValue: 0.2, saturation: 0.85, value: 0.85, light: 0.97),
        "armor_mage_robe_human": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.8, value: 0.4, light: 0.79),
        "hat_mage_robe_human": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.82, value: 0.5, light: 0.79),
        "armor_mage_robe_elf": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.8, value: 0.5, light: 0.83),
        "hat_mage_robe_elf": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.8, value: 0.5, light: 0.83),
        "armor_mage_robe_dwarf": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.61, value: 0.98, light: 0.98),
        "hat_mage_robe_dwarf": DyeMaterial(hue: [190, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.61, value: 0.98, light: 0.98),
        "armor_ranger_cloak_human": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.56, value: 0.33, light: 0.59),
        "hat_ranger_cloak_human": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.56, value: 0.33, light: 0.66),
        "armor_ranger_cloak_elf": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.55, value: 0.4, light: 0.67),
        "hat_ranger_cloak_elf": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.55, value: 0.5, light: 0.67),
        "armor_ranger_cloak_dwarf": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.5, value: 0.4, light: 0.4),
        "hat_ranger_cloak_dwarf": DyeMaterial(hue: [70, 170], minSaturation: 0.2, minValue: 0.2, saturation: 0.5, value: 0.4, light: 0.4),
        "armor_snow_cloak_human": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.54, value: 0.75, light: 0.98),
        "hat_snow_cloak_human": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.33, value: 0.9, light: 0.98),
        "armor_snow_cloak_elf": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.31, value: 0.76, light: 0.96),
        "hat_snow_cloak_elf": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.3, value: 0.84, light: 0.96),
        "armor_snow_cloak_dwarf": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.72, value: 0.42, light: 0.81),
        "hat_snow_cloak_dwarf": DyeMaterial(hue: [180, 250], minSaturation: 0.1, minValue: 0.2, saturation: 0.63, value: 0.61, light: 0.81),
        "hat_hide_hood_human": DyeMaterial(hue: [180, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.6, value: 0.55, light: 1.0),
        "hat_hide_hood_elf": DyeMaterial(hue: [180, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.6, value: 0.67, light: 0.91),
        "hat_hide_hood_dwarf": DyeMaterial(hue: [180, 260], minSaturation: 0.2, minValue: 0.2, saturation: 0.6, value: 0.55, light: 0.94),
    ]

    /// Each sheet's and hat's trim, a layer of its own ("<sheet>_trim", tools/dye_art.py `TRIMS`): a
    /// robe's gold sash and hem, a plate's red sash or gold collar, a dragon mail's gold, a ranger
    /// cloak's gold, a hide hood's fur lining. Chain mail and a snow cloak have none (chain mail's
    /// undershirt is the hands' reds), nor do a ranger's hood or a dwarf's wizard hat (their gold is the
    /// face's and the hair's).
    static let trims: [String: DyeMaterial] = [
        "armor_mage_robe_human": DyeMaterial(saturation: 0.42, value: 0.53, light: 0.94),
        "armor_mage_robe_elf": DyeMaterial(saturation: 0.72, value: 0.95, light: 0.95),
        "armor_mage_robe_dwarf": DyeMaterial(saturation: 0.87, value: 0.87, light: 0.98),
        "armor_iron_plate_human": DyeMaterial(saturation: 0.73, value: 0.33, light: 0.64),
        "armor_iron_plate_elf": DyeMaterial(saturation: 0.79, value: 0.81, light: 0.97),
        "armor_dragon_mail_human": DyeMaterial(saturation: 0.69, value: 0.98, light: 0.98),
        "armor_dragon_mail_elf": DyeMaterial(saturation: 0.47, value: 0.97, light: 0.97),
        "armor_dragon_mail_dwarf": DyeMaterial(saturation: 0.63, value: 0.99, light: 0.99),
        "armor_ranger_cloak_human": DyeMaterial(saturation: 0.58, value: 0.82, light: 0.91),
        "hat_mage_robe_human": DyeMaterial(saturation: 0.55, value: 0.85, light: 0.94),
        "hat_iron_plate_human": DyeMaterial(saturation: 0.87, value: 0.84, light: 0.84),
        "hat_iron_plate_elf": DyeMaterial(saturation: 0.79, value: 0.81, light: 0.97),
        "hat_iron_plate_dwarf": DyeMaterial(saturation: 0.62, value: 0.63, light: 0.89),
        "hat_dragon_mail_human": DyeMaterial(saturation: 0.77, value: 0.91, light: 0.98),
        "hat_dragon_mail_elf": DyeMaterial(saturation: 0.77, value: 0.75, light: 0.9),
        "hat_dragon_mail_dwarf": DyeMaterial(saturation: 0.63, value: 0.99, light: 0.99),
        "hat_hide_hood_human": DyeMaterial(saturation: 0.19, value: 0.96, light: 0.96),
        "hat_hide_hood_elf": DyeMaterial(saturation: 0.23, value: 0.96, light: 0.96),
        "hat_hide_hood_dwarf": DyeMaterial(saturation: 0.18, value: 0.98, light: 0.98),
    ]

    /// The weapons whose icon has no second colour to take a trim (a wooden sword, all wood; a steel one
    /// whose hilt is as dark as its outline), listed by tools/dye_art.py `cut`.
    static let oneColour: Set<String> = [
        "alloy_shortsword", "amber_whip", "armorbreaker_staff", "bamboo_staff", "beast_whip", "blossom_staff",
        "bronze_broadsword", "bronze_longsword", "brownwood_staff", "copper_sword", "cowhide_whip", "dragon_god_axe",
        "dragon_god_staff", "dragon_god_whip", "elder_staff", "ghost_staff", "golden_deer_whip", "goldleaf_axe",
        "hand_axe", "heavy_rattan_staff", "ironcleaver_sword", "ironcrusher_staff", "light_war_axe",
        "lightwood_staff", "luna_axe", "moonlight_sword", "novice_axe", "phantom_blade", "power_whip",
        "rattan_staff", "red_cypress_staff", "red_cypress_whip", "silver_inlaid_longsword", "silver_sword",
        "steel_sword", "strong_ox_whip", "tamer_whip", "teak_whip", "twin_blade_axe", "wooden_sword", "yew_staff"
    ]

    /// `material` taken to this dye's colour (playtesting 2026-10-30: an olive plate read as white): its
    /// hue, its saturation the dye's with half the material's own shading in it, its brightness the dye's
    /// in the middle and the ramp round it kept from dark to light, squeezed (to no less than 30%)
    /// where the lightest would pass white. tools/dye_art.py `rule_onto` is the same.
    func rule(onto material: DyeMaterial) -> RecolorRule {
        let top = lightest
        // Room to keep the shading (playtesting 2026-10-31: "make sure that the dyed items don't lose the
        // details like shadows and highlights"): a light dye's middle may sit a little under its own
        // (`slack`), so the ramp needn't be squeezed flat under white; a dark one's darkest only has to
        // stay over `floor`, not scale down with its middle; and never more contrast than the piece had,
        // unless brightening a dark one as before. tools/dye_art.py `rule_onto` is the same.
        let least = material.minValue ?? 0.2
        // A dark dye's middle may sit a little over its own (`rise`), so its shadows have room over black.
        let middle = value + rise
        let gain = Swift.max(0.3, Swift.min(Swift.max(1, value / material.value),
                                            (middle - slack - Self.floor) / Swift.max(0.01, material.value - least),
                                            (top - value + slack) / Swift.max(0.01, material.light - material.value)))
        return RecolorRule(hue: material.hue, minSaturation: material.minSaturation, maxSaturation: material.maxSaturation,
                           minValue: material.minValue, maxValue: nil, to: hue, shift: nil, spread: 0.25,
                           saturation: 0.5 * saturation / material.saturation, value: gain,
                           saturationOffset: 0.5 * saturation,
                           valueOffset: Swift.min(middle - gain * material.value, top - gain * material.light))
    }

    /// `rule(onto:)`, and under it, where that squeezed the ramp to fit a light dye under white, a rule
    /// of the material's shadows (its middle and darker) that keeps their contrast: up to `shadowGain`
    /// and no darker than `floor`. Squeezed whole, a Snow White plate's deepest shadow sat at 0.76 and it
    /// read as one white blob (playtesting 2026-10-31: "This looks too white"). tools/dye_art.py
    /// `rules_onto` is the same.
    func rules(onto material: DyeMaterial) -> [RecolorRule] {
        let main = rule(onto: material)
        let gain = main.value ?? 1
        let least = material.minValue ?? 0.2
        let middle = (main.valueOffset ?? 0) + gain * material.value
        let shadow = Swift.max(gain, Swift.min(shadowGain, (middle - Self.floor) / Swift.max(0.01, material.value - least)))
        guard shadow > gain + 1e-6 else { return [main] }
        let shadows = RecolorRule(hue: main.hue, minSaturation: main.minSaturation, maxSaturation: main.maxSaturation,
                                  minValue: main.minValue, maxValue: material.value, to: shadowHue ?? main.to, shift: main.shift,
                                  spread: main.spread,
                                  saturation: shadowSaturation.map { 0.5 * $0 / material.saturation } ?? main.saturation,
                                  value: shadow,
                                  saturationOffset: shadowSaturation.map { 0.5 * $0 } ?? main.saturationOffset,
                                  valueOffset: middle - shadow * material.value)
        return [shadows, main]
    }

    /// How much contrast a light dye's shadows keep where its lights are squeezed under white: all they
    /// had, a white's more, so its plate still has a deep shadow and an edge (tools/dye_art.py
    /// `SHADOW_GAIN`, `SHADOW_GAIN_WHITE`).
    var shadowGain: Double {
        shadowContrast ?? (saturation < 0.1 ? 2.0 : 1.0)
    }

    /// The brightest a dye's shine goes: white for a light dye; for a dark one, down toward halfway
    /// from its colour to white, the darker the further (from 0.7 down to 0.3). A Midnight plate's
    /// shine at 0.8 read as white beside its 0.32 navy (playtesting 2026-10-31). tools/dye_art.py
    /// `lightest` is the same.
    /// How far under its own brightness a piece's middle may sit to keep its shading: a light dye's
    /// (a white's more), none for a dark one, which has no white to fit under (tools/dye_art.py `SLACK`).
    var slack: Double {
        (saturation < 0.1 ? 0.12 : 0.08) * Swift.min(1, Swift.max(0, (value - 0.5) / 0.2))
    }

    /// How far over its own brightness a dark dye's middle may sit, so its shadows have room over black
    /// (a blackish Midnight on a bright blade squeezed it flat): none for a light dye (tools/dye_art.py
    /// `rise`).
    var rise: Double {
        0.08 * Swift.min(1, Swift.max(0, (0.5 - value) / 0.2))
    }

    /// The darkest a dyed piece's material goes: just over black, so its deepest shadow still reads as
    /// part of it (tools/dye_art.py `FLOOR`).
    static let floor = 0.06

    var lightest: Double {
        let darkness = Swift.min(1, Swift.max(0, (0.7 - value) / 0.4))
        return 1 - 0.5 * (1 - value) * darkness
    }

    /// How it recolours an armour sheet, or the hat cut from one, of `kind` (the `armor_<kind>_<race>`
    /// sheets, a hat's `headgear`), or the sheet or hat `art` itself where it's measured: its main
    /// material taken to the dye's colour. A kind to come is taken as chain mail's greyish steel.
    func rules(for kind: String, art: String? = nil) -> [RecolorRule] {
        guard let material = art.flatMap({ Self.mains[$0] }) ?? Self.mains[kind] ?? Self.mains["chain_mail"] else { return [] }
        return rules(onto: material)
    }

    /// How it recolours the hero's own outfit under armour drawn on it (`ItemDef.recolor`, the tunic's green).
    func outfitRules() -> [RecolorRule] {
        Self.mains["outfit"].map { rules(onto: $0) } ?? []
    }
}

nonisolated extension ItemDef {
    /// What joins a dyed piece's id to its dyes': "copper_plate~crimson_dye", its trim's after another
    /// ("copper_plate~crimson_dye~golden_dye", "copper_plate~~golden_dye" for the trim alone).
    static let dyeMark: Character = "~"

    /// A dyed piece's id in its parts: the piece, then its main dye and its trim's ("" for none).
    private static func parts(of id: String) -> [Substring] {
        id.split(separator: dyeMark, omittingEmptySubsequences: false)
    }

    /// The piece a dyed one was dyed from, or the id itself.
    static func baseID(of id: String) -> String {
        String(parts(of: id)[0])
    }

    /// The dye a dyed piece's main colour was dyed with, or nil.
    static func dyeID(of id: String) -> String? {
        let parts = parts(of: id)
        return parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
    }

    /// The dye a dyed piece's trim was dyed with, or nil.
    static func trimDyeID(of id: String) -> String? {
        let parts = parts(of: id)
        return parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
    }

    /// The id of `baseID` dyed with `dyeID`, and its trim with `trimID`: one colour as it always was,
    /// "<piece>~<dye>"; the piece itself with neither.
    static func dyedID(_ baseID: String, with dyeID: String?, trim trimID: String? = nil) -> String {
        guard let trimID else { return dyeID.map { baseID + String(dyeMark) + $0 } ?? baseID }
        return baseID + String(dyeMark) + (dyeID ?? "") + String(dyeMark) + trimID
    }

    /// The piece it was dyed from (its own id if it isn't dyed): what an armour's `headpiece` names.
    var baseID: String { Self.baseID(of: id) }
    /// The dye its main colour is dyed with, if it is.
    var dyeID: String? { Self.dyeID(of: id) }
    /// The dye its trim is dyed with, if it is.
    var trimDyeID: String? { Self.trimDyeID(of: id) }
    var isDyed: Bool { dyeID != nil || trimDyeID != nil }
    /// What its id has after its piece's ("~crimson_dye~golden_dye"), so its art's is the same: its icon
    /// "<art>~crimson_dye~golden_dye", a weapon's held sprites "held_<piece>_side~crimson_dye~golden_dye".
    var dyeSuffix: String {
        id.firstIndex(of: Self.dyeMark).map { String(id[$0...]) } ?? ""
    }

    /// Armour, a hat that goes with armour, gloves, boots and a weapon (playtesting 2026-10-30: "Also
    /// weapons should be dyed") take a dye; a festive hat (`hat`), a cape or a trinket doesn't. A weapon's
    /// icon and its held sprites (`GearArt`) are recoloured toward the dye from their own main colour.
    var canBeDyed: Bool {
        switch type {
        case .armor, .gloves, .boots, .weapon: true
        case .head: hat == nil
        default: false
        }
    }

    /// Whether its trim takes a dye too (playtesting 2026-10-30): a weapon's hilt or haft (one with a
    /// second colour, `DyeDef.oneColour`); armour drawn
    /// on the hero, its trim (`accent`); armour with sheets of its own, and the hats that go with it,
    /// where a sheet has a trim (`DyeDef.trims`: chain mail, a snow cloak, a ranger's hood haven't).
    /// Gloves and boots are one colour.
    var takesTrim: Bool {
        switch type {
        case .weapon:
            return !DyeDef.oneColour.contains(baseID)
        case .armor:
            guard let sheets else { return true }
            return sheets.values.contains { DyeDef.trims[$0] != nil }
        case .head:
            guard hat == nil, let headgear else { return false }
            return DyeDef.trims.keys.contains { $0.hasPrefix("hat_\(headgear)_") }
        default:
            return false
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

    /// Its trim over the sheet or hat `art` ("armor_iron_plate_human", "hat_iron_plate_elf"): the trim
    /// cut out of it ("<art>_trim", tools/dye_art.py) in its trim dye's colour. Nil when its trim isn't
    /// dyed, or that sheet has none.
    func trimLayer(over art: String) -> ArtLayer? {
        guard let trimDye, let material = DyeDef.trims[art] else { return nil }
        return ArtLayer(id: art + "_trim", recolor: trimDye.rules(onto: material))
    }

    /// How its sheet or hat `art` ("armor_iron_plate_dwarf", "hat_iron_plate_dwarf") is recoloured: in
    /// its main dye's colour, measured on that very sheet (`DyeDef.mains`), else its `tint` (a rare
    /// variant's, or a kind's own as a dye has it).
    func sheetTint(over art: String) -> [RecolorRule] {
        guard let mainDye, let kind = sheetKind else { return tint ?? [] }
        return mainDye.rules(for: kind, art: art)
    }

    /// This piece in its dyes' colours (`Content.item` makes it for "<id>~<dye id>~<trim dye id>"): the
    /// same piece, its name with the colours after it. Its main colour: its sheet or hat recoloured to the
    /// dye (`mainDye`, measured on each race's sheet, `sheetTint(over:)`; `tint` a kind's own, in place of
    /// a rare variant's: a dyed piece no longer shows its tier by its colour), the outfit under drawn-on
    /// armour too (`recolor`), and painted in it where it's painted (`color`: gloves, boots, a hide cloak).
    /// Its trim: a sheet's or hat's trim layer (`trimDye`, `trimLayer`), drawn-on armour's trim and a hide
    /// cloak's fur (`accent`). Its icon is its own recoloured the same way (`ArtLibrary`, the art
    /// "<art>~<dye id>~<trim dye id>").
    func dyed(main: (id: String, dye: DyeDef)?, trim: (id: String, dye: DyeDef)?) -> ItemDef {
        var copy = self
        copy.id = Self.dyedID(id, with: main?.id, trim: trim?.id)
        let colour: String
        if let main, let trim {
            colour = L("{colour} with {trim} trim", ["colour": main.dye.name, "trim": trim.dye.name])
        } else if let trim {
            colour = L("{colour} trim", ["colour": trim.dye.name])
        } else {
            colour = main?.dye.name ?? ""
        }
        copy.name = L("{item} ({colour})", ["item": name, "colour": colour])
        if let main {
            copy.mainDye = main.dye
            if let kind = sheetKind { copy.tint = main.dye.rules(for: kind) }
            if type == .armor { copy.recolor = main.dye.outfitRules() }
            if color != nil || type == .gloves || type == .boots || headgear == "hood" { copy.color = main.dye.color }
        }
        if let trim {
            copy.trimDye = trim.dye
            copy.accent = trim.dye.color
        }
        let suffix = copy.dyeSuffix
        copy.art = art.map { $0 + suffix }
        return copy
    }
}
