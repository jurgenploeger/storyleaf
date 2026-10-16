import Foundation

/// Where two lands meet: not a line but a band where one gives way to the other, as RuneScape's
/// regions run into each other. Across it the other land's ground comes in patches, a few strays
/// at first, then more and more, until it's all the other land's: `blend` cells either side of the
/// border, which wanders as the lands' shapes do (`Region`). The other land's scenery grows on its
/// patches (`WorldScene.placeSeamProps`). Only how it looks: whose each cell is still stops at the
/// border.
///
/// Worked out from how far each cell is from the other land, so both lands draw the same band: each
/// from its own side (`sign`), the cells showing the other land (`showsOther`) drawn with its ground
/// graded as it is there (`WorldScene.makeGround`), on the minimap and the world map too
/// (`WorldMap.foreign`). Not beside a town, whose walls stand on the border.
nonisolated struct Seam: Sendable {
    /// The land on the other side, by id.
    let neighbour: String
    /// This land's box's south-west cell on the continent.
    let origin: GridPoint
    /// 1 where this land is the first of the two by id, else -1: the patches are the first land's
    /// noise, turned over for the second.
    let sign: Double
    /// The window it's worked out over (the land's box and `margin` round it).
    private let margin: Int
    private let width: Int
    private let height: Int
    /// For each cell of the window, row by row from the south: how far it lies on this land's side of
    /// the border (half a cell on the cells either side of it), from how far it is from the other
    /// land; below 0 on the other land's side; infinite on neither.
    private let sides: [Float]

    /// How far either side of the border the two lands' ground mixes, in cells.
    static let blend: Double = 14
    /// How far in from the border the band can reach.
    static let depth = Int(blend) + 1

    /// The band between the land `here` (an index into `blend.around.lands`) and the land `there`.
    init(between here: Int, and there: Int, in blend: Blend) {
        let around = blend.around
        let other = around.lands[there]
        neighbour = other
        origin = around.origin
        sign = around.lands[here] < other ? 1 : -1
        margin = around.margin
        width = around.width
        height = around.height
        let toTheirs = blend.distances[there], toMine = blend.distances[here]
        var sides = [Float](repeating: .infinity, count: width * height)
        for index in sides.indices {
            if blend.owners[index] == here {
                sides[index] = toTheirs[index] - 0.5
            } else if blend.owners[index] == there {
                sides[index] = 0.5 - toMine[index]
            }
        }
        self.sides = sides
    }

    /// How far a cell (in this land's cells) lies on this land's side of the border: below 0 on the
    /// other's; nil off both, or out past the window.
    func side(_ cell: GridPoint) -> Double? {
        let x = cell.col + margin, y = cell.row + margin
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let value = sides[y * width + x]
        return value.isFinite ? Double(value) : nil
    }

    /// How much of the ground is the other land's `side` cells this side of the border, the band
    /// `blend` either side of it: none `blend` in, half on the line, all of it `blend` past.
    static func share(at side: Double) -> Double {
        let t = min(1, max(0, (blend - side) / (2 * blend)))
        return t * t * (3 - 2 * t)
    }

    /// How much of the ground at a cell is the other land's (nil off both lands).
    func share(_ cell: GridPoint) -> Double? {
        side(cell).map(Self.share)
    }

    /// Whether a cell is near enough the border, on either side, for the band to reach it.
    func covers(_ cell: GridPoint) -> Bool {
        side(cell).map { abs($0) < Double(Self.depth) } ?? false
    }

    /// Whether a cell (of either land) shows the other land's ground: where it's that land's share of
    /// the band, by patches of noise over the continent (`patch`), the same from either side.
    func showsOther(_ cell: GridPoint) -> Bool {
        guard let amount = share(cell) else { return false }
        return Self.patches(share: amount, at: GridPoint(col: cell.col + origin.col, row: cell.row + origin.row), sign: sign)
    }

    /// Patchy noise over the continent's cells, 0.02...0.98: blobs a few cells across, a little
    /// ragged, spread out so the patches come in steadily across the band.
    static func patch(x: Double, y: Double) -> Double {
        let raw = (value(x, y, every: 3.4, seed: 0x9A1) + value(x, y, every: 1.5, seed: 0x9A2) * 0.5) / 1.5
        return min(0.98, max(0.02, 0.5 + (raw - 0.5) * 1.8))
    }

    /// Whether a land's patches reach `cell` across a band: `share` of the ground there is its (`share(at:)`),
    /// against the noise there, turned over for the second of the two lands by id (`sign`).
    fileprivate static func patches(share: Double, at cell: GridPoint, sign: Double) -> Bool {
        guard share > 0 else { return false }
        let noise = patch(x: Double(cell.col) + 0.5, y: Double(cell.row) + 0.5)
        return share > (sign > 0 ? noise : 1 - noise)
    }

    // MARK: Noise

    /// Smooth noise over the continent, 0...1, its hills and hollows about `every` cells apart.
    static func value(_ x: Double, _ y: Double, every: Double, seed: UInt64) -> Double {
        let gx = x / every, gy = y / every
        let i = Int(gx.rounded(.down)), j = Int(gy.rounded(.down))
        let fx = gx - Double(i), fy = gy - Double(j)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(i, j, seed), b = hash(i + 1, j, seed), c = hash(i, j + 1, seed), d = hash(i + 1, j + 1, seed)
        return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy
    }

    /// A number 0..<1 for a corner of the noise's lattice, the same every time.
    static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
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
    /// diagonally, near enough to the straight line.
    static func distances(width: Int, height: Int, from source: [Bool]) -> [Float] {
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

/// Every band round a land at once (`Seam`): how far each cell of its window (`Neighbourhood`) is from
/// each land in it, and which lands share a border, so the land can tell what any cell shows as the
/// land holding it does (`shows`), on its own side of a border or past it. Its tiles look at the
/// cells round theirs, past the border too: what a land next door's cell showed there had to be
/// what that land draws on it, or the patches stopped dead along the border, and where three lands
/// meet a land's patches across the second border were left out (playtesting 2026-10-16). Worked
/// out from either land's window, it comes out the same: the band reaches no further than
/// `Seam.depth`, and the window runs on `region.margin` cells past the box.
nonisolated struct Blend: Sendable {
    let around: Neighbourhood
    /// Which of `around.lands` holds each cell of the window, row by row from the south; -1 none.
    fileprivate let owners: [Int]
    /// How far each cell of the window is from each land (`Seam.distances`), by land; empty for a land
    /// that shares no border in it.
    fileprivate let distances: [[Float]]
    /// The lands each shares a border with, in the window, by index.
    private let touching: [[Int]]

    init(_ around: Neighbourhood) {
        self.around = around
        let width = around.width, height = around.height, margin = around.margin
        var owners = [Int](repeating: -1, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                owners[y * width + x] = around.owner(GridPoint(col: x - margin, row: y - margin)) ?? -1
            }
        }
        var touching = [Set<Int>](repeating: [], count: around.lands.count)
        for y in 0..<height {
            for x in 0..<width {
                let here = owners[y * width + x]
                guard here >= 0 else { continue }
                for next in [x + 1 < width ? owners[y * width + x + 1] : -1, y + 1 < height ? owners[(y + 1) * width + x] : -1]
                where next >= 0 && next != here {
                    touching[here].insert(next)
                    touching[next].insert(here)
                }
            }
        }
        self.owners = owners
        self.touching = touching.map { $0.sorted() }
        distances = touching.indices.map { land in
            touching[land].isEmpty ? [] : Seam.distances(width: width, height: height, from: owners.map { $0 == land })
        }
    }

    /// The lands `land` (an index into `around.lands`) shares a border with, by index.
    func neighbours(of land: Int) -> [Int] { touching[land] }

    /// Which land's ground shows at a cell (in the window's land's cells), as the land holding it lays
    /// out its band (`WorldMap.markForeign`): of the lands beside it whose patches reach it
    /// (`Seam.showsOther`), the one with the largest share (the first by id if two have the same);
    /// else its own. An index into `around.lands`; nil off the lands, or past the window.
    func shows(_ cell: GridPoint) -> Int? {
        let x = cell.col + around.margin, y = cell.row + around.margin
        guard x >= 0, y >= 0, x < around.width, y < around.height else { return nil }
        let index = y * around.width + x
        let holder = owners[index]
        guard holder >= 0 else { return nil }
        let world = GridPoint(col: cell.col + around.origin.col, row: cell.row + around.origin.row)
        var best: (land: Int, share: Double)?
        for land in touching[holder] {
            // As `Seam.side` has it on the holder's cells.
            let share = Seam.share(at: Double(distances[land][index] - 0.5))
            guard share > best?.share ?? 0,
                  Seam.patches(share: share, at: world, sign: around.lands[holder] < around.lands[land] ? 1 : -1) else { continue }
            best = (land, share)
        }
        return best?.land ?? holder
    }
}
