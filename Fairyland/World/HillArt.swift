import SpriteKit

/// Draws a range of hills (`WorldMap.Hill`): the ground it rises over as pictures (the map's own
/// tiles, bare patches on its steepest slopes, its trails worn into it), lit from the upper left like
/// the trees' shadows say, then lifted off the map by its heights. The lifting is a small shader on
/// flat sprites over where it shows on screen: each pixel finds the ground point that rises to it
/// (`WorldMap.groundPoint`'s halving, against the same heights walkers stand on) and shows the
/// picture there. A warped sprite (`SKWarpGeometryGrid`) did the same, but SpriteKit crashed
/// subdividing grids that size.
///
/// A range is too big for one picture, so it's drawn in squares `square` cells a side; and too deep to
/// sort as one thing among the trees and walkers, so each square shows in strips `stripDepth` cells deep
/// (up the screen), each sorted just behind its back edge (`strip(at:)`): whatever stands on a strip or
/// in front of it is drawn over it, and whatever stands behind it is hidden by it.
enum HillArt {
    struct Look {
        /// The ground's tile pictures by cell, as the map has them.
        let ground: (GridPoint) -> CGImage?
        /// The trail's tile pictures by cell (the map's road).
        let trail: (GridPoint) -> CGImage?
        /// The rock (or sand, or chocolate) showing through on its slopes, by cell, if any.
        let bank: ((GridPoint) -> CGImage?)?
        /// How rocky the map's hills are (`WorldMap.rockiness`): the rockier, the more of the bank
        /// shows, further down the slopes, and the deeper the shade.
        let rocky: Double
        /// The soft colour patches over the map's whole ground: a pixel a cell, north at the top.
        let variation: CGImage?
        let mapSize: (columns: Int, rows: Int)
        /// Slopes in shade lean toward this colour, sunny ones toward the highlight.
        let shadow: (r: Double, g: Double, b: Double)
        let highlight: (r: Double, g: Double, b: Double)
    }

    /// Cells a side of each picture.
    static let square = 16
    /// Cells deep each strip is, along the map's diagonal (up the screen).
    static let stripDepth = 2
    /// How far up the screen a cell's depth is (a cell's diamond is twice this tall).
    private static let depthStep = WorldMap.project(CGPoint(x: WorldMap.tileSize, y: 0)).y
    /// How far up the screen each strip reaches.
    static let stripHeight = depthStep * CGFloat(stripDepth)

    /// The strip of raised ground over a point on the map (on the ground, not lifted): where it's
    /// sorted, just behind its back edge, and how far up the screen it begins. The strip in front of
    /// it is sorted `stripHeight` higher.
    static func strip(at ground: CGFloat) -> (z: CGFloat, start: CGFloat) {
        let band = (ground / stripHeight).rounded(.down)
        return (-(band + 1) * stripHeight - 0.75, band * stripHeight)
    }

    /// The range as sprites in the map's own space (put them straight in the world), each already
    /// sorted; none if it can't be drawn.
    static func sprites(for hill: WorldMap.Hill, look: Look) -> [SKSpriteNode] {
        guard let first = hill.cells.first, let sample = look.ground(first) else { return [] }
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

        // Per sample (between the lattice's points): how much bank shows, how it's lit, and where
        // it ends.
        let sw = columns * samples, sh = rows * samples
        var bare = [UInt8](repeating: 0, count: sw * sh * 4)
        var mask = [UInt8](repeating: 0, count: sw * sh * 4)
        // How bright each sample is lit, 1 on the flat (bottom row first, like the heights).
        var light = [Float](repeating: 1, count: sw * sh)
        // Sunlight from the upper left of the screen (up the map and to the left), 36° up. Soft: the
        // sides away from it go a few shades darker, the sides facing it only a shade lighter, so
        // the hill reads as matte ground rather than something glossy.
        let up = 36 * Double.pi / 180
        let toward = (x: -0.6, y: 1.0), length = (0.36 + 1.0).squareRoot()
        let sun = (x: toward.x / length * cos(up), y: toward.y / length * cos(up), z: sin(up))
        let ambient = 0.45 - 0.1 * look.rocky
        let flat = ambient + (1 - ambient) * sun.z
        let deepest = max(look.shadow.r, look.shadow.g, look.shadow.b, 0.01)
        let tint = (look.shadow.r / deepest, look.shadow.g / deepest, look.shadow.b / deepest)
        // The trails as worn paths (`stamps(of:)`), and how near each sample is to one: from its
        // edge, as if it reached an even 0.3 cells either side of its middle.
        let stamps = Self.stamps(of: hill)
        var nearness = [Float](repeating: .infinity, count: sw * sh)
        let around = Int(1.2 * Double(samples)) + 1
        for stamp in stamps {
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
        for j in 0..<sh {
            for i in 0..<sw {
                let x = Double(low.col) + (Double(i) + 0.5) / Double(samples)
                let y = Double(low.row) + (Double(j) + 0.5) / Double(samples)
                // Image rows run top down.
                let index = ((sh - 1 - j) * sw + i) * 4
                let field = hill.field(x, y)
                let trailDistance = Double(nearness[j * sw + i])
                // Its outline, softened, and its trails' starts out on the ground in front.
                var edge = min(1, max(0, (field + 0.06) / 0.25))
                if field < 0.2 { edge = max(edge, min(1, max(0, (0.5 - trailDistance) / 0.1))) }
                for channel in 0..<4 { mask[index + channel] = UInt8(edge * 255) }
                guard field > 0 else { continue }
                // How the slope faces the sun, from the heights walkers stand on (points a cell).
                // Heights stand 1/cos 30° taller than they're drawn.
                let h00 = Double(height(i, j)), h10 = Double(height(i + 1, j))
                let h01 = Double(height(i, j + 1)), h11 = Double(height(i + 1, j + 1))
                let gx = ((h10 + h11) - (h00 + h01)) / 2 * Double(samples)
                let gy = ((h01 + h11) - (h00 + h10)) / 2 * Double(samples)
                let hx = gx / Double(tile) / 0.866, hy = gy / Double(tile) / 0.866
                let lambert = (-hx * sun.x - hy * sun.y + sun.z) / (hx * hx + hy * hy + 1).squareRoot()
                var shade = (ambient + (1 - ambient) * max(0, lambert)) / flat
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
                if amount > 0 { amount *= min(1, max(0, (trailDistance - 0.55) / 0.3)) }
                for channel in 0..<4 { bare[index + channel] = UInt8(amount * 255) }
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
        for stamp in stamps {
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

        // The pictures, a square of cells at a time, all drawn in the range's own pixels (from its
        // corner, `low`).
        let whole = CGRect(x: 0, y: 0, width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        func rect(_ cell: GridPoint) -> CGRect {
            CGRect(x: CGFloat(cell.col - low.col) * scale, y: CGFloat(cell.row - low.row) * scale, width: scale, height: scale)
        }
        let side = square * px
        func paint(_ corner: GridPoint) -> CGImage? {
            guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let offset = (x: (corner.col - low.col) * px, y: (corner.row - low.row) * px)
            context.translateBy(x: -CGFloat(offset.x), y: -CGFloat(offset.y))
            context.clip(to: whole)
            // The square's cells within the range's area and the map.
            let firstColumn = max(corner.col, low.col, 0), firstRow = max(corner.row, low.row, 0)
            let endColumn = min(corner.col + square, low.col + columns, look.mapSize.columns)
            let endRow = min(corner.row + square, low.row + rows, look.mapSize.rows)
            var area: [GridPoint] = []
            if firstColumn < endColumn, firstRow < endRow {
                for row in firstRow..<endRow {
                    for col in firstColumn..<endColumn { area.append(GridPoint(col: col, row: row)) }
                }
            }

            // The ground, tile by tile as the map has it.
            context.interpolationQuality = .none
            for cell in area {
                if let picture = look.ground(cell) { context.draw(picture, in: rect(cell)) }
            }
            if let bank = look.bank, let patches {
                context.saveGState()
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.interpolationQuality = .none
                for cell in area where hill.cells.contains(cell) {
                    if let picture = bank(cell) { context.draw(picture, in: rect(cell)) }
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
                wear(context, road: road, marks: marks, wide: wide, offset: offset)
            }
            // The colour patches the rest of the ground has, then the light, then its outline.
            context.interpolationQuality = .medium
            if let variation = look.variation {
                context.draw(variation, in: CGRect(x: -CGFloat(low.col) * scale, y: -CGFloat(low.row) * scale,
                                                   width: CGFloat(look.mapSize.columns) * scale, height: CGFloat(look.mapSize.rows) * scale))
            }
            shade(context, light: light, samples: (sw, sh), perSample: Float(px) / Float(samples), offset: offset, tint: tint)
            if let outline {
                context.setBlendMode(.destinationIn)
                context.draw(outline, in: whole)
                context.setBlendMode(.normal)
            }
            return context.makeImage()
        }

        // Its heights, as a picture the shader reads (smoothly between samples, like
        // `Hill.height(atCells:_:)`): 255ths of its highest in red, and what's left over in green.
        // Not of its peak: where summits meet the ground stands higher, and would be cut off.
        let peak = max(hill.highest, 1)
        var levels = [UInt8](repeating: 0, count: lattice.columns * lattice.rows * 4)
        for j in 0..<lattice.rows {
            for i in 0..<lattice.columns {
                let value = Double(hill.heights[j * lattice.columns + i]) / Double(peak) * 255
                let units = min(255, max(0, value.rounded(.down)))
                let index = ((lattice.rows - 1 - j) * lattice.columns + i) * 4
                levels[index] = UInt8(units)
                levels[index + 1] = UInt8(min(255, max(0, ((value - units) * 255).rounded())))
                levels[index + 3] = 255
            }
        }
        guard let heightImage = image(levels, width: lattice.columns, height: lattice.rows) else { return [] }
        let heights = SKTexture(cgImage: heightImage)
        heights.filteringMode = .linear
        let shader = SKShader(source: Self.lifting)
        shader.uniforms = [
            SKUniform(name: "u_heights", texture: heights),
            SKUniform(name: "u_samples", vectorFloat4: SIMD4(Float(low.col), Float(low.row), Float(samples), Float(peak))),
            SKUniform(name: "u_sampleSize", vectorFloat2: SIMD2(Float(lattice.columns), Float(lattice.rows))),
        ]
        shader.attributes = [
            SKAttribute(name: "a_box", type: .vectorFloat4),
            SKAttribute(name: "a_area", type: .vectorFloat4),
            SKAttribute(name: "a_band", type: .vectorFloat4),
        ]

        // What shows: the range and a cell round it (its soft edge, its trails' feet).
        var shown: Set<GridPoint> = []
        for cell in hill.cells {
            for dr in -1...1 { for dc in -1...1 { shown.insert(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }
        }
        let across = WorldMap.project(CGPoint(x: tile, y: 0)).x
        var sprites: [SKSpriteNode] = []
        for top in stride(from: low.row, to: low.row + rows, by: square) {
            for left in stride(from: low.col, to: low.col + columns, by: square) {
                let corner = GridPoint(col: left, row: top)
                let own = shown.filter { cell in
                    let dc = cell.col - corner.col, dr = cell.row - corner.row
                    return dc >= 0 && dr >= 0 && dc < square && dr < square
                }
                guard !own.isEmpty, let picture = paint(corner) else { continue }
                let texture = SKTexture(cgImage: picture)
                texture.filteringMode = .nearest
                // The strips a cell reaches into: a cell spans two of the map's diagonals.
                var bands: Set<Int> = []
                for cell in own {
                    bands.insert((cell.col + cell.row) / stripDepth)
                    bands.insert((cell.col + cell.row + 1) / stripDepth)
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
                        let depth = Double(stripDepth)
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
                    let from = Double(band * stripDepth), to = Double((band + 1) * stripDepth)
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
            }
        }
        return sprites
    }

    /// Each pixel of a strip's sprite: the ground point that rises to it, found by halving (the ground
    /// under a spot only ever rises going up the screen, as a hill is never steeper than the view)
    /// between the lowest and highest the strip stands, then the square's picture there, if that
    /// point is in this strip and square (a hair either side, so no seam opens between strips).
    /// `WorldMap.project` and `unproject` in reverse; `tileSize` is 44.
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
            float lift = (level.r * 255.0 + level.g) / 255.0 * u_samples.w;
            if (middle + lift > spot.y) { high = middle; } else { low = middle; }
        }
        float ground = 0.5 * (low + high);
        float along = ground / 0.35355339;
        vec2 cell = vec2(along + across, along - across) * (0.5 / 44.0);
        vec2 at = ((cell - u_samples.xy) * u_samples.z + 0.5) / u_sampleSize;
        vec4 level = texture2D(u_heights, at);
        float lift = (level.r * 255.0 + level.g) / 255.0 * u_samples.w;
        vec2 uv = (cell - a_area.xy) / a_area.zw;
        if (ground < a_band.x - 0.3 || ground > a_band.y + 0.3 || abs(ground + lift - spot.y) > 0.3
            || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
            gl_FragColor = vec4(0.0);
        } else {
            gl_FragColor = texture2D(u_texture, uv);
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
    /// `offset`: where the square's corner is in the range's pixels.
    private static func wear(_ context: CGContext, road: CGContext, marks: [UInt8], wide: Int, offset: (x: Int, y: Int)) {
        guard let data = context.data, let paved = road.data, wide > 0 else { return }
        let width = context.width, height = context.height
        let rowBytes = context.bytesPerRow, roadRowBytes = road.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let paving = paved.bindMemory(to: UInt8.self, capacity: roadRowBytes * height)
        let high = marks.count / wide
        marks.withUnsafeBufferPointer { marks in
            for y in 0..<height {
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

    /// A steady scatter from 0 to 1 for a spot (`x`, `y`), a different one for each `kind`.
    private static func noise(_ x: Int, _ y: Int, _ kind: Int) -> Double {
        let mixed: Int = (x &* 73_856_093) ^ (y &* 19_349_663) ^ (kind &* 83_492_791)
        var value = UInt32(truncatingIfNeeded: mixed)
        value = (value ^ (value >> 13)) &* 0x5bd1_e995
        value ^= value >> 15
        return Double(value & 0xffff) / 65535
    }

    /// Lights a square's picture a pixel (a tile's pixel) at a time: how lit the slope is there, in
    /// steps of 6%, with a 4×4 ordered dither where one step gives way to the next, the way pixel art
    /// shades a hill in a few flat tones. A smooth gradient over pixel-art ground read as gloss.
    /// Shade leans toward the map's shadow colour (`tint`, its channels over its brightest).
    /// `offset`: where the square's corner is in the range's pixels, which `light` covers.
    private static func shade(_ context: CGContext, light: [Float], samples: (columns: Int, rows: Int), perSample: Float,
                              offset: (x: Int, y: Int), tint: (Double, Double, Double)) {
        guard let data = context.data else { return }
        let width = context.width, height = context.height, rowBytes = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let dither: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
        let step: Float = 0.06
        let lean = (Float(1 - tint.0), Float(1 - tint.1), Float(1 - tint.2))
        let sw = samples.columns, sh = samples.rows
        light.withUnsafeBufferPointer { light in
            for y in 0..<height {
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
                    let s = min(1 + step, 1 + steps * step)
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

    /// Premultiplied RGBA bytes, top row first, as an image.
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
