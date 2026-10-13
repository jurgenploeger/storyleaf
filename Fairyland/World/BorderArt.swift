import SpriteKit

/// What stands on a border between two lands (`Continent.Neighbour`), as RuneScape walls off what
/// you can't reach yet: a wooden fence along a border no road crosses, a line of boulders where
/// either land's ground is rocky (sand, snow, scree, desert), or beside a town a stone city wall
/// with towers; the same with a stone arch over a road a quest opens, barred and signed "Closed"
/// until it's done; nothing along a road's open border, where the two lands simply meet.
///
/// It stands on the line between the two lands, drawn the same by both (the same pictures, graded
/// with the same land's palette, the same random stones), so it's there whichever of them is built,
/// and where both are, the two lie exactly over each other.
enum BorderArt {
    /// The middle of a cell's stretch of `edge` (the cell `index` along it), on screen in the land's
    /// own points.
    static func point(along index: Int, of edge: Edge, columns: Int, rows: Int) -> CGPoint {
        corner(along: CGFloat(index) + 0.5, of: edge, columns: columns, rows: rows)
    }

    /// A point `along` cells along `edge` (from its south or west end), on screen.
    private static func corner(along: CGFloat, of edge: Edge, columns: Int, rows: Int) -> CGPoint {
        let tile = WorldMap.tileSize
        let grid: CGPoint = switch edge {
        case .east: CGPoint(x: CGFloat(columns), y: along)
        case .west: CGPoint(x: 0, y: along)
        case .north: CGPoint(x: along, y: CGFloat(rows))
        case .south: CGPoint(x: along, y: 0)
        }
        return WorldMap.project(CGPoint(x: grid.x * tile, y: grid.y * tile))
    }

    /// Whether a border is walled with boulders rather than a fence: either land's ground is rocky.
    static func isRocky(_ a: MapDef, _ b: MapDef) -> Bool {
        [a, b].contains { def in ["desert", "sand", "scree", "snow"].contains { def.theme.ground.contains($0) } }
    }

    /// Whether a border is walled with a city wall: one of the two lands is a town.
    static func isTown(_ a: MapDef, _ b: MapDef) -> Bool {
        a.fence == true || b.fence == true
    }

    /// The palette both lands draw a border's wall in: the first of the two by id.
    private static func sharedPalette(_ a: MapDef, _ b: MapDef) -> MapPalette? {
        (a.id < b.id ? a : b).theme.palette
    }

    /// Sets the wall along `neighbour`'s border with `here` into `parent(at:)` (`here`'s chunks).
    /// `open`: a quest's gate is open already. `dry`: whether there's land either side of the line at
    /// a cell along it (`WorldMap.isOpenSea`, the same from both lands): no wall where the sea's come
    /// in over the coast. Returns the bar across a shut gate and its sign, to take away once the quest
    /// is done.
    static func place(_ neighbour: Continent.Neighbour, of here: MapDef, open: Bool, art: ArtLibrary,
                      dry: (Int) -> Bool, into parent: (CGPoint) -> SKNode) -> [SKNode] {
        guard neighbour.isWalled, let origin = Continent.origin(of: here) else { return [] }
        let columns = here.width, rows = here.height, edge = neighbour.edge
        let palette = sharedPalette(here, neighbour.def)
        func put(_ node: SKNode) {
            node.zPosition = -node.position.y
            parent(node.position).addChild(node)
        }
        // A quest's gate: the road's cells either side, as `Continent.Neighbour.isOpen` lets you through.
        let gate: ClosedRange<Int>? = neighbour.quest == nil ? nil : neighbour.road.map { ($0 - Continent.gateReach)...($0 + Continent.gateReach) }
        let alongColumns = edge == .north || edge == .south

        if isTown(here, neighbour.def) {
            // A city wall: a stretch of stone a cell, its blocks running on from one to the next, and
            // towers at its ends, every 8 cells between and either side of a gate.
            guard let stones = wallPicture(palette: palette),
                  let wall = TownFence.railing(stones, posts: (0, 1), height: wallHeight, alongColumns: alongColumns),
                  let tower = towerPicture(palette: palette) else { return [] }
            for index in neighbour.span where gate?.contains(index) != true && dry(index) {
                let node = SKSpriteNode(texture: wall.texture, size: wall.size)
                node.anchorPoint = wall.anchor
                node.position = point(along: index, of: edge, columns: columns, rows: rows)
                put(node)
            }
            // A tower at each end of each stretch of wall (the coast can cut it short), and every 8 between.
            var towers: Set<Int> = []
            for run in runs(neighbour.span.filter(dry)) {
                towers.insert(run.lowerBound)
                towers.insert(run.upperBound + 1)
                for along in stride(from: run.lowerBound + 8, to: run.upperBound - 3, by: 8) {
                    if let gate, ((gate.lowerBound - 3)...(gate.upperBound + 4)).contains(along) { continue }
                    towers.insert(along)
                }
            }
            if let gate {
                towers.insert(gate.lowerBound)
                towers.insert(gate.upperBound + 1)
            }
            let texture = SKTexture(cgImage: tower)
            texture.filteringMode = .nearest
            for along in towers.sorted() {
                let node = SKSpriteNode(texture: texture, size: towerSize)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.06)
                node.position = corner(along: CGFloat(along), of: edge, columns: columns, rows: rows)
                put(node)
            }
            guard let gate else { return [] }
            return gateway(gate, neighbour, columns: columns, rows: rows, open: open, palette: palette, art: art, into: parent)
        }

        if gate == nil, isRocky(here, neighbour.def) {
            // A tumble of boulders along the line, the same stones from either side: each picked by
            // where its stretch of border lies on the continent.
            let kinds = ["boulder", "small_boulder"].compactMap { id -> (texture: SKTexture, size: CGSize)? in
                guard let image = art.gradedTile(id, palette: palette) else { return nil }
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .nearest
                return (texture, art.sprite(id).size)
            }
            guard !kinds.isEmpty else { return [] }
            for index in neighbour.span where dry(index) {
                let world: GridPoint = switch edge {
                case .east: GridPoint(col: origin.col + columns, row: origin.row + index)
                case .west: GridPoint(col: origin.col, row: origin.row + index)
                case .north: GridPoint(col: origin.col + index, row: origin.row + rows)
                case .south: GridPoint(col: origin.col + index, row: origin.row)
                }
                var random = SeededRandom(text: "border \(world.col),\(world.row)")
                guard Double.random(in: 0..<1, using: &random) < 0.85 else { continue }
                let kind = kinds[Int.random(in: 0..<kinds.count, using: &random)]
                let scale = CGFloat.random(in: 0.75...1.05, using: &random)
                let node = SKSpriteNode(texture: kind.texture, size: kind.size * scale)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.15)
                let along = CGFloat(index) + 0.5 + CGFloat.random(in: -0.3...0.3, using: &random)
                node.position = corner(along: along, of: edge, columns: columns, rows: rows)
                put(node)
            }
            return []
        }

        // A fence: the pickets slanted along the line, a picture a cell, like a town's.
        guard let pickets = art.gradedTile("fence", palette: palette),
              let rail = TownFence.railing(pickets, posts: (0, 1), height: 21, alongColumns: alongColumns) else { return [] }
        for index in neighbour.span where gate?.contains(index) != true && dry(index) {
            let node = SKSpriteNode(texture: rail.texture, size: rail.size)
            node.anchorPoint = rail.anchor
            node.position = point(along: index, of: edge, columns: columns, rows: rows)
            put(node)
        }
        guard let gate else { return [] }
        return gateway(gate, neighbour, columns: columns, rows: rows, open: open, palette: palette, art: art, into: parent)
    }

    /// Cells along a border in unbroken stretches, each from its first to its last.
    private static func runs(_ cells: [Int]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for cell in cells.sorted() {
            if let last = runs.last, last.upperBound + 1 == cell {
                runs[runs.count - 1] = last.lowerBound...cell
            } else {
                runs.append(cell...cell)
            }
        }
        return runs
    }

    /// A quest's way through a wall: a stone arch over the road, and while the quest isn't done a
    /// bar of pickets across it and "Closed" over it (returned, to take away once it's done).
    private static func gateway(_ gate: ClosedRange<Int>, _ neighbour: Continent.Neighbour, columns: Int, rows: Int, open: Bool,
                                palette: MapPalette?, art: ArtLibrary, into parent: (CGPoint) -> SKNode) -> [SKNode] {
        let edge = neighbour.edge
        let alongColumns = edge == .north || edge == .south
        if let arch = art.gradedTile("town_gate", palette: palette).flatMap(TownFence.cropped) {
            // From one end of the gate to the other, the west or north end first.
            let low = corner(along: CGFloat(gate.lowerBound), of: edge, columns: columns, rows: rows)
            let high = corner(along: CGFloat(gate.upperBound + 1), of: edge, columns: columns, rows: rows)
            let node = alongColumns ? TownFence.gate(arch, from: low, to: high) : TownFence.gate(arch, from: high, to: low)
            parent(node.position).addChild(node)
        }
        guard !open, let pickets = art.gradedTile("fence", palette: palette),
              let rail = TownFence.railing(pickets, posts: (0, 1), height: 21, alongColumns: alongColumns) else { return [] }
        var bar: [SKNode] = []
        for index in gate {
            let node = SKSpriteNode(texture: rail.texture, size: rail.size)
            node.anchorPoint = rail.anchor
            node.position = point(along: index, of: edge, columns: columns, rows: rows)
            node.zPosition = -node.position.y
            parent(node.position).addChild(node)
            bar.append(node)
        }
        // "Closed" over the bar, still: from both sides it's the same sign in the same place.
        let sign = SKLabelNode()
        sign.attributedText = Nodes.outlined(L("Closed"), size: 12, color: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1))
        let middle = point(along: neighbour.road ?? gate.lowerBound, of: edge, columns: columns, rows: rows)
        sign.position = middle + CGVector(dx: 0, dy: 62)
        sign.zPosition = 4_500
        parent(middle).addChild(sign)
        bar.append(sign)
        return bar
    }

    // MARK: City walls

    /// How tall the city wall stands, to the top of its battlements (points), and its towers.
    private static let wallHeight: CGFloat = 32
    private static let towerSize = CGSize(width: 30, height: 60)

    /// The wall's stones, as the town gate's arch has them: grey blocks, a lit lip, mortar between.
    private static let mortar = PixelColor(0x4C4F5A)
    private static let blocks = [PixelColor(0x7E818C), PixelColor(0x737682), PixelColor(0x888B96)]
    private static let lip = PixelColor(0xA4A7B2)
    private static let foot = PixelColor(0x5A5D68)
    private static let moss = PixelColor(0x5D7A3C)

    /// One cell's stretch of city wall, face on, to be slanted along the border (`TownFence.railing`):
    /// battlements along the top, courses of staggered blocks, a darker foot with moss on it. Its
    /// pattern repeats every 32 pixels, so stretches side by side run on as one wall.
    private static func wallPicture(palette: MapPalette?) -> CGImage? {
        var canvas = PixelCanvas(width: 32, height: 30)
        // Battlements: merlons 5 wide every 8, lit on top and shaded down their right side.
        for x in stride(from: 0, to: 32, by: 8) {
            canvas.fill(x, 0, 5, 6, blocks[0])
            canvas.fill(x, 0, 5, 1, lip)
            canvas.fill(x + 4, 1, 1, 5, mortar)
        }
        // The wall: four courses of blocks 4 high, the joints staggered from course to course.
        canvas.fill(0, 6, 32, 24, mortar)
        canvas.fill(0, 6, 32, 1, lip)
        for course in 0..<4 {
            let y = 7 + course * 5
            let offset = course % 2 == 0 ? 0 : 8
            for x in stride(from: offset - 16, to: 32, by: 16) {
                let left = max(0, x), right = min(32, x + 15)
                guard right > left else { continue }
                let block = blocks[(course + (x + 16) / 16) % blocks.count]
                canvas.fill(left, y, right - left, 4, block)
                canvas.fill(left, y, right - left, 1, block.shaded(1.12))
            }
        }
        canvas.fill(0, 27, 32, 3, foot)
        for x in [2, 3, 11, 19, 20, 27] {
            canvas[x, 26] = moss
            canvas[x, 27] = moss
        }
        let image = canvas.cgImage()
        return palette.flatMap { Recolor.grade($0, image: image) } ?? image
    }

    /// A round tower of the same stone, standing up from the wall: battlements, an arrow slit, its
    /// right side in shade.
    private static func towerPicture(palette: MapPalette?) -> CGImage? {
        var canvas = PixelCanvas(width: 20, height: 40)
        for x in stride(from: 0, to: 20, by: 8) {
            canvas.fill(x, 0, 4, 5, blocks[0])
            canvas.fill(x, 0, 4, 1, lip)
        }
        canvas.fill(0, 5, 20, 35, mortar)
        canvas.fill(0, 5, 20, 1, lip)
        for course in 0..<7 {
            let y = 6 + course * 5
            let offset = course % 2 == 0 ? 0 : 5
            for x in stride(from: offset - 10, to: 20, by: 10) {
                let left = max(0, x), right = min(20, x + 9)
                guard right > left else { continue }
                let block = blocks[(course + (x + 10) / 10) % blocks.count]
                canvas.fill(left, y, right - left, 4, block)
                canvas.fill(left, y, right - left, 1, block.shaded(1.12))
            }
        }
        // Rounded: the right third in shade, the left edge lit.
        for y in 5..<40 {
            for x in 14..<20 { canvas[x, y] = canvas[x, y].shaded(0.8) }
            canvas[0, y] = canvas[0, y].shaded(1.1)
        }
        canvas.fill(9, 15, 2, 8, PixelColor(0x23252C))
        canvas.fill(0, 37, 20, 3, foot)
        let image = canvas.cgImage()
        return palette.flatMap { Recolor.grade($0, image: image) } ?? image
    }
}
