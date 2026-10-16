import SpriteKit

/// Draws a range of hills (`WorldMap.Hill`): the ground it rises over as pictures (the map's own
/// tiles, bare patches on its steepest slopes, its trails worn into it), then lifted off the map by
/// its heights and lit by the sun wherever it is in the sky (`Sun`, `light(_:by:)`). The lifting is a
/// small shader on flat sprites over where it shows on screen: each pixel finds the ground point
/// that rises to it (`WorldMap.groundPoint`'s halving, against the same heights walkers stand on),
/// shows the picture there and lights it by how the ground slopes there. A warped sprite
/// (`SKWarpGeometryGrid`) did the same, but SpriteKit crashed subdividing grids that size.
///
/// A range is too big for one picture, so it's drawn in squares `square` cells a side; and too deep to
/// sort as one thing among the trees and walkers, so each square shows in strips `stripDepth` cells deep
/// (up the screen), each sorted just behind its back edge (`strip(at:)`): whatever stands on a strip or
/// in front of it is drawn over it, and whatever stands behind it is hidden by it.
enum HillArt {
    struct Look {
        /// The ground's tile pictures by cell, as the map has them.
        var ground: (GridPoint) -> CGImage?
        /// The trail's tile pictures by cell (the map's road).
        let trail: (GridPoint) -> CGImage?
        /// The rock (or sand, or chocolate) showing through on its slopes, by cell, if any.
        var bank: ((GridPoint) -> CGImage?)?
        /// How rocky the map's hills are (`WorldMap.rockiness`): the rockier, the more of the bank
        /// shows, further down the slopes, and the deeper the shade.
        var rocky: Double
        /// Bare rock all over from this far up its slopes (0 at the foot, 1 where its top begins), if
        /// set: a mountain of rock with only its foot grassy.
        var rockAbove: Double? = nil
        /// Bare rock all over from this high up (points), if set, with a ragged edge: a mountain's
        /// upper slopes, its foothills' grassy tops below.
        var rockFrom: Double? = nil
        /// How lit slopes facing away from the midday sun still are (0.45 less a tenth for rocky, if
        /// unset): lower for deeper shade, so a mountain's shape shows.
        var ambient: Double? = nil
        /// How much brighter than the flat its sunniest slopes go: only a shade on matte ground,
        /// more on bare rock, so the sides of a mountain stand out from the ground past it.
        var brightest = 1.06
        /// Ledges across its steep bare rock, if set: a darker band every this many points up, a
        /// lighter lip over each, so it reads as layered rock rather than a smooth mound.
        var strata: Double? = nil
        /// Its bare rock painted as it shows on the screen rather than as it lies on the map: each
        /// pixel's from where it rises to, the rock over all it covers there, and its ledges by its
        /// own height (`strata`). A sheer face showed the rock and its ledges stretched up the
        /// screen (a cave's wall, playtesting 2026-10-16).
        var upright = false
        /// The map's road, if bare rock should leave it showing (a road up into a cave's mouth).
        var road: ((GridPoint) -> Bool)? = nil
        /// The soft colour patches over the map's whole ground: a pixel a cell, north at the top.
        let variation: CGImage?
        let mapSize: (columns: Int, rows: Int)
        /// Slopes in shade lean toward this colour, sunny ones toward the highlight.
        let shadow: (r: Double, g: Double, b: Double)
        let highlight: (r: Double, g: Double, b: Double)
        /// Cells it isn't drawn over, if any: a land next door, where a cave's range out past the
        /// map's edge would reach into it past the edge's end.
        var hidden: ((GridPoint) -> Bool)? = nil
        /// Pictures lying on the ground, north up, and where (in cells): a bridge's deck over a lake
        /// that's sunk with the shore (`WorldMap.shore`).
        var overlays: [(image: CGImage, frame: CGRect)] = []
    }

    /// How lit a hill's slopes facing away from the midday sun still are, on a map as rocky as
    /// `rocky` (`WorldMap.rockiness`): the rockier, the deeper the shade.
    static func ambient(rocky: Double) -> Double {
        0.45 - 0.1 * rocky
    }

    /// How brightly `sun` lights a slope, next to the flat (1 there): `hx` and `hy` how far it rises
    /// a cell across and up the map (as heights stand, 1/cos 30° taller than they're drawn, over a
    /// cell's width), `ambient` how lit it still is turned from the midday sun. And `lambert`, how
    /// squarely the sun falls on it: 0 or below where the slope turns its back on the sun, steeper
    /// than the sun is high, in the hill's own shadow. The lower the sun, the brighter the slopes
    /// facing it next to the flat, and the more of them turned from it. The lifting shader
    /// (`lifting`) lights a hill's ground the same way.
    static func sunlight(hx: Double, hy: Double, ambient: Double, sun: Sun) -> (shade: Double, lambert: Double) {
        let lambert = (-hx * sun.x - hy * sun.y + sun.z) / (hx * hx + hy * hy + 1).squareRoot()
        let shaded = Sun.shaded(ambient: ambient)
        let shade = shaded + (1 - shaded) * max(0, lambert) / sun.z
        return (1 + (shade - 1) * sun.strength, lambert)
    }

    /// Lights hills' sprites (from `sprites(for:look:)`) by `sun`: cheap, so it can follow the clock.
    static func light(_ sprites: [SKNode], by sun: Sun) {
        let value = SIMD4(Float(sun.x), Float(sun.y), Float(sun.z), Float(sun.strength))
        var done: Set<ObjectIdentifier> = []
        for case let sprite as SKSpriteNode in sprites {
            guard let shader = sprite.shader, done.insert(ObjectIdentifier(shader)).inserted else { continue }
            shader.uniformNamed("u_sun")?.vectorFloat4Value = value
        }
    }

    /// Cells a side of each picture.
    static let square = 16
    /// How much darker sunk ground is at the water's level than at the land's (`WorldMap.seaDrop`
    /// below), in the shade's steps: wet ground running down into the sea, so the slope shows
    /// (playtesting 2026-10-15). A lake's shore, not as deep, darkens less.
    static let wetShade: Float = 0.3
    /// Cells deep each strip is, along the map's diagonal (up the screen).
    static let stripDepth = 2
    /// How far up the screen a cell's depth is (a cell's diamond is twice this tall).
    private static let depthStep = WorldMap.project(CGPoint(x: WorldMap.tileSize, y: 0)).y
    /// How far up the screen each strip reaches.
    static let stripHeight = depthStep * CGFloat(stripDepth)

    /// Cells deep each strip of sunk ground is (`Hill.sunken`): a square's worth. Nothing standing
    /// behind sunk ground is ever hidden by it (it sinks away from them, down the screen), so it
    /// needn't be cut finer to sort among them.
    static let sunkenDepth = 2 * square

    /// The strip of raised ground over a point on the map (on the ground, not lifted): where it's
    /// sorted, just behind its back edge, and how far up the screen it begins. The strip in front of
    /// it is sorted `stripHeight` higher. `depth`: `sunkenDepth` on sunk ground.
    static func strip(at ground: CGFloat, depth: Int = stripDepth) -> (z: CGFloat, start: CGFloat) {
        let height = depthStep * CGFloat(depth)
        let band = (ground / height).rounded(.down)
        return (-(band + 1) * height - 0.75, band * height)
    }

    /// A range made ready to draw (`painter(for:look:)`): what's the same all over it worked out once
    /// (its outline, light, trails and heights), so its squares can be drawn one at a time as they're
    /// wanted (the continent draws those of the chunks round you, `ContinentScene`).
    struct Painter {
        /// The south-west corners of its squares that show any of it, in the map's cells.
        let corners: [GridPoint]
        /// One square's sprites (at one of `corners`), in the map's own space, each already sorted.
        let draw: (_ corner: GridPoint, _ pause: @escaping () async -> Void) async -> [SKSpriteNode]
    }

    /// The range as sprites in the map's own space (put them straight in the world), each already
    /// sorted; none if it can't be drawn.
    /// `pause`: called every so often, for a land built in the background to give the frame back
    /// (`WorldScene.breathe`): a range takes far too long to draw in one go.
    static func sprites(for hill: WorldMap.Hill, look: Look, pause: @escaping () async -> Void = {}) async -> [SKSpriteNode] {
        guard let ready = await Self.painter(for: hill, look: look, pause: pause) else { return [] }
        var sprites: [SKSpriteNode] = []
        for corner in ready.corners {
            await pause()
            sprites += await ready.draw(corner, pause)
        }
        return sprites
    }

    /// The range made ready to draw a square at a time (`Painter`); nil if it can't be drawn.
    static func painter(for hill: WorldMap.Hill, look: Look, pause: @escaping () async -> Void = {}) async -> Painter? {
        guard let first = hill.cells.first, let sample = look.ground(first) else { return nil }
        let tile = WorldMap.tileSize
        let px = sample.width
        let scale = CGFloat(px)
        let low = hill.origin
        let columns = hill.size.columns, rows = hill.size.rows
        let samples = WorldMap.Hill.samples
        // Its heights, a lattice of samples (`Hill.heights`) at the cells' corners and between.
        let lattice = (columns: columns * samples + 1, rows: rows * samples + 1)
        func height(_ i: Int, _ j: Int) -> Float {
            hill.heights[min(lattice.rows - 1, max(0, j)) * lattice.columns + min(lattice.columns - 1, max(0, i))]
        }

        // What shows: the range and a cell round it (its soft edge, its trails' feet).
        var shown: Set<GridPoint> = []
        for cell in hill.cells {
            for dr in -1...1 { for dc in -1...1 { shown.insert(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }
        }
        let depthOfStrips = hill.sunken ? sunkenDepth : stripDepth

        // Per sample (between the lattice's points): how much bank shows, how it's lit, and where
        // it ends.
        let sw = columns * samples, sh = rows * samples
        var bare = [UInt8](repeating: 0, count: sw * sh * 4)
        var mask = [UInt8](repeating: 0, count: sw * sh * 4)
        // How much darker or lighter each sample is, whatever the sun does (its foot, ledges), 1 on
        // the flat (bottom row first, like the heights). The sun's light is the shader's (`lifting`).
        var light = [Float](repeating: 1, count: sw * sh)
        // Sunlight, for the shader (`sunlight`): soft, the sides away from it a few shades darker,
        // the sides facing it only a shade lighter at midday, so the hill reads as matte ground
        // rather than something glossy.
        let ambient = look.ambient ?? Self.ambient(rocky: look.rocky)
        let deepest = max(look.shadow.r, look.shadow.g, look.shadow.b, 0.01)
        let tint = (look.shadow.r / deepest, look.shadow.g / deepest, look.shadow.b / deepest)
        // The trails as worn paths (`stamps(of:)`), and how near each sample is to one: from its
        // edge, as if it reached an even 0.3 cells either side of its middle.
        let stamps = Self.stamps(of: hill)
        var nearness = [Float](repeating: .infinity, count: sw * sh)
        let around = Int(1.2 * Double(samples)) + 1
        for (number, stamp) in stamps.enumerated() {
            if number % 64 == 63 { await pause() }
            let fx = (stamp.x - Double(low.col)) * Double(samples) - 0.5
            let fy = (stamp.y - Double(low.row)) * Double(samples) - 0.5
            let ci = Int(fx.rounded(.down)), cj = Int(fy.rounded(.down))
            let i0 = max(0, ci - around), i1 = min(sw - 1, ci + around)
            let j0 = max(0, cj - around), j1 = min(sh - 1, cj + around)
            guard i0 <= i1, j0 <= j1 else { continue }
            for j in j0...j1 {
                for i in i0...i1 {
                    let dx = (Double(i) - fx) / Double(samples), dy = (Double(j) - fy) / Double(samples)
                    let distance = Float((dx * dx + dy * dy).squareRoot() - (stamp.width - 0.3))
                    nearness[j * sw + i] = min(nearness[j * sw + i], distance)
                }
            }
        }
        if hill.sunken {
            // Sunk ground, whole over its cells and the cell round them (the land there at its own
            // height, drawn just as it is round it), lit by how it slopes and darker the lower it
            // lies, wet toward the water (`wetShade`): their samples, not every one in its box (a
            // coast's shore reaches round much of its land, in a narrow band).
            let drop = Float(WorldMap.seaDrop)
            for (number, cell) in shown.enumerated() {
                if number % 256 == 255 { await pause() }
                let i0 = (cell.col - low.col) * samples, j0 = (cell.row - low.row) * samples
                let fromI = max(0, i0), toI = min(sw, i0 + samples), fromJ = max(0, j0), toJ = min(sh, j0 + samples)
                guard fromI < toI, fromJ < toJ else { continue }
                for j in fromJ..<toJ {
                    for i in fromI..<toI {
                        // Image rows run top down.
                        let index = ((sh - 1 - j) * sw + i) * 4
                        for channel in 0..<4 { mask[index + channel] = 255 }
                        let depth = -(height(i, j) + height(i + 1, j) + height(i, j + 1) + height(i + 1, j + 1)) / 4
                        let wet = min(1, max(0, depth / drop))
                        light[j * sw + i] = 1 - Self.wetShade * wet * wet.squareRoot()
                    }
                }
            }
        }
        for j in 0..<(hill.sunken ? 0 : sh) {
            if j % 4 == 3 { await pause() }
            for i in 0..<sw {
                let x = Double(low.col) + (Double(i) + 0.5) / Double(samples)
                let y = Double(low.row) + (Double(j) + 0.5) / Double(samples)
                // Image rows run top down.
                let index = ((sh - 1 - j) * sw + i) * 4
                let field = hill.field(x, y)
                if let hidden = look.hidden, hidden(GridPoint(col: Int(x.rounded(.down)), row: Int(y.rounded(.down)))) { continue }
                let trailDistance = Double(nearness[j * sw + i])
                // Its outline, softened, and its trails' starts out on the ground in front.
                var edge = min(1, max(0, (field + 0.06) / 0.25))
                if field < 0.2 { edge = max(edge, min(1, max(0, (0.5 - trailDistance) / 0.1))) }
                for channel in 0..<4 { mask[index + channel] = UInt8(edge * 255) }
                guard field > 0 else { continue }
                // How steep it is, from the heights walkers stand on (points a cell). Heights stand
                // 1/cos 30° taller than they're drawn.
                let h00 = Double(height(i, j)), h10 = Double(height(i + 1, j))
                let h01 = Double(height(i, j + 1)), h11 = Double(height(i + 1, j + 1))
                let gx = ((h10 + h11) - (h00 + h01)) / 2 * Double(samples)
                let gy = ((h01 + h11) - (h00 + h10)) / 2 * Double(samples)
                let hx = gx / Double(tile) / 0.866, hy = gy / Double(tile) / 0.866
                var shade = 1.0
                let s = hill.rise(x, y)
                // The foot tucked in a little darker.
                if s < 0.3 { shade *= 1 - 0.08 * sin(Double.pi * s / 0.3) }
                light[j * sw + i] = Float(shade)
                // The bank shows through in ragged patches where it's steepest, but not by a trail: on
                // gentle hills only at the steepest, on rocky ones down most of the slope and solid.
                guard look.bank != nil, s > 0 else { continue }
                let slope = (gx * gx + gy * gy).squareRoot()
                let ragged = sin(x * 2.3 + 1.1) * sin(y * 1.9 + 0.3) * 0.5 + sin(x * 5.1) * sin(y * 4.7 + 2) * 0.3
                let from = 0.75 - 0.45 * look.rocky, solid = 0.75 + 0.25 * look.rocky
                let sheer = slope / hill.steepness + ragged * (0.15 + 0.15 * look.rocky)
                var amount = min(1, max(0, (sheer - from) / 0.12)) * solid
                if let above = look.rockAbove { amount = max(amount, min(1, max(0, (s - above + ragged * 0.1) / 0.12))) }
                if let line = look.rockFrom {
                    let level = (h00 + h10 + h01 + h11) / 4
                    amount = max(amount, min(1, max(0, (level - line + ragged * 12) / 14)))
                }
                if amount > 0 { amount *= min(1, max(0, (trailDistance - 0.55) / 0.3)) }
                if amount > 0, let road = look.road, road(GridPoint(col: Int(x.rounded(.down)), row: Int(y.rounded(.down)))) { amount = 0 }
                for channel in 0..<4 { bare[index + channel] = UInt8(amount * 255) }
                // Ledges: on bare rock from a gentle slope up (a cell's rise over its width, as the
                // light has it, past 0.15), banded by height with a ragged edge; only where the rock
                // faces you. On a slope turned away the view squeezes each band into a thin dark line
                // that reads as a crack in the ground (playtesting 2026-10-12, Moonwhisper's cave
                // range): `facing` is 1 within 60° of straight at you, 0 turned side on or away.
                if !look.upright, let strata = look.strata, amount > 0.5 {
                    let rise = (hx * hx + hy * hy).squareRoot()
                    let facing = min(1, max(0, 2 * (hx + hy) / max(rise * 2.0.squareRoot(), 1e-6)))
                    let steep = min(1, max(0, (rise - 0.15) / 0.2)) * facing
                    let level = (h00 + h10 + h01 + h11) / 4 + ragged * 6
                    let band = level / strata - (level / strata).rounded(.down)
                    if band < 0.18 {
                        shade *= 1 - 0.3 * steep
                    } else if band < 0.28 {
                        shade *= 1 + 0.1 * steep
                    }
                    light[j * sw + i] = Float(shade)
                }
            }
        }
        let patches = look.bank == nil ? nil : image(bare, width: sw, height: sh)
        let outline = image(mask, width: sw, height: sh)

        // The trails' pixels over the range's own (bottom row first): 3 the trail, 2 the shadow along
        // its uphill edge where it's cut into the slope, 1 the lighter lip along its downhill edge.
        // Each stamp a round with a ragged edge, a pixel pair at a time.
        let wide = columns * px, high = rows * px
        let pixels = Double(px)
        var marks = [UInt8](repeating: 0, count: stamps.isEmpty ? 0 : wide * high)
        var worn: Set<GridPoint> = []
        for (number, stamp) in stamps.enumerated() {
            if number % 32 == 31 { await pause() }
            let cx = (stamp.x - Double(low.col)) * pixels, cy = (stamp.y - Double(low.row)) * pixels
            let half = stamp.width * pixels, band = 2.5 * stamp.cut
            let inner = half * 0.85, outer = half * 1.15 + band
            let reach = Int(outer.rounded(.up)) + 1
            let x0 = max(0, Int(cx) - reach), x1 = min(wide - 1, Int(cx) + reach)
            let y0 = max(0, Int(cy) - reach), y1 = min(high - 1, Int(cy) + reach)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let ex = Double(x) + 0.5 - cx, ey = Double(y) + 0.5 - cy
                    let distance = (ex * ex + ey * ey).squareRoot()
                    guard distance < outer else { continue }
                    let index = y * wide + x
                    if distance < inner {
                        marks[index] = 3
                        continue
                    }
                    let edge = half * (0.85 + 0.3 * noise(x >> 1, y >> 1, 0))
                    if distance < edge {
                        marks[index] = 3
                    } else if distance < edge + band {
                        let mark: UInt8 = ex * stamp.upX + ey * stamp.upY > 0 ? 2 : 1
                        marks[index] = max(marks[index], mark)
                    }
                }
            }
            let cell = GridPoint(col: Int(stamp.x.rounded(.down)), row: Int(stamp.y.rounded(.down)))
            for dr in -1...1 { for dc in -1...1 { worn.insert(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }
        }

        // A cave's mouth, standing upright on the screen however its slope leans.
        let doorway = hill.mouth.map { mouth in Self.doorway(mouth, height: { x, y in Double(hill.height(atCells: x, y)) }) }

        // The pictures, a square of cells at a time, all drawn in the range's own pixels (from its
        // corner, `low`).
        let whole = CGRect(x: 0, y: 0, width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        func rect(_ cell: GridPoint) -> CGRect {
            CGRect(x: CGFloat(cell.col - low.col) * scale, y: CGFloat(cell.row - low.row) * scale, width: scale, height: scale)
        }
        /// A point in cells, in the range's own pixels.
        func spot(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - CGFloat(low.col)) * scale, y: (point.y - CGFloat(low.row)) * scale)
        }
        let side = square * px
        // Bare rock painted upright (`Look.upright`): the rock's tiles round the range, read once.
        let rockUpright = look.upright ? look.bank.flatMap { UprightRock(bank: $0, from: low, columns: columns, rows: rows, highest: hill.highest) } : nil
        /// A square's bare rock painted upright (rows top down): each pixel's from where it rises to
        /// on the screen, as flat ground there would show it, over all the pixel covers there, and
        /// its ledges (`Look.strata`) by its own height, fine enough for a sheer face.
        func uprightRock(_ corner: GridPoint, cells: [GridPoint], _ rock: UprightRock, pause: () async -> Void) async -> CGImage? {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            let step = 1 / Double(px), climb = UprightRock.climb, unit = Double(tile) * 0.8660254
            for (number, cell) in cells.enumerated() {
                if number % 4 == 3 { await pause() }
                for j in 0..<px {
                    let y = Double(cell.row) + (Double(j) + 0.5) * step
                    let row = side - 1 - ((cell.row - corner.row) * px + j)
                    for i in 0..<px {
                        let x = Double(cell.col) + (Double(i) + 0.5) * step
                        let here = Double(hill.height(atCells: x, y))
                        // How fast it rises across and up the map (points a cell), so where the pixel
                        // shows and what it covers there: a pixel across and up the map each.
                        let gx = (Double(hill.height(atCells: x + step, y)) - here) / step
                        let gy = (Double(hill.height(atCells: x, y + step)) - here) / step
                        let lift = here / climb
                        let ax = step * (1 + gx / climb), ay = step * gx / climb
                        let bx = step * gy / climb, by = step * (1 + gy / climb)
                        let across = min(2, max(1, Int((ax * ax + ay * ay).squareRoot() * Double(rock.width) + 0.5)))
                        let up = min(4, max(1, Int((bx * bx + by * by).squareRoot() * Double(rock.height) + 0.5)))
                        var red = 0.0, green = 0.0, blue = 0.0
                        for u in 0..<across {
                            for v in 0..<up {
                                let fu = (Double(u) + 0.5) / Double(across) - 0.5, fv = (Double(v) + 0.5) / Double(up) - 0.5
                                let texel = rock.colour(x + lift + fu * ax + fv * bx, y + lift + fu * ay + fv * by)
                                red += texel.red
                                green += texel.green
                                blue += texel.blue
                            }
                        }
                        // Its ledges, as the light has them on other rock (`strata`), where it faces you.
                        var shade = 1.0 / Double(across * up)
                        if let strata = look.strata {
                            let hx = gx / unit, hy = gy / unit
                            let rise = (hx * hx + hy * hy).squareRoot()
                            let facing = min(1, max(0, 2 * (hx + hy) / max(rise * 2.0.squareRoot(), 1e-6)))
                            let steep = min(1, max(0, (rise - 0.15) / 0.2)) * facing
                            let ragged = sin(x * 2.3 + 1.1) * sin(y * 1.9 + 0.3) * 0.5 + sin(x * 5.1) * sin(y * 4.7 + 2) * 0.3
                            let level = here + ragged * 6
                            let band = level / strata - (level / strata).rounded(.down)
                            if band < 0.18 {
                                shade *= 1 - 0.3 * steep
                            } else if band < 0.28 {
                                shade *= 1 + 0.1 * steep
                            }
                        }
                        let index = (row * side + (cell.col - corner.col) * px + i) * 4
                        bytes[index] = UInt8(min(255, red * shade))
                        bytes[index + 1] = UInt8(min(255, green * shade))
                        bytes[index + 2] = UInt8(min(255, blue * shade))
                        bytes[index + 3] = 255
                    }
                }
            }
            return PixelImage.make(bytes, width: side, height: side)
        }
        func paint(_ corner: GridPoint, pause: @escaping () async -> Void) async -> CGImage? {
            guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let offset = (x: (corner.col - low.col) * px, y: (corner.row - low.row) * px)
            context.translateBy(x: -CGFloat(offset.x), y: -CGFloat(offset.y))
            context.clip(to: whole)
            // The square's cells within the range's area and the map.
            // (A range where a road leads into a cave goes on past the map's edge; `ground` has
            // pictures for the land out there too.)
            let firstColumn = max(corner.col, low.col), firstRow = max(corner.row, low.row)
            let endColumn = min(corner.col + square, low.col + columns)
            let endRow = min(corner.row + square, low.row + rows)
            var area: [GridPoint] = []
            if firstColumn < endColumn, firstRow < endRow {
                for row in firstRow..<endRow {
                    for col in firstColumn..<endColumn { area.append(GridPoint(col: col, row: row)) }
                }
            }

            // The ground, tile by tile as the map has it: a few at a time, as the first sight of each
            // tile's picture is slow (a texture drawn into an image), and most of a coast's are its own.
            context.interpolationQuality = .none
            for (number, cell) in area.enumerated() {
                if number % 16 == 15 { await pause() }
                if let picture = look.ground(cell) { context.draw(picture, in: rect(cell)) }
            }
            if let bank = look.bank, let patches {
                context.saveGState()
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.interpolationQuality = .none
                let rockCells = area.filter { hill.cells.contains($0) }
                if let rockUpright, let picture = await uprightRock(corner, cells: rockCells, rockUpright, pause: pause) {
                    context.draw(picture, in: CGRect(x: CGFloat(offset.x), y: CGFloat(offset.y), width: CGFloat(side), height: CGFloat(side)))
                } else {
                    for cell in rockCells {
                        if let picture = bank(cell) { context.draw(picture, in: rect(cell)) }
                    }
                }
                context.interpolationQuality = .medium
                context.setBlendMode(.destinationIn)
                context.draw(patches, in: whole)
                context.endTransparencyLayer()
                context.restoreGState()
            }
            // The trails, worn into it in the map's road.
            if !stamps.isEmpty, area.contains(where: { worn.contains($0) }),
               let road = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                road.translateBy(x: -CGFloat(offset.x), y: -CGFloat(offset.y))
                road.clip(to: whole)
                road.interpolationQuality = .none
                for cell in area where worn.contains(cell) {
                    if let picture = look.trail(cell) { road.draw(picture, in: rect(cell)) }
                }
                await wear(context, road: road, marks: marks, wide: wide, offset: offset, pause: pause)
            }
            // The colour patches the rest of the ground has, then the light, then its outline.
            context.interpolationQuality = .medium
            if let variation = look.variation {
                context.draw(variation, in: CGRect(x: -CGFloat(low.col) * scale, y: -CGFloat(low.row) * scale,
                                                   width: CGFloat(look.mapSize.columns) * scale, height: CGFloat(look.mapSize.rows) * scale))
            }
            // Sunk ground's light is only how wet it is; its slope's is the shader's.
            await shade(context, light: light, samples: (sw, sh), perSample: Float(px) / Float(samples), offset: offset, tint: tint,
                        brightest: Float(look.brightest), pause: pause)
            // A bridge's deck over a sunk lake lies over the wet ground, not wet itself.
            if !look.overlays.isEmpty {
                context.interpolationQuality = .none
                for overlay in look.overlays {
                    context.draw(overlay.image, in: CGRect(x: (overlay.frame.minX - CGFloat(low.col)) * scale,
                                                           y: (overlay.frame.minY - CGFloat(low.row)) * scale,
                                                           width: overlay.frame.width * scale, height: overlay.frame.height * scale))
                }
                context.interpolationQuality = .medium
            }
            if let doorway { Self.cave(doorway, in: context, at: { spot($0) }) }
            if let outline {
                context.setBlendMode(.destinationIn)
                context.draw(outline, in: whole)
                context.setBlendMode(.normal)
            }
            return context.makeImage()
        }

        // Its heights, as a picture the shader reads (smoothly between samples, like
        // `Hill.height(atCells:_:)`): 255ths of its highest in red, and what's left over in green,
        // from its lowest (`base`: 0, or below for sunk ground). Not of its peak: where summits meet
        // the ground stands higher, and would be cut off.
        let base = min(0, hill.lowest)
        let peak = max(hill.highest - base, 1)
        var levels = [UInt8](repeating: 0, count: lattice.columns * lattice.rows * 4)
        for j in 0..<lattice.rows {
            for i in 0..<lattice.columns {
                let value = Double(CGFloat(hill.heights[j * lattice.columns + i]) - base) / Double(peak) * 255
                let units = min(255, max(0, value.rounded(.down)))
                let index = ((lattice.rows - 1 - j) * lattice.columns + i) * 4
                levels[index] = UInt8(units)
                levels[index + 1] = UInt8(min(255, max(0, ((value - units) * 255).rounded())))
                levels[index + 3] = 255
            }
        }
        guard let heightImage = image(levels, width: lattice.columns, height: lattice.rows) else { return nil }
        let heights = SKTexture(cgImage: heightImage)
        heights.filteringMode = .linear
        let shader = SKShader(source: Self.lifting)
        let sun = Sun.noon
        shader.uniforms = [
            SKUniform(name: "u_heights", texture: heights),
            SKUniform(name: "u_samples", vectorFloat4: SIMD4(Float(low.col), Float(low.row), Float(samples), Float(peak))),
            SKUniform(name: "u_sampleSize", vectorFloat2: SIMD2(Float(lattice.columns), Float(lattice.rows))),
            // The sun (`light(_:by:)` moves it); how dark the shade, how bright the sunniest slope
            // and the picture's pixels a cell; how the shade leans toward the shadow colour.
            SKUniform(name: "u_sun", vectorFloat4: SIMD4(Float(sun.x), Float(sun.y), Float(sun.z), Float(sun.strength))),
            SKUniform(name: "u_look", vectorFloat4: SIMD4(Float(Sun.shaded(ambient: ambient)), Float(look.brightest), Float(base), Float(px))),
            SKUniform(name: "u_lean", vectorFloat4: SIMD4(Float(1 - tint.0), Float(1 - tint.1), Float(1 - tint.2), 0)),
        ]
        shader.attributes = [
            SKAttribute(name: "a_box", type: .vectorFloat4),
            SKAttribute(name: "a_area", type: .vectorFloat4),
            SKAttribute(name: "a_band", type: .vectorFloat4),
        ]

        let across = WorldMap.project(CGPoint(x: tile, y: 0)).x
        // The cells that show in each square, by its corner, sorted out once (not the whole range
        // gone through again for every square: a coast's shore has thousands).
        func floored(_ value: Int) -> Int { value >= 0 ? value / square : -((-value + square - 1) / square) }
        let bySquare = Dictionary(grouping: shown) { cell in
            GridPoint(col: low.col + floored(cell.col - low.col) * square, row: low.row + floored(cell.row - low.row) * square)
        }
        /// The cells of the square from `corner` that show any of it.
        func cellsShown(from corner: GridPoint) -> [GridPoint] {
            bySquare[corner] ?? []
        }
        var corners: [GridPoint] = []
        for top in stride(from: low.row, to: low.row + rows, by: square) {
            for left in stride(from: low.col, to: low.col + columns, by: square) {
                let corner = GridPoint(col: left, row: top)
                if !cellsShown(from: corner).isEmpty { corners.append(corner) }
            }
        }
        func drawSquare(at corner: GridPoint, pause: @escaping () async -> Void) async -> [SKSpriteNode] {
            let own = cellsShown(from: corner)
            guard let picture = await paint(corner, pause: pause) else { return [] }
            var sprites: [SKSpriteNode] = []
            let texture = SKTexture(cgImage: picture)
            texture.filteringMode = .nearest
            // The strips a cell reaches into: a cell spans two of the map's diagonals.
            var bands: Set<Int> = []
            for cell in own {
                bands.insert((cell.col + cell.row) / depthOfStrips)
                bands.insert((cell.col + cell.row + 1) / depthOfStrips)
            }
            // How low and high the ground stands in each strip of the square: from the lattice's
            // points round it, the ground between them never higher or lower.
            var lifts: [Int: (low: Float, high: Float)] = [:]
            let i0 = max(0, (corner.col - low.col) * samples - 1), i1 = min(lattice.columns - 1, (corner.col + square - low.col) * samples + 1)
            let j0 = max(0, (corner.row - low.row) * samples - 1), j1 = min(lattice.rows - 1, (corner.row + square - low.row) * samples + 1)
            for j in j0...j1 {
                for i in i0...i1 {
                    let sum = Double(low.col + low.row) + Double(i + j) / Double(samples)
                    let level = hill.heights[j * lattice.columns + i]
                    let depth = Double(depthOfStrips)
                    let first = Int(((sum - 0.5 - depth) / depth).rounded(.up)), last = Int(((sum + 0.5) / depth).rounded(.down))
                    guard first <= last else { continue }
                    for band in first...last {
                        let known = lifts[band] ?? (low: level, high: level)
                        lifts[band] = (low: min(known.low, level), high: max(known.high, level))
                    }
                }
            }
            for band in bands.sorted() {
                let lift = lifts[band] ?? (low: 0, high: 0)
                // Across the screen, where the strip crosses the square (in cells, column less row).
                let from = Double(band * depthOfStrips), to = Double((band + 1) * depthOfStrips)
                let c0 = Double(corner.col), r0 = Double(corner.row), size = Double(square)
                var least = Double.infinity, most = -Double.infinity
                for sum in [from, to, c0 + r0 + size] where sum >= from && sum <= to {
                    let lowest = max(r0, sum - c0 - size), highest = min(r0 + size, sum - c0)
                    guard lowest <= highest else { continue }
                    least = min(least, sum - 2 * highest)
                    most = max(most, sum - 2 * lowest)
                }
                guard least <= most else { continue }
                let box = CGRect(x: CGFloat(least) * across - 1, y: CGFloat(from) * depthStep + CGFloat(lift.low) - 1,
                                 width: CGFloat(most - least) * across + 2,
                                 height: CGFloat(to - from) * depthStep + CGFloat(lift.high - lift.low) + 2)
                let sprite = SKSpriteNode(texture: texture, size: box.size)
                sprite.anchorPoint = .zero
                sprite.position = box.origin
                // Just behind its back edge, as `strip(at:)` says.
                sprite.zPosition = -CGFloat(to) * depthStep - 0.75
                sprite.shader = shader
                sprite.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(box.minX), Float(box.minY), Float(box.width), Float(box.height))),
                                forAttribute: "a_box")
                sprite.setValue(SKAttributeValue(vectorFloat4: SIMD4(Float(corner.col), Float(corner.row), Float(square), Float(square))),
                                forAttribute: "a_area")
                let reach: SIMD4<Float> = [Float(CGFloat(from) * depthStep), Float(CGFloat(to) * depthStep), lift.low - 0.5, lift.high + 0.5]
                sprite.setValue(SKAttributeValue(vectorFloat4: reach), forAttribute: "a_band")
                sprites.append(sprite)
            }
            return sprites
        }
        return Painter(corners: corners, draw: drawSquare)
    }

    /// Each pixel of a strip's sprite: the ground point that rises to it, found by halving (the ground
    /// under a spot only ever rises going up the screen, as a hill is never steeper than the view)
    /// between the lowest and highest the strip stands, then the square's picture there, if that
    /// point is in this strip and square (a hair either side, so no seam opens between strips).
    /// `WorldMap.project` and `unproject` in reverse; `tileSize` is 44.
    ///
    /// Then lit by the sun (`u_sun`) as `sunlight` has it, from how the ground slopes at the middle of
    /// the picture's pixel (its heights half a sample either side), so each pixel is one tone: in
    /// steps of 6% with a 4×4 ordered dither where one gives way to the next, as `shade` lights the
    /// picture, the shade leaning toward the map's shadow colour (`u_lean`). Flat ground stays as it
    /// is. Everything inline: SpriteKit's shaders can't count on helper functions seeing uniforms.
    private static let lifting = """
    void main() {
        vec2 spot = a_box.xy + v_tex_coord * a_box.zw;
        float low = spot.y - a_band.w;
        float high = spot.y - a_band.z;
        float across = spot.x / 0.70710678;
        for (int i = 0; i < 16; i++) {
            float middle = 0.5 * (low + high);
            float along = middle / 0.35355339;
            vec2 cell = vec2(along + across, along - across) * (0.5 / 44.0);
            vec2 at = ((cell - u_samples.xy) * u_samples.z + 0.5) / u_sampleSize;
            vec4 level = texture2D(u_heights, at);
            float lift = (level.r * 255.0 + level.g) / 255.0 * u_samples.w + u_look.z;
            if (middle + lift > spot.y) { high = middle; } else { low = middle; }
        }
        float ground = 0.5 * (low + high);
        float along = ground / 0.35355339;
        vec2 cell = vec2(along + across, along - across) * (0.5 / 44.0);
        vec2 at = ((cell - u_samples.xy) * u_samples.z + 0.5) / u_sampleSize;
        vec4 level = texture2D(u_heights, at);
        float lift = (level.r * 255.0 + level.g) / 255.0 * u_samples.w + u_look.z;
        vec2 uv = (cell - a_area.xy) / a_area.zw;
        if (ground < a_band.x - 0.3 || ground > a_band.y + 0.3 || abs(ground + lift - spot.y) > 0.3
            || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
            gl_FragColor = vec4(0.0);
        } else {
            vec4 paint = texture2D(u_texture, uv);
            vec2 pixel = floor(uv * a_area.zw * u_look.w);
            vec2 centre = a_area.xy + (pixel + 0.5) / u_look.w;
            vec2 base = ((centre - u_samples.xy) * u_samples.z + 0.5) / u_sampleSize;
            vec2 sideways = vec2(0.5 / u_sampleSize.x, 0.0);
            vec2 upward = vec2(0.0, 0.5 / u_sampleSize.y);
            vec4 east = texture2D(u_heights, base + sideways);
            vec4 west = texture2D(u_heights, base - sideways);
            vec4 north = texture2D(u_heights, base + upward);
            vec4 south = texture2D(u_heights, base - upward);
            float rise = u_samples.w / 255.0 * u_samples.z / (44.0 * 0.8660254);
            float hx = ((east.r - west.r) * 255.0 + (east.g - west.g)) * rise;
            float hy = ((north.r - south.r) * 255.0 + (north.g - south.g)) * rise;
            float facing = (u_sun.z - hx * u_sun.x - hy * u_sun.y) / sqrt(hx * hx + hy * hy + 1.0);
            float lit = u_look.x + (1.0 - u_look.x) * max(0.0, facing) / u_sun.z;
            lit = 1.0 + (lit - 1.0) * u_sun.w;
            if (abs(lit - 1.0) > 0.004) {
                vec2 row = vec2(pixel.x, 3.0 - mod(pixel.y, 4.0));
                vec2 fine = mod(row, 2.0);
                vec2 coarse = mod(floor(row * 0.5), 2.0);
                float order = 4.0 * mod(2.0 * fine.x + 3.0 * fine.y, 4.0) + mod(2.0 * coarse.x + 3.0 * coarse.y, 4.0);
                float steps = floor((lit - 1.0) / 0.06 + (order + 0.5) / 16.0);
                float tone = min(u_look.y, 1.0 + steps * 0.06);
                if (tone < 1.0) {
                    paint.rgb = paint.rgb * tone * (vec3(1.0) - (1.0 - tone) * 0.4 * u_lean.rgb);
                } else {
                    paint.rgb = min(paint.rgb * tone, vec3(paint.a));
                }
            }
            gl_FragColor = paint;
        }
    }
    """

    /// A spot along a trail's middle (in cells): how far the trail reaches either side of it (in
    /// cells), which way is uphill, and how far it's cut into the slope (0 on the flat at its foot and
    /// on the top, 1 on the slope).
    private struct Stamp {
        let x, y, width, upX, upY, cut: Double
    }

    /// A range's trails as stamps every eighth of a cell or so: worn paths that wander a little either
    /// side of their lines and narrow and widen as they go, each its own way. A smooth band of even
    /// width read as drawn on, not walked in.
    private static func stamps(of hill: WorldMap.Hill) -> [Stamp] {
        var stamps: [Stamp] = []
        for (number, trail) in hill.trails.enumerated() {
            let seed = Double(number * 7 + trail.lobe * 3)
            let phases: (Double, Double, Double, Double) = (seed * 1.31 + 0.4, seed * 2.17 + 1.9, seed * 0.73 + 2.6, seed * 1.91 + 0.8)
            var walked = 0.0
            let last = trail.points.count - 2
            for index in 0..<max(0, last + 1) {
                let from = trail.points[index], to = trail.points[index + 1]
                let ax = Double(from.x), ay = Double(from.y)
                let dx = Double(to.x) - ax, dy = Double(to.y) - ay
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 1e-9 else { continue }
                let count = max(1, Int((length / 0.12).rounded(.up)))
                for k in 0..<(index == last ? count + 1 : count) {
                    let f = Double(k) / Double(count)
                    let s = walked + length * f
                    let wide: Double = 0.07 * sin(0.9 * s + phases.0)
                    let wider: Double = 0.05 * sin(2.3 * s + phases.1)
                    let drift: Double = 0.08 * sin(1.7 * s + phases.2)
                    let wobble: Double = 0.05 * sin(4.1 * s + phases.3)
                    let shift = drift + wobble
                    let x = ax + dx * f - dy / length * shift
                    let y = ay + dy * f + dx / length * shift
                    let up = hill.uphill(of: trail.lobe, x, y)
                    let rise = hill.rise(of: trail.lobe, x, y)
                    stamps.append(Stamp(x: x, y: y, width: 0.3 + wide + wider, upX: up.x, upY: up.y, cut: min(1, 6 * rise * (1 - rise))))
                }
                walked += length
            }
        }
        return stamps
    }

    /// Wears the trails into a square's picture (`marks`, over the range's pixels `wide` across, bottom
    /// row first): the trail's pixels from `road` but for a few where the grass grows through, its
    /// uphill edge in shadow and its downhill edge a little lighter.
    /// `offset`: where the square's corner is in the range's pixels. `pause`: called every few rows.
    private static func wear(_ context: CGContext, road: CGContext, marks: [UInt8], wide: Int, offset: (x: Int, y: Int),
                             pause: () async -> Void) async {
        guard let data = context.data, let paved = road.data, wide > 0 else { return }
        let width = context.width, height = context.height
        let rowBytes = context.bytesPerRow, roadRowBytes = road.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let paving = paved.bindMemory(to: UInt8.self, capacity: roadRowBytes * height)
        let high = marks.count / wide
        for first in stride(from: 0, to: height, by: rowsAtATime) {
            await pause()
            marks.withUnsafeBufferPointer { marks in
                for y in first..<min(height, first + rowsAtATime) {
                    // Memory rows run top down; marks bottom up.
                    let row = height - 1 - y + offset.y
                    guard row >= 0, row < high else { continue }
                    for x in 0..<width {
                        let column = x + offset.x
                        guard column < wide else { break }
                        let mark = marks[row * wide + column]
                        guard mark > 0 else { continue }
                        let index = y * rowBytes + x * 4
                        guard bytes[index + 3] > 0 else { continue }
                        if mark == 3 {
                            // A tuft of grass here and there.
                            guard noise(column >> 1, row >> 1, 7) < 0.97 else { continue }
                            let from = y * roadRowBytes + x * 4
                            let cover = 1 - Float(paving[from + 3]) / 255
                            for channel in 0..<4 {
                                bytes[index + channel] = UInt8(min(255, Float(paving[from + channel]) + Float(bytes[index + channel]) * cover))
                            }
                        } else if mark == 2 {
                            for channel in 0..<3 { bytes[index + channel] = UInt8(Float(bytes[index + channel]) * 0.75) }
                        } else {
                            // Premultiplied: no channel brighter than the pixel is opaque.
                            let alpha = Float(bytes[index + 3])
                            for channel in 0..<3 { bytes[index + channel] = UInt8(min(alpha, Float(bytes[index + channel]) * 1.1)) }
                        }
                    }
                }
            }
        }
    }

    /// How many rows of a square's pixels `wear` and `shade` work through between pauses.
    private static let rowsAtATime = 32

    /// A steady scatter from 0 to 1 for a spot (`x`, `y`), a different one for each `kind`.
    private static func noise(_ x: Int, _ y: Int, _ kind: Int) -> Double {
        let mixed: Int = (x &* 73_856_093) ^ (y &* 19_349_663) ^ (kind &* 83_492_791)
        var value = UInt32(truncatingIfNeeded: mixed)
        value = (value ^ (value >> 13)) &* 0x5bd1_e995
        value ^= value >> 15
        return Double(value & 0xffff) / 65535
    }

    /// A cave's mouth (`WorldMap.Hill.Mouth`) as a doorway in the rock: its opening and the edge of
    /// the rock round it, each a rough arch over the mouth's foot, in cells.
    struct Doorway {
        let opening: [CGPoint]
        let rim: [CGPoint]
        /// Where light catches the rim's top, just inside its edge.
        let lip: [CGPoint]
        /// The middle of its floor and of its top, for the shade inside.
        let floor: CGPoint
        let top: CGPoint
    }

    /// A rock's tiles for painting it upright (`Look.upright`): each tile's pixels read once, and
    /// which tile each cell round a range has (as `Look.bank` gives them), out as far up the screen
    /// as its highest ground shows.
    struct UprightRock {
        /// A cell up the map's diagonal is this many points up the screen.
        static let climb = 2 * Double(depthStep)
        let tiles: [[UInt8]]
        let width: Int, height: Int
        let index: [Int]
        let from: GridPoint
        let columns: Int, rows: Int

        init?(bank: (GridPoint) -> CGImage?, from low: GridPoint, columns: Int, rows: Int, highest: CGFloat) {
            let reach = Int((Double(highest) / Self.climb).rounded(.up)) + 2
            let from = GridPoint(col: low.col - 1, row: low.row - 1)
            let wide = columns + reach + 2, deep = rows + reach + 2
            var tiles: [[UInt8]] = [], known: [ObjectIdentifier: Int] = [:]
            var index = [Int](repeating: 0, count: wide * deep)
            var size = (width: 0, height: 0)
            for r in 0..<deep {
                for c in 0..<wide {
                    guard let picture = bank(GridPoint(col: from.col + c, row: from.row + r)) else { continue }
                    if let seen = known[ObjectIdentifier(picture)] {
                        index[r * wide + c] = seen
                        continue
                    }
                    if tiles.isEmpty { size = (picture.width, picture.height) }
                    guard picture.width == size.width, picture.height == size.height,
                          let pixels = PixelImage.pixels(of: picture, width: size.width, height: size.height) else { continue }
                    known[ObjectIdentifier(picture)] = tiles.count
                    index[r * wide + c] = tiles.count
                    tiles.append(pixels)
                }
            }
            guard !tiles.isEmpty, size.width > 0, size.height > 0 else { return nil }
            self.tiles = tiles
            width = size.width
            height = size.height
            self.index = index
            self.from = from
            self.columns = wide
            self.rows = deep
        }

        /// The rock at a point of flat ground (in cells): its tile's pixel there.
        func colour(_ x: Double, _ y: Double) -> (red: Double, green: Double, blue: Double) {
            let col = Int(x.rounded(.down)), row = Int(y.rounded(.down))
            let c = min(max(col - from.col, 0), columns - 1), r = min(max(row - from.row, 0), rows - 1)
            let tile = tiles[index[r * columns + c]]
            let px = min(width - 1, max(0, Int((x - Double(col)) * Double(width))))
            let py = min(height - 1, max(0, height - 1 - Int((y - Double(row)) * Double(height))))
            let at = (py * width + px) * 4
            return (Double(tile[at]), Double(tile[at + 1]), Double(tile[at + 2]))
        }
    }

    /// The mouth's doorway, upright on the screen like a door in a wall, however the slope it's in
    /// leans: a round arch from its foot, leaning along the edge the way the map's diagonals do, its
    /// sides straight up only a little way (playtesting 2026-10-16: with them a third of the way up,
    /// it met its top in a sharp corner). The opening is 30 points tall and 14 more for each cell of its
    /// half-width (55 over a road 3 cells wide). Painted on the ground, each point of it is where
    /// the ground shows that far up the screen over its foot: up the map's diagonal (a cell of it
    /// is 31 points up the screen), plus however much the ground rises or falls on the way.
    static func doorway(_ mouth: WorldMap.Hill.Mouth, height: (Double, Double) -> Double) -> Doorway {
        let climb = 2 * Double(WorldMap.project(CGPoint(x: WorldMap.tileSize, y: 0)).y)
        /// The ground `up` points up the screen over the foot, `across` cells along from its middle.
        func point(_ across: Double, _ up: Double) -> CGPoint {
            let x = mouth.x + mouth.along.x * across, y = mouth.y + mouth.along.y * across
            let foot = height(x, y)
            // Ground up the screen never folds back under itself, so this only climbs.
            var low = 0.0, high = 8.0
            for _ in 0..<24 {
                let t = (low + high) / 2
                if climb * t + height(x + t, y + t) - foot < up { low = t } else { high = t }
            }
            let t = (low + high) / 2
            return CGPoint(x: x + t, y: y + t)
        }
        let tall = 30 + 14 * mouth.half
        /// Feet first, then up one side, over the top and down the other.
        func arch(_ half: Double, _ top: Double, rough: Double) -> [CGPoint] {
            let steps = 24, side = 0.08 * top
            var points = [point(-half, 0)]
            for k in 0...steps {
                let u = Double(k) / Double(steps)
                let bulge = max(0, 1 - (2 * u - 1) * (2 * u - 1)).squareRoot()
                let wobble = k == 0 || k == steps ? 0 : rough * sin(Double(k) * 2.3 + 0.7)
                points.append(point((2 * u - 1) * half, side + (top - side) * bulge + wobble))
            }
            points.append(point(half, 0))
            return points
        }
        let lip = arch(mouth.half + 0.32, tall + 6.5, rough: 2.5)
        return Doorway(opening: arch(mouth.half, tall, rough: 1), rim: arch(mouth.half + 0.45, tall + 9, rough: 2.5),
                       lip: Array(lip[3..<(lip.count - 3)]), floor: point(0, 0), top: point(0, tall))
    }

    /// Paints a cave's doorway on a hill's ground, in the face of its rock wall (`Hill.Wall`): a
    /// shadow round its edge, light catching the rock over its top, the opening black up under its
    /// top and a little lighter at its floor, where the road goes in. `at`: a point in cells in the
    /// picture's pixels.
    private static func cave(_ doorway: Doorway, in context: CGContext, at: (CGPoint) -> CGPoint) {
        func shape(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map(at))
            path.closeSubpath()
            return path
        }
        /// Its outline over the top, not along the floor.
        func line(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map(at))
            return path
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(line(doorway.rim))
        context.setStrokeColor(UIColor(white: 0, alpha: 0.3).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.addPath(line(doorway.lip))
        context.setStrokeColor(UIColor(white: 1, alpha: 0.3).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()
        let inside = [UIColor(red: 0.13, green: 0.11, blue: 0.14, alpha: 1).cgColor,
                      UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor] as CFArray
        context.saveGState()
        context.addPath(shape(doorway.opening))
        context.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: inside, locations: [0, 0.6]) {
            context.drawLinearGradient(gradient, start: at(doorway.floor), end: at(doorway.top),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
        context.addPath(line(doorway.opening))
        context.setStrokeColor(UIColor(white: 0, alpha: 0.7).cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }

    /// Lights a square's picture a pixel (a tile's pixel) at a time: how lit the slope is there, in
    /// steps of 6%, with a 4×4 ordered dither where one step gives way to the next, the way pixel art
    /// shades a hill in a few flat tones. A smooth gradient over pixel-art ground read as gloss.
    /// Shade leans toward the map's shadow colour (`tint`, its channels over its brightest).
    /// `offset`: where the square's corner is in the range's pixels, which `light` covers.
    /// `brightest`: no sunny slope lighter than this (`Look.brightest`). `pause`: called every few rows.
    private static func shade(_ context: CGContext, light: [Float], samples: (columns: Int, rows: Int), perSample: Float,
                              offset: (x: Int, y: Int), tint: (Double, Double, Double), brightest: Float,
                              pause: () async -> Void) async {
        guard let data = context.data else { return }
        let width = context.width, height = context.height, rowBytes = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let dither: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
        let step: Float = 0.06
        let lean = (Float(1 - tint.0), Float(1 - tint.1), Float(1 - tint.2))
        let sw = samples.columns, sh = samples.rows
        for first in stride(from: 0, to: height, by: rowsAtATime) {
            await pause()
            light.withUnsafeBufferPointer { light in
                for y in first..<min(height, first + rowsAtATime) {
                    // Memory rows run top down; samples bottom up.
                    let fy = (Float(height - 1 - y + offset.y) + 0.5) / perSample - 0.5
                    let j = max(0, min(sh - 2, Int(fy.rounded(.down))))
                    let ty = min(1, max(0, fy - Float(j)))
                    for x in 0..<width {
                        let index = y * rowBytes + x * 4
                        guard bytes[index + 3] > 0 else { continue }
                        let fx = (Float(x + offset.x) + 0.5) / perSample - 0.5
                        let i = max(0, min(sw - 2, Int(fx.rounded(.down))))
                        let a = light[j * sw + i], b = light[j * sw + i + 1]
                        let c = light[(j + 1) * sw + i], d = light[(j + 1) * sw + i + 1]
                        // Flat ground stays as it is.
                        if a == 1, b == 1, c == 1, d == 1 { continue }
                        let tx = min(1, max(0, fx - Float(i)))
                        let near = a + (b - a) * tx, far = c + (d - c) * tx
                        let lit = near + (far - near) * ty
                        let steps = ((lit - 1) / step + dither[(y % 4) * 4 + x % 4]).rounded()
                        guard steps != 0 else { continue }
                        let s = min(brightest, 1 + steps * step)
                        if s < 1 {
                            let toward = (1 - s) * 0.4
                            bytes[index] = UInt8(min(255, Float(bytes[index]) * s * (1 - toward * lean.0)))
                            bytes[index + 1] = UInt8(min(255, Float(bytes[index + 1]) * s * (1 - toward * lean.1)))
                            bytes[index + 2] = UInt8(min(255, Float(bytes[index + 2]) * s * (1 - toward * lean.2)))
                        } else {
                            // Premultiplied: no channel brighter than the pixel is opaque.
                            let alpha = Float(bytes[index + 3])
                            bytes[index] = UInt8(min(alpha, Float(bytes[index]) * s))
                            bytes[index + 1] = UInt8(min(alpha, Float(bytes[index + 1]) * s))
                            bytes[index + 2] = UInt8(min(alpha, Float(bytes[index + 2]) * s))
                        }
                    }
                }
            }
        }
    }

    /// Premultiplied RGBA bytes, top row first, as an image.
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
