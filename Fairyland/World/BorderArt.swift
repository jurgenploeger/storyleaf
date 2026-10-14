import SpriteKit

/// What stands on a border between two lands (`Continent.Neighbour`), as RuneScape walls off what
/// you can't reach yet: a wooden fence along a border you can't cross yet, a line of boulders where
/// either land's ground is rocky (sand, snow, scree, desert), or beside a town a stone city wall
/// with towers; the same with a stone arch over a road a quest opens, barred and signed "Closed"
/// until it's done. A fence or boulders come down as a whole once you can cross (the quest's done,
/// or the roads you can take join the two lands); a city wall stays, its gate opening. Nothing
/// along a border open from the start, where the two lands simply meet.
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

    /// Whether a border is walled with a city wall: one of the two lands is a town.
    static func isTown(_ a: MapDef, _ b: MapDef) -> Bool {
        a.fence == true || b.fence == true
    }

    /// The palette both lands draw a border's wall in: the first of the two by id.
    private static func sharedPalette(_ a: MapDef, _ b: MapDef) -> MapPalette? {
        (a.id < b.id ? a : b).theme.palette
    }

    /// Sets the wall along `neighbour`'s border with `here` into `parent(at:)` (`here`'s chunks), where
    /// it's walled (`Continent.Neighbour.isWalled`): a piece along each side of a cell where the two
    /// lands meet, so it winds as their border does. `open`: a quest's gate is open already. Returns
    /// what's taken away once you can cross: a town's, the bar across its shut gate and its sign; any
    /// other, all of it.
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
        // Everything set down (but a town's wall), to take away once you can cross.
        var placed: [SKNode] = []
        func put(_ node: SKNode) {
            let foot = node.position
            node.zPosition = -foot.y
            node.position.y += ground(foot)
            parent(foot).addChild(node)
            placed.append(node)
        }
        let gate: Gate? = neighbour.quest == nil ? nil : neighbour.exit.flatMap { exit in neighbour.road.map { Gate(road: $0, edge: exit.edge) } }

        if isTown(here, neighbour.def) {
            // A city wall: a stretch of stone a cell, its blocks running on from one to the next, and
            // towers at the ends of each straight stretch, every 8 cells between and either side of a gate.
            guard let stones = wallPicture(palette: palette), let tower = towerPicture(palette: palette) else { return [] }
            let walls = rails(stones, height: wallHeight)
            for segment in segments where gate?.covers(segment) != true {
                guard let wall = walls[segment.alongColumns] else { continue }
                let node = SKSpriteNode(texture: wall.texture, size: wall.size)
                node.anchorPoint = wall.anchor
                node.position = segment.middle
                put(node)
            }
            // At the corners between cells, as whole cells.
            var towers: Set<GridPoint> = []
            func corner(_ point: CGPoint) -> GridPoint { GridPoint(col: Int(point.x.rounded()), row: Int(point.y.rounded())) }
            for run in runs(segments) {
                towers.insert(corner(run.grid(CGFloat(run.along.lowerBound))))
                towers.insert(corner(run.grid(CGFloat(run.along.upperBound + 1))))
                for along in stride(from: run.along.lowerBound + 8, to: run.along.upperBound - 3, by: 8) {
                    if let gate, gate.alongColumns == run.alongColumns, gate.line == run.line,
                       ((gate.along.lowerBound - 3)...(gate.along.upperBound + 4)).contains(along) { continue }
                    towers.insert(corner(run.grid(CGFloat(along))))
                }
            }
            if let gate {
                towers.insert(corner(gate.grid(CGFloat(gate.along.lowerBound))))
                towers.insert(corner(gate.grid(CGFloat(gate.along.upperBound + 1))))
            }
            let texture = SKTexture(cgImage: tower)
            texture.filteringMode = .nearest
            for spot in towers.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                let node = SKSpriteNode(texture: texture, size: towerSize)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.06)
                node.position = screen(CGPoint(x: spot.col, y: spot.row))
                put(node)
            }
            guard let gate else { return [] }
            return gateway(gate, open: open, palette: palette, art: art, into: parent).bar
        }

        if gate == nil, isRocky(here, neighbour.def) {
            // A tumble of boulders along the line, the same stones from either side: each picked by
            // where its piece of border lies on the continent.
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
                guard Double.random(in: 0..<1, using: &random) < 0.85 else { continue }
                let kind = kinds[Int.random(in: 0..<kinds.count, using: &random)]
                let scale = CGFloat.random(in: 0.75...1.05, using: &random)
                let node = SKSpriteNode(texture: kind.texture, size: kind.size * scale)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.15)
                node.position = screen(segment.grid(0.5 + CGFloat.random(in: -0.3...0.3, using: &random)))
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

    /// A straight stretch of border: its pieces one after another along the same line.
    private struct Run {
        let alongColumns: Bool
        let line: Int
        let along: ClosedRange<Int>

        func grid(_ at: CGFloat) -> CGPoint {
            alongColumns ? CGPoint(x: at, y: CGFloat(line)) : CGPoint(x: CGFloat(line), y: at)
        }
    }

    /// A border's pieces in unbroken straight stretches.
    private static func runs(_ segments: [Segment]) -> [Run] {
        var runs: [Run] = []
        let lines = Dictionary(grouping: segments) { "\($0.alongColumns) \($0.line)" }
        for key in lines.keys.sorted() {
            guard let pieces = lines[key], let first = pieces.first else { continue }
            var current: ClosedRange<Int>?
            for start in pieces.map(\.start).sorted() {
                if let open = current, open.upperBound + 1 == start {
                    current = open.lowerBound...start
                } else {
                    if let open = current { runs.append(Run(alongColumns: first.alongColumns, line: first.line, along: open)) }
                    current = start...start
                }
            }
            if let open = current { runs.append(Run(alongColumns: first.alongColumns, line: first.line, along: open)) }
        }
        return runs
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
