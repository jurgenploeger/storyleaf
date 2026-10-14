import SpriteKit

/// The continent as one place, with no borders (docs/continuous-world.md, step 2): every land on it
/// drawn a chunk at a time round the camera (`World.chunkSize` cells a side), from the lands' own
/// layouts and plans, each laid out as you come near it. So far its ground, sea and scenery, and you
/// walking about on it; a debug launch shows it (`continent`) until it takes over from the lands'
/// own scenes.
final class ContinentScene: SKScene {
    private let session: GameSession
    private let input: InputState
    private let art = ArtLibrary.shared
    /// The continent's cells: whose each is, and where you can walk (`World`).
    let store = World.continent()
    /// Everything standing on the ground (scenery, you), in the continent's points: a world cell's
    /// middle is `WorldMap.project` of it in grid points (cells × `WorldMap.tileSize`).
    private let layer = SKNode()
    /// The ground and the sea, chunk by chunk, in grid points, squashed and turned onto the screen as
    /// a land's ground is.
    private let groundGrid = SKNode()
    private let seaGrid = SKNode()
    private let cam = SKCameraNode()
    let player: Walker
    private let walkSpeed: CGFloat = 88
    private var lastUpdate: TimeInterval = 0

    /// A land near you, laid out and planned: its own map, what it sets down (by chunk), how its
    /// ground is tiled, and where its own points lie in the continent's.
    private final class Land {
        let def: MapDef
        let place: World.Land
        let map: WorldMap
        let tiles: GroundTiles
        let shift: CGVector
        /// Its scenery, by the chunk each piece stands in.
        let scenery: [GridPoint: [Placement]]

        init(def: MapDef, place: World.Land, map: WorldMap, plan: LandPlan, tiles: GroundTiles) {
            self.def = def
            self.place = place
            self.map = map
            self.tiles = tiles
            let origin = WorldMap.project(CGPoint(x: CGFloat(place.origin.col) * WorldMap.tileSize, y: CGFloat(place.origin.row) * WorldMap.tileSize))
            shift = CGVector(dx: origin.x, dy: origin.y)
            var scenery: [GridPoint: [Placement]] = [:]
            let all = plan.reeds + plan.lots + plan.streetDecor + plan.buildings + plan.decor + plan.localProps + plan.outcrops
                + plan.props + plan.seamProps
            for piece in all {
                let world = GridPoint(col: piece.cell.col + place.origin.col, row: piece.cell.row + place.origin.row)
                scenery[World.chunk(of: world), default: []].append(piece)
            }
            self.scenery = scenery
        }
    }
    private var lands: [String: Land] = [:]
    /// Lands being laid out now.
    private var laying: Set<String> = []
    /// The chunks drawn: their ground, their sea and what stands on them.
    private var chunks: [GridPoint: (ground: SKNode, sea: SKNode, things: SKNode)] = [:]
    /// How many chunks round yours are drawn, and how far off they're let go.
    static let reach = 2
    static let keep = 3
    private var lookedAround: TimeInterval = 0
    /// True once the chunks round where you started are drawn (a debug launch's screenshot waits).
    private(set) var isReady = false
    private var feet: [ObjectIdentifier: CGFloat] = [:]
    private let seaTile = "raw:tile_water"

    /// `point`: where you start, in the continent's points.
    init(session: GameSession, input: InputState, at point: CGPoint) {
        self.session = session
        self.input = input
        player = Walker(cycle: ArtLibrary.shared.walkCycle(GameSession.heroArt), label: session.data.hero.name)
        super.init(size: CGSize(width: 874, height: 402))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let seaLayer = Self.projected(seaGrid)
        seaLayer.position.y = -WorldMap.seaDrop
        seaLayer.zPosition = -100_001
        layer.addChild(seaLayer)
        let groundLayer = Self.projected(groundGrid)
        groundLayer.zPosition = -100_000
        layer.addChild(groundLayer)
        addChild(layer)
        player.tagMode = .whenStill
        player.position = point
        player.zPosition = -point.y
        layer.addChild(player)
        addChild(cam)
        camera = cam
        cam.position = point
        backgroundColor = UIColor(red: 0.36, green: 0.62, blue: 0.82, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A world cell's middle, in the continent's points.
    static func center(of cell: GridPoint) -> CGPoint {
        WorldMap.project(CGPoint(x: (CGFloat(cell.col) + 0.5) * WorldMap.tileSize, y: (CGFloat(cell.row) + 0.5) * WorldMap.tileSize))
    }

    /// The world cell under a point of the continent's.
    static func cell(at point: CGPoint) -> GridPoint {
        let grid = WorldMap.unproject(point)
        return GridPoint(col: Int((grid.x / WorldMap.tileSize).rounded(.down)), row: Int((grid.y / WorldMap.tileSize).rounded(.down)))
    }

    /// Grid points (cells × `WorldMap.tileSize`) squashed and turned onto the screen, as a land's
    /// ground is (`WorldScene.projected`).
    private static func projected(_ node: SKNode) -> SKNode {
        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(node)
        return squash
    }

    /// How high the ground stands under a point (on a hill, a terrace, down the shore), from the
    /// land whose it is: walkers stand on it (`Walker.settle`).
    func groundHeight(at point: CGPoint) -> CGFloat {
        guard let owner = store.land(at: Self.cell(at: point)), let land = lands[owner.id] else { return 0 }
        return land.map.height(at: CGPoint(x: point.x - land.shift.dx, y: point.y - land.shift.dy))
    }

    // MARK: Walking

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 8)
        lastUpdate = currentTime
        let stick = input.move
        if stick.length > 0.15 {
            let step = stick * (walkSpeed * CGFloat(dt))
            var next = player.position
            // Each axis on its own, so you slide along what you can't walk through.
            let alongX = CGPoint(x: next.x + step.dx, y: next.y)
            if canStand(at: alongX) { next = alongX }
            let alongY = CGPoint(x: next.x, y: next.y + step.dy)
            if canStand(at: alongY) { next = alongY }
            player.position = next
            player.zPosition = -next.y
            player.face(Direction(stick, current: player.facing))
            player.setWalking(true)
        } else {
            player.setWalking(false)
        }
        cam.position = player.position + CGVector(dx: 0, dy: player.lift)
        if currentTime - lookedAround > 0.25 {
            lookedAround = currentTime
            lookAround()
        }
    }

    /// Whether you can stand on a point: on ground a land's laid out and you can walk on.
    private func canStand(at point: CGPoint) -> Bool {
        store.isWalkable(Self.cell(at: point))
    }

    // MARK: Chunks

    /// Draws the chunks round the camera that aren't yet (laying out the lands they need first),
    /// and lets go of those far off.
    private func lookAround() {
        let here = World.chunk(of: Self.cell(at: cam.position))
        var missing = 0
        for dr in -Self.reach...Self.reach {
            for dc in -Self.reach...Self.reach {
                let chunk = GridPoint(col: here.col + dc, row: here.row + dr)
                guard chunks[chunk] == nil else { continue }
                missing += 1
                let needed = owners(of: chunk)
                let notYet = needed.filter { lands[$0] == nil }
                if notYet.isEmpty {
                    draw(chunk)
                } else {
                    for id in notYet { layOut(id) }
                }
            }
        }
        if missing == 0 { isReady = true }
        for chunk in chunks.keys where max(abs(chunk.col - here.col), abs(chunk.row - here.row)) > Self.keep {
            if let gone = chunks.removeValue(forKey: chunk) {
                gone.ground.removeFromParent()
                gone.sea.removeFromParent()
                gone.things.removeFromParent()
            }
        }
    }

    /// The lands owning any cell of a chunk.
    private func owners(of chunk: GridPoint) -> Set<String> {
        Set(World.cells(in: chunk).compactMap { store.land(at: $0)?.id })
    }

    /// Lays a land out off the main thread, then plans its scenery, and takes it into the store.
    private func layOut(_ id: String) {
        guard !laying.contains(id), let def = Content.shared.map(id), let place = store.land(id) else { return }
        laying.insert(id)
        Task { [weak self] in
            let map = await GameCoordinator.layOut(def)
            guard let self else { return }
            let planner = LandPlanner(def: def, map: map, art: art)
            await planner.planUpToLocals(pause: {})
            await planner.planTheRest(pause: {})
            store.add(map)
            art.use(palette: def.theme.palette, for: def.id)
            lands[id] = Land(def: def, place: place, map: map, plan: planner.plan, tiles: GroundTiles(map: map, art: art))
            laying.remove(id)
        }
    }

    /// Draws a chunk: each land's cells in it with that land's tiles, graded with its palette; the
    /// sea where no land is; and the scenery that stands in it.
    private func draw(_ chunk: GridPoint) {
        let size = World.chunkSize, tile = WorldMap.tileSize
        let origin = GridPoint(col: chunk.col * size, row: chunk.row * size)
        let tileSize = CGSize(width: tile, height: tile)
        var byLand: [String: [GridPoint]] = [:]
        for cell in World.cells(in: chunk) {
            if let owner = store.land(at: cell) { byLand[owner.id, default: []].append(cell) }
        }
        var picks: [(col: Int, row: Int, group: SKTileGroup)] = []
        var groups: [ObjectIdentifier: SKTileGroup] = [:]
        let things = SKNode()
        for (id, cells) in byLand.sorted(by: { $0.key < $1.key }) {
            guard let land = lands[id] else { continue }
            art.use(palette: land.def.theme.palette, for: id)
            for cell in cells {
                guard let group = land.tiles.pick(store.local(cell, in: land.place)).group else { continue }
                picks.append((cell.col - origin.col, cell.row - origin.row, group))
                groups[ObjectIdentifier(group)] = group
            }
            for piece in land.scenery[chunk] ?? [] { things.addChild(scenery(piece, of: land)) }
        }
        let ground = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: size, rows: size, tileSize: tileSize)
        ground.anchorPoint = .zero
        for pick in picks { ground.setTileGroup(pick.group, forColumn: pick.col, row: pick.row) }
        ground.position = CGPoint(x: CGFloat(origin.col) * tile, y: CGFloat(origin.row) * tile)
        groundGrid.addChild(ground)
        let water = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(seaTile), size: tileSize))
        let waters = SKTileMapNode(tileSet: SKTileSet(tileGroups: [water]), columns: size, rows: size, tileSize: tileSize)
        waters.anchorPoint = .zero
        // Under the land's cut edge along the coast too, so the sea shows through it.
        for cell in World.cells(in: chunk) {
            waters.setTileGroup(water, forColumn: cell.col - origin.col, row: cell.row - origin.row)
        }
        waters.position = ground.position
        seaGrid.addChild(waters)
        layer.addChild(things)
        chunks[chunk] = (ground, waters, things)
    }

    /// A piece of scenery as its land's plan set it down (`LandPlanner`), where it stands on the
    /// continent: on its cell, nudged, up on the ground there, swaying.
    private func scenery(_ piece: Placement, of land: Land) -> SKSpriteNode {
        let sprite = art.sprite(piece.art)
        let node = SKSpriteNode(texture: sprite.texture, size: CGSize(width: sprite.size.width * piece.scale, height: sprite.size.height * piece.scale))
        node.anchorPoint = CGPoint(x: 0.5, y: min(0.5, 0.05 + foot(of: sprite.texture)))
        var position = land.map.base(of: piece.cell) + land.shift
        if let nudge = piece.nudge {
            position.x += nudge.dx
            position.y += nudge.dy
        }
        let ground = position.y
        position.y += land.map.height(at: land.map.center(of: piece.cell))
        node.position = position
        node.zPosition = -ground
        if let sway = piece.sway {
            let left = SKAction.rotate(toAngle: sway.lean, duration: sway.duration, shortestUnitArc: true)
            let right = SKAction.rotate(toAngle: -sway.lean, duration: sway.duration, shortestUnitArc: true)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            node.zRotation = sway.start
            node.run(.repeatForever(.sequence([left, right])))
        }
        return node
    }

    /// How far up its picture a sprite's lowest opaque pixel sits (0...1), so scenery drawn with
    /// empty rows under it stands on its cell (`WorldScene.foot(of:)`).
    private func foot(of texture: SKTexture) -> CGFloat {
        let key = ObjectIdentifier(texture)
        if let known = feet[key] { return known }
        let image = art.picture(of: texture)
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
