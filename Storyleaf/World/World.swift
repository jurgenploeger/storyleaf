import CoreGraphics

/// The whole continent as one grid of world cells (x east, y north, as world.json has them), in
/// chunks of `chunkSize`: which land owns each cell, where you can walk (from its land's shape till
/// that's laid out), and, once it is (`add`), its ground. What the game draws a chunk at a time and
/// walks on, with no borders (docs/continuous-world.md).
///
/// Small on purpose: a byte or two a cell, about 2 MB for the whole continent. A laid-out land
/// (`WorldMap`) is copied in and can be let go.
nonisolated final class World: @unchecked Sendable {
    /// Cells a side of a chunk: two of `HillArt`'s squares, about 16 seconds' walk across.
    static let chunkSize = 32

    /// A land on the continent: its id, and its box (its map), from its south-west cell.
    nonisolated struct Land: Sendable {
        let id: String
        let origin: GridPoint
        let columns: Int
        let rows: Int
    }

    /// The lands, in the order `owner` numbers them.
    let lands: [Land]
    /// The cells it covers, every land's box: from `low` (south-west), `columns` × `rows`.
    let low: GridPoint
    let columns: Int
    let rows: Int
    /// Cells two lands' shapes both claimed (the first keeps them). None, as the painting is drawn:
    /// the tests check.
    private(set) var conflicts = 0

    /// Each cell's land, as its index in `lands` + 1; 0 for none (the sea).
    private var owner: [UInt8]
    /// Each cell's ground once its land's laid out (`Ground`'s raw value + 1); 0 till then.
    private var grounds: [UInt8]
    /// Whether you can walk on each cell: before its land's laid out, anywhere on it but its rivers
    /// and lakes (its shape's, `Region.isRiver`), so a land's layout never keeps you off it (it comes
    /// in round you, `ContinentScene.build`); then as its layout has it (`add`).
    private var walkable: [Bool]
    /// The lands laid out so far (`add`), by index.
    private var laidOut: Set<Int> = []
    /// The harbors' piers, out over the sea (`Region.Road.pierCells`), walked on as the land
    /// they're built from (its id), though no land owns them.
    private var piers: [GridPoint: String] = [:]

    /// `lands`: each land with its shape (`Region`), whose own cells it gets.
    init(lands: [(land: Land, region: Region)]) {
        precondition(lands.count < 255, "a land's index has to fit in a byte")
        self.lands = lands.map(\.land)
        let boxes = lands.map(\.land)
        let west = boxes.map(\.origin.col).min() ?? 0, south = boxes.map(\.origin.row).min() ?? 0
        let east = boxes.map { $0.origin.col + $0.columns }.max() ?? 0
        let north = boxes.map { $0.origin.row + $0.rows }.max() ?? 0
        low = GridPoint(col: west, row: south)
        columns = max(0, east - west)
        rows = max(0, north - south)
        owner = [UInt8](repeating: 0, count: columns * rows)
        grounds = [UInt8](repeating: 0, count: columns * rows)
        walkable = [Bool](repeating: false, count: columns * rows)
        for (number, item) in lands.enumerated() {
            let land = item.land
            for row in 0..<land.rows {
                for col in 0..<land.columns {
                    let cell = GridPoint(col: col, row: row)
                    guard item.region.owns(cell),
                          let index = index(GridPoint(col: land.origin.col + col, row: land.origin.row + row)) else { continue }
                    if owner[index] == 0 {
                        owner[index] = UInt8(number + 1)
                        walkable[index] = !item.region.isRiver(cell)
                    } else {
                        conflicts += 1
                    }
                }
            }
        }
        // The piers, over the sea.
        for item in lands {
            for road in item.region.roads.values {
                for cell in road.pierCells {
                    let spot = GridPoint(col: item.land.origin.col + cell.col, row: item.land.origin.row + cell.row)
                    guard let index = index(spot), owner[index] == 0 else { continue }
                    walkable[index] = true
                    piers[spot] = item.land.id
                }
            }
        }
    }

    /// The continent as content/world.json paints it: every land on it (not the caves).
    @MainActor static func continent() -> World {
        let content = Content.shared
        let lands = content.maps.compactMap { def -> (land: Land, region: Region)? in
            guard let origin = content.world[def.id], let region = content.regions[def.id] else { return nil }
            return (Land(id: def.id, origin: origin, columns: def.width, rows: def.height), region)
        }
        return World(lands: lands)
    }

    // MARK: Cells

    /// Where a world cell is kept, if it's on the continent's grid.
    private func index(_ cell: GridPoint) -> Int? {
        let x = cell.col - low.col, y = cell.row - low.row
        guard x >= 0, y >= 0, x < columns, y < rows else { return nil }
        return y * columns + x
    }

    /// The land that owns a world cell, if any (none: the sea, or off the grid).
    func land(at cell: GridPoint) -> Land? {
        guard let index = index(cell), owner[index] > 0 else { return nil }
        return lands[Int(owner[index]) - 1]
    }

    /// The land whose harbor's pier a world cell is on, if it's on one (`piers`).
    func pier(at cell: GridPoint) -> Land? {
        piers[cell].flatMap { land($0) }
    }

    /// The land with this id, if it's on the continent.
    func land(_ id: String) -> Land? {
        lands.first { $0.id == id }
    }

    /// A world cell in `land`'s own cells.
    func local(_ cell: GridPoint, in land: Land) -> GridPoint {
        GridPoint(col: cell.col - land.origin.col, row: cell.row - land.origin.row)
    }

    /// One of `land`'s cells as a world cell.
    func world(_ cell: GridPoint, of land: Land) -> GridPoint {
        GridPoint(col: cell.col + land.origin.col, row: cell.row + land.origin.row)
    }

    // MARK: Chunks

    /// The chunk a world cell is in: its south-west cell divided by `chunkSize`, rounded down.
    static func chunk(of cell: GridPoint) -> GridPoint {
        GridPoint(col: floored(cell.col), row: floored(cell.row))
    }

    /// The world cells of a chunk, row by row from the south.
    static func cells(in chunk: GridPoint) -> [GridPoint] {
        let col0 = chunk.col * chunkSize, row0 = chunk.row * chunkSize
        var cells: [GridPoint] = []
        cells.reserveCapacity(chunkSize * chunkSize)
        for row in row0..<(row0 + chunkSize) {
            for col in col0..<(col0 + chunkSize) { cells.append(GridPoint(col: col, row: row)) }
        }
        return cells
    }

    private static func floored(_ value: Int) -> Int {
        value >= 0 ? value / chunkSize : -((-value + chunkSize - 1) / chunkSize)
    }

    // MARK: Laid out

    /// Copies a land's layout in: the ground and walking of each cell it owns, in place of walking
    /// from its shape. Its `WorldMap` can be let go after. Nothing for a map that isn't on the
    /// continent (a cave).
    func add(_ map: WorldMap) {
        guard let number = lands.firstIndex(where: { $0.id == map.def.id }) else { return }
        let land = lands[number]
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let cell = GridPoint(col: col, row: row)
                guard let index = index(world(cell, of: land)), Int(owner[index]) == number + 1 else { continue }
                grounds[index] = map.ground[row][col].rawValue + 1
                walkable[index] = map.isWalkable(cell)
            }
        }
        laidOut.insert(number)
    }

    /// Whether a land's been laid out into the store yet.
    func isLaidOut(_ id: String) -> Bool {
        lands.firstIndex { $0.id == id }.map { laidOut.contains($0) } ?? false
    }

    /// A world cell's ground, once its land's laid out; nil before, and at sea.
    func ground(at cell: GridPoint) -> Ground? {
        guard let index = index(cell), grounds[index] > 0 else { return nil }
        return Ground(rawValue: grounds[index] - 1)
    }

    /// Whether you can walk on a world cell: as its land's laid out, or till then anywhere on it but
    /// its rivers and lakes (`walkable`). Never at sea.
    func isWalkable(_ cell: GridPoint) -> Bool {
        guard let index = index(cell) else { return false }
        return walkable[index]
    }

    // MARK: Paths

    /// The walkable cell nearest `cell` within `reach` cells, nearest ring first (`cell` if it's
    /// walkable), as `WorldMap.nearestWalkable` finds one on a land.
    func nearestWalkable(to cell: GridPoint, within reach: Int = 8) -> GridPoint? {
        if isWalkable(cell) { return cell }
        for radius in 1...max(1, reach) {
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dr), abs(dc)) == radius {
                    let candidate = GridPoint(col: cell.col + dc, row: cell.row + dr)
                    if isWalkable(candidate) { return candidate }
                }
            }
        }
        return nil
    }

    /// The shortest way from one world cell to another over cells you can walk on, within `reach`
    /// cells of the start either way: the cells after `start`, `goal` last; empty if there's none
    /// in reach (or `start` is `goal`). A* over the store in a window round you, rather than a graph
    /// of the whole continent (docs/continuous-world.md, step 3). It steps diagonally too, but only
    /// where both cells beside the step are open, so it never cuts a corner. `canStep`: whether a
    /// step from one cell to the next is allowed besides (over a border, only where it's open).
    func path(from start: GridPoint, to goal: GridPoint, reach: Int = 64,
              canStep: ((GridPoint, GridPoint) -> Bool)? = nil) -> [GridPoint] {
        guard start != goal, isWalkable(start), isWalkable(goal),
              max(abs(goal.col - start.col), abs(goal.row - start.row)) <= reach else { return [] }
        let side = 2 * reach + 1
        func slot(_ cell: GridPoint) -> Int? {
            let x = cell.col - start.col + reach, y = cell.row - start.row + reach
            guard x >= 0, y >= 0, x < side, y < side else { return nil }
            return y * side + x
        }
        func cell(_ slot: Int) -> GridPoint {
            GridPoint(col: slot % side - reach + start.col, row: slot / side - reach + start.row)
        }
        // Costs in tenths of a cell: 10 a step along, 14 across a corner.
        func estimate(_ cell: GridPoint) -> Int {
            let dx = abs(cell.col - goal.col), dy = abs(cell.row - goal.row)
            return 10 * max(dx, dy) + 4 * min(dx, dy)
        }
        guard let first = slot(start), let last = slot(goal) else { return [] }
        var cost = [Int](repeating: .max, count: side * side)
        var cameFrom = [Int](repeating: -1, count: side * side)
        var done = [Bool](repeating: false, count: side * side)
        var open = Frontier()
        cost[first] = 0
        open.push(first, priority: estimate(start))
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while let current = open.pop() {
            if current == last { break }
            guard !done[current] else { continue }
            done[current] = true
            let here = cell(current)
            for (dc, dr) in steps {
                let next = GridPoint(col: here.col + dc, row: here.row + dr)
                guard let index = slot(next), !done[index], isWalkable(next) else { continue }
                let diagonal = dc != 0 && dr != 0
                if diagonal, !isWalkable(GridPoint(col: here.col + dc, row: here.row)) || !isWalkable(GridPoint(col: here.col, row: here.row + dr)) {
                    continue
                }
                if let canStep, !canStep(here, next) { continue }
                let through = cost[current] + (diagonal ? 14 : 10)
                guard through < cost[index] else { continue }
                cost[index] = through
                cameFrom[index] = current
                open.push(index, priority: through + estimate(next))
            }
        }
        guard cameFrom[last] >= 0 else { return [] }
        var cells: [GridPoint] = []
        var at = last
        while at != first {
            cells.append(cell(at))
            at = cameFrom[at]
        }
        return cells.reversed()
    }

    /// The cells A* is yet to look at, the cheapest first: a binary heap (`WorldMap.route` too).
    nonisolated struct Frontier {
        private var items: [(slot: Int, priority: Int)] = []

        mutating func push(_ slot: Int, priority: Int) {
            items.append((slot, priority))
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard items[child].priority < items[parent].priority else { break }
                items.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> Int? {
            guard let top = items.first else { return nil }
            let end = items.removeLast()
            if !items.isEmpty {
                items[0] = end
                var parent = 0
                while true {
                    let left = 2 * parent + 1, right = left + 1
                    var least = parent
                    if left < items.count, items[left].priority < items[least].priority { least = left }
                    if right < items.count, items[right].priority < items[least].priority { least = right }
                    guard least != parent else { break }
                    items.swapAt(parent, least)
                    parent = least
                }
            }
            return top.slot
        }
    }
}
