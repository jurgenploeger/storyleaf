import UIKit

/// A piece of scenery a land sets down (`LandPlanner`): what, on which cell, nudged off the grid
/// how far, how big, and how it sways, all settled before anything's drawn.
struct Placement {
    let art: String
    let cell: GridPoint
    /// How far it's nudged off the middle of its cell, so groves look planted by nature.
    var nudge: CGVector?
    var scale: CGFloat = 1
    var sway: Sway?
    /// A prop from a land's theme (`MapDef.PropPlacement`): it may bob, cast a shadow and glow.
    var prop: MapDef.PropPlacement?
    /// Its glow, if its prop glows: how bright, and how long a pulse takes.
    var glow: (alpha: CGFloat, duration: TimeInterval)?
    /// A land next door's prop on this side of the line (`Seam`): graded with that land's palette.
    var land: MapDef?

    struct Sway {
        let duration: TimeInterval
        let lean: CGFloat
        /// The angle it starts at.
        let start: CGFloat
    }
}

/// Everything a land sets down on its ground, on which cells, decided before any of it is drawn,
/// so where you can walk is settled first (docs/continuous-world.md, step 1b).
struct LandPlan {
    /// Lily pads: the pond cell each floats on, and how far it's drifted off its middle.
    var lilyPads: [(cell: GridPoint, drift: CGVector)] = []
    var reeds: [Placement] = []
    /// A town's houses, street lamps and benches, and the land's own buildings.
    var lots: [Placement] = []
    var streetDecor: [Placement] = []
    var buildings: [Placement] = []
    var decor: [Placement] = []
    var npcs: [(npc: NPCDef, cell: GridPoint)] = []
    /// The people who live here, for the crowd to bring to life, and their things round home.
    var locals: [Crowd.Local] = []
    var localProps: [Placement] = []
    /// The middle of each fairy ring.
    var fairyRings: [GridPoint] = []
    var outcrops: [Placement] = []
    var props: [Placement] = []
    var seamProps: [Placement] = []
    var signposts: [(exit: MapDef.Exit, cell: GridPoint)] = []
    /// What lines stretches of its roads (`LandPlanner.planRoadsides`). A row's props are among
    /// `props`.
    var roadsides: [RoadsideLine] = []
}

/// A stretch of a land's road lined (`LandPlanner.planRoadsides`): a picket fence, a low wall, or a
/// row of its props, on the cells beside the road.
struct RoadsideLine {
    enum Kind: String { case fence, wall, row }
    let kind: Kind
    /// The cells beside the road it stands on, one after another along it.
    let cells: [GridPoint]
}

/// Decides where a land's scenery goes, taking the cells it stands on (`WorldMap.occupy`), in the
/// order `WorldScene.build` always set it down and with the same random draws, so a land looks as it
/// did. Nothing's drawn here: `WorldScene` draws the plan.
final class LandPlanner {
    private let def: MapDef
    private let map: WorldMap
    private let art: ArtLibrary
    /// The land's own stream for where its props go and how each is nudged and sways ("/props").
    private var rng: SeededRandom
    private(set) var plan = LandPlan()

    init(def: MapDef, map: WorldMap, art: ArtLibrary) {
        self.def = def
        self.map = map
        self.art = art
        rng = SeededRandom(text: def.id + "/props")
    }

    /// The plan's first part, up to the people who live here (`plan.locals`, for the crowd, which
    /// `WorldScene.build` makes before the rest). `pause`: called every so often, for a land built
    /// in the background to give the frame back (`WorldScene.breathe`).
    func planUpToLocals(pause: () async -> Void) async {
        planLilyPads()
        occupyBridgeBanks()
        planReeds()
        await pause()
        occupyFence()
        planBuildings()
        planDecor()
        planNPCs()
        await pause()
        planLocals()
    }

    /// The rest: what lines its roads, fairy rings, outcrops, the theme's props and the lands next
    /// door's, and signposts.
    func planTheRest(pause: () async -> Void) async {
        planRoadsides()
        await pause()
        planFairyRings()
        planOutcrops()
        await pause()
        await planProps(pause: pause)
        await planSeamProps(pause: pause)
        planSignposts()
    }

    /// A piece of scenery on `cell`, nudged and swaying as asked: the draws from the stream, in the
    /// order `WorldScene.addScenery` always made them.
    private func scenery(_ art: String, at cell: GridPoint, sway: Bool = false, nudge: Bool = false, scale: CGFloat = 1) -> Placement {
        var placement = Placement(art: art, cell: cell, scale: scale)
        if nudge {
            let dx = CGFloat.random(in: -7...7, using: &rng)
            let dy = CGFloat.random(in: -5...5, using: &rng)
            placement.nudge = CGVector(dx: dx, dy: dy)
        }
        if sway {
            let duration = TimeInterval.random(in: 1.8...2.8, using: &rng)
            let lean = CGFloat.random(in: 0.018...0.03, using: &rng)
            let start = CGFloat.random(in: -lean...lean, using: &rng)
            placement.sway = Placement.Sway(duration: duration, lean: lean, start: start)
        }
        return placement
    }

    private func planLilyPads() {
        // Frozen ponds and chocolate ones don't grow lily pads.
        let water = def.theme.water ?? ""
        guard !water.contains("ice"), !water.contains("chocolate") else { return }
        var padRNG = SeededRandom(text: def.id + "/lilies")
        for pond in map.ponds {
            // A few on a pond, more on a lake.
            for _ in 0..<min(max(4, pond.count / 60), max(1, pond.count / 8)) {
                guard let cell = pond.randomElement(using: &padRNG), !map.bridgeCells.contains(cell) else { continue }
                let dx = CGFloat.random(in: -6...6, using: &padRNG)
                let dy = CGFloat.random(in: -6...6, using: &padRNG)
                plan.lilyPads.append((cell: cell, drift: CGVector(dx: dx, dy: dy)))
            }
        }
    }

    /// Nothing grows right beside a bridge's deck either, on the bank its planks and rails reach
    /// over, where a fern or a tree would stand on the bridge.
    private func occupyBridgeBanks() {
        for bridge in map.bridges {
            for cell in bridge.cells {
                for dc in -1...1 {
                    for dr in -1...1 { map.occupy(GridPoint(col: cell.col + dc, row: cell.row + dr), blocking: false) }
                }
            }
        }
    }

    /// Reeds here and there along the lakes' and the river's shores, where the water isn't frozen
    /// or chocolate.
    private func planReeds() {
        let water = def.theme.water ?? ""
        guard !water.contains("ice"), !water.contains("chocolate"), !map.lakes.isEmpty || !map.river.isEmpty else { return }
        var reedRNG = SeededRandom(text: def.id + "/reeds")
        var seen: Set<GridPoint> = []
        for shore in map.lakes.map({ $0.water }) + [map.river] {
            for cell in shore.sorted(by: WorldMap.inOrder) {
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let land = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    guard map.contains(land), map.ground[land.row][land.col] != .water, seen.insert(land).inserted else { continue }
                    guard Double.random(in: 0..<1, using: &reedRNG) < 0.12, map.isFreeForScenery(land, blocking: false) else { continue }
                    map.occupy(land, blocking: false)
                    let scale = CGFloat.random(in: 0.75...1, using: &reedRNG)
                    plan.reeds.append(scenery("reeds", at: land, nudge: true, scale: scale))
                }
            }
        }
    }

    private func occupyFence() {
        for cell in map.fenceCells { map.occupy(cell, blocking: true) }
    }

    /// Houses take a 3×2 footprint above their anchor tile; the map's own buildings are already set
    /// down clear of the roads (`WorldMap.placeOwnBuildings`).
    private func planBuildings() {
        plan.lots = map.lots.map { scenery($0.art, at: $0.anchor) }
        plan.streetDecor = map.streetDecor.map { scenery($0.art, at: $0.cell) }
        plan.buildings = map.buildings.map { scenery($0.art, at: $0.anchor) }
    }

    /// Hand-placed decorations (fountains, blossom trees) from the map's `decor` list.
    private func planDecor() {
        for decor in def.decor ?? [] {
            let anchor = map.spot(x: decor.x, y: decor.y, summit: decor.summit)
            let sprite = art.sprite(decor.art)
            let blocking = decor.blocking ?? true
            let footprint = max(1, Int(sprite.size.width / WorldMap.tileSize * 0.75))
            for dc in 0..<footprint {
                map.occupy(GridPoint(col: anchor.col + dc - footprint / 2, row: anchor.row), blocking: blocking)
            }
            plan.decor.append(scenery(decor.art, at: anchor, sway: decor.art.contains("tree") || decor.art.contains("flower")))
        }
    }

    private func planNPCs() {
        for npc in def.npcs ?? [] {
            let cell = map.spot(of: npc)
            map.occupy(cell, blocking: true)
            plan.npcs.append((npc: npc, cell: cell))
        }
    }

    /// The people who live here (`MapDef.Local`): where each lives and walks to, their things set
    /// down around home and home kept clear of scenery.
    private func planLocals() {
        for (index, local) in (def.locals ?? []).enumerated() {
            guard let home = map.spot(of: local.home) else { continue }
            for prop in local.props ?? [] {
                let cell = GridPoint(col: home.col + prop.x, row: home.row + prop.y)
                let blocking = prop.blocking ?? true
                guard cell != home, map.isFreeForScenery(cell, insideFence: true, blocking: blocking) else { continue }
                map.occupy(cell, blocking: blocking)
                plan.localProps.append(scenery(prop.art, at: cell))
            }
            map.occupy(home, blocking: false)
            let walk = local.walk.flatMap { map.spot(of: $0) }
            plan.locals.append(Crowd.Local(def: local, index: index, home: home, walk: walk))
        }
    }

    #if DEBUG
    /// Debug launches only (`roadside=`): the plan up to what lines the roads, at once, in the
    /// order `planUpToLocals` and `planTheRest` take it (without their pauses).
    func planRoadsidesForDebug() -> [RoadsideLine] {
        planLilyPads()
        occupyBridgeBanks()
        planReeds()
        occupyFence()
        planBuildings()
        planDecor()
        planNPCs()
        planLocals()
        planRoadsides()
        return plan.roadsides
    }
    #endif

    /// How many cells a lined stretch of road runs, fewest to most.
    private static let roadsideLength = 4...10
    /// The chance each stretch of a road's straight edge is lined, where it could be.
    private static let roadsideShare = 0.3
    /// How far in from the lands next door a road's lined, in cells: clear of the band where the
    /// ground gives way to theirs, so no fence stops short at the border.
    private static let roadsideBorderGap = 6.0

    /// Stretches of the land's roads lined here and there (`theme.roadside`; playtesting
    /// 2026-10-15: roads with fences, walls or other scenery along them): along a straight edge of
    /// a road, a picket fence, a low wall of field stones, or a row of one of the land's own props (a
    /// hedge of bushes, an avenue of trees, lanterns), on the cells beside it. Only along a road
    /// wider than a footpath, on open ground with nothing on it, off the hills and the shore, and
    /// well in from the lands next door and the roads' crossings (where the signposts stand). A
    /// cell's kept clear either end, and behind it, so you can always step off the road round it.
    /// Its own stream ("/roadside"), so the draws for everything else stay as they were.
    private func planRoadsides() {
        guard let kinds = def.theme.roadside, !kinds.isEmpty, def.town == nil, def.theme.cave == nil else { return }
        let total = kinds.reduce(0.0) { $0 + max(0, $1.weight ?? 1) }
        guard total > 0 else { return }
        var random = SeededRandom(text: def.id + "/roadside")
        let crossings = map.region?.roads.values.map(\.at) ?? []
        func isRoad(_ cell: GridPoint) -> Bool {
            map.owns(cell) && map.ground[cell.row][cell.col] == .path
        }
        func isOpen(_ cell: GridPoint) -> Bool {
            guard map.owns(cell), map.isFreeForScenery(cell), map.foreign[cell] == nil,
                  map.hillIndex(at: cell) == nil, !map.isSunken(cell) else { return false }
            switch map.ground[cell.row][cell.col] {
            case .ground, .accent, .border: break
            default: return false
            }
            if map.seams.contains(where: { ($0.side(cell) ?? .infinity) < Self.roadsideBorderGap }) { return false }
            return !crossings.contains { max(abs($0.col - cell.col), abs($0.row - cell.row)) < 8 }
        }
        /// Whether `cell` is beside the road on its `side`: the road at least two cells deep the
        /// other way, and open ground on it and behind it.
        func besideRoad(_ cell: GridPoint, _ side: Edge) -> Bool {
            isRoad(cell.stepped(side.opposite)) && isRoad(cell.stepped(side.opposite, by: 2)) && isOpen(cell) && isOpen(cell.stepped(side))
        }
        func pick() -> MapDef.Roadside {
            var left = Double.random(in: 0..<total, using: &random)
            for kind in kinds {
                left -= max(0, kind.weight ?? 1)
                if left < 0 { return kind }
            }
            return kinds[kinds.count - 1]
        }
        /// Sets `kind` down on `cells`, beside the road one after another.
        func line(_ cells: [GridPoint], with kind: MapDef.Roadside) {
            guard kind.kind == "row" else {
                for cell in cells { map.occupy(cell, blocking: true) }
                plan.roadsides.append(RoadsideLine(kind: kind.kind == "wall" ? .wall : .fence, cells: cells))
                return
            }
            guard let art = kind.art, let prop = def.theme.props.first(where: { $0.art == art }) else { return }
            plan.roadsides.append(RoadsideLine(kind: .row, cells: cells))
            let every = max(1, kind.every ?? 1)
            // One size down the row, as if planted together: the middle of the prop's sizes.
            let sizes = prop.size.flatMap { $0.count == 2 && $0[0] <= $0[1] ? $0 : nil } ?? [1, 1]
            let size = (sizes[0] + sizes[1]) / 2
            for (index, cell) in cells.enumerated() {
                guard index % every == 0 else {
                    map.occupy(cell, blocking: false)
                    continue
                }
                map.occupy(cell, blocking: prop.blocking)
                var planted = Placement(art: art, cell: cell, scale: CGFloat(size * Double.random(in: 0.95...1.05, using: &random)))
                planted.prop = prop
                if prop.sway == true {
                    let duration = TimeInterval.random(in: 1.8...2.8, using: &random)
                    let lean = CGFloat.random(in: 0.018...0.03, using: &random)
                    planted.sway = Placement.Sway(duration: duration, lean: lean, start: CGFloat.random(in: -lean...lean, using: &random))
                }
                if let hex = prop.glow, UIColor(hex: hex) != nil {
                    planted.glow = (alpha: CGFloat.random(in: 0.3...0.45, using: &random), duration: Double.random(in: 1.4...2.6, using: &random))
                }
                plan.props.append(planted)
            }
        }
        /// Lines stretches of `run`, the cells beside a road's straight edge on its `side`, here and
        /// there, keeping a cell clear before each and after (and behind those).
        func lineStretches(of run: [GridPoint], _ side: Edge) {
            var start = 1
            while start + Self.roadsideLength.lowerBound < run.count {
                let longest = min(Self.roadsideLength.upperBound, run.count - 1 - start)
                let length = Int.random(in: Self.roadsideLength.lowerBound...longest, using: &random)
                if Double.random(in: 0..<1, using: &random) < Self.roadsideShare {
                    for end in [run[start - 1], run[start + length]] {
                        map.occupy(end, blocking: false)
                        map.occupy(end.stepped(side), blocking: false)
                    }
                    line(Array(run[start..<(start + length)]), with: pick())
                }
                start += length + Int.random(in: 3...8, using: &random)
            }
        }
        for side in [Edge.north, .east, .south, .west] {
            // The cells beside the road on this side run along a row (north or south of it) or a
            // column.
            let eastward = side == .north || side == .south
            let length = eastward ? map.columns : map.rows
            for across in 0..<(eastward ? map.rows : map.columns) {
                var run: [GridPoint] = []
                for along in 0...length {
                    let cell = eastward ? GridPoint(col: along, row: across) : GridPoint(col: across, row: along)
                    if along < length, besideRoad(cell, side) {
                        run.append(cell)
                        continue
                    }
                    if run.count >= Self.roadsideLength.lowerBound + 2 { lineStretches(of: run, side) }
                    run = []
                }
            }
        }
    }

    /// Circles of mushrooms with a sparkle in the middle, like the ones fairies dance in.
    private func planFairyRings() {
        guard let rings = def.theme.fairyRings else { return }
        for _ in 0..<rings.count {
            for _ in 0..<30 {
                guard let middle = map.randomFreeCell(using: &rng) else { break }
                let area = (-2...2).flatMap { dr in (-2...2).map { dc in GridPoint(col: middle.col + dc, row: middle.row + dr) } }
                guard area.allSatisfy({ map.isFreeForScenery($0) && map.height(at: map.center(of: $0)) == 0 }) else { continue }
                area.forEach { map.occupy($0, blocking: false) }
                plan.fairyRings.append(middle)
                break
            }
        }
    }

    /// Boulders on the slopes of rocky hills (`WorldMap.rockiness`), the more the rockier: the
    /// map's own rocks (its props named for a boulder or rock), on the steeper cells, off the trails.
    /// Grassy hills on the gentlest maps get none.
    private func planOutcrops() {
        let rocky = map.rockiness
        guard rocky >= 0.3, !map.hills.isEmpty else { return }
        var kinds = def.theme.props.map(\.art).filter { $0.contains("boulder") || $0.hasSuffix("rock") }
        if kinds.isEmpty { kinds = ["boulder", "small_boulder"] }
        var rocks = SeededRandom(text: def.id + "/outcrops")
        for hill in map.hills {
            for cell in hill.cells.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
                guard map.rise(across: cell) >= 6, map.isFreeForScenery(cell),
                      Double.random(in: 0..<1, using: &rocks) < 0.08 * rocky else { continue }
                let kind = kinds[Int.random(in: 0..<kinds.count, using: &rocks)]
                map.occupy(cell, blocking: true)
                let scale = CGFloat.random(in: 0.7...1.1, using: &rocks)
                plan.outcrops.append(scenery(kind, at: cell, nudge: true, scale: scale))
            }
        }
    }

    /// Scenery from the theme. Props with `cluster` grow in groves around a random centre. None
    /// past the lines the land meets the lands beside it along (`WorldMap.foreign`), where theirs
    /// grows (`planSeamProps`).
    private func planProps(pause: () async -> Void) async {
        for placement in def.theme.props {
            let groupSize = max(1, placement.cluster ?? 1)
            let spread = max(1, placement.spread ?? Int(Double(groupSize).squareRoot().rounded()) + 1)
            var placed = 0
            var attempts = 0
            while placed < placement.count, attempts < placement.count * 3 {
                attempts += 1
                await pause()
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
                          map.foreign[cell] == nil, !isCoast(cell) else { continue }
                    var scale: CGFloat = 1
                    if let range = placement.size, range.count == 2, range[0] <= range[1] {
                        scale = CGFloat(Double.random(in: range[0]...range[1], using: &rng))
                    }
                    plan.props.append(plant(placement, at: cell, scale: scale))
                    inGroup += 1
                }
                placed += inGroup
            }
        }
    }

    /// Past the lines the land meets the lands beside it along (`Seam`), where their ground has come
    /// over onto this one, their scenery (graded as it is there), as thick as it grows there, so the
    /// woods and the meadows run on over the line as the ground does.
    private func planSeamProps(pause: () async -> Void) async {
        guard !map.foreign.isEmpty else { return }
        var random = SeededRandom(text: def.id + "/seams")
        let lands = map.seams.map { Content.shared.map($0.neighbour) }
        for (number, cell) in map.foreign.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }).enumerated() {
            if number % 8 == 7 { await pause() }
            guard let seam = map.foreign[cell], let land = lands[seam] else { continue }
            let area = Double(land.width * land.height)
            for placement in land.theme.props where placement.within == nil {
                guard Double.random(in: 0..<1, using: &random) < Double(placement.count) / area else { continue }
                guard map.isFreeForScenery(cell, blocking: placement.blocking), !isCoast(cell) else { break }
                var scale: CGFloat = 1
                if let range = placement.size, range.count == 2, range[0] <= range[1] {
                    scale = CGFloat(Double.random(in: range[0]...range[1], using: &random))
                }
                var planted = plant(placement, at: cell, scale: scale)
                planted.land = land
                plan.seamProps.append(planted)
                break
            }
        }
    }

    /// Whether a cell is the coast's own, beside the sea, which the shoreline curves through (its tile
    /// cut along it, `GroundTiles`): no prop there, or it stood in the sea (playtesting 2026-10-15).
    private func isCoast(_ cell: GridPoint) -> Bool {
        for dr in -1...1 {
            for dc in -1...1 {
                let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
                let sea = map.contains(next) ? map.ground[next.row][next.col] == .sea : map.isOpenSea(next)
                if sea { return true }
            }
        }
        return false
    }

    /// A prop set down at `cell` as its placement says: taking the cell, nudged, swaying, and how it
    /// glows (the draws in the order `WorldScene` always made them: its nudge and sway, then its glow).
    private func plant(_ placement: MapDef.PropPlacement, at cell: GridPoint, scale: CGFloat) -> Placement {
        map.occupy(cell, blocking: placement.blocking)
        var planted = scenery(placement.art, at: cell, sway: placement.sway == true, nudge: true, scale: scale)
        planted.prop = placement
        if let hex = placement.glow, UIColor(hex: hex) != nil {
            let alpha = CGFloat.random(in: 0.3...0.45, using: &rng)
            let duration = Double.random(in: 1.4...2.6, using: &rng)
            planted.glow = (alpha: alpha, duration: duration)
        }
        return planted
    }

    /// A small sign where each road leaves the map, just off the side of the road.
    private func planSignposts() {
        for exit in def.exits {
            guard Content.shared.map(exit.to) != nil else { continue }
            let cell = signCell(near: exit) ?? map.entryCell(from: exit.edge)
            plan.signposts.append((exit: exit, cell: cell))
            if map.isWalkable(cell) { map.occupy(cell, blocking: true) }
        }
    }

    /// A free cell just off the side of the road out by `exit`, a few tiles in from where it leaves
    /// (on the continent, from where it crosses the border; else from the edge), for its signpost.
    private func signCell(near exit: MapDef.Exit, depth: Int = 4) -> GridPoint? {
        let edge = exit.edge
        let alongColumns = edge == .north || edge == .south
        let line: [GridPoint]
        if let road = map.region?.roads[exit.to] {
            let middle = road.at.stepped(edge.opposite, by: depth)
            line = (-12...12).map { alongColumns ? GridPoint(col: middle.col + $0, row: middle.row) : GridPoint(col: middle.col, row: middle.row + $0) }
        } else {
            line = switch edge {
            case .north: (0..<map.columns).map { GridPoint(col: $0, row: map.rows - 1 - depth) }
            case .south: (0..<map.columns).map { GridPoint(col: $0, row: depth) }
            case .east: (0..<map.rows).map { GridPoint(col: map.columns - 1 - depth, row: $0) }
            case .west: (0..<map.rows).map { GridPoint(col: depth, row: $0) }
            }
        }
        let road = line.indices.filter { map.owns(line[$0]) && map.ground[line[$0].row][line[$0].col] == .path }
        guard let first = road.first, let last = road.last else { return nil }
        for index in [first - 1, last + 1, first - 2, last + 2] where line.indices.contains(index) {
            let cell = line[index]
            if map.isWalkable(cell), map.ground[cell.row][cell.col] != .water { return cell }
        }
        return nil
    }
}
