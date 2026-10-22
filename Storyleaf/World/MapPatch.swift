import SpriteKit

/// A small patch of one of the game's maps, drawn the way WorldScene draws a whole map: the map's
/// own ground with its roads, flower patches and ponds blended in (ArtLibrary.organicTile), turned
/// into the same 2.5D diamond (WorldMap.project), graded with the map's palette, and its scenery and
/// people standing on it, the nearer ones in front. The story pages and How to play (StoryScene)
/// show the game with it as it really looks, without building a whole map.
///
/// The layout is drawn on a grid like a map's: columns run east (up and right on screen), rows run
/// north (up and left), row 0 is the south edge.
final class MapPatch: SKNode {
    let def: MapDef
    let columns: Int
    let rows: Int
    /// Everyone and everything standing on the ground, kept in depth order by `sortByDepth`.
    let things = SKNode()
    private var kinds: [[Ground]]
    private let art = ArtLibrary.shared
    private var feet: [ObjectIdentifier: CGFloat] = [:]

    /// A patch of `columns` × `rows` cells of the map `mapID`, all its plain ground until painted.
    /// Nil if there's no such map.
    init?(map mapID: String, columns: Int, rows: Int) {
        guard let def = Content.shared.map(mapID), columns > 0, rows > 0 else { return nil }
        self.def = def
        self.columns = columns
        self.rows = rows
        kinds = Array(repeating: Array(repeating: .ground, count: columns), count: rows)
        super.init()
        addChild(things)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Painting the ground

    /// A road from waypoint to waypoint, stepping a cell at a time like the map's carved roads.
    func road(_ points: [(col: Int, row: Int)]) {
        for (from, to) in zip(points, points.dropFirst()) {
            var col = from.col, row = from.row
            paint(col, row, .path)
            while col != to.col || row != to.row {
                if abs(to.col - col) >= abs(to.row - row) {
                    col += to.col > col ? 1 : -1
                } else {
                    row += to.row > row ? 1 : -1
                }
                paint(col, row, .path)
            }
        }
    }

    /// A round patch of `kind` (a pond, a flower meadow) over plain ground.
    func blob(_ col: Int, _ row: Int, radius: CGFloat, _ kind: Ground) {
        for r in 0..<rows {
            for c in 0..<columns where kinds[r][c] == .ground {
                let dx = CGFloat(c - col), dy = CGFloat(r - row)
                if dx * dx + dy * dy <= radius * radius { kinds[r][c] = kind }
            }
        }
    }

    private func paint(_ col: Int, _ row: Int, _ kind: Ground) {
        guard row >= 0, row < rows, col >= 0, col < columns else { return }
        kinds[row][col] = kind
    }

    /// Lays the ground once it's painted, in the map's own colours. Call it before anything stands
    /// on the patch: walkers made after it pick up the map's light, as they do on the real map.
    func layGround() {
        art.use(palette: def.theme.palette, for: def.id)
        if let palette = def.theme.palette, let hex = palette.light, let color = UIColor(hex: hex) {
            Walker.light = (color, CGFloat(palette.lightStrength ?? 0.4))
        } else {
            Walker.light = nil
        }
        let ground = makeGround()
        ground.zPosition = -100_000
        addChild(ground)
    }

    /// The ground as WorldScene.makeGround draws it, over this patch's cells.
    private func makeGround() -> SKNode {
        let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        let theme = def.theme
        let waterID = theme.water ?? "tile_water"
        let water = SKTileGroup(tileDefinition: SKTileDefinition(textures: art.waterFrames(waterID), size: tileSize, timePerFrame: 0.9))
        var groups: [String: SKTileGroup] = ["water": water]
        func group(_ key: String, _ texture: () -> SKTexture) -> SKTileGroup {
            if let known = groups[key] { return known }
            let made = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture(), size: tileSize))
            groups[key] = made
            return made
        }
        let patchAccent = (theme.accentPatches ?? 0) > 0 && theme.accent != nil && theme.accent != theme.ground
        func kind(_ col: Int, _ row: Int) -> Ground? {
            guard row >= 0, row < rows, col >= 0, col < columns else { return nil }
            return kinds[row][col]
        }
        /// Which cells of the 3×3 around a cell are `wanted` (bit row * 3 + col, row 0 north).
        func mask(_ col: Int, _ row: Int, _ wanted: Ground) -> Int {
            let own = kinds[row][col] == wanted
            var bits = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    // Past the patch's edge a road or patch carries on; water doesn't.
                    let hit = kind(col + dx, row + dy).map { $0 == wanted } ?? (own && wanted != .water)
                    if hit { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
                }
            }
            return bits
        }
        /// The water cells of the 5×5 around a cell (bit row * 5 + col, row 0 north), for shorelines.
        func poolMask(_ col: Int, _ row: Int) -> Int {
            var bits = 0
            for dy in -2...2 {
                for dx in -2...2 where kind(col + dx, row + dy) == .water {
                    bits |= 1 << ((2 - dy) * 5 + dx + 2)
                }
            }
            return bits
        }
        let waterVaries = art.waterFrames(waterID).count == 1
        func plain(_ id: String, _ variant: Int) -> SKTileGroup {
            group("\(id)#\(variant)") { art.tileVariant(id, variant) }
        }
        let full = 0b111_111_111, sides = 0b010_101_010
        var picks: [(col: Int, row: Int, group: SKTileGroup)] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let cell = GridPoint(col: col, row: row)
                let road = mask(col, row, .path), pond = mask(col, row, .water)
                let variant = WorldScene.variant(of: cell)
                let patch = patchAccent ? mask(col, row, .accent) : 0
                let base: String = switch kinds[row][col] {
                case .ground: theme.ground
                case .border: theme.border ?? theme.ground
                case .accent where !patchAccent: theme.accent ?? theme.ground
                default: mask(col, row, .border) & sides != 0 ? (theme.border ?? theme.ground) : theme.ground
                }
                var layers: [ArtLibrary.GroundLayer] = []
                if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
                if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road)) }
                if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(col, row), style: .water)) }
                let chosen: SKTileGroup
                if pond == full {
                    chosen = waterVaries ? plain(waterID, variant) : water
                } else if road == full, pond == 0 {
                    chosen = plain(theme.path, variant)
                } else if layers.isEmpty {
                    chosen = plain(base, variant)
                } else if let accent = theme.accent, patch == full, road == 0, pond == 0 {
                    chosen = plain(accent, variant)
                } else {
                    let place = pond != 0 ? "@\(col),\(row)" : ""
                    let key = base + "|" + layers.map { "\($0.style)\($0.mask)" }.joined(separator: "|") + place
                    chosen = group(key) { art.organicTile(base: base, layers: layers, cell: cell, variant: variant) }
                }
                picks.append((col, row, chosen))
            }
        }
        let tileMap = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: columns, rows: rows, tileSize: tileSize)
        tileMap.anchorPoint = .zero
        for pick in picks {
            tileMap.setTileGroup(pick.group, forColumn: pick.col, row: pick.row)
        }
        let grid = SKNode()
        grid.addChild(tileMap)
        // The same soft patches of colour as the map's ground.
        if let variation = Lighting.groundVariation(columns: columns, rows: rows, tile: WorldMap.tileSize, palette: theme.palette, seed: def.id) {
            variation.zPosition = 1
            grid.addChild(variation)
        }
        // Turned 45° and squashed to half height, like WorldScene's ground (WorldMap.project).
        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(grid)
        return squash
    }

    // MARK: - Standing on it

    /// The middle of a cell (fractions for in between), where people stand.
    func point(_ col: CGFloat, _ row: CGFloat) -> CGPoint {
        WorldMap.project(CGPoint(x: (col + 0.5) * WorldMap.tileSize, y: (row + 0.5) * WorldMap.tileSize))
    }

    /// The middle of the whole patch.
    var middle: CGPoint { point(CGFloat(columns - 1) / 2, CGFloat(rows - 1) / 2) }

    /// A piece of scenery set down on a cell as WorldScene.addScenery does: standing on its lowest
    /// opaque row, swaying in the breeze if it's a tree or a flower.
    @discardableResult
    func prop(_ id: String, _ col: CGFloat, _ row: CGFloat, scale: CGFloat = 1, sway: Bool? = nil) -> SKSpriteNode {
        let sprite = art.sprite(id)
        let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * scale)
        node.anchorPoint = CGPoint(x: 0.5, y: min(0.5, 0.05 + foot(of: sprite.texture)))
        node.position = point(col, row) + CGVector(dx: 0, dy: -4)
        if sway ?? (id.contains("tree") || id.contains("flower")) {
            let lean = CGFloat.random(in: 0.018...0.03)
            let duration = TimeInterval.random(in: 1.8...2.8)
            let left = SKAction.rotate(toAngle: lean, duration: duration, shortestUnitArc: true)
            let right = SKAction.rotate(toAngle: -lean, duration: duration, shortestUnitArc: true)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([left, right])))
        }
        things.addChild(node)
        sortByDepth()
        return node
    }

    /// Someone standing on a cell: a person breathing, a creature squishing or hopping, as they
    /// do on the map. `label` puts their name over their head.
    @discardableResult
    func walker(_ id: String, _ col: CGFloat, _ row: CGFloat, facing: Direction = .down, label: String? = nil) -> Walker {
        let node = Walker(cycle: art.walkCycle(id), label: label)
        node.motion = IdleMotion.of(art: id)
        node.face(facing)
        node.position = point(col, row)
        things.addChild(node)
        sortByDepth()
        return node
    }

    /// Nearer things in front, as on the map (call it while anyone moves).
    func sortByDepth() {
        for node in things.children {
            node.zPosition = -node.position.y
        }
    }

    /// How far up its picture a sprite's lowest opaque pixel sits (0...1), so scenery drawn with
    /// empty rows under it stands on its cell (WorldScene.foot(of:)).
    private func foot(of texture: SKTexture) -> CGFloat {
        let key = ObjectIdentifier(texture)
        if let known = feet[key] { return known }
        let image = texture.cgImage()
        let width = image.width, height = image.height
        var foot: CGFloat = 0
        if width > 0, height > 0,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let data = context.data {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            // The bitmap's rows run top to bottom, so search up from the last one.
            search: for row in stride(from: height - 1, through: 0, by: -1) {
                for col in 0..<width where pixels[(row * width + col) * 4 + 3] > 127 {
                    foot = CGFloat(height - 1 - row) / CGFloat(height)
                    break search
                }
            }
        }
        feet[key] = foot
        return foot
    }
}
