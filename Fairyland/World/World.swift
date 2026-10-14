import CoreGraphics

/// The whole continent as one grid of world cells (x east, y north, as world.json has them), in
/// chunks of `chunkSize`: which land owns each cell, and, once that land's been laid out (`add`),
/// its ground and where you can walk. What the game will draw a chunk at a time and walk on, with
/// no borders (docs/continuous-world.md); nothing but the tests reads it yet.
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
    /// Whether you can walk on each cell, once its land's laid out.
    private var walkable: [Bool]
    /// The lands laid out so far (`add`), by index.
    private var laidOut: Set<Int> = []

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
                for col in 0..<land.columns where item.region.owns(GridPoint(col: col, row: row)) {
                    guard let index = index(GridPoint(col: land.origin.col + col, row: land.origin.row + row)) else { continue }
                    if owner[index] == 0 {
                        owner[index] = UInt8(number + 1)
                    } else {
                        conflicts += 1
                    }
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

    /// Copies a land's layout in: the ground and walking of each cell it owns. Its `WorldMap` can be
    /// let go after. Nothing for a map that isn't on the continent (a cave).
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

    /// Whether you can walk on a world cell (only once its land's laid out).
    func isWalkable(_ cell: GridPoint) -> Bool {
        guard let index = index(cell) else { return false }
        return walkable[index]
    }
}
