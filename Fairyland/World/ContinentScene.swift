import SpriteKit

/// The continent as one place, with no borders (docs/continuous-world.md, step 2): every land on it
/// drawn a chunk at a time round the camera (`World.chunkSize` cells a side), from the lands' own
/// layouts and plans, each laid out as you come near it: its ground, sea, hills, shore and scenery,
/// its people and animals, its air, and you and your party walking about on it from one land into
/// the next with no border between them, each greeting you by name. Caves keep scenes of their own
/// (`WorldScene`), behind the loading card.
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
    /// The bank of earth down from the land's edge to the sea, a layer a step lower each, and the
    /// foam at its foot, the last (`bank`).
    private let bankGrids = (0...ContinentScene.bankSteps).map { _ in SKNode() }
    private static let bankSteps = 7
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
        /// Whether it comes down to the sea anywhere, so has a bank along it (`drawBank`).
        let coastal: Bool
        /// Its minimap, one pixel a cell (`WorldScene.overview`), made when it's first wanted; and
        /// remembered for the world map and the lands round it (`WorldOverview`).
        lazy var overview: CGImage = {
            let image = WorldScene.overview(of: self.map, art: ArtLibrary.shared)
            WorldOverview.shared.remember(self.def.id, image)
            return image
        }()

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
            coastal = map.shore != nil || map.ground.contains { $0.contains(.sea) }
        }
    }
    private var lands: [String: Land] = [:]
    /// The lands with a chunk drawn round you: the ones whose people and animals go about and that
    /// show (`update`). The rest wait, hidden, till you come near them again (`lookAround`).
    private var nearLands: Set<String> = []
    /// The lands wanted laid out, by how far off they are (in cells from you to the nearest of theirs
    /// in the chunks round you; the land you're put in or stand in first, at -1), laid out one at a
    /// time, nearest first (`buildWanted`); and the one being laid out now.
    private var wanted: [String: Int] = [:]
    private var building: String?
    /// Whether a land not laid out yet is under your feet or near enough to walk onto soon
    /// (`urgentReach`): the work takes longer slices till it's in (`breathe`).
    private var isUrgent = false
    private static let urgentReach = 20
    /// Whether the land under your feet isn't laid out yet (you walked onto its plain ground): its
    /// work takes the longest slices that still let you walk (`breathe`), and a note says how far
    /// it's come (`showLoading`).
    private var standsOnUnbuilt = false
    /// How far each land being built has come, 0 to 1 by its steps (`build`).
    private var progress: [String: Double] = [:]
    private var loadingNote: NameTag?
    /// A chunk drawn: its ground (a tile map for each land laid out, and one in its plain ground
    /// for each land not laid out yet, `placeholders`), its sea, and what stands on it.
    private final class Chunk {
        let ground = SKNode()
        var sea: SKNode
        let things = SKNode()
        var placeholders: [String: SKNode] = [:]
        /// The bank along the coast and the foam at its foot, a layer a step (`bankGrids`).
        var banks: [SKNode] = []

        init(sea: SKNode) {
            self.sea = sea
        }
    }
    private var chunks: [GridPoint: Chunk] = [:]
    /// Each chunk's lands (they never change), with the box round each one's cells in it, worked out
    /// once.
    private var owned: [GridPoint: [String: (low: GridPoint, high: GridPoint)]] = [:]
    /// Each land's plain ground as a tile, for its cells till it's laid out (`placehold`), and its
    /// road's tile and cells (`placeholderRoads`).
    private var placeholderTiles: [String: SKTileGroup] = [:]
    private var placeholderRoadTiles: [String: SKTileGroup] = [:]
    private var placeholderRoadCells: [String: Set<GridPoint>] = [:]
    /// How many chunks round yours are drawn, and how far off they're let go.
    static let reach = 2
    static let keep = 3
    private var lookedAround: TimeInterval = 0
    /// True once the land you're in is drawn round you, its hills and shore too (the loading card
    /// waits); the lands round it come in as they're laid out (`isSettled`).
    private(set) var isReady = false
    /// True once every land round you is laid out and drawn too (a debug launch's screenshot waits).
    var isSettled: Bool {
        isReady && building == nil && wanted.isEmpty && waiting.isEmpty && !painting
    }
    /// Debug launches waiting for the lands round you (`isSettled`): the work keeps its longer
    /// slices till they're in.
    var hurries = false
    /// The sea's picture (`tools/water_art.py`): `seaCells` cells a side that tile as a whole, the
    /// same blue round every land ("raw:", graded for none).
    private let seaSheet = "raw:sea"
    /// The sea's tiles, the picture cut a cell at a time (by row from the south), and the tile set
    /// they make: each world cell takes the one at its place in it (`seaGroup`), so the sea repeats
    /// only every `seaCells` cells, not every tile.
    private lazy var seaGroups: [SKTileGroup] = {
        let sheet = art.tileTexture(seaSheet)
        let step = 1 / CGFloat(seaCells), size = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        var groups: [SKTileGroup] = []
        for row in 0..<seaCells {
            for col in 0..<seaCells {
                let part = SKTexture(rect: CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step, width: step, height: step), in: sheet)
                part.filteringMode = .nearest
                groups.append(SKTileGroup(tileDefinition: SKTileDefinition(texture: part, size: size)))
            }
        }
        return groups
    }()
    private lazy var seaCells = max(1, Int((art.tileTexture(seaSheet).size().width / 32).rounded()))
    private lazy var seaTiles = SKTileSet(tileGroups: seaGroups)
    /// Squares of hills and shore waiting to be drawn (nearest first), and whether they're being drawn;
    /// and a chunk's bank along the sea (`bankJob` for its painter).
    private var waiting: [(chunk: GridPoint, land: String, painter: Int, corner: GridPoint)] = []
    private static let bankJob = -1
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
    /// Into a cave through its mouth (off the continent: behind the card, as ever).
    var onTravel: (@MainActor (MapDef.Exit) -> Void)?
    /// A duel with an adventurer who dared you (or you them), and what was on screen behind it.
    var onDuel: (@MainActor (Adventurer, SKTexture?) -> Void)?
    /// Whoever of the lands' people is near enough to talk to (the HUD's Talk button), by land.
    private var nearbyTalk: (land: String, npc: String)?
    /// What happens once a Homeward Feather has lifted you away (`featherAway`).
    private var onFeatherGone: (() -> Void)?
    /// Your party's friends: walking behind you, or waiting where you left them (on a land that's
    /// laid out) until you walk up to them (`Adventurer.waitingAt`), with their companions.
    private struct Ally {
        let id: UUID
        let node: Walker
        var pet: Walker?
        var waiting: Spot?
    }
    private var allies: [Ally] = []
    /// How close you come to a friend waiting for you before they set off with you again.
    private let rejoinRange: CGFloat = 64
    /// Set while a window or a battle is up (`MapScene`).
    var isInputLocked = false
    /// Debug launches walking you about (`crossing`): no battles on the way.
    var holdsEncounters = false
    private var stepsSinceBattle = 0
    /// Your companion, walking behind you, and what you and it were last drawn as (`refreshHero`,
    /// `refreshFollower`).
    private var follower: Walker?
    private var followerKey: String?
    private var heroKey: String?
    /// The minimap of the land you're in, with what's round it, as last drawn (`minimapPicture`).
    private var surrounded: (land: String, overviews: Int, picture: WorldScene.MinimapPicture)?
    /// The air of each land you've been in (`Air`), by its id.
    private var airs: [String: Air] = [:]
    private var sunTimer: TimeInterval = 0
    /// Whether you've been put somewhere on it (`place`): till then it draws nothing.
    private var placed = false
    /// Lands laid out already (`adopt`: the one a save starts in, laid out off the main thread as
    /// the game opened), taken instead of laying them out again.
    private var laidOut: [String: WorldMap] = [:]
    /// The next land's layout under way off the main thread while this one's planned and drawn on
    /// it (`layOutNext`), so one land's layout needn't wait for the last land's drawing.
    private var layingOut: (id: String, task: Task<WorldMap, Never>)?
    /// Lands laid out while the continent was off screen (a battle, a cave), their ground still to
    /// show in the chunks drawn: a tile map made then never showed (`didMove`).
    private var unshown: Set<String> = []
    /// Chunks drawn before the last battle or cave and not made afresh since (`redraw`): those round
    /// you are as you come back (`didMove`), the rest as you come near them (`lookAround`).
    private var stale: Set<GridPoint> = []
    private var pinchStartZoom: CGFloat = 1
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

    /// `point`: where you start, in the continent's points; none till you're put somewhere (`place`).
    init(session: GameSession, input: InputState, at start: CGPoint? = nil) {
        let point = start ?? .zero
        placed = start != nil
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
        // Each lower than the last, the foam just below the bottom one, all under the land
        // (`WorldScene.bank`).
        for (step, grid) in bankGrids.enumerated() {
            let bank = Self.projected(grid)
            let foam = step == Self.bankSteps
            bank.position.y = foam ? -WorldMap.seaDrop - 1.5 : -WorldMap.seaDrop * CGFloat(step + 1) / CGFloat(Self.bankSteps)
            bank.zPosition = -100_000.1 - 0.05 * CGFloat(step)
            layer.addChild(bank)
        }
        addChild(layer)
        player.tagMode = .whenStill
        player.fidgets = true
        player.position = point
        player.zPosition = -point.y
        layer.addChild(player)
        addChild(cam)
        camera = cam
        cam.position = point
        backgroundColor = UIColor(red: 0.36, green: 0.62, blue: 0.82, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A land's air as on its own map: drifting particles, butterflies and clouds' shadows, its
    /// colour mood and vignette (`Ambience`), its sunbeams, pools of light, haze and the sun's flare
    /// (`Lighting`), and its time of day and weather (`Sky`). Its parts on the screen hang in a layer
    /// of their own on the camera (an `SKCameraNode` the scene doesn't look through, as those take a
    /// camera); `mood` fades it in while you're in the land and out as you walk into the next, whose
    /// own comes in.
    private final class Air {
        let layer = SKCameraNode()
        let ambience: Ambience?
        let lighting: Lighting?
        let sky: Sky?
        var mood: CGFloat = 0

        init(stage: LandStage, camera: SKCameraNode, start: Date?, screen: CGSize) {
            let def = stage.def
            camera.addChild(layer)
            ambience = Ambience(def.ambience, world: stage.air, camera: layer, bounds: stage.map.bounds, seed: def.id,
                                inside: { [weak stage] in stage?.onLand($0) ?? $0 })
            lighting = Lighting(def.ambience, world: stage.air, camera: layer, bounds: stage.map.bounds, seed: def.id,
                                inside: { [weak stage] in stage?.onLand($0) ?? $0 })
            sky = Sky(map: def, camera: layer, start: start)
            ambience?.resize(to: screen)
            lighting?.resize(to: screen)
            if let sky { lighting?.sunlight(sky.sunlight) }
            lighting?.follow(sky?.sun ?? .noon)
            set(mood: 0)
        }

        /// Each part fades itself, the layer only hidden once it's gone: faded as a whole, the
        /// sky's multiplied shade went dark rather than faint as you walked into the next land.
        func set(mood: CGFloat) {
            self.mood = mood
            layer.isHidden = mood <= 0.01
            ambience?.setMood(mood)
            lighting?.setMood(mood)
            sky?.setMood(mood)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        for air in airs.values {
            air.ambience?.resize(to: size)
            air.lighting?.resize(to: size)
        }
    }

    /// The airs ease toward the land you're in's (over a second or so), its time of day and weather
    /// going on, its sun moved every half second.
    private func updateAir(_ dt: TimeInterval) {
        sunTimer -= dt
        let follow = sunTimer <= 0
        if follow { sunTimer = 0.5 }
        for (id, air) in airs {
            let goal: CGFloat = id == here?.id ? 1 : 0
            if air.mood != goal {
                let eased = air.mood + (goal - air.mood) * CGFloat(min(1, dt / 0.6))
                air.set(mood: abs(goal - eased) < 0.01 ? goal : eased)
            }
            guard air.mood > 0 else { continue }
            if let sky = air.sky {
                sky.update(dt)
                air.lighting?.sunlight(sky.sunlight)
                if follow { air.lighting?.follow(sky.sun) }
            }
        }
    }

    override func didMove(to view: SKView) {
        view.addGestureRecognizer(pinch)
        cam.setScale(1 / WorldScene.zoom)
        lastUpdate = 0
        // Back from a battle or a cave: the chunks round you made afresh (`redraw`), and the rest as
        // you come near them (`stale`), meanwhile with the ground of lands laid out since; then the
        // squares and banks left to draw.
        let middle = World.chunk(of: Self.cell(at: cam.position))
        for (key, drawn) in chunks {
            if max(abs(key.col - middle.col), abs(key.row - middle.row)) <= 1 {
                redraw(drawn, at: key)
                stale.remove(key)
            } else {
                stale.insert(key)
                for id in owners(of: key).sorted() where unshown.contains(id) {
                    if let land = lands[id] { show(land, in: drawn, at: key) }
                }
            }
        }
        unshown = []
        if !painting, !waiting.isEmpty {
            painting = true
            Task { [weak self] in await self?.paintWaiting() }
        }
        // Back from a battle, its song again, the victory tune fading out first (it stayed silent
        // till the next land's).
        if let here { MusicPlayer.shared.play(here.music, fade: Self.musicFade) }
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
    /// land whose it is, or out on a harbor's pier its deck: walkers stand on it (`Walker.settle`).
    func groundHeight(at point: CGPoint) -> CGFloat {
        let cell = Self.cell(at: point)
        guard let owner = store.land(at: cell), let land = lands[owner.id] else {
            return store.pier(at: cell) == nil ? 0 : WorldMap.pierHeight
        }
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
        // Your companion keeps to ground it can stand on, never into water or through a wall.
        player.markFootstep()
        let standable: (CGPoint) -> Bool = { [unowned self] in self.store.isWalkable(Self.cell(at: $0)) }
        if let follower {
            follower.follow(player, dt: dt, footstep: player.footstep(behind: 36), canStand: standable)
            follower.zPosition = -follower.position.y
            follower.settle()
        }
        // Your friends line up behind you; those waiting for you turn to watch you come.
        var leader: Walker = follower ?? player
        var place = follower == nil ? 1 : 2
        for ally in allies {
            if ally.waiting == nil {
                let behind = CGFloat(place) * 36
                ally.node.follow(leader, dt: dt, footstep: player.footstep(behind: behind), canStand: standable)
                ally.pet?.follow(ally.node, dt: dt, footstep: player.footstep(behind: behind + 18), canStand: standable, beside: true)
                leader = ally.node
                place += 1
            } else if ally.node.position.distance(to: player.position) < Walker.nameRange {
                ally.node.face(Direction(player.position - ally.node.position, current: ally.node.facing))
            }
            ally.node.zPosition = -ally.node.position.y
            ally.node.settle()
            if let pet = ally.pet {
                pet.zPosition = -pet.position.y
                pet.settle()
            }
        }
        player.settle()
        cam.position = player.position + CGVector(dx: 0, dy: player.lift)
        for id in nearLands {
            lands[id]?.stage.update(dt: dt, player: player.position, camera: cam.position, scale: cam.xScale, screen: size)
        }
        updateAir(dt)
        if currentTime - lookedAround > 0.25 {
            lookedAround = currentTime
            lookAround()
        }
    }

    /// Whether you can step onto a point from where you stand: onto ground you can walk on (on a land
    /// not laid out yet, anywhere but its rivers and lakes, `World.isWalkable`), and over a border
    /// only where it's open.
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
        // One on a harbor's pier means its deck, drawn a little over the sea.
        var ground = point
        let deck = CGPoint(x: point.x, y: point.y - WorldMap.pierHeight)
        if let owner = store.land(at: Self.cell(at: point)), let land = lands[owner.id] {
            let local = CGPoint(x: point.x - land.shift.dx, y: point.y - land.shift.dy)
            ground = land.map.groundPoint(under: local) + land.shift
        } else if store.pier(at: Self.cell(at: deck)) != nil {
            ground = deck
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
            Effects.tapMarker(at: end + CGVector(dx: 0, dy: groundHeight(at: end)), z: markZ(at: end), in: layer)
        }
    }

    /// How deep the tap's swirl at `point` sorts: over a hill, the sunk shore or a terrace's top, as
    /// the land there has it (`LandStage.markZ`), or they'd hide it; elsewhere under everything that
    /// stands.
    private func markZ(at point: CGPoint) -> CGFloat {
        guard let owner = store.land(at: Self.cell(at: point)), let land = lands[owner.id],
              let z = land.stage.markZ(at: land.stage.local(point)) else { return -50_000 }
        return z - land.shift.dy
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
        guard !starting else { return }
        // On a land not laid out yet, you're still in the last one (`checkLand`): none of its caves
        // or monsters there. Out on its harbor's pier, you're still in it.
        let ashore = store.land(at: cell)
        guard (ashore ?? store.pier(at: cell))?.id == here.id else { return }
        // Into a cave through its mouth, or aboard a ship at the end of a harbor's pier, over the
        // sea to the land it sails to: off where you are, behind the card.
        let cave = land.map.exit(at: session.mapCell).flatMap { Content.shared.world[$0.to] == nil ? $0 : nil }
        if let exit = cave ?? land.map.boarding(at: session.mapCell) {
            isInputLocked = true
            player.path = []
            player.setWalking(false)
            onTravel?(exit)
            return
        }
        // Out in the wild, now and then, the land's monsters (`MapDef.Encounters`), as on its own map;
        // none out on a pier.
        guard ashore != nil, let encounters = here.encounters else { return }
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
        var hidden: [SKNode] = [player]
        if let follower { hidden.append(follower) }
        for ally in allies {
            hidden.append(ally.node)
            if let pet = ally.pet { hidden.append(pet) }
        }
        hidden += boss
        hidden += layer.children.filter { $0.name == Effects.tapMarkerName }
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }
        guard let picture = view?.texture(from: layer, crop: visible) else { return nil }
        // One with nothing in it (as debug launches on CI get), none: the battle's own ground then
        // rather than its bare colour. The map's ground fills the screen, so a few points tell.
        let side = 16
        guard let pixels = PixelImage.pixels(of: picture.cgImage(), width: side, height: side),
              stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] > 0 }) else { return nil }
        return picture
    }

    // MARK: Talk, duels and the Homeward Feather (`MapScene`)

    /// The HUD's Talk button: whoever's near enough, unless something else has the map.
    func talkToNearby() {
        guard !isInputLocked, let near = nearbyTalk, let stage = lands[near.land]?.stage,
              let npc = stage.npcs.first(where: { $0.def.id == near.npc }) else { return }
        talkTarget = nil
        player.path = []
        player.setWalking(false)
        player.face(Direction(npc.node.position + stage.shift - player.position))
        onTalk?(npc.def)
    }

    /// You said something in the Chat window: a bubble over your head, and maybe an answer from
    /// someone about you.
    func heroSay(_ text: String) {
        player.say(text)
        session.postChat(text, from: session.data.hero.name, kind: .you)
        if let here, let stage = lands[here.id]?.stage { stage.crowd?.reply(near: stage.local(player.position)) }
    }

    /// An adventurer's answer (befriended, invited), in a bubble over them, wherever they are.
    func adventurerSays(_ line: String, _ id: UUID) {
        for land in lands.values { land.stage.crowd?.say(line, from: id) }
    }

    /// After a duel you won, the rival skulks off.
    func dismissAdventurer(_ id: UUID) {
        for land in lands.values { land.stage.crowd?.remove(id, poof: true) }
        if session.nearbyAdventurer?.id == id { session.nearbyAdventurer = nil }
    }

    /// A duel: the screen flashes red twice and it begins, where you stand.
    func startDuel(with rival: Adventurer) {
        guard !isInputLocked else { return }
        isInputLocked = true
        player.path = []
        talkTarget = nil
        player.setWalking(false)
        let flash = SKSpriteNode(color: UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 1), size: size)
        flash.alpha = 0
        flash.zPosition = 50_000
        cam.addChild(flash)
        Task {
            await flash.run(.sequence([.fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1), .fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1)]))
            flash.removeFromParent()
            onDuel?(rival, battleBackdrop(hiding: nil))
        }
    }

    /// A Homeward Feather's arrival (`featherArrive`), timed as on a land's own map
    /// (`WorldScene.Feather`); its departure (`featherAway`) is the same played backward.
    private enum Feather {
        static let height: CGFloat = 90
        static let drop = 0.85, appear = 0.45
        static let hold = 0.5, fade = 0.6
        static let count = 12
        static let flight = 1.2, stagger = 0.04
        static let length = flight + stagger * Double(count - 1)
        static let light = UIColor(red: 1, green: 0.95, blue: 0.78, alpha: 1)
    }

    /// A Homeward Feather taking you away: feathers spiral up round you, the column of light shines,
    /// and you rise into it and fade; then `done`.
    func featherAway(then done: @escaping () -> Void) {
        isInputLocked = true
        player.path = []
        player.setWalking(false)
        player.idles = false
        let column = featherColumn(over: player.position)
        column.alpha = 0
        column.run(.sequence([.wait(forDuration: Feather.length - Feather.hold - Feather.fade), .fadeAlpha(to: 0.9, duration: Feather.fade)]))
        featherGust(around: player.position, backward: true)
        let lift = SKAction.moveBy(x: 0, y: Feather.height, duration: Feather.drop)
        lift.timingMode = .easeIn
        player.sprite.run(.sequence([.wait(forDuration: Feather.length - Feather.drop), lift]), withKey: "feather")
        player.run(.sequence([.wait(forDuration: Feather.length - Feather.appear), .fadeOut(withDuration: Feather.appear)]))
        onFeatherGone = done
        Task {
            await run(.wait(forDuration: Feather.length))
            let gone = onFeatherGone
            onFeatherGone = nil
            gone?()
        }
    }

    /// Before you're shown: you aren't there yet (`featherArrive` brings you down).
    func awaitFeatherArrival() {
        player.idles = false
        player.alpha = 0
        player.sprite.position = CGPoint(x: 0, y: Feather.height)
    }

    /// Arriving by Homeward Feather: you float down in the light as the feathers settle.
    func featherArrive() {
        let column = featherColumn(over: player.position)
        column.alpha = 0.9
        column.run(.sequence([.wait(forDuration: Feather.hold), .fadeOut(withDuration: Feather.fade), .removeFromParent()]))
        featherGust(around: player.position, backward: false)
        player.run(.fadeIn(withDuration: Feather.appear))
        let drop = SKAction.move(to: .zero, duration: Feather.drop)
        drop.timingMode = .easeOut
        player.sprite.run(.sequence([drop, .run { [weak self] in self?.player.idles = true }]), withKey: "feather")
    }

    /// The soft column of light you rise into or come down in.
    private func featherColumn(over point: CGPoint) -> SKSpriteNode {
        let column = SkillEffects.glowSprite(Feather.light, size: CGSize(width: 70, height: 230))
        column.position = point + CGVector(dx: 0, dy: 80)
        column.zPosition = 30_000
        layer.addChild(column)
        return column
    }

    /// Feathers whirling round `center`: spiralling down from high up and out to settle, one after
    /// another; `backward`, the same played backward, as you leave.
    private func featherGust(around center: CGPoint, backward: Bool) {
        let texture = ArtLibrary.shared.sprite("item_homeward_feather").texture
        let flight = CGFloat(Feather.flight)
        for index in 0..<Feather.count {
            let feather = SKSpriteNode(texture: texture, size: CGSize(width: 18, height: 18))
            feather.zPosition = 30_001
            feather.alpha = 0
            layer.addChild(feather)
            let phase = CGFloat(index) / CGFloat(Feather.count) * 2 * .pi
            let spin = SKAction.customAction(withDuration: Feather.flight) { node, elapsed in
                let t = min(1, elapsed / flight)
                let s = backward ? 1 - t : t
                let p = 1 - s
                let angle = phase + p * 4.4 * .pi
                let radius = 34 - 14 * p
                node.position = CGPoint(x: center.x + cos(angle) * radius, y: center.y + 6 + p * 140 + sin(angle) * radius * 0.35)
                node.zRotation = angle
                node.alpha = min(1, s * 5, (1 - s) * 4)
            }
            let order = backward ? Feather.count - 1 - index : index
            feather.run(.sequence([.wait(forDuration: Double(order) * Feather.stagger), spin, .removeFromParent()]))
        }
    }

    /// Back from a battle or a window (`MapScene`): you can walk again, as whoever you've become.
    func resume() {
        openBorders = [:]
        for land in lands.values { land.stage.openGates() }
        isInputLocked = false
        lastUpdate = 0
        input.move = .zero
        refreshHero()
        refreshFollower()
        refreshAllies()
    }

    // MARK: Your party

    /// Keeps your party on the continent in step with who's in it (`WorldScene.refreshAllies`):
    /// friends at your side walk behind you, friends waiting for you stand at their spot (once their
    /// land's laid out), one who left stays about as an adventurer you can invite back.
    private func refreshAllies() {
        let members = session.partyMembers.filter { friend in friend.waitingAt.map { lands[$0.mapID] != nil } ?? true }
        guard members.map(\.id) != allies.map(\.id) || members.map(\.waitingAt) != allies.map(\.waiting)
                || members.map({ $0.petSpecies != nil }) != allies.map({ $0.pet != nil }) else { return }
        for ally in allies where !members.contains(where: { $0.id == ally.id }) {
            if let friend = session.friends.first(where: { $0.id == ally.id }), !session.isInParty(friend),
               let here, let stage = lands[here.id]?.stage, let crowd = stage.crowd {
                // Left the party but still a friend: they stay here, so you can invite them back.
                crowd.rejoin(friend, at: stage.local(ally.node.position), world: stage.world)
            } else {
                // Gone: unfriended, or off to wait for you somewhere else.
                SkillEffects.smoke(at: ally.node.position, in: layer)
            }
            ally.node.removeFromParent()
            ally.pet?.removeFromParent()
        }
        allies = members.enumerated().map { index, friend in
            if var existing = allies.first(where: { $0.id == friend.id }) {
                // Fainted beside you: off to their checkpoint, to wait for you there.
                if let spot = friend.waitingAt, spot != existing.waiting, let there = point(for: spot, index: index) {
                    SkillEffects.smoke(at: existing.node.position, in: layer)
                    move(existing, to: there)
                }
                existing.waiting = friend.waitingAt
                if existing.pet == nil, let pet = companionWalker(of: friend, beside: existing.node) {
                    SkillEffects.smoke(at: pet.position, in: layer)
                    existing.pet = pet
                }
                return existing
            }
            let node = Walker(cycle: art.walkCycle(session.artID(for: friend)), label: friend.name, labelColor: HUDStyle.partyGreen, badge: .bot)
            node.setWeapon(GameSession.weapon(for: friend))
            node.walkSpeed = 105
            node.tagMode = .whenStill
            if let spot = friend.waitingAt, let there = point(for: spot, index: index) {
                node.position = there
            } else {
                // Recruited here: they start where they stood.
                let beside = player.position + CGVector(dx: -40, dy: -10)
                var start = store.isWalkable(Self.cell(at: beside)) ? beside : player.position
                for land in lands.values {
                    guard let crowd = land.stage.crowd, let spot = crowd.position(of: friend.id) else { continue }
                    start = spot + land.shift
                    crowd.remove(friend.id, poof: false)
                    break
                }
                node.position = start
            }
            layer.addChild(node)
            return Ally(id: friend.id, node: node, pet: companionWalker(of: friend, beside: node), waiting: friend.waitingAt)
        }
    }

    /// A friend's companion, if they have one, set down at their side.
    private func companionWalker(of friend: Adventurer, beside node: Walker) -> Walker? {
        guard let species = friend.petSpecies.flatMap(session.content.monster) else { return nil }
        let walker = Walker(cycle: art.walkCycle(species.art), label: nil)
        walker.walkSpeed = 110
        walker.motion = IdleMotion.of(art: species.art)
        let side = node.position + CGVector(dx: 24, dy: 0)
        walker.position = store.isWalkable(Self.cell(at: side)) ? side : node.position
        layer.addChild(walker)
        walker.settle()
        return walker
    }

    /// Puts a friend, and their companion, somewhere else at once.
    private func move(_ ally: Ally, to point: CGPoint) {
        ally.node.position = point
        ally.node.setWalking(false)
        guard let pet = ally.pet else { return }
        let side = point + CGVector(dx: 24, dy: 0)
        pet.position = store.isWalkable(Self.cell(at: side)) ? side : point
        pet.setWalking(false)
    }

    /// Where a friend waiting for you stands on the continent (`WorldScene.point(for:index:)`): where
    /// they were left on their land (a step apart from the others there), or its checkpoint's spot,
    /// on ground they can stand on. None till that land's laid out.
    private func point(for spot: Spot, index: Int) -> CGPoint? {
        guard let land = lands[spot.mapID] else { return nil }
        let map = land.map
        var anchor = map.center(of: map.center)
        if let entry = spot.entry { anchor = map.center(of: map.entryCell(from: entry)) }
        if let position = spot.position, position.count == 2 { anchor = CGPoint(x: position[0], y: position[1]) }
        let apart = [CGVector(dx: -36, dy: 10), CGVector(dx: 36, dy: 10), CGVector(dx: -18, dy: -22), CGVector(dx: 18, dy: -22)]
        let wanted = anchor + apart[index % apart.count]
        var local = anchor
        if map.isWalkable(map.rawCell(at: wanted)) {
            local = wanted
        } else if let open = map.nearestWalkable(to: map.cell(at: wanted)) {
            local = map.center(of: open)
        }
        return local + land.shift
    }

    /// Friends waiting for you set off with you again once you reach them.
    private func rejoinWaitingFriends() {
        guard !isInputLocked else { return }
        for ally in allies where ally.waiting != nil && ally.node.position.distance(to: player.position) < rejoinRange {
            session.rejoin(ally.id)
            ally.node.say([L("There you are!"), L("Let's go!"), L("Back together!")].randomElement() ?? L("Let's go!"))
        }
    }

    /// Picks up a new look or name from the Character screen, the title you wear, a reborn hero's
    /// colour and what's in your hands (`WorldScene.refreshHero`).
    private func refreshHero() {
        let key = "\(session.data.hero.name)|\(session.heroLookKey)|\(session.data.title ?? "")|\(session.rebirths)"
        guard key != heroKey else { return }
        if heroKey != nil {
            player.setCycle(art.walkCycle(GameSession.heroArt))
            player.setLabel(session.data.hero.name)
        }
        player.setTitle(session.wornTitle)
        player.setLabelColor(WorldScene.nameColor(rebirths: session.rebirths))
        player.setWeapon(session.equipped(.weapon))
        heroKey = key
    }

    /// Keeps your companion in step: switched, renamed or recoloured; a fainted one out of sight
    /// till it's healed (`WorldScene.refreshFollower`).
    private func refreshFollower() {
        let pet = session.activePet.flatMap { $0.hp > 0 ? $0 : nil }
        let key = pet.map { "\($0.id)|\($0.name)" }
        guard key != followerKey else { return }
        followerKey = key
        let previous = follower?.position
        follower?.removeFromParent()
        follower = nil
        guard let pet else { return }
        let node = Walker(cycle: art.walkCycle(session.artID(for: pet)), label: pet.name)
        node.motion = IdleMotion.of(art: session.artID(for: pet))
        // Its name gives way to yours where the two would print over each other.
        node.tagMode = .whenClear
        let beside = player.position + CGVector(dx: -30, dy: 0)
        node.position = previous ?? (store.isWalkable(Self.cell(at: beside)) ? beside : player.position)
        node.walkSpeed = 110
        layer.addChild(node)
        follower = node
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

    /// Over how many seconds a land's song fades out as you walk into the next, and the next one's
    /// fades in (playtesting 2026-10-16: it cut straight over at the border).
    static let musicFade = 1.5

    /// You've walked into a land: its light on everyone, its music, and the game knows you're there
    /// (its checkpoint, the map you're on); and, new to you since you were last in it, its name at
    /// the top of the screen and in the chat (as `WorldScene.didMove` greets you).
    private func arrive(in def: MapDef) {
        let walkedIn = here != nil
        let before = here.flatMap { airs[$0.id] }
        here = def
        for land in lands.values { land.stage.isHere = land.def.id == def.id }
        // Its air: made the first time you're in it, and in full at once where you start.
        if airs[def.id] == nil, let stage = lands[def.id]?.stage {
            let air = Air(stage: stage, camera: cam, start: session.data.startedAt, screen: size)
            // The light and the weather's shade go on from where they were, toward this land's own.
            if let sky = air.sky, let previous = before?.sky { sky.carryOn(from: previous) }
            airs[def.id] = air
        }
        if !walkedIn { airs[def.id]?.set(mood: 1) }
        Walker.light = WorldScene.light(of: def)
        player.relight()
        // Walking in, the last land's song fades out and this one's in (`musicFade`).
        MusicPlayer.shared.play(def.music, fade: walkedIn ? Self.musicFade : 0)
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
    /// Debug launches (`demo`): a monster jumps out right here, as one does while you walk the wild.
    func encounterForDebug() {
        guard !isInputLocked, let encounters = here?.encounters else { return }
        stepsSinceBattle = 0
        startEncounter(encounters)
    }

    /// Debug launches (`invite=n`): the nearest friendly adventurers, brought over to stand by you.
    func summonAdventurersForDebug(_ count: Int) -> [Adventurer] {
        guard let here, let stage = lands[here.id]?.stage else { return [] }
        return stage.crowd?.summonForDebug(count, to: stage.local(player.position)) ?? []
    }

    /// Debug launches (`feather`): a Homeward Feather's lift without going anywhere, held part-way.
    func featherAwayForDebug() {
        featherAway {}
        run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.isPaused = true }]))
    }

    /// Debug launches (`say=<text>`): a speech bubble over you that stays.
    func sayForDebug(_ text: String) {
        player.say(text, for: 600)
    }

    /// Debug launches (`local=n`): the local you start beside tells you the first line of their story.
    func localTellsForDebug() {
        guard let here, let stage = lands[here.id]?.stage else { return }
        stage.crowd?.tellForDebug(near: stage.local(player.position))
    }

    /// Debug launches (`near=<land>,crossing`): walks you over the line into that land, to
    /// the nearest cell of it you can walk to with its own land all round it, and returns once
    /// you're in it (or after half a minute). `early` (`crossing,early`): onto it at once, in its
    /// plain ground before it's laid out (`World.walkable`), and waits there while it is.
    func walkIntoForDebug(_ id: String, early: Bool = false) async {
        // Once that land's laid out (it's near, so it's wanted), or a couple of minutes.
        let hurried = hurries
        hurries = true
        for _ in 0..<480 where lands[id] == nil && !early {
            try? await Task.sleep(for: .milliseconds(250))
        }
        hurries = hurried
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
        guard early else { return }
        hurries = true
        for _ in 0..<720 where here?.id != id {
            try? await Task.sleep(for: .milliseconds(250))
        }
        hurries = hurried
    }

    /// Debug launches: each land laid out and how long it took, by the frame counter
    /// (`showProgressForDebug`).
    private var builtForDebug: [String] = []
    private var progressForDebug: SKLabelNode?

    /// Debug launches: the lands laid out (and how long each took), the one being laid out, how many
    /// more are wanted and how many squares of hills and shore wait, at the foot of the screen.
    private func showProgressForDebug() {
        guard DebugLaunch.isActive, !DebugLaunch.hidesFrameCounter else { return }
        if progressForDebug == nil {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.fontSize = 10
            label.fontColor = .white
            label.verticalAlignmentMode = .bottom
            label.zPosition = 1_000_000
            cam.addChild(label)
            progressForDebug = label
        }
        progressForDebug?.position = CGPoint(x: 0, y: -size.height / 2 + 6)
        let built = builtForDebug.suffix(4).joined(separator: ", ")
        progressForDebug?.text = "built \(built) | building \(building ?? "-") | wanted \(wanted.count) | squares \(waiting.count)"
            + (isReady ? " | ready" : "") + (isSettled ? " | settled" : "")
    }
    #endif

    // MARK: Being put somewhere

    /// A land laid out already, to take instead of laying it out again.
    func adopt(_ map: WorldMap) {
        laidOut[map.def.id] = map
    }

    /// Puts you somewhere on the continent at once (a new game, out of a cave, a Homeward Feather,
    /// waking at your checkpoint): on `def`'s land at `arrival` (its own points), or just inside
    /// where its road from `entry` comes in, or in its middle, on ground you can stand on, as a land's
    /// own scene starts you (`WorldScene.init`). The chunks round there are drawn afresh; `isReady`
    /// once they are, and you're in that land.
    func place(on def: MapDef, entry: Edge?, arrival: CGPoint?) async {
        guard store.land(def.id) != nil else { return }
        isReady = false
        // Nothing round where you were is wanted now (`lookAround` waits): this land comes first,
        // and the world map's layouts wait for it (`buildWanted`).
        placed = false
        WorldOverview.shared.isHeld = true
        here = nil
        lastCell = nil
        wanted = [def.id: -1]
        buildWanted()
        while lands[def.id] == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let land = lands[def.id] else { return }
        let map = land.map
        var local = map.center(of: map.center)
        if let arrival {
            local = arrival
        } else if let entry {
            local = map.center(of: map.entryCell(from: entry))
        }
        if !map.isWalkable(map.rawCell(at: local)), let open = map.nearestWalkable(to: map.cell(at: local), within: 48) {
            local = map.center(of: open)
        }
        move(to: local + land.shift)
        placed = true
        lookAround()
    }

    /// You, your companion and the friends walking with you, somewhere else at once, the camera with
    /// you.
    private func move(to point: CGPoint) {
        player.path = []
        talkTarget = nil
        player.position = point
        player.zPosition = -point.y
        follower?.position = point + CGVector(dx: -30, dy: 0)
        for ally in allies where ally.waiting == nil { move(ally, to: point + CGVector(dx: -40, dy: -10)) }
        cam.position = point
        lastUpdate = 0
    }

    /// The HUD's minimap of the land you're in, with what's round it, as its own scene draws it
    /// (`WorldScene.minimapPicture`): the lands nearby as their own minimaps show them
    /// (`WorldOverview`; till one's drawn, its shape in its ground's colour) and the sea between.
    /// None till you're in a land. `overviews`: how many lands `WorldOverview` has drawn, so it's
    /// drawn again as more come in.
    func minimapPicture(overviews: Int) -> WorldScene.MinimapPicture? {
        guard let def = here, let land = lands[def.id] else { return nil }
        if let surrounded, surrounded.land == def.id, surrounded.overviews == overviews { return surrounded.picture }
        let margin = 40
        let columns = def.width + margin * 2, rows = def.height + margin * 2
        let own = land.overview
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        let sea = WorldMap.seaColor
        context.setFillColor(red: CGFloat(sea.r) / 255, green: CGFloat(sea.g) / 255, blue: CGFloat(sea.b) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        let drawn = WorldOverview.shared.images
        // Lands not drawn yet in their ground's colour, till the continent lays them out and hands
        // their pictures over (`Land.overview`), and the minimap's drawn again. Not laid out for the
        // world map meanwhile: one layout at a time (`MapLayouts`), and the land you walk into
        // waited behind them.
        for (other, offset) in Continent.lands(near: def, within: margin) {
            let frame = CGRect(x: offset.col + margin, y: offset.row + margin, width: other.width, height: other.height)
            if let image = drawn[other.id] {
                context.draw(image, in: frame)
                continue
            }
            let (red, green, blue) = WorldScene.groundColor(of: other, art: art)
            let color = PixelColor(r: UInt8(red * 255), g: UInt8(green * 255), b: UInt8(blue * 255))
            if let shape = WorldScene.silhouette(of: other, color: color) { context.draw(shape, in: frame) }
        }
        context.draw(own, in: CGRect(x: margin, y: margin, width: def.width, height: def.height))
        guard let made = context.makeImage() else { return nil }
        let picture = WorldScene.MinimapPicture(image: UIImage(cgImage: made), origin: GridPoint(col: -margin, row: -margin),
                                                columns: columns, rows: rows)
        surrounded = (def.id, overviews, picture)
        return picture
    }

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

    /// While the land you stand on isn't laid out yet (`id`), a note above you with its name and how
    /// far its build has come, so its plain ground reads as on its way; gone once it's in.
    private func showLoading(_ id: String?) {
        guard let id, let def = Content.shared.map(id) else {
            loadingNote?.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            loadingNote = nil
            return
        }
        // Waiting its turn, 0; laying out (off the main thread), 5; laid out, 40; then by its steps.
        let done = progress[id] ?? (laidOut[id] != nil ? 0.4 : layingOut?.id == id ? 0.05 : 0)
        let percent = Int((done * 100).rounded())
        let text = L("Loading {land}… {percent}%", ["land": def.name, "percent": percent])
        if let note = loadingNote {
            note.setText(text)
        } else {
            let note = NameTag(text, color: .white, size: 14)
            note.zPosition = 45_000
            note.alpha = 0
            cam.addChild(note)
            note.run(.fadeIn(withDuration: 0.4))
            loadingNote = note
        }
        loadingNote?.position = CGPoint(x: 0, y: min(120, size.height / 2 - 70))
    }

    // MARK: Chunks

    /// Draws the chunks round the camera that aren't yet (the lands in them not laid out yet in
    /// their plain ground, till they are), lays out those lands, nearest first, and lets go of
    /// the chunks far off.
    private func lookAround() {
        guard placed else { return }
        let you = Self.cell(at: cam.position)
        let middle = World.chunk(of: you)
        var near: [String: Int] = [:]
        for dr in -Self.reach...Self.reach {
            for dc in -Self.reach...Self.reach {
                let chunk = GridPoint(col: middle.col + dc, row: middle.row + dr)
                if chunks[chunk] == nil {
                    draw(chunk)
                } else if max(abs(dc), abs(dr)) <= 1, stale.contains(chunk), let drawn = chunks[chunk] {
                    stale.remove(chunk)
                    redraw(drawn, at: chunk)
                }
                // How far off each land not laid out yet is: to the box round its cells here.
                for (id, box) in boxes(in: chunk) where lands[id] == nil {
                    let gap = max(box.low.col - you.col, you.col - box.high.col, box.low.row - you.row, you.row - box.high.row, 0)
                    near[id] = min(near[id] ?? .max, gap)
                }
            }
        }
        // The land you stand in before any, its layout begun at once, even while another's built.
        let standing = store.land(at: you)?.id
        if let standing, lands[standing] == nil {
            near[standing] = -1
            layOutAhead(standing)
        }
        wanted = near
        isUrgent = (near.values.min() ?? .max) <= Self.urgentReach
        standsOnUnbuilt = standing.map { lands[$0] == nil } ?? false
        buildWanted()
        showLoading(standsOnUnbuilt ? standing : nil)
        // Ready once the land you're in is drawn round you, with its hills and shore on screen.
        if !isReady, standing.map({ lands[$0] != nil }) ?? true,
           !waiting.contains(where: { distance(of: $0, from: you) <= Self.screenReach }) {
            isReady = true
        }
        #if DEBUG
        showProgressForDebug()
        #endif
        refreshHero()
        refreshFollower()
        rejoinWaitingFriends()
        refreshAllies()
        // The minimap's people and their jobs, in the land you're in.
        if let here, let stage = lands[here.id]?.stage {
            let party = allies.map { GameSession.MinimapDot(cell: stage.map.cell(at: stage.local($0.node.position)), kind: .party) }
            let dots = stage.minimapDots(friends: Set(session.friends.map(\.id))) + party
            if session.minimapDots != dots { session.minimapDots = dots }
            let marks = stage.minimapMarks()
            if session.minimapMarks != marks { session.minimapMarks = marks }
        }
        // The lands' people: their quest marks, townsfolk watching you pass, and who's near enough to
        // talk to (the HUD's Talk button); and the adventurers about you in the land you're in.
        var nearest: (land: String, npc: NPCDef, distance: CGFloat)?
        for land in nearLands.compactMap({ lands[$0] }) {
            guard let near = land.stage.updateNotices(player: player.position, reach: talkRange + 12),
                  near.distance < (nearest?.distance ?? .infinity) else { continue }
            nearest = (land.def.id, near.npc, near.distance)
        }
        nearbyTalk = nearest.map { ($0.land, $0.npc.id) }
        if session.nearbyNPC != nearest?.npc.id { session.nearbyNPC = nearest?.npc.id }
        if let here, let stage = lands[here.id]?.stage, let crowd = stage.crowd {
            let you = stage.local(player.position)
            let nearby = crowd.adventurer(near: you, within: 80)
            if session.nearbyAdventurer?.id != nearby?.id { session.nearbyAdventurer = nearby }
            let around = crowd.adventurers(near: you, within: 320)
            if session.adventurersAround != around { session.adventurersAround = around }
        }
        for chunk in chunks.keys where max(abs(chunk.col - middle.col), abs(chunk.row - middle.row)) > Self.keep {
            if let gone = chunks.removeValue(forKey: chunk) {
                gone.ground.removeFromParent()
                gone.sea.removeFromParent()
                gone.things.removeFromParent()
                gone.banks.forEach { $0.removeFromParent() }
                waiting.removeAll { $0.chunk == chunk }
                stale.remove(chunk)
            }
        }
        // Only the lands round you go about their lives; those far off wait, out of sight.
        nearLands = Set(chunks.keys.flatMap { owners(of: $0) })
        for (id, land) in lands where land.stage.world.isHidden == nearLands.contains(id) {
            land.stage.world.isHidden = !nearLands.contains(id)
            land.stage.world.isPaused = !nearLands.contains(id)
        }
    }

    /// The lands owning any cell of a chunk.
    private func owners(of chunk: GridPoint) -> Set<String> {
        Set(boxes(in: chunk).keys)
    }

    /// The lands owning any cell of a chunk, each with the box round its cells there (south-west
    /// and north-east cells).
    private func boxes(in chunk: GridPoint) -> [String: (low: GridPoint, high: GridPoint)] {
        if let known = owned[chunk] { return known }
        var found: [String: (low: GridPoint, high: GridPoint)] = [:]
        for cell in World.cells(in: chunk) {
            guard let id = store.land(at: cell)?.id else { continue }
            if let box = found[id] {
                found[id] = (low: GridPoint(col: min(box.low.col, cell.col), row: min(box.low.row, cell.row)),
                             high: GridPoint(col: max(box.high.col, cell.col), row: max(box.high.row, cell.row)))
            } else {
                found[id] = (low: cell, high: cell)
            }
        }
        owned[chunk] = found
        return found
    }

    /// Lays out the lands wanted one at a time, nearest first, so the land you're in comes in before
    /// those round it rather than with them all; the world map's own work waits meanwhile
    /// (`WorldOverview.isHeld`), as it lays out lands the same way.
    private func buildWanted() {
        guard building == nil else { return }
        let next = wanted.filter { lands[$0.key] == nil }.min { ($0.value, $0.key) < ($1.value, $1.key) }?.key
        // Held while there's one to lay out; let go once there's none, unless you're being put
        // somewhere (`place`), where those round you come next.
        if next != nil {
            WorldOverview.shared.isHeld = true
        } else if placed {
            WorldOverview.shared.isHeld = false
        }
        guard let next else { return }
        wanted[next] = nil
        building = next
        Task { [weak self] in
            guard let self else {
                WorldOverview.shared.isHeld = false
                return
            }
            await build(next)
            building = nil
            buildWanted()
        }
    }

    /// Lays a land out off the main thread, then plans its scenery, takes it into the store and makes
    /// its hills and shore ready to draw; then shows its ground and draws its squares in the chunks
    /// already drawn, and hands its picture to the world map.
    private func build(_ id: String) async {
        guard lands[id] == nil, let def = Content.shared.map(id), let place = store.land(id) else { return }
        #if DEBUG
        let began = Date()
        #endif
        progress[id] = 0.05
        let map: WorldMap
        if let ready = laidOut.removeValue(forKey: id) {
            map = ready
        } else if let ahead = layingOut, ahead.id == id {
            layingOut = nil
            map = await ahead.task.value
        } else {
            // One laid out ahead that isn't wanted first after all is kept for when it is.
            if let ahead = layingOut {
                layingOut = nil
                setAside(ahead)
            }
            map = await GameCoordinator.layOut(def)
        }
        progress[id] = 0.45
        layOutNext(after: id)
        let rest = pause(for: def)
        art.use(palette: def.theme.palette, for: def.id)
        let planner = LandPlanner(def: def, map: map, art: art)
        await planner.planUpToLocals(pause: rest)
        progress[id] = 0.55
        await planner.planTheRest(pause: rest)
        progress[id] = 0.65
        let tiles = GroundTiles(map: map, art: art)
        let painters = await ranges(of: map, tiles: tiles, place: place, pause: rest)
        progress[id] = 0.8
        let stage = LandStage(def: def, map: map, plan: planner.plan, tiles: tiles, art: art, session: session, shift: Self.shift(of: place))
        await stage.build(pause: rest)
        progress[id] = nil
        // Its adventurers spoiling for a fight dare you only in the land you're in.
        stage.crowd?.onChallenge = { [weak self, weak stage] rival in
            guard let self, stage?.isHere == true, !self.isInputLocked else { return }
            self.startDuel(with: rival)
        }
        layer.addChild(stage.world)
        let land = Land(def: def, place: place, map: map, tiles: tiles, painters: painters, stage: stage)
        // Walked on as it's laid out from now, not as its shape has it (`World.walkable`): as its
        // scenery shows, not before, or you'd walk into trees you can't see yet.
        store.add(map)
        lands[id] = land
        #if DEBUG
        builtForDebug.append("\(id) \(Int(Date().timeIntervalSince(began)))s")
        #endif
        // Its ground in the chunks drawn already; while a battle or a cave is up, once you're back
        // (`didMove`): playtesting saw a chunk's ground made during a fight never show.
        if view != nil {
            for (key, chunk) in chunks where owners(of: key).contains(id) { show(land, in: chunk, at: key) }
        } else {
            unshown.insert(id)
        }
        // Don't stand on top of scenery, or out at sea (an old save): onto the nearest ground. A way
        // you were walking over it before it was laid out goes round what's there now.
        let standing = Self.cell(at: player.position)
        if store.land(at: standing)?.id == id, !store.isWalkable(standing), let open = store.nearestWalkable(to: standing, within: 48) {
            move(to: Self.center(of: open))
        } else if let end = player.path.last, player.path.contains(where: { !store.isWalkable(Self.cell(at: $0)) }) {
            walk(to: end, marked: false)
        }
        // Standing on it already (walked onto it in its plain ground), you're in it now, not only once
        // you take a step (`checkCell`).
        if here != nil, !isInputLocked { checkLand(at: Self.cell(at: player.position)) }
        for chunk in chunks.keys { paintSquares(of: land, in: chunk) }
        // Its minimap for the world map (`WorldOverview`), so that needn't lay it out again.
        await rest()
        _ = land.overview
    }

    /// Starts laying out the nearest land wanted after `id` (`wanted`), off the main thread, while
    /// `id`'s is planned and drawn on it.
    private func layOutNext(after id: String) {
        guard layingOut == nil,
              let next = wanted.filter({ $0.key != id && lands[$0.key] == nil && laidOut[$0.key] == nil })
                  .min(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key,
              let def = Content.shared.map(next) else { return }
        layingOut = (next, Task { await GameCoordinator.layOut(def) })
    }

    /// Starts laying out `id` off the main thread now, unless it's built, being built, or laid out
    /// or under way already: the land under your feet, without waiting for the one being built.
    /// One laid out ahead for another land is kept for when that's wanted.
    private func layOutAhead(_ id: String) {
        guard lands[id] == nil, building != id, laidOut[id] == nil, layingOut?.id != id,
              let def = Content.shared.map(id) else { return }
        if let ahead = layingOut { setAside(ahead) }
        layingOut = (id, Task { await GameCoordinator.layOut(def) })
    }

    /// Keeps a land's layout under way for when it's wanted (`laidOut`), unless it's been built or
    /// is being built by then.
    private func setAside(_ ahead: (id: String, task: Task<WorldMap, Never>)) {
        Task { [weak self] in
            let map = await ahead.task.value
            guard let self, lands[ahead.id] == nil, building != ahead.id else { return }
            laidOut[ahead.id] = map
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

    /// Gives the frame back once work's had it for a few milliseconds. Behind the loading card,
    /// before the land you start in is drawn round you, only every 120 (as a land's own scene did,
    /// `WorldScene.sliceLength`): the card still turns with the phone, and the work isn't held up
    /// by a pause every few milliseconds (each a good deal longer than asked on a busy phone). And
    /// so too while a debug launch `hurries`. While a land not laid out yet is near you (`isUrgent`),
    /// every 16: a frame or two dropped while it comes in faster; and while you stand on one, every
    /// 40, the frames slower for a few seconds but the land in sooner.
    private func breathe() async {
        let slice: Duration = !isReady || hurries ? .milliseconds(120)
            : standsOnUnbuilt ? .milliseconds(40) : isUrgent ? .milliseconds(16) : .milliseconds(6)
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
    /// background: each lifts itself and is sorted among what stands there (`HillArt`). Then its
    /// bank along the sea there (`drawBank`), its tiles made by then for the shore's squares.
    private func paintSquares(of land: Land, in chunk: GridPoint) {
        for square in land.squares[chunk] ?? [] { waiting.append((chunk, land.def.id, square.painter, square.corner)) }
        if land.coastal, owners(of: chunk).contains(land.def.id) { waiting.append((chunk, land.def.id, Self.bankJob, chunk)) }
        guard !painting, !waiting.isEmpty else { return }
        painting = true
        Task { [weak self] in await self?.paintWaiting() }
    }

    private func paintWaiting() async {
        // Not while a battle or a cave is up: their tile maps wouldn't show (`didMove` goes on).
        while !waiting.isEmpty, view != nil {
            let you = Self.cell(at: cam.position)
            guard let next = waiting.indices.min(by: { distance(of: waiting[$0], from: you) < distance(of: waiting[$1], from: you) })
            else { break }
            let job = waiting.remove(at: next)
            guard let drawn = chunks[job.chunk], let land = lands[job.land] else { continue }
            if job.painter == Self.bankJob {
                drawBank(of: land, in: drawn, at: job.chunk)
                await breathe()
                continue
            }
            let things = drawn.things
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

    /// How many cells out from you the screen shows (about 17 on a phone, either way up), with room
    /// for a mountain rising into it from further down: the loading card waits for the hills and
    /// shore within it (`lookAround`).
    private static let screenReach = 28

    /// How far a square waiting to be drawn (`HillArt.square` cells a side), or a chunk's bank,
    /// lies from `cell`, in cells: none if it covers it.
    private func distance(of job: (chunk: GridPoint, land: String, painter: Int, corner: GridPoint), from cell: GridPoint) -> Int {
        let low: GridPoint, side: Int
        if job.painter == Self.bankJob {
            low = GridPoint(col: job.chunk.col * World.chunkSize, row: job.chunk.row * World.chunkSize)
            side = World.chunkSize
        } else if let origin = lands[job.land]?.place.origin {
            low = GridPoint(col: origin.col + job.corner.col, row: origin.row + job.corner.row)
            side = HillArt.square
        } else {
            return .max
        }
        let across = max(low.col - cell.col, 0, cell.col - (low.col + side - 1))
        let up = max(low.row - cell.row, 0, cell.row - (low.row + side - 1))
        return max(across, up)
    }

    /// Draws a chunk: each land's cells in it with that land's tiles (in its plain ground till
    /// it's laid out); the sea where no land is; and (in the background) its squares of hills and
    /// shore. What the lands set down on it is theirs to show (`LandStage.show`).
    private func draw(_ chunk: GridPoint) {
        let waters = sea(of: chunk)
        seaGrid.addChild(waters)
        let drawn = Chunk(sea: waters)
        groundGrid.addChild(drawn.ground)
        layer.addChild(drawn.things)
        chunks[chunk] = drawn
        drawGround(of: drawn, at: chunk)
        for land in lands.values { paintSquares(of: land, in: chunk) }
    }

    /// A chunk's sea: the sea's tiles under every cell of it (under the land's cut edge along the
    /// coast too, so the sea shows through it), with its shallows along the coast.
    private func sea(of chunk: GridPoint) -> SKTileMapNode {
        let size = World.chunkSize, tile = WorldMap.tileSize
        let origin = GridPoint(col: chunk.col * size, row: chunk.row * size)
        let waters = SKTileMapNode(tileSet: seaTiles, columns: size, rows: size, tileSize: CGSize(width: tile, height: tile))
        waters.anchorPoint = .zero
        for cell in World.cells(in: chunk) {
            waters.setTileGroup(seaGroup(at: cell), forColumn: cell.col - origin.col, row: cell.row - origin.row)
        }
        waters.position = CGPoint(x: CGFloat(origin.col) * tile, y: CGFloat(origin.row) * tile)
        if let shallows = shallows(in: chunk) { waters.addChild(shallows) }
        return waters
    }

    /// A chunk's tile maps made afresh, its ground, sea and banks along the coast, as the continent's
    /// back on screen after a battle or a cave (`didMove`, and `stale` as you come near): playtesting
    /// saw a chunk's tile maps stop showing after a fight, its ground (0.7.2) and then its sea (0.7.4,
    /// the scene's background showing through, to the chunk's edge). New ones always show.
    private func redraw(_ drawn: Chunk, at chunk: GridPoint) {
        drawGround(of: drawn, at: chunk)
        drawn.sea.removeFromParent()
        drawn.sea = sea(of: chunk)
        seaGrid.addChild(drawn.sea)
        drawn.banks.forEach { $0.removeFromParent() }
        drawn.banks = []
        for id in owners(of: chunk).sorted() {
            // Those still waiting to be drawn are drawn in their turn (`paintWaiting`).
            guard let land = lands[id], land.coastal,
                  !waiting.contains(where: { $0.chunk == chunk && $0.land == id && $0.painter == Self.bankJob }) else { continue }
            drawBank(of: land, in: drawn, at: chunk)
        }
    }

    /// The sea's tile for a world cell: the one at its place in the sea's picture (`seaGroups`).
    private func seaGroup(at cell: GridPoint) -> SKTileGroup {
        let col = ((cell.col % seaCells) + seaCells) % seaCells, row = ((cell.row % seaCells) + seaCells) % seaCells
        return seaGroups[row * seaCells + col]
    }

    /// The sea paler along the coast, in bands out from the land (`shallowTiles`): the water shallow
    /// where the land runs down into it, palest at the waterline, under the cut edge of the land's
    /// cells along it too. None in a chunk all land or all sea.
    private func shallows(in chunk: GridPoint) -> SKTileMapNode? {
        let size = World.chunkSize, tile = WorldMap.tileSize
        let reach = Self.shallowTiles.count - 1
        // Which cells are land, over the chunk and `reach` round it.
        let low = GridPoint(col: chunk.col * size - reach, row: chunk.row * size - reach), side = size + 2 * reach
        var land = [Bool](repeating: false, count: side * side)
        for row in 0..<side {
            for col in 0..<side { land[row * side + col] = store.land(at: GridPoint(col: low.col + col, row: low.row + row)) != nil }
        }
        guard land.contains(true), land.contains(false) else { return nil }
        let map = SKTileMapNode(tileSet: SKTileSet(tileGroups: Self.shallowTiles), columns: size, rows: size,
                                tileSize: CGSize(width: tile, height: tile))
        map.anchorPoint = .zero
        map.zPosition = 1
        var any = false
        for row in 0..<size {
            for col in 0..<size {
                let isLand = land[(row + reach) * side + col + reach]
                // How far it lies out from the land, in cells (0: the land's own cell, at the waterline).
                var nearest = Double(reach) + 1
                for dr in -reach...reach {
                    for dc in -reach...reach where (dc != 0 || dr != 0) && land[(row + reach + dr) * side + col + reach + dc] != isLand {
                        nearest = min(nearest, Double(dc * dc + dr * dr).squareRoot())
                    }
                }
                let band: Int? = isLand ? (nearest < 1.5 ? 0 : nil) : Int(nearest.rounded(.up))
                guard let band, band <= reach else { continue }
                map.setTileGroup(Self.shallowTiles[band], forColumn: col, row: row)
                any = true
            }
        }
        return any ? map : nil
    }

    /// The shallows' bands, palest first: a pale sea green over the water, less of it each cell out.
    private static let shallowTiles: [SKTileGroup] = [0.42, 0.3, 0.18, 0.08].map { alpha in
        let color = UIColor(red: 0.8, green: 0.96, blue: 0.95, alpha: alpha)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let size = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        return SKTileGroup(tileDefinition: SKTileDefinition(texture: SKTexture(image: image), size: size))
    }

    /// A chunk's ground, made afresh: each land's cells in it with that land's tiles, or in its plain
    /// ground till it's laid out. Each time the continent's back on screen after a battle or a cave,
    /// round you (`didMove`): playtesting saw a chunk's ground gone after a fight, the sea showing
    /// through under its scenery while the sea's own tile maps still showed; new ones always do.
    private func drawGround(of drawn: Chunk, at chunk: GridPoint) {
        drawn.ground.removeAllChildren()
        drawn.placeholders = [:]
        for id in owners(of: chunk).sorted() {
            if let land = lands[id] {
                show(land, in: drawn, at: chunk)
            } else {
                placehold(id, in: drawn, at: chunk)
            }
        }
    }

    /// A land's cells in a chunk drawn, with its tiles graded with its palette, in place of its plain
    /// ground. Its shore's drawn sunk, with its hills, and its bank along the sea after
    /// them (`paintSquares`).
    private func show(_ land: Land, in drawn: Chunk, at chunk: GridPoint) {
        drawn.placeholders.removeValue(forKey: land.def.id)?.removeFromParent()
        let size = World.chunkSize, tile = WorldMap.tileSize
        let origin = GridPoint(col: chunk.col * size, row: chunk.row * size)
        art.use(palette: land.def.theme.palette, for: land.def.id)
        var picks: [(col: Int, row: Int, group: SKTileGroup)] = []
        var groups: [ObjectIdentifier: SKTileGroup] = [:]
        for cell in World.cells(in: chunk) where store.land(at: cell)?.id == land.def.id {
            let local = store.local(cell, in: land.place)
            guard !land.sunk.contains(local), let group = land.tiles.pick(local).group else { continue }
            picks.append((cell.col - origin.col, cell.row - origin.row, group))
            groups[ObjectIdentifier(group)] = group
        }
        guard !picks.isEmpty else { return }
        let ground = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: size, rows: size,
                                   tileSize: CGSize(width: tile, height: tile))
        ground.anchorPoint = .zero
        // At the chunk's corner itself, as the sea's are.
        ground.position = CGPoint(x: CGFloat(origin.col) * tile, y: CGFloat(origin.row) * tile)
        for pick in picks { ground.setTileGroup(pick.group, forColumn: pick.col, row: pick.row) }
        drawn.ground.addChild(ground)
    }

    /// The bank of earth along a land's edge over the sea in a chunk, as its own scene draws it
    /// (`WorldScene.bank`): its cells within two of the sea, with the tiles they show (cut along
    /// it), drawn again a little lower each time, in layers of soil darkening toward the water, and
    /// a line of foam at its foot. Under the land, so it shows only where its edge faces you. Where
    /// the land slopes down to the sea (`WorldMap.shore`), only the foam, at the water's edge.
    private func drawBank(of land: Land, in drawn: Chunk, at chunk: GridPoint) {
        let size = World.chunkSize, tile = WorldMap.tileSize, steps = Self.bankSteps
        let origin = GridPoint(col: chunk.col * size, row: chunk.row * size)
        art.use(palette: land.def.theme.palette, for: land.def.id)
        var cells: [(col: Int, row: Int, group: SKTileGroup)] = []
        var groups: [ObjectIdentifier: SKTileGroup] = [:]
        for cell in World.cells(in: chunk) where store.land(at: cell)?.id == land.def.id {
            let pick = land.tiles.pick(store.local(cell, in: land.place))
            guard pick.nearSea, let group = pick.group else { continue }
            cells.append((cell.col - origin.col, cell.row - origin.row, group))
            groups[ObjectIdentifier(group)] = group
        }
        guard !cells.isEmpty else { return }
        let tiles = SKTileSet(tileGroups: Array(groups.values))
        let soil = (r: CGFloat(0.43), g: CGFloat(0.32), b: CGFloat(0.22))
        // The land's own ground colour leans the soil its way (sandy under sand, grey under scree).
        let ground = WorldScene.groundColor(of: land.def, art: art)
        let top = (r: soil.r * 0.6 + ground.0 * 0.3, g: soil.g * 0.6 + ground.1 * 0.3, b: soil.b * 0.6 + ground.2 * 0.3)
        for step in (land.map.shore != nil ? steps : 0)...steps {
            let foam = step == steps
            let shade = 1 - 0.45 * CGFloat(step) / CGFloat(steps - 1)
            let outline = SKTileMapNode(tileSet: tiles, columns: size, rows: size, tileSize: CGSize(width: tile, height: tile))
            outline.anchorPoint = .zero
            outline.position = CGPoint(x: CGFloat(origin.col) * tile, y: CGFloat(origin.row) * tile)
            for cell in cells { outline.setTileGroup(cell.group, forColumn: cell.col, row: cell.row) }
            outline.color = foam ? .white : UIColor(red: top.r * shade, green: top.g * shade, blue: top.b * shade, alpha: 1)
            outline.colorBlendFactor = 1
            outline.alpha = foam ? 0.5 : 1
            bankGrids[step].addChild(outline)
            drawn.banks.append(outline)
        }
    }

    /// A land's cells in a chunk in its own plain ground, graded as it is there, till it's laid out
    /// (`show`) with its roads, patches and all: no sea where it'll be. Its rivers and lakes are left
    /// out, the sea's water showing there, as you can't walk on them (`World.isWalkable`).
    private func placehold(_ id: String, in drawn: Chunk, at chunk: GridPoint) {
        guard let def = Content.shared.map(id) else { return }
        let size = World.chunkSize, tile = WorldMap.tileSize
        let origin = GridPoint(col: chunk.col * size, row: chunk.row * size)
        let tileSize = CGSize(width: tile, height: tile)
        let group: SKTileGroup
        if let known = placeholderTiles[id] {
            group = known
        } else {
            let texture: SKTexture
            if let image = art.gradedTile(def.theme.ground, palette: def.theme.palette) {
                texture = SKTexture(cgImage: image)
                texture.filteringMode = .nearest
            } else {
                // Or its ground's colour.
                let (red, green, blue) = WorldScene.groundColor(of: def, art: art)
                let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
                texture = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                    color.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
                })
            }
            group = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture, size: tileSize))
            placeholderTiles[id] = group
        }
        // Its roads too, so one coming over the border runs on rather than stopping at the line.
        let road = placeholderRoadTile(def)
        let roads: Set<GridPoint> = road == nil ? [] : placeholderRoads(def)
        let flat = SKTileMapNode(tileSet: SKTileSet(tileGroups: [group] + (road.map { [$0] } ?? [])), columns: size, rows: size, tileSize: tileSize)
        flat.anchorPoint = .zero
        flat.position = CGPoint(x: CGFloat(origin.col) * tile, y: CGFloat(origin.row) * tile)
        var any = false
        for cell in World.cells(in: chunk) where store.land(at: cell)?.id == id && store.isWalkable(cell) {
            let pick = roads.contains(cell) ? (road ?? group) : group
            flat.setTileGroup(pick, forColumn: cell.col - origin.col, row: cell.row - origin.row)
            any = true
        }
        guard any else { return }
        drawn.ground.addChild(flat)
        drawn.placeholders[id] = flat
    }

    /// A land's road tile, graded with its palette, for its placeholder (`placehold`).
    private func placeholderRoadTile(_ def: MapDef) -> SKTileGroup? {
        if let known = placeholderRoadTiles[def.id] { return known }
        guard let image = art.gradedTile(def.theme.path, palette: def.theme.palette) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        let group = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture, size: CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)))
        placeholderRoadTiles[def.id] = group
        return group
    }

    /// A land's roads before it's laid out (`placehold`), in world cells: straight from its hub
    /// through the turns the painting found (`Region.Road`) to where each crosses its border (into
    /// a cave, up to its mouth), two cells wide. A road ran on over the border and stopped at the
    /// line while the land past it was still being laid out (playtesting 2026-10-16); its last
    /// stretch runs straight at the border as its own layout's does (`WorldMap.carveRoad`), so the
    /// two meet, and its layout, winding the rest a little, takes its place.
    private func placeholderRoads(_ def: MapDef) -> Set<GridPoint> {
        if let known = placeholderRoadCells[def.id] { return known }
        let cells: Set<GridPoint> = store.land(def.id).map { Self.placeholderRoads(of: def, origin: $0.origin) } ?? []
        placeholderRoadCells[def.id] = cells
        return cells
    }

    /// `placeholderRoads` worked out, its box starting at the world cell `origin`.
    static func placeholderRoads(of def: MapDef, origin: GridPoint) -> Set<GridPoint> {
        var cells: Set<GridPoint> = []
        if let region = Content.shared.regions[def.id] {
            func point(_ pair: [Int]) -> CGPoint {
                CGPoint(x: CGFloat(region.middle.col + (pair.first ?? 0)) + 0.5, y: CGFloat(region.middle.row + (pair.count > 1 ? pair[1] : 0)) + 0.5)
            }
            for exit in def.exits {
                guard let road = region.roads[exit.to] else { continue }
                let way = road.into ?? exit.edge
                let out: CGVector = switch way {
                case .east: CGVector(dx: 1, dy: 0)
                case .west: CGVector(dx: -1, dy: 0)
                case .north: CGVector(dx: 0, dy: 1)
                case .south: CGVector(dx: 0, dy: -1)
                }
                let end = CGPoint(x: CGFloat(road.at.col) + 0.5, y: CGFloat(road.at.row) + 0.5)
                let straight = CGFloat(road.into == nil ? 5 : WorldMap.gateApproach)
                let stops = [point(def.hub ?? [0, 0])] + road.via.map(point)
                    + [CGPoint(x: end.x - out.dx * straight, y: end.y - out.dy * straight), CGPoint(x: end.x + out.dx * 0.5, y: end.y + out.dy * 0.5)]
                for (a, b) in zip(stops, stops.dropFirst()) {
                    let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) * 3))
                    for step in 0...steps {
                        let t = CGFloat(step) / CGFloat(steps)
                        let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                        for dr in -2...2 {
                            for dc in -2...2 {
                                let col = Int(x.rounded(.down)) + dc, row = Int(y.rounded(.down)) + dr
                                let dx = CGFloat(col) + 0.5 - x, dy = CGFloat(row) + 0.5 - y
                                if dx * dx + dy * dy <= 1.1 * 1.1 { cells.insert(GridPoint(col: col + origin.col, row: row + origin.row)) }
                            }
                        }
                    }
                }
            }
        }
        return cells
    }
}
