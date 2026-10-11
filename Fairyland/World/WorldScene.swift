import SpriteKit

/// Joystick input shared between the SwiftUI HUD and the scene (read every frame).
final class InputState {
    /// -1...1 on each axis, y up.
    var move: CGVector = .zero
}

/// One map: ground, scenery, NPCs, passers-by, the hero and their companion.
///
/// Like Fairyland, monsters aren't shown on the map — walking through the wild can start
/// a random battle. Walk off the edge where a road leaves the map to travel to the next map.
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
    private let world = SKNode()
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

    private let walkSpeed: CGFloat = 88
    private let talkRange: CGFloat = 50

    /// Pinch to zoom in on the ground around you, or out for a wider view. Kept from map to map.
    private static var zoom: CGFloat = 1
    private static let zoomRange: ClosedRange<CGFloat> = 0.85...2.2
    private var pinchStartZoom: CGFloat = 1
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

    /// `entry` is the edge the player walked in through, or nil to use the saved position.
    init(map def: MapDef, session: GameSession, input: InputState, entry: Edge?) {
        // Characters made for this map pick up its light.
        if let palette = def.theme.palette, let hex = palette.light, let color = UIColor(hex: hex) {
            Walker.light = (color, CGFloat(palette.lightStrength ?? 0.4))
        } else {
            Walker.light = nil
        }
        let map = WorldMap(def: def)
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
        if let entry {
            start = map.center(of: map.entryCell(from: entry))
        } else if let saved = session.playerPosition {
            start = saved
        }
        player.position = start
        lastCell = map.cell(at: start)

        super.init(size: CGSize(width: 874, height: 402))
        scaleMode = .resizeFill
        backgroundColor = .black
        session.playerPosition = player.position
        // The scenery goes up in `build(progress:)`, a piece at a time, behind the loading bar.
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        view.addGestureRecognizer(pinch)
        cam.setScale(1 / Self.zoom)
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

    /// Builds the map a piece at a time, pausing between pieces so the loading bar can move.
    /// `progress` gets 0...1 as the pieces are done (weighted by roughly how long each takes).
    func build(progress: (Double) -> Void) async {
        guard !isBuilt, world.parent == nil else { return }
        art.use(palette: def.theme.palette, for: def.id)
        addChild(world)
        addChild(cam)
        camera = cam
        if let darkness = def.ambience?.darkness { lantern = Lantern(darkness, in: world) }
        await reached(0.05, progress)

        world.addChild(makeGround())
        placePlateaus()
        await reached(0.3, progress)
        placeSurroundings()
        await reached(0.45, progress)
        if let cave = def.theme.cave {
            caveWalls = CaveWalls(map: map, cave: cave, world: world, art: art, margin: Self.surroundingsMargin)
            await reached(0.55, progress)
        }
        placeLilyPads()
        placeFence()
        placeBuildings()
        await reached(0.65, progress)
        placeDecor()
        await reached(0.8, progress)
        placeNPCs()
        // A town's market traders sell what they have today, around your level.
        let market = Crowd.Market(sign: { [weak session] in session?.marketSign(for: $0) },
                                  shout: { [weak session] in session?.marketShout(for: $0) },
                                  level: session.data.hero.level)
        crowd = Crowd(def: def, map: map, world: world, heroLevel: session.data.hero.level,
                      friends: session.friends.filter { !session.isInParty($0) }, market: market)
        crowd?.onChat = { [weak session] speaker, text, kind in session?.postChat(text, from: speaker, kind: kind) }
        crowd?.dares = { [weak session] rival in session?.dares(rival) ?? false }
        crowd?.onChallenge = { [weak self] rival in
            guard let self, !self.isInputLocked else { return }
            self.startDuel(with: rival)
        }
        placeFairyRings()
        placeProps()
        placeSignposts()
        placeBarricades()
        // Everyone set down before they were on the map stands up on the ground under them.
        for case let walker as Walker in world.children { walker.settle() }
        await reached(0.9, progress)

        world.addChild(player)
        refreshHero()
        refreshFollower()
        refreshAllies()
        cam.position = player.position
        edgeFade.alpha = 0
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        edgeFade.zPosition = 40_000
        cam.addChild(edgeFade)
        ambience = Ambience(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id)
        ambience?.resize(to: size)
        critters = Critters(def.ambience, world: world, map: map, seed: def.id)
        lighting = Lighting(def.ambience, world: world, camera: cam, bounds: map.bounds, seed: def.id)
        lighting?.resize(to: size)
        sky = Sky(map: def, camera: cam, start: session.data.startedAt)
        if let sky { lighting?.sunlight(sky.sunlight) }

        // Don't start on top of scenery (e.g. an old save).
        // (A save from before a cave's walls went up can even be deep inside the rock.)
        if !map.isWalkable(lastCell),
           let open = map.nearestWalkable(to: lastCell) ?? map.nearestWalkable(to: map.entryCell(from: def.exits.first?.edge ?? .south)) {
            player.position = map.center(of: open)
            lastCell = open
            cam.position = player.position
        }
        session.playerPosition = player.position
        lantern?.follow(player.position)
        explore()
        isBuilt = true
        progress(1)
    }

    /// Reports progress, then gives the screen a moment to draw it before the next piece.
    private func reached(_ fraction: Double, _ progress: (Double) -> Void) async {
        progress(fraction)
        try? await Task.sleep(for: .milliseconds(10))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        edgeFade.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        ambience?.resize(to: size)
        lighting?.resize(to: size)
    }

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
        // Accent patches (flower meadows, moss) blend in as soft blobs. Not in towns, where the
        // accent is terrace paving and stays square.
        let patchAccent = (theme.accentPatches ?? 0) > 0 && theme.accent != nil && theme.accent != theme.ground
        /// Which cells of the 3×3 around `cell` are `kind` (bit row * 3 + col, row 0 north).
        func mask(_ cell: GridPoint, _ kind: Ground) -> Int {
            let own = map.ground[cell.row][cell.col] == kind
            var bits = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let next = GridPoint(col: cell.col + dx, row: cell.row + dy)
                    // Off the map a road or patch carries on; water doesn't.
                    let hit = map.contains(next) ? map.ground[next.row][next.col] == kind : own && kind != .water
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
                    if map.contains(next), map.ground[next.row][next.col] == .water { bits |= 1 << ((2 - dy) * 5 + dx + 2) }
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
        var picks: [(col: Int, row: Int, group: SKTileGroup)] = []
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let cell = GridPoint(col: col, row: row)
                let kind = map.ground[row][col]
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
                if patch != 0, let accent = theme.accent { layers.append(.init(tile: accent, mask: patch, style: .patch)) }
                if road != 0 { layers.append(.init(tile: theme.path, mask: road, style: .road)) }
                if pond != 0 { layers.append(.init(tile: waterID, mask: poolMask(cell), style: .water)) }
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
                    // Shorelines depend on where they are (see organicTile), so each gets its own tile.
                    let place = pond != 0 ? "@\(col),\(row)" : ""
                    let key = base + "|" + layers.map { "\($0.style)\($0.mask)" }.joined(separator: "|") + place
                    chosen = group(key) { art.organicTile(base: base, layers: layers, cell: cell, variant: variant) }
                }
                picks.append((col, row, chosen))
            }
        }
        let tileSet = SKTileSet(tileGroups: Array(groups.values))
        let tileMap = SKTileMapNode(tileSet: tileSet, columns: map.columns, rows: map.rows, tileSize: tileSize)
        tileMap.anchorPoint = .zero
        for pick in picks {
            tileMap.setTileGroup(pick.group, forColumn: pick.col, row: pick.row)
        }
        // Raised ground (a terrace, a hill): its own tiles again, drawn its height up
        // (`placePlateaus` sets them down). The ramps are drawn as slopes instead.
        raisedTops = map.plateaus.map { plateau in
            let (low, high) = plateau.bounds
            let top = SKTileMapNode(tileSet: tileSet, columns: high.col - low.col + 1, rows: high.row - low.row + 1, tileSize: tileSize)
            top.anchorPoint = .zero
            for pick in picks {
                let cell = GridPoint(col: pick.col, row: pick.row)
                guard plateau.cells.contains(cell), plateau.ramps[cell] == nil else { continue }
                top.setTileGroup(pick.group, forColumn: pick.col - low.col, row: pick.row - low.row)
            }
            top.position = CGPoint(x: CGFloat(low.col) * WorldMap.tileSize, y: CGFloat(low.row) * WorldMap.tileSize)
            // A hilltop catches a little more light than the ground around it, so it stands apart.
            if plateau.kind == .hill {
                top.color = .white
                top.colorBlendFactor = 0.08
            }
            let grid = SKNode()
            grid.addChild(top)
            let layer = projected(grid)
            layer.position.y = plateau.height
            return layer
        }
        // Soft patches of colour over the whole ground, so it isn't one flat colour.
        let grid = SKNode()
        grid.addChild(tileMap)
        if let variation = Lighting.groundVariation(columns: map.columns, rows: map.rows, tile: WorldMap.tileSize, palette: theme.palette, seed: def.id) {
            variation.zPosition = 1
            grid.addChild(variation)
        }
        let ground = projected(grid)
        ground.zPosition = -100_000
        return ground
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

    /// Scenery beyond the map's edge, so small maps never show black bars (e.g. in portrait).
    /// Roads carry on out through the exits, and the far edge melts into a soft fog.
    private func placeSurroundings() {
        let margin = Self.surroundingsMargin
        let tile = WorldMap.tileSize
        let tileSize = CGSize(width: tile, height: tile)
        let theme = def.theme
        let fill = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.border ?? theme.ground), size: tileSize))
        let road = SKTileGroup(tileDefinition: SKTileDefinition(texture: art.tileTexture(theme.path), size: tileSize))
        let columns = map.columns + margin * 2
        let rows = map.rows + margin * 2
        let surroundings = SKTileMapNode(tileSet: SKTileSet(tileGroups: [fill, road]), columns: columns, rows: rows, tileSize: tileSize, fillWith: fill)
        surroundings.anchorPoint = .zero
        surroundings.position = CGPoint(x: -CGFloat(margin) * tile, y: -CGFloat(margin) * tile)
        let fog = Self.fogColor(from: art.tileTexture(theme.border ?? theme.ground), cave: theme.cave != nil)
        backgroundColor = fog
        let ground = SKNode()
        ground.addChild(surroundings)
        addFog(fog, around: CGRect(origin: surroundings.position,
                                   size: CGSize(width: CGFloat(columns) * tile, height: CGFloat(rows) * tile)), in: ground)
        let projectedSurroundings = projected(ground)
        projectedSurroundings.zPosition = -100_001
        world.addChild(projectedSurroundings)

        // Extend each exit's road straight out to the edge of the surroundings.
        var roadCells: Set<GridPoint> = []
        for exit in def.exits {
            for i in 0..<margin {
                switch exit.edge {
                case .north, .south:
                    let edgeRow = exit.edge == .north ? map.rows - 1 : 0
                    for col in 0..<map.columns where map.ground[edgeRow][col] == .path {
                        roadCells.insert(GridPoint(col: col, row: exit.edge == .north ? map.rows + i : -1 - i))
                    }
                case .east, .west:
                    let edgeCol = exit.edge == .east ? map.columns - 1 : 0
                    for row in 0..<map.rows where map.ground[row][edgeCol] == .path {
                        roadCells.insert(GridPoint(col: exit.edge == .east ? map.columns + i : -1 - i, row: row))
                    }
                }
            }
        }
        for cell in roadCells {
            surroundings.setTileGroup(road, forColumn: cell.col + margin, row: cell.row + margin)
        }

        // A loose treeline, keeping the roads clear (caves have rock walls instead), and stopping
        // where the fog begins so no tree pokes out of it.
        guard def.theme.cave == nil, let decor = theme.props.first(where: \.blocking)?.art else { return }
        let sprite = art.sprite(decor)
        var decorRNG = SeededRandom(text: def.id + "/surroundings")
        let reach = margin - Self.fogBand
        for row in -reach..<(map.rows + reach) {
            for col in -reach..<(map.columns + reach) {
                let outside = row < 0 || col < 0 || row >= map.rows || col >= map.columns
                guard outside, Double.random(in: 0..<1, using: &decorRNG) < 0.14 else { continue }
                let nearRoad = (-1...1).contains { dc in (-1...1).contains { dr in roadCells.contains(GridPoint(col: col + dc, row: row + dr)) } }
                guard !nearRoad else { continue }
                addScenery(sprite, at: GridPoint(col: col, row: row))
            }
        }
    }

    /// Soft bands along the inside of `rect` (in unprojected ground space), clear on the map side
    /// and solid fog at the edge, where the background takes over.
    private func addFog(_ color: UIColor, around rect: CGRect, in parent: SKNode) {
        let depth = CGFloat(Self.fogBand) * WorldMap.tileSize
        let texture = Self.fogTexture
        // (centre, length along the edge, rotation): the texture is solid at its top edge.
        let bands: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.midX, y: rect.maxY - depth / 2), rect.width, 0),
            (CGPoint(x: rect.midX, y: rect.minY + depth / 2), rect.width, .pi),
            (CGPoint(x: rect.minX + depth / 2, y: rect.midY), rect.height, .pi / 2),
            (CGPoint(x: rect.maxX - depth / 2, y: rect.midY), rect.height, -.pi / 2),
        ]
        for (center, length, angle) in bands {
            let band = SKSpriteNode(texture: texture, color: color, size: CGSize(width: length, height: depth))
            band.colorBlendFactor = 1
            band.position = center
            band.zRotation = angle
            band.zPosition = 1
            parent.addChild(band)
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
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let texture = image.map { SKTexture(cgImage: $0) } ?? SKTexture()
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
                world.addChild(glow)
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

    /// How deep a plateau's top is drawn: just behind the back of it, so everything standing on it
    /// (or in front) is drawn over it and whoever stands just behind it is hidden by it.
    private static func topZ(of plateau: WorldMap.Plateau) -> CGFloat {
        let tile = WorldMap.tileSize
        let back = plateau.cells.map { WorldMap.project(CGPoint(x: CGFloat($0.col + 1) * tile, y: CGFloat($0.row + 1) * tile)).y }.max() ?? 0
        return -back - 0.75
    }

    /// Raised ground (WorldMap.plateaus): each top drawn its height up, a bank (a terrace's stone
    /// wall, a hill's earth) under the edges that face you, and ramps (stone steps up a terrace, a
    /// trodden slope up a hill) climbing from the ground in front to the top. The banks sit under
    /// the tops, so at a hill's nooks the top in front hides the bank behind it.
    private func placePlateaus() {
        let tile = WorldMap.tileSize
        let stone = art.tileTexture(def.theme.accent ?? "tile_scree")
        let bank = art.tileTexture(def.theme.hills?.bank ?? "tile_scree")
        let trodden = art.tileTexture(def.theme.path)
        let grass = Self.averageColor(of: art.tileTexture(def.theme.ground))
        let grassLip = UIColor(red: min(1, grass.0 * 1.2), green: min(1, grass.1 * 1.2), blue: min(1, grass.2 * 1.2), alpha: 1)
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
            let terrace = plateau.kind == .terrace
            let rise = plateau.height
            let topZ = Self.topZ(of: plateau)
            let lips = CGMutablePath(), shadows = CGMutablePath(), creases = CGMutablePath(), treads = CGMutablePath()
            let crests = CGMutablePath()
            let up = CGVector(dx: 0, dy: rise)
            func line(_ path: CGMutablePath, _ from: CGPoint, _ to: CGPoint) {
                path.move(to: from)
                path.addLine(to: to)
            }
            if index < raisedTops.count {
                raisedTops[index].zPosition = topZ
                world.addChild(raisedTops[index])
            }
            // Banks: under each edge of the top facing you (front, left) where the ground beyond is
            // lower, down to it (along a ramp, down to the slope: a triangle).
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
                    face.fillTexture = terrace ? stone : bank
                    // Lit from the front: the side facing left a shade darker.
                    face.fillColor = UIColor(white: front ? 0.82 : 0.64, alpha: 1)
                    face.strokeColor = .clear
                    face.lineWidth = 0
                    face.zPosition = topZ - 0.5
                    world.addChild(face)
                    // A lip along the top (pale stone on a terrace, the grass's edge on a hill) and a
                    // soft shadow where the bank meets the ground.
                    line(lips, pa + CGVector(dx: 0, dy: rise), pb + CGVector(dx: 0, dy: rise))
                    line(shadows, pa + CGVector(dx: 0, dy: min(rise, lowA)), pb + CGVector(dx: 0, dy: min(rise, lowB)))
                }
                // A hill's far edges (back and right), where the top drops away out of sight: a thin
                // shade along them, so its outline reads against the ground behind. A terrace has its
                // railings there.
                guard !terrace else { continue }
                if !plateau.cells.contains(GridPoint(col: cell.col, row: cell.row + 1)) {
                    line(crests, corner(cell.col, cell.row + 1) + up, corner(cell.col + 1, cell.row + 1) + up)
                }
                if !plateau.cells.contains(GridPoint(col: cell.col + 1, row: cell.row)) {
                    line(crests, corner(cell.col + 1, cell.row) + up, corner(cell.col + 1, cell.row + 1) + up)
                }
            }
            // Ramps: the foot on the ground in front, the head up at the top.
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
                slope.fillTexture = terrace ? stone : trodden
                slope.fillColor = UIColor(white: 0.95, alpha: 1)
                slope.strokeColor = UIColor(white: 0, alpha: 0.22)
                slope.lineWidth = 1
                // Under the top: where the top beside it stands in front of it, the top shows.
                slope.zPosition = topZ - 0.25
                world.addChild(slope)
                guard terrace else { continue }
                // Steps across a terrace's stairs, foot to head.
                let steps = 5
                for step in 1..<steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let left = points[0] + (points[3] - points[0]) * t
                    let right = points[1] + (points[2] - points[1]) * t
                    line(creases, left, right)
                    line(treads, left + CGVector(dx: 0, dy: 1.5), right + CGVector(dx: 0, dy: 1.5))
                }
            }
            stroke(lips, color: terrace ? UIColor(white: 1, alpha: 0.55) : grassLip, width: terrace ? 2 : 3, z: topZ + 0.1)
            stroke(shadows, color: UIColor(white: 0, alpha: 0.28), width: 2, z: topZ - 0.45)
            stroke(crests, color: UIColor(white: 0, alpha: 0.2), width: 2, z: topZ + 0.1)
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
                        world.addChild(node)
                        continue
                    }
                    let sprite = corner ? pillar : rail
                    let node = SKSpriteNode(texture: sprite.texture, size: sprite.size * (corner ? 0.6 : 0.7))
                    node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                    node.position = map.base(of: cell) + up
                    // Railings follow the edge they're on.
                    if !corner, col == o.col || col == last.col { node.xScale = -1 }
                    node.zPosition = -map.base(of: cell).y
                    world.addChild(node)
                }
            }
        }
    }

    private func placeNPCs() {
        for npc in def.npcs ?? [] {
            let cell = map.offset(npc.x, npc.y)
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

    /// Scenery from the theme. Props with `cluster` grow in groves around a random centre.
    private func placeProps() {
        for placement in def.theme.props {
            let sprite = art.sprite(placement.art)
            let groupSize = max(1, placement.cluster ?? 1)
            let spread = max(1, placement.spread ?? Int(Double(groupSize).squareRoot().rounded()) + 1)
            var placed = 0
            var attempts = 0
            while placed < placement.count, attempts < placement.count * 3 {
                attempts += 1
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
                    guard map.isFreeForScenery(cell, insideFence: placement.within != nil, blocking: placement.blocking) else { continue }
                    map.occupy(cell, blocking: placement.blocking)
                    var scale: CGFloat = 1
                    if let range = placement.size, range.count == 2, range[0] <= range[1] {
                        scale = CGFloat(Double.random(in: range[0]...range[1], using: &rng))
                    }
                    let node = addScenery(sprite, at: cell, sway: placement.sway == true, jitter: true, scale: scale)
                    if placement.bob == true {
                        // Unseeded, so the map's layout stays what it was.
                        let rise = SKAction.moveBy(x: 0, y: 3, duration: .random(in: 1.3...2))
                        rise.timingMode = .easeInEaseOut
                        node.run(.repeatForever(.sequence([rise, rise.reversed()])), withKey: "bob")
                    }
                    if placement.shadow == true { Lighting.shadow(under: node, in: world) }
                    if let hex = placement.glow, let color = UIColor(hex: hex) {
                        Lighting.glow(behind: node, color: color, in: world, rng: &rng)
                        lantern?.glint(at: node.position + CGVector(dx: 0, dy: node.size.height * 0.4), color: color, width: node.size.width * 1.6)
                    }
                    inGroup += 1
                }
                placed += inGroup
            }
        }
    }

    /// Hand-placed decorations (fountains, blossom trees) from the map's `decor` list.
    private func placeDecor() {
        for decor in def.decor ?? [] {
            let anchor = map.offset(decor.x, decor.y)
            let sprite = art.sprite(decor.art)
            let blocking = decor.blocking ?? true
            let footprint = max(1, Int(sprite.size.width / WorldMap.tileSize * 0.75))
            for dc in 0..<footprint {
                map.occupy(GridPoint(col: anchor.col + dc - footprint / 2, row: anchor.row), blocking: blocking)
            }
            addScenery(sprite, at: anchor, sway: decor.art.contains("tree") || decor.art.contains("flower"))
            if decor.art.contains("fountain") {
                Ambience.twinkle(around: map.center(of: anchor) + CGVector(dx: 0, dy: 30), radius: 30, count: 4, in: world)
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
                    world.addChild(node)
                }
                Ambience.twinkle(around: origin, radius: 26, count: 5, in: world)
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
            for _ in 0..<min(4, max(1, pond.count / 8)) {
                guard let cell = pond.randomElement(using: &padRNG) else { continue }
                let node = SKSpriteNode(texture: sprite.texture, size: sprite.size)
                node.position = map.center(of: cell) + CGVector(dx: .random(in: -6...6, using: &padRNG), dy: .random(in: -6...6, using: &padRNG))
                node.zPosition = -99_000
                node.run(.repeatForever(.sequence([
                    .rotate(toAngle: 0.08, duration: 2.2, shortestUnitArc: true),
                    .rotate(toAngle: -0.08, duration: 2.2, shortestUnitArc: true),
                ])))
                world.addChild(node)
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

    /// A fence across each road that a quest hasn't opened yet, with a little lock sign.
    private func placeBarricades() {
        for exit in def.exits where !session.canTravel(exit) {
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

    /// A finished quest opened a road while you were here: the barricade poofs away.
    private func openBarricades() {
        barricades.removeAll { barricade in
            guard session.canTravel(barricade.exit) else { return false }
            for node in barricade.nodes {
                SkillEffects.smoke(at: node.position, in: world)
                node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
            return true
        }
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
        world.addChild(node)
        focus.add(node)
        return node
    }

    private var feet: [ObjectIdentifier: CGFloat] = [:]

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

    /// Everyone else on this map, for the minimap: the adventurers walking about and the friends in
    /// your party (behind you, or waiting where you left them). On a dark map, only those standing
    /// somewhere you've seen.
    private func minimapDots() -> [GameSession.MinimapDot] {
        let friends = Set(session.friends.map(\.id))
        let seen: Data? = lantern == nil ? nil : session.explored(def.id) ?? Data()
        func dot(at point: CGPoint, _ kind: GameSession.MinimapDot.Kind) -> GameSession.MinimapDot? {
            let cell = map.cell(at: point)
            if let seen {
                let index = cell.row * map.columns + cell.col
                guard index / 8 < seen.count, seen[index / 8] & UInt8(1 << (index % 8)) != 0 else { return nil }
            }
            return GameSession.MinimapDot(cell: cell, kind: kind)
        }
        let walkers = (crowd?.adventurerPositions ?? []).compactMap { profile, position in
            dot(at: position, profile.hostile ? .hostile : friends.contains(profile.id) ? .friend : .adventurer)
        }
        return walkers + allies.compactMap { dot(at: $0.node.position, .party) }
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

    /// `image` with every cell you haven't seen painted the minimap window's own dark blue.
    private static func fog(_ image: UIImage, seen: Data?, columns: Int, rows: Int) -> UIImage {
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

    /// One pixel per tile, for the HUD minimap.
    private(set) lazy var minimap: UIImage = {
        // The map's own (palette-graded) tiles, averaged: a purple wood looks purple here too.
        // Graded with this map's palette itself: the HUD asks for the minimap as soon as the scene
        // exists, while the art library still grades for the map you came from (until `build`).
        let art = self.art
        let palette = def.theme.palette
        let waterID = def.theme.water ?? "tile_water"
        return UIImage(cgImage: map.overviewImage { id in
            let color: (CGFloat, CGFloat, CGFloat)
            if let image = art.gradedTile(id, palette: palette) {
                color = Self.averageColor(of: image)
            } else {
                color = Self.averageColor(of: id == waterID ? art.waterFrames(id).first ?? art.tileTexture(id) : art.tileTexture(id))
            }
            return PixelColor(r: UInt8(color.0 * 255), g: UInt8(color.1 * 255), b: UInt8(color.2 * 255))
        })
    }()


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
        // A tap on a hilltop means the top, not the ground it hides.
        player.path = map.path(from: player.position, to: map.groundPoint(under: point))
        if let destination = player.path.last {
            Effects.tapMarker(at: destination + CGVector(dx: 0, dy: map.height(at: destination)), in: world)
        }
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

    /// A Homeward Feather taking you away: a gust of feathers whirls up round you, and you rise
    /// into a column of light and fade, then `done` (the map changes).
    func featherAway(then done: @escaping () -> Void) {
        isInputLocked = true
        player.path = []
        player.setWalking(false)
        player.idles = false
        let column = featherColumn(over: player.position)
        column.alpha = 0
        column.yScale = 0.3
        column.run(.group([.fadeAlpha(to: 0.9, duration: 0.45), .scaleY(to: 1, duration: 0.45)]))
        featherGust(around: player.position, rising: true)
        let lift = SKAction.moveBy(x: 0, y: 90, duration: 0.9)
        lift.timingMode = .easeIn
        player.sprite.run(.sequence([.wait(forDuration: 0.25), .group([lift, .scaleX(to: 0.55, duration: 0.9)])]), withKey: "feather")
        player.run(.sequence([.wait(forDuration: 0.55), .fadeOut(withDuration: 0.6)]))
        onFeatherGone = done
        Task {
            await run(.wait(forDuration: 1.25))
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
        player.sprite.position = CGPoint(x: 0, y: 90)
    }

    /// Arriving by Homeward Feather: you float down in the light as the feathers settle.
    func featherArrive() {
        let column = featherColumn(over: player.position)
        column.alpha = 0.9
        column.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.6), .removeFromParent()]))
        featherGust(around: player.position, rising: false)
        player.run(.fadeIn(withDuration: 0.45))
        let drop = SKAction.move(to: .zero, duration: 0.85)
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

    /// Feathers whirling round `center`: spiralling up and closing in (`rising`), or drifting down
    /// and out to settle.
    private func featherGust(around center: CGPoint, rising: Bool) {
        let texture = ArtLibrary.shared.sprite("item_homeward_feather").texture
        let count = 12
        let duration: CGFloat = 1.2
        for index in 0..<count {
            let feather = SKSpriteNode(texture: texture, size: CGSize(width: 18, height: 18))
            feather.zPosition = 30_001
            feather.alpha = 0
            world.addChild(feather)
            let phase = CGFloat(index) / CGFloat(count) * 2 * .pi
            let spin = SKAction.customAction(withDuration: duration) { node, elapsed in
                let t = min(1, elapsed / duration)
                let p = rising ? t : 1 - t
                let angle = phase + p * 4.4 * .pi
                let radius = 34 - 14 * p
                node.position = CGPoint(x: center.x + cos(angle) * radius, y: center.y + 6 + p * 140 + sin(angle) * radius * 0.35)
                node.zRotation = angle
                node.alpha = min(1, t * 5, (1 - t) * 4)
            }
            feather.run(.sequence([.wait(forDuration: Double(index) * 0.04), spin, .removeFromParent()]))
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
        run(.sequence([.wait(forDuration: 0.75), .run { [weak self] in self?.isPaused = true }]))
    }

    /// Debug launches (`say=<text>`): a speech bubble over the hero that stays, for screenshots.
    func sayForDebug(_ text: String) {
        player.say(text, for: 600)
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

    /// Called by the HUD's Talk button.
    func talkToNearby() {
        guard let id = session.nearbyNPC, let npc = npcs.first(where: { $0.def.id == id }) else { return }
        startTalking(to: npc.def, node: npc.node)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        if let onFirstFrame {
            self.onFirstFrame = nil
            onFirstFrame()
        }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20)
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
        critters?.update(dt: dt, player: player.position, visible: visible, canStand: standable)
        noticeTimer -= dt
        if noticeTimer <= 0 {
            noticeTimer = 0.4
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
        }

        player.zPosition = -player.position.y
        if let follower { follower.zPosition = -follower.position.y }
        lantern?.follow(player.position)
        if let sky {
            sky.update(dt)
            lighting?.sunlight(sky.sunlight)
        }
        updateCamera(dt)
        updateEdgeFade(dt)
    }

    private func movePlayer(_ dt: TimeInterval) {
        let stick = input.move
        if stick.length > 0.15 {
            player.path = []
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
        let cell = map.cell(at: player.position)
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

        if let exit = map.exit(at: cell), !hasLeft {
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
        return view?.texture(from: world, crop: visible)
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

    /// The last few steps toward an open road out fade to black.
    private func updateEdgeFade(_ dt: TimeInterval) {
        let cell = map.cell(at: player.position)
        let fadeCells = 4
        var target: CGFloat = 0
        for exit in def.exits where session.canTravel(exit) {
            let distance = map.distance(from: cell, to: exit.edge)
            guard distance < fadeCells else { continue }
            target = max(target, CGFloat(fadeCells - distance) / CGFloat(fadeCells) * 0.75)
        }
        if hasLeft { target = 0.85 }
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 6)
        edgeFade.alpha += (target - edgeFade.alpha) * t
    }

    private func updateCamera(_ dt: TimeInterval) {
        // The diamond's corners are filled by the surroundings, so just follow the hero.
        let goal = player.position
        let t = dt == 0 ? 1 : min(1, CGFloat(dt) * 10)
        let eased = CGPoint(x: cam.position.x + (goal.x - cam.position.x) * t, y: cam.position.y + (goal.y - cam.position.y) * t)
        // Snap to whole screen pixels so pixel art doesn't shimmer (zooming changes their size).
        let scale = (view?.contentScaleFactor ?? 1) / cam.xScale
        cam.position = CGPoint(x: (eased.x * scale).rounded() / scale, y: (eased.y * scale).rounded() / scale)
        focus.update(camera: cam.position, halfHeight: size.height / 2 * cam.yScale)
    }
}
