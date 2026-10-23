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
                    guard Double.random(in: 0..<1, using: &reedRNG) < 0.18, map.isFreeForScenery(land, blocking: false) else { continue }
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
            planLair(of: npc, at: cell)
        }
    }

    /// A boss's lair (`NPCDef.lair`; playtesting 2026-10-23: bosses stood about on open ground): its
    /// pieces set down round it, turned so its way in (the pieces' south, y below 0) faces the land's
    /// middle, where the roads come from, a piece that would land on a road, water or the land next
    /// door, a cave's rock or a cliff left out; then a clearing round it where no tree grows, so it stands in a place of its own.
    private func planLair(of npc: NPCDef, at cell: GridPoint) {
        guard let lair = npc.lair, !lair.isEmpty else { return }
        let toward = (col: map.center.col - cell.col, row: map.center.row - cell.row)
        // Where the way in points after 0 to 3 quarter turns (y up is a row up).
        let ways = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        let turns = (0..<4).max { ways[$0].0 * toward.col + ways[$0].1 * toward.row < ways[$1].0 * toward.col + ways[$1].1 * toward.row } ?? 0
        func turned(_ x: Int, _ y: Int) -> (Int, Int) {
            var (dx, dy) = (x, y)
            for _ in 0..<turns { (dx, dy) = (-dy, dx) }
            return (dx, dy)
        }
        // The way in, straight on from the boss toward the middle, stays clear.
        var taken: Set<GridPoint> = [cell]
        for step in 1...3 {
            let (dx, dy) = turned(0, -step)
            taken.insert(GridPoint(col: cell.col + dx, row: cell.row + dy))
        }
        // Each piece at its spot, else pulled in toward the boss (a summit's top or a cave's chamber
        // has less room than open ground); one that mayn't block where it fits (by a cave's passage)
        // stands there to be walked through.
        var chosen: [(art: String, cell: GridPoint, blocking: Bool)] = []
        for piece in lair {
            let (dx, dy) = turned(piece.x, piece.y)
            let wantsToBlock = piece.blocking ?? true
            for scale in [1.0, 0.7, 0.45] {
                let at = GridPoint(col: cell.col + Int((Double(dx) * scale).rounded()), row: cell.row + Int((Double(dy) * scale).rounded()))
                guard !taken.contains(at), map.owns(at), map.isWalkable(at) else { continue }
                let blocking = wantsToBlock && map.isFreeForScenery(at, blocking: true)
                guard blocking || map.isFreeForScenery(at, blocking: false) else { continue }
                chosen.append((art: piece.art, cell: at, blocking: blocking))
                taken.insert(at)
                break
            }
        }
        // Never walled in: if what blocks would shut the boss in, nothing of the lair blocks.
        let walls = Set(chosen.filter { $0.blocking }.map { $0.cell })
        if !walls.isEmpty, !leavesRoom(around: cell, walls: walls) {
            chosen = chosen.map { (art: $0.art, cell: $0.cell, blocking: false) }
        }
        for piece in chosen {
            map.occupy(piece.cell, blocking: piece.blocking)
            plan.localProps.append(scenery(piece.art, at: piece.cell))
        }
        for dr in -3...3 {
            for dc in -3...3 where dc * dc + dr * dr <= 10 {
                let at = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if map.contains(at) { map.occupy(at, blocking: false) }
            }
        }
    }

    /// Whether, with `walls` blocked too, you can still walk a good way (400 cells) out from beside
    /// `cell`: a lair mustn't shut its boss in (playtesting's test: the Emerald Dragon's, at the end
    /// of its road between hills, did).
    private func leavesRoom(around cell: GridPoint, walls: Set<GridPoint>) -> Bool {
        let steps = [(0, 1), (1, 0), (0, -1), (-1, 0)]
        let starts = steps.map { GridPoint(col: cell.col + $0.0, row: cell.row + $0.1) }.filter { map.isWalkable($0) && !walls.contains($0) }
        var reached = Set(starts)
        var queue = starts
        while let at = queue.popLast(), reached.count < 400 {
            for (dc, dr) in steps {
                let next = GridPoint(col: at.col + dc, row: at.row + dr)
                if map.isWalkable(next), !walls.contains(next), reached.insert(next).inserted { queue.append(next) }
            }
        }
        return reached.count >= 400
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
            for spot in [home] + (walk.map { [$0] } ?? []) { keepInSight(spot) }
            plan.locals.append(Crowd.Local(def: local, index: index, home: home, walk: walk))
        }
    }

    /// Keeps scenery off the ground round where someone stands, a cell behind and beside them and
    /// three in front (lower on screen), where a tree would stand over them: a big tree is about three
    /// cells tall on screen (playtesting 2026-10-20: two of the Seven Hearths' dwarfs stood hidden
    /// behind trees).
    private func keepInSight(_ spot: GridPoint) {
        for dr in -3...1 {
            for dc in -3...1 where dc + dr >= -5 {
                let cell = GridPoint(col: spot.col + dc, row: spot.row + dr)
                if map.contains(cell) { map.occupy(cell, blocking: false) }
            }
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
    private static let roadsideLength = 4...12
    /// The chance each stretch of a road's edge is lined, where it could be.
    private static let roadsideShare = 0.5
    /// How far in from the lands next door a road's lined, in cells: clear of where the ground gives
    /// way most to theirs, so no fence stops short at the border.
    private static let roadsideBorderGap = 6.0
    /// How far from where a road crosses the border it's lined, in cells: its signpost stands there.
    private static let roadsideCrossingGap = 6
    /// How far off a town's wall or fence its roads are lined, in cells: its gates stand clear.
    private static let roadsideWallGap = 3

    /// Stretches of the land's roads lined here and there (`theme.roadside`; playtesting
    /// 2026-10-15: roads with fences, walls or other scenery along them): along a road's edge, a
    /// picket fence, a low wall of field stones, or a row of one of the land's own props (a hedge of
    /// bushes, an avenue of trees, lanterns), on the cells beside it. A row follows the edge, a
    /// cell out or in where the road shifts; a fence or a wall runs straight, and where the edge
    /// steps it ends and starts again a cell on, leaving a gap (one that jogged with the edge
    /// zigzagged; along a road that runs corner to corner, as Frog Swamp's do, only a row fits).
    /// Only along a road wider than a footpath, on open ground with nothing on it, off the hills
    /// and the shore, and well in from the lands next door and the roads' crossings; in a town
    /// only out in its countryside, a few cells off its wall. A cell's kept clear either end, and
    /// behind it, so you can always step off the road round it. Its own stream ("/roadside"), so
    /// the draws for everything else stay as they were. The first try (straight edges only, a
    /// third of them) lined next to nothing on most lands: their roads wander. The second (every
    /// kind straight three cells at least between steps, a fence jogging with each) lined nothing
    /// on Frog Swamp, whose roads all run corner to corner, and its fences zigzagged.
    private func planRoadsides() {
        guard let kinds = def.theme.roadside, !kinds.isEmpty, def.theme.cave == nil else { return }
        let total = kinds.reduce(0.0) { $0 + max(0, $1.weight ?? 1) }
        guard total > 0 else { return }
        var random = SeededRandom(text: def.id + "/roadside")
        let crossings = map.region?.roads.values.map(\.at) ?? []
        // A town's wall or fence, and the cells within `roadsideWallGap` of it.
        var nearWall: Set<GridPoint> = []
        let gap = Self.roadsideWallGap
        for cell in map.fenceCells {
            for dr in -gap...gap {
                for dc in -gap...gap { nearWall.insert(GridPoint(col: cell.col + dc, row: cell.row + dr)) }
            }
        }
        func isRoad(_ cell: GridPoint) -> Bool {
            map.owns(cell) && map.ground[cell.row][cell.col] == .path
        }
        func isOpen(_ cell: GridPoint) -> Bool {
            guard map.owns(cell), map.isFreeForScenery(cell), map.hillIndex(at: cell) == nil, !map.isSunken(cell),
                  !nearWall.contains(cell) else { return false }
            switch map.ground[cell.row][cell.col] {
            case .ground, .accent, .border: break
            default: return false
            }
            if map.seams.contains(where: { ($0.side(cell) ?? .infinity) < Self.roadsideBorderGap }) { return false }
            return !crossings.contains { max(abs($0.col - cell.col), abs($0.row - cell.row)) < Self.roadsideCrossingGap }
        }
        /// Whether `cell` is beside the road on its `side`: the road at least two cells deep the
        /// other way, open ground on it and behind it, and ground you can walk on behind that.
        func besideRoad(_ cell: GridPoint, _ side: Edge) -> Bool {
            isRoad(cell.stepped(side.opposite)) && isRoad(cell.stepped(side.opposite, by: 2)) && isOpen(cell) && isOpen(cell.stepped(side))
                && map.isWalkable(cell.stepped(side, by: 2))
        }
        /// Keeps the two cells behind a line you can't walk through clear of anything that blocks,
        /// so the way round behind it from either end stays open, its steps too.
        func keepBehindClear(_ cells: [GridPoint], _ side: Edge) {
            for cell in cells {
                for depth in 1...2 where map.isFreeForScenery(cell.stepped(side, by: depth)) {
                    map.occupy(cell.stepped(side, by: depth), blocking: false)
                }
            }
        }
        /// How far `b` lies out past `a` toward `side`, in cells.
        func outward(_ a: GridPoint, _ b: GridPoint, _ side: Edge) -> Int {
            switch side {
            case .north: b.row - a.row
            case .south: a.row - b.row
            case .east: b.col - a.col
            case .west: a.col - b.col
            }
        }
        /// The straight runs of `cells` a fence or a wall stands on: it ends where the road's edge
        /// steps out or in and starts again a cell on, a gap you can walk through, as a fence
        /// jogging with each step zigzagged. Runs shorter than a lined stretch's least are left out.
        func runs(_ cells: [GridPoint], _ side: Edge) -> [[GridPoint]] {
            var found: [[GridPoint]] = [], run = [cells[0]]
            for (a, b) in zip(cells, cells.dropFirst()) {
                if outward(a, b, side) == 0 {
                    run.append(b)
                } else {
                    found.append(run)
                    run = []
                }
            }
            found.append(run)
            return found.filter { $0.count >= Self.roadsideLength.lowerBound }
        }
        /// A kind to line a stretch with, by weight; only a row unless it runs `straight` long
        /// enough for a fence or a wall (along a road that runs corner to corner the edge steps
        /// every cell), nil if the land has none.
        func pick(straight: Bool) -> MapDef.Roadside? {
            let fits = straight ? kinds : kinds.filter { $0.kind == "row" }
            let weight = fits.reduce(0.0) { $0 + max(0, $1.weight ?? 1) }
            guard weight > 0 else { return nil }
            var left = Double.random(in: 0..<weight, using: &random)
            for kind in fits {
                left -= max(0, kind.weight ?? 1)
                if left < 0 { return kind }
            }
            return fits[fits.count - 1]
        }
        /// Sets `kind` down on `cells`, beside the road on its `side` one after another; false if
        /// something's taken one of them meanwhile.
        func line(_ cells: [GridPoint], _ side: Edge, with kind: MapDef.Roadside) -> Bool {
            guard kind.kind == "row" else {
                let fences = runs(cells, side)
                guard !fences.isEmpty, cells.allSatisfy({ map.isFreeForScenery($0) }) else { return false }
                for fence in fences {
                    for cell in fence { map.occupy(cell, blocking: true) }
                    plan.roadsides.append(RoadsideLine(kind: kind.kind == "wall" ? .wall : .fence, cells: fence))
                }
                // Its gaps stay open, and the ground behind it all along.
                for cell in cells where map.isFreeForScenery(cell) { map.occupy(cell, blocking: false) }
                keepBehindClear(cells, side)
                return true
            }
            guard let art = kind.art, let prop = def.theme.props.first(where: { $0.art == art }),
                  cells.allSatisfy({ map.isFreeForScenery($0) }) else { return false }
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
            // A hedge you can't walk through is a fence too.
            if every == 1, prop.blocking { keepBehindClear(cells, side) }
            return true
        }
        /// Lines stretches of `chain`, the cells beside a road's edge on its `side` one after
        /// another, here and there, keeping a cell clear before each and after (and behind those).
        func lineStretches(of chain: [GridPoint], _ side: Edge) {
            var start = 1
            while start + Self.roadsideLength.lowerBound < chain.count {
                let longest = min(Self.roadsideLength.upperBound, chain.count - 1 - start)
                let length = Int.random(in: Self.roadsideLength.lowerBound...longest, using: &random)
                let cells = Array(chain[start..<(start + length)])
                if Double.random(in: 0..<1, using: &random) < Self.roadsideShare,
                   let kind = pick(straight: !runs(cells, side).isEmpty), line(cells, side, with: kind) {
                    for end in [chain[start - 1], chain[start + length]] {
                        map.occupy(end, blocking: false)
                        map.occupy(end.stepped(side), blocking: false)
                    }
                }
                start += length + Int.random(in: 2...6, using: &random)
            }
        }
        // The cells already in a chain: beside a road that runs corner to corner, a cell lies beside
        // it two ways (north of it and west of it, say), so it's lined from one of them only.
        var used: Set<GridPoint> = []
        for side in [Edge.north, .east, .south, .west] {
            // The cells beside the road on this side, by how far along the row (north or south of
            // it) or the column they lie.
            let eastward = side == .north || side == .south
            let length = eastward ? map.columns : map.rows
            func cell(_ along: Int, _ across: Int) -> GridPoint {
                eastward ? GridPoint(col: along, row: across) : GridPoint(col: across, row: along)
            }
            var beside = [[Int]](repeating: [], count: length + 1)
            for across in 0..<(eastward ? map.rows : map.columns) {
                for along in 0..<length where besideRoad(cell(along, across), side) { beside[along].append(across) }
            }
            // Chains along the edge, from where each begins: on along it a cell at a time, a cell
            // out or in where the edge steps (every cell along a road that runs corner to corner).
            for along in 0..<length {
                for first in beside[along] where !used.contains(cell(along, first)) {
                    var chain = [cell(along, first)]
                    used.insert(chain[0])
                    var across = first, at = along
                    while at + 1 < length {
                        let options = beside[at + 1]
                        let step = [across, across - 1, across + 1].first { options.contains($0) }
                        guard let next = step, !used.contains(cell(at + 1, next)) else { break }
                        across = next
                        at += 1
                        chain.append(cell(at, across))
                        used.insert(chain[chain.count - 1])
                    }
                    if chain.count >= Self.roadsideLength.lowerBound + 2 { lineStretches(of: chain, side) }
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
            let gap = pathGap(placement)
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
                          map.foreign[cell] == nil, !isCoast(cell), !placement.blocking || roomOnIsland(cell),
                          gap == 0 || !nearPath(cell, within: gap) else { continue }
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

    /// How many cells a prop in the way keeps off the paths: as far as it spreads past its own cell
    /// at its biggest (playtesting 2026-10-20: big snowy trees beside a forest path closed it in).
    /// None for an ordinary tree; a cell for the big ones.
    private func pathGap(_ placement: MapDef.PropPlacement) -> Int {
        guard placement.blocking else { return 0 }
        let width = art.sprite(placement.art).size.width * CGFloat(placement.size?.last ?? 1)
        return max(0, Int(((width / WorldMap.tileSize - 1) / 2).rounded()))
    }

    /// Whether a road or path of the land's own runs within `reach` cells of `cell`.
    private func nearPath(_ cell: GridPoint, within reach: Int) -> Bool {
        for dr in -reach...reach {
            for dc in -reach...reach {
                let other = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if map.owns(other), map.ground[other.row][other.col] == .path { return true }
            }
        }
        return false
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
                guard map.isFreeForScenery(cell, blocking: placement.blocking), !isCoast(cell),
                      !placement.blocking || roomOnIsland(cell) else { break }
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

    /// The lakes' islands (`WorldMap.lakes`).
    private lazy var islands: Set<GridPoint> = Set(map.lakes.flatMap { $0.island })

    /// Whether something in the way may stand in `cell`: anywhere off the lakes' islands, but on one
    /// only here and there round its shore and not beside its footbridge, so you can walk about on it
    /// (it grew into a thicket, playtesting 2026-10-16). Flowers and the like grow all over it.
    private func roomOnIsland(_ cell: GridPoint) -> Bool {
        guard islands.contains(cell) else { return true }
        var shore = false
        for dr in -1...1 {
            for dc in -1...1 {
                let next = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if map.bridgeCells.contains(next) { return false }
                if !islands.contains(next) { shore = true }
            }
        }
        // One shore cell in five, the same ones every visit.
        return shore && (cell.col * 2 + cell.row * 3) % 5 == 0
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

    /// A small sign where each road leaves the map, just off the side of the road. Never where you
    /// arrive, nor where it would close the way (playtesting 2026-10-16: in the Rat Cavern's narrow
    /// tunnels there was no room beside the road, so the sign stood where you came in from Lotus Land
    /// and shut you in); with no room for it anywhere near, the road has none.
    private func planSignposts() {
        // Where you arrive by each road, before any sign's set down.
        let arrivals = def.exits.map { map.entryCell(from: $0.edge) }
        for exit in def.exits where Content.shared.map(exit.to) != nil {
            var spot: GridPoint?
            for depth in Self.signDepths where spot == nil {
                spot = signCell(near: exit, depth: depth, clearOf: arrivals)
            }
            guard let cell = spot else { continue }
            plan.signposts.append((exit: exit, cell: cell))
            map.occupy(cell, blocking: true)
        }
    }

    /// How many cells in from where a road leaves its signpost may stand, the likeliest first.
    private static let signDepths = [4, 5, 6, 3, 7, 8]

    /// Whether something standing in `cell` leaves every way past it open: the cells you could step
    /// to from it still reach each other round it. You walk one way at a time (`canStand` is tried
    /// across, then up or down), so only cells side by side join; corner to corner doesn't.
    private func keepsTheWayOpen(_ cell: GridPoint) -> Bool {
        // The eight cells round it, in order round the ring: those beside it at the even places.
        let ring = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        let open: [Bool] = ring.map { step in
            let next = GridPoint(col: cell.col + step.0, row: cell.row + step.1)
            return map.isWalkable(next) && map.ground[next.row][next.col] != .water
        }
        guard let shut = open.firstIndex(of: false) else { return true }
        // The open cells make runs round the ring, broken where one's shut; the cells beside it that
        // are open must all be in one run.
        var run = 0
        var runsBeside: Set<Int> = []
        for offset in 1...8 {
            let index = (shut + offset) % 8
            if !open[index] { run += 1 } else if index % 2 == 0 { runsBeside.insert(run) }
        }
        return runsBeside.count <= 1
    }

    /// A free cell just off the side of the road out by `exit`, `depth` tiles in from where it leaves
    /// (on the continent, from where it crosses the border, or for a road into a cave inland from
    /// its mouth; else from the edge), for its signpost: not beside where you arrive (`arrivals`),
    /// and closing no way past it.
    private func signCell(near exit: MapDef.Exit, depth: Int, clearOf arrivals: [GridPoint]) -> GridPoint? {
        let edge = exit.edge
        let line: [GridPoint]
        if let road = map.region?.roads[exit.to] {
            let way = road.into ?? edge
            let alongColumns = way == .north || way == .south
            let middle = road.at.stepped(way.opposite, by: depth)
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
            guard map.isWalkable(cell), map.ground[cell.row][cell.col] != .water, keepsTheWayOpen(cell) else { continue }
            if arrivals.contains(where: { max(abs($0.col - cell.col), abs($0.row - cell.row)) <= 1 }) { continue }
            return cell
        }
        return nil
    }
}
