import Foundation

/// Where the sea comes in over a land's edges, so the lands are natural shapes with bays and
/// headlands instead of rectangles (`WorldMap.carveCoast`). Worked out the same way from either
/// side of a border, so two lands' coasts meet where they touch: everything here is in the
/// continent's cells, from where every land lies (`Continent.coast(of:)`), not from what's on them.
///
/// The sea's in at a cell when the cell is nearer the open sea than the coast's depth there. The
/// distance is to the lands' outline with its outer corners rounded off (`rounding`); the depth
/// wanders smoothly along the coast (`deepest`, two waves of noise over the continent), shallow
/// beside a town (its walls stand by the sea) and pinched to nothing round a road over a border.
/// The depth changes more slowly than the distance, so the sea never cuts off a piece of land and
/// never leaves a pool inland. `tools/world_layout.py --preview` draws the same coasts (keep in step).
nonisolated struct Coast: Sendable {
    /// A land on the continent, in the cells of the land being laid out.
    nonisolated struct Land: Sendable {
        let low: GridPoint
        let high: GridPoint
        let town: Bool

        func contains(_ cell: GridPoint) -> Bool {
            cell.col >= low.col && cell.row >= low.row && cell.col <= high.col && cell.row <= high.row
        }

        /// How far a cell is from it, in cells (0 in it).
        func distance(to cell: GridPoint) -> Double {
            let dx = Double(max(0, low.col - cell.col, cell.col - high.col))
            let dy = Double(max(0, low.row - cell.row, cell.row - high.row))
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// The south-west cell of the land being laid out, on the continent.
    let origin: GridPoint
    /// The lands near enough to matter, this one among them, in its cells.
    let lands: [Land]
    /// Where roads cross from one land into the next (the cell either side of the line), in its cells.
    let crossings: [GridPoint]

    /// How far round a land the coast is worked out: past the furthest the sea reaches in, the
    /// rounding of the corners and the rounding's own reach, so both sides of a border see the
    /// same sea.
    static let margin = 64
    /// The radius the lands' outer corners are rounded to, in cells.
    static let rounding: Double = 30
    /// How far in the sea comes, at the least and the most (beside the towns, `townDepth`).
    static let shallowest: Double = 3
    static let deepest: Double = 30
    static let townDepth: Double = 1.25
    /// Round a road over a border, and round anything on a land the sea mustn't take (`WorldMap`),
    /// the depth falls to this much less than `protection` times the distance: a ring of dry land.
    static let protection: Double = 0.8
    static let ring: Double = 8.5

    /// The coast over a window of cells: the land being laid out (`columns` × `rows`) and `margin`
    /// round it.
    func field(columns: Int, rows: Int) -> Field {
        let margin = Self.margin
        let width = columns + margin * 2, height = rows + margin * 2
        var land = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let cell = GridPoint(col: x - margin, row: y - margin)
                land[y * width + x] = lands.contains { $0.contains(cell) }
            }
        }
        // How far each cell is from the open sea, and how far from the lands' outline with its
        // outer corners rounded off: the same where the outline runs straight, less round a corner
        // (below 0 out past the rounding, where the corner's cut away).
        let toSea = Self.distances(width: width, height: height, from: land.map { !$0 })
        let rounding = Float(Self.rounding)
        let toCore = Self.distances(width: width, height: height, from: toSea.map { $0 >= rounding })
        var shape = [Float](repeating: 0, count: width * height)
        var depth = [Float](repeating: 0, count: width * height)
        let towns = lands.filter(\.town)
        for index in 0..<(width * height) where land[index] {
            shape[index] = toSea[index] >= rounding ? toSea[index] : rounding - toCore[index]
            // Far enough in that the sea never reaches: no need for the depth.
            guard shape[index] < Float(Self.deepest) else { continue }
            let cell = GridPoint(col: index % width - margin, row: index / width - margin)
            depth[index] = Float(self.depth(at: cell, towns: towns))
        }
        return Field(margin: margin, width: width, height: height, land: land, shape: shape, depth: depth)
    }

    /// How far in the sea comes at `cell` (in this land's cells), before anything on the land
    /// holds it back.
    private func depth(at cell: GridPoint, towns: [Land]) -> Double {
        let x = Double(cell.col + origin.col) + 0.5, y = Double(cell.row + origin.row) + 0.5
        let wave = (Self.value(x, y, every: 64, seed: 0x51) + Self.value(x, y, every: 24, seed: 0xA7) * 0.4) / 1.4
        var depth = Self.shallowest + (Self.deepest - Self.shallowest) * wave
        // Shallow beside a town, coming in over its last dozen cells.
        if let near = towns.map({ $0.distance(to: cell) }).min() {
            let t = min(1, max(0, (near - 1) / 12))
            depth = Self.townDepth + (depth - Self.townDepth) * t * t * (3 - 2 * t)
        }
        // None round a road over a border.
        for crossing in crossings {
            let dx = Double(cell.col - crossing.col), dy = Double(cell.row - crossing.row)
            depth = min(depth, Self.protection * (dx * dx + dy * dy).squareRoot() - Self.ring)
        }
        return depth
    }

    /// The coast over a window round a land: `margin` cells out from its south-west corner.
    nonisolated struct Field: Sendable {
        let margin: Int
        let width: Int
        let height: Int
        /// Whether each cell lies in a land.
        let land: [Bool]
        /// How far each land cell is from the lands' rounded outline (`Coast.field`).
        let shape: [Float]
        /// How far in the sea comes at each land cell near the coast.
        let depth: [Float]

        func index(of cell: GridPoint) -> Int? {
            let x = cell.col + margin, y = cell.row + margin
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return y * width + x
        }

        /// Whether the sea's at `cell` with nothing on the land to hold it back: out past the lands,
        /// or in over the coast. The same from every land that sees the cell.
        func isSea(_ cell: GridPoint) -> Bool {
            guard let index = index(of: cell) else { return true }
            return !land[index] || shape[index] < depth[index]
        }
    }

    // MARK: Noise

    /// Smooth noise over the continent, 0...1, its hills and hollows about `every` cells apart.
    nonisolated static func value(_ x: Double, _ y: Double, every: Double, seed: UInt64) -> Double {
        let gx = x / every, gy = y / every
        let i = Int(gx.rounded(.down)), j = Int(gy.rounded(.down))
        let fx = gx - Double(i), fy = gy - Double(j)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(i, j, seed), b = hash(i + 1, j, seed), c = hash(i, j + 1, seed), d = hash(i + 1, j + 1, seed)
        return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy
    }

    /// A number 0..<1 for a corner of the noise's lattice, the same every time.
    nonisolated static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= seed
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h % 1_000_000) / 1_000_000
    }

    // MARK: Distances

    /// How far (in cells, middle to middle) every cell of a `width` × `height` grid is from the
    /// nearest cell where `source` is true: a pass each way over the grid, a step 1 straight and √2
    /// diagonally, near enough to the straight line for a coast.
    nonisolated static func distances(width: Int, height: Int, from source: [Bool]) -> [Float] {
        let far = Float(width + height) * 2
        var d = source.map { $0 ? Float(0) : far }
        let diagonal = Float(2).squareRoot()
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var best = d[i]
                if x > 0 { best = min(best, d[i - 1] + 1) }
                if y > 0 {
                    best = min(best, d[i - width] + 1)
                    if x > 0 { best = min(best, d[i - width - 1] + diagonal) }
                    if x < width - 1 { best = min(best, d[i - width + 1] + diagonal) }
                }
                d[i] = best
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                var best = d[i]
                if x < width - 1 { best = min(best, d[i + 1] + 1) }
                if y < height - 1 {
                    best = min(best, d[i + width] + 1)
                    if x < width - 1 { best = min(best, d[i + width + 1] + diagonal) }
                    if x > 0 { best = min(best, d[i + width - 1] + diagonal) }
                }
                d[i] = best
            }
        }
        return d
    }
}
