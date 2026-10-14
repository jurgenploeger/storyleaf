import SpriteKit

/// Joystick input shared between the SwiftUI HUD and the scene (read every frame).
final class InputState {
    /// -1...1 on each axis, y up.
    var move: CGVector = .zero
}

/// A land's own layer of the scene (`WorldScene.world`). It knows its land, so whoever stands on
/// it finds the ground's height there (`Walker.settle`), even shown past another land's border.
final class LandNode: SKNode {
    weak var land: WorldScene?
}

/// One map: ground, scenery, NPCs, passers-by, the hero and their companion.
///
/// Like Fairyland, monsters aren't shown on the map — walking through the wild can start
/// a random battle. The lands lie side by side on one continent (`Continent`): the lands next
/// door show past the borders (built in the background as you near them, `show(_:as:)`), and you
/// walk across into them where a road joins them, with no loading card (`onCross`). Caves you
/// enter through their mouths, behind the card.
final class WorldScene: SKScene {
    var onEncounter: (@MainActor (MapDef.Encounters, SKTexture?) -> Void)?
    var onTalk: (@MainActor (NPCDef) -> Void)?
    var onTravel: (@MainActor (MapDef.Exit) -> Void)?
    var onFirstFrame: (@MainActor () -> Void)?
    /// A duel with another adventurer is starting (you challenged them, or they picked a fight).
    var onDuel: (@MainActor (Adventurer, SKTexture?) -> Void)?
    /// Someone was tapped: an adventurer, a friend in your party (or their companion), or your companion.
    var onInspect: (@MainActor (Profile) -> Void)?
    /// Set while menus, dialogs or transitions are up.
    var isInputLocked = false
    /// No monster jumps out while set (debug `demo`, which picks its own moment).
    var holdsEncounters = false

    let def: MapDef
    private let session: GameSession
    private let input: InputState
    private let art = ArtLibrary.shared
    private let map: WorldMap
    private var rng: SeededRandom
    private let world = LandNode()
    /// This land's layer and those of the lands next door shown past its borders (`show(_:as:)`).
    private let lands = SKNode()
    private let cam = SKCameraNode()
    private let player: Walker
    private var follower: Walker?
    private var npcs: [(def: NPCDef, node: Walker, marker: NameTag)] = []
    private var talkTarget: String?
    private var lastCell: GridPoint
    private var stepsSinceBattle = 0
    private var lastUpdate: TimeInterval = 0
    private var noticeTimer: TimeInterval = 0
    private var hasLeft = false
    private var ambience: Ambience?
    /// Bunnies, frogs and crabs about the map, and birds crossing the sky.
    private var critters: Critters?
    private var lighting: Lighting?
    /// Day and night, and the weather.
    private var sky: Sky?
    /// On a dark map (a cave): the light round the hero, and the dark beyond it.
    private var lantern: Lantern?
    /// The minimap with only what you've seen, and which sighting it was drawn for.
    private var fogged: (version: Int, image: UIImage)?
    /// The minimap with what's round the land (`minimapPicture`), and what it was drawn from.
    private var surrounded: (version: Int, overviews: Int, picture: MinimapPicture)?
    /// Scenery softens toward the top and bottom of the screen.
    private let focus: DepthOfField
    private var crowd: Crowd?
    private var caveWalls: CaveWalls?
    /// Friends in your party walk behind you in a little line, each with their companion at their side.
    /// Those waiting for you on this map (`Adventurer.waitingAt`) stand where they are instead, until
    /// you walk up to them.
    private struct Ally {
        let id: UUID
        let node: Walker
        var pet: Walker?
        var waiting: Spot?
    }
    private var allies: [Ally] = []
    /// How close you come to a friend waiting for you before they set off with you again.
    private let rejoinRange: CGFloat = 64
    /// Roads that stay closed until a quest is done: the barricade nodes and the cells they block.
    private var barricades: [(exit: MapDef.Exit, nodes: [SKNode], cells: Set<GridPoint>)] = []
    private var lastBlockedNotice = Date.distantPast
    private var leftFoot = false
    /// Darkens the screen as you walk toward the edge of the map, so leaving is obvious.
    private let edgeFade = SKSpriteNode(color: .black, size: .zero)

    /// Built in the background to show past the border of the land you're in (`show(_:as:)`), not
    /// walked into yet: none of it reaches the session, the chat or the HUD until you do.
    private(set) var isNextDoor: Bool
    /// The lands next door shown past this one's borders, by id.
    private var nextDoor: [String: (scene: WorldScene, neighbour: Continent.Neighbour)] = [:]
    /// The lands round this one, each as its picture on the world map (`WorldOverview`) laid flat
    /// on the ground, under everything, while it isn't shown next door (not built yet, or let go):
    /// so past a border there's always the land next door, if not yet its trees, never nothing.
    /// By id (`placeFarLands`).
    private var farLands: [String: SKNode] = [:]
    /// Whether a land round this one had no picture yet when they were laid (they come in from
    /// the background, `WorldOverview.prepare`).
    private var farLandsMissing = false
    /// The lands among them laid in their ground's colour, waiting for their pictures.
    private var plainLands: Set<String> = []
    /// How far round the land they're laid, in cells.
    private static let farReach = 64
    /// The lands sharing a border with this one (none for a cave).
    private(set) lazy var neighbours: [Continent.Neighbour] = Continent.neighbours(of: def)
    /// The land you've just walked in from, whose place this one takes as it shows (`didMove(to:)`).
    var walkedInFrom: WorldScene?
    /// Walked into over a border: it's on screen already, so it shows with no fade (`SpriteKitView`).
    var arrivesOnFoot = false
    /// You've stepped over the border into a land shown next door, on your way there with no card.
    private var walkingOver = false
    /// Friends visiting the land you're in, who don't turn up next door too (set before `build`).
    var friendsElsewhere: Set<UUID> = []
    /// Every half second: the lands next door near enough to want built and shown, with how many
    /// cells away their borders are, nearest first.
    var onLandsNear: (@MainActor ([(neighbour: Continent.Neighbour, distance: Int)]) -> Void)?
    /// You've stepped across a border into a land next door: built and shown (its scene), or not
    /// built yet (nil: the coordinator takes you there behind the loading card), where you stand
    /// there, in its cells' points.
    var onCross: (@MainActor (Continent.Neighbour, WorldScene?, CGPoint) -> Void)?

    private let walkSpeed: CGFloat = 88
    private let talkRange: CGFloat = 50

    /// Pinch to zoom in on the ground around you, or out for a wider view. Kept from map to map.
    private static var zoom: CGFloat = 1
    private static let zoomRange: ClosedRange<CGFloat> = 0.85...2.2
    private var pinchStartZoom: CGFloat = 1
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

    /// `entry` is the edge the player walked in through, or nil to use the saved position;
    /// `arrival`, a spot to stand on instead (walked across a border before the land was built).
    /// `grid`: the land laid out already (off the main thread). `nextDoor`: built to show past the
    /// border of the land you're in (`isNextDoor`), touching nothing of the session.
    init(map def: MapDef, session: GameSession, input: InputState, entry: Edge?, arrival: CGPoint? = nil,
         grid: WorldMap? = nil, nextDoor: Bool = false) {
        // Characters made for this map pick up its light (a land next door's, as it's built).
        if !nextDoor { Walker.light = Self.light(of: def) }
        let map = grid ?? WorldMap(def: def)
        let player = Walker(cycle: ArtLibrary.shared.walkCycle(GameSession.heroArt), label: session.data.hero.name)
        player.tagMode = .whenStill
        player.fidgets = true
        self.def = def
        self.session = session
        self.input = input
        self.map = map
        self.player = player
        rng = SeededRandom(text: def.id + "/props")
        focus = DepthOfField(def.ambience?.focus)

        var start = map.center(of: map.center)
        if nextDoor {
            // Wherever you walk in from (`takeOver`).
        } else if let arrival {
            start = arrival
        } else if let entry {
            start = map.center(of: map.entryCell(from: entry))
        } else if let saved = session.playerPosition {
            start = saved
        }
        player.position = start
        lastCell = map.cell(at: start)
        isNextDoor = nextDoor

        super.init(size: CGSize(width: 874, height: 402))
        world.land = self
        scaleMode = .resizeFill
        backgroundColor = .black
        if !nextDoor { session.playerPosition = player.position }
        // The scenery goes up in `build(progress:)`, a piece at a time, behind the loading bar.
    }

    /// A point of the map's bounding box brought onto the land itself, its diamond: one past an
    /// edge is mirrored back in over it, so things scattered over the box (pools of light,
    /// butterflies) stay on this land, spread as evenly as before.
    private func onLand(_ point: CGPoint) -> CGPoint {
        let tile = WorldMap.tileSize
        let grid = WorldMap.unproject(point)
        func fold(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
            value < 0 ? min(length, -value) : value > length ? max(0, 2 * length - value) : value
        }
        return WorldMap.project(CGPoint(x: fold(grid.x, CGFloat(map.columns) * tile), y: fold(grid.y, CGFloat(map.rows) * tile)))
    }

    /// The light a land casts on everyone in it (`Walker.light`, its palette's `light`).
    private static func light(of def: MapDef) -> (color: UIColor, strength: CGFloat)? {
        guard let palette = def.theme.palette, let hex = palette.light, let color = UIColor(hex: hex) else { return nil }
        return (color, CGFloat(palette.lightStrength ?? 0.4))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        view.addGestureRecognizer(pinch)
        cam.setScale(1 / Self.zoom)
        if let previous = walkedInFrom {
            walkedInFrom = nil
            takeOver(from: previous)
        }
        if session.mapName != def.name {
            session.post(L("You arrive at {map}.", ["map": def.name]))
            if def.danger == true {
                session.post(L("⚔ Danger zone! Adventurers here may pick a fight."), .battle)
            }
            session.startChat(on: def.name)
        }
        session.mapName = def.name
        session.mapCell = lastCell
        MusicPlayer.shared.play(def.music)
        lastUpdate = 0
    }

    override func willMove(from view: SKView) {
        view.removeGestureRecognizer(pinch)
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pinchStartZoom = Self.zoom }
        Self.zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, pinchStartZoom * gesture.scale))
        cam.setScale(1 / Self.zoom)
    }

    #if DEBUG
    /// Debug launches (`zoom=2`): the map opens zoomed as if pinched, within the pinch's range.
    static func zoomForDebug(_ value: CGFloat) {
        zoom = min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
    #endif

    // MARK: - Building the map

    /// True once `build(progress:)` has finished; until then the scene sits still under the loading bar.
    private(set) var isBuilt = false

    /// How a land is built: all at once behind the loading card, or a few milliseconds a frame in
    /// the background while you walk toward it (a land next door), the frame given back between;
    /// `hurried`, the same in longer slices (debug screenshots of a border, which can't wait).
    enum Pace { case foreground, background, hurried }
    private var pace = Pace.foreground
    /// When this slice of a background build began.
    private var sliceStart = ContinuousClock.now
    /// The look the art library and walkers had before this slice (the land you're in), given back
    /// between slices (`breathe`).
    private var outerLook: (palette: MapPalette?, map: String?, light: (color: UIColor, strength: CGFloat)?)?

    /// Builds the map a piece at a time, pausing between pieces so the loading bar can move.
    /// `progress` gets 0...1 as the pieces are done (weighted by roughly how long each takes).
    /// In the `background`, it gives the frame back every few milliseconds instead.
    func build(pace: Pace = .foreground, progress: (Double) -> Void) async {
        guard !isBuilt, world.parent == nil else { return }
        self.pace = pace
        takeLook()
        addChild(lands)
        lands.addChild(world)
        addChild(cam)
        camera = cam
        if let darkness = def.ambience?.darkness { lantern = Lantern(darkness, in: world) }
        await reached(0.05, progress)

        world.addChild(await makeGround())
        placePlateaus()
        await reached(0.3, progress)
        await placeSurroundings()
        placeFarLands()
        await reached(0.45, progress)
        if let cave = def.theme.cave {
            caveWalls = CaveWalls(map: map, cave: cave, world: world, art: art, margin: Self.surroundingsMargin)
            await reached(0.55, progress)
        } else if !map.crags.isEmpty {
            placeCrags()
        }
        await breathe()
        placeLilyPads()
        placeBridges()
        placeReeds()
        await breathe()
        placeFence()
        placeBuildings()
        await reached(0.65, progress)
        placeDecor()
        await reached(0.8, progress)
        placeNPCs()
        await breathe()
        // A town's market traders sell what they have today, around your level.
        let market = Crowd.Market(sign: { [weak session] in session?.marketSign(for: $0) },
                                  shout: { [weak session] in session?.marketShout(for: $0) },
                                  level: session.data.hero.level)
        let away = friendsElsewhere
        crowd = Crowd(def: def, map: map, world: world, heroLevel: session.data.hero.level,
                      friends: session.friends.filter { !session.isInParty($0) && !away.contains($0.id) }, market: market,
                      locals: placeLocals())
        // Next door, nobody's heard yet, and nobody picks a fight with you over the border.
        crowd?.onChat = { [weak self, weak session] speaker, text, kind in
            guard self?.isNextDoor == false else { return }
            session?.postChat(text, from: speaker, kind: kind)
        }
        crowd?.dares = { [weak session] rival in session?.dares(rival) ?? false }
        crowd?.onChallenge = { [weak self] rival in
            guard let self, !self.isInputLocked, !self.isNextDoor else { return }
            self.startDuel(with: rival)
        }
        await breathe()
        placeFairyRings()
        placeOutcrops()
        await breathe()
        await placeProps()
        await placeSeamProps()
        placeSignposts()
        placeBorders()
        // Everyone set down before they were on the map stands up on the ground under them.
        for case let walker as Walker in world.children { walker.settle() }
        await reached(0.9, progress)

        if !isNextDoor {
            world.addChild(player)
            refreshHero()
            refreshFollower()
            refreshAllies()
        }
        player.settle()
        cam.position = cameraGoal
        edgeFade.alpha = 0
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        edgeFade.zPosition = 40_000
        cam.addChild(edgeFade)
        ambience = Ambience(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id, inside: { self.onLand($0) })
        ambience?.resize(to: size)
        critters = Critters(def.ambience, world: world, map: map, seed: def.id)
        lighting = Lighting(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id, inside: { self.onLand($0) })
        lighting?.resize(to: size)
        sky = Sky(map: def, camera: cam, start: session.data.startedAt)
        if let sky { lighting?.sunlight(sky.sunlight) }
        follow(sky?.sun ?? .noon)

        if !isNextDoor {
            // Don't start on top of scenery (e.g. an old save).
            // (A save from before a cave's walls went up can even be deep inside the rock, and one from
            // before the sea came in over the coasts out at sea, even off the map.)
            if !map.isWalkable(lastCell) || !map.contains(map.rawCell(at: player.position)),
               let open = map.nearestWalkable(to: lastCell, within: 48) ?? map.nearestWalkable(to: map.entryCell(from: def.exits.first?.edge ?? .south)) {
                player.position = map.center(of: open)
                lastCell = open
                cam.position = cameraGoal
            }
            session.playerPosition = player.position
            lantern?.follow(player.position)
            showChunks()
            explore()
        }
        if pace != .foreground { endSlice(at: #line) }
        giveLookBack()
        isBuilt = true
        progress(1)
    }

    /// Reports progress, then gives the screen a moment to draw it before the next piece (in the
    /// background, only once this slice has had its time).
    private func reached(_ fraction: Double, _ progress: (Double) -> Void, line: Int = #line) async {
        progress(fraction)
        if pace != .foreground {
            await breathe(line: line)
        } else {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Grades art and lights walkers for this land. In a background build the land you're in gets
    /// its own back between slices (`breathe`, `giveLookBack`).
    private func takeLook() {
        if pace != .foreground {
            outerLook = (art.grading.palette, art.grading.map, Walker.light)
            Walker.light = Self.light(of: def)
        }
        art.use(palette: def.theme.palette, for: def.id)
        sliceStart = .now
    }

    private func giveLookBack() {
        guard pace != .foreground, let outer = outerLook else { return }
        outerLook = nil
        if let map = outer.map { art.use(palette: outer.palette, for: map) }
        Walker.light = outer.light
    }

    /// In a background build: once this slice has had its few milliseconds, gives the frame back,
    /// and the land you're in its look, till the next. Nothing at all in the foreground.
    private func breathe(line: Int = #line) async {
        guard pace != .foreground, ContinuousClock.now - sliceStart > (pace == .hurried ? .milliseconds(250) : Self.sliceLength) else { return }
        endSlice(at: line)
        giveLookBack()
        try? await Task.sleep(for: .milliseconds(10))
        takeLook()
    }

    /// Notes how long this slice of a background build kept the frame, and where in this file it
    /// began and ended (`longestSlices`).
    private func endSlice(at line: Int) {
        let slice = ContinuousClock.now - sliceStart
        longestSlice = max(longestSlice, slice)
        if longestSlices.count < 5 || slice > longestSlices[longestSlices.count - 1].time {
            longestSlices.append((slice, sliceFrom, line))
            longestSlices.sort { $0.time > $1.time }
            if longestSlices.count > 5 { longestSlices.removeLast() }
        }
        sliceFrom = line
    }

    /// How long a background build works before giving a frame back.
    private static let sliceLength: Duration = .milliseconds(5)
    /// The longest a background build kept the frame in one go (the tests print it): what can't be
    /// cut finer than one step.
    private(set) var longestSlice: Duration = .zero
    /// The five longest slices, longest first, with the lines of this file where each began (the
    /// `breathe` before it; 0, the build's start) and ended: the tests print them, to show which
    /// steps to cut finer.
    private(set) var longestSlices: [(time: Duration, from: Int, to: Int)] = []
    /// The line of the `breathe` this slice began after.
    private var sliceFrom = 0

    override func didChangeSize(_ oldSize: CGSize) {
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        ambience?.resize(to: size)
        lighting?.resize(to: size)
    }

    private func makeGround() async -> SKNode {
        let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        let theme = def.theme
        let waterID = theme.water ?? "tile_water"
        let water = SKTileGroup(tileDefinition: SKTileDefinition(textures: art.waterFrames(waterID), size: tileSize, timePerFrame: 0.9))
        var groups: [String: SKTileGroup] = ["water": water]
        // Each group's picture, for drawing hills (`HillArt`).
        var pictures: [ObjectIdentifier: SKTexture] = [ObjectIdentifier(water): art.waterFrames(waterID).first ?? SKTexture()]
        func group(_ key: String, _ texture: () -> SKTexture) -> SKTileGroup {
            if let known = groups[key] { return known }
            let picture = texture()
            let made = SKTileGroup(tileDefinition: SKTileDefinition(texture: picture, size: tileSize))
            groups[key] = made
            pictures[ObjectIdentifier(made)] = picture
            return made
        }
        // Accent patches (flower meadows, moss) blend in as soft blobs. Not in towns, where the
        // accent is terrace paving and stays square.
        let patchAccent = (theme.accentPatches ?? 0) > 0 && theme.accent != nil && theme.accent != theme.ground
        /// Whether the ground past the map's edge at `cell` is water: where a river runs off the map
        /// it carries on straight (`placeSurroundings`), as the nearest cell on the map is.
        func waterBeyond(_ cell: GridPoint) -> Bool {
            let inside = GridPoint(col: min(max(cell.col, 0), map.columns - 1), row: min(max(cell.row, 0), map.rows - 1))
            return map.river.contains(inside)
        }
        /// Which cells of the 3×3 around `cell` are `kind` (bit row * 3 + col, row 0 north).
        func mask(_ cell: GridPoint, _ kind: Ground) -> Int {
            let own = map.ground[cell.row][cell.col] == kind
            var bits = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                    // Off the map a road or patch carries on; water only where a river runs off it.
                    let hit = map.contains(next) ? map.ground[next.row][next.col] == kind : kind == .water ? waterBeyond(next) : own
                    if hit { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
                }
            }
            return bits
        }
        /// The water cells of the 5×5 around `cell` (bit row * 5 + col, row 0 north), for shorelines.
        func poolMask(_ cell: GridPoint) -> Int {
            var bits = 0
            for dy in -2...2 {
                for dx in -2...2 {
                    let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                    let water = map.contains(next) ? map.ground[next.row][next.col] == .water : waterBeyond(next)
                    if water { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
                }
            }
            return bits
        }
        // Plain tiles come in four versions that fit together in any order, so big areas don't
        // repeat. Animated placeholder water keeps its single animated tile.
        let waterVaries = art.waterFrames(waterID).count == 1
        func plain(_ id: String, _ variant: Int) -> SKTileGroup {
            group("\(id)#\(variant)") { art.tileVariant(id, variant) }
        }
        let full = 0b111_111_111, sides = 0b010_101_010
        // The sea (on the continent), round the land and where it's come in over the coast
        // (`WorldMap.carveCoast`). It lies lower than the land (`Self.seaDrop`; `placeSea` draws it),
        // so its cells have no ground, and the land's edge along it is cut clear, curving as a lake's
        // shore does, a bank of earth under it (`bank`).
        var sea: Set<GridPoint> = []
        if map.coast != nil {
            for row in -2..<(map.rows + 2) {
                for col in -2..<(map.columns + 2) {
                    let cell = GridPoint(col: col, row: row)
                    let open = map.contains(cell) ? map.ground[row][col] == .sea : map.isOpenSea(cell)
                    if open { sea.insert(cell) }
                }
            }
        }
        /// The sea's cells of the 3×3 around `cell` (as `mask`), and of the 5×5 (as `poolMask`).
        func shore(_ cell: GridPoint) -> Int {
            var bits = 0
            for dy in -1...1 {
                for dx in -1...1 where sea.contains(GridPoint(col: cell.col + dx, row: cell.row + dy)) { bits |= 1 << ((1 - dy) * 3 + dx + 1) }
            }
            return bits
        }
        func seaPool(_ cell: GridPoint) -> Int {
            var bits = 0
            for dy in -2...2 {
                for dx in -2...2 where sea.contains(GridPoint(col: cell.col + dx, row: cell.row + dy)) { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
            }
            return bits
        }
        // Across the band where this land gives way to the one next door (`Seam`), that land's
        // ground in patches (`WorldMap.foreign`), graded as it is there: soft rounded blobs, as an
        // accent's patches are, joining where they touch (`ArtLibrary.GroundLayer.from`). Which land's
        // ground shows at a cell, as the index of its seam: inside the map as laid out, just past the
        // edge as the band runs on into the land next door.
        let others: [(land: MapDef, from: ArtLibrary.Foreign)?] = map.seams.map { seam in
            Content.shared.map(seam.neighbour).map { (land: $0, from: ArtLibrary.Foreign(land: $0.id, palette: $0.theme.palette)) }
        }
        var lookPast: [GridPoint: Int?] = [:]
        func otherLook(_ cell: GridPoint) -> Int? {
            if map.contains(cell) { return map.foreign[cell] }
            if let known = lookPast[cell] { return known }
            let found = map.seams.indices.first { map.seams[$0].covers(cell) && map.seams[$0].showsOther(cell) }
            lookPast[cell] = found
            return found
        }
        /// The land next door whose patches reach `cell` (its own, or one round it), and which cells
        /// of the 3×3 round it show that land (bit row * 3 + col, row 0 north).
        func patches(_ cell: GridPoint) -> (seam: Int, mask: Int)? {
            var looks: [Int?] = []
            for dy in -1...1 {
                for dx in -1...1 { looks.append(otherLook(GridPoint(col: cell.col + dx, row: cell.row - dy))) }
            }
            guard let seam = looks[4] ?? looks.compactMap({ $0 }).first else { return nil }
            var bits = 0
            for (bit, look) in looks.enumerated() where look == seam { bits |= 1 << bit }
            return (seam, bits)
        }
        var picks: [(col: Int, row: Int, group: SKTileGroup?)] = []
        // The land's cells within two of the sea, for its bank.
        var shoreline: [(col: Int, row: Int)] = []
        for row in 0..<map.rows {
            if row % 4 == 3 { await breathe() }
            for col in 0..<map.columns {
                let cell = GridPoint(col: col, row: row)
                let kind = map.ground[row][col]
                guard kind != .sea else {
                    picks.append((col, row, nil))
                    continue
                }
                let road = mask(cell, .path), pond = mask(cell, .water)
                let variant = Self.variant(of: cell)
                let patch = patchAccent ? mask(cell, .accent) : 0
                // What shows between the soft shapes: the cell's own ground, or for a road, pond or
                // patch cell the ground around it.
                let base: String = switch kind {
                case .ground: theme.ground
                case .border: theme.border ?? theme.ground
                case .accent where !patchAccent: theme.accent ?? theme.ground
                default: mask(cell, .border) & sides != 0 ? (theme.border ?? theme.ground) : theme.ground
                }
                var layers: [ArtLibrary.GroundLayer] = []
                // The land next door's patches first, under everything of this land's.
                let other = map.seams.isEmpty ? nil : patches(cell)
                let otherLand = other.flatMap { others[$0.seam] }
                if let other, let otherLand {
                    layers.append(.init(tile: otherLand.land.theme.ground, mask: other.mask, style: .patch, from: otherLand.from))
                }
                if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
                if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road)) }
                if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(cell), style: .water)) }
                let near = sea.isEmpty ? 0 : seaPool(cell)
                if near != 0 { shoreline.append((col, row)) }
                let coast = near == 0 ? 0 : shore(cell)
                if coast != 0 { layers.append(.init(tile: base, mask: near, style: .cut)) }
                let chosen: SKTileGroup
                if pond == full, coast == 0 {
                    chosen = waterVaries ? plain(waterID, variant) : water
                } else if road == full, pond == 0, coast == 0 {
                    chosen = plain(theme.path, variant)
                } else if let other, let otherLand, other.mask == full, layers.count == 1 {
                    // All the land next door's ground.
                    let land = otherLand.land
                    chosen = group("foreign|\(land.id)#\(variant)") {
                        art.foreignTile(land.theme.ground, palette: land.theme.palette, from: land.id, variant: variant, base: base)
                    }
                } else if layers.isEmpty {
                    chosen = plain(base, variant)
                } else if let accent = theme.accent, patch == full, road == 0, pond == 0, coast == 0 {
                    chosen = plain(accent, variant)
                } else {
                    // Shorelines depend on where they are (see organicTile), so each gets its own tile.
                    let place = pond != 0 || coast != 0 ? "@\(col),\(row)" : ""
                    let key = base + "|" + layers.map { "\($0.style)\($0.mask)\($0.from?.land ?? "")" }.joined(separator: "|") + place
                    chosen = group(key) { art.organicTile(base: base, layers: layers, cell: cell, variant: variant) }
                }
                picks.append((col, row, chosen))
            }
        }
        await breathe()
        let tileSet = SKTileSet(tileGroups: Array(groups.values))
        let tileMap = SKTileMapNode(tileSet: tileSet, columns: map.columns, rows: map.rows, tileSize: tileSize)
        tileMap.anchorPoint = .zero
        for (index, pick) in picks.enumerated() {
            // SpriteKit takes its time over each tile (a fifth of a millisecond in the tests), so a few at a time.
            if index % 32 == 31 { await breathe() }
            if let group = pick.group { tileMap.setTileGroup(group, forColumn: pick.col, row: pick.row) }
        }
        // A raised terrace: its own tiles again, drawn its height up (`placePlateaus` sets them
        // down). The stairs are drawn as slopes instead.
        raisedTops = map.plateaus.map { plateau in
            let (low, high) = plateau.bounds
            let top = SKTileMapNode(tileSet: tileSet, columns: high.col - low.col + 1, rows: high.row - low.row + 1, tileSize: tileSize)
            top.anchorPoint = .zero
            for pick in picks {
                let cell = GridPoint(col: pick.col, row: pick.row)
                guard let group = pick.group, plateau.cells.contains(cell), plateau.ramps[cell] == nil else { continue }
                top.setTileGroup(group, forColumn: pick.col - low.col, row: pick.row - low.row)
            }
            top.position = CGPoint(x: CGFloat(low.col) * WorldMap.tileSize, y: CGFloat(low.row) * WorldMap.tileSize)
            let grid = SKNode()
            grid.addChild(top)
            let layer = projected(grid)
            layer.position.y = plateau.height
            return layer
        }
        // Soft patches of colour over the whole ground, so it isn't one flat colour.
        let grid = SKNode()
        grid.addChild(tileMap)
        await breathe()
        let variation = Lighting.groundVariation(columns: map.columns, rows: map.rows, tile: WorldMap.tileSize, palette: theme.palette,
                                                 seed: def.id) { col, row in self.map.ground[row][col] != .sea }
        if let variation {
            variation.zPosition = 1
            grid.addChild(variation)
        }
        // And a wash of the two lands' colours over the band along each border, so the patches of
        // each land's ground run into each other (as RuneScape blends its ground's colours).
        for neighbour in neighbours {
            await breathe()
            let band = await blendBand(toward: neighbour, seam: map.seams.first { $0.neighbour == neighbour.def.id })
            grid.addChild(band)
        }
        // Bridges' decks lie on the water with the ground (`BridgeArt`; their rails stand in the
        // world, `placeBridges`).
        if !map.bridges.isEmpty {
            let pixels = art.tileTexture(theme.ground).cgImage().width
            for bridge in map.bridges {
                await breathe()
                guard let deck = BridgeArt.deck(for: bridge, pixels: pixels, palette: theme.palette) else { continue }
                deck.zPosition = 2
                grid.addChild(deck)
            }
        }
        // Hills: the same ground again, lit and lifted (`HillArt`; `placePlateaus` sets them down).
        if !map.hills.isEmpty {
            await breathe()
            var images: [String: CGImage] = [:]
            func picture(_ key: String, _ texture: () -> SKTexture?) -> CGImage? {
                if let known = images[key] { return known }
                let made = texture()?.cgImage()
                images[key] = made
                return made
            }
            func tiles(_ id: String) -> (GridPoint) -> CGImage? {
                { cell in picture("\(id)#\(Self.variant(of: cell))") { self.art.tileVariant(id, Self.variant(of: cell)) } }
            }
            let palette = theme.palette
            // Rock shows on the slopes of all but the gentlest hills: the map's own bank, or scree.
            let rock: String? = theme.hills?.bank ?? (map.rockiness >= 0.2 ? "tile_scree" : nil)
            // Past the map's edge (a range where a road leads into a cave), the land out there.
            let beyond = tiles(theme.border ?? theme.ground)
            let look = HillArt.Look(
                ground: { cell in
                    guard self.map.contains(cell), let group = picks[cell.row * self.map.columns + cell.col].group else { return beyond(cell) }
                    return picture("\(ObjectIdentifier(group).hashValue)") { pictures[ObjectIdentifier(group)] }
                },
                trail: tiles(theme.path),
                bank: rock.map(tiles),
                rocky: map.rockiness,
                variation: variation?.texture?.cgImage(),
                mapSize: (map.columns, map.rows),
                shadow: Lighting.rgb(palette?.shadow) ?? (r: 0.2, g: 0.22, b: 0.3),
                highlight: Lighting.rgb(palette?.highlight) ?? (r: 1, g: 0.95, b: 0.8))
            // A range where a road leads into a cave is a mountain of layered rock, its foot grassy,
            // in deeper shade and brighter sun; out past the map's edge the ground is rock too.
            let scree = tiles(theme.hills?.bank ?? "tile_scree")
            var crag = look
            crag.ground = { cell in self.map.contains(cell) ? look.ground(cell) : scree(cell) }
            crag.bank = scree
            crag.rocky = 1
            crag.rockAbove = 0.2
            crag.ambient = Self.cragShade
            crag.brightest = 1.3
            crag.strata = 14
            // Its road stays a road all the way up to the cave's mouth.
            crag.road = { cell in self.map.contains(cell) && self.map.ground[cell.row][cell.col] == .path }
            // Out past the ends of its edge, it stops where a land next door lies.
            var elsewhere: [GridPoint: Bool] = [:]
            crag.hidden = { cell in
                guard !self.map.contains(cell) else { return false }
                if let known = elsewhere[cell] { return known }
                let land = Continent.isLand(cell, from: self.def)
                elsewhere[cell] = land
                return land
            }
            // A range with a mountain in it: bare layered rock from partway up (its foothills'
            // tops below that), in deeper shade and brighter sun, so its height shows.
            var mountain = look
            mountain.bank = look.bank ?? scree
            mountain.ambient = Self.cragShade
            mountain.brightest = 1.2
            mountain.strata = 14
            // Already where they show on screen (they lift themselves) and sorted, so straight into
            // the world.
            for hill in map.hills {
                await breathe()
                var style = look
                if hill.isCrag {
                    style = crag
                } else if hill.hasMountain {
                    style = mountain
                    style.rockFrom = Double(hill.peak) * 0.4
                }
                let sprites = await HillArt.sprites(for: hill, look: style, pause: { await self.breathe() })
                raisedHills += sprites as [SKNode]
            }
        }
        let ground = SKNode()
        ground.zPosition = -100_000
        ground.addChild(projected(grid))
        if !shoreline.isEmpty {
            for layer in await bank(under: shoreline, picks: picks, tiles: tileSet) { ground.addChild(layer) }
        }
        return ground
    }

    /// How far the sea lies below the land, in points.
    static let seaDrop: CGFloat = 14

    /// The bank of earth along the land's edge over the sea, which lies `seaDrop` lower: the land's
    /// outline along the shore (`cells`, with the tiles they show, cut along it) drawn again a little
    /// lower each time, in layers of soil darkening toward the water, and a line of foam at its foot.
    /// Under the land, so it shows only where the land's edge faces you.
    private func bank(under cells: [(col: Int, row: Int)], picks: [(col: Int, row: Int, group: SKTileGroup?)],
                      tiles: SKTileSet) async -> [SKNode] {
        let tileSize = CGSize(width: WorldMap.tileSize, height: WorldMap.tileSize)
        let soil = (r: CGFloat(0.43), g: CGFloat(0.32), b: CGFloat(0.22))
        // The land's own ground colour, darkened, leans the soil its way (sandy under sand, grey under scree).
        let ground = art.gradedTile(def.theme.ground, palette: def.theme.palette).map { Self.averageColor(of: $0) } ?? (0.4, 0.5, 0.3)
        let top = (r: soil.r * 0.6 + ground.0 * 0.3, g: soil.g * 0.6 + ground.1 * 0.3, b: soil.b * 0.6 + ground.2 * 0.3)
        let steps = 7
        var layers: [SKNode] = []
        for step in 0...steps {
            let foam = step == steps
            let shade = 1 - 0.45 * CGFloat(step) / CGFloat(steps - 1)
            let outline = SKTileMapNode(tileSet: tiles, columns: map.columns, rows: map.rows, tileSize: tileSize)
            outline.anchorPoint = .zero
            for (number, cell) in cells.enumerated() {
                if number % 32 == 31 { await breathe() }
                if let group = picks[cell.row * map.columns + cell.col].group { outline.setTileGroup(group, forColumn: cell.col, row: cell.row) }
            }
            outline.color = foam ? .white : UIColor(red: top.r * shade, green: top.g * shade, blue: top.b * shade, alpha: 1)
            outline.colorBlendFactor = 1
            outline.alpha = foam ? 0.5 : 1
            let grid = SKNode()
            grid.addChild(outline)
            let layer = projected(grid)
            // Each lower than the last, the foam just below the bottom one, all under the land.
            layer.position.y = foam ? -Self.seaDrop - 1.5 : -Self.seaDrop * CGFloat(step + 1) / CGFloat(steps)
            layer.zPosition = -0.1 - 0.05 * CGFloat(step)
            layers.append(layer)
            await breathe()
        }
        return layers
    }

    /// How many texels a cell the wash has across, so it follows the band's middle line through
    /// the cells, not their edges.
    private static let blendFineness = 4
    /// How strong the wash is in the middle of the band, where the two lands' ground is half each.
    private static let blendStrength: CGFloat = 0.35

    /// A wash over the band where this land gives way to the one next door (`Seam`), in the two
    /// lands' ground colours (each graded by its palette) mixed as their ground is there: this
    /// land's colour where its own ground's most of it, the other's where the other's is, half
    /// each on the middle line. Strongest there, where the two grounds' patches are half and half,
    /// and fading to nothing either side as one land's ground takes over, so the patches' colours
    /// run into each other. The land next door lays the same wash on its side, so the two meet
    /// without a seam. Along a town's wall the band's middle is the border itself. Over the band
    /// only, `blendFineness` texels a cell, smoothed: none over the sea or the land's edge along it
    /// (its bank shows there), and fading out toward the ends of the stretch they share.
    private func blendBand(toward neighbour: Continent.Neighbour, seam: Seam?) async -> SKNode {
        let tile = WorldMap.tileSize
        let image = art.gradedTile(neighbour.def.theme.ground, palette: neighbour.def.theme.palette)
        let other = image.map { Self.averageColor(of: $0) } ?? (0.5, 0.5, 0.5)
        let own = art.gradedTile(def.theme.ground, palette: def.theme.palette).map { Self.averageColor(of: $0) } ?? (0.5, 0.5, 0.5)
        let columns = map.columns, rows = map.rows
        func nearSea(_ cell: GridPoint) -> Bool {
            for dr in -1...1 {
                for dc in -1...1 {
                    let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    let open = map.contains(next) ? map.ground[next.row][next.col] == .sea : map.isOpenSea(next)
                    if open { return true }
                }
            }
            return false
        }
        // The band the wash covers: the stretch the two share, and in from the edge as far as the
        // band reaches.
        let edge = neighbour.edge, span = neighbour.span
        let across = edge == .east || edge == .west
        let depth = min(Seam.depth, across ? columns : rows)
        let low: GridPoint = switch edge {
        case .north: GridPoint(col: span.lowerBound, row: rows - depth)
        case .south: GridPoint(col: span.lowerBound, row: 0)
        case .east: GridPoint(col: columns - depth, row: span.lowerBound)
        case .west: GridPoint(col: 0, row: span.lowerBound)
        }
        let cells = (width: across ? depth : span.count, height: across ? span.count : depth)
        let fine = Self.blendFineness
        let width = cells.width * fine, height = cells.height * fine
        // The middle line's offset from the border at each texel along it, and the band's width
        // either side of it (along a town's wall, the border itself and the full width).
        let alongs = (0..<(span.count * fine)).map { Double(span.lowerBound) + (Double($0) + 0.5) / Double(fine) }
        let offsets: [Double] = alongs.map { seam?.offset(at: $0) ?? 0 }
        let widths: [Double] = alongs.map { seam?.width(at: $0) ?? Seam.blend }
        var wet: [GridPoint: Bool] = [:]
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            if y % 16 == 15 { await breathe() }
            for x in 0..<width {
                // The texel's middle in the land's cells: the bitmap's rows run north to south, the
                // grid's count up from the south.
                let gx = Double(low.col) + (Double(x) + 0.5) / Double(fine)
                let gy = Double(low.row + cells.height) - (Double(y) + 0.5) / Double(fine)
                // How far in from the edge, and which texel along it.
                let spot: (inward: Double, step: Int) = switch edge {
                case .north: (Double(rows) - gy, x)
                case .south: (gy, x)
                case .east: (Double(columns) - gx, height - 1 - y)
                case .west: (gx, height - 1 - y)
                }
                let step = spot.step
                // How much of the ground is the other land's here (`Seam.share`).
                let share = CGFloat(Seam.share(at: spot.inward - offsets[step], width: widths[step]))
                guard share > 0.001, share < 0.999 else { continue }
                let cell = GridPoint(col: Int(gx.rounded(.down)), row: Int(gy.rounded(.down)))
                let near: Bool
                if let known = wet[cell] {
                    near = known
                } else {
                    near = nearSea(cell)
                    wet[cell] = near
                }
                guard !near else { continue }
                let color = (own.0 + (other.0 - own.0) * share, own.1 + (other.1 - own.1) * share, own.2 + (other.2 - own.2) * share)
                let along = (Double(step) + 0.5) / Double(fine)
                let end = CGFloat(min(1, min(along, Double(span.count) - along) / 4))
                let alpha = Self.blendStrength * 4 * share * (1 - share) * end * end * (3 - 2 * end)
                let index = (y * width + x) * 4
                pixels[index] = UInt8((color.0 * alpha * 255).rounded())
                pixels[index + 1] = UInt8((color.1 * alpha * 255).rounded())
                pixels[index + 2] = UInt8((color.2 * alpha * 255).rounded())
                pixels[index + 3] = UInt8((alpha * 255).rounded())
            }
        }
        guard width > 0, height > 0, let made = PixelImage.make(pixels, width: width, height: height) else { return SKNode() }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .linear
        let band = SKSpriteNode(texture: texture, size: CGSize(width: CGFloat(cells.width) * tile, height: CGFloat(cells.height) * tile))
        band.anchorPoint = .zero
        band.position = CGPoint(x: CGFloat(low.col) * tile, y: CGFloat(low.row) * tile)
        band.zPosition = 1.5
        return band
    }

    /// Which of a tile's four versions a cell shows: a hash, so neighbours differ without a pattern.
    static func variant(of cell: GridPoint) -> Int {
        var hash = UInt64(bitPattern: Int64(cell.col)) &* 0x9E37_79B9_7F4A_7C15
        hash ^= UInt64(bitPattern: Int64(cell.row)) &* 0xC2B2_AE3D_27D4_EB4F
        hash ^= hash >> 29
        hash = hash &* 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 32
        return Int(hash % 4)
    }

    /// Wraps grid-space ground so it renders in Fairyland's isometric 2.5D view:
    /// turned 45° and squashed to half height (matches `WorldMap.project`).
    private func projected(_ node: SKNode) -> SKNode {
        let squash = SKNode()
        squash.yScale = 0.5
        let turn = SKNode()
        turn.zRotation = .pi / 4
        squash.addChild(turn)
        turn.addChild(node)
        return squash
    }

    private static let surroundingsMargin = 18
    /// The outer tiles of the surroundings that fade into fog. Past them the scene's background is
    /// the same fog colour, so walking to a corner never shows black.
    private static let fogBand = 8

    /// What lies past the map's edge, so small maps never show black bars (e.g. in portrait): on the
    /// continent the sea (`placeSea`); round a cave its ground, under the rock of its walls
    /// (`CaveWalls`), the roads running on out through the exits, into the gloom.
    private func placeSurroundings() async {
        let margin = Self.surroundingsMargin
        let around = Continent.sea(round: def, margin: margin)
        if Continent.origin(of: def) != nil {
            await placeSea(around, margin: margin)
            return
        }
        let tile = WorldMap.tileSize
        let tileSize = CGSize(width: tile, height: tile)
        let theme = def.theme
        let fill = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.border ?? theme.ground), size: tileSize))
        let road = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.path), size: tileSize))
        let surroundings = SKTileMapNode(tileSet: SKTileSet(tileGroups: [fill, road]), columns: map.columns + margin * 2,
                                         rows: map.rows + margin * 2, tileSize: tileSize, fillWith: fill)
        surroundings.anchorPoint = .zero
        surroundings.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        // Each exit's road runs straight out to the edge of the surroundings.
        for exit in def.exits {
            for i in 0..<margin {
                switch exit.edge {
                case .north, .south:
                    let edgeRow = exit.edge == .north ? map.rows - 1 : 0
                    for col in 0..<map.columns where map.ground[edgeRow][col] == .path {
                        let row = exit.edge == .north ? map.rows + i : -1 - i
                        surroundings.setTileGroup(road, forColumn: col + margin, row: row + margin)
                    }
                case .east, .west:
                    let edgeCol = exit.edge == .east ? map.columns - 1 : 0
                    for row in 0..<map.rows where map.ground[row][edgeCol] == .path {
                        let col = exit.edge == .east ? map.columns + i : -1 - i
                        surroundings.setTileGroup(road, forColumn: col + margin, row: row + margin)
                    }
                }
            }
        }
        let fog = Self.fogColor(from: art.tileTexture(theme.border ?? theme.ground), cave: theme.cave != nil)
        backgroundColor = fog
        let ground = SKNode()
        ground.addChild(surroundings)
        if let mist = mist(over: around, margin: margin, color: fog) { ground.addChild(mist) }
        let projectedSurroundings = projected(ground)
        projectedSurroundings.zPosition = -100_001
        world.addChild(projectedSurroundings)
    }

    /// The water all round the lands (`Self.seaTile`, the same blue whichever land you're in).
    private static let seaTile = "raw:tile_water"

    /// The sea round a land on the continent (`Continent.sea`, as much of it as is this land's to
    /// draw) and where it's come in over the land's coast (`WorldMap.carveCoast`): water out to the
    /// haze, which thickens with distance from any land until the scene's background, the same
    /// colour, takes over, `seaDrop` lower than the land (`bank` draws the land's edge down to it).
    /// Where a road leads into a cave, its range rises out of it on rock.
    private func placeSea(_ sea: [GridPoint: Double], margin: Int) async {
        let tile = WorldMap.tileSize
        let tileSize = CGSize(width: tile, height: tile)
        let water = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(Self.seaTile), size: tileSize))
        let rock = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(def.theme.hills?.bank ?? "tile_scree"), size: tileSize))
        let surroundings = SKTileMapNode(tileSet: SKTileSet(tileGroups: [water, rock]), columns: map.columns + margin * 2,
                                         rows: map.rows + margin * 2, tileSize: tileSize)
        surroundings.anchorPoint = .zero
        surroundings.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        let ranges = map.crags.map { map.hills[$0.hill] }
        // A few tiles at a time, as SpriteKit takes its time over each (`makeGround`).
        for (number, cell) in sea.keys.enumerated() {
            if number % 32 == 31 { await breathe() }
            let group = ranges.contains { $0.cells.contains(cell) } ? rock : water
            surroundings.setTileGroup(group, forColumn: cell.col + margin, row: cell.row + margin)
        }
        for row in 0..<map.rows {
            if row % 4 == 3 { await breathe() }
            for col in 0..<map.columns where map.ground[row][col] == .sea {
                surroundings.setTileGroup(water, forColumn: col + margin, row: row + margin)
            }
        }
        let haze = Self.fogColor(from: art.tileTexture(Self.seaTile), cave: false)
        backgroundColor = haze
        let ground = SKNode()
        ground.addChild(surroundings)
        if let mist = mist(over: sea, margin: margin, color: haze) { ground.addChild(mist) }
        let projectedSea = projected(ground)
        projectedSea.position.y = -Self.seaDrop
        projectedSea.zPosition = -100_001
        world.addChild(projectedSea)
    }

    /// Haze over what lies round the land (the sea, a cave's gloom), by how far each cell is from any
    /// land: clear close by, thickening from `fogBand` cells short of the margin to solid at it,
    /// where the scene's background (the same colour) takes over. One pixel a cell, smoothed.
    private func mist(over around: [GridPoint: Double], margin: Int, color: UIColor) -> SKSpriteNode? {
        let columns = map.columns + margin * 2, rows = map.rows + margin * 2
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let start = Double(margin - Self.fogBand)
        for (cell, distance) in around {
            let t = min(1, max(0, (distance - start) / Double(Self.fogBand)))
            let alpha = UInt8((t * t * (3 - 2 * t) * 255).rounded())
            // The bitmap's rows run north to south; the grid's count up from the south.
            let index = ((rows - 1 - (cell.row + margin)) * columns + cell.col + margin) * 4
            for channel in 0..<4 { pixels[index + channel] = alpha }   // premultiplied white
        }
        guard let image = PixelImage.make(pixels, width: columns, height: rows) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        let tile = WorldMap.tileSize
        let node = SKSpriteNode(texture: texture, color: color, size: CGSize(width: CGFloat(columns) * tile, height: CGFloat(rows) * tile))
        node.colorBlendFactor = 1
        node.anchorPoint = .zero
        node.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        node.zPosition = 1
        return node
    }

    /// Where a road leads into a cave: stones strewn over its range out past the map's edge, and
    /// mist over its far reaches, from 14 cells out (13 past a ridge) to all mist 8 further, up at
    /// about the height of the ground there, as over the land past the other edges.
    /// (The range itself is drawn with the hills, `HillArt`, its cave's mouth in its side.)
    private func placeCrags() {
        let tile = WorldMap.tileSize
        let colour = Self.fogColor(from: art.tileTexture(def.theme.border ?? def.theme.ground), cave: false)
        for crag in map.crags {
            let hill = map.hills[crag.hill]
            strewStones(on: hill)
            let length = crag.edge == .north || crag.edge == .south ? map.columns : map.rows
            let facesYou = crag.edge == .north || crag.edge == .east
            let from: CGFloat = facesYou ? 14 : 13
            // The ground's height where the mist thickens, on average along the edge.
            let heights = stride(from: 0, to: length, by: 4).map { along -> CGFloat in
                let cell = map.cell(on: crag.edge, along: along, inward: -Int(from) - 4)
                return hill.height(atCells: Double(cell.col) + 0.5, Double(cell.row) + 0.5)
            }
            let lift = heights.reduce(0, +) / CGFloat(max(1, heights.count))
            // In the ground's own terms: `from` cells past the edge to all mist 8 further, and on to
            // where the range ends (the continent keeps the lands next door clear that far). Past
            // the ends of the edge it reaches as far as the range does, but not over a land there.
            func clear(_ alongs: StrideTo<Int>) -> Bool {
                alongs.allSatisfy { along in
                    stride(from: -4, through: -32, by: -7).allSatisfy { inward in
                        !Continent.isLand(map.cell(on: crag.edge, along: along, inward: inward), from: def)
                    }
                }
            }
            let low: CGFloat = clear(stride(from: -2, to: -22, by: -5)) ? 20 : 0
            let high: CGFloat = clear(stride(from: length + 1, to: length + 21, by: 5)) ? 20 : 0
            let wide = (CGFloat(length) + low + high) * tile, deep = 8 * tile, beyond = 8 * tile
            // Along the edge, the way its cells count, from the middle: which way that is once turned.
            let toward: CGFloat = crag.edge == .north || crag.edge == .west ? 1 : -1
            let off = (high - low) / 2 * tile * toward
            let fog = SKNode()
            let band = SKSpriteNode(texture: Self.fogTexture, color: colour, size: CGSize(width: wide, height: deep))
            band.colorBlendFactor = 1
            let mist = SKSpriteNode(color: colour, size: CGSize(width: wide, height: beyond))
            // Laid out for the north edge, then turned to the crag's.
            band.position = CGPoint(x: off, y: (from + 4) * tile)
            mist.position = CGPoint(x: off, y: (from + 8) * tile + beyond / 2)
            let turned = SKNode()
            turned.addChild(band)
            turned.addChild(mist)
            let middle = CGFloat(length) / 2 * tile
            switch crag.edge {
            case .north: turned.position = CGPoint(x: middle, y: CGFloat(map.rows) * tile)
            case .south: turned.position = CGPoint(x: middle, y: 0); turned.zRotation = .pi
            case .east: turned.position = CGPoint(x: CGFloat(map.columns) * tile, y: middle); turned.zRotation = -.pi / 2
            case .west: turned.position = CGPoint(x: 0, y: middle); turned.zRotation = .pi / 2
            }
            fog.addChild(turned)
            let raised = projected(fog)
            raised.position.y = lift
            raised.zPosition = 15_000
            world.addChild(raised)
        }
    }

    /// Boulders and stones strewn over a range where a road leads into a cave, out past the map's
    /// edge, so its slopes read as rough rock; up where its ground stands, and none over its cave's
    /// mouth.
    private func strewStones(on hill: WorldMap.Hill) {
        var random = SeededRandom(text: def.id + "/crag stones")
        for cell in hill.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) where !map.contains(cell) {
            // Not on a land next door, where the range past the edge's end would reach into it.
            if Continent.isLand(cell, from: def) { continue }
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

    /// White, solid along the top row and fading smoothly to clear at the bottom (tinted per map).
    private static let fogTexture: SKTexture = {
        let height = 64
        var pixels = [UInt8](repeating: 0, count: height * 4)
        for row in 0..<height {
            let t = 1 - Double(row) / Double(height - 1)
            let alpha = UInt8((t * t * (3 - 2 * t) * 255).rounded())     // smoothstep
            for channel in 0..<4 { pixels[row * 4 + channel] = alpha }   // premultiplied white
        }
        let texture = PixelImage.make(pixels, width: 1, height: height).map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        return texture
    }()

    /// The map's surrounding ground, averaged and hazed: pale mist outdoors, deep gloom in caves.
    /// A texture's average colour, 0...1 per channel.
    private static func averageColor(of texture: SKTexture) -> (CGFloat, CGFloat, CGFloat) {
        averageColor(of: texture.cgImage())
    }

    /// An image's average colour, 0...1 per channel.
    private static func averageColor(of image: CGImage) -> (CGFloat, CGFloat, CGFloat) {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    private static func fogColor(from texture: SKTexture, cave: Bool) -> UIColor {
        let (r, g, b) = averageColor(of: texture)
        let average = [r, g, b]
        let haze: [CGFloat] = cave ? [0.05, 0.04, 0.06] : [0.86, 0.9, 0.94]
        let mix: CGFloat = cave ? 0.55 : 0.4
        let channel = (0..<3).map { average[$0] + (haze[$0] - average[$0]) * mix }
        return UIColor(red: channel[0], green: channel[1], blue: channel[2], alpha: 1)
    }

    private func placeFence() {
        guard !map.fenceCells.isEmpty else { return }
        for cell in map.fenceCells { map.occupy(cell, blocking: true) }
        TownFence.place(cells: map.fenceCells, map: map, world: world, art: art)
    }

    /// Houses take a 3×2 footprint above their anchor tile.
    private func placeBuildings() {
        for lot in map.lots {
            addScenery(art.sprite(lot.art), at: lot.anchor)
        }
        for decor in map.streetDecor {
            let lamp = addScenery(art.sprite(decor.art), at: decor.cell)
            if decor.art == "street_lamp" {
                // A warm glow around each lamp.
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
        }
        placeTerraces()
        // The map's own buildings, already set down clear of the roads (WorldMap.placeOwnBuildings).
        for building in map.buildings {
            addScenery(art.sprite(building.art), at: building.anchor)
        }
    }

    /// How high the ground stands under a point on the map (a hilltop, a terrace): walkers there are
    /// drawn that much higher (`Walker.settle`).
    func groundHeight(at point: CGPoint) -> CGFloat { map.height(at: point) }

    /// Raised tops from `makeGround`, one per plateau, until `placePlateaus` sets them down.
    private var raisedTops: [SKNode] = []
    /// Hills from `makeGround`: `placePlateaus` sets them down, and the sun lights them (`follow(_:)`).
    private var raisedHills: [SKNode] = []

    /// How deep raised ground over `cells` is drawn: just behind the back of it, so everything
    /// standing on it (or in front) is drawn over it and whoever stands just behind it is hidden by it.
    private static func topZ(of cells: Set<GridPoint>) -> CGFloat {
        let tile = WorldMap.tileSize
        let back = cells.map { WorldMap.project(CGPoint(x: CGFloat($0.col + 1) * tile, y: CGFloat($0.row + 1) * tile)).y }.max() ?? 0
        return -back - 0.75
    }

    /// Raised ground: the hills (drawn in strips by `HillArt`), and a town's terraces (WorldMap.plateaus),
    /// each top drawn its height up, a stone wall under the edges that face you, and stone steps
    /// climbing from the ground in front to the top.
    private func placePlateaus() {
        for hill in raisedHills { world.addChild(hill) }
        let tile = WorldMap.tileSize
        let stone = art.tileTexture(def.theme.accent ?? "tile_scree")
        func corner(_ col: Int, _ row: Int) -> CGPoint { WorldMap.project(CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile)) }
        // Lines are gathered into one shape per colour, a draw each instead of one per edge.
        func stroke(_ path: CGPath, color: UIColor, width: CGFloat, z: CGFloat) {
            guard !path.isEmpty else { return }
            let node = SKShapeNode(path: path)
            node.strokeColor = color
            node.lineWidth = width
            node.lineCap = .round
            node.zPosition = z
            world.addChild(node)
        }
        for (index, plateau) in map.plateaus.enumerated() {
            let rise = plateau.height
            let topZ = Self.topZ(of: plateau.cells)
            let lips = CGMutablePath(), shadows = CGMutablePath(), creases = CGMutablePath(), treads = CGMutablePath()
            func line(_ path: CGMutablePath, _ from: CGPoint, _ to: CGPoint) {
                path.move(to: from)
                path.addLine(to: to)
            }
            if index < raisedTops.count {
                raisedTops[index].zPosition = topZ
                world.addChild(raisedTops[index])
            }
            // Walls: under each edge of the top facing you (front, left) where the ground beyond is
            // lower, down to it (beside the stairs, down to their slope: a triangle).
            for cell in plateau.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) where plateau.ramps[cell] == nil {
                for front in [true, false] {
                    let beyond = front ? GridPoint(col: cell.col, row: cell.row - 1) : GridPoint(col: cell.col - 1, row: cell.row)
                    if plateau.cells.contains(beyond), plateau.ramps[beyond] == nil { continue }
                    let a = CGPoint(x: CGFloat(cell.col) * tile, y: CGFloat(cell.row) * tile)
                    let b = front ? CGPoint(x: a.x + tile, y: a.y) : CGPoint(x: a.x, y: a.y + tile)
                    // Just over the edge, at each end.
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
                    // Lit from the front: the side facing left a shade darker.
                    face.fillColor = UIColor(white: front ? 0.82 : 0.64, alpha: 1)
                    face.strokeColor = .clear
                    face.lineWidth = 0
                    face.zPosition = topZ - 0.5
                    world.addChild(face)
                    // A pale stone lip along the top and a soft shadow where the wall meets the ground.
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
                // Under the top: where the top beside it stands in front of it, the top shows.
                slope.zPosition = topZ - 0.25
                world.addChild(slope)
                // Steps across them, foot to head.
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

    /// Layered stone terraces like Fairyland's, raised (`placePlateaus` draws the top, its walls
    /// and stairs): balustrades run along every edge of the top and pillars stand on its corners.
    private func placeTerraces() {
        let rail = art.sprite("stone_balustrade"), pillar = art.sprite("wall_pillar")
        // The balustrade picture is face on: set down a cell at a time, it stepped along a slanted
        // edge like stairs, so it's slanted to follow the edge. Its posts sit 11% and 89% across it.
        let picture = rail.texture.cgImage()
        let rising = TownFence.railing(picture, posts: (0.108, 0.912), height: 16, alongColumns: true)
        let falling = TownFence.railing(picture, posts: (0.108, 0.912), height: 16, alongColumns: false)
        let up = CGVector(dx: 0, dy: WorldMap.terraceHeight)
        for terrace in map.terraces {
            let o = terrace.origin
            let last = GridPoint(col: o.col + terrace.width - 1, row: o.row + terrace.height - 1)
            // Railings and pillars on the border ring, up on the top; the stairs stay open.
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
                    // Railings follow the edge they're on.
                    if !corner, col == o.col || col == last.col { node.xScale = -1 }
                    node.zPosition = -map.base(of: cell).y
                    chunk(at: node.position).addChild(node)
                }
            }
        }
    }

    private func placeNPCs() {
        for npc in def.npcs ?? [] {
            let cell = map.spot(of: npc)
            map.occupy(cell, blocking: true)
            let node = Walker(cycle: art.walkCycle(npc.art), label: npc.name)
            node.idles = npc.role != .chest
            node.tagMode = .onDemand
            if npc.role == .boss { node.motion = IdleMotion.of(art: npc.art) }
            node.position = map.center(of: cell)
            node.zPosition = -node.position.y
            // Quest "!" / "?" in the same style as the names in battle, big enough to spot from afar.
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
        updateNotices()
    }

    /// The people who live here (`MapDef.Local`): where each lives and walks to, their things set
    /// down around home and home kept clear of scenery, for the crowd to bring them to life.
    private func placeLocals() -> [Crowd.Local] {
        var placed: [Crowd.Local] = []
        for (index, local) in (def.locals ?? []).enumerated() {
            guard let home = map.spot(of: local.home) else { continue }
            for prop in local.props ?? [] {
                let cell = GridPoint(col: home.col + prop.x, row: home.row + prop.y)
                let blocking = prop.blocking ?? true
                guard cell != home, map.isFreeForScenery(cell, insideFence: true, blocking: blocking) else { continue }
                map.occupy(cell, blocking: blocking)
                addScenery(art.sprite(prop.art), at: cell)
            }
            map.occupy(home, blocking: false)
            let walk = local.walk.flatMap { map.spot(of: $0) }
            placed.append(Crowd.Local(def: local, index: index, home: home, walk: walk))
        }
        return placed
    }

    /// Boulders on the slopes of rocky hills (`WorldMap.rockiness`), the more the rockier: the
    /// map's own rocks (its props named for a boulder or rock), on the steeper cells, off the trails.
    /// Grassy hills on the gentlest maps get none.
    private func placeOutcrops() {
        let rocky = map.rockiness
        guard rocky >= 0.3, !map.hills.isEmpty else { return }
        var kinds = def.theme.props.map(\.art).filter { $0.contains("boulder") || $0.hasSuffix("rock") }
        if kinds.isEmpty { kinds = ["boulder", "small_boulder"] }
        var rocks = SeededRandom(text: def.id + "/outcrops")
        for hill in map.hills {
            for cell in hill.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                guard map.rise(across: cell) >= 6, map.isFreeForScenery(cell),
                      Double.random(in: 0..<1, using: &rocks) < 0.08 * rocky else { continue }
                let sprite = art.sprite(kinds[Int.random(in: 0..<kinds.count, using: &rocks)])
                map.occupy(cell, blocking: true)
                addScenery(sprite, at: cell, jitter: true, scale: CGFloat.random(in: 0.7...1.1, using: &rocks))
            }
        }
    }

    /// Scenery from the theme. Props with `cluster` grow in groves around a random centre. None
    /// past the lines the land meets the lands beside it along (`WorldMap.foreign`), where theirs
    /// grows (`placeSeamProps`).
    private func placeProps() async {
        for placement in def.theme.props {
            let sprite = art.sprite(placement.art)
            let groupSize = max(1, placement.cluster ?? 1)
            let spread = max(1, placement.spread ?? Int(Double(groupSize).squareRoot().rounded()) + 1)
            var placed = 0
            var attempts = 0
            while placed < placement.count, attempts < placement.count * 3 {
                attempts += 1
                await breathe()
                let found: GridPoint? = if let radius = placement.within {
                    map.randomFreeCell(within: radius, using: &rng)
                } else {
                    map.randomFreeCell(blocking: placement.blocking, using: &rng)
                }
                guard let middle = found else { break }
                let wanted = min(groupSize, placement.count - placed)
                var inGroup = 0
                for index in 0..<(wanted * 5) where inGroup < wanted {
                    let cell = index == 0 ? middle : GridPoint(
                        col: middle.col + Int.random(in: -spread...spread, using: &rng),
                        row: middle.row + Int.random(in: -spread...spread, using: &rng)
                    )
                    guard map.isFreeForScenery(cell, insideFence: placement.within != nil, blocking: placement.blocking),
                          map.foreign[cell] == nil else { continue }
                    var scale: CGFloat = 1
                    if let range = placement.size, range.count == 2, range[0] <= range[1] {
                        scale = CGFloat(Double.random(in: range[0]...range[1], using: &rng))
                    }
                    plant(sprite, placement, at: cell, scale: scale)
                    inGroup += 1
                }
                placed += inGroup
            }
        }
    }

    /// Past the lines the land meets the lands beside it along (`Seam`), where their ground has come
    /// over onto this one, their scenery (graded as it is there), as thick as it grows there, so the
    /// woods and the meadows run on over the line as the ground does.
    private func placeSeamProps() async {
        guard !map.foreign.isEmpty else { return }
        var random = SeededRandom(text: def.id + "/seams")
        var sprites: [String: SpriteArt] = [:]
        let lands = map.seams.map { Content.shared.map($0.neighbour) }
        for (number, cell) in map.foreign.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }).enumerated() {
            if number % 8 == 7 { await breathe() }
            guard let seam = map.foreign[cell], let land = lands[seam] else { continue }
            let area = Double(land.width * land.height)
            for placement in land.theme.props where placement.within == nil {
                guard Double.random(in: 0..<1, using: &random) < Double(placement.count) / area else { continue }
                guard map.isFreeForScenery(cell, blocking: placement.blocking) else { break }
                let key = land.id + "|" + placement.art
                let sprite: SpriteArt
                if let known = sprites[key] {
                    sprite = known
                } else {
                    let own = art.sprite(placement.art)
                    let texture = art.gradedTile(placement.art, palette: land.theme.palette).map { image -> SKTexture in
                        let made = SKTexture(cgImage: image)
                        made.filteringMode = .nearest
                        return made
                    } ?? own.texture
                    sprite = SpriteArt(texture: texture, size: own.size)
                    sprites[key] = sprite
                }
                var scale: CGFloat = 1
                if let range = placement.size, range.count == 2, range[0] <= range[1] {
                    scale = CGFloat(Double.random(in: range[0]...range[1], using: &random))
                }
                plant(sprite, placement, at: cell, scale: scale)
                break
            }
        }
    }

    /// Sets a prop down at `cell` as its placement says: taking the cell, swaying, bobbing, with its
    /// shadow and its glow.
    private func plant(_ sprite: SpriteArt, _ placement: MapDef.PropPlacement, at cell: GridPoint, scale: CGFloat) {
        map.occupy(cell, blocking: placement.blocking)
        let node = addScenery(sprite, at: cell, sway: placement.sway == true, jitter: true, scale: scale)
        if placement.bob == true {
            // Unseeded, so the map's layout stays what it was.
            let rise = SKAction.moveBy(x: 0, y: 3, duration: .random(in: 1.3...2))
            rise.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([rise, rise.reversed()])), withKey: "bob")
        }
        if placement.shadow == true {
            if map.hillIndex(at: cell) != nil {
                // On a hill, over the strip it stands on, and over the two in front where
                // it reaches them (`HillArt.strip(at:)`): each from where it begins on
                // screen, under it.
                let strip = HillArt.strip(at: -node.zPosition)
                let layers: [(from: CGFloat, z: CGFloat)] = (0..<3).map { step in
                    let start = strip.start - CGFloat(step) * HillArt.stripHeight
                    return (from: start + map.height(at: CGPoint(x: node.position.x, y: start)),
                            z: strip.z + CGFloat(step) * HillArt.stripHeight)
                }
                shadows.append(Lighting.Shadow(under: node, in: chunk(at: node.position), layers: layers))
            } else {
                shadows.append(Lighting.Shadow(under: node, in: chunk(at: node.position)))
            }
        }
        if let hex = placement.glow, let color = UIColor(hex: hex) {
            Lighting.glow(behind: node, color: color, in: chunk(at: node.position), rng: &rng)
            lantern?.glint(at: node.position + CGVector(dx: 0, dy: node.size.height * 0.4), color: color, width: node.size.width * 1.6)
        }
    }

    /// Hand-placed decorations (fountains, blossom trees) from the map's `decor` list.
    private func placeDecor() {
        for decor in def.decor ?? [] {
            let anchor = map.spot(x: decor.x, y: decor.y, summit: decor.summit)
            let sprite = art.sprite(decor.art)
            let blocking = decor.blocking ?? true
            let footprint = max(1, Int(sprite.size.width / WorldMap.tileSize * 0.75))
            for dc in 0..<footprint {
                map.occupy(GridPoint(col: anchor.col + dc - footprint / 2, row: anchor.row), blocking: blocking)
            }
            addScenery(sprite, at: anchor, sway: decor.art.contains("tree") || decor.art.contains("flower"))
            if decor.art.contains("fountain") {
                let sparkle = map.center(of: anchor) + CGVector(dx: 0, dy: 30)
                Ambience.twinkle(around: sparkle, radius: 30, count: 4, in: chunk(at: sparkle))
            }
        }
    }

    /// Circles of mushrooms with a sparkle in the middle, like the ones fairies dance in.
    private func placeFairyRings() {
        guard let rings = def.theme.fairyRings else { return }
        let sprite = art.sprite(rings.art)
        for _ in 0..<rings.count {
            for _ in 0..<30 {
                guard let middle = map.randomFreeCell(using: &rng) else { break }
                let area = (-2...2).flatMap { dr in (-2...2).map { dc in GridPoint(col: middle.col + dc, row: middle.row + dr) } }
                guard area.allSatisfy({ map.isFreeForScenery($0) && map.height(at: map.center(of: $0)) == 0 }) else { continue }
                area.forEach { map.occupy($0, blocking: false) }
                let origin = map.center(of: middle)
                for index in 0..<9 {
                    let angle = CGFloat(index) / 9 * 2 * .pi
                    let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * 0.75)
                    node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                    node.position = origin + CGVector(dx: cos(angle) * 52, dy: sin(angle) * 36)
                    node.zPosition = -node.position.y
                    chunk(at: origin).addChild(node)
                }
                Ambience.twinkle(around: origin, radius: 26, count: 5, in: chunk(at: origin))
                break
            }
        }
    }

    private func placeLilyPads() {
        // Frozen ponds and chocolate ones don't grow lily pads.
        let water = def.theme.water ?? ""
        guard !water.contains("ice"), !water.contains("chocolate") else { return }
        let sprite = art.sprite("lily_pad")
        var padRNG = SeededRandom(text: def.id + "/lilies")
        for pond in map.ponds {
            // A few on a pond, more on a lake.
            for _ in 0..<min(max(4, pond.count / 60), max(1, pond.count / 8)) {
                guard let cell = pond.randomElement(using: &padRNG), !map.bridgeCells.contains(cell) else { continue }
                let node = SKSpriteNode(texture: sprite.texture, size: sprite.size)
                node.position = map.center(of: cell) + CGVector(dx: .random(in: -6...6, using: &padRNG), dy: .random(in: -6...6, using: &padRNG))
                node.zPosition = -99_000
                node.run(.repeatForever(.sequence([
                    .rotate(toAngle: 0.08, duration: 2.2, shortestUnitArc: true),
                    .rotate(toAngle: -0.08, duration: 2.2, shortestUnitArc: true),
                ])))
                chunk(at: node.position).addChild(node)
            }
        }
    }

    /// The bridges' posts and rails (`BridgeArt`; their decks lie with the ground, `makeGround`).
    private func placeBridges() {
        guard !map.bridges.isEmpty else { return }
        let pixels = art.tileTexture(def.theme.ground).cgImage().width
        for bridge in map.bridges {
            BridgeArt.rails(for: bridge, pixels: pixels, palette: def.theme.palette, in: world)
            // Nothing grows right beside a deck either, on the bank its planks and rails reach over,
            // where a fern or a tree would stand on the bridge.
            for cell in bridge.cells {
                for dc in -1...1 {
                    for dr in -1...1 { map.occupy(GridPoint(col: cell.col + dc, row: cell.row + dr), blocking: false) }
                }
            }
        }
    }

    /// Reeds here and there along the lakes' and the river's shores, where the water isn't frozen
    /// or chocolate.
    private func placeReeds() {
        let water = def.theme.water ?? ""
        guard !water.contains("ice"), !water.contains("chocolate"), !map.lakes.isEmpty || !map.river.isEmpty else { return }
        let sprite = art.sprite("reeds")
        var reedRNG = SeededRandom(text: def.id + "/reeds")
        var seen: Set<GridPoint> = []
        for shore in map.lakes.map({ $0.water }) + [map.river] {
            for cell in shore.sorted(by: WorldMap.inOrder) {
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let land = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    guard map.contains(land), map.ground[land.row][land.col] != .water, seen.insert(land).inserted else { continue }
                    guard Double.random(in: 0..<1, using: &reedRNG) < 0.12, map.isFreeForScenery(land, blocking: false) else { continue }
                    map.occupy(land, blocking: false)
                    addScenery(sprite, at: land, jitter: true, scale: CGFloat.random(in: 0.75...1, using: &reedRNG))
                }
            }
        }
    }

    /// A small sign where each road leaves the map.
    private func placeSignposts() {
        for exit in def.exits {
            guard let destination = Content.shared.map(exit.to) else { continue }
            let text = switch exit.edge {
            // Arrows follow the road on screen: north runs up-left, east up-right.
            case .north: "↖ \(destination.name)"
            case .south: "\(destination.name) ↘"
            case .east: "\(destination.name) ↗"
            case .west: "↙ \(destination.name)"
            }
            // A wooden signpost beside the road. Its words only show when you walk up and tap it.
            let cell = signCell(near: exit.edge) ?? map.entryCell(from: exit.edge)
            let post = addScenery(art.sprite("signpost"), at: cell, scale: 1.6)
            if map.isWalkable(cell) { map.occupy(cell, blocking: true) }
            let top = map.base(of: cell) + CGVector(dx: 0, dy: post.size.height + 4)
            let label = NameTag(text, color: Nodes.gold, size: 12)
            label.position = top + CGVector(dx: 0, dy: 4)
            label.zPosition = 6_000
            label.alpha = 0
            world.addChild(label)
            // A little "?" bobs over it while you're close enough to read it.
            let hint = NameTag("?", color: Nodes.gold, size: 16)
            hint.position = top
            hint.zPosition = 6_000
            hint.isHidden = true
            hint.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.4), .moveBy(x: 0, y: -4, duration: 0.4)])))
            world.addChild(hint)
            signs.append(Signpost(text: text, base: map.base(of: cell), label: label, hint: hint))
        }
    }

    /// A signpost by the road out, and the destination written on it.
    private struct Signpost {
        let text: String
        let base: CGPoint
        let label: NameTag
        let hint: NameTag
    }
    private var signs: [Signpost] = []
    /// A signpost you tapped from afar: read it once you get there.
    private var signTarget: Int?
    private let signRange: CGFloat = 90

    /// Shows what a signpost says for a few seconds, and notes it in the log.
    private func read(_ sign: Signpost) {
        sign.label.removeAllActions()
        sign.label.run(.sequence([.fadeIn(withDuration: 0.15), .wait(forDuration: 4), .fadeOut(withDuration: 0.4)]))
        session.post(L("The sign reads: {text}", ["text": sign.text]))
        SoundEffects.shared.play(.talk, volume: 0.5)
    }

    /// A free cell just off the side of the road, a few tiles in from `edge`, for its signpost.
    private func signCell(near edge: Edge, depth: Int = 4) -> GridPoint? {
        let line: [GridPoint] = switch edge {
        case .north: (0..<map.columns).map { GridPoint(col: $0, row: map.rows - 1 - depth) }
        case .south: (0..<map.columns).map { GridPoint(col: $0, row: depth) }
        case .east: (0..<map.rows).map { GridPoint(col: map.columns - 1 - depth, row: $0) }
        case .west: (0..<map.rows).map { GridPoint(col: depth, row: $0) }
        }
        let road = line.indices.filter { map.contains(line[$0]) && map.ground[line[$0].row][line[$0].col] == .path }
        guard let first = road.first, let last = road.last else { return nil }
        for index in [first - 1, last + 1, first - 2, last + 2] where line.indices.contains(index) {
            let cell = line[index]
            if map.isWalkable(cell), map.ground[cell.row][cell.col] != .water { return cell }
        }
        return nil
    }

    /// What walls the land's borders with the lands next door (`BorderArt`): a town's city wall, and
    /// fences or boulders where you can't cross yet, with a quest's barred gate. Roads off the
    /// continent (out of a cave) a quest hasn't opened yet get a barricade across them instead
    /// (`placeBarricades`).
    private func placeBorders() {
        for neighbour in neighbours where neighbour.isWalled(done: session.hasCompleted, joined: isJoined(neighbour)) {
            let open = neighbour.quest.map(session.hasCompleted) ?? false
            let columns = map.columns, rows = map.rows
            let dry = { [unowned self] (along: Int) -> Bool in
                let line: (inside: GridPoint, outside: GridPoint) = switch neighbour.edge {
                case .east: (GridPoint(col: columns - 1, row: along), GridPoint(col: columns, row: along))
                case .west: (GridPoint(col: 0, row: along), GridPoint(col: -1, row: along))
                case .north: (GridPoint(col: along, row: rows - 1), GridPoint(col: along, row: rows))
                case .south: (GridPoint(col: along, row: 0), GridPoint(col: along, row: -1))
                }
                return !self.map.isOpenSea(line.inside) && !self.map.isOpenSea(line.outside)
            }
            let bar = BorderArt.place(neighbour, of: def, open: open, art: art, dry: dry) { [unowned self] in self.chunk(at: $0) }
            if !bar.isEmpty { gates.append((neighbour, bar)) }
        }
        placeBarricades()
    }

    /// Walls that come down once you can cross (`BorderArt.place`): the border, and what's taken
    /// away (a town's gate's bar, or the whole fence).
    private var gates: [(neighbour: Continent.Neighbour, bar: [SKNode])] = []

    /// Whether the roads you can take join this land to a land next door (`Continent.joined`), by
    /// its id: worked out when it's wanted, and again after a quest (`openBarricades`).
    private var joinedLands: [String: Bool] = [:]

    private func isJoined(_ neighbour: Continent.Neighbour) -> Bool {
        if let known = joinedLands[neighbour.def.id] { return known }
        let joined = Continent.joined(def.id, neighbour.def.id, done: session.hasCompleted)
        joinedLands[neighbour.def.id] = joined
        return joined
    }

    /// A fence across each road off the continent that a quest hasn't opened yet, with a little lock sign.
    private func placeBarricades() {
        for exit in def.exits where !session.canTravel(exit) {
            // On the continent, the border's gate does this (`placeBorders`).
            guard Continent.origin(of: def) == nil || Content.shared.world[exit.to] == nil else { continue }
            let cells = map.roadCells(near: exit.edge)
            guard !cells.isEmpty else { continue }
            var nodes: [SKNode] = []
            // The pickets slanted along the line across the road, a picture a cell, like the town
            // fence: set down upright, a cell at a time, they'd stand in a jumble on the diagonal.
            let acrossColumns = exit.edge == .north || exit.edge == .south
            guard let rail = TownFence.railing(art.sprite("fence").texture.cgImage(), posts: (0, 1), height: 21,
                                               alongColumns: acrossColumns) else { continue }
            for cell in cells {
                let node = SKSpriteNode(texture: rail.texture, size: rail.size)
                node.anchorPoint = rail.anchor
                node.position = map.center(of: cell)
                node.zPosition = -node.position.y
                world.addChild(node)
                nodes.append(node)
            }
            let middle = cells[cells.count / 2]
            let sign = SKLabelNode()
            sign.attributedText = Nodes.outlined(L("Closed"), size: 12, color: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1))
            // Over the pickets, clear of a town's gate arch just inside them.
            sign.position = map.center(of: middle) + CGVector(dx: 0, dy: map.fenceCells.isEmpty ? 34 : 62)
            sign.zPosition = 4_500
            sign.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.6), .moveBy(x: 0, y: -3, duration: 0.6)])))
            world.addChild(sign)
            nodes.append(sign)
            barricades.append((exit, nodes, Set(cells)))
        }
    }

    /// A finished quest opened a road while you were here: the barricade, the bar across the
    /// border's gate, or a fence along a border you can cross now, poofs away (next door too, where
    /// the same wall shows).
    private func openBarricades() {
        joinedLands = [:]
        barricades.removeAll { barricade in
            guard session.canTravel(barricade.exit) else { return false }
            for node in barricade.nodes {
                SkillEffects.smoke(at: node.position, in: world)
                node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
            return true
        }
        gates.removeAll { gate in
            let neighbour = gate.neighbour
            let opened = neighbour.town ? neighbour.quest.map(session.hasCompleted) ?? false
                : !neighbour.isWalled(done: session.hasCompleted, joined: isJoined(neighbour))
            guard opened else { return false }
            for node in gate.bar {
                if let parent = node.parent { SkillEffects.smoke(at: node.position, in: parent) }
                node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
            return true
        }
        for land in nextDoor.values { land.scene.openBarricades() }
    }

    @discardableResult
    private func addScenery(_ sprite: SpriteArt, at cell: GridPoint, sway: Bool = false, jitter: Bool = false, scale: CGFloat = 1) -> SKSpriteNode {
        let node = SKSpriteNode(texture: sprite.texture, size: CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale))
        node.anchorPoint = CGPoint(x: 0.5, y: min(0.5, 0.05 + foot(of: sprite.texture)))
        var position = map.base(of: cell)
        if jitter {
            // Nudge off the grid so groves look planted by nature, not a spreadsheet.
            position.x += .random(in: -7...7, using: &rng)
            position.y += .random(in: -5...5, using: &rng)
        }
        // Standing on raised ground (a hilltop, a terrace) it's drawn up there, sorted by its spot.
        let ground = position.y
        position.y += map.height(at: map.center(of: cell))
        node.position = position
        node.zPosition = -ground
        shade(node, standingOn: cell)
        if sway {
            let duration = TimeInterval.random(in: 1.8...2.8, using: &rng)
            let lean = CGFloat.random(in: 0.018...0.03, using: &rng)
            let left = SKAction.rotate(toAngle: lean, duration: duration, shortestUnitArc: true)
            let right = SKAction.rotate(toAngle: -lean, duration: duration, shortestUnitArc: true)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            node.zRotation = .random(in: -lean...lean, using: &rng)
            node.run(.repeatForever(.sequence([left, right])))
        }
        chunk(at: node.position).addChild(node)
        focus.add(node)
        return node
    }

    // MARK: - Chunks

    /// Scenery in square pieces of the screen-space map (`chunk(at:)`), only those near the camera in
    /// the scene (`showChunks`): a wooded map's thousands of trees, their shadows, glows and sways
    /// cost nothing while they're out of sight (launch audit: 10-12k nodes, a few hundred on screen).
    private var chunks: [GridPoint: SKNode] = [:]
    /// The span of chunks around the camera now in the scene, until the camera moves into another.
    private var shownChunks: (low: GridPoint, high: GridPoint)?
    private static let chunkSize: CGFloat = 400
    /// How far past the screen's edges a chunk is kept: scenery stands up from where it's rooted
    /// (a mountain's trees as high as its summits), and long shadows reach out from it.
    private static let chunkMargin: CGFloat = 360

    /// The piece of the map holding scenery at `position` (where it's drawn).
    private func chunk(at position: CGPoint) -> SKNode {
        let key = GridPoint(col: Int((position.x / Self.chunkSize).rounded(.down)), row: Int((position.y / Self.chunkSize).rounded(.down)))
        if let known = chunks[key] { return known }
        let node = SKNode()
        node.name = "chunk"
        chunks[key] = node
        // Shown (or not) when the chunks are looked at next.
        shownChunks = nil
        return node
    }

    /// Puts the chunks near the camera in the scene and takes the rest out (their actions wait).
    private func showChunks() {
        showChunks(around: cam.position, scale: cam.xScale, screen: size)
    }

    /// The same for a camera at `camera` (in this land's points) showing `screen` at `scale`: this
    /// land's own, or the land you're in looking over the border.
    private func showChunks(around camera: CGPoint, scale: CGFloat, screen: CGSize) {
        let reach = CGSize(width: screen.width / 2 * scale + Self.chunkMargin, height: screen.height / 2 * scale + Self.chunkMargin)
        func key(_ x: CGFloat, _ y: CGFloat) -> GridPoint {
            GridPoint(col: Int((x / Self.chunkSize).rounded(.down)), row: Int((y / Self.chunkSize).rounded(.down)))
        }
        let low = key(camera.x - reach.width, camera.y - reach.height)
        let high = key(camera.x + reach.width, camera.y + reach.height)
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
        focus.refocus()
    }

    private var feet: [ObjectIdentifier: CGFloat] = [:]

    /// How lit a cave's range is turned from the sun (`HillArt.Look.ambient`): deeper shade than
    /// other hills, so a mountain's shape shows.
    private static let cragShade = 0.25

    /// Scenery on a hill, with how the ground under it rises a cell across and up the map (as
    /// `HillArt.sunlight` takes it) and how lit it is there turned from the midday sun: shaded
    /// with that ground as the sun moves (`follow(_:)`).
    private var onSlopes: [(node: SKSpriteNode, hx: Double, hy: Double, ambient: Double)] = []

    /// Shades scenery standing on a hill with the ground there, by the sun (`Self.shade`).
    private func shade(_ node: SKSpriteNode, standingOn cell: GridPoint) {
        guard let index = map.hillIndex(at: cell) else { return }
        let hill = map.hills[index]
        let x = Double(cell.col) + 0.5, y = Double(cell.row) + 0.5, e = 0.25
        let gx = Double(hill.height(atCells: x + e, y) - hill.height(atCells: x - e, y)) / (2 * e)
        let gy = Double(hill.height(atCells: x, y + e) - hill.height(atCells: x, y - e)) / (2 * e)
        let tile = Double(WorldMap.tileSize)
        // The same light as the ground's (`HillArt.sprites`), crags and mountains in their deeper
        // shade.
        let ambient = hill.isCrag || hill.hasMountain ? Self.cragShade : HillArt.ambient(rocky: map.rockiness)
        let spot = (node: node, hx: gx / tile / 0.866, hy: gy / tile / 0.866, ambient: ambient)
        onSlopes.append(spot)
        Self.shade(spot.node, hx: spot.hx, hy: spot.hy, ambient: spot.ambient, sun: sunShown ?? .noon)
    }

    /// Darkens scenery on a hill's shaded side with the ground there (`HillArt.sunlight`): by most
    /// of the ground's shade (60%) where the sun only grazes the slope, since it stands up into the
    /// light, and by all of it where the slope turns its back on the sun, in the hill's own shadow.
    /// A slope facing the sun leaves it as it is.
    private static func shade(_ node: SKSpriteNode, hx: Double, hy: Double, ambient: Double, sun: Sun) {
        let light = HillArt.sunlight(hx: hx, hy: hy, ambient: ambient, sun: sun)
        guard light.shade < 1 else {
            node.colorBlendFactor = 0
            return
        }
        let shadowed = min(1, max(0, (0.15 - light.lambert) / 0.15))
        node.color = .black
        node.colorBlendFactor = CGFloat((1 - light.shade) * (0.6 + 0.4 * shadowed))
    }

    /// Shadows cast by scenery (`Lighting.Shadow`), turned with the sun.
    private var shadows: [Lighting.Shadow] = []
    /// The sun the map is lit by now (`follow(_:)`), and how long until it's looked at again.
    private var sunShown: Sun?
    private var sunTimer: TimeInterval = 0

    /// Lights the map by where the sun is (`Sky.sun`; midday in a cave): its hills shaded and the
    /// scenery on them, shadows cast away from it, its flare and beams turned toward it.
    private func follow(_ sun: Sun) {
        guard sun != sunShown else { return }
        sunShown = sun
        HillArt.light(raisedHills, by: sun)
        for shadow in shadows { shadow.fall(from: sun) }
        // Everyone standing on the map casts theirs the same way, and anyone set down later too.
        Walker.sun = sun
        for case let walker as Walker in world.children { walker.cast(from: sun) }
        for spot in onSlopes { Self.shade(spot.node, hx: spot.hx, hy: spot.hy, ambient: spot.ambient, sun: sun) }
        lighting?.follow(sun)
        // The lands next door are under the same sun.
        for land in nextDoor.values { land.scene.follow(sun) }
    }

    /// How far up its image a sprite's lowest opaque pixel sits (0...1). Scenery is anchored there,
    /// so a log or cactus drawn with empty rows under it stands on its cell instead of floating
    /// above it, where it looked like it was behind the ground in front of it.
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

    /// On a dark map, notes the cells your light has fallen on, for the minimap.
    private func explore() {
        guard let lantern else { return }
        let here = map.cell(at: player.position)
        let reach = lantern.radius * 0.85
        // Neighbouring cells' centres are at least 31 points apart on screen.
        let span = Int(reach / 31) + 2
        var cells: [GridPoint] = []
        for row in (here.row - span)...(here.row + span) {
            for col in (here.col - span)...(here.col + span) {
                let cell = GridPoint(col: col, row: row)
                if map.contains(cell), map.center(of: cell).distance(to: player.position) <= reach {
                    cells.append(cell)
                }
            }
        }
        session.explore(cells, on: def.id, columns: map.columns, rows: map.rows)
    }

    /// Everyone else on this map, for the minimap: the adventurers walking about, the folk who live
    /// here and the friends in your party (behind you, or waiting where you left them). On a dark
    /// map, only those standing somewhere you've seen.
    private func minimapDots() -> [GameSession.MinimapDot] {
        let friends = Set(session.friends.map(\.id))
        let seen = seenCells()
        func dot(at point: CGPoint, _ kind: GameSession.MinimapDot.Kind) -> GameSession.MinimapDot? {
            let cell = map.cell(at: point)
            return seen(cell) ? GameSession.MinimapDot(cell: cell, kind: kind) : nil
        }
        let walkers = (crowd?.adventurerPositions ?? []).compactMap { profile, position in
            dot(at: position, profile.hostile ? .hostile : friends.contains(profile.id) ? .friend : .adventurer)
        }
        let folk = (crowd?.folkPositions ?? []).compactMap { dot(at: $0, .folk) }
        return folk + walkers + allies.compactMap { dot(at: $0.node.position, .party) }
    }

    /// Who does what on this map, for the minimap's icons: the quest givers (a quest for you, or one
    /// to hand in, as their "!" and "?" say), the healer, the shop, the smith, the guilds, a chest
    /// still to open and a boss still to beat. On a dark map, only where you've been.
    private func minimapMarks() -> [GameSession.MinimapMark] {
        let seen = seenCells()
        return npcs.compactMap { npc -> GameSession.MinimapMark? in
            let cell = map.cell(at: npc.node.position)
            guard !npc.node.isHidden, seen(cell) else { return nil }
            let kind: GameSession.MinimapMark.Kind
            switch npc.def.role {
            case .healer: kind = .healer
            case .shop: kind = .shop
            case .smith: kind = .smith
            case .guild: kind = .guild
            case .boss: kind = .boss
            case .chest:
                guard !session.isOpened(npc.def.id) else { return nil }
                kind = .chest
            case .quests:
                switch session.notice(for: npc.def.id) {
                case .ready?: kind = .questReady
                case nil: kind = .quest
                default: kind = .questNew
                }
            }
            return GameSession.MinimapMark(cell: cell, kind: kind)
        }
    }

    /// Whether you've seen a cell (on a dark map, as the minimap shows it; everywhere elsewhere).
    private func seenCells() -> (GridPoint) -> Bool {
        guard lantern != nil else { return { _ in true } }
        let seen = session.explored(def.id) ?? Data()
        return { cell in
            let index = cell.row * self.map.columns + cell.col
            return index / 8 < seen.count && seen[index / 8] & UInt8(1 << (index % 8)) != 0
        }
    }

    /// The HUD's minimap. On a dark map it shows only the cells you've seen; `version` is the
    /// session's count of new sightings (`exploredVersion`), so it's redrawn as you explore.
    func minimapImage(explored version: Int) -> UIImage {
        guard lantern != nil else { return minimap }
        if let fogged, fogged.version == version { return fogged.image }
        let image = Self.fog(minimap, seen: session.explored(def.id), columns: map.columns, rows: map.rows)
        fogged = (version, image)
        return image
    }

    /// The minimap and what's round the land, `margin` cells out each way (`origin` is its south-west
    /// cell, in this land's cells).
    struct MinimapPicture {
        let image: UIImage
        let origin: GridPoint
        let columns: Int
        let rows: Int
    }

    /// The HUD's minimap with everything round the land, so it shows past the edges too: the lands
    /// nearby as their own minimaps show them (`WorldOverview`; a dark one only where you've seen)
    /// and the sea between. Round a cave, its gloom. `overviews`: how many lands `WorldOverview` has
    /// drawn, so it's drawn again as more come in.
    func minimapPicture(explored version: Int, overviews: Int) -> MinimapPicture {
        if let surrounded, surrounded.version == version, surrounded.overviews == overviews { return surrounded.picture }
        let margin = 40
        let columns = map.columns + margin * 2, rows = map.rows + margin * 2
        let own = minimapImage(explored: version)
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return MinimapPicture(image: own, origin: .init(col: 0, row: 0), columns: map.columns, rows: map.rows) }
        context.interpolationQuality = .none
        let onContinent = Continent.origin(of: def) != nil
        let sea = WorldMap.seaColor
        if onContinent {
            context.setFillColor(red: CGFloat(sea.r) / 255, green: CGFloat(sea.g) / 255, blue: CGFloat(sea.b) / 255, alpha: 1)
        } else {
            context.setFillColor(red: 13 / 255, green: 31 / 255, blue: 56 / 255, alpha: 1)
        }
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        let drawn = WorldOverview.shared.images
        var missing = false
        for (land, offset) in Continent.lands(near: def, within: margin) {
            guard var image = drawn[land.id] else {
                // Till it's drawn, its ground's colour: land, not sea.
                missing = true
                let (red, green, blue) = Self.groundColor(of: land, art: art)
                context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                context.fill(CGRect(x: offset.col + margin, y: offset.row + margin, width: land.width, height: land.height))
                continue
            }
            if land.ambience?.darkness != nil,
               let fogged = Self.fog(UIImage(cgImage: image), seen: session.explored(land.id), columns: land.width, rows: land.height).cgImage {
                image = fogged
            }
            context.draw(image, in: CGRect(x: offset.col + margin, y: offset.row + margin, width: land.width, height: land.height))
        }
        // Lands not drawn yet are laid out in the background (once the HUD's drawn), and the
        // minimap's drawn again as they come.
        if missing {
            let first = overviewsFirst
            Task { WorldOverview.shared.prepare(first: first) }
        }
        if let image = own.cgImage { context.draw(image, in: CGRect(x: margin, y: margin, width: map.columns, height: map.rows)) }
        let made = context.makeImage().map { UIImage(cgImage: $0) } ?? own
        let picture = MinimapPicture(image: made, origin: GridPoint(col: -margin, row: -margin), columns: columns, rows: rows)
        surrounded = (version, overviews, picture)
        return picture
    }

    /// `image` with every cell you haven't seen painted the minimap window's own dark blue.
    static func fog(_ image: UIImage, seen: Data?, columns: Int, rows: Int) -> UIImage {
        guard let source = image.cgImage, source.width == columns, source.height == rows,
              let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return image }
        context.draw(source, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        let pixels = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        for row in 0..<rows {
            for col in 0..<columns {
                let index = row * columns + col
                if let seen, index / 8 < seen.count, seen[index / 8] & UInt8(1 << (index % 8)) != 0 { continue }
                // The bitmap's rows run north to south; the grid's count up from the south.
                let pixel = ((rows - 1 - row) * columns + col) * 4
                pixels[pixel] = 13
                pixels[pixel + 1] = 31
                pixels[pixel + 2] = 56
                pixels[pixel + 3] = 255
            }
        }
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output)
    }

    /// One pixel per tile, for the HUD minimap (and the world map, `WorldOverview`).
    private(set) lazy var minimap: UIImage = {
        let image = Self.overview(of: map, art: art)
        if Continent.origin(of: def) != nil { WorldOverview.shared.remember(def.id, image) }
        return UIImage(cgImage: image)
    }()

    /// A map one pixel a cell, in its own (palette-graded) tiles, averaged: a purple wood looks
    /// purple here too. Graded with the map's palette itself: the HUD asks for the minimap as soon as
    /// the scene exists, while the art library still grades for the map you came from (until `build`).
    static func overview(of map: WorldMap, art: ArtLibrary) -> CGImage {
        let palette = map.def.theme.palette
        let waterID = map.def.theme.water ?? "tile_water"
        return map.overviewImage(tileColor: { id in
            let color: (CGFloat, CGFloat, CGFloat)
            if let image = art.gradedTile(id, palette: palette) {
                color = averageColor(of: image)
            } else {
                color = averageColor(of: id == waterID ? art.waterFrames(id).first ?? art.tileTexture(id) : art.tileTexture(id))
            }
            return PixelColor(r: UInt8(color.0 * 255), g: UInt8(color.1 * 255), b: UInt8(color.2 * 255))
        }, foreignColor: { id in
            // A land next door's ground, as it's graded there.
            guard let other = Content.shared.map(id), let image = art.gradedTile(other.theme.ground, palette: other.theme.palette) else { return nil }
            let color = averageColor(of: image)
            return PixelColor(r: UInt8(color.0 * 255), g: UInt8(color.1 * 255), b: UInt8(color.2 * 255))
        })
    }


    // MARK: - Companion

    private var followerKey: String?
    private var heroKey: String?

    /// Keeps the companion in sync: switched, renamed or recoloured. A fainted one stays out of
    /// sight until it's healed.
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
        node.position = previous ?? (canStand(at: beside) ? beside : player.position)
        node.walkSpeed = 110
        world.addChild(node)
        follower = node
    }

    /// Picks up a new look or name from the Character screen, the title you wear, and a reborn
    /// hero's colour.
    private func refreshHero() {
        let key = "\(session.data.hero.name)|\(session.heroLookKey)|\(session.data.title ?? "")|\(session.rebirths)"
        guard key != heroKey else { return }
        if heroKey != nil {
            player.setCycle(art.walkCycle(GameSession.heroArt))
            player.setLabel(session.data.hero.name)
        }
        player.setTitle(session.wornTitle)
        player.setLabelColor(Self.nameColor(rebirths: session.rebirths))
        player.setGear(weapon: session.equipped(.weapon), accessory: session.equipped(.accessory))
        heroKey = key
    }

    /// The hero's name over their head: white, then sky blue, violet and gold as they're reborn.
    static func nameColor(rebirths: Int) -> UIColor {
        switch rebirths {
        case ...0: .white
        case 1: UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1)
        case 2: UIColor(red: 0.82, green: 0.66, blue: 1, alpha: 1)
        default: Nodes.gold
        }
    }


    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBuilt, !isInputLocked, let point = touches.first?.location(in: world) else { return }
        // A boss you've just beaten has gone (hidden) and doesn't answer taps.
        if let npc = npcs.first(where: { !$0.node.isHidden && ($0.node.position + CGVector(dx: 0, dy: 24 + $0.node.lift)).distance(to: point) < 34 }) {
            talkTarget = npc.def.id
            npc.node.revealTag()
            player.path = map.path(from: player.position, to: npc.node.position)
            return
        }
        talkTarget = nil
        signTarget = nil
        // Tapping someone shows who they are and how strong (they turn and say hello first).
        if let profile = profile(at: point) {
            crowd?.greet(at: point, from: player.position)
            player.path = []
            onInspect?(profile)
            return
        }
        // Tapping a signpost reads it, walking over first if it's too far to make out.
        if let index = signs.firstIndex(where: { ($0.base + CGVector(dx: 0, dy: 22)).distance(to: point) < 30 }) {
            if signs[index].base.distance(to: player.position) <= signRange {
                read(signs[index])
                return
            }
            signTarget = index
        }
        crowd?.greet(at: point, from: player.position)
        // A tap over the border, in a land next door: there by the nearest way over, and on to the
        // spot once you're across (`takeOver`). Into one not built yet too: over behind the
        // loading card, where you step across (`cross(into:)`).
        let ground = map.groundPoint(under: point)
        let tapped = map.rawCell(at: ground)
        tapOverBorder = nil
        if !map.contains(tapped), let neighbour = neighbour(holding: tapped), let way = wayOver(to: tapped, into: neighbour) {
            player.path = map.path(from: player.position, to: map.center(of: way.inside)) + [way.over]
            tapOverBorder = ground
            Effects.tapMarker(at: ground, z: -50_000, in: world)
            return
        }
        // A tap on a hilltop means the top, not the ground it hides.
        player.path = map.path(from: player.position, to: ground)
        if let destination = player.path.last {
            Effects.tapMarker(at: destination + CGVector(dx: 0, dy: map.height(at: destination)), z: flatZ(at: destination), in: world)
        }
    }

    /// Where you tapped over the border, in a land next door (in this land's points): the walk
    /// there goes on once you're across.
    private var tapOverBorder: CGPoint?

    /// The way over the border into `neighbour` nearest `cell` (past the edge): the cell on this
    /// side to walk to, and a spot just over the line, where it's open and there's ground to stand.
    private func wayOver(to cell: GridPoint, into neighbour: Continent.Neighbour) -> (inside: GridPoint, over: CGPoint)? {
        let wanted = Continent.place(of: cell, from: neighbour.edge, columns: map.columns, rows: map.rows).along
        func cells(_ along: Int) -> (inside: GridPoint, outside: GridPoint) {
            switch neighbour.edge {
            case .east: (GridPoint(col: map.columns - 1, row: along), GridPoint(col: map.columns, row: along))
            case .west: (GridPoint(col: 0, row: along), GridPoint(col: -1, row: along))
            case .north: (GridPoint(col: along, row: map.rows - 1), GridPoint(col: along, row: map.rows))
            case .south: (GridPoint(col: along, row: 0), GridPoint(col: along, row: -1))
            }
        }
        let open = neighbour.span.filter { along in
            let pair = cells(along)
            return map.isWalkable(pair.inside) && canCross(into: pair.outside)
        }
        guard let along = open.min(by: { abs($0 - wanted) < abs($1 - wanted) }) else { return nil }
        let pair = cells(along)
        return (pair.inside, map.center(of: pair.outside))
    }

    /// How deep something lying flat on the ground at `point` (a tap's swirl) sorts: on a hill, just
    /// over the strip of raised ground it lies on (`HillArt.strip(at:)`), as the scenery's shadows
    /// are, and on a terrace just over its top, or the raised ground drawn over it would hide it;
    /// elsewhere under everything that stands.
    private func flatZ(at point: CGPoint) -> CGFloat {
        let cell = map.cell(at: point)
        if map.hillIndex(at: cell) != nil { return HillArt.strip(at: point.y).z + 0.2 }
        if let plateau = map.plateaus.first(where: { $0.cells.contains(cell) }) { return Self.topZ(of: plateau.cells) + 0.2 }
        return -50_000
    }

    /// Who's standing where you tapped: a friend in your party or their companion, your companion,
    /// or an adventurer on the map (or theirs). Villagers just say hello.
    private func profile(at point: CGPoint) -> Profile? {
        func hit(_ node: SKNode) -> Bool { !node.isHidden && (node.position + CGVector(dx: 0, dy: 24)).distance(to: point) < 30 }
        if let ally = allies.first(where: { ally in hit(ally.node) || ally.pet.map { hit($0) } == true }),
           let friend = session.partyMembers.first(where: { $0.id == ally.id }) {
            return .adventurer(friend)
        }
        if let follower, hit(follower), let pet = session.activePet {
            return .pet(pet.id)
        }
        return crowd?.adventurer(at: point).map { .adventurer($0) }
    }

    /// Keeps the party on this map in sync with who's in it: friends at your side walk behind you,
    /// and friends waiting for you here stand at their spot.
    private func refreshAllies() {
        let members = session.partyMembers.filter { $0.waitingAt == nil || $0.waitingAt?.mapID == def.id }
        // A friend's companion counts too: one they've just caught steps out beside them.
        guard members.map(\.id) != allies.map(\.id) || members.map(\.waitingAt) != allies.map(\.waiting)
                || members.map({ $0.petSpecies != nil }) != allies.map({ $0.pet != nil }) else { return }
        for ally in allies where !members.contains(where: { $0.id == ally.id }) {
            if let friend = session.friends.first(where: { $0.id == ally.id }), !session.isInParty(friend) {
                // Left the party but still a friend: they stay here, so you can invite them back.
                crowd?.rejoin(friend, at: ally.node.position, world: world)
            } else {
                // Gone: unfriended, or off to wait for you on another map.
                SkillEffects.smoke(at: ally.node.position, in: world)
            }
            ally.node.removeFromParent()
            ally.pet?.removeFromParent()
        }
        allies = members.enumerated().map { index, friend in
            if var existing = allies.first(where: { $0.id == friend.id }) {
                // Fainted beside you: off to their checkpoint on this map, to wait for you there.
                if let spot = friend.waitingAt, spot != existing.waiting {
                    SkillEffects.smoke(at: existing.node.position, in: world)
                    move(existing, to: point(for: spot, index: index))
                }
                existing.waiting = friend.waitingAt
                if existing.pet == nil, let pet = companionWalker(of: friend, beside: existing.node) {
                    SkillEffects.smoke(at: pet.position, in: world)
                    existing.pet = pet
                }
                return existing
            }
            // No title over a friend's name: the party walks bunched up, so it would sit on the next one's
            // name. Their card still shows it.
            let node = Walker(cycle: art.walkCycle(session.artID(for: friend)), label: friend.name, labelColor: HUDStyle.partyGreen, badge: .bot)
            node.setGear(weapon: GameSession.weapon(for: friend), accessory: nil)
            node.walkSpeed = 105
            node.tagMode = .whenStill
            if let spot = friend.waitingAt {
                node.position = point(for: spot, index: index)
            } else {
                // Recruited on this map: they start where they stood.
                let beside = player.position + CGVector(dx: -40, dy: -10)
                node.position = crowd?.position(of: friend.id) ?? (canStand(at: beside) ? beside : player.position)
                crowd?.remove(friend.id, poof: false)
            }
            world.addChild(node)
            // Their companion comes along too, at their side.
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
        walker.position = canStand(at: side) ? side : node.position
        world.addChild(walker)
        walker.settle()
        return walker
    }

    /// Puts a friend, and their companion, somewhere else on the map at once.
    private func move(_ ally: Ally, to point: CGPoint) {
        ally.node.position = point
        ally.node.setWalking(false)
        guard let pet = ally.pet else { return }
        let side = point + CGVector(dx: 24, dy: 0)
        pet.position = canStand(at: side) ? side : point
        pet.setWalking(false)
    }

    /// Where a friend waiting for you stands: where they were left (a step apart from the others
    /// there), or their checkpoint's spot, on ground they can stand on.
    private func point(for spot: Spot, index: Int) -> CGPoint {
        var anchor = map.center(of: map.center)
        if let entry = spot.entry { anchor = map.center(of: map.entryCell(from: entry)) }
        if let position = spot.position, position.count == 2 { anchor = CGPoint(x: position[0], y: position[1]) }
        let apart = [CGVector(dx: -36, dy: 10), CGVector(dx: 36, dy: 10), CGVector(dx: -18, dy: -22), CGVector(dx: 18, dy: -22)]
        let wanted = anchor + apart[index % apart.count]
        if canStand(at: wanted) { return wanted }
        if let open = map.nearestWalkable(to: map.cell(at: wanted)) { return map.center(of: open) }
        return anchor
    }

    /// Friends waiting for you set off with you again once you reach them. Not while you can't walk:
    /// after you faint, this map lingers under the loading card with you still where you fell.
    private func rejoinWaitingFriends() {
        guard !isInputLocked else { return }
        for ally in allies where ally.waiting != nil && ally.node.position.distance(to: player.position) < rejoinRange {
            session.rejoin(ally.id)
            ally.node.say([L("There you are!"), L("Let's go!"), L("Back together!")].randomElement() ?? L("Let's go!"))
        }
    }

    /// A duel: the same white flash as a monster encounter.
    func startDuel(with rival: Adventurer) {
        guard !isInputLocked else { return }
        isInputLocked = true
        player.path = []
        player.setWalking(false)
        let flash = SKSpriteNode(color: UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 1), size: size)
        flash.alpha = 0
        flash.zPosition = 50_000
        cam.addChild(flash)
        Task {
            await flash.run(.sequence([.fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1), .fadeAlpha(to: 0.7, duration: 0.1), .fadeAlpha(to: 0, duration: 0.1)]))
            flash.removeFromParent()
            onDuel?(rival, snapshot())
        }
    }

    // MARK: - Homeward Feather

    /// The Homeward Feather's light: a warm white, like sun through a cloud.
    private static let featherLight = UIColor(red: 1, green: 0.95, blue: 0.78, alpha: 1)

    /// A Homeward Feather's arrival (`featherArrive`), the way it's timed; its departure
    /// (`featherAway`) is the same played backward. The hero floats down `height` points over
    /// `drop` seconds, appearing over the first `appear`; the column of light shines `hold` seconds
    /// and then fades over `fade`; `count` feathers spiral down and out, each over `flight` seconds,
    /// one every `stagger`. The whole of it is `length` long (until the last feather settles).
    private enum Feather {
        static let height: CGFloat = 90
        static let drop = 0.85, appear = 0.45
        static let hold = 0.5, fade = 0.6
        static let count = 12
        static let flight = 1.2, stagger = 0.04
        static let length = flight + stagger * Double(count - 1)
    }

    /// A Homeward Feather taking you away: its arrival (`featherArrive`) played backward. A gust
    /// of feathers spirals up and in round you, the column of light shines up out of nothing, and
    /// you rise into it and fade, then `done` (the map changes).
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

    /// What happens once a Homeward Feather has lifted you away (`featherAway`).
    private var onFeatherGone: (() -> Void)?

    /// Before the map shows: the hero isn't here yet (`featherArrive` brings them down).
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

    /// The soft column of light the hero rises into or comes down in.
    private func featherColumn(over point: CGPoint) -> SKSpriteNode {
        let column = SkillEffects.glowSprite(Self.featherLight, size: CGSize(width: 70, height: 230))
        column.position = point + CGVector(dx: 0, dy: 80)
        column.zPosition = 30_000
        world.addChild(column)
        return column
    }

    /// Feathers whirling round `center` as you arrive: spiralling down from high up and out to
    /// settle, one after another. `backward`: the same played backward, as you leave, the last
    /// to settle the first to rise, spiralling up and in.
    private func featherGust(around center: CGPoint, backward: Bool) {
        let texture = ArtLibrary.shared.sprite("item_homeward_feather").texture
        let flight = CGFloat(Feather.flight)
        for index in 0..<Feather.count {
            let feather = SKSpriteNode(texture: texture, size: CGSize(width: 18, height: 18))
            feather.zPosition = 30_001
            feather.alpha = 0
            world.addChild(feather)
            let phase = CGFloat(index) / CGFloat(Feather.count) * 2 * .pi
            let spin = SKAction.customAction(withDuration: Feather.flight) { node, elapsed in
                let t = min(1, elapsed / flight)
                // How far through its arrival it is, and so how high (1 up top, 0 settled).
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

    /// After a duel you won, the rival skulks off.
    func dismissAdventurer(_ id: UUID) {
        crowd?.remove(id, poof: true)
        if session.nearbyAdventurer?.id == id { session.nearbyAdventurer = nil }
    }

    #if DEBUG
    /// Debug launches (`demo`): a monster jumps out right here, just as one does while you walk
    /// the wild (the flash, then the fight on this spot of the map).
    func encounterForDebug() {
        guard !isInputLocked, let encounters = def.encounters else { return }
        stepsSinceBattle = 0
        startEncounter(encounters)
    }

    /// Debug launches (`invite=n`): the nearest friendly adventurers, brought over to stand by you.
    func summonAdventurersForDebug(_ count: Int) -> [Adventurer] {
        crowd?.summonForDebug(count, to: player.position) ?? []
    }

    /// Debug launches (`feather`): a Homeward Feather's lift without going anywhere, the map held
    /// still part-way so a screenshot catches the feathers whirling.
    func featherAwayForDebug() {
        featherAway {}
        run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.isPaused = true }]))
    }

    /// Debug launches (`say=<text>`): a speech bubble over the hero that stays, for screenshots.
    func sayForDebug(_ text: String) {
        player.say(text, for: 600)
    }

    /// Debug launches (`local=n`): the local you start beside tells you the first line of their
    /// story, in a bubble that stays.
    func localTellsForDebug() {
        crowd?.tellForDebug(near: player.position)
    }

    /// Debug launches (`border=<land>,cross`): you walk over the border into that land, on the
    /// stick, as you would (the land next door must be shown already).
    func walkOverForDebug(into id: String) async {
        guard let neighbour = neighbours.first(where: { $0.def.id == id }) else { return }
        let along = neighbour.road ?? (neighbour.span.lowerBound + neighbour.span.upperBound) / 2
        let target = BorderArt.point(along: along, of: neighbour.edge, columns: map.columns, rows: map.rows)
        input.move = (target - player.position).normalized
        try? await Task.sleep(for: .seconds(5))
        input.move = .zero
    }
    #endif

    func adventurerSays(_ line: String, _ id: UUID) {
        crowd?.say(line, from: id)
    }

    /// You said something in the Chat window: a bubble over your head, and maybe an answer.
    func heroSay(_ text: String) {
        player.say(text)
        session.postChat(text, from: session.data.hero.name, kind: .you)
        crowd?.reply(near: player.position)
    }

    /// Called by the HUD's Talk button. Not while a battle's starting (or anything else has the map).
    func talkToNearby() {
        guard !isInputLocked, let id = session.nearbyNPC, let npc = npcs.first(where: { $0.def.id == id }) else { return }
        startTalking(to: npc.def, node: npc.node)
    }

    // MARK: - Next door

    /// Where a land `offset` cells off (its south-west cell, in this land's cells) lies on screen:
    /// add it to that land's points for this one's.
    static func shift(_ offset: GridPoint) -> CGVector {
        let point = WorldMap.project(CGPoint(x: CGFloat(offset.col) * WorldMap.tileSize, y: CGFloat(offset.row) * WorldMap.tileSize))
        return CGVector(dx: point.x, dy: point.y)
    }

    /// The lands next door shown past this one's borders now, by id.
    var shownNextDoor: [String: WorldScene] { nextDoor.mapValues(\.scene) }

    /// The friends visiting this land, who stay here rather than turn up next door as well.
    var visitingFriends: Set<UUID> {
        let friends = Set(session.friends.map(\.id))
        return Set((crowd?.adventurerPositions ?? []).map(\.profile.id).filter(friends.contains))
    }

    /// Shows a land next door, built in the background, past the border: its own layer moved into
    /// this scene, where it lies, sorted in with this land's as if they were one.
    func show(_ land: WorldScene, as neighbour: Continent.Neighbour) {
        guard land.isBuilt, land !== self, nextDoor[land.def.id] == nil else { return }
        let shift = Self.shift(neighbour.offset)
        land.world.removeFromParent()
        land.world.position = CGPoint(x: shift.dx, y: shift.dy)
        land.world.zPosition = -shift.dy
        lands.addChild(land.world)
        nextDoor[land.def.id] = (land, neighbour)
        farLands[land.def.id]?.isHidden = true
        land.follow(sunShown ?? .noon)
    }

    /// Lays the lands round this one flat on the ground as their world map pictures (`farLands`),
    /// those not laid yet. One with no picture yet lies there in its ground's colour till
    /// `WorldOverview` draws it (looked for again every so often, `lookAround`), so there's never
    /// nothing past a border. Not for a land shown next door, nor round a cave.
    private func placeFarLands() {
        guard !isNextDoor, Continent.origin(of: def) != nil else { return }
        let drawn = WorldOverview.shared.images
        var missing = false
        let tile = WorldMap.tileSize
        for (land, offset) in Continent.lands(near: def, within: Self.farReach) where farLands[land.id] == nil || plainLands.contains(land.id) {
            let size = CGSize(width: CGFloat(land.width) * tile, height: CGFloat(land.height) * tile)
            let picture: SKSpriteNode
            if let image = drawn[land.id] {
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .linear
                picture = SKSpriteNode(texture: texture, size: size)
                farLands.removeValue(forKey: land.id)?.removeFromParent()
                plainLands.remove(land.id)
            } else {
                missing = true
                guard farLands[land.id] == nil else { continue }
                let (red, green, blue) = Self.groundColor(of: land, art: art)
                picture = SKSpriteNode(color: UIColor(red: red, green: green, blue: blue, alpha: 1), size: size)
                plainLands.insert(land.id)
            }
            picture.anchorPoint = .zero
            picture.position = CGPoint(x: CGFloat(offset.col) * tile, y: CGFloat(offset.row) * tile)
            let grid = SKNode()
            grid.addChild(picture)
            let layer = projected(grid)
            layer.zPosition = -1_000_000
            layer.isHidden = nextDoor[land.id] != nil
            lands.addChild(layer)
            farLands[land.id] = layer
        }
        farLandsMissing = missing
        if missing { WorldOverview.shared.prepare(first: overviewsFirst) }
    }

    /// The lands whose pictures this one wants first (`WorldOverview.prepare(first:)`): those it
    /// shares a border with, the nearest to you first.
    private var overviewsFirst: [String] {
        let here = map.cell(at: player.position)
        return neighbours
            .map { (id: $0.def.id, distance: $0.distance(from: here, columns: map.columns, rows: map.rows)) }
            .sorted { $0.distance < $1.distance }
            .map(\.id)
    }

    /// A land's ground colour, as it's graded there: what lies past the border till its picture's
    /// drawn (`placeFarLands`, `minimapPicture`).
    static func groundColor(of land: MapDef, art: ArtLibrary) -> (CGFloat, CGFloat, CGFloat) {
        if let known = groundColors[land.id] { return known }
        let color: (CGFloat, CGFloat, CGFloat)
        if let image = art.gradedTile(land.theme.ground, palette: land.theme.palette) {
            color = averageColor(of: image)
        } else {
            color = averageColor(of: art.tileTexture(land.theme.ground))
        }
        groundColors[land.id] = color
        return color
    }

    private static var groundColors: [String: (CGFloat, CGFloat, CGFloat)] = [:]

    /// Takes a land next door away again (too far to see), its layer back in its own scene.
    @discardableResult
    func hide(_ id: String) -> WorldScene? {
        guard let land = nextDoor.removeValue(forKey: id)?.scene else { return nil }
        farLands[id]?.isHidden = false
        land.world.removeFromParent()
        land.world.position = .zero
        land.world.zPosition = 0
        land.lands.addChild(land.world)
        return land
    }

    /// The land next door a cell past this one's edge lies in (built or not), if it's in one.
    private func neighbour(holding cell: GridPoint) -> Continent.Neighbour? {
        neighbours.first { neighbour in
            let local = neighbour.local(cell)
            return local.col >= 0 && local.row >= 0 && local.col < neighbour.def.width && local.row < neighbour.def.height
        }
    }

    /// Whether you can step from inside this land onto `cell`, past its edge: straight across a
    /// border open there, onto ground you can stand on in the land next door (if it's built yet;
    /// if not, the coordinator takes you there behind the loading card as you step).
    private func canCross(into cell: GridPoint) -> Bool {
        guard let neighbour = neighbour(holding: cell) else { return false }
        let place = Continent.place(of: cell, from: neighbour.edge, columns: map.columns, rows: map.rows)
        guard place.inward == -1, neighbour.isOpen(at: place.along, done: session.hasCompleted, joined: isJoined(neighbour)) else { return false }
        // Not built yet: anywhere the sea hasn't come in over its coast (`Coast`).
        guard let land = nextDoor[neighbour.def.id]?.scene else { return !map.isOpenSea(cell) }
        return land.map.isWalkable(neighbour.local(cell))
    }

    /// You've stepped over the border: on into the land next door, there already if it's shown
    /// (`takeOver`, with no loading card), or behind the card if it isn't built yet.
    private func cross(into neighbour: Continent.Neighbour) {
        hasLeft = true
        let land = nextDoor[neighbour.def.id]?.scene
        walkingOver = land != nil
        if land == nil { isInputLocked = true }
        onCross?(neighbour, land, player.position + Self.shift(neighbour.offset) * -1)
    }

    /// Every half second: the lands next door, with how far you are from each one's border, for the
    /// coordinator to build the near ones in the background and show them, and let far ones go.
    private func lookAround() {
        // Not once you've stepped over (this land's on its way to being next door).
        guard !isNextDoor, !hasLeft, let onLandsNear, !neighbours.isEmpty else { return }
        if farLandsMissing { placeFarLands() }
        let here = map.cell(at: player.position)
        let near = neighbours
            .map { (neighbour: $0, distance: $0.distance(from: here, columns: map.columns, rows: map.rows)) }
            .sorted { $0.distance < $1.distance }
        onLandsNear(near)
    }

    /// The lands next door go on while they're shown: their people stroll, their animals mind you
    /// as you come near, and their scenery near the camera is in the scene.
    private func tickNextDoor(_ dt: TimeInterval) {
        for land in nextDoor.values {
            let back = Self.shift(land.neighbour.offset) * -1
            land.scene.carryOn(dt: dt, player: player.position + back, camera: cam.position + back, scale: cam.xScale, screen: size)
        }
    }

    /// One frame of a land next door's life, seen from the land you're in (`tickNextDoor`); the
    /// points are its own.
    private func carryOn(dt: TimeInterval, player point: CGPoint, camera: CGPoint, scale: CGFloat, screen: CGSize) {
        // Its people keep to themselves over there: too far off to hear you or pick a fight.
        crowd?.update(dt: dt, player: CGPoint(x: 1e7, y: 1e7))
        let visible = CGRect(x: camera.x - screen.width / 2 * scale, y: camera.y - screen.height / 2 * scale,
                             width: screen.width * scale, height: screen.height * scale)
        critters?.update(dt: dt, player: point, visible: visible) { self.map.isWalkable(self.map.rawCell(at: $0)) }
        showChunks(around: camera, scale: scale, screen: screen)
        focus.update(camera: camera, halfHeight: screen.height / 2 * scale)
    }

    /// You've walked out over the border: the hero and the friends walking with you leave this
    /// land's layer (it stays on show next door, friends waiting here included), and it waits.
    private func leave() {
        player.removeFromParent()
        player.path = []
        follower?.removeFromParent()
        follower = nil
        followerKey = nil
        for ally in allies where ally.waiting == nil {
            ally.node.removeFromParent()
            ally.pet?.removeFromParent()
        }
        allies.removeAll { $0.waiting == nil }
        talkTarget = nil
        signTarget = nil
        tapOverBorder = nil
        hasLeft = false
        walkingOver = false
        isInputLocked = true
        isNextDoor = true
    }

    /// You've walked over the border into this land from `previous`, where it was shown next
    /// door: it carries on from that very moment, with no loading card. The hero, their companion
    /// and friends, and the camera are where they were; the lands next door to both stay on show;
    /// and `previous` shows next door now in its turn.
    private func takeOver(from previous: WorldScene) {
        guard let back = neighbours.first(where: { $0.def.id == previous.def.id }) else { return }
        // Its points plus this, for mine.
        let shift = Self.shift(back.offset)
        previous.hide(def.id)
        for (id, land) in previous.shownNextDoor {
            previous.hide(id)
            if let neighbour = neighbours.first(where: { $0.def.id == id }) { show(land, as: neighbour) }
        }
        isNextDoor = false
        placeFarLands()
        art.use(palette: def.theme.palette, for: def.id)
        Walker.light = Self.light(of: def)

        if player.parent == nil { world.addChild(player) }
        player.position = previous.player.position + shift
        player.face(previous.player.facing)
        player.path = []
        heroKey = nil
        refreshHero()
        player.relight()
        // Walking on to where you tapped over the border.
        if let tapped = previous.tapOverBorder {
            player.path = map.path(from: player.position, to: tapped + shift)
        }
        let companion = previous.follower.map { (position: $0.position + shift, facing: $0.facing) }
        let party = previous.allies.filter { $0.waiting == nil }.map { (id: $0.id, position: $0.node.position + shift, pet: $0.pet?.position) }
        previous.leave()
        show(previous, as: back)
        refreshFollower()
        if let companion, let follower {
            follower.position = companion.position
            follower.face(companion.facing)
        }
        refreshAllies()
        for (index, ally) in allies.enumerated() {
            guard let was = party.first(where: { $0.id == ally.id }) else { continue }
            allies[index].node.position = was.position
            if let pet = was.pet { allies[index].pet?.position = pet + shift }
        }
        cam.position = previous.cam.position + shift
        lastCell = map.cell(at: player.position)
        stepsSinceBattle = previous.stepsSinceBattle
        hasLeft = false
        isInputLocked = false
        lastUpdate = 0
        // The light and the weather's shade go on from where they were, toward this land's own.
        if let sky, let before = previous.sky { sky.carryOn(from: before) }
        mood = 0
        session.playerPosition = player.position
        session.mapCell = lastCell
        showChunks()
        explore()
        if let sky { follow(sky.sun) }
    }

    // MARK: - Mood

    /// How much of this land's mood shows (`Ambience`, `Lighting`, the weather): all of it inside,
    /// fading out over the last `moodReach` cells toward a border you can walk across, so crossing
    /// into the next land its mood comes in from nothing as this one's went.
    private var mood: CGFloat = 1
    private static let moodReach = 10

    private func updateMood(_ dt: TimeInterval) {
        let here = map.cell(at: player.position)
        var nearest = Self.moodReach
        for neighbour in neighbours where neighbour.isCrossable(done: session.hasCompleted, joined: isJoined(neighbour)) {
            nearest = min(nearest, neighbour.distance(from: here, columns: map.columns, rows: map.rows))
        }
        let t = CGFloat(nearest) / CGFloat(Self.moodReach)
        let goal = t * t * (3 - 2 * t)
        mood += (goal - mood) * (dt == 0 ? 1 : min(1, CGFloat(dt) * 2))
        ambience?.setMood(mood)
        lighting?.setMood(mood)
        sky?.setMood(mood)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        if let onFirstFrame {
            self.onFirstFrame = nil
            onFirstFrame()
        }
        // As much time as has passed, up to an eighth of a second: a frame that comes late (a land
        // next door being built in the background) doesn't slow your walking, and only a long
        // stall (a pause, a menu) skips ahead no more than that.
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 8)
        lastUpdate = currentTime

        if isInputLocked {
            player.setWalking(false)
        } else {
            movePlayer(dt)
            checkTalkTarget()
            checkCell()
        }
        // Companions and friends keep to ground they can stand on, never into water or through a
        // wall. Where their places beside you are blocked, they line up in your footsteps.
        player.markFootstep()
        let standable: (CGPoint) -> Bool = { self.canStand(at: $0) }
        follower?.follow(player, dt: dt, footstep: player.footstep(behind: 36), canStand: standable)
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
                // Waiting for you: they stay put, and turn to watch you come.
                ally.node.face(Direction(player.position - ally.node.position, current: ally.node.facing))
            }
            ally.node.zPosition = -ally.node.position.y
            if let pet = ally.pet { pet.zPosition = -pet.position.y }
        }
        crowd?.update(dt: dt, player: player.position)
        let visible = CGRect(x: cam.position.x - size.width / 2, y: cam.position.y - size.height / 2, width: size.width, height: size.height)
        // The animals keep to their own land.
        critters?.update(dt: dt, player: player.position, visible: visible) { self.map.isWalkable(self.map.rawCell(at: $0)) }
        tickNextDoor(dt)
        noticeTimer -= dt
        if noticeTimer <= 0 {
            noticeTimer = 0.4
            lookAround()
            updateNotices()
            refreshFollower()
            refreshHero()
            rejoinWaitingFriends()
            refreshAllies()
            let nearby = crowd?.adventurer(near: player.position, within: 80)
            if session.nearbyAdventurer?.id != nearby?.id { session.nearbyAdventurer = nearby }
            let around = crowd?.adventurers(near: player.position, within: 320) ?? []
            if session.adventurersAround != around { session.adventurersAround = around }
            let dots = minimapDots()
            if session.minimapDots != dots { session.minimapDots = dots }
            let marks = minimapMarks()
            if session.minimapMarks != marks { session.minimapMarks = marks }
        }

        player.zPosition = -player.position.y
        if let follower { follower.zPosition = -follower.position.y }
        // Up onto the ground under them: their spot is set before they join the map, and a walker
        // only rises with the ground as it moves on it, so one starting on a hill stood sunk in it
        // (behind its slope) till it took a step. Cheap when nothing's changed.
        player.settle()
        follower?.settle()
        for ally in allies {
            ally.node.settle()
            ally.pet?.settle()
        }
        lantern?.follow(player.position)
        if let sky {
            sky.update(dt)
            lighting?.sunlight(sky.sunlight)
            // The sun creeps (a fifth of a degree in half a second at most): no need to move it every frame.
            sunTimer -= dt
            if sunTimer <= 0 {
                sunTimer = 0.5
                follow(sky.sun)
            }
        }
        updateCamera(dt)
        showChunks()
        updateEdgeFade(dt)
        updateMood(dt)
    }

    private func movePlayer(_ dt: TimeInterval) {
        let stick = input.move
        if stick.length > 0.15 {
            player.path = []
            tapOverBorder = nil
            talkTarget = nil
            let step = stick * (walkSpeed * CGFloat(dt))
            var next = player.position
            // Try each axis separately so you slide along walls instead of sticking.
            let alongX = CGPoint(x: next.x + step.dx, y: next.y)
            if canStand(at: alongX) { next = alongX }
            let alongY = CGPoint(x: next.x, y: next.y + step.dy)
            if canStand(at: alongY) { next = alongY }
            player.position = next
            player.face(Direction(stick, current: player.facing))
            player.setWalking(true)
        } else {
            player.setWalking(player.followPath(dt: dt) || !player.path.isEmpty)
        }
    }

    private func canStand(at point: CGPoint) -> Bool {
        let cell = map.rawCell(at: point)
        guard map.contains(cell) else { return canCross(into: cell) }
        return map.isWalkable(cell) && !barricades.contains { $0.cells.contains(cell) }
    }

    private func checkTalkTarget() {
        guard let target = talkTarget, let npc = npcs.first(where: { $0.def.id == target }) else { return }
        if player.position.distance(to: npc.node.position) <= talkRange {
            startTalking(to: npc.def, node: npc.node)
        } else if player.path.isEmpty {
            talkTarget = nil
        }
    }

    private func startTalking(to npc: NPCDef, node: Walker) {
        talkTarget = nil
        player.path = []
        player.setWalking(false)
        player.face(Direction(node.position - player.position))
        onTalk?(npc)
    }

    private func checkCell() {
        // Walking up to someone this frame opened their window: no battle or road out under it.
        guard !isInputLocked else { return }
        // Over a border into the land next door.
        let raw = map.rawCell(at: player.position)
        if !map.contains(raw) {
            if !hasLeft, let neighbour = neighbour(holding: raw) { cross(into: neighbour) }
            return
        }
        let cell = raw
        guard cell != lastCell else { return }
        if let barricade = barricades.first(where: { $0.cells.contains(cell) || map.exit(at: cell)?.to == $0.exit.to }) {
            // Closed road: back you go, with a hint about which quest opens it.
            player.position = map.center(of: lastCell)
            player.path = []
            if Date().timeIntervalSince(lastBlockedNotice) > 3 {
                lastBlockedNotice = Date()
                let place = Content.shared.map(barricade.exit.to)?.name ?? L("there")
                let quest = barricade.exit.requires.flatMap { session.content.quest($0)?.title } ?? L("a quest")
                session.post(L("The road to {map} is closed. Finish “{quest}” first.", ["map": place, "quest": quest]), .quest)
                player.say(L("It's closed…"))
            }
            return
        }
        lastCell = cell
        if GameSettings.footsteps {
            // Alternate feet, a touch louder and softer.
            leftFoot.toggle()
            SoundEffects.shared.play(.step, volume: leftFoot ? 0.6 : 0.45)
        }
        session.playerPosition = player.position
        session.mapCell = cell
        explore()

        // Off the continent's lands, the old way: into a cave through its mouth, or out of one.
        if let exit = map.exit(at: cell), !hasLeft, Continent.origin(of: def) == nil || Content.shared.world[exit.to] == nil {
            hasLeft = true
            isInputLocked = true
            onTravel?(exit)
            return
        }

        guard let encounters = def.encounters else { return }
        stepsSinceBattle += 1
        if !holdsEncounters, stepsSinceBattle > encounters.graceSteps, Double.random(in: 0..<1) < encounters.rate {
            stepsSinceBattle = 0
            startEncounter(encounters)
        }
    }

    private func startEncounter(_ encounters: MapDef.Encounters) {
        isInputLocked = true
        player.path = []
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
            onEncounter?(encounters, snapshot())
        }
    }

    /// What's on screen right now, for the battle backdrop (Fairyland fights where you stand).
    private func snapshot() -> SKTexture? {
        battleBackdrop()
    }

    /// The map as it looks right now, for behind a battle. The party (and a boss, `npcID`) are
    /// drawn by the battle itself, so they're left out, with tap markers. A cave's dark stays in:
    /// a fight shows no more of the cave than your light did.
    func battleBackdrop(hiding npcID: String? = nil) -> SKTexture? {
        let visible = CGRect(x: cam.position.x - size.width / 2, y: cam.position.y - size.height / 2, width: size.width, height: size.height)
        let boss: [SKNode] = npcs.filter { $0.def.id == npcID }.map(\.node)
        var hidden: [SKNode] = [player, follower].compactMap { $0 } + allies.map(\.node) + boss
            + world.children.filter { $0.name == Effects.tapMarkerName }
        hidden += allies.compactMap(\.pet)
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }
        // The lands next door too, where they show past a border.
        return view?.texture(from: lands, crop: visible)
    }

    /// Back from a battle (or a dialog): unlock input and pick up party changes.
    func resume() {
        openBarricades()
        isInputLocked = false
        lastUpdate = 0
        input.move = .zero
        refreshHero()
        refreshFollower()
        refreshAllies()
        updateNotices()
    }

    // MARK: - Upkeep

    private func updateNotices() {
        var nearest: (id: String, distance: CGFloat)?
        for npc in npcs {
            npc.node.isNear = npc.node.position.distance(to: player.position) < Walker.nameRange
            if npc.def.role == .chest, session.isOpened(npc.def.id), npc.node.alpha > 0.5 {
                npc.node.run(.fadeAlpha(to: 0.35, duration: 0.3))
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
            if let notice {
                npc.marker.setText(notice == .ready ? "?" : "!")
            }
            let distance = player.position.distance(to: npc.node.position)
            if distance <= talkRange + 12, distance < (nearest?.distance ?? .infinity) {
                nearest = (npc.def.id, distance)
            }
            // Townsfolk at their posts turn to watch you pass, and glance around otherwise.
            if npc.def.role != .chest, npc.def.role != .boss {
                if distance < 130 {
                    npc.node.face(Direction(player.position - npc.node.position, current: npc.node.facing))
                } else if Int.random(in: 0..<12) == 0 {
                    npc.node.face(Direction.allCases.randomElement() ?? .down)
                }
            }
        }
        if session.nearbyNPC != nearest?.id { session.nearbyNPC = nearest?.id }
        for (index, sign) in signs.enumerated() {
            let near = sign.base.distance(to: player.position) <= signRange
            sign.hint.isHidden = !near || sign.label.alpha > 0.5
            if near, signTarget == index {
                signTarget = nil
                read(sign)
            }
        }
    }

    /// The last few steps toward an open road out fade to black (into a cave, only toward its mouth).
    /// Not where it runs on into the land next door: you can see where you're going.
    private func updateEdgeFade(_ dt: TimeInterval) {
        // Only going off behind the loading card (into a cave, or over a border before the land's
        // built), not walking on over a border. Nearing a way out used to darken too, from when every
        // edge was one; playtesting: "the map doesn't need to go dark anymore when you switch lands".
        let target: CGFloat = hasLeft && !walkingOver ? 0.85 : 0
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 6)
        edgeFade.alpha += (target - edgeFade.alpha) * t
    }

    /// Where the camera looks: at the hero as drawn, lifted onto the hills, not at the ground under
    /// them, or climbing a mountain you'd walk off the top of the screen.
    private var cameraGoal: CGPoint {
        player.position + CGVector(dx: 0, dy: player.lift)
    }

    private func updateCamera(_ dt: TimeInterval) {
        // The diamond's corners are filled by the surroundings, so just follow the hero.
        let goal = cameraGoal
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 10)
        let eased = CGPoint(x: cam.position.x + (goal.x - cam.position.x) * t, y: cam.position.y + (goal.y - cam.position.y) * t)
        // Snap to whole screen pixels so pixel art doesn't shimmer (zooming changes their size).
        let scale = (view?.contentScaleFactor ?? 1) / cam.xScale
        cam.position = CGPoint(x: (eased.x * scale).rounded() / scale, y: (eased.y * scale).rounded() / scale)
        focus.update(camera: cam.position, halfHeight: size.height / 2 * cam.yScale)
    }
}
