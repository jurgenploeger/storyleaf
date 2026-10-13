import SpriteKit

/// What stands on a border between two lands (`Continent.Neighbour`), as RuneScape walls off what
/// you can't reach yet: a wooden fence along a border no road crosses, or a line of boulders where
/// either land's ground is rocky (sand, snow, scree, desert); the same fence with a stone arch over
/// a road a quest opens, barred and signed "Closed" until it's done; nothing along a road's open
/// border, where the two lands simply meet.
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

    /// The palette both lands draw a border's wall in: the first of the two by id.
    private static func sharedPalette(_ a: MapDef, _ b: MapDef) -> MapPalette? {
        (a.id < b.id ? a : b).theme.palette
    }

    /// Sets the wall along `neighbour`'s border with `here` into `parent(at:)` (`here`'s chunks).
    /// `open`: a quest's gate is open already. Returns the bar across a shut gate and its sign, to
    /// take away once the quest is done.
    static func place(_ neighbour: Continent.Neighbour, of here: MapDef, open: Bool, art: ArtLibrary,
                      into parent: (CGPoint) -> SKNode) -> [SKNode] {
        guard neighbour.isWalled, let origin = Continent.origin(of: here) else { return [] }
        let columns = here.width, rows = here.height, edge = neighbour.edge
        let palette = sharedPalette(here, neighbour.def)
        func put(_ node: SKNode) {
            node.zPosition = -node.position.y
            parent(node.position).addChild(node)
        }
        // A quest's gate: the road's cells either side, as `Continent.Neighbour.isOpen` lets you through.
        let gate: ClosedRange<Int>? = neighbour.quest == nil ? nil : neighbour.road.map { ($0 - Continent.gateReach)...($0 + Continent.gateReach) }

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
            for index in neighbour.span {
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
        let alongColumns = edge == .north || edge == .south
        guard let pickets = art.gradedTile("fence", palette: palette),
              let rail = TownFence.railing(pickets, posts: (0, 1), height: 21, alongColumns: alongColumns) else { return [] }
        var bar: [SKNode] = []
        for index in neighbour.span {
            let barred = gate?.contains(index) == true
            if barred, open { continue }
            let node = SKSpriteNode(texture: rail.texture, size: rail.size)
            node.anchorPoint = rail.anchor
            node.position = point(along: index, of: edge, columns: columns, rows: rows)
            put(node)
            if barred { bar.append(node) }
        }
        guard let gate else { return bar }
        // The arch over the road, from one end of the gate to the other (the west or north end first).
        if let arch = art.gradedTile("town_gate", palette: palette).flatMap(TownFence.cropped) {
            let low = corner(along: CGFloat(gate.lowerBound), of: edge, columns: columns, rows: rows)
            let high = corner(along: CGFloat(gate.upperBound + 1), of: edge, columns: columns, rows: rows)
            let node = alongColumns ? TownFence.gate(arch, from: low, to: high) : TownFence.gate(arch, from: high, to: low)
            parent(node.position).addChild(node)
        }
        guard !open else { return bar }
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
}
