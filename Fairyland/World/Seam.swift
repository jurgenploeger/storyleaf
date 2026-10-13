import Foundation

/// Where two lands meet: not a line but a band where one gives way to the other, as RuneScape's
/// regions run into each other. Across it the other land's ground comes in patches, a few strays
/// at first, then more and more, until it's all the other land's: `blend` cells either side of a
/// middle line that wanders either side of the straight border (`offset`), so each land is a shape
/// of its own. The other land's scenery grows on its patches (`WorldScene.placeSeamProps`). Only
/// how it looks: what's on each land, and whose it is, still stops at the straight border.
///
/// Worked out in the continent's cells, so both lands draw the same band: each from its own side
/// (`sign`), the cells showing the other land (`showsOther`) drawn with its ground graded as it is
/// there (`WorldScene.makeGround`), on the minimap and the world map too (`WorldMap.foreign`). Not
/// beside a town, whose walls stand on the border (`Continent.coast(of:)`).
/// `tools/world_layout.py --preview` draws the same band (keep the two in step).
nonisolated struct Seam: Sendable {
    /// The land on the other side, by id.
    let neighbour: String
    /// The edge of this land the border runs along.
    let edge: Edge
    /// The cells along that edge the two share: columns on the north and south, rows on the east
    /// and west, in this land's cells.
    let span: ClosedRange<Int>
    /// This land's size.
    let columns: Int
    let rows: Int
    /// This land's south-west cell on the continent.
    let origin: GridPoint
    /// 1 where this land is the first of the two by id, else -1: the middle line's offset is into
    /// the first land, so the second sees it turned round, and the patches are the first land's
    /// noise turned over.
    let sign: Double

    /// The furthest the middle line wanders either side of the border, in cells.
    static let reach: Double = 10
    /// Over how many cells at either end of the stretch they share it comes back to the border,
    /// to meet the band round the next land (or the coast) at the corner.
    static let taper: Double = 16
    /// The waves the middle line wanders in: how many cells apart their crests are, the noise's
    /// seed, its weight.
    static let waves: [(every: Double, seed: UInt64, weight: Double)] = [(52, 0x5EA, 1), (18, 0x5EB, 0.5), (7, 0x5EC, 0.18)]
    /// How far either side of the middle line the two lands' ground mixes, in cells.
    static let blend: Double = 20
    /// How far in from the edge the band can reach.
    static let depth = Int(reach + blend) + 1

    /// Where along the edge this land's first cell lies on the continent, and where the border
    /// lies across it (the column of an east or west border, the row of a north or south one).
    var start: Int { edge == .east || edge == .west ? origin.row : origin.col }
    var line: Int {
        switch edge {
        case .east: origin.col + columns
        case .west: origin.col
        case .north: origin.row + rows
        case .south: origin.row
        }
    }

    /// How far a point lies in from the edge and where along it, in this land's cells (a cell
    /// (col, row) spans col...col + 1, row...row + 1).
    func place(x: Double, y: Double) -> (inward: Double, along: Double) {
        switch edge {
        case .north: (Double(rows) - y, x)
        case .south: (y, x)
        case .east: (Double(columns) - x, y)
        case .west: (x, y)
        }
    }

    /// How far the band reaches at `along` (continuous, in this land's cells along the edge): all
    /// of it from `taper` in from the ends of the stretch the two share, none at the ends.
    func fade(at along: Double) -> Double {
        let end = min(along - Double(span.lowerBound), Double(span.upperBound + 1) - along)
        let t = min(1, max(0, end / Self.taper))
        return t * t * (3 - 2 * t)
    }

    /// How far into this land (+) or the other (-) the middle line lies at `along` (continuous,
    /// in this land's cells along the edge).
    func offset(at along: Double) -> Double {
        let strength = fade(at: along)
        guard strength > 0 else { return 0 }
        let world = along + Double(start)
        var wave = 0.0, total = 0.0
        for octave in Self.waves {
            wave += Coast.value(world, Double(line), every: octave.every, seed: octave.seed) * octave.weight
            total += octave.weight
        }
        return sign * (wave / total * 2 - 1) * Self.reach * strength
    }

    /// How wide the band is either side of the middle line at `along`: narrowing toward the ends
    /// of the stretch the two share, so it meets the band round the next land at the corner.
    func width(at along: Double) -> Double {
        Self.blend * max(0.1, fade(at: along))
    }

    /// How far a point (in this land's cells) lies on this land's side of the middle line, in
    /// cells across the edge: below 0 past it.
    func side(x: Double, y: Double) -> Double {
        let point = place(x: x, y: y)
        return point.inward - offset(at: point.along)
    }

    /// How much of the ground is the other land's `side` cells this side of the middle line, where
    /// the band's `width` either side of it: none `width` in, half on the line, all of it `width` past.
    static func share(at side: Double, width: Double) -> Double {
        let t = min(1, max(0, (width - side) / (2 * width)))
        return t * t * (3 - 2 * t)
    }

    /// How much of the ground is the other land's at a point (in this land's cells).
    func share(x: Double, y: Double) -> Double {
        let point = place(x: x, y: y)
        return Self.share(at: point.inward - offset(at: point.along), width: width(at: point.along))
    }

    /// Whether a cell (in this land's cells, inside it or just past the edge) is near enough the
    /// border, along the stretch the two share, for the band to reach it.
    func covers(_ cell: GridPoint) -> Bool {
        let point = place(x: Double(cell.col) + 0.5, y: Double(cell.row) + 0.5)
        return point.inward < Double(Self.depth) && point.along >= Double(span.lowerBound) && point.along < Double(span.upperBound + 1)
    }

    /// Whether a cell shows the other land's ground: where it's that land's share of the band, by
    /// patches of noise over the continent (`patch`), the same from either side.
    func showsOther(_ cell: GridPoint) -> Bool {
        let x = Double(cell.col) + 0.5, y = Double(cell.row) + 0.5
        let amount = share(x: x, y: y)
        guard amount > 0 else { return false }
        let noise = patch(x: x + Double(origin.col), y: y + Double(origin.row))
        return amount > (sign > 0 ? noise : 1 - noise)
    }

    /// Patchy noise over the continent's cells, 0.02...0.98: blobs a few cells across, a little
    /// ragged, spread out so the patches come in steadily across the band.
    func patch(x: Double, y: Double) -> Double {
        let raw = (Coast.value(x, y, every: 3.4, seed: 0x9A1) + Coast.value(x, y, every: 1.5, seed: 0x9A2) * 0.5) / 1.5
        return min(0.98, max(0.02, 0.5 + (raw - 0.5) * 1.8))
    }
}
