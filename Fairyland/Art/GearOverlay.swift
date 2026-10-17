import CoreGraphics
import Foundation

/// What the hero has on, beyond the outfit's colours: the cut of their armour, a cape, and their
/// gloves, boots and necklace.
nonisolated struct GearLook: Sendable, Hashable {
    /// The armour's cut (content/items.json `wear`): vest | mail | plate | robe | cloak.
    var wear: String?
    /// Trim colour for buttons, clasps and hems, "#RRGGBB" (`accent`).
    var accent: String?
    /// Finer work on stronger armour (`pattern`): engraved | scales | fur | runes | pockets.
    var pattern: String? = nil
    /// A status cape on the back (items.json type cape): its colour and its trim, "#RRGGBB".
    var cape: String? = nil
    var capeTrim: String? = nil
    /// Gloves, boots and a necklace, each in its colour (items.json `color`; a necklace's chain is
    /// its `accent`), "#RRGGBB".
    var gloves: String? = nil
    var boots: String? = nil
    var necklace: String? = nil
    var chain: String? = nil
    /// The plain body (art/sprites `body_*`, tools/hero_layers.py) the hands, chin and boots are found
    /// on: the hero's own, or their race's under armour with a walk sheet of its own, which is drawn
    /// on the same poses.
    var body: String? = nil

    var isPlain: Bool { wear == nil && cape == nil && gloves == nil && boots == nil && necklace == nil }
}

/// Draws worn gear onto a walk sheet, frame by frame. It finds the outfit (the green tunic) on the
/// original sheet, then on the recoloured sheet adds what that kind of armour looks like: chain
/// links, an open vest, pauldrons, a robe's long hem, a cape, and colours in a helmet or hood (drawn
/// by tools/hero_layers.py in place of the hair); then gloves, boots and a necklace in their colours.
/// tools/gear_preview.py is the same algorithm in Python, to tune it without a Mac.
enum GearOverlay {
    nonisolated static func apply(_ gear: GearLook, original: CGImage, dressed: CGImage, skeleton: CGImage? = nil,
                                  frame: Int = 48, directions: [String] = ["up", "right", "down", "left"]) -> CGImage? {
        guard !gear.isPlain, original.width == dressed.width, original.height == dressed.height,
              let base = Bitmap(original), var out = Bitmap(dressed) else { return dressed }
        var body = base
        if let skeleton, let plain = Bitmap(skeleton), plain.width == base.width, plain.height == base.height { body = plain }
        let accent = color(hex: gear.accent) ?? RGB(0.95, 0.78, 0.25)
        for (row, facing) in directions.enumerated() {
            for column in 0..<(base.width / frame) {
                dress(&out, base: base, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear, accent: accent)
                trinkets(&out, body: body, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear)
                if gear.cape != nil {
                    drape(&out, base: base, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear)
                }
            }
        }
        return out.image()
    }

    // MARK: A cape

    /// A status cape (items.json type cape) over whatever else is worn: from behind it hangs from the
    /// shoulders nearly to the feet, widening as it falls, its trim along the hem and its emblem (a
    /// diamond) on the back, the hair falling over its top; from the front and the side it shows past
    /// the body's outline, a clasp at the collar. It measures the body from its outline, the shoulders
    /// 0.38 of the way down from the top of the head to the feet (where the tunic starts on every
    /// race's sheet), so it fits armour with a sheet of its own too. tools/gear_preview.py `cape`.
    nonisolated private static func drape(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                          facing: String, gear: GearLook) {
        guard let colour = color(hex: gear.cape) else { return }
        let trim = color(hex: gear.capeTrim) ?? RGB(0.95, 0.78, 0.25)
        let dark = colour.scaled(0.62), light = colour.mixed(with: RGB(1, 1, 1), 0.3)
        let outline = RGB(0.16, 0.12, 0.18)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func put(_ x: Int, _ y: Int, _ c: RGB, onlyEmpty: Bool = false) {
            guard x >= 0, y >= 0, x < size, y < size, !onlyEmpty || !opaque(x, y) else { return }
            out.set(origin.x + x, origin.y + y, c)
        }
        let rows = (0..<size).filter { y in (0..<size).contains { opaque($0, y) } }
        guard let top = rows.first, let feet = rows.last, feet - top > 8 else { return }
        let shoulder = top + Int((Double(feet - top) * 0.38).rounded())
        let hem = feet - 3
        guard hem > shoulder + 2,
              let left = (0..<size).first(where: { opaque($0, shoulder) }),
              let right = (0..<size).last(where: { opaque($0, shoulder) }) else { return }
        let cx = (left + right) / 2
        /// Hair falling over the cape's top: bright and warm on the original sheet.
        func hair(_ x: Int, _ y: Int) -> Bool {
            guard y < shoulder + 11, opaque(x, y) else { return false }
            let (h, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
            return h >= 10 && h <= 65 && s > 0.4 && v > 0.6
        }
        if facing == "up" {
            for y in shoulder...hem {
                let widen = (y - shoulder) / 4
                let lo = left + 1 - widen, hi = right - 1 + widen
                guard lo < hi else { continue }
                for x in lo...hi where !hair(x, y) {
                    let c: RGB = x == lo || x == hi || y == hem ? outline
                        : y == hem - 1 ? trim : x == lo + 1 ? light : x == hi - 1 ? dark : colour
                    put(x, y, c)
                }
            }
            let emblem = shoulder + 6
            for dy in -2...2 {
                for dx in (abs(dy) - 2)...(2 - abs(dy)) where !hair(cx + dx, emblem + dy) {
                    put(cx + dx, emblem + dy, abs(dx) + abs(dy) < 2 ? trim : trim.scaled(0.7))
                }
            }
            return
        }
        for y in (shoulder + 1)...hem {
            guard let l = (0..<size).first(where: { opaque($0, y) }),
                  let r = (0..<size).last(where: { opaque($0, y) }) else { continue }
            // Out past the body's outline: a pixel at the shoulders, more toward the hem.
            let flare = 1 + (y - shoulder) / 4
            var spots: [(x: Int, outer: Bool)] = []
            switch facing {
            case "down":
                spots = [(l - flare, true), (r + flare, true)]
                for k in stride(from: 1, to: flare, by: 1) { spots += [(l - k, false), (r + k, false)] }
            case "right":
                spots = [(l - flare - 1, true)]
                for k in 1...flare { spots.append((l - k, false)) }
            default:
                spots = [(r + flare + 1, true)]
                for k in 1...flare { spots.append((r + k, false)) }
            }
            for spot in spots {
                put(spot.x, y, spot.outer ? outline : y == hem ? trim : colour, onlyEmpty: true)
            }
        }
        if facing == "down" {
            put(cx, shoulder, trim)
            put(cx - 1, shoulder, trim)
            put(cx, shoulder + 1, trim.scaled(0.7))
        }
    }

    // MARK: One frame

    nonisolated private static func dress(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                          facing: String, gear: GearLook, accent: RGB) {
        // Frame-local helpers. `opaque` and `outfit` read the original sheet.
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func outfit(_ x: Int, _ y: Int) -> Bool {
            guard opaque(x, y) else { return false }
            let (h, s, _) = hsv(base.rgb(origin.x + x, origin.y + y))
            return h >= 85 && h <= 170 && s >= 0.3
        }
        func put(_ x: Int, _ y: Int, _ c: RGB, onlyEmpty: Bool = false) {
            guard x >= 0, y >= 0, x < size, y < size, !onlyEmpty || !opaque(x, y) else { return }
            out.set(origin.x + x, origin.y + y, c)
        }

        var cells: [(x: Int, y: Int)] = []
        for y in 0..<size { for x in 0..<size where outfit(x, y) { cells.append((x, y)) } }
        guard let first = cells.first else { return }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for cell in cells {
            x0 = min(x0, cell.x); x1 = max(x1, cell.x); y0 = min(y0, cell.y); y1 = max(y1, cell.y)
        }
        var feet = 0
        for y in 0..<size where (0..<size).contains(where: { opaque($0, y) }) { feet = y }
        let mid = median(cells.map { out.rgb(origin.x + $0.x, origin.y + $0.y) })
        let dark = mid.scaled(0.55), light = mid.mixed(with: RGB(1, 1, 1), 0.35)
        let outline = RGB(0.16, 0.12, 0.18)
        let cx = (x0 + x1) / 2

        switch gear.wear {
        case "mail":
            // Chain links: a fine checker over the tunic.
            for cell in cells {
                if (cell.x + cell.y) % 2 == 0 {
                    out.set(origin.x + cell.x, origin.y + cell.y, light)
                } else if (cell.x + 2 * cell.y) % 4 == 1 {
                    out.set(origin.x + cell.x, origin.y + cell.y, dark)
                }
            }
        case "vest":
            // Worn open over a light shirt, with two buttons.
            guard facing == "down" else { break }
            for cell in cells where abs(cell.x - cx) <= 1 && cell.y < y1 - 1 {
                out.set(origin.x + cell.x, origin.y + cell.y, cell.x == cx ? RGB(0.8, 0.74, 0.62) : RGB(0.93, 0.88, 0.76))
            }
            put(cx - 2, y0 + 3, accent)
            put(cx + 2, y0 + 3, accent)
        case "plate":
            // Round pauldrons on the shoulders, lit from the top left, and a shine down the chest.
            let pads = switch facing {
            case "right": [x1 - 1]
            case "left": [x0 + 1]
            default: [x0 + 1, x1 - 1]
            }
            for px in pads {
                for dy in -1...2 {
                    for dx in -2...2 where Double(dx * dx) + pow(Double(dy) - 0.6, 2) * 1.6 <= 4.4 {
                        var c = dy <= 0 ? light : mid
                        if dy == 2 || (abs(dx) == 2 && dy >= 1) { c = dark }
                        put(px + dx, y0 + dy, c)
                    }
                }
                put(px - 1, y0 - 1, RGB(1, 1, 1))
            }
            if facing == "down" || facing == "up" {
                for y in (y0 + 3)..<max(y0 + 3, y1) where outfit(cx, y) { out.set(origin.x + cx, origin.y + y, light) }
                if facing == "down" { put(cx, y0 + 4, accent) }
            }
        case "robe":
            // The hem drops past the knees, flaring a little, with a trimmed edge.
            var bottom: [Int: Int] = [:]
            for cell in cells { bottom[cell.x] = max(bottom[cell.x] ?? 0, cell.y) }
            let hemTop = bottom.values.max() ?? y1
            let hemBottom = feet - 2
            let columns = bottom.filter { $0.value >= hemTop - 2 }.map(\.key)
            guard hemBottom > hemTop, let lx = columns.min(), let rx = columns.max() else { break }
            for y in (hemTop + 1)...hemBottom {
                let flare = (y - hemTop + 1) / 2
                for x in (lx - flare)...(rx + flare) {
                    put(x, y, x == lx - flare || x == rx + flare ? dark : mid)
                }
            }
            let flare = (hemBottom - hemTop + 1) / 2
            for x in (lx - flare)...(rx + flare) {
                put(x, hemBottom, dark)
                put(x, hemBottom - 1, accent)
            }
        case "cloak":
            let top = y0, hem = feet - 3
            guard hem > top else { break }
            if facing == "up" {
                // From behind: the cape covers the back, widening toward the hem.
                for y in top...hem {
                    let w = (y - top) / 3
                    for x in (x0 - w)...(x1 + w) {
                        let edge = x == x0 - w || x == x1 + w || y == hem
                        let furred = gear.pattern == "fur" && !edge && y >= hem - 2
                        put(x, y, furred ? fur(x, y) : edge ? outline : (x == cx - 2 ? light : mid))
                    }
                }
            } else {
                // From the front or side: the cape shows just outside the body's outline.
                for y in (top + 1)...hem {
                    guard let left = (0..<size).first(where: { opaque($0, y) }),
                          let right = (0..<size).last(where: { opaque($0, y) }) else { continue }
                    let flare = (y - top) / 5
                    // (x, whether it's the cape's outer edge)
                    var spots: [(Int, Bool)] = []
                    switch facing {
                    case "down":
                        spots = [(left - 1 - flare, true), (right + 1 + flare, true)]
                        if flare > 0 { spots += [(left - flare, false), (right + flare, false)] }
                    case "right":
                        spots = [(left - 1 - flare, true)]
                        for k in 0...flare { spots.append((left - k, false)) }
                    default:
                        spots = [(right + 1 + flare, true)]
                        for k in 0...flare { spots.append((right + k, false)) }
                    }
                    for (x, outer) in spots {
                        let furred = gear.pattern == "fur" && !outer && y >= hem - 2
                        put(x, y, furred ? fur(x, y) : outer ? outline : mid, onlyEmpty: true)
                    }
                }
                if facing == "down" {
                    put(cx, top, accent)
                    put(cx - 1, top, accent)
                    put(cx, top + 1, accent.scaled(0.7))
                }
            }
        default:
            break
        }
        // A helmet or hood (art/sprites/helmet_*, hood_*, stacked under the recolour) comes in magenta:
        // soft magenta takes the armour's colour, keeping its shade, and full magenta the trim.
        func isMark(_ x: Int, _ y: Int) -> Bool {
            guard opaque(x, y) else { return false }
            let (h, s, _) = hsv(base.rgb(origin.x + x, origin.y + y))
            return abs(h - 300) < 12 && s > 0.3
        }
        for y in 0..<size {
            for x in 0..<size where isMark(x, y) {
                let (_, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
                let c = s > 0.85 ? accent : v > 0.82 ? light : v < 0.55 ? dark : mid
                out.set(origin.x + x, origin.y + y, c)
            }
        }

        // Finer work on stronger armour (items.json `pattern`), drawn over the cut.
        let shine = mid.mixed(with: RGB(1, 1, 1), 0.45)
        let outfitCells = Set(cells.map { $0.y * size + $0.x })
        func inOutfit(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && outfitCells.contains(y * size + x)
        }
        func atEdge(_ x: Int, _ y: Int) -> Bool {
            !inOutfit(x + 1, y) || !inOutfit(x - 1, y) || !inOutfit(x, y + 1) || !inOutfit(x, y - 1)
        }
        func metalBoots(_ tint: RGB) {
            // Brown boots turn to armoured boots, keeping their shading.
            for y in max(0, feet - 5)...feet {
                for x in 0..<size where opaque(x, y) {
                    let (h, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
                    guard h >= 7, h <= 43, s > 0.35, v < 0.75 else { continue }
                    put(x, y, tint.scaled(0.55 + v * 0.9))
                }
            }
        }
        switch gear.pattern {
        case "engraved":
            // Overlapping plates (a dark seam every few rows, a rivet at each end) and a bright shine.
            for cell in cells where !atEdge(cell.x, cell.y) {
                if cell.y > y0 + 3 && (cell.y - y0) % 4 == 3 {
                    put(cell.x, cell.y, dark)
                } else if (facing == "down" || facing == "up") && cell.x == x0 + 2 {
                    put(cell.x, cell.y, shine)
                }
            }
            for y in stride(from: y0 + 7, to: y1, by: 4) {
                for x in [x0 + 1, x1 - 1] where inOutfit(x, y) { put(x, y, shine) }
            }
            metalBoots(RGB(0.62, 0.66, 0.74))
        case "scales":
            // Dragon scales: staggered rows of little arches, gold along the collar and hem, and horns.
            for cell in cells where !atEdge(cell.x, cell.y) {
                let row = (cell.y - y0) / 2
                let sx = (cell.x + 2 * (row % 2)) % 4
                if sx == 0 {
                    put(cell.x, cell.y, dark)
                } else if (cell.y - y0) % 2 == 0 && sx == 2 {
                    put(cell.x, cell.y, shine)
                }
            }
            var bottom: [Int: Int] = [:]
            for cell in cells { bottom[cell.x] = max(bottom[cell.x] ?? 0, cell.y) }
            for (x, y) in bottom { put(x, y, accent) }
            for cell in cells where cell.y == y0 { put(cell.x, cell.y, accent) }
            metalBoots(RGB(0.55, 0.16, 0.14))
            var marks: [(x: Int, y: Int)] = []
            for y in 0..<size { for x in 0..<size where isMark(x, y) { marks.append((x, y)) } }
            if let top = marks.map { $0.y }.min() {
                let row = marks.filter { $0.y == top + 2 }.map { $0.x }
                let xs = row.isEmpty ? marks.map { $0.x } : row
                if let left = xs.min(), let right = xs.max() {
                    let ivory = RGB(0.96, 0.91, 0.78), tip = RGB(0.72, 0.64, 0.5)
                    var horn: [(x: Int, y: Int)] = []
                    for (side, x) in [(-1, left), (1, right)] {
                        let points = [(x + side, top + 2, ivory), (x + side, top + 1, ivory),
                                      (x + 2 * side, top, ivory), (x + 2 * side, top - 1, tip)]
                        for (px, py, c) in points {
                            put(px, py, c)
                            horn.append((px, py))
                        }
                    }
                    for point in horn {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let x = point.x + dx, y = point.y + dy
                            if x >= 0, y >= 0, x < size, y < size, out.alpha(origin.x + x, origin.y + y) < 0.5 {
                                put(x, y, outline)
                            }
                        }
                    }
                }
            }
        case "fur":
            // White fur round the hood's opening (and the cape's hem, drawn with the cape).
            for y in 0..<size {
                for x in 0..<size where isMark(x, y) && hsv(base.rgb(origin.x + x, origin.y + y)).2 < 0.5 {
                    put(x, y, fur(x, y))
                }
            }
        case "runes":
            // Glowing runes: a stitched band down the front, and marks along the hem.
            let glow = accent.mixed(with: RGB(1, 1, 1), 0.3), mark = accent.mixed(with: RGB(1, 1, 1), 0.45)
            if facing == "down", y0 + 2 < feet - 2 {
                for y in (y0 + 2)..<(feet - 2) where opaque(cx, y) && y % 2 == 0 { put(cx, y, glow) }
            }
            let hem = feet - 4
            if hem >= 0 {
                for x in 0..<size where x % 3 == 0 && out.alpha(origin.x + x, origin.y + hem) > 0.5 {
                    let c = out.rgb(origin.x + x, origin.y + hem)
                    if abs(c.r - outline.r) > 0.05 || abs(c.g - outline.g) > 0.05 || abs(c.b - outline.b) > 0.05 {
                        put(x, hem, mark)
                    }
                }
            }
        case "pockets":
            // Two patch pockets with buttons, and a light collar.
            guard facing == "down" else { break }
            for px in [x0 + 1, x1 - 3] {
                for y in (y1 - 4)..<(y1 - 1) {
                    for x in px..<(px + 3) where inOutfit(x, y) {
                        let side = x == px || x == px + 2 || y == y1 - 2
                        put(x, y, y == y1 - 4 ? shine : side ? dark : mid.mixed(with: dark, 0.4))
                    }
                }
                put(px + 1, y1 - 4, accent)
            }
            for x in (cx - 2)...(cx + 2) where inOutfit(x, y0) { put(x, y0, shine) }
        default:
            break
        }
    }

    // MARK: Gloves, boots and a necklace

    /// Gloves on the hands, boots on the feet and a necklace under the chin, each in its colour at
    /// the brightness of what was there. They're found on the plain body: its skin in patches, the
    /// biggest the face (with the neck and ears) and those below its chin the arms, whose last three
    /// rows are the hands; the boots are its brown near the feet. Armour with a walk sheet of its own
    /// is drawn on the same poses, so they land on its gauntlets and greaves. tools/gear_preview.py
    /// `trinkets`.
    nonisolated private static func trinkets(_ out: inout Bitmap, body: Bitmap, origin: (x: Int, y: Int), size: Int,
                                             facing: String, gear: GearLook) {
        let gloves = color(hex: gear.gloves), boots = color(hex: gear.boots), necklace = color(hex: gear.necklace)
        guard gloves != nil || boots != nil || necklace != nil else { return }
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && body.alpha(origin.x + x, origin.y + y) > 0.5
        }
        /// Over what's drawn there (never into thin air): `c`, as bright as that was (`lift` + its value × `gain`).
        func paint(_ x: Int, _ y: Int, _ c: RGB, lift: Double, gain: Double) {
            guard x >= 0, y >= 0, x < size, y < size, out.alpha(origin.x + x, origin.y + y) > 0.5 else { return }
            out.set(origin.x + x, origin.y + y, c.scaled(lift + hsv(out.rgb(origin.x + x, origin.y + y)).2 * gain))
        }
        let rows = (0..<size).filter { y in (0..<size).contains { opaque($0, y) } }
        guard let top = rows.first, let feet = rows.last, feet - top > 8 else { return }
        if let boots {
            for y in max(0, feet - 5)...feet {
                for x in 0..<size where opaque(x, y) {
                    let (h, s, v) = hsv(body.rgb(origin.x + x, origin.y + y))
                    if h >= 7, h <= 43, s > 0.35, v < 0.75 { paint(x, y, boots, lift: 0.55, gain: 0.9) }
                }
            }
        }
        guard gloves != nil || necklace != nil else { return }
        var skin = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size where opaque(x, y) {
                let (h, s, v) = hsv(body.rgb(origin.x + x, origin.y + y))
                skin[y * size + x] = (h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55
            }
        }
        var seen = [Bool](repeating: false, count: size * size)
        var patches: [[(x: Int, y: Int)]] = []
        for start in 0..<(size * size) where skin[start] && !seen[start] {
            var stack = [start]
            var cells: [(x: Int, y: Int)] = []
            seen[start] = true
            while let i = stack.popLast() {
                let x = i % size, y = i / size
                cells.append((x, y))
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < size, ny < size, skin[ny * size + nx], !seen[ny * size + nx] else { continue }
                    seen[ny * size + nx] = true
                    stack.append(ny * size + nx)
                }
            }
            patches.append(cells)
        }
        guard let face = patches.indices.max(by: { patches[$0].count < patches[$1].count }),
              let chin = patches[face].map({ $0.y }).max() else { return }
        if let gloves {
            for (index, cells) in patches.enumerated() where index != face {
                guard let high = cells.map({ $0.y }).min(), high >= chin - 1, let low = cells.map({ $0.y }).max() else { continue }
                for cell in cells where cell.y >= low - 2 { paint(cell.x, cell.y, gloves, lift: 0.5, gain: 0.6) }
            }
        }
        // From the front: a chain in a V under the chin, the stone hanging from it.
        let under = patches[face].filter { $0.y == chin }.map { $0.x }
        if let necklace, facing == "down", let left = under.min(), let right = under.max() {
            let cx = (left + right) / 2
            let chain = color(hex: gear.chain) ?? RGB(0.95, 0.78, 0.25)
            func put(_ x: Int, _ y: Int, _ c: RGB) {
                guard x >= 0, y >= 0, x < size, y < size, out.alpha(origin.x + x, origin.y + y) > 0.5 else { return }
                out.set(origin.x + x, origin.y + y, c)
            }
            for (dx, dy) in [(-2, 1), (-1, 2), (1, 2), (2, 1)] { put(cx + dx, chin + dy, chain) }
            put(cx, chin + 2, necklace.mixed(with: RGB(1, 1, 1), 0.4))
            put(cx, chin + 3, necklace)
        }
    }

    /// Snowy fur: white with grey flecks.
    nonisolated private static func fur(_ x: Int, _ y: Int) -> RGB {
        (x * 7 + y * 3) % 5 == 0 ? RGB(0.78, 0.82, 0.88) : RGB(0.97, 0.98, 1.0)
    }

    // MARK: Colour helpers

    nonisolated struct RGB: Sendable {
        var r, g, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        func scaled(_ k: Double) -> RGB { RGB(min(1, r * k), min(1, g * k), min(1, b * k)) }
        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
        }
    }

    nonisolated private static func median(_ colors: [RGB]) -> RGB {
        func mid(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0.5 : sorted[sorted.count / 2]
        }
        return RGB(mid(colors.map(\.r)), mid(colors.map(\.g)), mid(colors.map(\.b)))
    }

    nonisolated private static func color(hex: String?) -> RGB? {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
        return RGB(Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    /// Hue in degrees, saturation and value in 0...1.
    nonisolated private static func hsv(_ c: RGB) -> (Double, Double, Double) {
        let maximum = max(c.r, c.g, c.b), minimum = min(c.r, c.g, c.b), delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == c.r { hue = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == c.g { hue = 60 * ((c.b - c.r) / delta + 2) }
            else { hue = 60 * ((c.r - c.g) / delta + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    // MARK: Pixels

    /// RGBA pixels, rows top to bottom like the image (premultiplied, as Core Graphics keeps them).
    nonisolated private struct Bitmap {
        let width: Int, height: Int
        var pixels: [UInt8]

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = data.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            pixels = data
        }

        func alpha(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + 3]) / 255 }

        func rgb(_ x: Int, _ y: Int) -> RGB {
            let i = (y * width + x) * 4
            let a = max(1, Double(pixels[i + 3]))
            return RGB(Double(pixels[i]) / a, Double(pixels[i + 1]) / a, Double(pixels[i + 2]) / a)
        }

        /// Paints a fully opaque pixel.
        mutating func set(_ x: Int, _ y: Int, _ c: RGB) {
            let i = (y * width + x) * 4
            pixels[i] = UInt8(max(0, min(255, (c.r * 255).rounded())))
            pixels[i + 1] = UInt8(max(0, min(255, (c.g * 255).rounded())))
            pixels[i + 2] = UInt8(max(0, min(255, (c.b * 255).rounded())))
            pixels[i + 3] = 255
        }

        func image() -> CGImage? {
            PixelImage.make(pixels, width: width, height: height)
        }
    }
}
