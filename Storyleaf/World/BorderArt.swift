import SpriteKit

/// What stands on a border between two lands (`Continent.Neighbour`), as RuneScape walls off what
/// you can't reach yet: a wooden fence along a border you can't cross yet, or a line of boulders
/// where either land's ground is rocky (sand, snow, scree, desert); the same with a stone arch over a
/// road a quest opens, barred and signed "Closed" until it's done. They come down as a whole once you
/// can cross (the quest's done, or the roads you can take join the two lands). Nothing along a
/// border open from the start, where the two lands simply meet. And the low walls of field stones
/// along roads (`lowWallPicture`).
///
/// It stands on the line between the two lands, winding along the sides of the cells where their
/// shapes meet, drawn the same by both (the same pictures, graded with the same land's palette, the
/// same random stones), so it's there whichever of them is built, and where both are, the two lie
/// exactly over each other.
enum BorderArt {
    /// A cell's side along a border: between a cell of the land and one of the land next door.
    private struct Segment {
        /// Whether it runs along the columns (a cell's north or south side), the row or column line it
        /// lies on, and the column or row it spans.
        let alongColumns: Bool
        let line: Int
        let start: Int

        init(_ pair: (inside: GridPoint, outside: GridPoint)) {
            let columns = pair.inside.col == pair.outside.col
            alongColumns = columns
            line = columns ? max(pair.inside.row, pair.outside.row) : max(pair.inside.col, pair.outside.col)
            start = columns ? pair.inside.col : pair.inside.row
        }

        /// A point `at` cells along it from its start, in grid cells.
        func grid(_ at: CGFloat) -> CGPoint {
            alongColumns ? CGPoint(x: CGFloat(start) + at, y: CGFloat(line)) : CGPoint(x: CGFloat(line), y: CGFloat(start) + at)
        }

        /// Its middle, on screen in the land's own points.
        var middle: CGPoint { BorderArt.screen(grid(0.5)) }
    }

    /// A quest's gate across a border: the stretch of it where the road crosses, `Continent.gateReach`
    /// either side of the road, as `Continent.Neighbour.isOpen` lets you through.
    private struct Gate {
        let alongColumns: Bool
        let line: Int
        let along: ClosedRange<Int>
        /// Where the road crosses, along the line.
        let road: Int

        /// `road`: the last cell on this side, `edge`: the way over.
        init(road cell: GridPoint, edge: Edge) {
            let over = cell.stepped(edge)
            let columns = edge == .north || edge == .south
            let at = columns ? cell.col : cell.row
            alongColumns = columns
            line = columns ? max(cell.row, over.row) : max(cell.col, over.col)
            road = at
            along = (at - Continent.gateReach)...(at + Continent.gateReach)
        }

        func covers(_ segment: Segment) -> Bool {
            segment.alongColumns == alongColumns && segment.line == line && along.contains(segment.start)
        }

        /// A point `at` cells along the line, in grid cells.
        func grid(_ at: CGFloat) -> CGPoint {
            alongColumns ? CGPoint(x: at, y: CGFloat(line)) : CGPoint(x: CGFloat(line), y: at)
        }
    }

    /// A point in grid cells, on screen in the land's own points.
    private static func screen(_ grid: CGPoint) -> CGPoint {
        WorldMap.project(CGPoint(x: grid.x * WorldMap.tileSize, y: grid.y * WorldMap.tileSize))
    }

    /// Whether a border is walled with boulders rather than a fence: either land's ground is rocky.
    static func isRocky(_ a: MapDef, _ b: MapDef) -> Bool {
        [a, b].contains { def in ["desert", "sand", "scree", "snow"].contains { def.theme.ground.contains($0) } }
    }

    /// The palette both lands draw a border's wall in: the first of the two by id.
    private static func sharedPalette(_ a: MapDef, _ b: MapDef) -> MapPalette? {
        (a.id < b.id ? a : b).theme.palette
    }

    /// Sets the wall along `neighbour`'s border with `here` into `parent(at:)` (`here`'s chunks), where
    /// it's walled (`Continent.Neighbour.isWalled`): a piece along each side of a cell where the two
    /// lands meet, so it winds as their border does. `open`: a quest's gate is open already. Returns
    /// what's taken away once you can cross: all of it.
    /// `ground`: how high the ground lies under a spot on screen (where the land slopes down to the
    /// sea, `WorldMap.shore`), for the wall to stand on.
    static func place(_ neighbour: Continent.Neighbour, of here: MapDef, open: Bool, art: ArtLibrary,
                      ground: (CGPoint) -> CGFloat = { _ in 0 }, into parent: (CGPoint) -> SKNode) -> [SKNode] {
        guard let origin = Continent.origin(of: here), !neighbour.border.isEmpty else { return [] }
        let palette = sharedPalette(here, neighbour.def)
        // Not across a river where it runs over the border: the water's in the way already.
        let region = Continent.region(of: here)
        let segments = neighbour.border.filter { pair in
            region.map { !$0.isRiver(pair.inside) && !$0.isRiver(pair.outside) } ?? true
        }.map(Segment.init)
        // Everything set down, to take away once you can cross.
        var placed: [SKNode] = []
        func put(_ node: SKNode) {
            let foot = node.position
            node.zPosition = -foot.y
            node.position.y += ground(foot)
            parent(foot).addChild(node)
            placed.append(node)
        }
        let gate: Gate? = neighbour.quest == nil ? nil : neighbour.exit.flatMap { exit in neighbour.road.map { Gate(road: $0, edge: exit.edge) } }

        if gate == nil, isRocky(here, neighbour.def) {
            // A tumble of boulders along the line, the same stones from either side: each picked by
            // where its piece of border lies on the continent. One on every piece, no gaps
            // (playtesting 2026-10-20: a gap you can't walk through looked like a way over).
            let kinds = ["boulder", "small_boulder"].compactMap { id -> (texture: SKTexture, size: CGSize)? in
                guard let image = art.gradedTile(id, palette: palette) else { return nil }
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .nearest
                return (texture, art.sprite(id).size)
            }
            guard !kinds.isEmpty else { return [] }
            for segment in segments {
                let world = segment.grid(0.5)
                var random = SeededRandom(text: "border \(Int(world.x * 2) + origin.col * 2),\(Int(world.y * 2) + origin.row * 2)")
                let kind = kinds[Int.random(in: 0..<kinds.count, using: &random)]
                let scale = CGFloat.random(in: 0.9...1.1, using: &random)
                let node = SKSpriteNode(texture: kind.texture, size: kind.size * scale)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.15)
                node.position = screen(segment.grid(0.5 + CGFloat.random(in: -0.15...0.15, using: &random)))
                put(node)
            }
            return placed
        }

        // A fence: the pickets slanted along the line, a picture a cell, like a town's.
        guard let pickets = art.gradedTile("fence", palette: palette) else { return [] }
        let fences = rails(pickets, height: 21)
        for segment in segments where gate?.covers(segment) != true {
            guard let rail = fences[segment.alongColumns] else { continue }
            let node = SKSpriteNode(texture: rail.texture, size: rail.size)
            node.anchorPoint = rail.anchor
            node.position = segment.middle
            put(node)
        }
        guard let gate else { return placed }
        let way = gateway(gate, open: open, palette: palette, art: art, into: parent)
        return placed + [way.arch].compactMap { $0 } + way.bar
    }

    /// A picture slanted along a border both ways it can run (`TownFence.railing`), by whether it runs
    /// along the columns.
    private static func rails(_ picture: CGImage, height: CGFloat) -> [Bool: (texture: SKTexture, size: CGSize, anchor: CGPoint)] {
        var found: [Bool: (texture: SKTexture, size: CGSize, anchor: CGPoint)] = [:]
        for alongColumns in [true, false] {
            found[alongColumns] = TownFence.railing(picture, posts: (0, 1), height: height, alongColumns: alongColumns)
        }
        return found
    }

    /// A quest's way through a wall: a stone arch over the road, and while the quest isn't done a
    /// bar of pickets across it and "Closed" over it (to take away once it's done).
    private static func gateway(_ gate: Gate, open: Bool, palette: MapPalette?, art: ArtLibrary,
                                into parent: (CGPoint) -> SKNode) -> (arch: SKNode?, bar: [SKNode]) {
        var arch: SKNode?
        if let picture = art.gradedTile("town_gate", palette: palette).flatMap(TownFence.cropped) {
            // From one end of the gate to the other, the west or north end first.
            let low = screen(gate.grid(CGFloat(gate.along.lowerBound)))
            let high = screen(gate.grid(CGFloat(gate.along.upperBound + 1)))
            let node = gate.alongColumns ? TownFence.gate(picture, from: low, to: high) : TownFence.gate(picture, from: high, to: low)
            parent(node.position).addChild(node)
            arch = node
        }
        guard !open, let pickets = art.gradedTile("fence", palette: palette),
              let rail = TownFence.railing(pickets, posts: (0, 1), height: 21, alongColumns: gate.alongColumns) else { return (arch, []) }
        var bar: [SKNode] = []
        for along in gate.along {
            let node = SKSpriteNode(texture: rail.texture, size: rail.size)
            node.anchorPoint = rail.anchor
            node.position = screen(gate.grid(CGFloat(along) + 0.5))
            node.zPosition = -node.position.y
            parent(node.position).addChild(node)
            bar.append(node)
        }
        // "Closed" over the bar, still: from both sides it's the same sign in the same place.
        let sign = SKLabelNode()
        sign.attributedText = Nodes.outlined(L("Closed"), size: 12, color: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1))
        let middle = screen(gate.grid(CGFloat(gate.road) + 0.5))
        sign.position = middle + CGVector(dx: 0, dy: 62)
        sign.zPosition = 4_500
        parent(middle).addChild(sign)
        bar.append(sign)
        return (arch, bar)
    }

    // MARK: City walls

    /// How tall a city's wall stands, to the top of its battlements (points), and its towers
    /// (`TownFence.place`; art/sprites/city_wall.png and city_tower.png, `tools/city_wall_art.py`).
    static let wallHeight: CGFloat = 32
    static let towerSize = CGSize(width: 30, height: 60)

    /// The low wall's stones (`lowWallPicture`): grey blocks, a lit lip, mortar between.
    private static let mortar = PixelColor(0x4C4F5A)
    private static let blocks = [PixelColor(0x7E818C), PixelColor(0x737682), PixelColor(0x888B96)]
    private static let lip = PixelColor(0xA4A7B2)
    private static let foot = PixelColor(0x5A5D68)
    private static let moss = PixelColor(0x5D7A3C)

    /// How tall a low wall along a road stands (`lowWallPicture`), in points.
    static let lowWallHeight: CGFloat = 13

    /// One cell's stretch of a low wall of field stones along a road (`LandPlanner.planRoadsides`),
    /// face on, to be slanted along its line (`TownFence.pieces`): a row of slabs set on edge along
    /// its top, two courses of rounded grey stones, unevenly long, and a darker
    /// foot with moss. Its pattern repeats every 32 pixels, so stretches run on as one wall.
    static func lowWallPicture(palette: MapPalette?) -> CGImage? {
        var canvas = PixelCanvas(width: 32, height: 14)
        // The coping: slabs on edge, two wide with a joint between, every other one a shade darker.
        canvas.fill(0, 0, 32, 3, mortar)
        for x in stride(from: 0, to: 32, by: 3) {
            let slab = blocks[(x / 3) % 2 == 0 ? 0 : 1]
            canvas.fill(x, 0, 2, 3, slab)
            canvas[x, 0] = lip
        }
        // Two courses of rounded stones, their joints apart from course to course.
        canvas.fill(0, 3, 32, 9, mortar)
        let courses: [(y: Int, height: Int, widths: [Int])] = [(3, 4, [7, 5, 8, 6, 6]), (8, 4, [4, 8, 6, 7, 7])]
        for (number, course) in courses.enumerated() {
            var x = 0
            for (index, width) in course.widths.enumerated() {
                let stone = blocks[(number + index) % blocks.count]
                canvas.fill(x, course.y, width - 1, course.height, stone)
                canvas.fill(x, course.y, width - 1, 1, stone.shaded(1.15))
                // Rounded: the corners in the joints' shade.
                for (cx, cy) in [(x, course.y), (x + width - 2, course.y), (x, course.y + course.height - 1), (x + width - 2, course.y + course.height - 1)] {
                    canvas[cx, cy] = mortar
                }
                x += width
            }
        }
        canvas.fill(0, 12, 32, 2, foot)
        for x in [1, 2, 9, 17, 18, 25, 30] {
            canvas[x, 11] = moss
            canvas[x, 12] = moss
        }
        let image = canvas.cgImage()
        return palette.flatMap { Recolor.grade($0, image: image) } ?? image
    }
}
