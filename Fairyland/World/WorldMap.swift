import GameplayKit

nonisolated enum Ground {
    case ground, path, accent, border, water
}

nonisolated struct GridPoint: Hashable {
    var col: Int
    var row: Int
}

extension GridPoint {
    init(_ vector: vector_int2) {
        self.init(col: Int(vector.x), row: Int(vector.y))
    }

    var vector: vector_int2 { vector_int2(Int32(col), Int32(row)) }
}

/// The grid for one map: ground layout, blocked cells, exits and A* pathfinding.
///
/// Fairyland Online was 2.5D, not flat top-down: the grid is turned 45° and squashed to half
/// height (a 2:1 isometric diamond). Game logic works on the square grid; `project` and
/// `unproject` convert to and from on-screen positions.
final class WorldMap {
    /// Size of a grid cell before projection (on screen a cell is a ~62×31 diamond).
    static let tileSize: CGFloat = 44

    static func project(_ grid: CGPoint) -> CGPoint {
        let c = CGFloat(0.5).squareRoot()
        return CGPoint(x: (grid.x - grid.y) * c, y: (grid.x + grid.y) * c * 0.5)
    }

    static func unproject(_ point: CGPoint) -> CGPoint {
        let c = CGFloat(0.5).squareRoot()
        let difference = point.x / c
        let sum = point.y / (c * 0.5)
        return CGPoint(x: (sum + difference) / 2, y: (sum - difference) / 2)
    }
    /// Width of the grass ring outside a fenced town.
    static let townBorder = 2

    let def: MapDef
    let columns: Int
    let rows: Int
    let center: GridPoint
    /// ground[row][col], row 0 at the bottom (SpriteKit's y-up).
    private(set) var ground: [[Ground]]
    private(set) var fenceCells: [GridPoint] = []
    /// Each pond's water cells, for lily pads.
    private(set) var ponds: [[GridPoint]] = []
    /// Town planning results: where each building and bit of street furniture goes.
    private(set) var lots: [(art: String, anchor: GridPoint)] = []
    /// The map's own buildings (`buildings` in maps.json), each where it was put or, if that's on a
    /// road or another building, on the nearest clear plot (`placeOwnBuildings`).
    private(set) var buildings: [(art: String, anchor: GridPoint)] = []
    private(set) var streetDecor: [(art: String, cell: GridPoint)] = []
    /// Raised terraces: their rectangles in grid cells (min corner inclusive), and stair cells.
    private(set) var terraces: [(origin: GridPoint, width: Int, height: Int, stairs: [GridPoint])] = []
    /// A town's raised terraces (`height(at:)`): each stands `height` points up; its rim is a wall
    /// but at its stairs.
    private(set) var plateaus: [Plateau] = []
    /// Which plateau each raised cell belongs to.
    private var plateauOf: [GridPoint: Int] = [:]
    /// The hills out in the fields (`theme.hills`).
    private(set) var hills: [Hill] = []
    /// Which hill each cell it rises over belongs to.
    private var hillOf: [GridPoint: Int] = [:]
    /// The cells the hills' trails run over (for the minimap).
    private(set) var trailCells: Set<GridPoint> = []

    /// The hill rising over `cell`, if any (an index into `hills`).
    func hillIndex(at cell: GridPoint) -> Int? { hillOf[cell] }

    /// How rocky its hills are, from 0, grassy slopes on the gentlest maps, to 1, steep and rocky on
    /// the most dangerous: `theme.hills.rocky`, or from the levels of the monsters met there.
    var rockiness: Double {
        if let rocky = def.theme.hills?.rocky { return min(1, max(0, rocky)) }
        guard let levels = def.encounters?.levels, let low = levels.first, let high = levels.last else { return 0 }
        return min(1, max(0, (Double(low + high) / 2 - 15) / 70))
    }

    /// How much the ground rises across `cell`, in points (0 off the hills).
    func rise(across cell: GridPoint) -> CGFloat {
        guard let index = hillOf[cell] else { return 0 }
        let hill = hills[index]
        let corners = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.5, 0.5)].map {
            hill.height(atCells: Double(cell.col) + $0.0, Double(cell.row) + $0.1)
        }
        return (corners.max() ?? 0) - (corners.min() ?? 0)
    }

    nonisolated struct Plateau {
        /// Which way a ramp faces, down its slope: toward the row in front (south) or the column in
        /// front (west), the two sides that face you. It climbs from the ground there to the top.
        nonisolated enum Ramp { case south, west }
        let cells: Set<GridPoint>
        let ramps: [GridPoint: Ramp]
        let height: CGFloat
        /// The smallest and largest column and row it covers.
        var bounds: (min: GridPoint, max: GridPoint) {
            (GridPoint(col: cells.map(\.col).min() ?? 0, row: cells.map(\.row).min() ?? 0),
             GridPoint(col: cells.map(\.col).max() ?? 0, row: cells.map(\.row).max() ?? 0))
        }
    }
    /// Cave rock: solid cells drawn as raised walls (only on maps with a `cave` theme).
    private(set) var rock: Set<GridPoint> = []
    /// Where a road leads into a cave, a range of rocky hills rises along that side of the map and
    /// on out past its edge, the cave's mouth in its side (`raiseCrags`): which side, the cave, and
    /// the range (an index into `hills`).
    nonisolated struct Crag {
        let edge: Edge
        let cave: MapDef.Cave
        let hill: Int
    }
    private(set) var crags: [Crag] = []
    /// The map's cells a crag's range rises over, kept clear of ponds (and, taken, of scenery and
    /// the other hills).
    private var cragGround: Set<GridPoint> = []
    /// The middles of a cave's galleries and tunnels, kept clear of scenery so they stay open.
    private var passages: Set<GridPoint> = []
    private var occupied: Set<GridPoint> = []
    private var blocked: Set<GridPoint> = []
    private let graph: GKGridGraph<GKGridGraphNode>

    /// The projected map's on-screen bounding box.
    var bounds: CGRect {
        let width = CGFloat(columns) * Self.tileSize
        let height = CGFloat(rows) * Self.tileSize
        let corners = [CGPoint.zero, CGPoint(x: width, y: 0), CGPoint(x: 0, y: height), CGPoint(x: width, y: height)].map(Self.project)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// `caveOf`: the cave a map is, if it is one (by its id), for the roads that lead into caves.
    init(def: MapDef, caveOf: (String) -> MapDef.Cave? = { Content.shared.map($0)?.theme.cave }) {
        self.def = def
        columns = def.width
        rows = def.height
        center = GridPoint(col: def.width / 2, row: def.height / 2)
        ground = Array(repeating: Array(repeating: .ground, count: def.width), count: def.height)
        graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: Int32(def.width),
            height: Int32(def.height),
            diagonalsAllowed: true
        )
        // Seeded by the map id, so every map looks the same each time you visit.
        var rng = SeededRandom(text: def.id)
        if def.fence == true { layOutTownBorder() }
        for exit in def.exits { carveRoad(for: exit, &rng) }
        for trail in def.trails ?? [] { carveTrail(trail, &rng) }
        // Caves dig their ponds first and then a chamber around each one.
        let ponds = def.theme.water != nil ? def.theme.ponds : nil
        if let cave = def.theme.cave {
            if let ponds { digPonds(ponds, &rng) }
            digCave(cave, &rng)
        }
        if let town = def.town {
            planTown(town, &rng)
        } else {
            placeOwnBuildings()
            keepNPCsInView()
        }
        var ranges: [(edge: Edge, cave: MapDef.Cave, hill: Hill)] = []
        if def.theme.cave == nil, def.town == nil {
            // Its own random numbers, so the rest of the map comes out as it did before.
            var cragRNG = SeededRandom(text: def.id + "/crags")
            for exit in def.exits {
                guard let cave = caveOf(exit.to), let range = raiseCrags(along: exit.edge, &cragRNG) else { continue }
                ranges.append((exit.edge, cave, range))
            }
        }
        if def.theme.cave == nil, let ponds { digPonds(ponds, &rng) }
        if def.town == nil, def.theme.cave == nil, let hills = def.theme.hills { raiseHills(hills, &rng) }
        // The ranges where roads lead into caves join the hills after them, so the hills keep their
        // places in the list.
        for range in ranges {
            for cell in range.hill.cells where contains(cell) { hillOf[cell] = self.hills.count }
            crags.append(Crag(edge: range.edge, cave: range.cave, hill: self.hills.count))
            self.hills.append(range.hill)
        }
        if def.town == nil, def.theme.cave == nil, def.theme.hills != nil { layFootpaths() }
        if def.theme.accent != nil {
            if let patches = def.theme.accentPatches {
                paintAccentPatches(patches, &rng)
            } else {
                scatterAccents(&rng)
            }
        }
    }

    // MARK: Coordinates

    /// The cell under an on-screen point, clamped to the map.
    func cell(at point: CGPoint) -> GridPoint {
        let raw = rawCell(at: point)
        return GridPoint(col: min(max(raw.col, 0), columns - 1), row: min(max(raw.row, 0), rows - 1))
    }

    // MARK: Elevation

    /// How high the ground stands at a point in grid space (unprojected): on a hill, its slope's
    /// height there; a plateau's height on top of it, part of it on a ramp (rising from its foot to
    /// the top); and 0 elsewhere.
    func height(atGrid grid: CGPoint) -> CGFloat {
        let cell = GridPoint(col: Int((grid.x / Self.tileSize).rounded(.down)), row: Int((grid.y / Self.tileSize).rounded(.down)))
        if let index = hillOf[cell] { return hills[index].height(atCells: grid.x / Self.tileSize, grid.y / Self.tileSize) }
        guard let index = plateauOf[cell] else { return 0 }
        let plateau = plateaus[index]
        let rise: CGFloat? = switch plateau.ramps[cell] {
        case .south: grid.y / Self.tileSize - CGFloat(cell.row)
        case .west: grid.x / Self.tileSize - CGFloat(cell.col)
        case nil: nil
        }
        return plateau.height * min(1, max(0, rise ?? 1))
    }

    /// How high the ground stands under an on-screen (ground) point: walkers and scenery standing
    /// there are drawn this much higher.
    func height(at point: CGPoint) -> CGFloat {
        plateaus.isEmpty && hills.isEmpty ? 0 : height(atGrid: Self.unproject(point))
    }

    /// The ground point a tap at `point` means. Raised ground hides the ground behind it, so a tap
    /// on a terrace is a tap on its top: tops first, then ramps, then the ground itself.
    func groundPoint(under point: CGPoint) -> CGPoint {
        guard !plateaus.isEmpty || !hills.isEmpty else { return point }
        if !hills.isEmpty {
            // A hill is never steeper than the view (`Hill.Lobe.band`), so going up the screen the ground
            // under it only ever rises: exactly one ground point lands on the spot. Found by halving.
            var low = point.y - (hills.map(\.highest).max() ?? 0) - 1, high = point.y
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if middle + height(at: CGPoint(x: point.x, y: middle)) > point.y { high = middle } else { low = middle }
            }
            return CGPoint(x: point.x, y: (low + high) / 2)
        }
        for height in Set(plateaus.map(\.height)).sorted(by: >) {
            let candidate = CGPoint(x: point.x, y: point.y - height)
            if abs(self.height(at: candidate) - height) < 0.5 { return candidate }
        }
        var guess = point
        for _ in 0..<4 { guess = CGPoint(x: point.x, y: point.y - height(at: guess)) }
        return guess
    }

    /// The cell under an on-screen point, possibly outside the map.
    func rawCell(at point: CGPoint) -> GridPoint {
        let grid = Self.unproject(point)
        return GridPoint(col: Int((grid.x / Self.tileSize).rounded(.down)), row: Int((grid.y / Self.tileSize).rounded(.down)))
    }

    /// A cell relative to the map centre (content uses x/y offsets, y up).
    func offset(_ x: Int, _ y: Int) -> GridPoint {
        GridPoint(col: center.col + x, row: center.row + y)
    }

    /// On-screen centre of a cell's diamond.
    func center(of cell: GridPoint) -> CGPoint {
        Self.project(CGPoint(x: (CGFloat(cell.col) + 0.5) * Self.tileSize, y: (CGFloat(cell.row) + 0.5) * Self.tileSize))
    }

    /// Where something standing in `cell` should be anchored.
    func base(of cell: GridPoint) -> CGPoint {
        center(of: cell) + CGVector(dx: 0, dy: -4)
    }

    /// 0...1 position of a cell for maps and minimaps (top-left origin, north up).
    func unitPosition(of cell: GridPoint) -> CGPoint {
        CGPoint(x: (CGFloat(cell.col) + 0.5) / CGFloat(columns), y: 1 - (CGFloat(cell.row) + 0.5) / CGFloat(rows))
    }

    func contains(_ cell: GridPoint) -> Bool {
        cell.col >= 0 && cell.row >= 0 && cell.col < columns && cell.row < rows
    }

    func isWalkable(_ cell: GridPoint) -> Bool {
        contains(cell) && !blocked.contains(cell)
    }

    // MARK: Exits

    /// The exit edge `cell` touches, if any — step on the outermost row of an exit to leave.
    func exit(at cell: GridPoint) -> MapDef.Exit? {
        def.exits.first { exit in
            switch exit.edge {
            case .north: cell.row == rows - 1
            case .south: cell.row == 0
            case .east: cell.col == columns - 1
            case .west: cell.col == 0
            }
        }
    }

    /// How many cells `cell` is from the edge of `exit` (0 = standing on the way out).
    func distance(from cell: GridPoint, to edge: Edge) -> Int {
        switch edge {
        case .north: rows - 1 - cell.row
        case .south: cell.row
        case .east: columns - 1 - cell.col
        case .west: cell.col
        }
    }

    /// Road cells one step in from `edge`, where a barricade closes a road.
    func roadCells(near edge: Edge) -> [GridPoint] {
        switch edge {
        case .north: (0..<columns).filter { ground[rows - 2][$0] == .path }.map { GridPoint(col: $0, row: rows - 2) }
        case .south: (0..<columns).filter { ground[1][$0] == .path }.map { GridPoint(col: $0, row: 1) }
        case .east: (0..<rows).filter { ground[$0][columns - 2] == .path }.map { GridPoint(col: columns - 2, row: $0) }
        case .west: (0..<rows).filter { ground[$0][1] == .path }.map { GridPoint(col: 1, row: $0) }
        }
    }

    /// Where you arrive when entering through `edge`: on the road, a couple of tiles in.
    func entryCell(from edge: Edge) -> GridPoint {
        let cell = switch edge {
        case .north: GridPoint(col: roadColumn(near: rows - 3), row: rows - 3)
        case .south: GridPoint(col: roadColumn(near: 2), row: 2)
        case .east: GridPoint(col: columns - 3, row: roadRow(near: columns - 3))
        case .west: GridPoint(col: 2, row: roadRow(near: 2))
        }
        return nearestWalkable(to: cell) ?? center
    }

    /// The road column closest to the centre on `row` (roads are two tiles wide).
    private func roadColumn(near row: Int) -> Int {
        (0..<columns).filter { ground[row][$0] == .path }.min { abs($0 - center.col) < abs($1 - center.col) } ?? center.col
    }

    private func roadRow(near col: Int) -> Int {
        (0..<rows).filter { ground[$0][col] == .path }.min { abs($0 - center.row) < abs($1 - center.row) } ?? center.row
    }

    // MARK: Placement

    /// Reserves a cell; blocking things also take it out of the walk graph.
    func occupy(_ cell: GridPoint, blocking: Bool) {
        guard contains(cell) else { return }
        occupied.insert(cell)
        guard blocking, !blocked.contains(cell), let node = graph.node(atGridPosition: cell.vector) else { return }
        graph.remove([node])
        blocked.insert(cell)
    }

    /// Whether scenery may go in `cell`: free, off roads and water, clear of the centre and
    /// the arrival spots, and (in fenced towns) outside the fence.
    /// `insideFence` lets town-square planting use the town's ground, not just its border.
    /// Things you can walk through (`blocking` false) may sit in a cave's passages.
    func isFreeForScenery(_ cell: GridPoint, insideFence: Bool = false, blocking: Bool = true) -> Bool {
        guard cell.col >= 1, cell.row >= 1, cell.col < columns - 1, cell.row < rows - 1 else { return false }
        guard !occupied.contains(cell) else { return false }
        if blocking, !passages.isEmpty, (-1...1).contains(where: { dc in (-1...1).contains { dr in passages.contains(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }) {
            return false
        }
        let tile = ground[cell.row][cell.col]
        guard tile != .path, tile != .water else { return false }
        guard max(abs(cell.col - center.col), abs(cell.row - center.row)) > 2 else { return false }
        if def.fence == true, (insideFence ? tile != .ground : tile != .border) { return false }
        for entry in entryCells where max(abs(cell.col - entry.col), abs(cell.row - entry.row)) <= 2 {
            return false
        }
        return true
    }

    private var cachedEntryCells: [GridPoint]?

    private var entryCells: [GridPoint] {
        if let cachedEntryCells { return cachedEntryCells }
        let cells = def.exits.map { entryCell(from: $0.edge) }
        cachedEntryCells = cells
        return cells
    }

    /// A random free cell for scenery.
    func randomFreeCell(blocking: Bool = true, using rng: inout SeededRandom) -> GridPoint? {
        for _ in 0..<400 {
            let cell = GridPoint(col: Int.random(in: 1..<(columns - 1), using: &rng), row: Int.random(in: 1..<(rows - 1), using: &rng))
            if isFreeForScenery(cell, blocking: blocking) { return cell }
        }
        return nil
    }

    /// A free cell within `radius` cells of the map's centre, for planting around a town square.
    func randomFreeCell(within radius: Int, using rng: inout SeededRandom) -> GridPoint? {
        for _ in 0..<400 {
            let cell = GridPoint(col: center.col + Int.random(in: -radius...radius, using: &rng),
                                 row: center.row + Int.random(in: -radius...radius, using: &rng))
            if isFreeForScenery(cell, insideFence: true) { return cell }
        }
        return nil
    }

    /// A walkable cell within `radius` of `cell` for background characters to stroll to:
    /// never on the map's edge (where the exits are), and inside the fence in towns.
    func strollTarget(near cell: GridPoint, radius: Int, using rng: inout some RandomNumberGenerator) -> GridPoint? {
        for _ in 0..<24 {
            let candidate = GridPoint(col: cell.col + Int.random(in: -radius...radius, using: &rng),
                                      row: cell.row + Int.random(in: -radius...radius, using: &rng))
            guard candidate.col > 0, candidate.row > 0, candidate.col < columns - 1, candidate.row < rows - 1,
                  isWalkable(candidate) else { continue }
            if def.fence == true, ground[candidate.row][candidate.col] == .border { continue }
            return candidate
        }
        return nil
    }

    // MARK: Pathfinding

    /// Waypoints from `start` to `end` around blocked cells. Empty if unreachable.
    func path(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        guard let startCell = nearestWalkable(to: cell(at: start)),
              let goalCell = nearestWalkable(to: cell(at: end)),
              let from = graph.node(atGridPosition: startCell.vector),
              let to = graph.node(atGridPosition: goalCell.vector)
        else { return [] }

        // Stop exactly where the player tapped when that spot is walkable.
        let goal = goalCell == cell(at: end) ? end : center(of: goalCell)
        if startCell == goalCell { return [goal] }

        let nodes = graph.findPath(from: from, to: to).compactMap { $0 as? GKGridGraphNode }
        guard nodes.count > 1 else { return [] }
        var points = nodes.dropFirst().map { center(of: GridPoint($0.gridPosition)) }
        points[points.count - 1] = goal
        return points
    }

    func nearestWalkable(to cell: GridPoint) -> GridPoint? {
        if isWalkable(cell) { return cell }
        for radius in 1...8 {
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dr), abs(dc)) == radius {
                    let candidate = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    if isWalkable(candidate) { return candidate }
                }
            }
        }
        return nil
    }

    // MARK: Generation

    /// Towns: a grass ring around the edge with a fence just inside it and gates at the exits.
    private func layOutTownBorder() {
        let ring = Self.townBorder
        for row in 0..<rows {
            for col in 0..<columns {
                let inset = min(col, row, columns - 1 - col, rows - 1 - row)
                if inset < ring {
                    ground[row][col] = .border
                } else if inset == ring {
                    fenceCells.append(GridPoint(col: col, row: row))
                }
            }
        }
    }

    /// A cell offset from the centre (content's [x, y]), at the middle of that cell.
    private func point(_ offset: [Int]) -> CGPoint {
        CGPoint(x: CGFloat(center.col + (offset.first ?? 0)) + 0.5, y: CGFloat(center.row + (offset.count > 1 ? offset[1] : 0)) + 0.5)
    }

    /// A road from the hub (the centre unless the map says otherwise) out through an exit, via
    /// any waypoints the map gives it, winding along a smooth curve and swelling and narrowing a
    /// little (towns keep theirs tidier). The last stretch runs straight at the edge so exits and
    /// arrivals line up.
    private func carveRoad(for exit: MapDef.Exit, _ rng: inout SeededRandom) {
        let middle = point([0, 0])
        let along = CGFloat(exit.at ?? 0)
        let x = min(max(middle.x + along, 4), CGFloat(columns - 4))
        let y = min(max(middle.y + along, 4), CGFloat(rows - 4))
        let (end, inward): (CGPoint, CGVector) = switch exit.edge {
        case .east: (CGPoint(x: CGFloat(columns), y: y), CGVector(dx: -1, dy: 0))
        case .west: (CGPoint(x: 0, y: y), CGVector(dx: 1, dy: 0))
        case .north: (CGPoint(x: x, y: CGFloat(rows)), CGVector(dx: 0, dy: -1))
        case .south: (CGPoint(x: x, y: 0), CGVector(dx: 0, dy: 1))
        }
        let approach = end + inward * 5
        let stops = [point(def.hub ?? [0, 0])] + (exit.via ?? []).map(point) + [approach]
        carve(through: stops, then: [end], halfWidth: 1.05, &rng)
    }

    /// A narrower path to somewhere worth visiting, from the hub (or `from`) via any waypoints.
    private func carveTrail(_ trail: MapDef.Trail, _ rng: inout SeededRandom) {
        let stops = [point(trail.from ?? def.hub ?? [0, 0])] + (trail.via ?? []).map(point) + [point(trail.to)]
        carve(through: stops, then: [], halfWidth: 0.8, &rng)
    }

    private func carve(through stops: [CGPoint], then tail: [CGPoint], halfWidth base: CGFloat, _ rng: inout SeededRandom) {
        let fenced = def.fence == true
        // Waypoints between the stops, pushed sideways by a smooth random drift.
        var points = [stops[0]]
        var drift: CGFloat = 0
        let sway: CGFloat = fenced ? 1 : 6
        for (a, b) in zip(stops, stops.dropFirst()) {
            let length = a.distance(to: b)
            let back = length > 0 ? CGVector(dx: (a.x - b.x) / length, dy: (a.y - b.y) / length) : CGVector(dx: 0, dy: 1)
            let side = CGVector(dx: -back.dy, dy: back.dx)
            let count = max(2, Int(length / 8))
            for k in 1..<count {
                drift = min(max(drift + CGFloat.random(in: -3...3, using: &rng), -sway), sway)
                let t = CGFloat(k) / CGFloat(count)
                var point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) + side * drift
                point.x = min(max(point.x, 4), CGFloat(columns - 4))
                point.y = min(max(point.y, 4), CGFloat(rows - 4))
                points.append(point)
            }
            points.append(b)
        }
        points += tail

        // Paint along a Catmull-Rom curve through the waypoints.
        var travelled: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)], p1 = points[index], p2 = points[index + 1], p3 = points[min(points.count - 1, index + 2)]
            let steps = max(4, Int(p1.distance(to: p2) * 4))
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = Self.catmullRom(p0, p1, p2, p3, t)
                travelled += p1.distance(to: p2) / CGFloat(steps)
                let halfWidth = fenced ? base : base + base / 3 * sin(travelled / 6)
                paintRoad(around: point, radius: halfWidth)
            }
        }
    }

    private func paintRoad(around point: CGPoint, radius: CGFloat) {
        let reach = Int(radius.rounded(.up)) + 1
        let middle = GridPoint(col: Int(point.x), row: Int(point.y))
        for dr in -reach...reach {
            for dc in -reach...reach {
                let cell = GridPoint(col: middle.col + dc, row: middle.row + dr)
                guard contains(cell) else { continue }
                let cellCenter = CGPoint(x: CGFloat(cell.col) + 0.5, y: CGFloat(cell.row) + 0.5)
                guard cellCenter.distance(to: point) <= radius else { continue }
                ground[cell.row][cell.col] = .path
                fenceCells.removeAll { $0 == cell }   // gate
            }
        }
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y))
    }

    // MARK: Caves

    /// Fills the map with rock, then digs it out: wide galleries around the roads and trails,
    /// a chamber where they meet and around each character, more chambers joined on by short
    /// tunnels, and dead-end tunnels branching off. The edges are roughened, pockets that can't
    /// be reached are filled back in, and the map's edge stays solid except where roads leave.
    private func digCave(_ cave: MapDef.Cave, _ rng: inout SeededRandom) {
        guard columns > 12, rows > 12 else { return }
        var open = Array(repeating: Array(repeating: false, count: columns), count: rows)
        func dig(_ p: CGPoint, _ radius: CGFloat) {
            let reach = Int(radius) + 1
            let middle = GridPoint(col: Int(p.x), row: Int(p.y))
            for dr in -reach...reach {
                for dc in -reach...reach {
                    let cell = GridPoint(col: middle.col + dc, row: middle.row + dr)
                    guard contains(cell), CGPoint(x: CGFloat(cell.col) + 0.5, y: CGFloat(cell.row) + 0.5).distance(to: p) <= radius else { continue }
                    open[cell.row][cell.col] = true
                }
            }
        }
        func tunnel(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) {
            let steps = max(1, Int(a.distance(to: b) * 2))
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                dig(p, radius)
                passages.insert(GridPoint(col: Int(p.x), row: Int(p.y)))
            }
        }
        /// A tunnel with a sideways jog halfway, so it doesn't run dead straight.
        func bentTunnel(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) {
            let length = max(a.distance(to: b), 0.001)
            let jog = CGFloat(Double.random(in: -0.35...0.35, using: &rng)) * length
            let mid = CGPoint(x: (a.x + b.x) / 2 - (b.y - a.y) / length * jog, y: (a.y + b.y) / 2 + (b.x - a.x) / length * jog)
            tunnel(a, mid, radius)
            tunnel(mid, b, radius)
        }
        func clamped(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, 3), CGFloat(columns - 3)), y: min(max(p.y, 3), CGFloat(rows - 3)))
        }
        func nearestOpen(to p: CGPoint) -> CGPoint? {
            var best: (CGPoint, CGFloat)?
            for row in 0..<rows {
                for col in 0..<columns where open[row][col] {
                    let q = CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)
                    let d = q.distance(to: p)
                    if best == nil || d < best!.1 { best = (q, d) }
                }
            }
            return best?.0
        }

        // Galleries around the roads and trails, swelling and narrowing as they go.
        let wide = CGFloat(cave.width ?? 3)
        for row in 0..<rows {
            for col in 0..<columns where ground[row][col] == .path {
                let swell = wide * 0.35 * sin(CGFloat(col) * 0.31 + CGFloat(row) * 0.17)
                dig(CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5), wide + swell)
                passages.insert(GridPoint(col: col, row: row))
            }
        }
        let hub = point(def.hub ?? [0, 0])
        dig(hub, wide * 2 + 1)
        for npc in def.npcs ?? [] { dig(point([npc.x, npc.y]), 3.5) }
        // Underground lakes, each in a chamber of its own joined on by a tunnel.
        for pond in ponds where !pond.isEmpty {
            let middle = CGPoint(x: CGFloat(pond.map(\.col).reduce(0, +)) / CGFloat(pond.count) + 0.5,
                                 y: CGFloat(pond.map(\.row).reduce(0, +)) / CGFloat(pond.count) + 0.5)
            let target = nearestOpen(to: middle)
            for cell in pond { dig(CGPoint(x: CGFloat(cell.col) + 0.5, y: CGFloat(cell.row) + 0.5), 2.2) }
            if let target { bentTunnel(middle, target, 1.4) }
        }

        for _ in 0..<(cave.chambers ?? 0) {
            for _ in 0..<30 {
                let middle = CGPoint(x: CGFloat(Int.random(in: 6..<(columns - 6), using: &rng)) + 0.5,
                                     y: CGFloat(Int.random(in: 6..<(rows - 6), using: &rng)) + 0.5)
                let radius = CGFloat(Double.random(in: 2.5..<5, using: &rng))
                let lobe = CGPoint(x: middle.x + CGFloat(Int.random(in: -3...3, using: &rng)), y: middle.y + CGFloat(Int.random(in: -3...3, using: &rng)))
                guard !open[Int(middle.y)][Int(middle.x)], let target = nearestOpen(to: middle), target.distance(to: middle) > radius + 3 else { continue }
                bentTunnel(middle, target, 1.4)
                dig(middle, radius)
                dig(clamped(lobe), radius * 0.7)
                break
            }
        }

        for _ in 0..<(cave.branches ?? 0) {
            var cells: [CGPoint] = []
            for row in 3..<(rows - 3) {
                for col in 3..<(columns - 3) where open[row][col] { cells.append(CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)) }
            }
            guard !cells.isEmpty else { break }
            let start = cells[Int.random(in: 0..<cells.count, using: &rng)]
            let angle = CGFloat(Double.random(in: 0..<(2 * Double.pi), using: &rng))
            let length = CGFloat(Double.random(in: 8..<16, using: &rng))
            let end = clamped(CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
            bentTunnel(start, end, 1.2)
            dig(end, 2)
        }

        // Ragged edges: nibble at the walls, then smooth into rounded rock.
        let before = open
        for row in 0..<rows {
            for col in 0..<columns where !before[row][col] {
                let touches = [(0, 1), (1, 0), (0, -1), (-1, 0)].contains { d in
                    let c = col + d.0, r = row + d.1
                    return c >= 0 && r >= 0 && c < columns && r < rows && before[r][c]
                }
                if touches, Double.random(in: 0..<1, using: &rng) < 0.3 { open[row][col] = true }
            }
        }
        for _ in 0..<2 {
            let last = open
            for row in 0..<rows {
                for col in 0..<columns {
                    var count = 0
                    for dr in -1...1 {
                        for dc in -1...1 where dr != 0 || dc != 0 {
                            let c = col + dc, r = row + dr
                            if c >= 0, r >= 0, c < columns, r < rows, last[r][c] { count += 1 }
                        }
                    }
                    if count >= 5 { open[row][col] = true } else if count <= 2 { open[row][col] = false }
                }
            }
        }
        // Narrow passages, one or two cells wide, dug after the smoothing so they stay narrow.
        var narrow: Set<GridPoint> = []
        func carveNarrow(_ points: [CGPoint]) {
            for (a, b) in zip(points, points.dropFirst()) {
                let steps = max(1, Int(a.distance(to: b) * 2))
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let cell = GridPoint(col: Int(p.x) + dc, row: Int(p.y) + dr)
                            guard contains(cell), CGPoint(x: CGFloat(cell.col) + 0.5, y: CGFloat(cell.row) + 0.5).distance(to: p) <= 0.8 else { continue }
                            open[cell.row][cell.col] = true
                            narrow.insert(cell)
                        }
                    }
                }
            }
        }

        // A maze over the whole cave: a grid of junctions joined along a random spanning tree, so
        // every part can be reached and there are dead ends, plus a few loops. Each link kinks
        // sideways halfway.
        if let spacing = cave.maze, spacing >= 4 {
            let across = max(2, (columns - 6) / spacing + 1), down = max(2, (rows - 6) / spacing + 1)
            var nodes: [CGPoint] = []
            for j in 0..<down {
                for i in 0..<across {
                    let x = 3 + CGFloat(i) * CGFloat(columns - 7) / CGFloat(across - 1) + CGFloat(Double.random(in: -1.5...1.5, using: &rng))
                    let y = 3 + CGFloat(j) * CGFloat(rows - 7) / CGFloat(down - 1) + CGFloat(Double.random(in: -1.5...1.5, using: &rng))
                    nodes.append(clamped(CGPoint(x: x.rounded(.down) + 0.5, y: y.rounded(.down) + 0.5)))
                }
            }
            var visited = Array(repeating: false, count: nodes.count)
            var stack = [Int.random(in: 0..<nodes.count, using: &rng)]
            visited[stack[0]] = true
            var links: [(Int, Int)] = []
            while let current = stack.last {
                let i = current % across, j = current / across
                let options = [(i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)].filter { option in
                    option.0 >= 0 && option.0 < across && option.1 >= 0 && option.1 < down && !visited[option.1 * across + option.0]
                }
                guard !options.isEmpty else { stack.removeLast(); continue }
                let pick = options[Int.random(in: 0..<options.count, using: &rng)]
                let next = pick.1 * across + pick.0
                visited[next] = true
                links.append((current, next))
                stack.append(next)
            }
            for j in 0..<down {
                for i in 0..<across {
                    let here = j * across + i
                    for (di, dj) in [(1, 0), (0, 1)] where i + di < across && j + dj < down {
                        let there = (j + dj) * across + i + di
                        let linked = links.contains { ($0.0 == here && $0.1 == there) || ($0.0 == there && $0.1 == here) }
                        if !linked, Double.random(in: 0..<1, using: &rng) < 0.15 { links.append((here, there)) }
                    }
                }
            }
            for (a, b) in links {
                let from = nodes[a], to = nodes[b]
                let length = max(from.distance(to: to), 0.001)
                let swing = CGFloat(Double.random(in: -2...2, using: &rng))
                let middle = clamped(CGPoint(x: (from.x + to.x) / 2 - (to.y - from.y) / length * swing,
                                             y: (from.y + to.y) / 2 + (to.x - from.x) / length * swing))
                carveNarrow([from, middle, to])
            }
        }

        // Zigzag passages between two open spots.
        for _ in 0..<(cave.zigzags ?? 0) {
            var cells: [CGPoint] = []
            for row in 3..<(rows - 3) {
                for col in 3..<(columns - 3) where open[row][col] { cells.append(CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)) }
            }
            guard cells.count > 1 else { break }
            let start = cells[Int.random(in: 0..<cells.count, using: &rng)]
            var target: CGPoint?
            for _ in 0..<20 {
                let candidate = cells[Int.random(in: 0..<cells.count, using: &rng)]
                if (CGFloat(12)...CGFloat(30)).contains(candidate.distance(to: start)) { target = candidate; break }
            }
            guard let target else { continue }
            let length = start.distance(to: target)
            let ahead = CGVector(dx: (target.x - start.x) / length, dy: (target.y - start.y) / length)
            let side = CGVector(dx: -ahead.dy, dy: ahead.dx)
            let legs = max(3, Int(length / 4))
            var points = [start]
            for leg in 1..<legs {
                let swing = CGFloat(leg % 2 == 0 ? 1 : -1) * CGFloat(Double.random(in: 1.5...3, using: &rng))
                points.append(clamped(start + ahead * (length * CGFloat(leg) / CGFloat(legs)) + side * swing))
            }
            points.append(target)
            carveNarrow(points)
        }

        passages.formUnion(narrow)
        for cell in passages where contains(cell) { open[cell.row][cell.col] = true }

        // The map's edge is solid, except the mouths where roads leave.
        func mouth(_ col: Int, _ row: Int) -> Bool {
            for d in -2...2 {
                for (c, r) in [(col + d, row), (col, row + d)] where c >= 0 && r >= 0 && c < columns && r < rows {
                    let onEdge = c == 0 || r == 0 || c == columns - 1 || r == rows - 1
                    if onEdge, ground[r][c] == .path { return true }
                }
            }
            return false
        }
        for row in 0..<rows {
            for col in 0..<columns where min(col, row, columns - 1 - col, rows - 1 - row) == 0 && open[row][col] && !mouth(col, row) {
                open[row][col] = false
            }
        }

        // Fill in whatever can't be reached from the hub, after making sure every character's
        // chamber is joined on (a narrow passage to the nearest reachable spot if it isn't).
        func flood() -> [[Bool]] {
            var reached = Array(repeating: Array(repeating: false, count: columns), count: rows)
            var queue = [GridPoint(col: Int(hub.x), row: Int(hub.y))]
            if contains(queue[0]), open[queue[0].row][queue[0].col] { reached[queue[0].row][queue[0].col] = true } else { queue = [] }
            while let cell = queue.popLast() {
                for d in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                    let next = GridPoint(col: cell.col + d.0, row: cell.row + d.1)
                    guard contains(next), open[next.row][next.col], !reached[next.row][next.col], ground[next.row][next.col] != .water else { continue }
                    reached[next.row][next.col] = true
                    queue.append(next)
                }
            }
            return reached
        }
        var reached = flood()
        for npc in def.npcs ?? [] {
            let spot = point([npc.x, npc.y])
            let cell = GridPoint(col: Int(spot.x), row: Int(spot.y))
            guard contains(cell), !reached[cell.row][cell.col] else { continue }
            var best: (CGPoint, CGFloat)?
            for row in 0..<rows {
                for col in 0..<columns where reached[row][col] {
                    let q = CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)
                    let d = q.distance(to: spot)
                    if best == nil || d < best!.1 { best = (q, d) }
                }
            }
            guard let target = best?.0 else { continue }
            narrow.removeAll()
            carveNarrow([spot, target])
            passages.formUnion(narrow)
            reached = flood()
        }
        for row in 0..<rows {
            for col in 0..<columns where !reached[row][col] && ground[row][col] != .water {
                let cell = GridPoint(col: col, row: row)
                rock.insert(cell)
                occupy(cell, blocking: true)
            }
        }
        passages = passages.filter { !rock.contains($0) }
    }

    /// The cell `inward` cells in from `edge` (0 on the edge, below 0 out past it), `along` it
    /// (the column on the north and south edges, the row on the east and west).
    func cell(on edge: Edge, along: Int, inward: Int) -> GridPoint {
        switch edge {
        case .north: GridPoint(col: along, row: rows - 1 - inward)
        case .south: GridPoint(col: along, row: inward)
        case .east: GridPoint(col: columns - 1 - inward, row: along)
        case .west: GridPoint(col: inward, row: along)
        }
    }

    /// Where a cell is from `edge`: how far along it and how far in (`cell(on:along:inward:)`).
    func spot(of cell: GridPoint, from edge: Edge) -> (along: Int, inward: Int) {
        switch edge {
        case .north: (cell.col, rows - 1 - cell.row)
        case .south: (cell.col, cell.row)
        case .east: (cell.row, columns - 1 - cell.col)
        case .west: (cell.row, cell.col)
        }
    }

    /// Where a road leads into a cave, a range of rocky hills rises along that side of the map, so
    /// you can see from afar that the way on goes into the mountain: summits one after another along
    /// the edge, their feet 2 to 4 cells in from it, one round the road with its foot 5.5 cells in
    /// (the road climbs to the cave's mouth, about 40 points up its side), and taller ones behind,
    /// rising on past the edge into the mist. The mouth is in its side where the road meets the edge
    /// (`Hill.Mouth`). A summit that would cover anything already set down is left out. Nil if no
    /// road reaches that edge.
    private func raiseCrags(along edge: Edge, _ rng: inout SeededRandom) -> Hill? {
        let length = edge == .north || edge == .south ? columns : rows
        let road = (0..<length).filter { along in
            let cell = self.cell(on: edge, along: along, inward: 0)
            return ground[cell.row][cell.col] == .path
        }
        guard !road.isEmpty else { return nil }
        let middle = Double(road[road.count / 2]) + 0.5
        // Grid directions along the edge and out past it, and where the edge begins.
        let along: (x: Double, y: Double) = edge == .north || edge == .south ? (1, 0) : (0, 1)
        let out: (x: Double, y: Double) = switch edge {
        case .north: (0, 1)
        case .south: (0, -1)
        case .east: (1, 0)
        case .west: (-1, 0)
        }
        let start: (x: Double, y: Double) = switch edge {
        case .north: (0, Double(rows))
        case .east: (Double(columns), 0)
        case .south, .west: (0, 0)
        }
        /// The point `a` cells along the edge and `o` cells out past it.
        func point(_ a: Double, _ o: Double) -> (x: Double, y: Double) {
            (start.x + along.x * a + out.x * o, start.y + along.y * a + out.y * o)
        }
        let angle = edge == .north || edge == .south ? 0.0 : Double.pi / 2
        let steepness = Hill.steepness(rockiness: 1)
        var lobes: [Hill.Lobe] = []
        /// Whether a summit keeps clear of anything already on the map.
        func clear(_ lobe: Hill.Lobe) -> Bool {
            let reach = Int(max(lobe.along, lobe.across).rounded(.up)) + 1
            for dr in -reach...reach {
                for dc in -reach...reach {
                    let cell = GridPoint(col: Int(lobe.x.rounded(.down)) + dc, row: Int(lobe.y.rounded(.down)) + dr)
                    guard contains(cell), lobe.depth(Double(cell.col) + 0.5, Double(cell.row) + 0.5) > -1 else { continue }
                    if occupied.contains(cell) || ground[cell.row][cell.col] == .water { return false }
                }
            }
            return true
        }
        // Along the edge and a little past its ends, a summit every 5 to 9 cells.
        var a = -8.0
        while a < Double(length) + 8 {
            let reach = Double.random(in: 7...10, using: &rng)
            let depth = Double.random(in: 11...15, using: &rng)
            let peak = Double.random(in: 80...115, using: &rng)
            let foot = abs(a - middle) < reach ? 3 : Double.random(in: 2...4, using: &rng)
            let centre = point(a, depth - foot)
            let lobe = Hill.Lobe(x: centre.x, y: centre.y, along: reach, across: depth,
                                 angle: angle + Double.random(in: -0.15...0.15, using: &rng), peak: peak, steepness: steepness)
            if clear(lobe) { lobes.append(lobe) }
            // Close enough that it rises all along the edge, not in humps with flats between.
            a += reach * Double.random(in: 0.7...0.95, using: &rng)
        }
        // A summit round the road, its foot 5.5 cells in, so the road climbs to the mouth partway up
        // its side (the long summits along the edge rise too slowly across to stand high there).
        let summit = point(middle, 9 - 5.5)
        let over = Hill.Lobe(x: summit.x, y: summit.y, along: 8, across: 9, angle: angle,
                             peak: Double.random(in: 95...110, using: &rng), steepness: steepness)
        if clear(over) { lobes.append(over) }
        // Taller ones behind, out past the edge.
        a = -4
        while a < Double(length) + 4 {
            let reach = Double.random(in: 9...13, using: &rng)
            let depth = Double.random(in: 12...16, using: &rng)
            let peak = Double.random(in: 110...150, using: &rng)
            let centre = point(a, depth + Double.random(in: 2...6, using: &rng))
            lobes.append(Hill.Lobe(x: centre.x, y: centre.y, along: reach, across: depth,
                                   angle: angle + Double.random(in: -0.2...0.2, using: &rng), peak: peak, steepness: steepness))
            a += reach * Double.random(in: 1.1...1.6, using: &rng)
        }
        guard !lobes.isEmpty else { return nil }
        let ripples = (0..<3).map { _ in
            (fx: Double.random(in: 0.4...1, using: &rng), px: Double.random(in: 0..<6.3, using: &rng),
             fy: Double.random(in: 0.4...1, using: &rng), py: Double.random(in: 0..<6.3, using: &rng))
        }
        var hill = Hill(lobes: lobes, ripples: ripples, steepness: steepness)
        // Where it's drawn: past the map's corners and out past its edge as far as the mist hides
        // it (the scene's surroundings reach 18 cells out; past them it's all mist).
        let corners = [point(-20, -5), point(Double(length) + 20, -5), point(-20, 22), point(Double(length) + 20, 22)]
        let xs = corners.map { $0.x }, ys = corners.map { $0.y }
        let low = GridPoint(col: Int(xs.min()!.rounded(.down)), row: Int(ys.min()!.rounded(.down)))
        let high = GridPoint(col: Int(xs.max()!.rounded(.up)), row: Int(ys.max()!.rounded(.up)))
        var cells: Set<GridPoint> = []
        let spots = [(0.0, 0.0), (0.5, 0.0), (1.0, 0.0), (0.0, 0.5), (0.5, 0.5), (1.0, 0.5), (0.0, 1.0), (0.5, 1.0), (1.0, 1.0)]
        for row in low.row..<high.row {
            for col in low.col..<high.col where spots.contains(where: { hill.field(Double(col) + $0.0, Double(row) + $0.1) > 0 }) {
                cells.insert(GridPoint(col: col, row: row))
            }
        }
        guard !cells.isEmpty else { return nil }
        hill.cells = cells
        let samples = Hill.samples
        hill.origin = low
        hill.size = (high.col - low.col, high.row - low.row)
        let width = hill.size.columns * samples + 1, deep = hill.size.rows * samples + 1
        hill.heights = [Float](repeating: 0, count: width * deep)
        for j in 0..<deep {
            for i in 0..<width {
                hill.heights[j * width + i] = Float(hill.shape(Double(low.col) + Double(i) / Double(samples), Double(low.row) + Double(j) / Double(samples)))
            }
        }
        hill.highest = CGFloat(hill.heights.max() ?? 0)
        let mouth = point(middle, 0)
        hill.mouth = Hill.Mouth(x: mouth.x, y: mouth.y, along: along, into: out, half: Double(road.count) / 2 + 0.4, depth: 1.7)
        // Nothing grows on its foot in the map, and no pond or other hill goes there.
        for cell in cells where contains(cell) {
            occupy(cell, blocking: false)
            cragGround.insert(cell)
        }
        return hill
    }

    /// Whether a cell is under or against a range where a road leads into a cave, in the map or
    /// out past its edge.
    func nearCrag(_ cell: GridPoint) -> Bool {
        crags.contains { hills[$0.hill].field(Double(cell.col) + 0.5, Double(cell.row) + 0.5) > -1.5 }
    }

    // MARK: Town planning

    private func planTown(_ town: MapDef.Town, _ rng: inout SeededRandom) {
        // The townsfolk stay in view: nothing is built, set down or planted on their spot or just
        // in front of it, where a roof or a tree would hide them. You can still walk there.
        for npc in def.npcs ?? [] {
            let spot = offset(npc.x, npc.y)
            for dc in -2...1 {
                for dr in -2...1 { occupy(GridPoint(col: spot.col + dc, row: spot.row + dr), blocking: false) }
            }
        }
        for street in town.streets ?? [] where street.count == 4 {
            let a = offset(street[0], street[1]), b = offset(street[2], street[3])
            let steps = max(abs(b.col - a.col), abs(b.row - a.row)) * 3
            for step in 0...max(1, steps) {
                let t = CGFloat(step) / CGFloat(max(1, steps))
                paintRoad(around: CGPoint(x: CGFloat(a.col) + 0.5 + CGFloat(b.col - a.col) * t,
                                          y: CGFloat(a.row) + 0.5 + CGFloat(b.row - a.row) * t), radius: 1.05)
            }
        }
        if let radius = town.plaza {
            paintRoad(around: CGPoint(x: CGFloat(center.col) + 0.5, y: CGFloat(center.row) + 0.5), radius: CGFloat(radius) + 0.3)
        }
        for terrace in town.terraces ?? [] { raiseTerrace(terrace) }
        // The town's own buildings first, so the shops below keep clear of them.
        placeOwnBuildings()

        // Shops along the streets: a 3×2 plot just off a street, clear of everything else.
        let frontage = streetFrontage(&rng)
        var used: Set<GridPoint> = []
        for art in town.lots ?? [] {
            guard let anchor = frontage.first(where: { plotFits($0, used: used) }) else { continue }
            for dc in -2...2 {
                for dr in -1...2 { used.insert(GridPoint(col: anchor.col + dc, row: anchor.row + dr)) }
            }
            for dc in -1...1 {
                for dr in 0...1 { occupy(GridPoint(col: anchor.col + dc, row: anchor.row + dr), blocking: true) }
            }
            lots.append((art, anchor))
        }
        // Street furniture on single cells beside the streets.
        var spots = frontage.filter { isFreeForTownDecor($0) }
        for (art, count) in (town.streetDecor ?? [:]).sorted(by: { $0.key < $1.key }) {
            for _ in 0..<count {
                guard let index = spots.indices.randomElement(using: &rng) else { break }
                let cell = spots.remove(at: index)
                guard isFreeForTownDecor(cell) else { continue }
                occupy(cell, blocking: true)
                streetDecor.append((art, cell))
            }
        }
    }

    /// Sets down the map's own buildings (a 3×2 footprint above the anchor, like the shops) where
    /// maps.json puts them. One that would stand on a road, water, the town fence, a terrace's wall,
    /// an NPC or another building (maps.json put some right on a street) moves to the nearest plot
    /// that's clear, ring by ring, up to 8 cells away. A terrace's paved top is fine to build on.
    /// Out on the road, like in town: no tree or bush on an NPC's spot or in front of it (down the
    /// screen, toward you), where it would hide them. A boss is big, and the trees around it tall,
    /// so it gets a wider clearing. You can still walk there.
    private func keepNPCsInView() {
        for npc in def.npcs ?? [] {
            let spot = offset(npc.x, npc.y)
            let reach = npc.role == .boss ? 5 : 2
            for dc in -reach...1 {
                for dr in -reach...1 { occupy(GridPoint(col: spot.col + dc, row: spot.row + dr), blocking: false) }
            }
        }
    }

    private func placeOwnBuildings() {
        let npcs = Set((def.npcs ?? []).map { offset($0.x, $0.y) })
        let fence = Set(fenceCells)
        func fits(_ anchor: GridPoint) -> Bool {
            for dc in -1...1 {
                for dr in 0...1 {
                    let cell = GridPoint(col: anchor.col + dc, row: anchor.row + dr)
                    guard contains(cell), [.ground, .accent].contains(ground[cell.row][cell.col]),
                          !occupied.contains(cell), !fence.contains(cell), !npcs.contains(cell) else { return false }
                }
            }
            return true
        }
        for building in def.buildings ?? [] {
            let wanted = offset(building.x, building.y)
            var plot: GridPoint?
            search: for radius in 0...8 {
                for dr in -radius...radius {
                    for dc in -radius...radius where max(abs(dc), abs(dr)) == radius {
                        let candidate = GridPoint(col: wanted.col + dc, row: wanted.row + dr)
                        if fits(candidate) {
                            plot = candidate
                            break search
                        }
                    }
                }
            }
            guard let plot else { continue }
            for dc in -1...1 {
                for dr in 0...1 { occupy(GridPoint(col: plot.col + dc, row: plot.row + dr), blocking: true) }
            }
            buildings.append((building.art, plot))
        }
    }

    /// Cells one step off a street (on plain ground), shuffled but stable per map.
    private func streetFrontage(_ rng: inout SeededRandom) -> [GridPoint] {
        var cells: [GridPoint] = []
        for row in 1..<(rows - 1) {
            for col in 1..<(columns - 1) where ground[row][col] == .ground {
                let touches = [(0, 1), (1, 0), (0, -1), (-1, 0)].contains { ground[row + $0.1][col + $0.0] == .path }
                if touches { cells.append(GridPoint(col: col, row: row)) }
            }
        }
        // Closer to the centre first, a little shuffled, so the busiest shops sit near the plaza.
        return cells.map { ($0, Double(abs($0.col - center.col) + abs($0.row - center.row)) + Double.random(in: 0..<6, using: &rng)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func plotFits(_ anchor: GridPoint, used: Set<GridPoint>) -> Bool {
        for dc in -1...1 {
            for dr in 0...1 {
                let cell = GridPoint(col: anchor.col + dc, row: anchor.row + dr)
                guard contains(cell), ground[cell.row][cell.col] == .ground, !occupied.contains(cell), !used.contains(cell) else { return false }
            }
        }
        return max(abs(anchor.col - center.col), abs(anchor.row - center.row)) > 3
    }

    private func isFreeForTownDecor(_ cell: GridPoint) -> Bool {
        contains(cell) && ground[cell.row][cell.col] == .ground && !occupied.contains(cell)
            && !(-1...1).contains { dc in (-1...1).contains { dr in occupied.contains(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }
    }

    /// A raised stone terrace: its edges are walls (railings along the back), with stairs in
    /// the middle of the front and one side. The walls block; the top is walkable.
    private func raiseTerrace(_ terrace: MapDef.Terrace) {
        let origin = offset(terrace.x, terrace.y)
        let stairs = [GridPoint(col: origin.col + terrace.width / 2, row: origin.row),
                      GridPoint(col: origin.col, row: origin.row + terrace.height / 2)]
        for col in origin.col..<(origin.col + terrace.width) {
            for row in origin.row..<(origin.row + terrace.height) {
                let cell = GridPoint(col: col, row: row)
                guard contains(cell) else { continue }
                let onEdge = col == origin.col || row == origin.row || col == origin.col + terrace.width - 1 || row == origin.row + terrace.height - 1
                if onEdge, !stairs.contains(cell) {
                    occupy(cell, blocking: true)
                } else if ground[row][col] == .ground {
                    ground[row][col] = .accent   // the terrace top is paved
                }
            }
        }
        terraces.append((origin, terrace.width, terrace.height, stairs))
        // It stands raised: walk up its stairs (front and side) and you're up on it.
        let cells = Set((origin.col..<(origin.col + terrace.width)).flatMap { col in
            (origin.row..<(origin.row + terrace.height)).map { GridPoint(col: col, row: $0) }
        }.filter { contains($0) })
        addPlateau(Plateau(cells: cells, ramps: [stairs[0]: .south, stairs[1]: .west], height: Self.terraceHeight))
    }

    /// How high a town's terraces stand (points).
    static let terraceHeight: CGFloat = 26

    private func addPlateau(_ plateau: Plateau) {
        for cell in plateau.cells { plateauOf[cell] = plateaus.count }
        plateaus.append(plateau)
    }

    /// How a range's trails wind (`Hill.traceTrail`): the angle their feet aim at (round the front),
    /// which way round they go first, how much further round than they need, and how they bend.
    private struct Winding {
        let aim, way, stretch, phase: Double
        let bends: Int
    }

    /// Ranges of grassy hills out in the fields (`theme.hills`, `Hill`): summits one after another
    /// along a wandering line, melted together, off the roads and water and clear of buildings,
    /// people, the arrivals and each other. Mountains first, each the tallest and widest summit of
    /// its range. You can walk up them anywhere, and trails wind up round their sides from the side
    /// facing you, the easy way up; scenery grows on them like anywhere else.
    private func raiseHills(_ hills: MapDef.Hills, _ rng: inout SeededRandom) {
        let sizes = hills.size ?? [3, 6]
        let smallest = Double(max(2, sizes.first ?? 3)), biggest = Double(max(sizes.first ?? 3, sizes.last ?? 6))
        let fewest = max(1, hills.chain?.first ?? 2), most = max(fewest, hills.chain?.last ?? 4)
        let tallest = hills.height ?? 44
        let steep = Hill.steepness(rockiness: rockiness)
        // A mountain is steep whatever the land, or it'd need more room than a map has.
        let mountainSteep = max(steep, 13)
        let mountains = [Double?](repeating: hills.mountains?.height, count: hills.mountains?.count ?? 0)
        var claimed: Set<GridPoint> = []
        for mountain in mountains + [Double?](repeating: nil, count: hills.count) {
            let room = clearance(claimed: claimed)
            // The widest a summit could be anywhere on the map now, in cells; and the cells to try
            // it at, in a random order.
            let widest = ((room.max() ?? 0) - 3.01) / 1.05
            let order = (0..<(columns * rows)).shuffled(using: &rng)
            for attempt in 0..<60 {
                // Where one doesn't fit, a shorter range might.
                let summits = max(1, Int.random(in: fewest...most, using: &rng) - attempt / 20)
                let tall: Int? = mountain == nil ? nil : Int.random(in: 0..<summits, using: &rng)
                var heading = Double.random(in: 0..<(2 * Double.pi), using: &rng)
                var lobes: [Hill.Lobe] = []
                for index in 0..<summits {
                    var along = Double.random(in: smallest...biggest, using: &rng) + 1
                    var across = max(min(along, 4), along * Double.random(in: 0.6...0.95, using: &rng))
                    var peak = tallest * Double.random(in: 0.8...1.15, using: &rng)
                    let steepness = index == tall ? mountainSteep : steep
                    if index == tall, let mountain {
                        // As tall as asked, if anywhere has room for one that wide (it needs the
                        // width to climb that high and still have a top); else as tall as fits.
                        let fits = (widest - 1) * 0.75 * steepness / 1.5
                        peak = max(tallest, min(mountain * Double.random(in: 0.92...1.08, using: &rng), fits))
                        let need = 1.5 * peak / steepness / 0.75 + 1
                        along = max(along, min(max(widest, need), need * Double.random(in: 1...1.2, using: &rng)))
                        across = max(across, need)
                    } else {
                        // A narrow one stands lower, so it still has a top.
                        peak = min(peak, min(along, across) * 0.75 * steepness / 1.5)
                    }
                    var x = 0.0, y = 0.0
                    if let previous = lobes.last {
                        // On from the last, overlapping it, the line wandering a little.
                        let step = 0.75 * (max(previous.along, previous.across) + along) / 2
                        heading += Double.random(in: -0.6...0.6, using: &rng)
                        x = previous.x + step * cos(heading)
                        y = previous.y + step * sin(heading)
                    }
                    lobes.append(Hill.Lobe(x: x, y: y, along: along, across: across,
                                           angle: heading + Double.random(in: -0.3...0.3, using: &rng), peak: peak, steepness: steepness))
                }
                // Somewhere every summit has room around it, if anywhere.
                guard let spot = place(lobes, in: room, trying: order) else { continue }
                for index in lobes.indices {
                    lobes[index].x += spot.x
                    lobes[index].y += spot.y
                }
                let ripples = (0..<3).map { _ in
                    (fx: Double.random(in: 0.4...1, using: &rng), px: Double.random(in: 0..<6.3, using: &rng),
                     fy: Double.random(in: 0.4...1, using: &rng), py: Double.random(in: 0..<6.3, using: &rng))
                }
                var hill = Hill(lobes: lobes, ripples: ripples, steepness: steep)
                // How its trails wind: from where on its front, which way round, how far and how
                // they bend, its own.
                let winding = Winding(aim: 1.25 * Double.pi + Double.random(in: -0.35...0.35, using: &rng),
                                      way: Bool.random(using: &rng) ? 1 : -1,
                                      stretch: Double.random(in: 1...1.3, using: &rng),
                                      phase: Double.random(in: 0..<(2 * Double.pi), using: &rng),
                                      bends: Int.random(in: 2...3, using: &rng))
                guard shapeHill(&hill, mountain: tall, winding: winding, claimed: claimed) else { continue }
                let index = self.hills.count
                for cell in hill.cells { hillOf[cell] = index }
                self.hills.append(hill)
                for cell in hill.cells {
                    for dr in -2...2 { for dc in -2...2 { claimed.insert(GridPoint(col: cell.col + dc, row: cell.row + dr)) } }
                }
                break
            }
        }
    }

    /// How far each cell (row by row) is from the nearest one a hill can't cover, in cells, roughly:
    /// roads, water, buildings, people and the arrivals (`isFreeForScenery`), the hills already
    /// raised and a little round them (`claimed`), and the map's edge with three cells to spare.
    private func clearance(claimed: Set<GridPoint>) -> [Double] {
        let far = Double(columns + rows)
        var room = [Double](repeating: 0, count: columns * rows)
        for row in 3..<max(3, rows - 3) {
            for col in 3..<max(3, columns - 3) {
                let cell = GridPoint(col: col, row: row)
                if isFreeForScenery(cell), !claimed.contains(cell) { room[row * columns + col] = far }
            }
        }
        // Twice over the grid, each cell taking the nearest of what its neighbours have, a step
        // across or along a diagonal away: first from above and left, then from below and right.
        let diagonal = 2.0.squareRoot()
        for row in 0..<rows {
            for col in 0..<columns where room[row * columns + col] > 0 {
                var best = room[row * columns + col]
                if col > 0 { best = min(best, room[row * columns + col - 1] + 1) }
                if row > 0 {
                    best = min(best, room[(row - 1) * columns + col] + 1)
                    if col > 0 { best = min(best, room[(row - 1) * columns + col - 1] + diagonal) }
                    if col < columns - 1 { best = min(best, room[(row - 1) * columns + col + 1] + diagonal) }
                }
                room[row * columns + col] = best
            }
        }
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for col in stride(from: columns - 1, through: 0, by: -1) where room[row * columns + col] > 0 {
                var best = room[row * columns + col]
                if col < columns - 1 { best = min(best, room[row * columns + col + 1] + 1) }
                if row < rows - 1 {
                    best = min(best, room[(row + 1) * columns + col] + 1)
                    if col < columns - 1 { best = min(best, room[(row + 1) * columns + col + 1] + diagonal) }
                    if col > 0 { best = min(best, room[(row + 1) * columns + col - 1] + diagonal) }
                }
                room[row * columns + col] = best
            }
        }
        return room
    }

    /// Where a range of `lobes` can go so each summit has room round it (`room`, from `clearance`):
    /// how far to move them, its first summit in the first of the cells `order` lists (a random
    /// order) where they all fit, or nil if they fit nowhere.
    private func place(_ lobes: [Hill.Lobe], in room: [Double], trying order: [Int]) -> (x: Double, y: Double)? {
        guard let first = lobes.first else { return nil }
        // Its reach, its ripples, the cell to spare round it, and a little for the rough measure.
        let needs = lobes.map { max($0.along, $0.across) * 1.05 + 3 }
        for index in order where room[index] >= needs[0] {
            let dx = Double(index % columns) + 0.5 - first.x, dy = Double(index / columns) + 0.5 - first.y
            let fits = zip(lobes, needs).allSatisfy { lobe, need in
                let col = Int((lobe.x + dx).rounded(.down)), row = Int((lobe.y + dy).rounded(.down))
                return col >= 0 && row >= 0 && col < columns && row < rows && room[row * columns + col] >= need
            }
            if fits { return (dx, dy) }
        }
        return nil
    }

    /// Lays `hill` on the map if there's room: the cells it covers (all clear ground, a cell to spare
    /// all round, well inside the map's edge and off the other hills), its heights and its trails
    /// (one up its mountain, `mountain`, a summit's index, where there's room). False if it doesn't
    /// fit or there's no trail up from the ground in front.
    private func shapeHill(_ hill: inout Hill, mountain: Int?, winding: Winding, claimed: Set<GridPoint>) -> Bool {
        // The cells any summit reaches into, with a cell to spare for the ripples.
        let reach = hill.lobes.map { max($0.along, $0.across) + 1 }
        let low = GridPoint(col: Int(zip(hill.lobes, reach).map { $0.x - $1 }.min()!.rounded(.down)),
                            row: Int(zip(hill.lobes, reach).map { $0.y - $1 }.min()!.rounded(.down)))
        let high = GridPoint(col: Int(zip(hill.lobes, reach).map { $0.x + $1 }.max()!.rounded(.up)),
                             row: Int(zip(hill.lobes, reach).map { $0.y + $1 }.max()!.rounded(.up)))
        guard low.col >= 3, low.row >= 3, high.col < columns - 3, high.row < rows - 3 else { return false }
        func free(_ cell: GridPoint) -> Bool { isFreeForScenery(cell) && !claimed.contains(cell) }
        // A quick look first, before the work of sampling it all: each summit's middle and halfway
        // out, then every cell whose middle it rises over.
        for lobe in hill.lobes {
            let turn: (cos: Double, sin: Double) = (cos(lobe.angle), sin(lobe.angle))
            for (u, v) in [(0.0, 0.0), (0.5, 0.0), (-0.5, 0.0), (0.0, 0.5), (0.0, -0.5)] {
                let a: Double = u * lobe.along, b: Double = v * lobe.across
                let x: Double = lobe.x + a * turn.cos - b * turn.sin
                let y: Double = lobe.y + a * turn.sin + b * turn.cos
                guard free(GridPoint(col: Int(x.rounded(.down)), row: Int(y.rounded(.down)))) else { return false }
            }
        }
        for row in low.row..<high.row {
            for col in low.col..<high.col where hill.field(Double(col) + 0.5, Double(row) + 0.5) > 0 {
                guard free(GridPoint(col: col, row: row)) else { return false }
            }
        }
        // The cells it rises over: where it's inside at a corner, between two or in the middle.
        var cells: Set<GridPoint> = []
        for row in low.row..<high.row {
            for col in low.col..<high.col {
                let spots = [(0.0, 0.0), (0.5, 0.0), (1.0, 0.0), (0.0, 0.5), (0.5, 0.5), (1.0, 0.5), (0.0, 1.0), (0.5, 1.0), (1.0, 1.0)]
                if spots.contains(where: { hill.field(Double(col) + $0.0, Double(row) + $0.1) > 0 }) { cells.insert(GridPoint(col: col, row: row)) }
            }
        }
        guard !cells.isEmpty else { return false }
        let ring = Set(cells.flatMap { cell in (-1...1).flatMap { dr in (-1...1).map { dc in GridPoint(col: cell.col + dc, row: cell.row + dr) } } })
        guard ring.allSatisfy(free) else { return false }
        hill.cells = cells
        // Its heights, `samples` a cell, at the cells' corners and between.
        let samples = Hill.samples
        hill.origin = low
        hill.size = (high.col - low.col, high.row - low.row)
        let width = hill.size.columns * samples + 1, depth = hill.size.rows * samples + 1
        hill.heights = [Float](repeating: 0, count: width * depth)
        for j in 0..<depth {
            for i in 0..<width {
                hill.heights[j * width + i] = Float(hill.shape(Double(low.col) + Double(i) / Double(samples), Double(low.row) + Double(j) / Double(samples)))
            }
        }
        hill.highest = CGFloat(hill.heights.max() ?? 0)
        // Its trails, the easy way up (you can climb it anywhere): from the ground in front up the
        // nearest summit with room for one, and up the mountain too if that wasn't it, winding round
        // their sides (`Hill.traceTrail`). Each is never steeper than a comfortable walk and keeps
        // clear of the other. They start on the side facing you, round either way.
        let order = hill.lobes.indices.sorted { hill.lobes[$0].x + hill.lobes[$0].y < hill.lobes[$1].x + hill.lobes[$1].y }
        let starts: [(offset: Double, way: Double)] = [(0, winding.way), (0, -winding.way), (-0.5, winding.way),
                                                      (0.5, -winding.way), (-0.9, -winding.way), (0.9, winding.way)]
        var trails: [Hill.Trail] = []
        var onTrails: Set<GridPoint> = []
        /// Whether a line comes within a cell and a half of a trail already laid.
        func crowds(_ line: [CGPoint]) -> Bool {
            trails.contains { other in
                let xs = other.points.map(\.x), ys = other.points.map(\.y)
                let left: CGFloat = xs.min()! - 1.5, bottom: CGFloat = ys.min()! - 1.5
                let near = CGRect(x: left, y: bottom, width: xs.max()! + 1.5 - left, height: ys.max()! + 1.5 - bottom)
                return line.contains { near.contains($0) && Hill.distance(Double($0.x), Double($0.y), to: other.points) < 1.5 }
            }
        }
        func climb(_ index: Int, fromGround: Bool) -> Bool {
            for start in starts {
                guard let points = hill.traceTrail(on: index, from: winding.aim + start.offset, way: start.way,
                                                   stretch: winding.stretch, phase: winding.phase, bends: winding.bends)
                else { continue }
                let path = Self.cells(along: points)
                // From the ground: by the heights walkers stand on (not `shape`, a hair off them),
                // with room to spare, so everything that asks agrees it starts there.
                guard path.allSatisfy({ ring.contains($0) }),
                      !fromGround || hill.height(atCells: Double(points[0].x), Double(points[0].y)) < 0.5,
                      hill.steepestClimb(along: points) <= 8, !crowds(points)
                else { continue }
                trails.append(Hill.Trail(lobe: index, points: points))
                onTrails.formUnion(path)
                return true
            }
            return false
        }
        guard order.contains(where: { climb($0, fromGround: true) }) else { return false }
        if let mountain, !trails.contains(where: { $0.lobe == mountain }) { _ = climb(mountain, fromGround: false) }
        hill.trails = trails
        // Nothing grows on the trails or beside them, so the ways up stay open and in sight.
        for cell in onTrails {
            for dr in -1...1 {
                for dc in -1...1 { occupy(GridPoint(col: cell.col + dc, row: cell.row + dr), blocking: false) }
            }
        }
        self.trailCells.formUnion(onTrails)
        return true
    }

    /// The cells along a trail, one after another with no diagonal steps, so you can walk it.
    private static func cells(along trail: [CGPoint]) -> [GridPoint] {
        var path: [GridPoint] = []
        for (a, b) in zip(trail, trail.dropFirst()) {
            let steps = max(1, Int((hypot(b.x - a.x, b.y - a.y) / 0.1).rounded(.up)))
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let cell = GridPoint(col: Int((a.x + (b.x - a.x) * t).rounded(.down)), row: Int((a.y + (b.y - a.y) * t).rounded(.down)))
                guard cell != path.last else { continue }
                if let last = path.last, last.col != cell.col, last.row != cell.row {
                    // Through whichever of the two cells between is nearer the trail.
                    let one = GridPoint(col: cell.col, row: last.row), other = GridPoint(col: last.col, row: cell.row)
                    let near = Hill.distance(Double(one.col) + 0.5, Double(one.row) + 0.5, to: trail)
                    path.append(near <= Hill.distance(Double(other.col) + 0.5, Double(other.row) + 0.5, to: trail) ? one : other)
                }
                path.append(cell)
            }
        }
        return path
    }

    /// Footpaths from each hill's trails to the nearest road (or a footpath laid before it): worn
    /// paths across the fields, winding a little round whatever's in the way, so the hills are
    /// somewhere to go and the minimap shows the way there. Road cells like the rest, a cell wide.
    private func layFootpaths() {
        let hillCells = Set(hills.flatMap(\.cells))
        // A little unevenness in each cell's cost, the same every visit, so paths wander.
        func rough(_ cell: GridPoint) -> Double {
            var hash = UInt64(bitPattern: Int64(cell.col &* 73_856_093 ^ cell.row &* 19_349_663)) &+ 0x9E37_79B9_7F4A_7C15
            hash = (hash ^ (hash >> 30)) &* 0xBF58_476D_1CE4_E5B9
            hash ^= hash >> 31
            return Double(hash % 1000) / 1000
        }
        func open(_ cell: GridPoint) -> Bool {
            cell.col > 0 && cell.row > 0 && cell.col < columns - 1 && cell.row < rows - 1 && isWalkable(cell)
                && ground[cell.row][cell.col] != .water
        }
        // Over a hill only where it must (a trail can start in a nook between two summits), and
        // the dearer the higher, so it goes round.
        func climb(_ cell: GridPoint) -> Double {
            guard hillCells.contains(cell) else { return 0 }
            return 2 + Double(height(atGrid: CGPoint(x: (CGFloat(cell.col) + 0.5) * Self.tileSize, y: (CGFloat(cell.row) + 0.5) * Self.tileSize))) / 4
        }
        // From each trail that starts on the ground (others start up on the range), by the heights
        // walkers stand on.
        let feet = hills.flatMap { $0.trails.compactMap(\.points.first) }
            .filter { height(atGrid: CGPoint(x: $0.x * Self.tileSize, y: $0.y * Self.tileSize)) < 1 }
        for foot in feet {
            let start = GridPoint(col: Int(foot.x.rounded(.down)), row: Int(foot.y.rounded(.down)))
            guard contains(start), ground[start.row][start.col] != .path else { continue }
            // The cheapest way to a road (Dijkstra), dearer beside anything in the way.
            var cost: [GridPoint: Double] = [start: 0]
            var from: [GridPoint: GridPoint] = [:]
            var queue = CostQueue()
            queue.push(start, 0)
            var reached: GridPoint?
            while let next = queue.pop() {
                let (cell, spent) = next
                guard spent <= cost[cell] ?? .infinity else { continue }
                if cell != start, ground[cell.row][cell.col] == .path { reached = cell; break }
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let step = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    guard open(step) else { continue }
                    let crowded = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { !isWalkable(GridPoint(col: step.col + $0.0, row: step.row + $0.1)) }
                    var price = spent + 1 + rough(step) * 1.5
                    if crowded { price += 2 }
                    price += climb(step)
                    if price < cost[step] ?? .infinity {
                        cost[step] = price
                        from[step] = cell
                        queue.push(step, price)
                    }
                }
            }
            guard var cell = reached else { continue }
            while let back = from[cell] {
                cell = back
                ground[cell.row][cell.col] = .path
                occupy(cell, blocking: false)
            }
        }
    }

    /// The cheapest cell first (a binary heap), for `layFootpaths`.
    private struct CostQueue {
        private var heap: [(cell: GridPoint, cost: Double)] = []

        mutating func push(_ cell: GridPoint, _ cost: Double) {
            heap.append((cell, cost))
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard heap[child].cost < heap[parent].cost else { break }
                heap.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> (GridPoint, Double)? {
            guard !heap.isEmpty else { return nil }
            heap.swapAt(0, heap.count - 1)
            let top = heap.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var least = parent
                if left < heap.count, heap[left].cost < heap[least].cost { least = left }
                if right < heap.count, heap[right].cost < heap[least].cost { least = right }
                guard least != parent else { break }
                heap.swapAt(parent, least)
                parent = least
            }
            return (top.cell, top.cost)
        }
    }

    private func scatterAccents(_ rng: inout SeededRandom) {
        for row in 0..<rows {
            for col in 0..<columns where ground[row][col] == .ground && Double.random(in: 0..<1, using: &rng) < 0.06 {
                ground[row][col] = .accent
            }
        }
    }

    /// Soft round patches — flower meadows, shell beaches.
    private func paintAccentPatches(_ count: Int, _ rng: inout SeededRandom) {
        for _ in 0..<count {
            let middle = GridPoint(col: Int.random(in: 0..<columns, using: &rng), row: Int.random(in: 0..<rows, using: &rng))
            let radius = Double.random(in: 1.5...4.5, using: &rng)
            let reach = Int(radius.rounded(.up))
            for dr in -reach...reach {
                for dc in -reach...reach {
                    let cell = GridPoint(col: middle.col + dc, row: middle.row + dr)
                    guard contains(cell), ground[cell.row][cell.col] == .ground else { continue }
                    let distance = (Double(dc * dc + dr * dr)).squareRoot()
                    if distance <= radius, Double.random(in: 0..<1, using: &rng) < 0.8 - distance / radius * 0.4 {
                        ground[cell.row][cell.col] = .accent
                    }
                }
            }
        }
    }

    /// Wobbly ponds, kept away from roads, the centre and each other.
    private func digPonds(_ count: Int, _ rng: inout SeededRandom) {
        for _ in 0..<count {
            for _ in 0..<60 {
                let rx = Double.random(in: 2.5...6.5, using: &rng)
                let ry = Double.random(in: 2...4.5, using: &rng)
                let middle = GridPoint(col: Int.random(in: 8..<max(9, columns - 8), using: &rng), row: Int.random(in: 8..<max(9, rows - 8), using: &rng))
                guard max(abs(middle.col - center.col), abs(middle.row - center.row)) > 8 else { continue }
                var cells: [GridPoint] = []
                for dr in -Int(ry + 1)...Int(ry + 1) {
                    for dc in -Int(rx + 1)...Int(rx + 1) {
                        let distance = pow(Double(dc) / rx, 2) + pow(Double(dr) / ry, 2)
                        if distance <= 1 + Double.random(in: -0.18...0.12, using: &rng) {
                            cells.append(GridPoint(col: middle.col + dc, row: middle.row + dr))
                        }
                    }
                }
                let clear = cells.allSatisfy { cell in
                    contains(cell) && !rock.contains(cell) && !cragGround.contains(cell)
                        && !isNear(cell, within: 2) { $0 == .path || $0 == .water }
                }
                guard clear, !cells.isEmpty else { continue }
                for cell in cells {
                    ground[cell.row][cell.col] = .water
                    occupy(cell, blocking: true)
                }
                ponds.append(cells)
                break
            }
        }
    }

    private func isNear(_ cell: GridPoint, within radius: Int, where matches: (Ground) -> Bool) -> Bool {
        for dr in -radius...radius {
            for dc in -radius...radius {
                let other = GridPoint(col: cell.col + dc, row: cell.row + dr)
                if contains(other), matches(ground[other.row][other.col]) { return true }
            }
        }
        return false
    }

    // MARK: Map screen

    /// One pixel per tile, for the map screen.
    /// `tileColor` gives a tile's colour as the map really shows it (the scene averages its graded
    /// tiles, so the minimap matches the map's palette); without it, rough colours by tile name.
    func overviewImage(tileColor: ((String) -> PixelColor)? = nil) -> CGImage {
        // First match wins, so more specific names come first.
        let tileColors: [(String, UInt32)] = [
            ("snow_path", 0xC9D6E8), ("snow", 0xF2F6FA), ("cave_rock", 0x2B2F3A), ("cave", 0x4A4F5C), ("scree", 0x8C9099),
            ("desert", 0xE8C872), ("swamp", 0x5F6B32), ("forest", 0x3F7A3A),
            ("dark", 0x2E5E5A), ("sand", 0xF2D78F), ("shell", 0xF2D78F), ("town", 0xD8CDBB), ("path", 0xD9B77A),
        ]
        // Once per tile id: `tileColor` averages a whole texture, far too slow to repeat for every cell
        // (on a big map that stalled loading long enough for iOS to kill the app).
        var colors: [String: PixelColor] = [:]
        func color(forTile id: String) -> PixelColor {
            if let known = colors[id] { return known }
            let value = tileColor?(id) ?? PixelColor(tileColors.first { id.contains($0.0) }?.1 ?? 0x5DBB4C)
            colors[id] = value
            return value
        }
        let theme = def.theme
        func onHill(_ col: Int, _ row: Int) -> Bool { hillOf[GridPoint(col: col, row: row)] != nil }
        var canvas = PixelCanvas(width: columns, height: rows)
        for row in 0..<rows {
            for col in 0..<columns {
                let cell = GridPoint(col: col, row: row)
                var pixel: PixelColor = switch ground[row][col] {
                case .ground: color(forTile: theme.ground)
                case .accent: color(forTile: theme.accent ?? theme.ground).shaded(1.08)
                case .path: tileColor == nil && theme.path == "tile_path" ? PixelColor(0xE8C98C) : color(forTile: theme.path).shaded(1.15)
                case .border: color(forTile: theme.border ?? theme.ground)
                case .water: tileColor == nil ? PixelColor(0x4FA3E0) : color(forTile: theme.water ?? "tile_water")
                }
                if rock.contains(cell) {
                    pixel = color(forTile: theme.cave?.rock ?? "cave_rock").shaded(0.5)
                } else if trailCells.contains(cell) {
                    pixel = tileColor == nil && theme.path == "tile_path" ? PixelColor(0xE8C98C) : color(forTile: theme.path).shaded(1.15)
                } else if let index = hillOf[cell] {
                    // Raised ground in a few flat tones, like the rest of the map, not a gradient
                    // (a pixel a cell made it a staircase of shades): a hill a shade lighter, its edge
                    // lit where it faces the light (up the map and left, as the trees' shadows say)
                    // and shaded where it faces away, and a mountain's upper slopes, higher than any
                    // hill stands, lighter still.
                    let lit = !onHill(col - 1, row) || !onHill(col, row + 1)
                    let away = !onHill(col + 1, row) || !onHill(col, row - 1)
                    var tone: Double = hills[index].height(atCells: Double(col) + 0.5, Double(row) + 0.5) >= 66 ? 1.2 : 1.1
                    if lit, !away { tone = 1.24 } else if away, !lit { tone = 0.8 }
                    pixel = pixel.shaded(tone)
                } else if blocked.contains(cell), ground[row][col] != .water {
                    pixel = pixel.shaded(0.55)
                }
                // The ground just past a hill's shaded edge lies in its shadow.
                if hillOf[cell] == nil, !rock.contains(cell), onHill(col - 1, row) || onHill(col, row + 1) {
                    pixel = pixel.shaded(0.88)
                }
                // PixelCanvas is top-down; the map is bottom-up.
                canvas[col, rows - 1 - row] = pixel
            }
        }
        return canvas.cgImage()
    }
}
