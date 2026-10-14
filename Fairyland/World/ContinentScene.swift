import SpriteKit

/// The continent as one place, with no borders (docs/continuous-world.md, step 2): every land on it
/// drawn a chunk at a time round the camera (`World.chunkSize` cells a side), from the lands' own
/// layouts and plans, each laid out as you come near it. So far its ground, sea, hills, shore,
/// bridges and scenery, and you walking about on it (with the stick, or tapping where to go) from
/// one land into the next, each greeting you by name; a debug launch shows it (`continent`) until it
/// takes over from the lands' own scenes.
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

    /// A land near you, laid out and planned: its own map, how its ground is tiled, its hills and
    /// shore ready to draw, what it sets down (`LandStage`), and where its own points lie in the
    /// continent's.
    private final class Land {
        let def: MapDef
        let place: World.Land
        let map: WorldMap
        let tiles: GroundTiles
        let shift: CGVector
        let stage: LandStage
        /// Its hills and its shore, each ready to draw a square at a time (`HillArt.Painter`), and the
        /// squares each chunk draws: those whose south-west corner is in it.
        let painters: [HillArt.Painter]
        let squares: [GridPoint: [(painter: Int, corner: GridPoint)]]
        /// Its shore's cells, drawn sunk with it rather than flat (`WorldMap.shore`).
        let sunk: Set<GridPoint>

        init(def: MapDef, place: World.Land, map: WorldMap, tiles: GroundTiles, painters: [HillArt.Painter], stage: LandStage) {
            self.def = def
            self.place = place
            self.map = map
            self.tiles = tiles
            self.painters = painters
            self.stage = stage
            shift = ContinentScene.shift(of: place)
            var squares: [GridPoint: [(painter: Int, corner: GridPoint)]] = [:]
            for (number, painter) in painters.enumerated() {
                for corner in painter.corners {
                    let world = GridPoint(col: corner.col + place.origin.col, row: corner.row + place.origin.row)
                    squares[World.chunk(of: world), default: []].append((number, corner))
                }
            }
            self.squares = squares
            sunk = map.shore?.cells ?? []
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
    private let seaTile = "raw:tile_water"
    /// Squares of hills and shore waiting to be drawn (nearest first), and whether they're being drawn.
    private var waiting: [(chunk: GridPoint, land: String, painter: Int, corner: GridPoint)] = []
    private var painting = false
    /// When the work under way last had the frame back (`breathe`).
    private var sliceStart = ContinuousClock.now
    /// The land you're in (`arrive(in:)`): the one that owns where you stand, once you're a cell
    /// over its line.
    private(set) var here: MapDef?
    /// The world cell you last stood in.
    private var lastCell: GridPoint?
    private var leftFoot = false
    /// The name of the land you've just walked into, at the top of the screen for a moment.
    private var banner: SKNode?
    /// Who you're walking up to talk to (a tap on them), by land and id; near enough is `talkRange`.
    private var talkTarget: (land: String, npc: String)?
    private let talkRange: CGFloat = 50
    /// Walking up to someone opens their window; tapping a passer-by shows who they are.
    var onTalk: (@MainActor (NPCDef) -> Void)?
    var onInspect: (@MainActor (Profile) -> Void)?
    /// A random battle with the land's monsters, and what was on screen for behind it.
    var onEncounter: (@MainActor (MapDef.Encounters, SKTexture?) -> Void)?
    /// Set while a window or a battle is up (`MapScene`).
    var isInputLocked = false
    /// Debug launches walking you about (`crossing`): no battles on the way.
    var holdsEncounters = false
    private var stepsSinceBattle = 0
    private var pinchStartZoom: CGFloat = 1
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

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

    override func didMove(to view: SKView) {
        view.addGestureRecognizer(pinch)
        cam.setScale(1 / WorldScene.zoom)
        lastUpdate = 0
    }

    override func willMove(from view: SKView) {
        view.removeGestureRecognizer(pinch)
    }

    /// Pinch to zoom, as on a land of its own (`WorldScene.zoom`, kept from one to the other).
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pinchStartZoom = WorldScene.zoom }
        WorldScene.zoom = min(WorldScene.zoomRange.upperBound, max(WorldScene.zoomRange.lowerBound, pinchStartZoom * gesture.scale))
        cam.setScale(1 / WorldScene.zoom)
    }

    /// Where a land's own points lie in the continent's: its origin, projected.
    static func shift(of land: World.Land) -> CGVector {
        let origin = WorldMap.project(CGPoint(x: CGFloat(land.origin.col) * WorldMap.tileSize, y: CGFloat(land.origin.row) * WorldMap.tileSize))
        return CGVector(dx: origin.x, dy: origin.y)
    }

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
    static func projected(_ node: SKNode) -> SKNode {
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
        if isInputLocked {
            player.setWalking(false)
        } else if stick.length > 0.15 {
            player.path = []
            talkTarget = nil
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
            player.setWalking(player.followPath(dt: dt) || !player.path.isEmpty)
            player.zPosition = -player.position.y
        }
        if !isInputLocked {
            checkCell()
            checkTalkTarget()
        }
        player.settle()
        cam.position = player.position + CGVector(dx: 0, dy: player.lift)
        for land in lands.values {
            land.stage.update(dt: dt, player: player.position, camera: cam.position, scale: cam.xScale, screen: size)
        }
        if currentTime - lookedAround > 0.25 {
            lookedAround = currentTime
            lookAround()
        }
    }

    /// Whether you can step onto a point from where you stand: onto ground a land's laid out and you
    /// can walk on, and over a border only where it's open.
    private func canStand(at point: CGPoint) -> Bool {
        let cell = Self.cell(at: point)
        return store.isWalkable(cell) && canCross(from: Self.cell(at: player.position), to: cell)
    }

    /// Whether the borders you can walk across, by the two lands' ids (in order), are open: worked
    /// out when they're wanted, and again after a window closes (a quest may have opened one).
    private var openBorders: [String: Bool] = [:]

    /// Whether a step from one world cell to the next is allowed: within a land always; from one
    /// land into another only where you can cross the border between them (`Continent.Neighbour`:
    /// a road joins them, its quest done), as on the lands' own maps.
    private func canCross(from: GridPoint, to: GridPoint) -> Bool {
        guard let a = store.land(at: from)?.id, let b = store.land(at: to)?.id, a != b else { return true }
        let key = a < b ? a + "|" + b : b + "|" + a
        if let known = openBorders[key] { return known }
        var open = false
        if let def = Content.shared.map(a), let neighbour = Continent.neighbours(of: def).first(where: { $0.def.id == b }) {
            open = neighbour.isCrossable(done: session.hasCompleted, joined: Continent.joined(a, b, done: session.hasCompleted))
        }
        openBorders[key] = open
        return open
    }

    /// Tapping someone of a land's walks you up to talk to them; a passer-by turns to you and shows
    /// who they are; the ground walks you there, the shortest way within reach (`World.path`), to the
    /// very spot if you can stand on it.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isInputLocked, let point = touches.first?.location(in: layer) else { return }
        for land in lands.values {
            guard let npc = land.stage.npc(tappedAt: point) else { continue }
            talkTarget = (land.def.id, npc.def.id)
            npc.node.revealTag()
            walk(to: npc.node.position + land.shift, marked: false)
            return
        }
        talkTarget = nil
        for land in lands.values {
            guard let crowd = land.stage.crowd else { continue }
            let spot = land.stage.local(point)
            if let adventurer = crowd.adventurer(at: spot) {
                crowd.greet(at: spot, from: land.stage.local(player.position))
                player.path = []
                onInspect?(.adventurer(adventurer))
                return
            }
            crowd.greet(at: spot, from: land.stage.local(player.position))
        }
        // A tap on a hilltop means the top, not the ground it hides: worked out by the land there.
        var ground = point
        if let owner = store.land(at: Self.cell(at: point)), let land = lands[owner.id] {
            let local = CGPoint(x: point.x - land.shift.dx, y: point.y - land.shift.dy)
            ground = land.map.groundPoint(under: local) + land.shift
        }
        walk(to: ground, marked: true)
    }

    /// Walks you to `ground` (the continent's points) the shortest way within reach, to the very
    /// spot if you can stand on it; `marked`, with the tap's mark where you'll stop.
    private func walk(to ground: CGPoint, marked: Bool) {
        let tapped = Self.cell(at: ground)
        guard let start = store.nearestWalkable(to: Self.cell(at: player.position), within: 2),
              let goal = store.nearestWalkable(to: tapped) else { return }
        var points = store.path(from: start, to: goal) { [unowned self] in self.canCross(from: $0, to: $1) }.map { Self.center(of: $0) }
        guard !points.isEmpty || start == goal else { return }
        if goal == tapped {
            if points.isEmpty { points = [ground] } else { points[points.count - 1] = ground }
        }
        player.path = points
        if marked, let end = points.last {
            Effects.tapMarker(at: end + CGVector(dx: 0, dy: groundHeight(at: end)), in: layer)
        }
    }

    /// Once you're near enough whoever you were walking up to, their window opens; if you stop short
    /// (the way was blocked), you've given up.
    private func checkTalkTarget() {
        guard let target = talkTarget, let stage = lands[target.land]?.stage,
              let npc = stage.npcs.first(where: { $0.def.id == target.npc }) else { return }
        let at = npc.node.position + stage.shift
        if player.position.distance(to: at) <= talkRange {
            talkTarget = nil
            player.path = []
            player.setWalking(false)
            player.face(Direction(at - player.position))
            onTalk?(npc.def)
        } else if player.path.isEmpty {
            talkTarget = nil
        }
    }

    // MARK: The land you're in

    /// Each step onto a new cell: footsteps, the land you're in, and where you stand there for the
    /// game to keep (its own points and cell, as on a land of its own).
    private func checkCell() {
        let cell = Self.cell(at: player.position)
        // Till the land you start in is laid out, you're in none, standing still or not.
        let starting = here == nil
        if starting { checkLand(at: cell) }
        guard cell != lastCell || (starting && here != nil) else { return }
        lastCell = cell
        if GameSettings.footsteps, !starting {
            // Alternate feet, a touch louder and softer.
            leftFoot.toggle()
            SoundEffects.shared.play(.step, volume: leftFoot ? 0.6 : 0.45)
        }
        if !starting { checkLand(at: cell) }
        guard let here, let land = lands[here.id] else { return }
        session.playerPosition = CGPoint(x: player.position.x - land.shift.dx, y: player.position.y - land.shift.dy)
        session.mapCell = store.local(cell, in: land.place)
        // Out in the wild, now and then, the land's monsters (`MapDef.Encounters`), as on its own map.
        guard !starting, let encounters = here.encounters else { return }
        stepsSinceBattle += 1
        if !holdsEncounters, stepsSinceBattle > encounters.graceSteps, Double.random(in: 0..<1) < encounters.rate {
            stepsSinceBattle = 0
            startEncounter(encounters)
        }
    }

    /// The screen flashes twice and the battle begins, where you stand (`WorldScene.startEncounter`).
    private func startEncounter(_ encounters: MapDef.Encounters) {
        isInputLocked = true
        player.path = []
        talkTarget = nil
        player.setWalking(false)
        let flash = SKSpriteNode(color: .white, size: size)
        flash.alpha = 0
        flash.zPosition = 50_000
        cam.addChild(flash)
        Task {
            await flash.run(.sequence([
                .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
                .fadeAlpha(to: 0.85, duration: 0.08), .fadeAlpha(to: 0, duration: 0.08),
            ]))
            flash.removeFromParent()
            onEncounter?(encounters, battleBackdrop(hiding: nil))
        }
    }

    /// What's on screen right now, for behind a battle: you (and a boss, `npcID`) and the tap marks
    /// left out, as the battle draws the party itself.
    func battleBackdrop(hiding npcID: String?) -> SKTexture? {
        let visible = CGRect(x: cam.position.x - size.width / 2, y: cam.position.y - size.height / 2, width: size.width, height: size.height)
        let boss: [SKNode] = lands.values.flatMap { land in land.stage.npcs.filter { $0.def.id == npcID }.map(\.node) }
        let hidden: [SKNode] = [player] + boss + layer.children.filter { $0.name == Effects.tapMarkerName }
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }
        return view?.texture(from: layer, crop: visible)
    }

    /// Back from a battle or a window (`MapScene`): you can walk again.
    func resume() {
        openBorders = [:]
        isInputLocked = false
        lastUpdate = 0
        input.move = .zero
    }

    /// Into the land that owns `cell`, once it's laid out, if you aren't in it already: a cell in from
    /// its line, so walking along the line doesn't flick from one to the other.
    private func checkLand(at cell: GridPoint) {
        guard let owner = store.land(at: cell), owner.id != here?.id, lands[owner.id] != nil,
              let def = Content.shared.map(owner.id) else { return }
        if here != nil {
            for dr in -1...1 {
                for dc in -1...1 {
                    if let other = store.land(at: GridPoint(col: cell.col + dc, row: cell.row + dr)), other.id != owner.id { return }
                }
            }
        }
        arrive(in: def)
    }

    /// You've walked into a land: its light on everyone, its music, and the game knows you're there
    /// (its checkpoint, the map you're on); and, new to you since you were last in it, its name at
    /// the top of the screen and in the chat (as `WorldScene.didMove` greets you).
    private func arrive(in def: MapDef) {
        let walkedIn = here != nil
        here = def
        for land in lands.values { land.stage.isHere = land.def.id == def.id }
        Walker.light = WorldScene.light(of: def)
        player.relight()
        MusicPlayer.shared.play(def.music)
        session.data.mapID = def.id
        session.markVisited(def.id)
        session.reachCheckpoint(def)
        if walkedIn { session.bossesBeatenHere = [] }
        guard session.mapName != def.name else { return }
        session.post(L("You arrive at {map}.", ["map": def.name]))
        if def.danger == true {
            session.post(L("⚔ Danger zone! Adventurers here may pick a fight."), .battle)
        }
        session.startChat(on: def.name)
        session.mapName = def.name
        showBanner(def.name)
    }

    #if DEBUG
    /// Debug launches (`continent,near=<land>,crossing`): walks you over the line into that land, to
    /// the nearest cell of it you can walk to with its own land all round it, and returns once
    /// you're in it (or after half a minute).
    func walkIntoForDebug(_ id: String) async {
        let from = Self.cell(at: player.position)
        func inside(_ cell: GridPoint) -> Bool {
            guard store.isWalkable(cell) else { return false }
            for dr in -2...2 {
                for dc in -2...2 where store.land(at: GridPoint(col: cell.col + dc, row: cell.row + dr))?.id != id { return false }
            }
            return true
        }
        var goal: GridPoint?
        search: for radius in 1...48 {
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dr), abs(dc)) == radius {
                    let cell = GridPoint(col: from.col + dc, row: from.row + dr)
                    if inside(cell) {
                        goal = cell
                        break search
                    }
                }
            }
        }
        guard let goal, let start = store.nearestWalkable(to: from, within: 2) else { return }
        holdsEncounters = true
        player.path = store.path(from: start, to: goal) { [unowned self] in self.canCross(from: $0, to: $1) }.map { Self.center(of: $0) }
        for _ in 0..<120 where here?.id != id {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
    #endif

    /// A land's name at the top of the screen as you walk into it, fading in and away.
    private func showBanner(_ name: String) {
        banner?.removeFromParent()
        let tag = NameTag(name, color: Nodes.gold, size: 20)
        tag.position = CGPoint(x: 0, y: size.height / 2 - 90)
        tag.zPosition = 45_000
        tag.alpha = 0
        cam.addChild(tag)
        tag.run(.sequence([.fadeIn(withDuration: 0.6), .wait(forDuration: 2.4), .fadeOut(withDuration: 0.9), .removeFromParent()]))
        banner = tag
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
        if missing == 0, waiting.isEmpty, !painting { isReady = true }
        // The lands' people: their quest marks, and townsfolk watching you pass.
        for land in lands.values { _ = land.stage.updateNotices(player: player.position, reach: talkRange + 12) }
        for chunk in chunks.keys where max(abs(chunk.col - here.col), abs(chunk.row - here.row)) > Self.keep {
            if let gone = chunks.removeValue(forKey: chunk) {
                gone.ground.removeFromParent()
                gone.sea.removeFromParent()
                gone.things.removeFromParent()
                waiting.removeAll { $0.chunk == chunk }
            }
        }
    }

    /// The lands owning any cell of a chunk.
    private func owners(of chunk: GridPoint) -> Set<String> {
        Set(World.cells(in: chunk).compactMap { store.land(at: $0)?.id })
    }

    /// Lays a land out off the main thread, then plans its scenery, takes it into the store and makes
    /// its hills and shore ready to draw; then draws its squares in the chunks already drawn.
    private func layOut(_ id: String) {
        guard !laying.contains(id), let def = Content.shared.map(id), let place = store.land(id) else { return }
        laying.insert(id)
        Task { [weak self] in
            let map = await GameCoordinator.layOut(def)
            guard let self else { return }
            let rest = self.pause(for: def)
            art.use(palette: def.theme.palette, for: def.id)
            let planner = LandPlanner(def: def, map: map, art: art)
            await planner.planUpToLocals(pause: rest)
            await planner.planTheRest(pause: rest)
            store.add(map)
            let tiles = GroundTiles(map: map, art: art)
            let painters = await ranges(of: map, tiles: tiles, place: place, pause: rest)
            let stage = LandStage(def: def, map: map, plan: planner.plan, tiles: tiles, art: art, session: session, shift: Self.shift(of: place))
            await stage.build(pause: rest)
            layer.addChild(stage.world)
            let land = Land(def: def, place: place, map: map, tiles: tiles, painters: painters, stage: stage)
            lands[id] = land
            laying.remove(id)
            for chunk in chunks.keys { paintSquares(of: land, in: chunk) }
        }
    }

    /// A pause in work on `def`'s land: gives the frame back once the work's had it a while, then
    /// grades with that land's palette again, as other work may have changed it meanwhile.
    private func pause(for def: MapDef) -> () async -> Void {
        { [weak self] in
            guard let self else { return }
            await breathe()
            art.use(palette: def.theme.palette, for: def.id)
        }
    }

    /// Gives the frame back once work's had it for a few milliseconds; for longer before the chunks
    /// round where you started are drawn, as there's nothing yet to keep smooth.
    private func breathe() async {
        let slice: Duration = isReady ? .milliseconds(6) : .milliseconds(40)
        guard ContinuousClock.now - sliceStart > slice else { return }
        try? await Task.sleep(for: .milliseconds(10))
        sliceStart = ContinuousClock.now
    }

    /// A land's hills and its shore, made ready to draw a square at a time as its own scene draws them
    /// (`HillLooks`), over its colour patches and with its bridges' decks out over a sunk lake. And,
    /// for the whole land at once (they're light), its colour patches and bridges' decks on the
    /// ground (their rails stand with the rest of what it sets down, `LandStage`).
    private func ranges(of map: WorldMap, tiles: GroundTiles, place: World.Land, pause: @escaping () async -> Void) async -> [HillArt.Painter] {
        let def = map.def, theme = def.theme, tile = WorldMap.tileSize
        // On the ground, in the land's own grid points: its soft colour patches over its own cells
        // (`Lighting.groundVariation`), and its bridges' decks lying on the water.
        let flat = SKNode()
        flat.position = CGPoint(x: CGFloat(place.origin.col) * tile, y: CGFloat(place.origin.row) * tile)
        let variation = Lighting.groundVariation(columns: map.columns, rows: map.rows, tile: tile, palette: theme.palette,
                                                 seed: def.id) { col, row in map.owns(GridPoint(col: col, row: row)) }
        if let variation {
            variation.zPosition = 1
            flat.addChild(variation)
        }
        groundGrid.addChild(flat)
        await pause()
        // Its picture, for the hills and the shore, made once (`SKTexture.cgImage()` is slow).
        let variationPicture = map.hills.isEmpty && map.shore == nil ? nil : variation?.texture?.cgImage()
        // Over a sunk lake, the bridges' decks are drawn with the shore.
        let sunk = map.shore?.cells ?? []
        var sunkDecks: [(image: CGImage, frame: CGRect)] = []
        if !map.bridges.isEmpty {
            let pixels = art.picture(of: art.tileTexture(theme.ground)).width
            for bridge in map.bridges {
                if bridge.cells.contains(where: { sunk.contains($0) }) {
                    if let deck = BridgeArt.deckPicture(for: bridge, pixels: pixels, palette: theme.palette) { sunkDecks.append(deck) }
                } else if let deck = BridgeArt.deck(for: bridge, pixels: pixels, palette: theme.palette) {
                    deck.zPosition = 2
                    flat.addChild(deck)
                }
            }
            await pause()
        }
        // Each cell's own tile picture, as the land's ground shows it.
        var images: [ObjectIdentifier: CGImage] = [:]
        let tilePicture: (GridPoint) -> CGImage? = { [weak self] cell in
            guard let self, map.contains(cell), let group = tiles.pick(cell).group else { return nil }
            if let known = images[ObjectIdentifier(group)] { return known }
            let made = tiles.pictures[ObjectIdentifier(group)].map { self.art.picture(of: $0) }
            images[ObjectIdentifier(group)] = made
            return made
        }
        var painters: [HillArt.Painter] = []
        if !map.hills.isEmpty {
            let looks = HillLooks(map: map, art: art, ground: tilePicture, variation: variationPicture)
            for hill in map.hills {
                await pause()
                if let painter = await HillArt.painter(for: hill, look: looks.look(for: hill), pause: pause) { painters.append(painter) }
            }
        }
        if let shore = map.shore {
            await pause()
            let look = HillLooks.shore(of: map, ground: tilePicture, variation: variationPicture, overlays: sunkDecks)
            if let painter = await HillArt.painter(for: shore, look: look, pause: pause) { painters.append(painter) }
        }
        return painters
    }

    /// Draws a land's squares of hills and shore in a chunk, nearest the camera first, in the
    /// background: each lifts itself and is sorted among what stands there (`HillArt`).
    private func paintSquares(of land: Land, in chunk: GridPoint) {
        for square in land.squares[chunk] ?? [] { waiting.append((chunk, land.def.id, square.painter, square.corner)) }
        guard !painting, !waiting.isEmpty else { return }
        painting = true
        Task { [weak self] in await self?.paintWaiting() }
    }

    private func paintWaiting() async {
        while !waiting.isEmpty {
            let here = World.chunk(of: Self.cell(at: cam.position))
            func away(_ chunk: GridPoint) -> Int { max(abs(chunk.col - here.col), abs(chunk.row - here.row)) }
            guard let next = waiting.indices.min(by: { away(waiting[$0].chunk) < away(waiting[$1].chunk) }) else { break }
            let job = waiting.remove(at: next)
            guard let things = chunks[job.chunk]?.things, let land = lands[job.land] else { continue }
            art.use(palette: land.def.theme.palette, for: land.def.id)
            let sprites = await land.painters[job.painter].draw(job.corner, self.pause(for: land.def))
            // Unless the chunk's been let go meanwhile (and maybe drawn again, with its own).
            guard chunks[job.chunk]?.things === things else { continue }
            for sprite in sprites {
                sprite.position = sprite.position + land.shift
                sprite.zPosition -= land.shift.dy
                things.addChild(sprite)
            }
            await breathe()
        }
        painting = false
    }

    /// Draws a chunk: each land's cells in it with that land's tiles, graded with its palette; the
    /// sea where no land is; and (in the background) its squares of hills and shore. What the lands
    /// set down on it is theirs to show (`LandStage.show`).
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
                // The shore's drawn sunk, with its hills (`paintSquares`).
                let local = store.local(cell, in: land.place)
                guard !land.sunk.contains(local), let group = land.tiles.pick(local).group else { continue }
                picks.append((cell.col - origin.col, cell.row - origin.row, group))
                groups[ObjectIdentifier(group)] = group
            }
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
        for land in lands.values { paintSquares(of: land, in: chunk) }
    }
}
