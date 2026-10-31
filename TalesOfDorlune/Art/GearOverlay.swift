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
    /// A hide cloak's colour (an armour with `wear` cloak and no walk sheet of its own), "#RRGGBB":
    /// it hangs as a status cape does (`drape`), its fur (`accent`) along the hem.
    var cloak: String? = nil
    /// Gloves, boots and a necklace, each in its colour (items.json `color`; a necklace's chain is
    /// its `accent`), "#RRGGBB".
    var gloves: String? = nil
    var boots: String? = nil
    var necklace: String? = nil
    var chain: String? = nil
    /// A festive hat (items.json type head): how it's drawn (`ItemDef.hat`: crown | santa | ears |
    /// mask), its colour and its trim (a bunny's ears' pink), "#RRGGBB".
    var hat: String? = nil
    var hatColor: String? = nil
    var hatTrim: String? = nil
    /// A festive scarf round the neck (a necklace that wears `scarf`), in its colour, "#RRGGBB", in place
    /// of a necklace.
    var scarf: String? = nil
    /// A hood worn as a hat (one that goes with a hide cloak, items.json `headgear` hood): its colour
    /// and trim, "#RRGGBB", and whether it's lined with fur round its opening (`pattern` fur).
    var hood: String? = nil
    var hoodTrim: String? = nil
    var hoodFur = false
    /// The plain body (art/sprites `body_*`, tools/hero_layers.py) the hands, chin and boots are found
    /// on: the hero's own, or their race's under armour with a walk sheet of its own, which is drawn
    /// on the same poses.
    var body: String? = nil

    var isPlain: Bool {
        wear == nil && cape == nil && cloak == nil && gloves == nil && boots == nil && necklace == nil && hat == nil && scarf == nil && hood == nil
    }
}

/// Draws worn gear onto a walk sheet, frame by frame. It finds the outfit (the green tunic) on the
/// original sheet, then on the recoloured sheet adds what that kind of armour looks like: chain
/// links, an open vest, pauldrons, a robe's long hem, a cape, and colours in a helmet or hood (drawn
/// by tools/hero_layers.py in place of the hair); then gloves, boots and a necklace in their colours,
/// and a festive hat over everything.
/// tools/gear_preview.py is the same algorithm in Python, to tune it without a Mac.
enum GearOverlay {
    /// `piece` is a festive hat's (GearLook.hat), `capePiece` a status cape's and `scarfPiece` a scarf's,
    /// as tools/wear_art.py cut them out: a frame a row, one row for each of `directions`.
    nonisolated static func apply(_ gear: GearLook, original: CGImage, dressed: CGImage, skeleton: CGImage? = nil,
                                  piece: CGImage? = nil, capePiece: CGImage? = nil, scarfPiece: CGImage? = nil, frame: Int = 48,
                                  directions: [String] = ["up", "right", "down", "left"]) -> CGImage? {
        guard !gear.isPlain, original.width == dressed.width, original.height == dressed.height,
              let base = Bitmap(original), var out = Bitmap(dressed) else { return dressed }
        var body = base
        if let skeleton, let plain = Bitmap(skeleton), plain.width == base.width, plain.height == base.height { body = plain }
        let accent = color(hex: gear.accent) ?? RGB(0.95, 0.78, 0.25)
        var pieces: [Piece] = []
        if let piece, let sheet = Bitmap(piece), sheet.width == frame, sheet.height >= frame * directions.count,
           let colour = color(hex: gear.hatColor) {
            pieces = directions.indices.map { Self.painted(sheet, row: $0, size: frame, colour: color(hex: gear.hatTrim) ?? colour) }
        }
        var scarves: [Piece] = []
        if let scarfPiece, let sheet = Bitmap(scarfPiece), sheet.width == frame, sheet.height >= frame * directions.count,
           let colour = color(hex: gear.scarf) {
            scarves = directions.indices.map { Self.painted(sheet, row: $0, size: frame, colour: colour) }
        }
        // The frame a scarf finds the chin on from behind: the one facing you.
        let frontRow = directions.firstIndex(of: "down")
        var capes: [Piece] = []
        let capeTrim = color(hex: gear.capeTrim) ?? RGB(0.95, 0.78, 0.25)
        if let capePiece, let sheet = Bitmap(capePiece), sheet.width == frame, sheet.height >= frame * directions.count,
           let colour = color(hex: gear.cape) {
            capes = directions.indices.map { Self.cape(sheet, row: $0, size: frame, colour: colour, trim: capeTrim) }
        }
        // A hide cloak is the same cape in its own colour, its fur along the hem (playtesting
        // 2026-10-22: drawn as a plain trapezoid of its own, it looked blocky beside the capes).
        var cloaks: [Piece] = []
        if let capePiece, let sheet = Bitmap(capePiece), sheet.width == frame, sheet.height >= frame * directions.count,
           let colour = color(hex: gear.cloak) {
            cloaks = directions.indices.map { Self.cape(sheet, row: $0, size: frame, colour: colour, trim: accent) }
        }
        for (row, facing) in directions.enumerated() {
            // A cape's span, as wide as the body gets across the walk this way and round its middle
            // across them, measured on the plain body (`drape`).
            let figures = (0..<(base.width / frame)).compactMap { Self.figure(body, origin: ($0 * frame, row * frame), size: frame) }
            let span = figures.isEmpty ? nil : (left: figures.map { $0.left }.min() ?? 0, right: figures.map { $0.right }.max() ?? 0)
            for column in 0..<(base.width / frame) {
                dress(&out, base: base, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear, accent: accent)
                if gear.hood != nil { hood(&out, base: base, origin: (column * frame, row * frame), size: frame, gear: gear) }
                trinkets(&out, body: body, origin: (column * frame, row * frame), size: frame, facing: facing, gear: gear)
                if let colour = color(hex: gear.cloak), row < cloaks.count {
                    drape(&out, base: base, body: body, span: span, origin: (column * frame, row * frame), size: frame,
                          facing: facing, piece: cloaks[row], colour: colour, trim: accent, emblem: false)
                }
                if let colour = color(hex: gear.cape), row < capes.count {
                    drape(&out, base: base, body: body, span: span, origin: (column * frame, row * frame), size: frame,
                          facing: facing, piece: capes[row], colour: colour, trim: capeTrim, emblem: true)
                }
                if gear.scarf != nil, row < scarves.count {
                    scarf(&out, body: body, base: base, origin: (column * frame, row * frame), size: frame, facing: facing,
                          piece: scarves[row], front: (column * frame, (frontRow ?? row) * frame))
                }
                if gear.hat != nil, row < pieces.count {
                    hat(&out, body: body, base: base, origin: (column * frame, row * frame), size: frame, facing: facing,
                        kind: gear.hat ?? "", piece: pieces[row])
                }
            }
        }
        return out.image()
    }

    // MARK: A cape

    /// A status cape (items.json type cape) over whatever else is worn: the cape Retro Diffusion drew
    /// (art/sprites/wear_cape.png, cut out by tools/wear_art.py) in its colour, its trim along the hem,
    /// stretched to the body: its shoulders 0.38 of the way down from the top of the head to the feet
    /// (where the tunic starts on every race's sheet), as wide as it is there, and as long down to the
    /// feet, measured from its outline so it fits armour with a sheet of its own too. From behind it
    /// hangs over the body, the hair falling over its top, its emblem (a diamond) on the back; from
    /// the front and the side it shows past the body's outline, a clasp at the collar. Resized evenly
    /// (`Piece.spread`), so it's the same shape on every body. tools/gear_preview.py `cape`.
    /// A hide cloak hangs the same way, in its colour, with no emblem (`emblem` false). The body is
    /// measured on `body` (the plain bald body, GearLook.body), so tall hair doesn't lift the shoulders
    /// and the clasp onto the face; its width and middle are `span`, the same for every frame of the
    /// walk this way: measured frame by frame, an arm swung out at the shoulders moved and narrowed the
    /// cape, and a gap showed where the arm had been (playtesting 2026-10-22).
    nonisolated private static func drape(_ out: inout Bitmap, base: Bitmap, body: Bitmap, span: (left: Int, right: Int)?,
                                          origin: (x: Int, y: Int), size: Int, facing: String, piece: Piece,
                                          colour: RGB, trim: RGB, emblem: Bool) {
        guard piece.box != nil, let measured = Self.figure(body, origin: origin, size: size) else { return }
        let figure = (feet: measured.feet, shoulder: measured.shoulder,
                      left: span?.left ?? measured.left, right: span?.right ?? measured.right)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func put(_ x: Int, _ y: Int, _ c: RGB, onlyEmpty: Bool = false) {
            guard x >= 0, y >= 0, x < size, y < size, !onlyEmpty || !opaque(x, y) else { return }
            out.set(origin.x + x, origin.y + y, c)
        }
        let shoulder = figure.shoulder, cx = (figure.left + figure.right) / 2
        /// Hair falling over the cape's top: bright and warm on the original sheet.
        func hair(_ x: Int, _ y: Int) -> Bool {
            guard y < shoulder + 11, opaque(x, y) else { return false }
            let (h, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
            return h >= 10 && h <= 65 && s > 0.4 && v > 0.6
        }
        // From the front and the side a little wider than the body, so it shows past its outline.
        let flare = facing == "up" ? 0 : facing == "down" ? 4 : 2
        // From behind it hangs from just under the head (`capeRise` over the shoulder line), over the
        // shoulders, down to the feet: from the shoulder line the armour's shoulders showed above it
        // (playtesting 2026-10-24).
        let hang = facing == "up" ? shoulder - capeRise : shoulder
        // Resized evenly, not through its middle, so it keeps its outline on every body (`spread`).
        let fitted = piece.scaledDown(by: (figure.feet - hang) - capeDrop, start: shoulderY)
            .scaledAcross(by: (figure.right - figure.left + 1) - capeSpan + flare)
        let dy = hang - shoulderY, dx = cx - anchorX
        for y in 0..<size {
            for x in 0..<size {
                guard let c = fitted[x: x, y: y] else { continue }
                if facing == "up" {
                    if !hair(x + dx, y + dy) { put(x + dx, y + dy, c) }
                } else {
                    put(x + dx, y + dy, c, onlyEmpty: true)
                }
            }
        }
        if facing != "up" {
            lining(&out, base: base, origin: origin, size: size, fitted: fitted, dx: dx, dy: dy, shoulder: shoulder,
                   colour: colour, trim: trim, front: facing == "down")
        }
        if facing == "up", emblem {
            let emblem = shoulder + 6
            for ey in -2...2 {
                for ex in (abs(ey) - 2)...(2 - abs(ey)) where !hair(cx + ex, emblem + ey) {
                    put(cx + ex, emblem + ey, abs(ex) + abs(ey) < 2 ? trim : trim.scaled(0.7))
                }
            }
        } else if facing == "down" {
            put(cx, shoulder, trim)
            put(cx - 1, shoulder, trim)
            put(cx, shoulder + 1, trim.scaled(0.7))
        }
    }

    /// How far past its edge a cape's lining reaches to meet the body (from the side).
    nonisolated private static let capeReach = 4
    /// From behind, how far over the shoulder line (`figure`) a cape's top sits: under the head.
    nonisolated private static let capeRise = 3

    /// A cape's inside, seen from the front or the side wherever the body doesn't cover it: on each
    /// row below the shoulders, every gap within the cape's own span (between its panels, between an
    /// arm swung out and the body), and a gap of up to `capeReach` pixels between its edge and the body
    /// (from the side, where the back leans away from it). Dark in the cape's colour; along its bottom
    /// two rows, its trim and outline, so the hem runs on unbroken (playtesting 2026-10-21: "the cloaks
    /// still have a gap depending on what they wear or their arm position"). From the side only what
    /// shows of it counts: the part hidden behind the body reaches under the legs, and nothing hangs
    /// between them there. Last, any clear pixel it has closed in (one the bare figure didn't), as
    /// between an arm and the back above where it shows, is its inside too. tools/gear_preview.py `lining`.
    nonisolated private static func lining(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                           fitted: Piece, dx: Int, dy: Int, shoulder: Int, colour: RGB, trim: RGB,
                                           front: Bool) {
        func body(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        var rows: [Int: [Int]] = [:]
        for y in 0..<size {
            for x in 0..<size where fitted[x: x, y: y] != nil && (front || !body(x + dx, y + dy)) {
                rows[y + dy, default: []].append(x + dx)
            }
        }
        guard let bottom = rows.keys.max() else { return }
        let inside = colour.scaled(0.45), outline = RGB(0.16, 0.12, 0.18)
        func tone(_ y: Int) -> RGB { y == bottom ? outline : y == bottom - 1 ? trim : inside }
        for (y, xs) in rows where y > shoulder && y >= 0 && y < size {
            guard let lo = xs.min(), let hi = xs.max() else { continue }
            var fill = Array(lo...hi)
            for (start, step) in [(lo - 1, -1), (hi + 1, 1)] {
                var gap: [Int] = []
                var x = start
                while gap.count < capeReach, x >= 0, x < size, !body(x, y) {
                    gap.append(x)
                    x += step
                }
                if body(x, y) { fill += gap }
            }
            let own = Set(xs)
            for x in fill where x >= 0 && x < size && !body(x, y) && !own.contains(x) {
                out.set(origin.x + x, origin.y + y, tone(y))
            }
        }
        let before = enclosed(size) { !body($0, $1) }
        let after = enclosed(size) { out.alpha(origin.x + $0, origin.y + $1) < 0.5 }
        for (index, closed) in after.enumerated() where closed && !before[index] {
            out.set(origin.x + index % size, origin.y + index / size, tone(index / size))
        }
    }

    /// Which pixels of a `size`-square frame are `clear` but can't be reached from its edge through
    /// clear pixels (4 ways), row by row. tools/gear_preview.py `enclosed`.
    nonisolated private static func enclosed(_ size: Int, _ clear: (Int, Int) -> Bool) -> [Bool] {
        var open = [Bool](repeating: false, count: size * size)
        for y in 0..<size { for x in 0..<size { open[y * size + x] = clear(x, y) } }
        var reached = [Bool](repeating: false, count: size * size)
        var stack: [(Int, Int)] = []
        for i in 0..<size { stack += [(i, 0), (i, size - 1), (0, i), (size - 1, i)] }
        while let point = stack.popLast() {
            let (x, y) = point
            guard x >= 0, y >= 0, x < size, y < size, open[y * size + x], !reached[y * size + x] else { continue }
            reached[y * size + x] = true
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        }
        return (0..<(size * size)).map { open[$0] && !reached[$0] }
    }

    /// Row `row` of the cape's sheet in a cape's colours (`painted`, its deepest shadows too), its trim
    /// on the lowest coloured pixel of each column with an outline under it.
    nonisolated private static func cape(_ sheet: Bitmap, row: Int, size: Int, colour: RGB, trim: RGB) -> Piece {
        var piece = painted(sheet, row: row, size: size, colour: colour, floor: capeFloor)
        let outline = RGB(0.16, 0.12, 0.18)
        for x in 0..<size {
            let coloured = (0..<size).filter { y in
                guard sheet.alpha(x, row * size + y) > 0.5 else { return false }
                let (_, s, v) = hsv(sheet.rgb(x, row * size + y))
                return s > 0.2 && v > capeFloor
            }
            guard let hem = coloured.max() else { continue }
            piece.pixels[hem * size + x] = trim
            if hem + 1 < size, piece.pixels[(hem + 1) * size + x] == nil { piece.pixels[(hem + 1) * size + x] = outline }
        }
        return piece
    }

    /// A figure on a frame, measured from its outline: its top, its feet, its shoulders (0.38 of the
    /// way down) and its left and right there; nil if it's too small. tools/gear_preview.py `figure`.
    nonisolated private static func figure(_ image: Bitmap, origin: (x: Int, y: Int), size: Int)
        -> (top: Int, feet: Int, shoulder: Int, left: Int, right: Int)? {
        func opaque(_ x: Int, _ y: Int) -> Bool { image.alpha(origin.x + x, origin.y + y) > 0.5 }
        let rows = (0..<size).filter { y in (0..<size).contains { opaque($0, y) } }
        guard let top = rows.first, let feet = rows.last, feet - top > 8 else { return nil }
        let shoulder = top + Int((Double(feet - top) * 0.38).rounded())
        guard let left = (0..<size).first(where: { opaque($0, shoulder) }),
              let right = (0..<size).last(where: { opaque($0, shoulder) }) else { return nil }
        return (top, feet, shoulder, left, right)
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
            // Hung from the shoulders like a status cape, in `apply` (`GearLook.cloak`, `drape`).
            break
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
            // White fur round the hood's opening: the hood next to the face (and the cape's hem, drawn
            // with the cape). Its dark pixels made a white wedge down the side, like a wing.
            func bare(_ x: Int, _ y: Int) -> Bool {
                guard opaque(x, y) else { return false }
                let (h, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
                return (h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55
            }
            for y in 0..<size {
                for x in 0..<size where isMark(x, y) && (bare(x + 1, y) || bare(x - 1, y) || bare(x, y + 1) || bare(x, y - 1)) {
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
    /// How many of a hand's last rows gloves take, and the rows of sleeve over it their cuff takes.
    nonisolated private static let gloveRows = 5
    nonisolated private static let gloveCuff = 2

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
        // Gloves take the hand, the pale bits drawn with it and a cuff over it, as strongly as boots take
        // the feet (playtesting 2026-10-31: "the gloves should change the color of the hero a bit more,
        // similar to the boots": a human's hand is two pixels of skin, and they took only that, faintly).
        // tools/gear_preview.py `trinkets` (GLOVE_ROWS, GLOVE_CUFF, GLOVE_TONE).
        if let gloves {
            let knees = Double(top) + 0.7 * Double(feet - top)
            for (index, cells) in patches.enumerated() where index != face {
                // A hand: under the chin (not a sliver of the jaw seen from the side) and above the knees
                // (not a bare knee).
                guard let high = cells.map({ $0.y }).min(), high >= chin + 2, Double(high) <= knees,
                      let low = cells.map({ $0.y }).max(),
                      let left = cells.map({ $0.x }).min(), let right = cells.map({ $0.x }).max() else { continue }
                for cell in cells where cell.y > low - Self.gloveRows { paint(cell.x, cell.y, gloves, lift: 0.55, gain: 0.9) }
                // The pale bits drawn with it (a human's grey-blue fingers, its white ones): touching the
                // hand and barely coloured, never dark.
                var hand = Set<Int>()
                for cell in cells { hand.insert(cell.y * size + cell.x) }
                var pale = Set<Int>()
                for cell in cells {
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = cell.x + dx, ny = cell.y + dy
                            guard opaque(nx, ny), !hand.contains(ny * size + nx), !skin[ny * size + nx] else { continue }
                            let (_, s, v) = hsv(body.rgb(origin.x + nx, origin.y + ny))
                            if s < 0.3, v >= 0.35 { pale.insert(ny * size + nx) }
                        }
                    }
                }
                for i in pale { paint(i % size, i / size, gloves, lift: 0.55, gain: 0.9) }
                // Its cuff: the sleeve's end over the hand, a pixel wider each side, never its outline.
                for y in Swift.max(0, high - Self.gloveCuff)..<high {
                    for x in (left - 1)...(right + 1) where opaque(x, y) && !skin[y * size + x]
                        && out.alpha(origin.x + x, origin.y + y) > 0.5 && hsv(out.rgb(origin.x + x, origin.y + y)).2 >= 0.25 {
                        paint(x, y, gloves, lift: 0.55, gain: 0.9)
                    }
                }
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

    // MARK: A festive hat

    /// A cell of a frame.
    nonisolated private struct HatCell: Hashable {
        let x: Int, y: Int
    }

    /// The head on a plain body's frame: its skin's biggest patch (the bald scalp is skin too), its
    /// top and its lowest row. tools/gear_preview.py `head`.
    nonisolated private static func head(_ body: Bitmap, origin: (x: Int, y: Int), size: Int) -> (top: Int, chin: Int, cells: [HatCell])? {
        var skin = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size where body.alpha(origin.x + x, origin.y + y) > 0.5 {
                let (h, s, v) = hsv(body.rgb(origin.x + x, origin.y + y))
                skin[y * size + x] = (h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55
            }
        }
        var seen = [Bool](repeating: false, count: size * size)
        var best: [HatCell] = []
        for start in 0..<(size * size) where skin[start] && !seen[start] {
            var stack = [start]
            var cells: [HatCell] = []
            seen[start] = true
            while let i = stack.popLast() {
                let x = i % size, y = i / size
                cells.append(HatCell(x: x, y: y))
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < size, ny < size, skin[ny * size + nx], !seen[ny * size + nx] else { continue }
                    seen[ny * size + nx] = true
                    stack.append(ny * size + nx)
                }
            }
            if cells.count > best.count { best = cells }
        }
        guard let top = best.map(\.y).min(), let chin = best.map(\.y).max() else { return nil }
        return (top, chin, best)
    }

    /// Where tools/wear_art.py puts a festive hat's piece in its frame: the band round the head on row
    /// `hatBrim`, centred on column `anchorX`; a mask's eye holes' top row on `anchorY`, centred on
    /// `anchorX` between them (from the side, its front eye hole there). tools/gear_preview.py too.
    nonisolated private static let hatBrim = 40, anchorX = 24, anchorY = 20
    /// Where tools/wear_art.py puts a scarf or a cape: its wearer's shoulders on row `shoulderY`, the
    /// middle of the figure there on `anchorX`; a cape stretched to `capeDrop` rows from the shoulders to
    /// the feet and `capeSpan` pixels across the shoulders.
    nonisolated private static let shoulderY = 24, capeDrop = 20, capeSpan = 14
    /// A cape's shadows take its colour down to this value (tools/wear_art.py outlines it in a neutral
    /// dark that stays).
    nonisolated private static let capeFloor = 0.05
    /// Where tools/wear_art.py puts a scarf's wearer's chin (the face's bottom row, `face`).
    nonisolated private static let chinY = 20

    /// One frame of a worn piece: each pixel's colour, nil where it's clear.
    nonisolated private struct Piece {
        let size: Int
        var pixels: [RGB?]

        subscript(x x: Int, y y: Int) -> RGB? {
            x >= 0 && y >= 0 && x < size && y < size ? pixels[y * size + x] : nil
        }

        /// How many pixels row `y` has.
        func width(_ y: Int) -> Int { (0..<size).filter { self[x: $0, y: y] != nil }.count }

        /// Its top and bottom rows and its left and right columns; nil if it's empty.
        var box: (top: Int, bottom: Int, left: Int, right: Int)? {
            let cells = pixels.indices.filter { pixels[$0] != nil }
            guard let first = cells.first, let last = cells.last else { return nil }
            let columns = cells.map { $0 % size }
            return (first / size, last / size, columns.min() ?? 0, columns.max() ?? 0)
        }

        /// Pixel-art stretch: `by` columns repeated (or dropped) through the middle of its rows from
        /// `keepTop` down, spread a little either side, so a pom over them keeps its shape.
        /// tools/gear_preview.py `widen`.
        func widened(by: Int, keepTop: Int) -> Piece {
            guard by != 0, keepTop >= 0, keepTop < size else { return self }
            let used = (0..<size).filter { x in (keepTop..<size).contains { self[x: x, y: $0] != nil } }
            guard let l = used.min(), let r = used.max() else { return self }
            var columns = (l...r).map { x in (keepTop..<size).map { self[x: x, y: $0] } }
            for k in 0..<abs(by) where !columns.isEmpty {
                let m = max(0, min(columns.count - 1, columns.count / 2 + (k % 3 - 1)))
                if by > 0 { columns.insert(columns[m], at: m) } else if columns.count > 1 { columns.remove(at: m) }
            }
            var out = self
            for y in keepTop..<size { for x in 0..<size { out.pixels[y * size + x] = nil } }
            let x0 = Int((Double(l + r) / 2 - Double(columns.count - 1) / 2 + 0.5).rounded(.down))
            for (i, column) in columns.enumerated() where x0 + i >= 0 && x0 + i < size {
                for (k, c) in column.enumerated() { out.pixels[(keepTop + k) * size + x0 + i] = c }
            }
            return out
        }

        /// Narrower by `by` columns, dropped next to its edges in turn, left then right: what's between
        /// them, a mask's eye holes, stays put. tools/gear_preview.py `pinched`.
        func pinched(by: Int) -> Piece {
            var out = self
            for k in 0..<max(0, by) {
                let used = (0..<size).filter { x in (0..<size).contains { out[x: x, y: $0] != nil } }
                guard used.count >= 8, let l = used.min(), let r = used.max() else { break }
                for y in 0..<size {
                    if k % 2 == 0 {
                        out.pixels[y * size + l + 2] = out.pixels[y * size + l + 1]
                        out.pixels[y * size + l + 1] = out.pixels[y * size + l]
                        out.pixels[y * size + l] = nil
                    } else {
                        out.pixels[y * size + r - 2] = out.pixels[y * size + r - 1]
                        out.pixels[y * size + r - 1] = out.pixels[y * size + r]
                        out.pixels[y * size + r] = nil
                    }
                }
            }
            return out
        }

        /// Which of `n` rows or columns each of `n + by` comes from: the repeated (or dropped) ones
        /// spread evenly, the first and last kept. A cape resized so, not through its middle, keeps
        /// its outline on every body (playtesting 2026-10-22: stretched through the middle it turned
        /// boxy, the line down its back a block). tools/gear_preview.py `spread`.
        static func spread(_ n: Int, by: Int) -> [Int] {
            let m = n + by
            guard m > 1, n > 1 else { return Array(repeating: 0, count: max(m, 0)) }
            return (0..<m).map { Int(Double($0 * (n - 1)) / Double(m - 1) + 0.5) }
        }

        /// `lengthened`, its rows from `start` down resized evenly (`spread`), for a cape.
        /// tools/gear_preview.py `scaled_down`.
        func scaledDown(by: Int, start: Int) -> Piece {
            guard by != 0, start >= 0, start < size,
                  let last = (start..<size).last(where: { width($0) > 0 }) else { return self }
            let rows = (start...last).map { y in (0..<size).map { self[x: $0, y: y] } }
            var out = self
            for y in start..<size { for x in 0..<size { out.pixels[y * size + x] = nil } }
            for (i, k) in Self.spread(rows.count, by: by).enumerated() where start + i < size {
                for (x, c) in rows[k].enumerated() { out.pixels[(start + i) * size + x] = c }
            }
            return out
        }

        /// `widened`, its columns resized evenly (`spread`), centred where they were, for a cape.
        /// tools/gear_preview.py `scaled_across`.
        func scaledAcross(by: Int) -> Piece {
            let used = (0..<size).filter { x in (0..<size).contains { self[x: x, y: $0] != nil } }
            guard by != 0, let l = used.min(), let r = used.max() else { return self }
            let picks = Self.spread(r - l + 1, by: by)
            var out = Piece(size: size, pixels: Array(repeating: nil, count: size * size))
            let x0 = Int((Double(l + r) / 2 - Double(picks.count - 1) / 2 + 0.5).rounded(.down))
            for (i, k) in picks.enumerated() where x0 + i >= 0 && x0 + i < size {
                for y in 0..<size { out.pixels[y * size + x0 + i] = self[x: l + k, y: y] }
            }
            return out
        }

        /// Upside down, to stretch or shrink its rows from the bottom up (`lengthened` on it).
        func flipped() -> Piece {
            var out = self
            for y in 0..<size { for x in 0..<size { out.pixels[y * size + x] = pixels[(size - 1 - y) * size + x] } }
            return out
        }

        /// Pixel-art stretch down: `by` rows repeated (or dropped) through the middle of its rows from
        /// `start` down, the rows above staying where they are. tools/gear_preview.py `lengthened`.
        func lengthened(by: Int, start: Int) -> Piece {
            guard by != 0, start >= 0, start < size,
                  let last = (start..<size).last(where: { width($0) > 0 }) else { return self }
            var rows = (start...last).map { y in (0..<size).map { self[x: $0, y: y] } }
            for k in 0..<abs(by) where !rows.isEmpty {
                let m = max(0, min(rows.count - 1, rows.count / 2 + (k % 3 - 1)))
                if by > 0 { rows.insert(rows[m], at: m) } else if rows.count > 1 { rows.remove(at: m) }
            }
            var out = self
            for y in start..<size { for x in 0..<size { out.pixels[y * size + x] = nil } }
            for (i, row) in rows.enumerated() where start + i < size {
                for (x, c) in row.enumerated() { out.pixels[(start + i) * size + x] = c }
            }
            return out
        }
    }

    /// Row `row` of a piece's sheet in the hat's colours: its coloured pixels (not its white fur, its
    /// outline or its eye holes: darker than `floor`) in `colour` (a hat's trim if it has one: a
    /// bunny's pink band), as light or dark as they were against their middle shade.
    /// tools/gear_preview.py `painted`.
    nonisolated private static func painted(_ sheet: Bitmap, row: Int, size: Int, colour: RGB, floor: Double = 0.25) -> Piece {
        var piece = Piece(size: size, pixels: Array(repeating: nil, count: size * size))
        var lit: [(i: Int, v: Double)] = []
        for y in 0..<size {
            for x in 0..<size where sheet.alpha(x, row * size + y) > 0.5 {
                let c = sheet.rgb(x, row * size + y)
                piece.pixels[y * size + x] = c
                let (_, s, v) = hsv(c)
                if s > 0.2, v > floor { lit.append((y * size + x, v)) }
            }
        }
        guard !lit.isEmpty else { return piece }
        let middle = lit.map { $0.v }.sorted()[lit.count / 2]
        for (i, v) in lit { piece.pixels[i] = shade(colour, v / middle) }
        return piece
    }

    /// `colour` as a shade `k` times as light as the middle one, as a drawn ramp goes: brighter or
    /// darker by a softened `k` (a cape's lit back is twice its middle), a little paler and turned a
    /// few degrees toward yellow where lit, toward red in shadow. Its red, green and blue each scaled
    /// by `k` instead, the lit side ran out of red first and a topaz cloak came out yellow, an azure
    /// cape cyan, an amethyst one pink (playtesting 2026-10-30). tools/gear_preview.py `shade`.
    nonisolated private static func shade(_ colour: RGB, _ k: Double) -> RGB {
        let (h, s, v) = hsv(colour)
        let hue = s > 0.1 ? (h + 6 * (k - 1) + 360).truncatingRemainder(dividingBy: 360) : h
        return rgb(hue: hue, saturation: s * (1 - 0.12 * max(0, k - 1)), value: min(1, v * pow(k, 0.45)))
    }

    /// The colour of a hue in degrees, saturation and value in 0...1.
    nonisolated private static func rgb(hue: Double, saturation s: Double, value v: Double) -> RGB {
        let c = v * s, x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r + m, g + m, b + m)
    }

    /// The face on a frame as drawn (tools/gear_preview.py `face`).
    nonisolated private struct Face {
        /// The eyes' top row and the middle of each eye, left to right.
        let eyeTop: Int
        let middles: [Double]
        /// The face's top and bottom rows: from the eyes up and down, the rows that show it.
        let high: Int, low: Int
        /// The columns searched, and the frame's size.
        let span: Range<Int>
        let size: Int
        /// How pale an eye's white is: saturation under `most`, value over `least`.
        let most: Double, least: Double

        /// Whether the pixel at `x`, `y` is face: skin, or an eye's white.
        func shows(_ image: Bitmap, origin: (x: Int, y: Int), _ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < size, y < size, image.alpha(origin.x + x, origin.y + y) > 0.5 else { return false }
            let (h, s, v) = GearOverlay.hsv(image.rgb(origin.x + x, origin.y + y))
            return ((h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55) || (s < most && v > least)
        }
    }

    /// The face on a frame as drawn, its head found on the plain body (`found`): the eyes' whites with
    /// a pupil or lash beside or over them and the face's skin near (a glint in a beard or on a helmet
    /// has none; a cream white, as some armour sheets draw, only if there's no pure one), the highest
    /// pair; and the rows from them up and down that show skin or white. `eyesAt`: the eyes' row on
    /// the plain body, if known; only rows within two of it are searched (a hair's highlight or a glint
    /// on mail over or under the face passed for an eye, and the mask slid off the face, playtesting
    /// 2026-10-24). Nil from behind. tools/gear_preview.py `face`.
    nonisolated private static func face(_ out: Bitmap, origin: (x: Int, y: Int), size: Int,
                                         found: (top: Int, chin: Int, cells: [HatCell]), eyesAt: Int? = nil) -> Face? {
        func isDrawn(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && out.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func dark(_ x: Int, _ y: Int) -> Bool { isDrawn(x, y) && hsv(out.rgb(origin.x + x, origin.y + y)).2 < 0.35 }
        func isSkin(_ x: Int, _ y: Int) -> Bool {
            guard isDrawn(x, y) else { return false }
            let (h, s, v) = hsv(out.rgb(origin.x + x, origin.y + y))
            return (h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55
        }
        let xs = found.cells.map(\.x)
        guard let leftmost = xs.min(), let rightmost = xs.max() else { return nil }
        var first = max(0, found.top + 2), last = min(size, found.chin + 3)
        if let eyesAt { (first, last) = (max(first, eyesAt - 2), min(last, eyesAt + 3)) }
        var whites: [HatCell] = [], near: [HatCell] = []
        var most = 0.06, least = 0.92
        for (m, l) in [(0.06, 0.92), (0.25, 0.85)] {
            (most, least) = (m, l)
            for y in stride(from: first, to: last, by: 1) {
                for x in max(0, leftmost - 1)..<min(size, rightmost + 3) where isDrawn(x, y) {
                    let (_, s, v) = hsv(out.rgb(origin.x + x, origin.y + y))
                    guard s < most, v > least, dark(x - 1, y) || dark(x + 1, y) || dark(x, y - 1) else { continue }
                    whites.append(HatCell(x: x, y: y))
                    if [y, y + 1].contains(where: { yy in [x - 2, x - 1, x + 1, x + 2].contains { isSkin($0, yy) } }) {
                        near.append(HatCell(x: x, y: y))
                    }
                }
            }
            if !near.isEmpty { break }
        }
        let eyes = near.isEmpty ? whites : near
        guard let eyeTop = eyes.map(\.y).min() else { return nil }
        let columns = Set(eyes.filter { $0.y <= eyeTop + 1 }.map(\.x)).sorted()
        var groups: [[Int]] = []
        for x in columns {
            if let previous = groups.last?.last, x - previous <= 2 { groups[groups.count - 1].append(x) } else { groups.append([x]) }
        }
        let span = max(0, leftmost - 2)..<min(size, rightmost + 3)
        let pale = (most, least)
        func shows(_ y: Int) -> Bool {
            y >= 0 && y < size && span.contains { x in
                guard isDrawn(x, y) else { return false }
                let (_, s, v) = hsv(out.rgb(origin.x + x, origin.y + y))
                return isSkin(x, y) || (s < pale.0 && v > pale.1)
            }
        }
        var low = eyeTop, high = eyeTop
        while low - eyeTop < 6, shows(low + 1) { low += 1 }
        while eyeTop - high < 8, shows(high - 1) { high -= 1 }
        return Face(eyeTop: eyeTop, middles: groups.map { Double($0.reduce(0, +)) / Double($0.count) },
                    high: high, low: low, span: span, size: size, most: most, least: least)
    }

    /// A festive scarf (`GearLook.scarf`) round the neck, over everything: the piece Retro Diffusion drew
    /// (art/sprites/wear_scarf.png, what's under its wearer's chin, cut out by tools/wear_art.py) in its
    /// colour, under the chin as drawn (armour with a sheet of its own draws its head higher or lower than
    /// the plain body; from behind, the chin found on the frame facing you, `front`), across the middle
    /// of the body at the shoulders. The chin is found on `base`, the sprite before any recolouring:
    /// the skin test knows the sheets' own fair skin, not a darker tone the hero chose.
    /// tools/gear_preview.py `scarf`.
    nonisolated private static func scarf(_ out: inout Bitmap, body: Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                          facing: String, piece: Piece, front: (x: Int, y: Int)) {
        let at = facing == "up" ? front : origin
        guard piece.box != nil, let figure = Self.figure(body, origin: origin, size: size),
              let found = Self.head(body, origin: at, size: size) else { return }
        let chin = Self.face(base, origin: at, size: size, found: found)?.low ?? found.chin
        let dy = chin - chinY, dx = (figure.left + figure.right) / 2 - anchorX
        for y in 0..<size {
            for x in 0..<size {
                guard let c = piece[x: x, y: y], y + dy >= 0, x + dx >= 0, y + dy < size, x + dx < size else { continue }
                out.set(origin.x + x + dx, origin.y + y + dy, c)
            }
        }
    }

    /// A festive hat (`GearLook.hat`) on the head, frame by frame: a piece Retro Diffusion drew on a
    /// hero (art/sprites/wear_<kind>.png, cut out by tools/wear_art.py), fitted to the head as drawn,
    /// hair and all, measured on the plain body (the scalp, the eyes) and on what's drawn before the
    /// hat goes on. A crown (a party crown), a Santa hat or a bunny's ears go round the head: their band
    /// on the widest row of the head as drawn over the eyes, as wide as the scalp and a little more, over
    /// all the hair above it. A mask (none from behind) goes over the face, its eye holes on the eyes,
    /// found on the face as drawn (armour with a sheet of its own has a face of its own), no wider or
    /// taller than the face, a little over a beard, and from the side as far forward as it reaches. The
    /// face is found on `base`, the sprite before any recolouring: the skin test knows the sheets' own
    /// fair skin, not a darker tone the hero chose (it found no face on a deep one, and the mask slid
    /// off it). tools/gear_preview.py `hat`.
    nonisolated private static func hat(_ out: inout Bitmap, body: Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int,
                                        facing: String, kind: String, piece: Piece) {
        guard piece.box != nil else { return }
        guard let found = Self.head(body, origin: origin, size: size) else { return }
        let top = found.top, chin = found.chin
        let span = found.cells.filter { $0.y == top + 3 }.map(\.x)
        let across = span.isEmpty ? found.cells.map(\.x) : span
        guard let left = across.min(), let right = across.max() else { return }
        let cx = (left + right) / 2
        // The head as drawn, hair and all, before the hat goes on.
        var drawn = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size { drawn[y * size + x] = out.alpha(origin.x + x, origin.y + y) > 0.5 }
        }
        func isDrawn(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < size && y < size && drawn[y * size + x] }
        func stamp(_ t: Piece, dy: Int, dx: Int) {
            for y in 0..<size {
                for x in 0..<size {
                    guard let c = t[x: x, y: y], y + dy >= 0, x + dx >= 0, y + dy < size, x + dx < size else { continue }
                    out.set(origin.x + x + dx, origin.y + y + dy, c)
                }
            }
        }
        if kind == "mask" {
            // The eyes as drawn near where the plain body has them; where none show there (a sheet's
            // pale face), the plain body's face.
            let plain = Self.face(body, origin: origin, size: size, found: found)
            let drawnFace = Self.face(base, origin: origin, size: size, found: found, eyesAt: plain?.eyeTop)
            guard let seen = drawnFace ?? plain,
                  let first = seen.middles.first, let last = seen.middles.last else { return }
            let eyeTop = seen.eyeTop, low = seen.low, high = seen.high, span = seen.span
            let image = drawnFace == nil ? body : base
            func facial(_ x: Int, _ y: Int) -> Bool { seen.shows(image, origin: origin, x, y) }
            let anchor = switch facing {
            case "right": seen.middles.max() ?? last
            case "left": seen.middles.min() ?? first
            default: (first + last) / 2
            }
            var dx = Int((anchor + 0.5).rounded(.down)) - anchorX
            // The mask stops two rows under the chin (over the top of a dwarf's beard) and starts no
            // more than a row over the face (on the hair).
            var narrow = piece
            if facing == "down", let whole = piece.box {
                // No wider than the face (its outermost skin or eye pixels from just over the eyes to
                // the chin) and its outline: on a narrow face it spilled onto the hair.
                let wide = (eyeTop - 1...low).compactMap { y -> Int? in
                    let row = span.filter { facial($0, y) }
                    guard let l = row.min(), let r = row.max() else { return nil }
                    return r - l + 1
                }.max() ?? 0
                if wide > 0 { narrow = piece.pinched(by: max(0, min(4, (whole.right - whole.left + 1) - (wide + 2)))) }
            }
            guard let box = narrow.box else { return }
            let below = max(0, min(3, box.bottom - (low - eyeTop + anchorY + 2)))
            let above = max(0, min(3, (high - eyeTop + anchorY - 1) - box.top))
            let fitted = narrow.lengthened(by: -below, start: anchorY + 2)
                .flipped().lengthened(by: -above, start: size - anchorY + 1).flipped()
            let dy = eyeTop - anchorY
            if facing == "right" || facing == "left" {
                // From the side, as far forward as the face reaches on any of its rows (forehead,
                // nose, chin; not the hair above, whose ginger passes for skin), the outline past
                // it: no skin peeking out in front of it. Within three pixels of the front eye on
                // the front eye hole.
                let sign = facing == "right" ? 1 : -1
                var need = 0
                for y in high...low where y - dy >= 0 && y - dy < size {
                    let maskRow = (0..<size).filter { fitted[x: $0, y: y - dy] != nil }
                    let faceRow = span.filter { facial($0, y) }
                    guard let maskLeft = maskRow.min(), let maskRight = maskRow.max(),
                          let faceLeft = faceRow.min(), let faceRight = faceRow.max() else { continue }
                    need = max(need, sign > 0 ? faceRight + 1 - (maskRight + dx) : (maskLeft + dx) - (faceLeft - 1))
                }
                dx += sign * min(3, need)
            }
            stamp(fitted, dy: dy, dx: dx)
            return
        }
        /// The head as drawn on row `y`: the run through its middle, hair and all, never narrower than
        /// the scalp and its outline.
        func around(_ y: Int) -> (l: Int, r: Int) {
            let near = (max(0, cx - 3)...min(size - 1, cx + 3)).filter { isDrawn($0, y) }
            guard let start = near.min(by: { abs($0 - cx) < abs($1 - cx) }) else { return (left - 1, right + 1) }
            var l = start, r = start
            while l - 1 >= max(0, left - 6), isDrawn(l - 1, y) { l -= 1 }
            while r + 1 < min(size, right + 7), isDrawn(r + 1, y) { r += 1 }
            return (min(l, left - 1), max(r, right + 1))
        }
        // The eyes: gaps in the face's skin, a pixel or two wide (none from behind). The band sits on
        // the widest row of the head as drawn over them: worn round the head, not perched on top of it.
        // Never lower than three fifths of the way from the scalp's top to the eyes: a cowl or a helmet
        // round the face is wide all the way down.
        let skin = Set(found.cells)
        let eye = found.cells.filter {
            $0.y > top + 2 && !skin.contains(HatCell(x: $0.x + 1, y: $0.y))
                && (skin.contains(HatCell(x: $0.x + 2, y: $0.y)) || skin.contains(HatCell(x: $0.x + 3, y: $0.y)))
        }.map(\.y).min() ?? top + max(4, (chin - top) / 2)
        let deep = min(eye - 2, top + max(2, (eye - top) * 3 / 5))
        let crownTop = (0..<size).first { y in (max(0, left)...max(max(0, left), min(size - 1, right))).contains { isDrawn($0, y) } } ?? top
        let rows = crownTop <= deep ? Array(crownTop...deep) : []
        let brim = rows.max { a, b in
            let wa = around(a).r - around(a).l, wb = around(b).r - around(b).l
            return wa != wb ? wa < wb : a < b
        } ?? top + 1
        // As wide as the scalp and its outline and a little more, within three pixels of as drawn; a pom
        // (the rows narrower than half the piece) keeps its shape.
        guard let box = piece.box else { return }
        let keep = (box.top...box.bottom).first { piece.width($0) >= max(1, (box.right - box.left + 1) / 2) } ?? box.top
        let fitted = piece.widened(by: max(-3, min(3, (right - left + 5) - piece.width(hatBrim))), keepTop: keep)
        guard let fit = fitted.box else { return }
        let dy = brim + 1 - hatBrim, dx = (left + right + 1) / 2 - (fit.left + fit.right + 1) / 2
        // It sits on the head: the hair above the band it doesn't cover goes (spiky hair stuck up between
        // a crown's points or a bunny's ears).
        for y in 0..<max(0, brim - 1) {
            for x in max(0, left - 1)..<min(size, right + 2) where isDrawn(x, y) && fitted[x: x - dx, y: y - dy] == nil {
                out.clear(origin.x + x, origin.y + y)
            }
        }
        stamp(fitted, dy: dy, dx: dx)
    }

    /// A hood worn as a hat (GearLook.hood): art/sprites/hood_* comes in magenta, soft magenta takes the
    /// hood's colour, keeping its shade, and full magenta its trim, as a hide cloak's own did; lined
    /// with white fur round its opening, next to the face, if its cloak was. Over whatever the armour
    /// painted it (`dress`). tools/gear_preview.py `hood`.
    nonisolated private static func hood(_ out: inout Bitmap, base: Bitmap, origin: (x: Int, y: Int), size: Int, gear: GearLook) {
        guard let mid = color(hex: gear.hood) else { return }
        let accent = color(hex: gear.hoodTrim) ?? RGB(0.91, 0.85, 0.69)
        let dark = mid.scaled(0.55), light = mid.mixed(with: RGB(1, 1, 1), 0.35)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < size && y < size && base.alpha(origin.x + x, origin.y + y) > 0.5
        }
        func isMark(_ x: Int, _ y: Int) -> Bool {
            guard opaque(x, y) else { return false }
            let (h, s, _) = hsv(base.rgb(origin.x + x, origin.y + y))
            return abs(h - 300) < 12 && s > 0.3
        }
        /// The face's skin, which the fur lines.
        func bare(_ x: Int, _ y: Int) -> Bool {
            guard opaque(x, y) else { return false }
            let (h, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
            return (h <= 40 || h >= 342) && s > 0.12 && s < 0.65 && v > 0.55
        }
        for y in 0..<size {
            for x in 0..<size where isMark(x, y) {
                if gear.hoodFur, bare(x + 1, y) || bare(x - 1, y) || bare(x, y + 1) || bare(x, y - 1) {
                    out.set(origin.x + x, origin.y + y, fur(x, y))
                    continue
                }
                let (_, s, v) = hsv(base.rgb(origin.x + x, origin.y + y))
                out.set(origin.x + x, origin.y + y, s > 0.85 ? accent : v > 0.82 ? light : v < 0.55 ? dark : mid)
            }
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

        /// Makes a pixel clear.
        mutating func clear(_ x: Int, _ y: Int) {
            let i = (y * width + x) * 4
            for k in 0..<4 { pixels[i + k] = 0 }
        }

        func image() -> CGImage? {
            PixelImage.make(pixels, width: width, height: height)
        }
    }
}
