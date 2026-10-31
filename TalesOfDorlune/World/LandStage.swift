import SpriteKit

/// What a land's things on the continent are kept in (`LandStage.world`): whoever walks in it stands
/// on that land's ground (`Walker.settle`).
final class StageNode: SKNode {
    weak var stage: LandStage?
}

/// A land's own things on the continent (`ContinentScene`), set down in its own points where its
/// plan put them (`LandPlanner`), as its own scene sets them down (`WorldScene.build`): its scenery
/// and buildings, its town's fence and terraces, lamps and fountains, the crags round a cave's mouth,
/// lily pads, fairy rings, its bridges' rails, its people, signposts, and the fences along the
/// borders a quest keeps closed; and its passers-by and animals, going about as you come near. Its
/// ground, hills and shore are the continent's (`ContinentScene.draw`).
///
/// Kept in pieces of the screen (`chunk(at:)`), only those near the camera in the scene (`show`),
/// as its own scene keeps them: a wooded land's thousands of trees cost nothing out of sight.
final class LandStage {
    let def: MapDef
    let map: WorldMap
    /// Everything of it, at its shift on the continent: its points are the land's own, and its depth
    /// too (`-y` in its own points, less its shift's), so it sorts among everything else there.
    let world = StageNode()
    /// The people who stand about it (`placeNPCs`), with their quest marks.
    private(set) var npcs: [(def: NPCDef, node: Walker, marker: NameTag)] = []
    /// Its passers-by, traders and locals (`Crowd`), and its animals (`Critters`).
    private(set) var crowd: Crowd?
    private var critters: Critters?
    /// Whether it's the land you're in: only then do its passers-by's chats reach yours.
    var isHere = false
    /// Where its own points lie in the continent's.
    let shift: CGVector
    private let art: ArtLibrary
    private let session: GameSession
    private let plan: LandPlan
    private let tiles: GroundTiles
    private var chunks: [GridPoint: SKNode] = [:]
    /// Each chunk's layers that keep a depth of the continent's own (`layer(at:lift:)`).
    private var layers: [GridPoint: [CGFloat: SKNode]] = [:]
    private var shownChunks: (low: GridPoint, high: GridPoint)?
    private var feet: [ObjectIdentifier: CGFloat] = [:]
    /// Shadows cast by its scenery (`Lighting.Shadow`).
    private var shadows: [Lighting.Shadow] = []
    /// The walls along its borders that come down once you can cross (`placeBorders`): the border,
    /// and what's taken away (a gate's bar, or the whole fence).
    private var gates: [(neighbour: Continent.Neighbour, bar: [SKNode])] = []
    private static let chunkSize: CGFloat = 400
    /// How far past the screen's edges a chunk is kept (`WorldScene.chunkMargin`).
    private static let chunkMargin: CGFloat = 360
    /// How far over everything that stands on the continent its layers above everything are lifted:
    /// past the deepest anything stands there (`ContinentScene`, about ±25,000).
    private static let above: CGFloat = 40_000
    /// How far its air is lifted (`air`, and the sparkles over a fairy ring or a fountain): with
    /// their own depths (20,000 to 30,000) past the deepest anything stands, and still under the
    /// night's shade over the screen (`Sky`, 43,000), as on a land's own map. Lifted `above`, the
    /// butterflies and sparkles stayed as bright at night as by day (playtesting 2026-10-16).
    private static let airLift: CGFloat = 10_000

    init(def: MapDef, map: WorldMap, plan: LandPlan, tiles: GroundTiles, art: ArtLibrary, session: GameSession, shift: CGVector) {
        self.def = def
        self.map = map
        self.plan = plan
        self.tiles = tiles
        self.art = art
        self.session = session
        self.shift = shift
        world.position = CGPoint(x: shift.dx, y: shift.dy)
        world.zPosition = -shift.dy
        world.stage = self
    }

    /// A layer of its own over everything that stands on the continent, for its air's parts that a
    /// land's scene puts over everything (`Ambience`'s butterflies and clouds' shadows, `Lighting`'s
    /// pools of light and sunbeams, and the particles drifting about): their depths, lifted
    /// `airLift`, keep their order there.
    private(set) lazy var air: SKNode = {
        let node = SKNode()
        node.zPosition = self.shift.dy + Self.airLift
        self.world.addChild(node)
        return node
    }()

    /// A point of its box brought onto the land itself, as `WorldScene.onLand` does: one past an
    /// edge mirrored back in, one off its shape moved in toward its middle.
    func onLand(_ point: CGPoint) -> CGPoint {
        let tile = WorldMap.tileSize
        let grid = WorldMap.unproject(point)
        func fold(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
            value < 0 ? min(length, -value) : value > length ? max(0, 2 * length - value) : value
        }
        var spot = WorldMap.project(CGPoint(x: fold(grid.x, CGFloat(map.columns) * tile), y: fold(grid.y, CGFloat(map.rows) * tile)))
        let middle = map.center(of: map.center)
        for _ in 0..<6 where !map.owns(map.rawCell(at: spot)) {
            spot = CGPoint(x: (spot.x + middle.x) / 2, y: (spot.y + middle.y) / 2)
        }
        return spot
    }

    /// How high its ground stands under a point of its own (a hilltop, a terrace, down the shore).
    func groundHeight(at point: CGPoint) -> CGFloat { map.height(at: point) }

    /// A point of the continent's in its own points.
    func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - shift.dx, y: point.y - shift.dy) }

    /// Sets it all down, a piece at a time (`pause` between them: grading with its own palette).
    func build(pause: @escaping () async -> Void) async {
        placeLilyPads(plan.lilyPads)
        placeBridges()
        placeHarbors()
        for reed in plan.reeds { addScenery(reed) }
        await pause()
        placeFence()
        placeBuildings()
        await pause()
        placeDecor(plan.decor)
        placeNPCs(plan.npcs)
        for prop in plan.localProps { addScenery(prop) }
        await pause()
        placeFairyRings(plan.fairyRings)
        for rock in plan.outcrops { addScenery(rock) }
        await pause()
        await placeProps(plan.props, seams: plan.seamProps, pause: pause)
        placeRoadsides()
        placeSignposts(plan.signposts)
        placeCrags()
        await pause()
        placePlateaus()
        placeBorders()
        for npc in npcs { npc.node.settle() }
        await pause()
        // A town's market traders sell what they have today, around your level.
        let market = Crowd.Market(sign: { [weak session] in session?.marketSign(for: $0) },
                                  shout: { [weak session] in session?.marketShout(for: $0) },
                                  level: session.data.hero.level)
        // Your friends who are here now come along among its adventurers (`GameSession.friendsIn`).
        let crowd = Crowd(def: def, map: map, world: world, heroLevel: session.data.hero.level, friends: session.friendsIn(def.id),
                          market: market, locals: plan.locals)
        crowd.onChat = { [weak self, weak session] speaker, text, kind in
            guard self?.isHere == true else { return }
            session?.postChat(text, from: speaker, kind: kind)
        }
        crowd.dares = { [weak session] rival in session?.dares(rival) ?? false }
        self.crowd = crowd
        critters = Critters(def.ambience, world: world, map: map, seed: def.id)
    }

    /// A frame of its life (`player` and `camera` in the continent's points, the screen at
    /// `scale`): its people stroll and its animals mind you as you come near, and its pieces near the
    /// camera are in the scene. Its birds cross the sky only while you're in it (`isHere`).
    func update(dt: TimeInterval, player: CGPoint, camera: CGPoint, scale: CGFloat, screen: CGSize, isHere: Bool = true) {
        let you = local(player), eye = local(camera)
        crowd?.update(dt: dt, player: you)
        let visible = CGRect(x: eye.x - screen.width / 2 * scale, y: eye.y - screen.height / 2 * scale,
                             width: screen.width * scale, height: screen.height * scale)
        critters?.update(dt: dt, player: you, visible: visible, flocks: isHere) { [map] in map.isWalkable(map.rawCell(at: $0)) }
        show(around: camera, scale: scale, screen: screen)
    }

    /// Its people's quest marks (`!` news, `?` done), opened chests and beaten bosses, and its
    /// townsfolk turning to watch you pass (`player` in the continent's points), as
    /// `WorldScene.updateNotices` has them. The one nearest you within `reach`, if any, and how near.
    func updateNotices(player: CGPoint, reach: CGFloat) -> (npc: NPCDef, distance: CGFloat)? {
        let you = local(player)
        var nearest: (npc: NPCDef, distance: CGFloat)?
        for npc in npcs {
            npc.node.isNear = npc.node.position.distance(to: you) < Walker.nameRange
            // A chest stands faded while it's empty, and comes back as something new turns up in it.
            if npc.def.role == .chest, session.isOpened(npc.def.id) == (npc.node.alpha > 0.5) {
                npc.node.run(.fadeAlpha(to: session.isOpened(npc.def.id) ? 0.35 : 1, duration: 0.3))
            }
            // A waystone stands faded while it sleeps, and comes back once its quest wakes it.
            if npc.def.role == .waystone, session.isAwake(npc.def) == (npc.node.alpha < 0.9) {
                npc.node.run(.fadeAlpha(to: session.isAwake(npc.def) ? 1 : 0.55, duration: 0.3))
            }
            if npc.def.role == .boss, session.isBeatenHere(npc.def) {
                if !npc.node.isHidden {
                    SkillEffects.smoke(at: npc.node.position, in: world)
                    npc.node.isHidden = true
                }
                continue
            }
            let notice = session.notice(for: npc.def.id)
            npc.marker.isHidden = notice == nil
            if let notice { npc.marker.setText(notice == .ready ? "?" : "!") }
            let distance = you.distance(to: npc.node.position)
            if distance <= reach, distance < (nearest?.distance ?? .infinity) { nearest = (npc.def, distance) }
            // Townsfolk at their posts turn to watch you pass, and glance around otherwise.
            if !npc.def.role.isObject, npc.def.role != .boss {
                if distance < 130 {
                    npc.node.face(Direction(you - npc.node.position, current: npc.node.facing))
                } else if Int.random(in: 0..<12) == 0 {
                    npc.node.face(Direction.allCases.randomElement() ?? .down)
                }
            }
        }
        return nearest
    }

    /// Everyone else about it, for the minimap (in its cells): the adventurers walking about (friends
    /// and those spoiling for a fight marked so) and the folk who live here (`WorldScene.minimapDots`).
    func minimapDots(friends: Set<UUID>, party: Set<UUID> = []) -> [GameSession.MinimapDot] {
        let walkers = (crowd?.adventurerPositions ?? []).map { profile, position in
            GameSession.MinimapDot(cell: map.cell(at: position), kind: GameSession.MinimapDot.kind(of: profile, friends: friends, party: party))
        }
        let folk = (crowd?.folkPositions ?? []).map { GameSession.MinimapDot(cell: map.cell(at: $0), kind: .folk) }
        return folk + walkers
    }

    /// Who does what about it, for the minimap's icons (`WorldScene.minimapMarks`): quest givers as
    /// their marks say, the healer, the shop, the smith, the guilds, a chest still to open, a boss
    /// still to beat.
    func minimapMarks() -> [GameSession.MinimapMark] {
        npcs.compactMap { npc -> GameSession.MinimapMark? in
            guard !npc.node.isHidden else { return nil }
            guard let kind = session.minimapKind(for: npc.def) else { return nil }
            return GameSession.MinimapMark(cell: map.cell(at: npc.node.position), kind: kind)
        }
    }

    /// Whoever of its people was tapped at `point` (the continent's): one of its own, by where they
    /// stand (and how high), unless they've gone.
    func npc(tappedAt point: CGPoint) -> (def: NPCDef, node: Walker)? {
        let spot = local(point)
        return npcs.first { !$0.node.isHidden && ($0.node.position + CGVector(dx: 0, dy: 24 + $0.node.lift)).distance(to: spot) < 34 }
            .map { ($0.def, $0.node) }
    }

    // MARK: Chunks

    /// The piece of the land holding what's drawn at `position` (its own points).
    private func chunk(at position: CGPoint) -> SKNode {
        let key = Self.key(position.x, position.y)
        if let known = chunks[key] { return known }
        let node = SKNode()
        chunks[key] = node
        shownChunks = nil
        return node
    }

    /// A layer of the chunk at `position` for things with a depth of the continent's own, not the
    /// land's: the ground's shadows and lily pads (`lift` 0, just over the ground at -100,000), or,
    /// lifted `airLift` or `above`, the sparkles, mist and signs over everything that stands.
    private func layer(at position: CGPoint, lift: CGFloat = 0) -> SKNode {
        let key = Self.key(position.x, position.y)
        if let known = layers[key]?[lift] { return known }
        let node = SKNode()
        // Undoes the land's own depth (`world`'s).
        node.zPosition = shift.dy + lift
        chunk(at: position).addChild(node)
        layers[key, default: [:]][lift] = node
        return node
    }

    private static func key(_ x: CGFloat, _ y: CGFloat) -> GridPoint {
        GridPoint(col: Int((x / chunkSize).rounded(.down)), row: Int((y / chunkSize).rounded(.down)))
    }

    /// Puts its chunks near the camera (`camera` in the continent's points, showing `screen` at
    /// `scale`) in the scene, and takes the rest out (their actions wait).
    func show(around camera: CGPoint, scale: CGFloat, screen: CGSize) {
        let local = CGPoint(x: camera.x - shift.dx, y: camera.y - shift.dy)
        let reach = CGSize(width: screen.width / 2 * scale + Self.chunkMargin, height: screen.height / 2 * scale + Self.chunkMargin)
        let low = Self.key(local.x - reach.width, local.y - reach.height)
        let high = Self.key(local.x + reach.width, local.y + reach.height)
        if let shown = shownChunks, shown.low == low, shown.high == high { return }
        shownChunks = (low, high)
        for (spot, node) in chunks {
            let near = spot.col >= low.col && spot.col <= high.col && spot.row >= low.row && spot.row <= high.row
            if near, node.parent == nil {
                world.addChild(node)
            } else if !near, node.parent != nil {
                node.removeFromParent()
            }
        }
    }

    // MARK: Scenery

    /// A piece of scenery as the plan set it down: its own sprite, or `sprite` (a land next door's,
    /// graded as it is there).
    @discardableResult
    private func addScenery(_ placement: Placement, sprite: SpriteArt? = nil) -> SKSpriteNode {
        addScenery(sprite ?? art.sprite(placement.art), at: placement.cell, nudge: placement.nudge, sway: placement.sway, scale: placement.scale)
    }

    /// As `WorldScene.addScenery`: on its cell, nudged, up on the ground there, shaded on a hill's
    /// shaded side (by the midday sun, for now), swaying.
    @discardableResult
    private func addScenery(_ sprite: SpriteArt, at cell: GridPoint, nudge: CGVector? = nil, sway: Placement.Sway? = nil, scale: CGFloat = 1) -> SKSpriteNode {
        let node = SKSpriteNode(texture: sprite.texture, size: CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale))
        node.anchorPoint = CGPoint(x: 0.5, y: min(0.5, 0.05 + foot(of: sprite.texture)))
        var position = map.base(of: cell)
        if let nudge {
            position.x += nudge.dx
            position.y += nudge.dy
        }
        let ground = position.y
        position.y += map.height(at: map.center(of: cell))
        node.position = position
        node.zPosition = -ground
        shade(node, standingOn: cell)
        if let sway {
            let left = SKAction.rotate(toAngle: sway.lean, duration: sway.duration, shortestUnitArc: true)
            let right = SKAction.rotate(toAngle: -sway.lean, duration: sway.duration, shortestUnitArc: true)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            node.zRotation = sway.start
            node.run(.repeatForever(.sequence([left, right])))
        }
        chunk(at: node.position).addChild(node)
        return node
    }

    /// Darkens scenery on a hill's shaded side with the ground there, as `WorldScene.shade` does, by
    /// the midday sun.
    private func shade(_ node: SKSpriteNode, standingOn cell: GridPoint) {
        guard let index = map.hillIndex(at: cell) else { return }
        let hill = map.hills[index]
        let x = Double(cell.col) + 0.5, y = Double(cell.row) + 0.5, e = 0.25
        let gx = Double(hill.height(atCells: x + e, y) - hill.height(atCells: x - e, y)) / (2 * e)
        let gy = Double(hill.height(atCells: x, y + e) - hill.height(atCells: x, y - e)) / (2 * e)
        let tile = Double(WorldMap.tileSize)
        let ambient = hill.isCrag || hill.hasMountain ? HillLooks.cragShade : HillArt.ambient(rocky: map.rockiness)
        let light = HillArt.sunlight(hx: gx / tile / 0.866, hy: gy / tile / 0.866, ambient: ambient, sun: .noon)
        guard light.shade < 1 else { return }
        let shadowed = min(1, max(0, (0.15 - light.lambert) / 0.15))
        node.color = .black
        node.colorBlendFactor = CGFloat((1 - light.shade) * (0.6 + 0.4 * shadowed))
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

    /// How deep something lying flat on the ground at `point` sorts, in the land's own depth: on a
    /// hill just over the strip of raised ground it lies on, on the shore over the sunk ground
    /// (`WorldScene.flatZ`); nil elsewhere, where it lies on the ground under everything.
    private func flatZ(at point: CGPoint) -> CGFloat? {
        let cell = map.cell(at: point)
        if map.hillIndex(at: cell) != nil { return HillArt.strip(at: point.y).z + 0.2 }
        if map.isSunken(cell) { return HillArt.strip(at: point.y, depth: HillArt.sunkenDepth).z + 0.2 }
        return nil
    }


    // MARK: What it sets down

    private func placeLilyPads(_ pads: [(cell: GridPoint, drift: CGVector)]) {
        guard !pads.isEmpty else { return }
        let sprite = art.sprite("lily_pad")
        for (cell, drift) in pads {
            let node = SKSpriteNode(texture: sprite.texture, size: sprite.size)
            let spot = map.center(of: cell) + drift
            // On a lake sunk with the shore, down on its water.
            node.position = CGPoint(x: spot.x, y: spot.y + map.height(at: spot))
            node.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.08, duration: 2.2, shortestUnitArc: true),
                .rotate(toAngle: -0.08, duration: 2.2, shortestUnitArc: true),
            ])))
            if map.isSunken(cell), let z = flatZ(at: spot) {
                node.zPosition = z
                chunk(at: node.position).addChild(node)
            } else {
                node.zPosition = -99_000
                layer(at: node.position).addChild(node)
            }
        }
    }

    /// The bridges' posts and rails (`BridgeArt`; their decks lie with the ground).
    private func placeBridges() {
        guard !map.bridges.isEmpty else { return }
        let pixels = art.picture(of: art.tileTexture(def.theme.ground)).width
        for bridge in map.bridges {
            BridgeArt.rails(for: bridge, pixels: pixels, palette: def.theme.palette, in: world) { [map] in map.height(at: $0) }
        }
    }

    /// How far across from its harbor's road its ship lies, up the screen from the pier (cells, its
    /// middle: past the pier's far side and a little water), and how far out along it.
    static let shipAcross: CGFloat = 2.9
    static let shipAlong: CGFloat = 4

    /// Its harbors (`WorldMap.harbors`): a pier of planks out over the sea, a little over the water
    /// (`WorldMap.pierHeight`) on posts, and a ship moored alongside, up the screen from it, rocking
    /// gently, its gangplank down to the pier. You walk aboard at the pier's end
    /// (`Region.Road.boarding`, `ContinentScene.checkCell`).
    private func placeHarbors() {
        let harbors = map.harbors
        guard !harbors.isEmpty else { return }
        let pixels = art.picture(of: art.tileTexture(def.theme.ground)).width
        let tile = WorldMap.tileSize
        for harbor in harbors {
            let road = harbor.road
            guard let pier = road.pier, let first = road.pierCell(along: 1, across: -1),
                  let last = road.pierCell(along: Region.Road.pierLength, across: -1) else { continue }
            let northward = pier == .north || pier == .south, outward = pier == .north || pier == .east
            let a = northward ? first.row : first.col, b = northward ? last.row : last.col
            let bridge = WorldMap.Bridge(kind: .jetty, northward: northward, lane: northward ? first.col : first.row, lanes: 3,
                                         start: min(a, b), end: max(a, b), landsAtStart: outward, landsAtEnd: !outward)
            // Its deck, under whoever walks it: under the lowest of them on the screen.
            var top: CGFloat = 0
            if let picture = BridgeArt.deckPicture(for: bridge, pixels: pixels, palette: def.theme.palette) {
                let texture = SKTexture(cgImage: picture.image)
                texture.filteringMode = .nearest
                let deck = SKSpriteNode(texture: texture, size: CGSize(width: picture.frame.width * tile, height: picture.frame.height * tile))
                deck.anchorPoint = .zero
                deck.position = CGPoint(x: picture.frame.minX * tile, y: picture.frame.minY * tile)
                let flat = ContinentScene.projected(deck)
                flat.position.y = WorldMap.pierHeight
                let frame = picture.frame
                top = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)]
                    .map { WorldMap.project(CGPoint(x: $0.x * tile, y: $0.y * tile)).y }.max() ?? 0
                flat.zPosition = -top - 1
                world.addChild(flat)
            }
            BridgeArt.rails(for: bridge, pixels: pixels, palette: def.theme.palette, in: world, railed: false) { _ in WorldMap.pierHeight }
            // The ship, behind the pier and all on it.
            let side = northward ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1)
            let out = Self.step(pier)
            let middle = CGPoint(x: CGFloat(road.at.col) + 0.5 + out.dx * Self.shipAlong + side.dx * Self.shipAcross,
                                 y: CGFloat(road.at.row) + 0.5 + out.dy * Self.shipAlong + side.dy * Self.shipAcross)
            let sprite = art.sprite("ship")
            let ship = SKSpriteNode(texture: sprite.texture, size: sprite.size)
            // Drawn lying along the east; its mirror image lies along the north.
            if northward { ship.xScale = -1 }
            ship.position = WorldMap.project(CGPoint(x: middle.x * tile, y: middle.y * tile)) + CGVector(dx: 0, dy: -WorldMap.seaDrop)
            ship.zPosition = -top - 2
            let rise = SKAction.moveBy(x: 0, y: 1.5, duration: 1.9)
            rise.timingMode = .easeInEaseOut
            let lean = SKAction.rotate(byAngle: 0.012, duration: 2.6)
            lean.timingMode = .easeInEaseOut
            ship.run(.repeatForever(.sequence([rise, rise.reversed()])))
            ship.run(.repeatForever(.sequence([lean, lean.reversed(), lean.reversed(), lean])))
            world.addChild(ship)
        }
    }

    /// A step the way `edge` faces, in cells.
    private static func step(_ edge: Edge) -> CGVector {
        switch edge {
        case .east: CGVector(dx: 1, dy: 0)
        case .west: CGVector(dx: -1, dy: 0)
        case .north: CGVector(dx: 0, dy: 1)
        case .south: CGVector(dx: 0, dy: -1)
        }
    }

    private func placeFence() {
        guard !map.fenceCells.isEmpty else { return }
        TownFence.place(cells: map.fenceCells, map: map, world: world, art: art, stone: def.town?.walls == "stone")
    }

    /// The picket fences and low walls along stretches of its roads (`LandPlanner.planRoadsides`),
    /// joined from cell to cell as a town's fence is, each piece in the chunk it stands in.
    private func placeRoadsides() {
        TownFence.placeRoadsides(plan.roadsides, map: map, art: art) { node in self.chunk(at: node.position).addChild(node) }
    }

    /// Houses, the street's lamps (glowing) and decor, the terraces' railings, and the land's own
    /// buildings.
    private func placeBuildings() {
        for lot in plan.lots { addScenery(lot) }
        for decor in plan.streetDecor {
            let lamp = addScenery(decor)
            guard decor.art == "street_lamp" else { continue }
            let glow = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: 70, height: 50))
            glow.color = UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1)
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.35
            glow.position = map.center(of: decor.cell) + CGVector(dx: 0, dy: 34)
            // Just behind the lamp: whoever stands in front hides the glow, whoever is behind is lit.
            glow.zPosition = lamp.zPosition - 0.5
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 1.4), .fadeAlpha(to: 0.3, duration: 1.4)])))
            chunk(at: glow.position).addChild(glow)
        }
        placeTerraces()
        for building in plan.buildings { addScenery(building) }
    }

    /// Stone terraces' balustrades and corner pillars, up on their tops (`WorldScene.placeTerraces`).
    private func placeTerraces() {
        guard !map.terraces.isEmpty else { return }
        let rail = art.sprite("stone_balustrade"), pillar = art.sprite("wall_pillar")
        let picture = art.picture(of: rail.texture)
        let rising = TownFence.railing(picture, posts: (0.108, 0.912), height: 16, alongColumns: true)
        let falling = TownFence.railing(picture, posts: (0.108, 0.912), height: 16, alongColumns: false)
        let up = CGVector(dx: 0, dy: WorldMap.terraceHeight)
        for terrace in map.terraces {
            let o = terrace.origin
            let last = GridPoint(col: o.col + terrace.width - 1, row: o.row + terrace.height - 1)
            for col in o.col...last.col {
                for row in o.row...last.row {
                    let cell = GridPoint(col: col, row: row)
                    guard col == o.col || row == o.row || col == last.col || row == last.row,
                          !terrace.stairs.contains(cell) else { continue }
                    let corner = (col == o.col || col == last.col) && (row == o.row || row == last.row)
                    if !corner, let slanted = row == o.row || row == last.row ? rising : falling {
                        let node = SKSpriteNode(texture: slanted.texture, size: slanted.size)
                        node.anchorPoint = slanted.anchor
                        node.position = map.center(of: cell) + up
                        node.zPosition = -map.center(of: cell).y
                        chunk(at: node.position).addChild(node)
                        continue
                    }
                    let sprite = corner ? pillar : rail
                    let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * (corner ? 0.6 : 0.7))
                    node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                    node.position = map.base(of: cell) + up
                    if !corner, col == o.col || col == last.col { node.xScale = -1 }
                    node.zPosition = -map.base(of: cell).y
                    chunk(at: node.position).addChild(node)
                }
            }
        }
    }

    private func placeDecor(_ planned: [Placement]) {
        for decor in planned {
            addScenery(decor)
            if decor.art.contains("fountain") {
                let sparkle = map.center(of: decor.cell) + CGVector(dx: 0, dy: 30)
                Ambience.twinkle(around: sparkle, radius: 30, count: 4, in: layer(at: sparkle, lift: Self.airLift))
            }
        }
    }

    /// The land's people where the plan put them, each with a quest mark over them (hidden till
    /// there's news for you); they stand and idle for now.
    private func placeNPCs(_ planned: [(npc: NPCDef, cell: GridPoint)]) {
        for (npc, cell) in planned {
            let node = Walker(cycle: art.walkCycle(npc.art), label: npc.name)
            node.idles = !npc.role.isObject
            node.tagMode = .onDemand
            if npc.role == .boss { node.motion = IdleMotion.of(art: npc.art) }
            node.position = map.center(of: cell)
            node.zPosition = -node.position.y
            let marker = NameTag("!", size: 28)
            marker.position = CGPoint(x: 0, y: node.sprite.size.height + 18)
            marker.zPosition = 6_000
            marker.isHidden = true
            let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 0.4), .moveBy(x: 0, y: -5, duration: 0.4)])
            let pulse = SKAction.sequence([.scale(to: 1.15, duration: 0.4), .scale(to: 1, duration: 0.4)])
            marker.run(.repeatForever(.group([bob, pulse])))
            node.addChild(marker)
            world.addChild(node)
            npcs.append((npc, node, marker))
        }
    }

    /// Circles of mushrooms with a sparkle in the middle, like the ones fairies dance in.
    private func placeFairyRings(_ middles: [GridPoint]) {
        guard let rings = def.theme.fairyRings, !middles.isEmpty else { return }
        let sprite = art.sprite(rings.art)
        for middle in middles {
            let origin = map.center(of: middle)
            for index in 0..<9 {
                let angle = CGFloat(index) / 9 * 2 * .pi
                let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * 0.75)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                node.position = origin + CGVector(dx: cos(angle) * 52, dy: sin(angle) * 36)
                node.zPosition = -node.position.y
                chunk(at: origin).addChild(node)
            }
            Ambience.twinkle(around: origin, radius: 26, count: 5, in: layer(at: origin, lift: Self.airLift))
        }
    }

    /// The theme's props, and past the lines the land meets the lands beside it along (`Seam`)
    /// theirs, graded as they are there.
    private func placeProps(_ props: [Placement], seams: [Placement], pause: @escaping () async -> Void) async {
        for (number, prop) in props.enumerated() {
            if number % 32 == 31 { await pause() }
            plant(prop)
        }
        var sprites: [String: SpriteArt] = [:]
        for (number, prop) in seams.enumerated() {
            if number % 32 == 31 { await pause() }
            guard let land = prop.land else { continue }
            let key = land.id + "|" + prop.art
            let sprite: SpriteArt
            if let known = sprites[key] {
                sprite = known
            } else {
                let own = art.sprite(prop.art)
                let texture = art.gradedTile(prop.art, palette: land.theme.palette).map { image -> SKTexture in
                    let made = SKTexture(cgImage: image)
                    made.filteringMode = .nearest
                    return made
                } ?? own.texture
                sprite = SpriteArt(texture: texture, size: own.size)
                sprites[key] = sprite
            }
            plant(prop, sprite: sprite)
        }
    }

    /// A prop as its placement says (`WorldScene.plant`): swaying, bobbing, with its shadow and its
    /// glow.
    private func plant(_ planted: Placement, sprite: SpriteArt? = nil) {
        guard let placement = planted.prop else { return }
        let cell = planted.cell
        let node = addScenery(planted, sprite: sprite)
        if placement.bob == true {
            // Unseeded, so the land's layout stays what it was.
            let rise = SKAction.moveBy(x: 0, y: 3, duration: .random(in: 1.3...2))
            rise.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([rise, rise.reversed()])), withKey: "bob")
        }
        // On a hill, the strip it stands on and the two in front, where its shadow and glow reach
        // them (`HillArt.strip(at:)`).
        var layers: [(from: CGFloat, z: CGFloat)] = []
        if map.hillIndex(at: cell) != nil {
            let strip = HillArt.strip(at: -node.zPosition)
            layers = (0..<3).map { step in
                let start = strip.start - CGFloat(step) * HillArt.stripHeight
                return (from: start + map.height(at: CGPoint(x: node.position.x, y: start)),
                        z: strip.z + CGFloat(step) * HillArt.stripHeight)
            }
        }
        if placement.shadow == true {
            if !layers.isEmpty {
                shadows.append(Lighting.Shadow(under: node, in: chunk(at: node.position), layers: layers))
            } else if map.isSunken(cell) {
                // On the shore, over the sunk ground it stands on (`HillArt.sunkenDepth`).
                let strip = HillArt.strip(at: -node.zPosition, depth: HillArt.sunkenDepth)
                shadows.append(Lighting.Shadow(under: node, in: chunk(at: node.position), layers: [(from: strip.start, z: strip.z)]))
            } else {
                // On flat ground, under everything that stands.
                shadows.append(Lighting.Shadow(under: node, in: layer(at: node.position)))
            }
        }
        if let hex = placement.glow, let color = UIColor(hex: hex), let glow = planted.glow {
            // A light isn't darkened on a hill's shaded side (`shade`).
            node.colorBlendFactor = 0
            Lighting.glow(behind: node, color: color, in: chunk(at: node.position), alpha: glow.alpha, duration: glow.duration,
                          layers: layers)
        }
    }

    /// A small sign where each road leaves the land, where the plan put it, its words over it
    /// (shown when you come to read it).
    private func placeSignposts(_ planned: [(exit: MapDef.Exit, cell: GridPoint)]) {
        for (exit, cell) in planned {
            guard let destination = Content.shared.map(exit.to) else { continue }
            let text = switch map.signWay(for: exit) {
            // Arrows follow the road on screen: north runs up-left, east up-right.
            case .north: "↖ \(destination.name)"
            case .south: "\(destination.name) ↘"
            case .east: "\(destination.name) ↗"
            case .west: "↙ \(destination.name)"
            }
            let post = addScenery(art.sprite("signpost"), at: cell, scale: 1.6)
            let top = map.base(of: cell) + CGVector(dx: 0, dy: post.size.height + 4)
            let label = NameTag(text, color: Nodes.gold, size: 12)
            label.position = top + CGVector(dx: 0, dy: 4)
            label.alpha = 0
            layer(at: top, lift: Self.above).addChild(label)
        }
    }

    /// The crags round a cave's mouth: boulders strewn on the range past the land's edge, and the
    /// mist thickening out past it (`WorldScene.placeCrags`).
    private func placeCrags() {
        guard !map.crags.isEmpty else { return }
        let tile = WorldMap.tileSize
        let colour = Self.fogColor(from: art.picture(of: art.tileTexture(def.theme.border ?? def.theme.ground)))
        for crag in map.crags {
            let hill = map.hills[crag.hill]
            strewStones(on: hill, inland: crag.inland)
            // A hill inland stands in the land's own ground: no range past the edge to fade out.
            guard !crag.inland else { continue }
            let length = crag.edge == .north || crag.edge == .south ? map.columns : map.rows
            var span = 0...length
            if map.region != nil, let mouth = hill.mouth {
                let road = Int((crag.edge == .north || crag.edge == .south ? mouth.x : mouth.y).rounded(.down))
                let reach = Int(WorldMap.cragStretch) + 8
                span = max(0, road - reach)...min(length, road + reach)
            }
            let facesYou = crag.edge == .north || crag.edge == .east
            let from: CGFloat = facesYou ? 14 : 13
            let heights = stride(from: span.lowerBound, to: span.upperBound, by: 4).map { along -> CGFloat in
                let cell = map.cell(on: crag.edge, along: along, inward: -Int(from) - 4)
                return hill.height(atCells: Double(cell.col) + 0.5, Double(cell.row) + 0.5)
            }
            let lift = heights.reduce(0, +) / CGFloat(max(1, heights.count))
            func clear(_ alongs: StrideTo<Int>) -> Bool {
                alongs.allSatisfy { along in
                    stride(from: -4, through: -32, by: -7).allSatisfy { inward in
                        !Continent.isLand(map.cell(on: crag.edge, along: along, inward: inward), from: def)
                    }
                }
            }
            let low: CGFloat = clear(stride(from: span.lowerBound - 2, to: span.lowerBound - 22, by: -5)) ? 20 : 0
            let high: CGFloat = clear(stride(from: span.upperBound + 1, to: span.upperBound + 21, by: 5)) ? 20 : 0
            let wide = (CGFloat(span.upperBound - span.lowerBound) + low + high) * tile, deep = 8 * tile, beyond = 8 * tile
            let toward: CGFloat = crag.edge == .north || crag.edge == .west ? 1 : -1
            let off = (high - low) / 2 * tile * toward
            let fog = SKNode()
            let band = SKSpriteNode(texture: Self.fogTexture, color: colour, size: CGSize(width: wide, height: deep))
            band.colorBlendFactor = 1
            let mist = SKSpriteNode(color: colour, size: CGSize(width: wide, height: beyond))
            band.position = CGPoint(x: off, y: (from + 4) * tile)
            mist.position = CGPoint(x: off, y: (from + 8) * tile + beyond / 2)
            let turned = SKNode()
            turned.addChild(band)
            turned.addChild(mist)
            let middle = CGFloat(span.lowerBound + span.upperBound) / 2 * tile
            switch crag.edge {
            case .north: turned.position = CGPoint(x: middle, y: CGFloat(map.rows) * tile)
            case .south: turned.position = CGPoint(x: middle, y: 0); turned.zRotation = .pi
            case .east: turned.position = CGPoint(x: CGFloat(map.columns) * tile, y: middle); turned.zRotation = -.pi / 2
            case .west: turned.position = CGPoint(x: 0, y: middle); turned.zRotation = .pi / 2
            }
            fog.addChild(turned)
            let raised = ContinentScene.projected(fog)
            raised.position.y = lift
            // Over everything that stands, as in the land's own scene (15,000 there).
            raised.zPosition = shift.dy + Self.above + 15_000
            world.addChild(raised)
        }
    }

    /// Boulders and stones strewn over a range where a road leads into a cave, out past the land's
    /// edge, or over its rock where it's a hill inland (`WorldScene.strewStones`).
    private func strewStones(on hill: WorldMap.Hill, inland: Bool) {
        var random = SeededRandom(text: def.id + "/crag stones")
        for cell in hill.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) where inland ? !map.isWalkable(cell) : !map.contains(cell) {
            if !inland, Continent.isLand(cell, from: def) { continue }
            let x = Double(cell.col) + 0.5, y = Double(cell.row) + 0.5
            if let mouth = hill.mouth {
                let dx = x - mouth.x, dy = y - mouth.y
                let across = dx * mouth.along.x + dy * mouth.along.y, inward = dx * mouth.into.x + dy * mouth.into.y
                if abs(across) < mouth.half + 2, inward < mouth.depth + 3 { continue }
            }
            guard hill.rise(x, y) > 0.15, Double.random(in: 0..<1, using: &random) < 0.06 else { continue }
            let big = Bool.random(using: &random)
            let size = CGFloat.random(in: 0.55...0.85, using: &random)
            let stone = addScenery(art.sprite(big ? "boulder" : "rock"), at: cell, scale: big ? size : size * 1.4)
            stone.position.y += hill.height(atCells: x, y)
        }
    }

    /// Raised terraces (`WorldMap.plateaus`): each top drawn its height up in its own tiles, a stone
    /// wall under the edges that face you, and stone steps up from the ground in front
    /// (`WorldScene.placePlateaus`).
    private func placePlateaus() {
        guard !map.plateaus.isEmpty else { return }
        let tile = WorldMap.tileSize
        let tileSize = CGSize(width: tile, height: tile)
        let stone = art.tileTexture(def.theme.accent ?? "tile_scree")
        func corner(_ col: Int, _ row: Int) -> CGPoint { WorldMap.project(CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile)) }
        func stroke(_ path: CGPath, color: UIColor, width: CGFloat, z: CGFloat) {
            guard !path.isEmpty else { return }
            let node = SKShapeNode(path: path)
            node.strokeColor = color
            node.lineWidth = width
            node.lineCap = .round
            node.zPosition = z
            world.addChild(node)
        }
        for plateau in map.plateaus {
            let rise = plateau.height
            let topZ = Self.topZ(of: plateau.cells)
            let lips = CGMutablePath(), shadows = CGMutablePath(), creases = CGMutablePath(), treads = CGMutablePath()
            func line(_ path: CGMutablePath, _ from: CGPoint, _ to: CGPoint) {
                path.move(to: from)
                path.addLine(to: to)
            }
            // Its top: its own tiles again, its height up. The stairs are drawn as slopes instead.
            let (low, high) = plateau.bounds
            var picks: [(cell: GridPoint, group: SKTileGroup)] = []
            for cell in plateau.cells where plateau.ramps[cell] == nil {
                if let group = tiles.pick(cell).group { picks.append((cell, group)) }
            }
            var groups: [ObjectIdentifier: SKTileGroup] = [:]
            for pick in picks { groups[ObjectIdentifier(pick.group)] = pick.group }
            let top = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: high.col - low.col + 1,
                                    rows: high.row - low.row + 1, tileSize: tileSize)
            top.anchorPoint = .zero
            for pick in picks { top.setTileGroup(pick.group, forColumn: pick.cell.col - low.col, row: pick.cell.row - low.row) }
            top.position = CGPoint(x: CGFloat(low.col) * tile, y: CGFloat(low.row) * tile)
            let grid = SKNode()
            grid.addChild(top)
            let raised = ContinentScene.projected(grid)
            raised.position.y = rise
            raised.zPosition = topZ
            world.addChild(raised)
            // Walls: under each edge of the top facing you (front, left) where the ground beyond is
            // lower, down to it.
            for cell in plateau.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) where plateau.ramps[cell] == nil {
                for front in [true, false] {
                    let beyond = front ? GridPoint(col: cell.col, row: cell.row - 1) : GridPoint(col: cell.col - 1, row: cell.row)
                    if plateau.cells.contains(beyond), plateau.ramps[beyond] == nil { continue }
                    let a = CGPoint(x: CGFloat(cell.col) * tile, y: CGFloat(cell.row) * tile)
                    let b = front ? CGPoint(x: a.x + tile, y: a.y) : CGPoint(x: a.x, y: a.y + tile)
                    let nudge: CGFloat = 0.5
                    let lowA = map.height(atGrid: front ? CGPoint(x: a.x + nudge, y: a.y - nudge) : CGPoint(x: a.x - nudge, y: a.y + nudge))
                    let lowB = map.height(atGrid: CGPoint(x: b.x - nudge, y: b.y - nudge))
                    guard min(lowA, lowB) < rise - 0.5 else { continue }
                    let pa = WorldMap.project(a), pb = WorldMap.project(b)
                    let path = CGMutablePath()
                    path.move(to: pa + CGVector(dx: 0, dy: rise))
                    path.addLine(to: pb + CGVector(dx: 0, dy: rise))
                    path.addLine(to: pb + CGVector(dx: 0, dy: min(rise, lowB)))
                    path.addLine(to: pa + CGVector(dx: 0, dy: min(rise, lowA)))
                    path.closeSubpath()
                    let face = SKShapeNode(path: path)
                    face.fillTexture = stone
                    face.fillColor = UIColor(white: front ? 0.82 : 0.64, alpha: 1)
                    face.strokeColor = .clear
                    face.lineWidth = 0
                    face.zPosition = topZ - 0.5
                    world.addChild(face)
                    line(lips, pa + CGVector(dx: 0, dy: rise), pb + CGVector(dx: 0, dy: rise))
                    line(shadows, pa + CGVector(dx: 0, dy: min(rise, lowA)), pb + CGVector(dx: 0, dy: min(rise, lowB)))
                }
            }
            // Stairs: the foot on the ground in front, the head up at the top.
            for (cell, ramp) in plateau.ramps {
                let c = cell.col, r = cell.row
                let corners: [(CGPoint, CGFloat)] = ramp == .south
                    ? [(corner(c, r), 0), (corner(c + 1, r), 0), (corner(c + 1, r + 1), rise), (corner(c, r + 1), rise)]
                    : [(corner(c, r + 1), 0), (corner(c, r), 0), (corner(c + 1, r), rise), (corner(c + 1, r + 1), rise)]
                let points = corners.map { $0.0 + CGVector(dx: 0, dy: $0.1) }
                let path = CGMutablePath()
                path.addLines(between: points)
                path.closeSubpath()
                let slope = SKShapeNode(path: path)
                slope.fillTexture = stone
                slope.fillColor = UIColor(white: 0.95, alpha: 1)
                slope.strokeColor = UIColor(white: 0, alpha: 0.22)
                slope.lineWidth = 1
                slope.zPosition = topZ - 0.25
                world.addChild(slope)
                let steps = 5
                for step in 1..<steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let left = points[0] + (points[3] - points[0]) * t
                    let right = points[1] + (points[2] - points[1]) * t
                    line(creases, left, right)
                    line(treads, left + CGVector(dx: 0, dy: 1.5), right + CGVector(dx: 0, dy: 1.5))
                }
            }
            stroke(lips, color: UIColor(white: 1, alpha: 0.55), width: 2, z: topZ + 0.1)
            stroke(shadows, color: UIColor(white: 0, alpha: 0.28), width: 2, z: topZ - 0.45)
            stroke(creases, color: UIColor(white: 0, alpha: 0.3), width: 1.5, z: topZ - 0.2)
            stroke(treads, color: UIColor(white: 1, alpha: 0.35), width: 1, z: topZ - 0.2)
        }
    }

    /// The fences and rocks along the borders you can't cross (`BorderArt.place`): where a quest
    /// keeps you out, and where no road you can take joins the two lands.
    private func placeBorders() {
        // Both lands would set the same wall down in the same places (`BorderArt.place`): on the
        // continent, the first of the two by id does.
        for neighbour in Continent.neighbours(of: def) where def.id < neighbour.def.id {
            let joined = Continent.joined(def.id, neighbour.def.id, done: session.hasCompleted)
            guard neighbour.isWalled(done: session.hasCompleted, joined: joined) else { continue }
            let open = neighbour.quest.map(session.hasCompleted) ?? false
            let bar = BorderArt.place(neighbour, of: def, open: open, art: art, ground: { [map] in map.height(at: $0) }) { [weak self] point in
                self?.chunk(at: point) ?? SKNode()
            }
            if !bar.isEmpty { gates.append((neighbour, bar)) }
        }
    }

    /// A quest done opened a border of its while you were away in a window: the bar across its gate,
    /// or the fence along it, poofs away (`WorldScene.openBarricades`).
    func openGates() {
        gates.removeAll { gate in
            let joined = Continent.joined(def.id, gate.neighbour.def.id, done: session.hasCompleted)
            guard !gate.neighbour.isWalled(done: session.hasCompleted, joined: joined) else { return false }
            for node in gate.bar {
                if let parent = node.parent { SkillEffects.smoke(at: node.position, in: parent) }
                node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
            return true
        }
    }

    /// Where a terrace's top is sorted: just behind its back corner (`WorldScene.topZ`).
    private static func topZ(of cells: Set<GridPoint>) -> CGFloat {
        let tile = WorldMap.tileSize
        let back = cells.map { WorldMap.project(CGPoint(x: CGFloat($0.col + 1) * tile, y: CGFloat($0.row + 1) * tile)).y }.max() ?? 0
        return -back - 0.75
    }

    /// White, solid along the top row and fading smoothly to clear at the bottom (tinted per land).
    private static let fogTexture: SKTexture = {
        let height = 64
        var pixels = [UInt8](repeating: 0, count: height * 4)
        for row in 0..<height {
            let t = 1 - Double(row) / Double(height - 1)
            let alpha = UInt8((t * t * (3 - 2 * t) * 255).rounded())
            for channel in 0..<4 { pixels[row * 4 + channel] = alpha }
        }
        let texture = PixelImage.make(pixels, width: 1, height: height).map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        return texture
    }()

    /// The land's surrounding ground, averaged and hazed into a pale mist (`WorldScene.fogColor`).
    private static func fogColor(from image: CGImage) -> UIColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let average = [CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255]
        let haze: [CGFloat] = [0.86, 0.9, 0.94]
        let channel = (0..<3).map { average[$0] + (haze[$0] - average[$0]) * 0.4 }
        return UIColor(red: channel[0], green: channel[1], blue: channel[2], alpha: 1)
    }
}
