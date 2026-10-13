import Foundation

/// Where two lands meet: not the straight line between their rectangles but a line wandering
/// either side of it, so each land's ground comes over onto the other's in bays and tongues, and
/// the lands are shapes of their own (as RuneScape's regions run into each other). Only where
/// it's drawn: what's on each land, and whose it is, still stops at the straight line.
///
/// Worked out in the continent's cells, so both lands draw the same line: each from its own side
/// (`sign`), its ground past the line the other land's (`WorldScene.makeGround`), on the minimap
/// and the world map too (`WorldMap.foreign`). Not beside a town, whose walls stand on the border
/// (`Continent.coast(of:)`). `tools/world_layout.py --preview` draws the same lines (keep in step).
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
    /// Where this land's first cell along the edge lies on the continent, and where the border
    /// lies across it (the column of an east or west border, the row of a north or south one).
    let start: Int
    let line: Int
    /// 1 where this land is the first of the two by id, else -1: the line's offset is into the
    /// first land, so the second sees it turned round.
    let sign: Double

    /// The furthest the line wanders either side of the border, in cells.
    static let reach: Double = 16
    /// Over how many cells at either end of the stretch they share it comes back to the border,
    /// to meet the line round the next land (or the coast) at the corner.
    static let taper: Double = 16
    /// The waves it wanders in: how many cells apart their crests are, the noise's seed, its weight.
    static let waves: [(every: Double, seed: UInt64, weight: Double)] = [(52, 0x5EA, 1), (18, 0x5EB, 0.5), (7, 0x5EC, 0.18)]

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

    /// How far into this land (+) or the other (-) the line lies at `along` (continuous, in this
    /// land's cells along the edge).
    func offset(at along: Double) -> Double {
        let low = Double(span.lowerBound), high = Double(span.upperBound + 1)
        let end = min(along - low, high - along)
        guard end > 0 else { return 0 }
        let t = min(1, end / Self.taper)
        let world = along + Double(start)
        var wave = 0.0, total = 0.0
        for octave in Self.waves {
            wave += Coast.value(world, Double(line), every: octave.every, seed: octave.seed) * octave.weight
            total += octave.weight
        }
        return sign * (wave / total * 2 - 1) * Self.reach * t * t * (3 - 2 * t)
    }

    /// How far a point (in this land's cells) lies on this land's side of the line, in cells across
    /// the edge: below 0 past it, where the land next door's ground shows.
    func side(x: Double, y: Double) -> Double {
        let point = place(x: x, y: y)
        return point.inward - offset(at: point.along)
    }

    /// `side(x:y:)` over one cell, quicker, for drawing it a pixel at a time: the line's offset
    /// worked out every eighth of the cell along the edge and straight between (it bends far more
    /// slowly). Takes a point in the cell, -0.5...0.5 from its middle (x east, y north).
    func side(across cell: GridPoint) -> (Double, Double) -> Double {
        let low = place(x: Double(cell.col), y: Double(cell.row)).along
        let steps = 8
        let offsets = (0...steps).map { offset(at: low + Double($0) / Double(steps)) }
        let seam = self
        return { x, y in
            let point = seam.place(x: Double(cell.col) + 0.5 + x, y: Double(cell.row) + 0.5 + y)
            let t = min(Double(steps), max(0, (point.along - low) * Double(steps)))
            let step = min(steps - 1, Int(t))
            return point.inward - (offsets[step] + (offsets[step + 1] - offsets[step]) * (t - Double(step)))
        }
    }

    /// How far a cell lies on this land's side of the line, at the least and the most (the line
    /// changes slowly, so its ends and middle along the edge are enough): both below 0 for a cell
    /// all past it, both above for one all this side. Nil far enough in that the line never reaches.
    func sides(of cell: GridPoint) -> (low: Double, high: Double)? {
        let corner = place(x: Double(cell.col), y: Double(cell.row))
        let far = place(x: Double(cell.col + 1), y: Double(cell.row + 1))
        let inward = (low: min(corner.inward, far.inward), high: max(corner.inward, far.inward))
        guard inward.low < Self.reach + 1 else { return nil }
        let along = min(corner.along, far.along)
        guard along + 1 > Double(span.lowerBound), along < Double(span.upperBound + 1) else { return nil }
        let offsets = [along, along + 0.5, along + 1].map { offset(at: $0) }
        return (inward.low - offsets.max()!, inward.high - offsets.min()!)
    }
}
