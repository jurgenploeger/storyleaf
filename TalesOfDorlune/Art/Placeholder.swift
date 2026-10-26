import CoreGraphics

/// Stand-in pixel art for every asset in art/assets.json. Used only when
/// art/sprites/<id>.png doesn't exist yet, so the game is always playable.
enum Placeholder {
    private static let ink = PixelColor(0x2B1B2E)

    static func canvas(for id: String, kind: String, direction: Direction = .down, frame: Int = 0) -> PixelCanvas {
        switch kind {
        case "walk_sheet":
            id.contains("pet") || id.contains("bunny") ? bunny(direction, frame: frame) : person(direction, frame: frame, palette: .hero)
        case "npc": person(.down, frame: 0, palette: .npc(id))
        case "tile": tile(id)
        case "prop": prop(id)
        case "building": id.contains("fence") ? fence() : house(roof: id.contains("guild") ? 0x3F6FD8 : 0xD84315)
        default: slime(for: id)
        }
    }

    /// How much placeholder canvases are scaled up to match real sprite sizes.
    static func scale(for kind: String) -> CGFloat {
        ["tile", "prop", "building"].contains(kind) ? 2 : 3
    }

    static func stableHash(_ text: String) -> UInt32 {
        text.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
    }

    // MARK: People — 16×16, drawn at 3× (48pt)

    struct Palette {
        var hair: PixelColor
        var tunic: PixelColor
        var boots: PixelColor

        static let hero = Palette(hair: PixelColor(0xE8812C), tunic: PixelColor(0x4CAF50), boots: PixelColor(0x6D4C41))

        static func npc(_ id: String) -> Palette {
            let hairs: [UInt32] = [0xF5F5F5, 0x5D4037, 0xFFD54F, 0x7E57C2, 0x263238, 0xD84315]
            let tunics: [UInt32] = [0xF06292, 0x42A5F5, 0x8D6E63, 0x78909C, 0x7E57C2, 0xFFB74D]
            let hash = Placeholder.stableHash(id)
            return Palette(hair: PixelColor(hairs[Int(hash % 6)]), tunic: PixelColor(tunics[Int((hash / 7) % 6)]), boots: PixelColor(0x4E342E))
        }
    }

    static func person(_ direction: Direction, frame: Int, palette: Palette) -> PixelCanvas {
        let skin = PixelColor(0xF7C9A0), belt = PixelColor(0x7B4A2A), blush = PixelColor(0xF48FB1)
        let hair = palette.hair, tunic = palette.tunic
        // Frames: stand, left foot up, stand, right foot up.
        let step = frame == 1 ? 1 : frame == 3 ? -1 : 0
        var c = PixelCanvas(width: 16, height: 16)

        let legX = direction.isHorizontal ? (6, 8) : (5, 9)
        c.fill(legX.0, 12, 2, 3 - max(0, step), palette.boots)
        c.fill(legX.1, 12, 2, 3 - max(0, -step), palette.boots)

        c.fill(4, 8, 8, 4, tunic)
        c.fill(4, 11, 8, 1, belt)
        if direction.isHorizontal {
            c.fill(6, 8, 2, 3, tunic.shaded(0.75))
        } else {
            c.fill(3, 8, 1, 3, skin)
            c.fill(12, 8, 1, 3, skin)
        }

        c.fill(4, 2, 8, 6, skin)
        c.fill(4, 1, 8, 2, hair)
        c.fill(3, 2, 1, 4, hair)
        c.fill(12, 2, 1, 4, hair)
        c[5, 0] = hair
        c[8, 0] = hair
        c[10, 0] = hair
        switch direction {
        case .down:
            c.fill(4, 3, 8, 1, hair)
            c.fill(6, 5, 1, 2, ink)
            c.fill(9, 5, 1, 2, ink)
            c[5, 7] = blush
            c[10, 7] = blush
        case .up:
            c.fill(4, 1, 8, 6, hair)
        case .left, .right:
            c.fill(4, 3, 8, 1, hair)
            c.fill(9, 2, 3, 5, hair)
            c.fill(5, 5, 1, 2, ink)
            c[5, 7] = blush
        }
        c.outline(ink)
        return direction == .right ? c.mirrored() : c
    }

    static func bunny(_ direction: Direction, frame: Int) -> PixelCanvas {
        let fur = PixelColor.white, shade = PixelColor(0xE3DDF2), pink = PixelColor(0xF8A5C2)
        let lift = frame % 2   // hop on odd frames
        var c = PixelCanvas(width: 16, height: 16)

        let earTop = 2 - lift
        if direction.isHorizontal {
            c.fill(8, earTop, 2, 6, fur)
            c.fill(10, earTop + 1, 2, 5, fur)
            c.fill(8, earTop + 1, 1, 4, pink)
        } else {
            c.fill(4, earTop, 2, 6, fur)
            c.fill(10, earTop, 2, 6, fur)
            if direction == .down {
                c.fill(5, earTop + 1, 1, 4, pink)
                c.fill(10, earTop + 1, 1, 4, pink)
            }
        }
        c.ellipse(8, 10.5 - Double(lift), 6, 4.5, fur)
        c.ellipse(8, 13 - Double(lift), 4, 1.6, shade)

        let eyeY = 9 - lift
        switch direction {
        case .down:
            c.fill(5, eyeY, 1, 2, ink)
            c.fill(10, eyeY, 1, 2, ink)
            c[4, eyeY + 2] = pink
            c[11, eyeY + 2] = pink
            c[7, eyeY + 2] = pink
            c[8, eyeY + 2] = pink
        case .up:
            c.fill(7, 12 - lift, 2, 2, shade)
        case .left, .right:
            c.fill(4, eyeY, 1, 2, ink)
            c[3, eyeY + 2] = pink
        }
        c.outline(ink)
        return direction == .right ? c.mirrored() : c
    }

    // MARK: Monsters — 16×16, drawn at 3×

    /// A slime whose colour comes from the asset id, so each monster type looks different.
    static func slime(for id: String) -> PixelCanvas {
        let palette: [UInt32] = [0xF48FB1, 0x81D4FA, 0xFFE082, 0xCE93D8, 0xA5D6A7, 0xFFAB91]
        let tint = PixelColor(palette[Int(stableHash(id) % UInt32(palette.count))])
        var c = PixelCanvas(width: 16, height: 16)
        c.ellipse(8, 10.5, 7, 4.5, tint)
        c.ellipse(8, 8.5, 5, 5, tint)
        c.ellipse(8, 12.5, 5.5, 2, tint.shaded(0.82))
        c.fill(5, 6, 2, 1, .white)
        c[5, 7] = .white
        c.fill(6, 9, 1, 2, ink)
        c.fill(9, 9, 1, 2, ink)
        c[7, 11] = ink
        c[8, 11] = ink
        c.outline(tint.shaded(0.4))
        return c
    }

    // MARK: Ground tiles — 16×16, drawn at 2× (32pt)

    static func tile(_ id: String) -> PixelCanvas {
        switch id {
        case _ where id.contains("dark_flowers"): flowers(on: darkGrass(seed: 7), colors: [0x80DEEA, 0xB39DDB, 0x4DD0E1, 0xE1BEE7])
        case _ where id.contains("dark_grass"): darkGrass(seed: 6)
        case _ where id.contains("flowers"): flowers(on: grass(seed: 3), colors: [0xF48FB1, 0xFFF59D, 0xFFFFFF, 0x90CAF9])
        case _ where id.contains("shells"): shells()
        case _ where id.contains("sand"): speckled(base: 0xF2D78F, dark: 0xE2C57A, light: 0xFBE8B0, seed: 8)
        case _ where id.contains("town"): cobbles()
        case _ where id.contains("path"): path()
        case _ where id.contains("water"): water(frame: 0)
        default: grass(seed: 1)
        }
    }

    /// Two frames of gently rippling water.
    static func water(frame: Int) -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.fill(0, 0, 16, 16, PixelColor(0x4FA3E0))
        let light = PixelColor(0x8FD0F5), deep = PixelColor(0x3A86C8)
        let shift = frame == 0 ? 0 : 3
        for (x, y) in [(2, 3), (9, 6), (5, 11), (12, 13)] {
            c.fill((x + shift) % 16, y, 3, 1, light)
        }
        for (x, y) in [(11, 2), (1, 8), (8, 14)] {
            c.fill((x + 16 - shift) % 16, y, 2, 1, deep)
        }
        return c
    }

    private static func grass(seed: UInt64) -> PixelCanvas {
        var c = speckled(base: 0x5DBB4C, dark: 0x4CA23E, light: 0x7ACF63, seed: seed)
        tufts(&c, color: PixelColor(0x3F8F34))
        return c
    }

    private static func darkGrass(seed: UInt64) -> PixelCanvas {
        var c = speckled(base: 0x2E5E5A, dark: 0x244C49, light: 0x3B716B, seed: seed)
        tufts(&c, color: PixelColor(0x1C3D3A))
        return c
    }

    private static func tufts(_ c: inout PixelCanvas, color: PixelColor) {
        for (x, y) in [(4, 6), (12, 11), (9, 2)] {
            c[x, y] = color
            c[x - 1, y - 1] = color
            c[x + 1, y - 1] = color
        }
    }

    private static func flowers(on base: PixelCanvas, colors: [UInt32]) -> PixelCanvas {
        var c = base
        for (index, (x, y)) in [(3, 3), (11, 5), (6, 11), (13, 13)].enumerated() {
            let petal = PixelColor(colors[index % colors.count])
            c[x - 1, y] = petal
            c[x + 1, y] = petal
            c[x, y - 1] = petal
            c[x, y + 1] = petal
            c[x, y] = PixelColor(0xFFD54F)
        }
        return c
    }

    private static func path() -> PixelCanvas {
        var c = speckled(base: 0xD9B77A, dark: 0xC29B62, light: 0xEBD29F, seed: 2)
        for (x, y) in [(3, 4), (11, 2), (8, 10), (13, 13), (2, 12)] {
            c[x, y] = PixelColor(0xA88652)
            c[x + 1, y] = PixelColor(0xF3E0B5)
        }
        return c
    }

    private static func shells() -> PixelCanvas {
        var c = speckled(base: 0xF2D78F, dark: 0xE2C57A, light: 0xFBE8B0, seed: 9)
        for (x, y) in [(4, 4), (11, 10)] {
            c.fill(x, y, 2, 1, PixelColor(0xF8BBD0))
            c.fill(x - 1, y + 1, 4, 1, PixelColor(0xF48FB1))
        }
        return c
    }

    private static func cobbles() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.fill(0, 0, 16, 16, PixelColor(0xD8CDBB))
        let mortar = PixelColor(0xB8AC98)
        for y in [0, 5, 10, 15] { c.fill(0, y, 16, 1, mortar) }
        for (row, y) in [0, 5, 10].enumerated() {
            let shift = row % 2 == 0 ? 0 : 4
            for x in stride(from: shift, to: 16, by: 8) { c.fill(x, y, 1, 5, mortar) }
        }
        c[3, 2] = PixelColor(0xE8DFD0)
        c[11, 7] = PixelColor(0xE8DFD0)
        c[6, 12] = PixelColor(0xE8DFD0)
        return c
    }

    private static func speckled(base: UInt32, dark: UInt32, light: UInt32, seed: UInt64) -> PixelCanvas {
        var rng = SeededRandom(seed: seed)
        var c = PixelCanvas(width: 16, height: 16)
        c.fill(0, 0, 16, 16, PixelColor(base))
        for (count, color) in [(22, dark), (12, light)] {
            for _ in 0..<count {
                c[Int.random(in: 0..<16, using: &rng), Int.random(in: 0..<16, using: &rng)] = PixelColor(color)
            }
        }
        return c
    }

    // MARK: Scenery — drawn at 2×

    static func prop(_ id: String) -> PixelCanvas {
        switch id {
        case _ where id.contains("blossom"): tree(canopy: 0xF8A5C2, light: 0xFCD3E1, dark: 0xE57FA5, outline: 0x7A2E4E)
        case _ where id.contains("giant_flower"): giantFlower()
        case _ where id.contains("crystal"): crystal()
        case _ where id.contains("sandcastle"): sandcastle()
        case _ where id.contains("fountain"): fountain()
        case _ where id.contains("lily"): lilyPad()
        case _ where id.contains("gift"): giftBox()
        case _ where id.contains("egg"): egg()
        case _ where id.contains("palm"): palmTree()
        case _ where id.contains("dark_tree"): tree(canopy: 0x5E4B8B, light: 0x7E68B0, dark: 0x45366A, outline: 0x241B38)
        case _ where id.contains("tree"): tree(canopy: 0x3FA34D, light: 0x5CC163, dark: 0x2F8A3F, outline: 0x1E3B22)
        case _ where id.contains("rock") || id.contains("stone"): rock()
        case _ where id.contains("glow"): mushroom(cap: 0x4DD0E1, spots: 0xE0F7FA)
        default: mushroom(cap: 0xE53935, spots: 0xFFFFFF)
        }
    }

    private static func tree(canopy: UInt32, light: UInt32, dark: UInt32, outline: UInt32) -> PixelCanvas {
        var c = PixelCanvas(width: 32, height: 32)
        c.fill(13, 20, 6, 10, PixelColor(0x8D5A34))
        c.fill(13, 20, 2, 10, PixelColor(0x6D4226))
        c.ellipse(16, 12, 12, 10, PixelColor(canopy))
        c.ellipse(21, 15, 6, 5, PixelColor(dark))
        c.ellipse(12, 9, 6, 5, PixelColor(light))
        c.outline(PixelColor(outline))
        return c
    }

    private static func palmTree() -> PixelCanvas {
        var c = PixelCanvas(width: 32, height: 32)
        let trunk = PixelColor(0xA1774A), ring = PixelColor(0x7A5634), leaf = PixelColor(0x43A047), leafLight = PixelColor(0x66BB6A)
        for y in 12..<30 {
            let x = 15 + (30 - y) / 7
            c.fill(x, y, 3, 1, y % 3 == 0 ? ring : trunk)
        }
        c.ellipse(9, 9, 8, 3, leaf)
        c.ellipse(24, 9, 8, 3, leaf)
        c.ellipse(12, 5, 6, 3, leafLight)
        c.ellipse(21, 5, 6, 3, leafLight)
        c.ellipse(17, 8, 4, 4, leaf)
        c.fill(15, 11, 2, 2, PixelColor(0x6D4C41))
        c.fill(18, 11, 2, 2, PixelColor(0x6D4C41))
        c.outline(PixelColor(0x1E3B22))
        return c
    }

    private static func giantFlower() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 24)
        c.fill(7, 10, 2, 13, PixelColor(0x43A047))
        c.ellipse(4.5, 16, 3, 1.5, PixelColor(0x66BB6A))
        c.ellipse(11.5, 13, 3, 1.5, PixelColor(0x66BB6A))
        let petal = PixelColor(0xFFB3D1)
        for (x, y) in [(8.0, 2.5), (8.0, 9.5), (4.5, 6.0), (11.5, 6.0), (5.5, 3.5), (10.5, 3.5), (5.5, 8.5), (10.5, 8.5)] {
            c.ellipse(x, y, 2.4, 2.4, petal)
        }
        c.ellipse(8, 6, 2.6, 2.6, PixelColor(0xFFD54F))
        c[7, 5] = PixelColor(0xFFF59D)
        c.outline(PixelColor(0x7A2E4E))
        return c
    }

    private static func crystal() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        let body = PixelColor(0x80DEEA), light = PixelColor(0xE0F7FA), dark = PixelColor(0x26A69A)
        for (x, top, width) in [(6, 1, 4), (2, 6, 3), (11, 5, 3)] {
            for y in top..<15 {
                let inset = max(0, 2 - (y - top))
                c.fill(x + inset / 2, y, max(1, width - inset), 1, body)
            }
            c.fill(x, top + 2, 1, 15 - top - 2, light)
            c.fill(x + width - 1, top + 3, 1, 15 - top - 3, dark)
        }
        c.outline(PixelColor(0x1A3A4A))
        return c
    }

    private static func sandcastle() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        let sand = PixelColor(0xE8C36A), shade = PixelColor(0xC9A24E)
        c.fill(2, 8, 12, 7, sand)
        c.fill(2, 13, 12, 2, shade)
        c.fill(5, 4, 6, 4, sand)
        for x in [2, 4, 11, 13] { c.fill(x, 7, 1, 1, sand) }
        c.fill(6, 3, 1, 1, sand)
        c.fill(9, 3, 1, 1, sand)
        c.fill(7, 10, 2, 5, PixelColor(0x8D6E63))
        c.fill(8, 0, 1, 4, PixelColor(0x6D4C41))
        c.fill(9, 0, 3, 2, PixelColor(0xE53935))
        c.outline(PixelColor(0x6D4C41))
        return c
    }

    private static func fountain() -> PixelCanvas {
        var c = PixelCanvas(width: 48, height: 32)
        let stone = PixelColor(0xCFC6B8), stoneDark = PixelColor(0xA89F90), water = PixelColor(0x6EC6F0), light = PixelColor(0xC8ECFF)
        c.ellipse(24, 23, 22, 8, stone)
        c.ellipse(24, 22, 18, 5.5, water)
        c.fill(4, 23, 40, 5, stoneDark)
        c.ellipse(24, 28, 20, 3, stoneDark)
        c.fill(21, 8, 6, 14, stone)
        c.ellipse(24, 8, 7, 3, stone)
        c.ellipse(24, 7.5, 5, 2, water)
        c.fill(23, 1, 2, 6, light)
        for (x, y) in [(18, 20), (30, 21), (24, 24)] { c.fill(x, y, 3, 1, light) }
        c.outline(PixelColor(0x5D5448))
        return c
    }

    private static func giftBox() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        let box = PixelColor(0x64B5F6), boxDark = PixelColor(0x3A86C8), ribbon = PixelColor(0xE53935)
        c.fill(2, 7, 12, 8, box)
        c.fill(2, 12, 12, 3, boxDark)
        c.fill(1, 5, 14, 3, PixelColor(0x90CAF9))
        c.fill(7, 5, 2, 10, ribbon)
        c.fill(1, 6, 14, 1, ribbon)
        c.ellipse(5.5, 3.5, 2.5, 1.8, ribbon)
        c.ellipse(10.5, 3.5, 2.5, 1.8, ribbon)
        c[7, 4] = PixelColor(0xB71C1C)
        c[8, 4] = PixelColor(0xB71C1C)
        c.outline(ink)
        return c
    }

    private static func egg() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.ellipse(8, 9, 5.5, 6.5, PixelColor(0xFFF8E1))
        c.ellipse(9.5, 11, 3.5, 3.5, PixelColor(0xF3E5C8))
        for (x, y, color) in [(6, 5, 0xF8A5C2), (10, 8, 0x90CAF9), (6, 11, 0xFFE082), (9, 13, 0xF8A5C2)] as [(Int, Int, UInt32)] {
            c.fill(x, y, 2, 2, PixelColor(color))
        }
        c[6, 4] = .white
        c.outline(PixelColor(0x6D4C41))
        return c
    }

    private static func lilyPad() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.ellipse(8, 9, 6, 4, PixelColor(0x5DBB4C))
        c.ellipse(8, 9, 4, 2.5, PixelColor(0x7ACF63))
        c.fill(8, 5, 1, 4, PixelColor(0x4FA3E0))
        c.fill(9, 6, 1, 3, PixelColor(0x4FA3E0))
        c.ellipse(5, 7, 1.6, 1.6, PixelColor(0xF8A5C2))
        c[5, 7] = PixelColor(0xFFF59D)
        c.outline(PixelColor(0x2E6B2A))
        return c
    }

    private static func rock() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.ellipse(8, 10, 7, 5, PixelColor(0x9E9E9E))
        c.ellipse(9, 12, 5, 2.5, PixelColor(0x858585))
        c.ellipse(6, 8.5, 3, 2, PixelColor(0xC4C4C4))
        c.ellipse(9, 6.5, 4, 1.5, PixelColor(0x6CAF4F))
        c.outline(PixelColor(0x3A3A3A))
        return c
    }

    private static func mushroom(cap: UInt32, spots: UInt32) -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        c.ellipse(8, 7.5, 6.5, 4.5, PixelColor(cap))
        c.fill(6, 10, 4, 4, PixelColor(0xF3E5CF))
        for (x, y) in [(5, 5), (6, 5), (10, 6), (8, 4)] {
            c[x, y] = PixelColor(spots)
        }
        c.outline(ink)
        return c
    }

    // MARK: Buildings — drawn at 2×

    private static func house(roof: UInt32) -> PixelCanvas {
        var c = PixelCanvas(width: 48, height: 48)
        let wall = PixelColor(0xF3E5CF), wallShade = PixelColor(0xDCC9AA), roofColor = PixelColor(roof)
        c.fill(8, 24, 32, 22, wall)
        c.fill(8, 40, 32, 6, wallShade)
        for y in 4..<25 {
            let half = 4 + (y - 4)
            c.fill(24 - half, y, half * 2, 1, y % 4 == 0 ? roofColor.shaded(0.8) : roofColor)
        }
        c.fill(32, 6, 4, 8, PixelColor(0x8D6E63))
        c.fill(20, 32, 8, 14, PixelColor(0x8D5A34))
        c[26, 39] = PixelColor(0xFFD54F)
        for x in [11, 31] {
            c.fill(x, 29, 6, 6, PixelColor(0x90CAF9))
            c.fill(x + 2, 29, 1, 6, wall)
            c.fill(x, 31, 6, 1, wall)
        }
        c.outline(ink)
        return c
    }

    private static func fence() -> PixelCanvas {
        var c = PixelCanvas(width: 16, height: 16)
        let wood = PixelColor(0xA1887F)
        c.fill(2, 4, 2, 11, wood)
        c.fill(12, 4, 2, 11, wood)
        c.fill(0, 7, 16, 2, wood)
        c.fill(0, 11, 16, 2, wood)
        c.outline(PixelColor(0x5D4037))
        return c
    }
}
