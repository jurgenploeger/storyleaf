import SpriteKit

/// A cave's rock (and the crags outside where a road leads into one, `WorldMap.Crag`), drawn as
/// raised walls you pass in front of and disappear behind. Each cell
/// near the floor gets a depth-sorted block: a shaded stone top and lit faces where the rock
/// drops to the floor. The outline runs through the middles of the cells (marching squares),
/// so corners are cut at 45° instead of stepping in sharp right angles: on screen, walls that
/// would zig-zag run straight. Rock deeper in is one flat raised layer underneath. Walls stay
/// solid: whoever walks behind one is hidden, and their name tag shows where they are.
final class CaveWalls {
    /// Faces, edges and soft shadows (in points) around each block's texture.
    private static let pad: CGFloat = 10
    /// The tops of the walls are in shadow, so they stand apart from the lit floor.
    private static let topShade: CGFloat = 0.45
    /// Straight pieces per rounded corner.
    private static let arcSteps = 6

    /// A cave's walls: its rock, and beyond the map rock too but for the tunnels the roads leave by.
    convenience init(map: WorldMap, cave: MapDef.Cave, world: SKNode, art: ArtLibrary, margin: Int) {
        var mouths: Set<GridPoint> = []
        for exit in map.def.exits {
            for i in 0..<margin {
                switch exit.edge {
                case .north, .south:
                    let edgeRow = exit.edge == .north ? map.rows - 1 : 0
                    for col in 0..<map.columns where !map.rock.contains(GridPoint(col: col, row: edgeRow)) {
                        mouths.insert(GridPoint(col: col, row: exit.edge == .north ? map.rows + i : -1 - i))
                    }
                case .east, .west:
                    let edgeCol = exit.edge == .east ? map.columns - 1 : 0
                    for row in 0..<map.rows where !map.rock.contains(GridPoint(col: edgeCol, row: row)) {
                        mouths.insert(GridPoint(col: exit.edge == .east ? map.columns + i : -1 - i, row: row))
                    }
                }
            }
        }
        func isRock(_ cell: GridPoint) -> Bool {
            map.contains(cell) ? map.rock.contains(cell) : !mouths.contains(cell)
        }
        self.init(map: map, rock: cave.rock, height: CGFloat(cave.height ?? 40), topShade: CaveWalls.topShade,
                  world: world, art: art, margin: margin, isRock: isRock)
    }

    /// Walls of `rock` (a tile) `height` points tall wherever `isRock` says, in the map and out past
    /// its edge to `margin` cells, their tops `topShade` darker than the rock. `rows` and `columns`
    /// narrow where to look, if the rock is all in one part of that.
    /// A tier of rock on top of another stands `lift` points up, its floor the top of the one under
    /// it, and `layer` (its tier) sorts it over that one where they meet. `deepFrom`: how many cells
    /// from its floor its rock can be the flat layer, if the default (about its height) isn't far
    /// enough, as when a high tier stands in front of lower ground. `craggy` rock, out in the open,
    /// has cut corners instead of rounded ones and cracks and ledges in its faces.
    init(map: WorldMap, rock: String, height: CGFloat, topShade: CGFloat, world: SKNode, art: ArtLibrary, margin: Int,
         lift: CGFloat = 0, layer: Int = 0, deepFrom: Int? = nil, craggy: Bool = false,
         rows: Range<Int>? = nil, columns: Range<Int>? = nil, isRock: (GridPoint) -> Bool) {
        let tile = WorldMap.tileSize
        // Every top uses the same tile, lined up with the flat layer, so they meet seamlessly.
        let top = art.tileVariant(rock, 0).cgImage()
        let side = art.tileVariant(rock, 1).cgImage()

        let topTexture = SKTexture(cgImage: top)
        topTexture.filteringMode = .nearest
        let group = SKTileGroup(tileDefinition: SKTileDefinition(texture: topTexture, size: CGSize(width: tile, height: tile)))
        let deep = SKTileMapNode(tileSet: SKTileSet(tileGroups: [group]), columns: map.columns + margin * 2, rows: map.rows + margin * 2,
                                 tileSize: CGSize(width: tile, height: tile))
        deep.anchorPoint = .zero
        deep.color = .black
        deep.colorBlendFactor = topShade
        deep.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        // Rock this far from the floor is hidden behind the blocks in front of it, so it can be the
        // flat layer: about as many cells as the walls are tall, up the screen.
        let depthStep = WorldMap.project(CGPoint(x: tile, y: 0)).y
        let near = max(2, deepFrom ?? Int((height / depthStep).rounded(.up)) - 1)

        // Which blocks go where. A rock cell's block shows all of its rock; a floor cell in a
        // corner between walls gets a sliver of rock in that corner, sorted by where it sits.
        var pending: [(cell: GridPoint, key: Int, z: CGFloat)] = []
        for row in rows ?? (-margin..<(map.rows + margin)) {
            for col in columns ?? (-margin..<(map.columns + margin)) {
                let cell = GridPoint(col: col, row: row)
                var mask = 0
                for dr in -1...1 {
                    for dc in -1...1 where isRock(GridPoint(col: col + dc, row: row + dr)) { mask |= 1 << ((dr + 1) * 3 + dc + 1) }
                }
                let center = WorldMap.project(CGPoint(x: (CGFloat(col) + 0.5) * tile, y: (CGFloat(row) + 0.5) * tile))
                // Craggy rock's blocks come in three versions, their cracks in different places.
                let variant = craggy ? Self.variant(col, row) << 12 : 0
                if isRock(cell) {
                    // Only rock near the floor needs its own block; the rest is the flat layer.
                    let nearFloor = (-near...near).contains { dr in (-near...near).contains { dc in !isRock(GridPoint(col: col + dc, row: row + dr)) } }
                    if nearFloor {
                        pending.append((cell, mask | variant, -center.y))
                    } else {
                        deep.setTileGroup(group, forColumn: col + margin, row: row + margin)
                    }
                } else {
                    for corner in 0..<4 where Self.fills(mask: mask, corner: corner) {
                        let quarter = WorldMap.project(CGPoint(x: (CGFloat(col) + 0.25 + 0.5 * CGFloat(corner & 1)) * tile,
                                                               y: (CGFloat(row) + 0.25 + 0.5 * CGFloat(corner >> 1)) * tile))
                        pending.append((cell, mask | (corner + 1) << 9 | variant, -quarter.y))
                    }
                }
            }
        }

        let keys = Array(Set(pending.map(\.key))).sorted()
        let (textures, blockSize) = Self.atlas(keys: keys, top: top, side: side, height: height, topShade: topShade, craggy: craggy)
        guard textures.count == keys.count else { return }
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        let half = WorldMap.project(CGPoint(x: tile, y: tile)).y / 2
        for block in pending {
            guard let i = index[block.key] else { continue }
            let node = SKSpriteNode(texture: textures[i], size: blockSize)
            let center = WorldMap.project(CGPoint(x: (CGFloat(block.cell.col) + 0.5) * tile, y: (CGFloat(block.cell.row) + 0.5) * tile))
            node.anchorPoint = CGPoint(x: 0.5, y: Self.pad / blockSize.height)
            node.position = center + CGVector(dx: 0, dy: lift - half)
            node.zPosition = block.z + CGFloat(layer) * 0.01
            world.addChild(node)
        }

        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(deep)
        squash.position.y = lift + height
        squash.zPosition = -99_000 + CGFloat(layer)
        world.addChild(squash)
    }

    // MARK: Shapes

    /// The rock in one block, in the cell's own grid units (0...1, x east, y north): the tops,
    /// and the outline pieces with their normals pointing from the rock out to the floor.
    private struct Shape {
        var tops: [[CGPoint]] = []
        /// `along`: how far along the wall (grid units) the piece starts, so the face texture runs on.
        var edges: [(a: CGPoint, b: CGPoint, normal: CGVector, along: CGFloat)] = []
    }

    /// Whether `mask` (bit `(dy + 1) * 3 + dx + 1` set for each rock cell around this one) is
    /// rock at that offset.
    private static func rock(_ mask: Int, _ dx: Int, _ dy: Int) -> Bool {
        mask & (1 << ((dy + 1) * 3 + dx + 1)) != 0
    }

    /// The corner of a floor cell (bit 0: east, bit 1: north) between three rock cells.
    private static func fills(mask: Int, corner: Int) -> Bool {
        let x = corner & 1 == 1 ? 1 : -1, y = corner >> 1 == 1 ? 1 : -1
        return !rock(mask, 0, 0) && rock(mask, x, 0) && rock(mask, 0, y) && rock(mask, x, y)
    }

    /// Marching squares over the cell middles, one quarter of the cell at a time, with every
    /// corner rounded: a quarter circle around the cell's middle, bulging out where the rock
    /// sticks out and hollowed where it goes in. Neighbouring arcs and straight walls meet
    /// without a kink, so walls that would zig-zag become gentle waves. Key: the 3×3 rock mask,
    /// plus (for a floor cell's corner sliver) `(corner + 1) << 9`, plus a craggy block's version
    /// `<< 12`. `steps`: straight pieces a corner, 1 cutting it off straight.
    private static func shape(for key: Int, steps arcSteps: Int) -> Shape {
        let mask = key & 511
        let only = ((key >> 9) & 7) - 1
        var result = Shape()
        for corner in 0..<4 where only < 0 || corner == only {
            let x = corner & 1 == 1 ? 1 : -1, y = corner >> 1 == 1 ? 1 : -1
            let sx = CGFloat(x), sy = CGFloat(y)
            // (p, q) runs from the cell's middle (0, 0) out to its corner (0.5, 0.5).
            func at(_ p: CGFloat, _ q: CGFloat) -> CGPoint { CGPoint(x: 0.5 + sx * p, y: 0.5 + sy * q) }
            let here = rock(mask, 0, 0), across = rock(mask, x, 0), above = rock(mask, 0, y), diagonal = rock(mask, x, y)
            let angles = (0...arcSteps).map { CGFloat($0) / CGFloat(arcSteps) * .pi / 2 }
            let arc = angles.map { at(0.5 * cos($0), 0.5 * sin($0)) }
            let step = 0.5 * .pi / 2 / CGFloat(arcSteps)
            if here {
                if !across && !above {
                    // A corner sticking out: rounded off.
                    result.tops.append([at(0, 0)] + arc)
                    for i in 0..<arcSteps {
                        let middle = (angles[i] + angles[i + 1]) / 2
                        result.edges.append((arc[i], arc[i + 1], CGVector(dx: sx * cos(middle), dy: sy * sin(middle)), CGFloat(i) * step))
                    }
                } else {
                    result.tops.append([at(0, 0), at(0.5, 0), at(0.5, 0.5), at(0, 0.5)])
                    if !across && !diagonal { result.edges.append((at(0.5, 0), at(0.5, 0.5), CGVector(dx: sx, dy: 0), 0)) }
                    if !above && !diagonal { result.edges.append((at(0, 0.5), at(0.5, 0.5), CGVector(dx: 0, dy: sy), 0)) }
                }
            } else if across && above && diagonal {
                // A corner going in: a rounded hollow.
                result.tops.append(arc + [at(0.5, 0.5)])
                for i in 0..<arcSteps {
                    let middle = (angles[i] + angles[i + 1]) / 2
                    result.edges.append((arc[i], arc[i + 1], CGVector(dx: -sx * cos(middle), dy: -sy * sin(middle)), CGFloat(i) * step))
                }
            }
        }
        return result
    }

    /// Which of three versions a craggy block at a cell is: a hash, so neighbours differ.
    private static func variant(_ col: Int, _ row: Int) -> Int {
        Int(scatter(col &* 92_821 ^ row, 0) * 2.999)
    }

    /// A steady scatter from 0 to 1 for a seed and a number.
    private static func scatter(_ seed: Int, _ number: Int) -> CGFloat {
        var value = UInt32(truncatingIfNeeded: (seed &* 7_919) ^ (number &* 104_729))
        value = (value ^ (value >> 15)) &* 0x2C1B_3C6D
        value = (value ^ (value >> 12)) &* 0x297A_2D39
        value ^= value >> 15
        return CGFloat(value & 0xFFFF) / 65_535
    }

    // MARK: Drawing

    /// Every block that's needed, in one texture so they draw together, in the order of `keys`.
    /// Also returns a block's size in points.
    private static func atlas(keys: [Int], top: CGImage, side: CGImage, height: CGFloat, topShade: CGFloat,
                              craggy: Bool) -> ([SKTexture], CGSize) {
        let tile = WorldMap.tileSize
        let c = CGFloat(0.5).squareRoot()
        let width = 2 * tile * c
        let cell = CGSize(width: width + pad * 2, height: tile * c + height + pad * 2)
        let columns = 16
        let rows = max(1, (keys.count + columns - 1) / columns)
        // Two pixels per point, unless that would make the sheet too big.
        let scale: CGFloat = CGFloat(rows) * (cell.height * 2 + 2) > 8000 ? 1 : 2
        let cellPixels = (w: Int((cell.width * scale).rounded(.up)) + 2, h: Int((cell.height * scale).rounded(.up)) + 2)
        let size = (w: cellPixels.w * columns, h: cellPixels.h * rows)
        guard let context = CGContext(data: nil, width: size.w, height: size.h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return ([], cell) }
        context.interpolationQuality = .none
        let lift = CGVector(dx: 0, dy: height)
        let space = CGColorSpaceCreateDeviceRGB()
        func gradient(_ from: UIColor, _ to: UIColor) -> CGGradient {
            CGGradient(colorsSpace: space, colors: [from.cgColor, to.cgColor] as CFArray, locations: [0, 1])!
        }
        let darkToFloor = gradient(UIColor(white: 0, alpha: 0.45), UIColor(white: 0, alpha: 0))
        let lipShine = gradient(UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.22))
        let shadow = gradient(UIColor(white: 0, alpha: 0.4), UIColor(white: 0, alpha: 0))

        /// A point in the cell's grid units, on the floor, in block points.
        func floor(_ p: CGPoint) -> CGPoint {
            CGPoint(x: width / 2 + (p.x - p.y) * c * tile, y: (p.x + p.y) * c * tile / 2)
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: UIColor, _ lineWidth: CGFloat) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
        }
        /// A wall face from `a` to `b` along the floor (`length` in grid points), up to the top:
        /// the rock texture sheared onto it, shaded darker toward the floor, with light rounding
        /// over the lip; craggy, a crack and a ledge here and there (where `cracks` says).
        func face(_ a: CGPoint, _ b: CGPoint, length: CGFloat, start: CGFloat, shade: CGFloat, cracks: Int?) {
            guard length > 0 else { return }
            context.saveGState()
            context.concatenate(CGAffineTransform(a: (b.x - a.x) / length, b: (b.y - a.y) / length, c: 0, d: 1, tx: a.x, ty: a.y))
            let rect = CGRect(x: 0, y: 0, width: length, height: height)
            context.clip(to: rect)
            var y: CGFloat = 0
            while y < height {
                var x = -start.truncatingRemainder(dividingBy: tile)
                while x < length {
                    context.draw(side, in: CGRect(x: x, y: y, width: tile, height: tile))
                    x += tile
                }
                y += tile
            }
            context.setFillColor(UIColor(white: 0, alpha: shade).cgColor)
            context.fill(rect)
            context.drawLinearGradient(darkToFloor, start: .zero, end: CGPoint(x: 0, y: height * 0.7), options: [])
            context.drawLinearGradient(lipShine, start: CGPoint(x: 0, y: height - 7), end: CGPoint(x: 0, y: height), options: [])
            if let cracks {
                func scatter(_ n: Int) -> CGFloat { CaveWalls.scatter(cracks, n) }
                context.setLineCap(.butt)
                context.setLineWidth(1)
                if scatter(0) < 0.7 {
                    // A crack up from the foot, wandering a little.
                    let x = length * (0.2 + 0.6 * scatter(1)), reach = height * (0.35 + 0.55 * scatter(2))
                    context.move(to: CGPoint(x: x, y: 0))
                    context.addLine(to: CGPoint(x: x + (scatter(3) - 0.5) * 4, y: reach * 0.5))
                    context.addLine(to: CGPoint(x: x + (scatter(4) - 0.5) * 6, y: reach))
                    context.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
                    context.strokePath()
                }
                if scatter(5) < 0.6 {
                    // A ledge: light along its top, its shadow under it.
                    let y = height * (0.3 + 0.5 * scatter(6))
                    let from = length * 0.6 * scatter(7), to = min(length, from + length * (0.3 + 0.4 * scatter(8)))
                    context.move(to: CGPoint(x: from, y: y))
                    context.addLine(to: CGPoint(x: to, y: y))
                    context.setStrokeColor(UIColor(white: 1, alpha: 0.16).cgColor)
                    context.strokePath()
                    context.move(to: CGPoint(x: from, y: y - 1))
                    context.addLine(to: CGPoint(x: to, y: y - 1))
                    context.setStrokeColor(UIColor(white: 0, alpha: 0.22).cgColor)
                    context.strokePath()
                }
            }
            context.restoreGState()
        }
        /// A soft shadow on the floor in front of a face (`out` points away from the wall).
        func floorShadow(_ a: CGPoint, _ b: CGPoint, out: CGVector) {
            let path = CGMutablePath()
            path.addLines(between: [a, b, b + out, a + out])
            path.closeSubpath()
            context.saveGState()
            context.addPath(path)
            context.clip()
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            context.drawLinearGradient(shadow, start: mid, end: mid + out, options: [])
            context.restoreGState()
        }

        var textures: [SKTexture] = []
        for (index, key) in keys.enumerated() {
            let piece = Self.shape(for: key, steps: craggy ? 1 : arcSteps)
            let origin = CGPoint(x: CGFloat((index % columns) * cellPixels.w + 1), y: CGFloat((index / columns) * cellPixels.h + 1))
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: pad, y: pad)

            // Faces you can see point toward the camera (down the screen); the far ones first.
            let front = piece.edges.filter { $0.normal.dx + $0.normal.dy < 0 }
                .sorted { $0.a.x + $0.a.y + $0.b.x + $0.b.y > $1.a.x + $1.a.y + $1.b.x + $1.b.y }
            for edge in front {
                let n = edge.normal, length = (n.dx * n.dx + n.dy * n.dy).squareRoot()
                let out = CGVector(dx: (n.dx - n.dy) * c / length * pad * 0.9, dy: (n.dx + n.dy) * c / 2 / length * pad * 0.9)
                floorShadow(floor(edge.a), floor(edge.b), out: out)
            }
            for (number, edge) in front.enumerated() {
                let n = edge.normal, length = (n.dx * n.dx + n.dy * n.dy).squareRoot()
                // Lit from the left: faces turned west are brightest, faces turned south darkest.
                let shade = 0.22 + 0.1 * (n.dx - n.dy) / length
                face(floor(edge.a), floor(edge.b), length: edge.a.distance(to: edge.b) * tile, start: edge.along * tile, shade: shade,
                     cracks: craggy ? key * 8 + number : nil)
            }

            // The top: the rock tile laid over the lifted outline, a hair bigger than the cell so
            // neighbouring tops overlap instead of leaving seams.
            if !piece.tops.isEmpty {
                let outline = CGMutablePath()
                for polygon in piece.tops {
                    outline.addLines(between: polygon.map { p in
                        floor(CGPoint(x: 0.5 + (p.x - 0.5) * 1.03, y: 0.5 + (p.y - 0.5) * 1.03)) + lift
                    })
                    outline.closeSubpath()
                }
                context.saveGState()
                context.addPath(outline)
                context.clip()
                context.concatenate(CGAffineTransform(a: c, b: c / 2, c: -c, d: c / 2, tx: width / 2, ty: height))
                let cover = CGRect(x: -2, y: -2, width: tile + 4, height: tile + 4)
                context.draw(top, in: cover)
                context.setFillColor(UIColor(white: 0, alpha: topShade).cgColor)
                context.fill(cover)
                context.restoreGState()
            }

            // Light catches the lips above the faces; where the rock drops away out of sight
            // there's a dark rim.
            for edge in piece.edges {
                let facing = edge.normal.dx + edge.normal.dy
                let color = facing < 0 ? UIColor(white: 1, alpha: 0.4) : UIColor(white: 0, alpha: 0.5)
                line(floor(edge.a) + lift, floor(edge.b) + lift, color, 1.5)
            }
            context.restoreGState()
        }

        guard let image = context.makeImage() else { return ([], cell) }
        let sheet = SKTexture(cgImage: image)
        sheet.filteringMode = .nearest
        for index in keys.indices {
            let origin = CGPoint(x: CGFloat((index % columns) * cellPixels.w + 1), y: CGFloat((index / columns) * cellPixels.h + 1))
            let rect = CGRect(x: origin.x / CGFloat(size.w), y: origin.y / CGFloat(size.h),
                              width: cell.width * scale / CGFloat(size.w), height: cell.height * scale / CGFloat(size.h))
            let texture = SKTexture(rect: rect, in: sheet)
            texture.filteringMode = .nearest
            textures.append(texture)
        }
        return (textures, cell)
    }
}
